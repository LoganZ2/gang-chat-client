#include "flutter_screen_audio_capture.h"

#if defined(_WIN32)

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <propidl.h>
#include <windows.h>
#include <wrl/client.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <thread>
#include <utility>
#include <vector>

#if __has_include(<audioclientactivationparams.h>)
#include <audioclientactivationparams.h>
#else
typedef enum AUDIOCLIENT_ACTIVATION_TYPE {
  AUDIOCLIENT_ACTIVATION_TYPE_DEFAULT = 0,
  AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK = 1,
} AUDIOCLIENT_ACTIVATION_TYPE;

typedef enum PROCESS_LOOPBACK_MODE {
  PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE = 0,
  PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE = 1,
} PROCESS_LOOPBACK_MODE;

typedef struct AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS {
  DWORD TargetProcessId;
  PROCESS_LOOPBACK_MODE ProcessLoopbackMode;
} AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS;

typedef struct AUDIOCLIENT_ACTIVATION_PARAMS {
  AUDIOCLIENT_ACTIVATION_TYPE ActivationType;
  union {
    AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS ProcessLoopbackParams;
  };
} AUDIOCLIENT_ACTIVATION_PARAMS;
#endif

#ifndef VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK
#define VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK L"VAD\\Process_Loopback"
#endif

#ifndef AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM
#define AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM 0x80000000
#endif

namespace flutter_webrtc_plugin {
namespace {

constexpr int kBitsPerSample = 16;
constexpr int kSampleRate = 48000;
constexpr int kChannels = 2;
constexpr UINT32 kFramesPerWebRTCChunk = kSampleRate / 100;
constexpr DWORD kActivationTimeoutMs = 10000;

class ScopedHandle {
 public:
  ScopedHandle() = default;
  explicit ScopedHandle(HANDLE handle) : handle_(handle) {}
  ~ScopedHandle() { reset(); }

  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;

  HANDLE get() const { return handle_; }

  HANDLE release() {
    HANDLE handle = handle_;
    handle_ = nullptr;
    return handle;
  }

  void reset(HANDLE handle = nullptr) {
    if (handle_ != nullptr) {
      CloseHandle(handle_);
    }
    handle_ = handle;
  }

 private:
  HANDLE handle_ = nullptr;
};

class AudioActivationHandler
    : public IActivateAudioInterfaceCompletionHandler {
 public:
  explicit AudioActivationHandler(HANDLE completed_event)
      : completed_event_(completed_event) {}

  IFACEMETHODIMP QueryInterface(REFIID riid, void** object) override {
    if (object == nullptr) {
      return E_POINTER;
    }
    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(IActivateAudioInterfaceCompletionHandler)) {
      *object = static_cast<IActivateAudioInterfaceCompletionHandler*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  IFACEMETHODIMP_(ULONG) AddRef() override {
    return refs_.fetch_add(1, std::memory_order_relaxed) + 1;
  }

  IFACEMETHODIMP_(ULONG) Release() override {
    ULONG refs = refs_.fetch_sub(1, std::memory_order_acq_rel) - 1;
    if (refs == 0) {
      delete this;
    }
    return refs;
  }

  IFACEMETHODIMP ActivateCompleted(
      IActivateAudioInterfaceAsyncOperation* operation) override {
    activate_result_ = E_UNEXPECTED;
    HRESULT operation_hr = E_UNEXPECTED;
    Microsoft::WRL::ComPtr<IUnknown> audio_interface;

    HRESULT hr =
        operation->GetActivateResult(&operation_hr, &audio_interface);
    if (SUCCEEDED(hr)) {
      activate_result_ = operation_hr;
      if (SUCCEEDED(operation_hr) && audio_interface != nullptr) {
        activate_result_ = audio_interface.As(&audio_client_);
      }
    } else {
      activate_result_ = hr;
    }

    SetEvent(completed_event_);
    return S_OK;
  }

  HRESULT activate_result() const { return activate_result_; }

  Microsoft::WRL::ComPtr<IAudioClient> audio_client() const {
    return audio_client_;
  }

 private:
  std::atomic<ULONG> refs_{1};
  HANDLE completed_event_ = nullptr;
  HRESULT activate_result_ = E_UNEXPECTED;
  Microsoft::WRL::ComPtr<IAudioClient> audio_client_;
};

using ActivateAudioInterfaceAsyncFn = HRESULT(WINAPI*)(
    LPCWSTR,
    REFIID,
    PROPVARIANT*,
    IActivateAudioInterfaceCompletionHandler*,
    IActivateAudioInterfaceAsyncOperation**);

HRESULT ActivateProcessLoopbackAudioClient(
    DWORD target_process_id,
    bool include_process_tree,
    Microsoft::WRL::ComPtr<IAudioClient>* audio_client) {
  if (audio_client == nullptr) {
    return E_POINTER;
  }

  HMODULE mmdevapi = LoadLibraryW(L"Mmdevapi.dll");
  if (mmdevapi == nullptr) {
    return HRESULT_FROM_WIN32(GetLastError());
  }

  auto free_library = [&]() { FreeLibrary(mmdevapi); };
  auto activate_audio_interface_async =
      reinterpret_cast<ActivateAudioInterfaceAsyncFn>(
          GetProcAddress(mmdevapi, "ActivateAudioInterfaceAsync"));
  if (activate_audio_interface_async == nullptr) {
    HRESULT hr = HRESULT_FROM_WIN32(GetLastError());
    free_library();
    return hr;
  }

  ScopedHandle completed_event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  if (completed_event.get() == nullptr) {
    HRESULT hr = HRESULT_FROM_WIN32(GetLastError());
    free_library();
    return hr;
  }

  AUDIOCLIENT_ACTIVATION_PARAMS activation_params = {};
  activation_params.ActivationType =
      AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
  activation_params.ProcessLoopbackParams.TargetProcessId = target_process_id;
  activation_params.ProcessLoopbackParams.ProcessLoopbackMode =
      include_process_tree
          ? PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE
          : PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE;

  PROPVARIANT activate_params = {};
  activate_params.vt = VT_BLOB;
  activate_params.blob.cbSize = sizeof(activation_params);
  activate_params.blob.pBlobData =
      reinterpret_cast<BYTE*>(&activation_params);

  AudioActivationHandler* handler =
      new AudioActivationHandler(completed_event.get());
  Microsoft::WRL::ComPtr<IActivateAudioInterfaceAsyncOperation> async_op;
  HRESULT hr = activate_audio_interface_async(
      VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient),
      &activate_params, handler, &async_op);
  if (FAILED(hr)) {
    handler->Release();
    free_library();
    return hr;
  }

  DWORD wait_result =
      WaitForSingleObject(completed_event.get(), kActivationTimeoutMs);
  if (wait_result != WAIT_OBJECT_0) {
    // The system may still complete the async activation later. Keep the
    // handler, event, and module alive rather than risking a late callback into
    // freed memory on unsupported or unhealthy Windows audio stacks.
    completed_event.release();
    return wait_result == WAIT_TIMEOUT ? HRESULT_FROM_WIN32(WAIT_TIMEOUT)
                                       : HRESULT_FROM_WIN32(GetLastError());
  }

  hr = handler->activate_result();
  if (SUCCEEDED(hr)) {
    *audio_client = handler->audio_client();
  }
  handler->Release();
  free_library();
  return hr;
}

HRESULT ActivateDefaultRenderAudioClient(
    Microsoft::WRL::ComPtr<IAudioClient>* audio_client) {
  if (audio_client == nullptr) {
    return E_POINTER;
  }

  Microsoft::WRL::ComPtr<IMMDeviceEnumerator> device_enumerator;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL,
                                IID_PPV_ARGS(&device_enumerator));
  if (FAILED(hr)) {
    return hr;
  }

  Microsoft::WRL::ComPtr<IMMDevice> render_device;
  hr = device_enumerator->GetDefaultAudioEndpoint(eRender, eConsole,
                                                  &render_device);
  if (FAILED(hr)) {
    return hr;
  }

  return render_device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                 reinterpret_cast<void**>(
                                     audio_client->GetAddressOf()));
}

WAVEFORMATEX CreateCaptureFormat() {
  WAVEFORMATEX format = {};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = kChannels;
  format.nSamplesPerSec = kSampleRate;
  format.wBitsPerSample = kBitsPerSample;
  format.nBlockAlign =
      format.nChannels * format.wBitsPerSample / 8;
  format.nAvgBytesPerSec =
      format.nSamplesPerSec * format.nBlockAlign;
  format.cbSize = 0;
  return format;
}

class CustomSourceScreenAudioSink : public ScreenAudioFrameSink {
 public:
  explicit CustomSourceScreenAudioSink(
      libwebrtc::scoped_refptr<libwebrtc::RTCAudioSource> audio_source)
      : audio_source_(audio_source) {}

  void EnqueueAudioData(const void* audio_data,
                        int bits_per_sample,
                        int sample_rate,
                        size_t number_of_channels,
                        size_t number_of_frames) override {
    if (audio_source_ == nullptr || audio_data == nullptr ||
        number_of_frames == 0) {
      return;
    }
    audio_source_->CaptureFrame(audio_data, bits_per_sample, sample_rate,
                                number_of_channels, number_of_frames);
  }

 private:
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioSource> audio_source_;
};

}  // namespace

class ScreenAudioCapture::Impl {
 public:
  explicit Impl(std::shared_ptr<ScreenAudioFrameSink> sink)
      : sink_(std::move(sink)) {}

  ~Impl() { Stop(); }

  bool Start(unsigned long target_process_id, bool include_process_tree) {
    if (running_.load(std::memory_order_acquire)) {
      return true;
    }

    stop_event_.reset(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    started_event_.reset(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    sample_event_.reset(CreateEventW(nullptr, FALSE, FALSE, nullptr));
    if (stop_event_.get() == nullptr || started_event_.get() == nullptr ||
        sample_event_.get() == nullptr) {
      start_result_.store(HRESULT_FROM_WIN32(GetLastError()),
                          std::memory_order_release);
      return false;
    }

    start_result_.store(E_PENDING, std::memory_order_release);
    worker_ = std::thread(&Impl::Run, this,
                          static_cast<DWORD>(target_process_id),
                          include_process_tree);

    DWORD wait_result =
        WaitForSingleObject(started_event_.get(), kActivationTimeoutMs);
    if (wait_result != WAIT_OBJECT_0 ||
        FAILED(start_result_.load(std::memory_order_acquire))) {
      Stop();
      return false;
    }
    return true;
  }

  void Stop() {
    if (stop_event_.get() != nullptr) {
      SetEvent(stop_event_.get());
    }
    if (worker_.joinable()) {
      worker_.join();
    }
    running_.store(false, std::memory_order_release);
    audio_client_.Reset();
    audio_capture_client_.Reset();
    stop_event_.reset();
    started_event_.reset();
    sample_event_.reset();
  }

 private:
  void Run(DWORD target_process_id, bool include_process_tree) {
    HRESULT coinit_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    bool did_initialize_com = SUCCEEDED(coinit_hr);
    if (coinit_hr == RPC_E_CHANGED_MODE) {
      did_initialize_com = false;
      coinit_hr = S_OK;
    }

    start_result_.store(coinit_hr, std::memory_order_release);
    if (SUCCEEDED(start_result_.load(std::memory_order_acquire))) {
      start_result_.store(
          InitializeAudioClient(target_process_id, include_process_tree),
          std::memory_order_release);
    }
    if (SUCCEEDED(start_result_.load(std::memory_order_acquire))) {
      start_result_.store(audio_client_->Start(), std::memory_order_release);
    }

    HRESULT start_result = start_result_.load(std::memory_order_acquire);
    if (FAILED(start_result)) {
      std::cerr << "Failed to start screen audio capture: 0x" << std::hex
                << start_result << std::dec << std::endl;
      SetEvent(started_event_.get());
      if (did_initialize_com) {
        CoUninitialize();
      }
      return;
    }

    running_.store(true, std::memory_order_release);
    SetEvent(started_event_.get());
    CaptureLoop();
    audio_client_->Stop();
    audio_capture_client_.Reset();
    audio_client_.Reset();
    running_.store(false, std::memory_order_release);

    if (did_initialize_com) {
      CoUninitialize();
    }
  }

  HRESULT InitializeAudioClient(DWORD target_process_id,
                                bool include_process_tree) {
    process_loopback_result_.store(
        InitializeProcessLoopbackAudioClient(target_process_id,
                                             include_process_tree),
        std::memory_order_release);
    if (SUCCEEDED(process_loopback_result_.load(std::memory_order_acquire))) {
      return S_OK;
    }

    audio_client_.Reset();
    audio_capture_client_.Reset();

    // Process loopback is endpoint-independent but requires newer Windows
    // audio support. Fall back to classic system loopback so screen sharing can
    // still include sound on older or unhealthy process-loopback stacks.
    system_loopback_result_.store(InitializeSystemLoopbackAudioClient(),
                                  std::memory_order_release);
    return system_loopback_result_.load(std::memory_order_acquire);
  }

  HRESULT InitializeProcessLoopbackAudioClient(DWORD target_process_id,
                                               bool include_process_tree) {
    Microsoft::WRL::ComPtr<IAudioClient> audio_client;
    HRESULT hr = ActivateProcessLoopbackAudioClient(
        target_process_id, include_process_tree, &audio_client);
    if (FAILED(hr)) {
      return hr;
    }
    return InitializeAudioClientStream(audio_client);
  }

  HRESULT InitializeSystemLoopbackAudioClient() {
    Microsoft::WRL::ComPtr<IAudioClient> audio_client;
    HRESULT hr = ActivateDefaultRenderAudioClient(&audio_client);
    if (FAILED(hr)) {
      return hr;
    }
    return InitializeAudioClientStream(audio_client);
  }

  HRESULT InitializeAudioClientStream(
      Microsoft::WRL::ComPtr<IAudioClient> audio_client) {
    if (audio_client == nullptr) {
      return E_POINTER;
    }

    capture_format_ = CreateCaptureFormat();
    HRESULT hr = audio_client->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
            AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
        0, 0, &capture_format_, nullptr);
    if (FAILED(hr)) {
      return hr;
    }

    hr = audio_client->GetService(
        __uuidof(IAudioCaptureClient),
        reinterpret_cast<void**>(audio_capture_client_.GetAddressOf()));
    if (FAILED(hr)) {
      return hr;
    }

    hr = audio_client->SetEventHandle(sample_event_.get());
    if (SUCCEEDED(hr)) {
      audio_client_ = audio_client;
    } else {
      audio_capture_client_.Reset();
    }
    return hr;
  }

  void CaptureLoop() {
    HANDLE events[] = {stop_event_.get(), sample_event_.get()};
    while (true) {
      DWORD wait_result = WaitForMultipleObjects(2, events, FALSE, INFINITE);
      if (wait_result == WAIT_OBJECT_0) {
        return;
      }
      if (wait_result != WAIT_OBJECT_0 + 1) {
        return;
      }
      if (FAILED(ProcessPendingPackets())) {
        return;
      }
    }
  }

  HRESULT ProcessPendingPackets() {
    UINT32 frames_available = 0;
    HRESULT hr = audio_capture_client_->GetNextPacketSize(&frames_available);
    while (SUCCEEDED(hr) && frames_available > 0) {
      BYTE* data = nullptr;
      DWORD flags = 0;
      UINT64 device_position = 0;
      UINT64 qpc_position = 0;
      hr = audio_capture_client_->GetBuffer(
          &data, &frames_available, &flags, &device_position, &qpc_position);
      if (FAILED(hr)) {
        return hr;
      }

      if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0) {
        PushSilentFrames(frames_available);
      } else if (data != nullptr) {
        PushFrames(data, frames_available);
      }

      hr = audio_capture_client_->ReleaseBuffer(frames_available);
      if (FAILED(hr)) {
        return hr;
      }
      hr = audio_capture_client_->GetNextPacketSize(&frames_available);
    }
    return hr;
  }

  void PushFrames(const BYTE* data, UINT32 frames) {
    if (sink_ == nullptr) {
      return;
    }
    UINT32 offset = 0;
    while (offset < frames) {
      UINT32 chunk_frames =
          (frames - offset) > kFramesPerWebRTCChunk
              ? kFramesPerWebRTCChunk
              : (frames - offset);
      const BYTE* chunk =
          data + offset * capture_format_.nBlockAlign;
      sink_->EnqueueAudioData(chunk, kBitsPerSample, kSampleRate, kChannels,
                              chunk_frames);
      offset += chunk_frames;
    }
  }

  void PushSilentFrames(UINT32 frames) {
    if (sink_ == nullptr) {
      return;
    }
    const size_t sample_count =
        static_cast<size_t>(kFramesPerWebRTCChunk) * kChannels;
    std::vector<int16_t> silence(sample_count, 0);
    UINT32 offset = 0;
    while (offset < frames) {
      UINT32 chunk_frames =
          (frames - offset) > kFramesPerWebRTCChunk
              ? kFramesPerWebRTCChunk
              : (frames - offset);
      sink_->EnqueueAudioData(silence.data(), kBitsPerSample, kSampleRate,
                              kChannels, chunk_frames);
      offset += chunk_frames;
    }
  }

  std::shared_ptr<ScreenAudioFrameSink> sink_;
  std::thread worker_;
  std::atomic<bool> running_{false};
  std::atomic<HRESULT> start_result_{E_PENDING};
  std::atomic<HRESULT> process_loopback_result_{S_OK};
  std::atomic<HRESULT> system_loopback_result_{S_OK};
  ScopedHandle stop_event_;
  ScopedHandle started_event_;
  ScopedHandle sample_event_;
  WAVEFORMATEX capture_format_{};
  Microsoft::WRL::ComPtr<IAudioClient> audio_client_;
  Microsoft::WRL::ComPtr<IAudioCaptureClient> audio_capture_client_;
};

std::shared_ptr<ScreenAudioFrameSink> CreateScreenAudioCustomSourceSink(
    libwebrtc::scoped_refptr<libwebrtc::RTCAudioSource> audio_source) {
  if (audio_source == nullptr) {
    return nullptr;
  }
  return std::make_shared<CustomSourceScreenAudioSink>(audio_source);
}

ScreenAudioCapture::ScreenAudioCapture(
    std::shared_ptr<ScreenAudioFrameSink> sink)
    : impl_(std::make_unique<Impl>(std::move(sink))) {}

ScreenAudioCapture::~ScreenAudioCapture() = default;

bool ScreenAudioCapture::Start(unsigned long target_process_id,
                               bool include_process_tree) {
  return impl_->Start(target_process_id, include_process_tree);
}

void ScreenAudioCapture::Stop() {
  impl_->Stop();
}

}  // namespace flutter_webrtc_plugin

#endif  // defined(_WIN32)
