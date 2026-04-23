#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Set the file path passed on the command line (e.g. via file association).
  // Must be called before the Flutter engine delivers its first frame so that
  // getInitialFile() can return it.
  void SetInitialFilePath(const std::string& path) {
    initial_file_path_ = path;
  }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // MethodChannel for file-open events (mirrors macOS AppDelegate channel).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      file_open_channel_;

  // File path received via command-line argument (file association open).
  // Returned once by getInitialFile, then cleared.
  std::string initial_file_path_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
