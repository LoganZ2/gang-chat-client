// Copyright 2024 LiveKit, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "include/livekit_client/live_kit_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <flutter_common.h>
#include <flutter_webrtc.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>

#include <algorithm>
#include <atomic>
#include <iomanip>
#include <limits>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <unordered_map>
#include <vector>

#include "audio_visualizer.h"
#include "task_runner_windows.h"

namespace livekit_client_plugin {

class VisualizerSink : public libwebrtc::AudioTrackSink {
public:
  VisualizerSink(BinaryMessenger *messenger, std::string event_channel_name,
                 libwebrtc::scoped_refptr<libwebrtc::RTCMediaTrack> media_track,
                 bool is_centered = false, int bar_count = 7)
      : channel_(
            std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
                messenger, event_channel_name,
                &flutter::StandardMethodCodec::GetInstance())),
        media_track_(media_track), is_centered_(is_centered),
        bar_count_(bar_count) {
    task_runner_ = std::make_unique<livekit_client_plugin::TaskRunnerWindows>();
    auto handler = std::make_unique<
        flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        [&](const flutter::EncodableValue *arguments,
            std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
                &&events)
            -> std::unique_ptr<
                flutter::StreamHandlerError<flutter::EncodableValue>> {
          std::list<flutter::EncodableValue> queued_events;
          {
            std::lock_guard<std::mutex> lock(sink_mutex_);
            sink_ = std::move(events);
            queued_events.swap(event_queue_);
            on_listen_called_.store(true);
          }
          for (auto &event : queued_events) {
            PostEvent(event);
          }
          return nullptr;
        },
        [&](const flutter::EncodableValue *arguments)
            -> std::unique_ptr<
                flutter::StreamHandlerError<flutter::EncodableValue>> {
          on_listen_called_.store(false);
          std::lock_guard<std::mutex> lock(sink_mutex_);
          sink_.reset();
          return nullptr;
        });

    channel_->SetStreamHandler(std::move(handler));
    audio_visualizer_ =
        std::make_unique<AudioVisualizer>(bar_count_, is_centered_);
    if (media_track_) {
      audio_track_ = dynamic_cast<libwebrtc::RTCAudioTrack *>(media_track_.get());
    }
    if (audio_track_ != nullptr) {
      audio_track_->AddSink(this);
    } else {
      removed_.store(true);
    }
  }
  ~VisualizerSink() override { RemoveSink(); }

public:
  void OnData(const void *audio_data, int bits_per_sample, int sample_rate,
              size_t number_of_channels, size_t number_of_frames) override {
    if (removed_.load() || !on_listen_called_.load() || audio_data == nullptr ||
        bits_per_sample != 16 || sample_rate <= 0 ||
        number_of_channels == 0 || number_of_frames == 0) {
      return;
    }

    if (number_of_frames >
        (std::numeric_limits<size_t>::max)() / number_of_channels) {
      return;
    }
    const size_t sample_count = number_of_frames * number_of_channels;
    if (sample_count == 0 ||
        sample_count > static_cast<size_t>(
                           (std::numeric_limits<unsigned int>::max)())) {
      return;
    }

    std::vector<float> bands;
    bool processed = false;
    {
      std::lock_guard<std::mutex> lock(audio_mutex_);
      if (removed_.load() || !audio_visualizer_) {
        return;
      }
      processed = audio_visualizer_->Process(
          static_cast<const int16_t *>(audio_data),
          static_cast<unsigned int>(sample_count), float(sample_rate), bands);
    }
    if (processed) {
      // Post the processed data to the event sink
      EncodableList bands_list = EncodableList(bands.begin(), bands.end());
      Success(EncodableValue(bands_list));
    }
  }

  void Success(const flutter::EncodableValue &event, bool cache_event = true) {
    if (on_listen_called_.load()) {
      PostEvent(event);
    } else if (cache_event) {
      std::lock_guard<std::mutex> lock(sink_mutex_);
      event_queue_.push_back(event);
    }
  }

  void PostEvent(const flutter::EncodableValue &event) {
    std::weak_ptr<flutter::EventSink<EncodableValue>> weak_sink;
    {
      std::lock_guard<std::mutex> lock(sink_mutex_);
      weak_sink = sink_;
    }
    if (task_runner_) {
      task_runner_->EnqueueTask([weak_sink, event]() {
        auto sink = weak_sink.lock();
        if (sink) {
          sink->Success(event);
        }
      });
    } else {
      auto sink = weak_sink.lock();
      if (sink) {
        sink->Success(event);
      }
    }
  }

  void RemoveSink() {
    if (removed_.exchange(true)) {
      return;
    }
    if (audio_track_ != nullptr) {
      audio_track_->RemoveSink(this);
      audio_track_ = nullptr;
    }

    std::lock_guard<std::mutex> lock(audio_mutex_);
  }

  bool IsAttached() const {
    return audio_track_ != nullptr && !removed_.load();
  }

private:
  std::unique_ptr<AudioVisualizer> audio_visualizer_;
  std::unique_ptr<livekit_client_plugin::TaskRunnerWindows> task_runner_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> channel_;
  std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  std::list<flutter::EncodableValue> event_queue_;
  std::mutex sink_mutex_;
  std::mutex audio_mutex_;
  std::atomic<bool> on_listen_called_{false};
  std::atomic<bool> removed_{false};
  libwebrtc::scoped_refptr<libwebrtc::RTCMediaTrack> media_track_;
  libwebrtc::RTCAudioTrack *audio_track_ = nullptr;
  bool is_centered_ = false;
  int bar_count_ = 7;
};

class LiveKitPlugin : public flutter::Plugin {
public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  LiveKitPlugin(BinaryMessenger *messenger);

  virtual ~LiveKitPlugin();

private:
  flutter_webrtc_plugin::FlutterWebRTC *WebRTCInstance();

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

private:
  flutter_webrtc_plugin::FlutterWebRTC *webrtc_instance_ = nullptr;
  std::unordered_map<std::string, std::unique_ptr<VisualizerSink>> visualizers_;
  BinaryMessenger *messenger_ = nullptr;
  mutable std::mutex mutex_;
};

// static
void LiveKitPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "livekit_client",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<LiveKitPlugin>(registrar->messenger());

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

LiveKitPlugin::LiveKitPlugin(BinaryMessenger *messenger)
    : messenger_(messenger) {
  webrtc_instance_ = FlutterWebRTCPluginSharedInstance();
}

LiveKitPlugin::~LiveKitPlugin() {}

flutter_webrtc_plugin::FlutterWebRTC *LiveKitPlugin::WebRTCInstance() {
  if (webrtc_instance_ == nullptr) {
    webrtc_instance_ = FlutterWebRTCPluginSharedInstance();
  }
  return webrtc_instance_;
}

void LiveKitPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("startVisualizer") == 0) {
    if (!method_call.arguments()) {
      result->Error("Bad Arguments", "Null arguments received");
      return;
    }
    flutter::EncodableMap params =
        GetValue<flutter::EncodableMap>(*method_call.arguments());
    std::string trackId = findString(params, "trackId");
    std::string visualizerId = findString(params, "visualizerId");
    int barCount = findInt(params, "barCount");
    bool isCentered = findBoolean(params, "isCentered");
    if (trackId.empty() || visualizerId.empty()) {
      result->Error("Invalid Arguments",
                    "trackId and visualizerId are required");
      return;
    }
    auto *webrtc_instance = WebRTCInstance();
    if (webrtc_instance == nullptr) {
      result->Error("WebRTC Not Initialized",
                    "Flutter WebRTC is not available for audio visualizer");
      return;
    }
    libwebrtc::scoped_refptr<libwebrtc::RTCMediaTrack> media_track =
        webrtc_instance->MediaTrackForId(trackId);
    if (!media_track) {
      result->Error("Track Not Found", "No media track found for the given ID");
      return;
    }
    if (barCount <= 0) {
      barCount = AudioVisualizer::kDefaultBandsCount;
    }
    std::ostringstream oss;
    oss << "io.livekit.audio.visualizer/eventChannel-" << trackId << "-"
        << visualizerId;

    auto visualizer = std::make_unique<VisualizerSink>(
        messenger_, oss.str(), media_track, isCentered, barCount);
    if (!visualizer->IsAttached()) {
      result->Error("Visualizer Not Started",
                    "Failed to attach the audio visualizer sink");
      return;
    }

    std::lock_guard<std::mutex> lock(mutex_);
    auto it = visualizers_.find(visualizerId);
    if (it != visualizers_.end()) {
      it->second->RemoveSink();
      visualizers_.erase(it);
    }
    visualizers_[visualizerId] = std::move(visualizer);

    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name().compare("stopVisualizer") == 0) {
    if (!method_call.arguments()) {
      result->Error("Bad Arguments", "Null arguments received");
      return;
    }
    flutter::EncodableMap args =
        GetValue<flutter::EncodableMap>(*method_call.arguments());
    std::string trackId = findString(args, "trackId");
    std::string visualizerId = findString(args, "visualizerId");
    if (trackId.empty() || visualizerId.empty()) {
      result->Error("Invalid Arguments",
                    "trackId and visualizerId are required");
      return;
    }

    std::lock_guard<std::mutex> lock(mutex_);
    auto it = visualizers_.find(visualizerId);
    if (it != visualizers_.end()) {
      it->second->RemoveSink();
      visualizers_.erase(it);
    } else {
      result->Error("Visualizer Not Found",
                    "No visualizer found for the given visualizerId");
      return;
    }

    result->Success();
  } else {
    result->NotImplemented();
  }
}

} // namespace livekit_client_plugin

void LiveKitPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  livekit_client_plugin::LiveKitPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
