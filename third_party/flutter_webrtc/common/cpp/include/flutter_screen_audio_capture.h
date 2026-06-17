#ifndef FLUTTER_SCREEN_AUDIO_CAPTURE_HXX
#define FLUTTER_SCREEN_AUDIO_CAPTURE_HXX

#include <memory>

#include "rtc_audio_source.h"

namespace flutter_webrtc_plugin {

#if defined(_WIN32)

class ScreenAudioCapture {
 public:
  explicit ScreenAudioCapture(
      libwebrtc::scoped_refptr<libwebrtc::RTCAudioSource> audio_source);
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
