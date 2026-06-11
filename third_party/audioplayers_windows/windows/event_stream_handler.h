#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>

#include <memory>
#include <mutex>

#include "task_runner_windows.h"

using namespace flutter;

template <typename T = EncodableValue>
class EventStreamHandler : public StreamHandler<T> {
 public:
  explicit EventStreamHandler(audioplayers_windows::TaskRunnerWindows* runner)
      : runner_(runner), state_(std::make_shared<State>()) {}

  virtual ~EventStreamHandler() = default;

  void Success(std::unique_ptr<T> data) {
    if (!runner_) {
      return;
    }
    auto state = state_;
    auto value = std::make_shared<T>(*data);
    runner_->EnqueueTask([state, value]() {
      std::unique_lock<std::mutex> lock(state->mutex);
      if (state->sink) {
        state->sink->Success(*value);
      }
    });
  }

  void Error(const std::string& error_code,
             const std::string& error_message,
             const T& error_details) {
    if (!runner_) {
      return;
    }
    auto state = state_;
    auto details = error_details;
    runner_->EnqueueTask([state, error_code, error_message, details]() {
      std::unique_lock<std::mutex> lock(state->mutex);
      if (state->sink) {
        state->sink->Error(error_code, error_message, details);
      }
    });
  }

 protected:
  std::unique_ptr<StreamHandlerError<T>> OnListenInternal(
      const T* arguments,
      std::unique_ptr<EventSink<T>>&& events) override {
    std::unique_lock<std::mutex> lock(state_->mutex);
    state_->sink = std::move(events);
    return nullptr;
  }

  std::unique_ptr<StreamHandlerError<T>> OnCancelInternal(
      const T* arguments) override {
    std::unique_lock<std::mutex> lock(state_->mutex);
    state_->sink.reset();
    return nullptr;
  }

 private:
  struct State {
    std::mutex mutex;
    std::unique_ptr<EventSink<T>> sink;
  };

  audioplayers_windows::TaskRunnerWindows* runner_;
  std::shared_ptr<State> state_;
};
