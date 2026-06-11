#ifndef AUDIOPLAYERS_WINDOWS_TASK_RUNNER_WINDOWS_H_
#define AUDIOPLAYERS_WINDOWS_TASK_RUNNER_WINDOWS_H_

#include <windows.h>

#include <functional>
#include <mutex>
#include <queue>
#include <string>

namespace audioplayers_windows {

using TaskClosure = std::function<void()>;

// Runs queued callbacks on the Windows platform thread. Flutter requires
// platform-channel messages to be sent from that thread.
class TaskRunnerWindows {
 public:
  TaskRunnerWindows();
  ~TaskRunnerWindows();

  void EnqueueTask(TaskClosure task);

 private:
  void ProcessTasks();
  WNDCLASS RegisterWindowClass();

  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) noexcept;

  static LRESULT CALLBACK WndProc(HWND window,
                                  UINT message,
                                  WPARAM wparam,
                                  LPARAM lparam) noexcept;

  HWND window_handle_ = nullptr;
  std::wstring window_class_name_;
  std::mutex tasks_mutex_;
  std::queue<TaskClosure> tasks_;

  TaskRunnerWindows(const TaskRunnerWindows&) = delete;
  TaskRunnerWindows& operator=(const TaskRunnerWindows&) = delete;
};

}  // namespace audioplayers_windows

#endif  // AUDIOPLAYERS_WINDOWS_TASK_RUNNER_WINDOWS_H_
