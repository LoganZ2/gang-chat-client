#ifndef FLUTTER_SCREEN_AUDIO_CAPTURE_HXX
#define FLUTTER_SCREEN_AUDIO_CAPTURE_HXX

#include <memory>
#include <string>

#include "libwebrtc.h"

namespace flutter_webrtc_plugin {

class ScreenAudioCapture {
 public:
  virtual ~ScreenAudioCapture() = default;
  virtual void Stop() = 0;
};

std::shared_ptr<ScreenAudioCapture> StartScreenAudioCapture(
    libwebrtc::scoped_refptr<libwebrtc::RTCAudioSource> source,
    std::string* error);

}  // namespace flutter_webrtc_plugin

#endif  // FLUTTER_SCREEN_AUDIO_CAPTURE_HXX
