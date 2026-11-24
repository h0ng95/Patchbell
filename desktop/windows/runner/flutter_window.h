#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <cstdint>
#include <memory>

#include "win32_window.h"

// Hosts the Flutter view and the Patchbell notification-area icon.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();
  static bool ActivateExistingWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  bool UpdateTrayIcon();
  void UpdateTaskbarBadge();
  void RemoveTrayIcon(HWND hwnd);
  void ShowTrayMenu(HWND hwnd, POINT point);

  bool tray_icon_added_ = false;
  bool taskbar_button_ready_ = false;
  int32_t badge_count_ = 0;
  std::wstring badge_description_ = L"Patchbell";
  std::wstring tray_open_label_ = L"Open Patchbell";
  std::wstring tray_quit_label_ = L"Quit Patchbell";

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
