#include "task_runner_windows.h"

#include <iostream>

namespace audioplayers_windows {

TaskRunnerWindows::TaskRunnerWindows() {
  WNDCLASS window_class = RegisterWindowClass();
  window_handle_ = CreateWindowEx(0, window_class.lpszClassName,
                                  L"audioplayers", 0, 0, 0, 0, 0,
                                  HWND_MESSAGE, nullptr,
                                  window_class.hInstance, nullptr);

  if (window_handle_) {
    SetWindowLongPtr(window_handle_, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(this));
  } else {
    const auto error_code = GetLastError();
    std::cerr << "Audioplayers: failed to create task runner window; "
              << "error_code: " << error_code << std::endl;
  }
}

TaskRunnerWindows::~TaskRunnerWindows() {
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (!window_class_name_.empty()) {
    UnregisterClass(window_class_name_.c_str(), nullptr);
  }
}

void TaskRunnerWindows::EnqueueTask(TaskClosure task) {
  {
    std::lock_guard<std::mutex> lock(tasks_mutex_);
    tasks_.push(std::move(task));
  }

  if (window_handle_ && PostMessage(window_handle_, WM_NULL, 0, 0)) {
    return;
  }

  const auto error_code = GetLastError();
  std::cerr << "Audioplayers: failed to post task to platform thread; "
            << "error_code: " << error_code << std::endl;
}

void TaskRunnerWindows::ProcessTasks() {
  for (;;) {
    TaskClosure task;
    {
      std::lock_guard<std::mutex> lock(tasks_mutex_);
      if (tasks_.empty()) {
        break;
      }
      task = std::move(tasks_.front());
      tasks_.pop();
    }
    task();
  }
}

WNDCLASS TaskRunnerWindows::RegisterWindowClass() {
  window_class_name_ = L"AudioplayersWindowsTaskRunnerWindow";

  WNDCLASS window_class{};
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = window_class_name_.c_str();
  window_class.lpfnWndProc = WndProc;
  RegisterClass(&window_class);
  return window_class;
}

LRESULT TaskRunnerWindows::HandleMessage(UINT message,
                                         WPARAM wparam,
                                         LPARAM lparam) noexcept {
  if (message == WM_NULL) {
    ProcessTasks();
    return 0;
  }
  return DefWindowProcW(window_handle_, message, wparam, lparam);
}

LRESULT TaskRunnerWindows::WndProc(HWND window,
                                   UINT message,
                                   WPARAM wparam,
                                   LPARAM lparam) noexcept {
  auto* runner =
      reinterpret_cast<TaskRunnerWindows*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (runner) {
    return runner->HandleMessage(message, wparam, lparam);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

}  // namespace audioplayers_windows
