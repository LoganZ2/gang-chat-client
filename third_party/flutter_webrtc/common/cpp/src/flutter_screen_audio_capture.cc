#include "flutter_screen_audio_capture.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <future>
#include <string>
#include <thread>
#include <vector>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#endif

namespace flutter_webrtc_plugin {
namespace {

#if defined(_WIN32)

constexpr REFERENCE_TIME kRequestedBufferDuration = 1000000;  // 100 ms.
constexpr int kStartupTimeoutMs = 3000;

template <typename T>
void SafeRelease(T*& value) {
  if (value) {
    value->Release();
    value = nullptr;
  }
}

class ScopedComInitialization {
 public:
  ScopedComInitialization() {
    const HRESULT result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    initialized_here_ = SUCCEEDED(result);
    ok_ = initialized_here_ || result == RPC_E_CHANGED_MODE;
  }

  ~ScopedComInitialization() {
    if (initialized_here_) {
      CoUninitialize();
    }
  }

  bool ok() const { return ok_; }

 private:
  bool ok_ = false;
  bool initialized_here_ = false;
};

std::string HResultMessage(const char* operation, HRESULT hr) {
  char buffer[96] = {0};
  std::snprintf(buffer, sizeof(buffer), "%s failed: 0x%08lx", operation,
                static_cast<unsigned long>(hr));
  return std::string(buffer);
}

bool IsWaveExtensibleSubFormat(const WAVEFORMATEX* format, uint32_t data1) {
  if (!format || format->wFormatTag != WAVE_FORMAT_EXTENSIBLE ||
      format->cbSize <
          sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)) {
    return false;
  }
  const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
  const GUID& guid = ext->SubFormat;
  static constexpr uint8_t kTail[8] = {0x80, 0x00, 0x00, 0xaa,
                                       0x00, 0x38, 0x9b, 0x71};
  return guid.Data1 == data1 && guid.Data2 == 0 && guid.Data3 == 0x0010 &&
         std::memcmp(guid.Data4, kTail, sizeof(kTail)) == 0;
}

bool IsFloatFormat(const WAVEFORMATEX* format) {
  return format &&
         (format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
          IsWaveExtensibleSubFormat(format, WAVE_FORMAT_IEEE_FLOAT));
}

bool IsPcmFormat(const WAVEFORMATEX* format) {
  return format && (format->wFormatTag == WAVE_FORMAT_PCM ||
                    IsWaveExtensibleSubFormat(format, WAVE_FORMAT_PCM));
}

int16_t FloatToS16(float value) {
  if (value > 1.0f) {
    value = 1.0f;
  } else if (value < -1.0f) {
    value = -1.0f;
  }
  return static_cast<int16_t>(value * 32767.0f);
}

void ConvertWasapiBufferToS16(const BYTE* data,
                              UINT32 frames,
                              DWORD flags,
                              const WAVEFORMATEX* format,
                              std::vector<int16_t>& output) {
  const size_t channels =
      format && format->nChannels > 0 ? format->nChannels : 1;
  const size_t samples = static_cast<size_t>(frames) * channels;
  output.assign(samples, 0);
  if (samples == 0 || !format || data == nullptr ||
      (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0) {
    return;
  }

  const uint16_t bits_per_sample = format->wBitsPerSample;
  const bool is_float = IsFloatFormat(format);
  const bool is_pcm = IsPcmFormat(format);
  if (is_float && bits_per_sample == 32) {
    const auto* input = reinterpret_cast<const float*>(data);
    for (size_t i = 0; i < samples; ++i) {
      output[i] = FloatToS16(input[i]);
    }
    return;
  }
  if (is_float && bits_per_sample == 64) {
    const auto* input = reinterpret_cast<const double*>(data);
    for (size_t i = 0; i < samples; ++i) {
      output[i] = FloatToS16(static_cast<float>(input[i]));
    }
    return;
  }
  if (!is_pcm) {
    return;
  }

  const auto* bytes = reinterpret_cast<const uint8_t*>(data);
  switch (bits_per_sample) {
    case 8:
      for (size_t i = 0; i < samples; ++i) {
        output[i] = static_cast<int16_t>((static_cast<int>(bytes[i]) - 128)
                                         << 8);
      }
      break;
    case 16:
      for (size_t i = 0; i < samples; ++i) {
        int16_t sample = 0;
        std::memcpy(&sample, bytes + i * 2, sizeof(sample));
        output[i] = sample;
      }
      break;
    case 24:
      for (size_t i = 0; i < samples; ++i) {
        const uint8_t* sample_bytes = bytes + i * 3;
        int32_t sample = sample_bytes[0] | (sample_bytes[1] << 8) |
                         (sample_bytes[2] << 16);
        if ((sample & 0x00800000) != 0) {
          sample |= ~0x00ffffff;
        }
        output[i] = static_cast<int16_t>(sample / 256);
      }
      break;
    case 32:
      for (size_t i = 0; i < samples; ++i) {
        int32_t sample = 0;
        std::memcpy(&sample, bytes + i * 4, sizeof(sample));
        output[i] = static_cast<int16_t>(sample / 65536);
      }
      break;
    default:
      break;
  }
}

class WindowsLoopbackScreenAudioCapture : public ScreenAudioCapture {
 public:
  explicit WindowsLoopbackScreenAudioCapture(
      libwebrtc::scoped_refptr<libwebrtc::RTCAudioSource> source)
      : source_(source) {}

  ~WindowsLoopbackScreenAudioCapture() override { Stop(); }

  bool Start(std::string* error) {
    if (!source_.get()) {
      if (error) {
        *error = "audio source is null";
      }
      return false;
    }

    running_.store(true, std::memory_order_release);
    std::promise<std::string> started;
    auto ready = started.get_future();
    thread_ = std::thread([this, promise = std::move(started)]() mutable {
      Run(std::move(promise));
    });

    if (ready.wait_for(std::chrono::milliseconds(kStartupTimeoutMs)) !=
        std::future_status::ready) {
      if (error) {
        *error = "WASAPI loopback startup timed out";
      }
      Stop();
      return false;
    }

    const std::string message = ready.get();
    if (!message.empty()) {
      if (error) {
        *error = message;
      }
      Stop();
      return false;
    }
    return true;
  }

  void Stop() override {
    running_.store(false, std::memory_order_release);
    if (thread_.joinable() &&
        thread_.get_id() != std::this_thread::get_id()) {
      thread_.join();
    }
    source_ = nullptr;
  }

 private:
  void Run(std::promise<std::string> started) {
    bool signaled = false;
    const auto signal = [&](const std::string& message) {
      if (!signaled) {
        started.set_value(message);
        signaled = true;
      }
    };

    ScopedComInitialization com;
    if (!com.ok()) {
      signal("CoInitializeEx failed for WASAPI loopback");
      return;
    }

    IMMDeviceEnumerator* enumerator = nullptr;
    IMMDevice* device = nullptr;
    IAudioClient* audio_client = nullptr;
    IAudioCaptureClient* capture_client = nullptr;
    WAVEFORMATEX* mix_format = nullptr;

    auto cleanup = [&]() {
      if (audio_client) {
        audio_client->Stop();
      }
      if (mix_format) {
        CoTaskMemFree(mix_format);
        mix_format = nullptr;
      }
      SafeRelease(capture_client);
      SafeRelease(audio_client);
      SafeRelease(device);
      SafeRelease(enumerator);
    };

    HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                  CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
    if (FAILED(hr)) {
      signal(HResultMessage("CoCreateInstance(MMDeviceEnumerator)", hr));
      cleanup();
      return;
    }

    hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
    if (FAILED(hr)) {
      signal(HResultMessage("GetDefaultAudioEndpoint(eRender)", hr));
      cleanup();
      return;
    }

    hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                          reinterpret_cast<void**>(&audio_client));
    if (FAILED(hr)) {
      signal(HResultMessage("IMMDevice::Activate(IAudioClient)", hr));
      cleanup();
      return;
    }

    hr = audio_client->GetMixFormat(&mix_format);
    if (FAILED(hr) || !mix_format) {
      signal(FAILED(hr) ? HResultMessage("IAudioClient::GetMixFormat", hr)
                        : "IAudioClient::GetMixFormat returned null");
      cleanup();
      return;
    }

    hr = audio_client->Initialize(
        AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
        kRequestedBufferDuration, 0, mix_format, nullptr);
    if (FAILED(hr)) {
      signal(HResultMessage("IAudioClient::Initialize(loopback)", hr));
      cleanup();
      return;
    }

    hr = audio_client->GetService(IID_PPV_ARGS(&capture_client));
    if (FAILED(hr)) {
      signal(HResultMessage("IAudioClient::GetService(IAudioCaptureClient)",
                            hr));
      cleanup();
      return;
    }

    hr = audio_client->Start();
    if (FAILED(hr)) {
      signal(HResultMessage("IAudioClient::Start", hr));
      cleanup();
      return;
    }

    signal(std::string());
    CaptureLoop(capture_client, mix_format);
    cleanup();
  }

  void CaptureLoop(IAudioCaptureClient* capture_client,
                   const WAVEFORMATEX* format) {
    if (!capture_client || !format || !source_.get()) {
      return;
    }
    const int sample_rate = static_cast<int>(format->nSamplesPerSec);
    const size_t channels = format->nChannels > 0 ? format->nChannels : 1;
    std::vector<int16_t> pcm;

    while (running_.load(std::memory_order_acquire)) {
      UINT32 packet_length = 0;
      HRESULT hr = capture_client->GetNextPacketSize(&packet_length);
      if (FAILED(hr)) {
        break;
      }
      if (packet_length == 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
        continue;
      }

      while (packet_length != 0 &&
             running_.load(std::memory_order_acquire)) {
        BYTE* data = nullptr;
        UINT32 frames = 0;
        DWORD flags = 0;
        hr = capture_client->GetBuffer(&data, &frames, &flags, nullptr,
                                       nullptr);
        if (FAILED(hr)) {
          return;
        }

        ConvertWasapiBufferToS16(data, frames, flags, format, pcm);
        if (!pcm.empty() && source_.get()) {
          source_->CaptureFrame(pcm.data(), 16, sample_rate, channels, frames);
        }

        hr = capture_client->ReleaseBuffer(frames);
        if (FAILED(hr)) {
          return;
        }
        hr = capture_client->GetNextPacketSize(&packet_length);
        if (FAILED(hr)) {
          return;
        }
      }
    }
  }

 private:
  std::atomic<bool> running_{false};
  std::thread thread_;
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioSource> source_;
};

#endif  // defined(_WIN32)

}  // namespace

std::shared_ptr<ScreenAudioCapture> StartScreenAudioCapture(
    libwebrtc::scoped_refptr<libwebrtc::RTCAudioSource> source,
    std::string* error) {
#if defined(_WIN32)
  auto capture = std::make_shared<WindowsLoopbackScreenAudioCapture>(source);
  if (!capture->Start(error)) {
    return nullptr;
  }
  return capture;
#else
  (void)source;
  if (error) {
    *error = "screen audio capture is only implemented on Windows desktop";
  }
  return nullptr;
#endif
}

}  // namespace flutter_webrtc_plugin
