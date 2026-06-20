#ifndef FLUTTER_SCREEN_AUDIO_CAPTURE_HXX
#define FLUTTER_SCREEN_AUDIO_CAPTURE_HXX

#include <cstddef>
#include <memory>

#include "rtc_audio_source.h"

namespace flutter_webrtc_plugin {

#if defined(_WIN32)

class ScreenAudioFrameSink {
 public:
  virtual ~ScreenAudioFrameSink() = default;

  virtual void EnqueueAudioData(const void* audio_data,
                                int bits_per_sample,
                                int sample_rate,
                                size_t number_of_channels,
                                size_t number_of_frames) = 0;
};

std::shared_ptr<ScreenAudioFrameSink> CreateScreenAudioCustomSourceSink(
    libwebrtc::scoped_refptr<libwebrtc::RTCAudioSource> audio_source);

class ScreenAudioCapture {
 public:
  explicit ScreenAudioCapture(std::shared_ptr<ScreenAudioFrameSink> sink);
  ~ScreenAudioCapture();

  ScreenAudioCapture(const ScreenAudioCapture&) = delete;
  ScreenAudioCapture& operator=(const ScreenAudioCapture&) = delete;

  bool Start(unsigned long target_process_id, bool include_process_tree);
  void Stop();

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif

}  // namespace flutter_webrtc_plugin

#endif  // FLUTTER_SCREEN_AUDIO_CAPTURE_HXX
