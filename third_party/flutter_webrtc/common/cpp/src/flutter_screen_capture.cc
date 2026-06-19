#include "flutter_screen_capture.h"

#if defined(_WIN32)
#define FLUTTER_WEBRTC_ENABLE_UNSAFE_WINDOWS_SCREEN_AUDIO 0

#if FLUTTER_WEBRTC_ENABLE_UNSAFE_WINDOWS_SCREEN_AUDIO
#include "flutter_screen_audio_capture.h"
#endif

#include <windows.h>

#include <cstdint>
#include <iostream>
#include <memory>
#endif

namespace flutter_webrtc_plugin {

namespace {

bool WantsScreenAudio(const EncodableMap& constraints) {
  auto it = constraints.find(EncodableValue("audio"));
  if (it == constraints.end()) {
    return false;
  }
  if (TypeIs<bool>(it->second)) {
    return GetValue<bool>(it->second);
  }
  return TypeIs<EncodableMap>(it->second);
}

#if defined(_WIN32)
#if FLUTTER_WEBRTC_ENABLE_UNSAFE_WINDOWS_SCREEN_AUDIO
constexpr int kScreenAudioSampleRate = 48000;
constexpr int kScreenAudioChannels = 2;

bool ResolveWindowProcessId(const std::string& source_id,
                            DWORD* process_id) {
  if (process_id == nullptr || source_id.empty()) {
    return false;
  }

  try {
    size_t parsed = 0;
    std::uint64_t value = std::stoull(source_id, &parsed, 0);
    if (parsed != source_id.size() || value == 0) {
      return false;
    }
    HWND window = reinterpret_cast<HWND>(static_cast<std::uintptr_t>(value));
    if (!IsWindow(window)) {
      return false;
    }
    DWORD window_process_id = 0;
    GetWindowThreadProcessId(window, &window_process_id);
    if (window_process_id == 0) {
      return false;
    }
    *process_id = window_process_id;
    return true;
  } catch (...) {
    return false;
  }
}
#endif  // FLUTTER_WEBRTC_ENABLE_UNSAFE_WINDOWS_SCREEN_AUDIO
#endif

}  // namespace

FlutterScreenCapture::FlutterScreenCapture(FlutterWebRTCBase* base)
    : base_(base) {}

bool FlutterScreenCapture::BuildDesktopSourcesList(const EncodableList& types,
                                                   bool force_reload) {
  size_t size = types.size();
  sources_.clear();
  for (size_t i = 0; i < size; i++) {
    std::string type_str = GetValue<std::string>(types[i]);
    DesktopType desktop_type = DesktopType::kScreen;
    if (type_str == "screen") {
      desktop_type = DesktopType::kScreen;
    } else if (type_str == "window") {
      desktop_type = DesktopType::kWindow;
    } else {
      // std::cout << "Unknown type " << type_str << std::endl;
      return false;
    }
    scoped_refptr<RTCDesktopMediaList> source_list;
    auto it = medialist_.find(desktop_type);
    if (it != medialist_.end()) {
      source_list = (*it).second;
    } else {
      source_list = base_->desktop_device_->GetDesktopMediaList(desktop_type);
      source_list->RegisterMediaListObserver(this);
      medialist_[desktop_type] = source_list;
    }
    source_list->UpdateSourceList(force_reload);
    int count = source_list->GetSourceCount();
    for (int j = 0; j < count; j++) {
      sources_.push_back(source_list->GetSource(j));
    }
  }
  return true;
}

void FlutterScreenCapture::GetDesktopSources(
    const EncodableList& types,
    std::unique_ptr<MethodResultProxy> result) {
  if (!BuildDesktopSourcesList(types, true)) {
    result->Error("Bad Arguments", "Failed to get desktop sources");
    return;
  }

  EncodableList sources;
  for (auto source : sources_) {
    EncodableMap info;
    info[EncodableValue("id")] = EncodableValue(source->id().std_string());
    info[EncodableValue("name")] = EncodableValue(source->name().std_string());
    info[EncodableValue("type")] =
        EncodableValue(source->type() == kWindow ? "window" : "screen");
    // TODO "thumbnailSize"
    info[EncodableValue("thumbnailSize")] = EncodableMap{
        {EncodableValue("width"), EncodableValue(0)},
        {EncodableValue("height"), EncodableValue(0)},
    };
    sources.push_back(EncodableValue(info));
  }

  std::cout << " sources: " << sources.size() << std::endl;
  auto map = EncodableMap();
  map[EncodableValue("sources")] = sources;
  result->Success(EncodableValue(map));
}

void FlutterScreenCapture::UpdateDesktopSources(
    const EncodableList& types,
    std::unique_ptr<MethodResultProxy> result) {
  if (!BuildDesktopSourcesList(types, false)) {
    result->Error("Bad Arguments", "Failed to update desktop sources");
    return;
  }
  auto map = EncodableMap();
  map[EncodableValue("result")] = true;
  result->Success(EncodableValue(map));
}

void FlutterScreenCapture::OnMediaSourceAdded(
    scoped_refptr<MediaSource> source) {
  std::cout << " OnMediaSourceAdded: " << source->id().std_string()
            << std::endl;

  EncodableMap info;
  info[EncodableValue("event")] = "desktopSourceAdded";
  info[EncodableValue("id")] = EncodableValue(source->id().std_string());
  info[EncodableValue("name")] = EncodableValue(source->name().std_string());
  info[EncodableValue("type")] =
      EncodableValue(source->type() == kWindow ? "window" : "screen");
  // TODO "thumbnailSize"
  info[EncodableValue("thumbnailSize")] = EncodableMap{
      {EncodableValue("width"), EncodableValue(0)},
      {EncodableValue("height"), EncodableValue(0)},
  };
  base_->event_channel()->Success(EncodableValue(info));
}

void FlutterScreenCapture::OnMediaSourceRemoved(
    scoped_refptr<MediaSource> source) {
  std::cout << " OnMediaSourceRemoved: " << source->id().std_string()
            << std::endl;

  EncodableMap info;
  info[EncodableValue("event")] = "desktopSourceRemoved";
  info[EncodableValue("id")] = EncodableValue(source->id().std_string());
  base_->event_channel()->Success(EncodableValue(info));
}

void FlutterScreenCapture::OnMediaSourceNameChanged(
    scoped_refptr<MediaSource> source) {
  std::cout << " OnMediaSourceNameChanged: " << source->id().std_string()
            << std::endl;

  EncodableMap info;
  info[EncodableValue("event")] = "desktopSourceNameChanged";
  info[EncodableValue("id")] = EncodableValue(source->id().std_string());
  info[EncodableValue("name")] = EncodableValue(source->name().std_string());
  base_->event_channel()->Success(EncodableValue(info));
}

void FlutterScreenCapture::OnMediaSourceThumbnailChanged(
    scoped_refptr<MediaSource> source) {
  std::cout << " OnMediaSourceThumbnailChanged: " << source->id().std_string()
            << std::endl;

  EncodableMap info;
  info[EncodableValue("event")] = "desktopSourceThumbnailChanged";
  info[EncodableValue("id")] = EncodableValue(source->id().std_string());
  info[EncodableValue("thumbnail")] =
      EncodableValue(source->thumbnail().std_vector());
  base_->event_channel()->Success(EncodableValue(info));
}

void FlutterScreenCapture::OnStart(scoped_refptr<RTCDesktopCapturer> capturer) {
  // std::cout << " OnStart: " << capturer->source()->id().std_string()
  //          << std::endl;
}

void FlutterScreenCapture::OnPaused(
    scoped_refptr<RTCDesktopCapturer> capturer) {
  // std::cout << " OnPaused: " << capturer->source()->id().std_string()
  //          << std::endl;
}

void FlutterScreenCapture::OnStop(scoped_refptr<RTCDesktopCapturer> capturer) {
  // std::cout << " OnStop: " << capturer->source()->id().std_string()
  //          << std::endl;
}

void FlutterScreenCapture::OnError(scoped_refptr<RTCDesktopCapturer> capturer) {
  // std::cout << " OnError: " << capturer->source()->id().std_string()
  //          << std::endl;
}

void FlutterScreenCapture::GetDesktopSourceThumbnail(
    std::string source_id,
    int width,
    int height,
    std::unique_ptr<MethodResultProxy> result) {
  scoped_refptr<MediaSource> source;
  for (auto src : sources_) {
    if (src->id().std_string() == source_id) {
      source = src;
    }
  }
  if (source.get() == nullptr) {
    result->Error("Bad Arguments", "Failed to get desktop source thumbnail");
    return;
  }
  std::cout << " GetDesktopSourceThumbnail: " << source->id().std_string()
            << std::endl;
  source->UpdateThumbnail();
  result->Success(EncodableValue(source->thumbnail().std_vector()));
}

void FlutterScreenCapture::GetDisplayMedia(
    const EncodableMap& constraints,
    std::unique_ptr<MethodResultProxy> result) {
  std::string source_id = "0";
  // DesktopType source_type = kScreen;
  double fps = 30.0;

  const EncodableMap video = findMap(constraints, "video");
  if (video != EncodableMap()) {
    const EncodableMap deviceId = findMap(video, "deviceId");
    if (deviceId != EncodableMap()) {
      source_id = findString(deviceId, "exact");
      if (source_id.empty()) {
        result->Error("Bad Arguments", "Incorrect video->deviceId->exact");
        return;
      }
      if (source_id != "0") {
        // source_type = DesktopType::kWindow;
      }
    }
    const EncodableMap mandatory = findMap(video, "mandatory");
    if (mandatory != EncodableMap()) {
      double frameRate = findDouble(mandatory, "frameRate");
      if (frameRate != 0.0) {
        fps = frameRate;
      }
    }
  }

  std::string uuid = base_->GenerateUUID();

  scoped_refptr<RTCMediaStream> stream =
      base_->factory_->CreateStream(uuid.c_str());

  EncodableMap params;
  params[EncodableValue("streamId")] = EncodableValue(uuid);

  // VIDEO

  EncodableMap video_constraints;
  auto it = constraints.find(EncodableValue("video"));
  if (it != constraints.end() && TypeIs<EncodableMap>(it->second)) {
    video_constraints = GetValue<EncodableMap>(it->second);
  }

  scoped_refptr<MediaSource> source;
  for (auto src : sources_) {
    if (src->id().std_string() == source_id) {
      source = src;
    }
  }

  if (!source.get()) {
    result->Error("Bad Arguments", "source not found!");
    return;
  }

  scoped_refptr<RTCDesktopCapturer> desktop_capturer =
      base_->desktop_device_->CreateDesktopCapturer(source);

  if (!desktop_capturer.get()) {
    result->Error("Bad Arguments", "CreateDesktopCapturer failed!");
    return;
  }

  desktop_capturer->RegisterDesktopCapturerObserver(this);

  const char* video_source_label = "screen_capture_input";

  scoped_refptr<RTCVideoSource> video_source =
      base_->factory_->CreateDesktopSource(
          desktop_capturer, video_source_label,
          base_->ParseMediaConstraints(video_constraints));

  // TODO: RTCVideoSource -> RTCVideoTrack

  scoped_refptr<RTCVideoTrack> track =
      base_->factory_->CreateVideoTrack(video_source, uuid.c_str());

  EncodableList videoTracks;
  EncodableMap info;
  info[EncodableValue("id")] = EncodableValue(track->id().std_string());
  info[EncodableValue("label")] = EncodableValue(track->id().std_string());
  info[EncodableValue("kind")] = EncodableValue(track->kind().std_string());
  info[EncodableValue("enabled")] = EncodableValue(track->enabled());
  videoTracks.push_back(EncodableValue(info));
  params[EncodableValue("videoTracks")] = EncodableValue(videoTracks);

  // AUDIO

  EncodableList audioTracks;
#if defined(_WIN32)
#if FLUTTER_WEBRTC_ENABLE_UNSAFE_WINDOWS_SCREEN_AUDIO
  if (WantsScreenAudio(constraints)) {
    RTCAudioOptions audio_options;
    audio_options.echo_cancellation = false;
    audio_options.auto_gain_control = false;
    audio_options.noise_suppression = false;
    audio_options.highpass_filter = false;

    scoped_refptr<RTCAudioSource> audio_source =
        base_->factory_->CreateAudioSource(
            "screen_capture_audio", RTCAudioSource::SourceType::kCustom,
            audio_options);
    scoped_refptr<RTCAudioTrack> audio_track;
    std::shared_ptr<ScreenAudioCapture> screen_audio_capture;

    if (audio_source.get() != nullptr) {
      DWORD target_process_id = GetCurrentProcessId();
      bool include_process_tree = false;
      DWORD window_process_id = 0;
      if (source->type() == kWindow &&
          ResolveWindowProcessId(source->id().std_string(),
                                 &window_process_id)) {
        target_process_id = window_process_id;
        include_process_tree = true;
      }

      std::string audio_track_id = base_->GenerateUUID();
      audio_track =
          base_->factory_->CreateAudioTrack(audio_source, audio_track_id.c_str());
      screen_audio_capture =
          std::make_shared<ScreenAudioCapture>(audio_source);

      if (audio_track.get() != nullptr &&
          screen_audio_capture->Start(target_process_id,
                                      include_process_tree)) {
        EncodableMap audio_info;
        audio_info[EncodableValue("id")] =
            EncodableValue(audio_track->id().std_string());
        audio_info[EncodableValue("label")] =
            EncodableValue(audio_track->id().std_string());
        audio_info[EncodableValue("kind")] =
            EncodableValue(audio_track->kind().std_string());
        audio_info[EncodableValue("enabled")] =
            EncodableValue(audio_track->enabled());

        EncodableMap audio_settings;
        audio_settings[EncodableValue("deviceId")] =
            EncodableValue("screen_audio");
        audio_settings[EncodableValue("kind")] =
            EncodableValue("audiooutput");
        audio_settings[EncodableValue("autoGainControl")] =
            EncodableValue(false);
        audio_settings[EncodableValue("echoCancellation")] =
            EncodableValue(false);
        audio_settings[EncodableValue("noiseSuppression")] =
            EncodableValue(false);
        audio_settings[EncodableValue("channelCount")] =
            EncodableValue(kScreenAudioChannels);
        audio_settings[EncodableValue("sampleRate")] =
            EncodableValue(kScreenAudioSampleRate);
        audio_info[EncodableValue("settings")] =
            EncodableValue(audio_settings);

        audioTracks.push_back(EncodableValue(audio_info));
        stream->AddTrack(audio_track);
        base_->local_tracks_[audio_track->id().std_string()] = audio_track;
        base_->RegisterLocalTrackCleanup(
            audio_track->id().std_string(),
            [screen_audio_capture]() { screen_audio_capture->Stop(); });
      } else {
        std::cerr << "Screen audio capture is unavailable; continuing with "
                     "video-only screen share."
                  << std::endl;
      }
    }
  }
#else
  if (WantsScreenAudio(constraints)) {
    std::cerr
        << "Windows screen audio capture is disabled because the current "
           "custom RTCAudioSource path can race WebRTC's audio send stream; "
           "continuing with video-only screen share."
        << std::endl;
  }
#endif
#endif
  params[EncodableValue("audioTracks")] = EncodableValue(audioTracks);

  stream->AddTrack(track);

  base_->local_tracks_[track->id().std_string()] = track;

  base_->local_streams_[uuid] = stream;

  desktop_capturer->Start(uint32_t(fps));

  result->Success(EncodableValue(params));
}

}  // namespace flutter_webrtc_plugin
