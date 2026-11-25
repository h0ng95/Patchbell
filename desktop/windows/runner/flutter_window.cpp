#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <gdiplus.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <windowsx.h>
#include <wrl/client.h>

#include <cstdint>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

namespace {

constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayEvent = WM_APP + 1;
constexpr UINT kOpenCommand = 1;
constexpr UINT kQuitCommand = 2;
const UINT kTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
const UINT kTaskbarButtonCreated =
    RegisterWindowMessageW(L"TaskbarButtonCreated");
const UINT kReopenWindow = RegisterWindowMessageW(L"io.github.h0ng95.Patchbell.Reopen");

NOTIFYICONDATAW TrayIconData(HWND hwnd) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = hwnd;
  data.uID = kTrayIconId;
  return data;
}

void RestoreWindow(HWND hwnd) {
  ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(hwnd);
}

COLORREF ToColorRef(int32_t rgb) {
  return RGB((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
}

std::wstring ToWideString(const std::string& text) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         text.c_str(), -1, nullptr, 0);
  if (length <= 1) return {};
  std::wstring result(length, L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.c_str(), -1,
                           result.data(), length)) {
    return {};
  }
  result.pop_back();
  return result;
}

std::string ReadRegistryText(HKEY key, const wchar_t* name) {
  wchar_t value[2048]{};
  DWORD size = static_cast<DWORD>(sizeof(value));
  if (RegGetValueW(key, nullptr, name, RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ,
                   nullptr, value, &size) != ERROR_SUCCESS) {
    return {};
  }
  return Utf8FromUtf16(value);
}

void ReadUninstallEntries(HKEY hive, REGSAM view,
                          flutter::EncodableList* entries) {
  constexpr wchar_t path[] = LR"(Software\Microsoft\Windows\CurrentVersion\Uninstall)";
  HKEY uninstall;
  if (RegOpenKeyExW(hive, path, 0, KEY_ENUMERATE_SUB_KEYS | view,
                    &uninstall) != ERROR_SUCCESS) {
    return;
  }
  for (DWORD index = 0;; ++index) {
    wchar_t subkey[256]{};
    DWORD length = static_cast<DWORD>(sizeof(subkey) / sizeof(subkey[0]));
    if (RegEnumKeyExW(uninstall, index, subkey, &length,
                      nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) {
      break;
    }
    HKEY app;
    if (RegOpenKeyExW(uninstall, subkey, 0, KEY_QUERY_VALUE | view,
                      &app) != ERROR_SUCCESS) {
      continue;
    }
    DWORD system_component = 0;
    DWORD size = static_cast<DWORD>(sizeof(system_component));
    RegGetValueW(app, nullptr, L"SystemComponent", RRF_RT_REG_DWORD,
                 nullptr, &system_component, &size);
    if (system_component == 0 && ReadRegistryText(app, L"ParentKeyName").empty()) {
      const auto name = ReadRegistryText(app, L"DisplayName");
      const auto version = ReadRegistryText(app, L"DisplayVersion");
      if (!name.empty() && !version.empty()) {
        using Value = flutter::EncodableValue;
        entries->emplace_back(flutter::EncodableMap{
            {Value("name"), Value(name)},
            {Value("version"), Value(version)},
            {Value("publisher"), Value(ReadRegistryText(app, L"Publisher"))},
            {Value("path"), Value(ReadRegistryText(app, L"InstallLocation"))},
        });
      }
    }
    RegCloseKey(app);
  }
  RegCloseKey(uninstall);
}

flutter::EncodableList InstalledApplications() {
  flutter::EncodableList entries;
  ReadUninstallEntries(HKEY_CURRENT_USER, 0, &entries);
  ReadUninstallEntries(HKEY_LOCAL_MACHINE, KEY_WOW64_64KEY, &entries);
  ReadUninstallEntries(HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY, &entries);
  return entries;
}

int SmallIconSize(UINT dpi) {
  const int size = GetSystemMetricsForDpi(SM_CXSMICON, dpi);
  return size > 0 ? size : 16;
}

HICON DrawBadgeIcon(int32_t count, int size, HICON app_icon = nullptr) {
  Gdiplus::GdiplusStartupInput startup;
  ULONG_PTR token;
  if (Gdiplus::GdiplusStartup(&token, &startup, nullptr) != Gdiplus::Ok) {
    return nullptr;
  }

  HICON icon = nullptr;
  {
    Gdiplus::Bitmap bitmap(size, size, PixelFormat32bppARGB);
    Gdiplus::Graphics graphics(&bitmap);
    graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
    if (app_icon) {
      Gdiplus::Bitmap logo(app_icon);
      graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
      const int logo_size = size - size / 8;
      graphics.DrawImage(&logo, 0, 0, logo_size, logo_size);
    }
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

    const auto edge = static_cast<float>(size);
    const float badge_height = app_icon ? edge * 0.60f : edge;
    float badge_width = badge_height;
    if (app_icon && count >= 10) {
      badge_width = edge * (count < 100 ? 0.75f : 0.875f);
    }
    Gdiplus::RectF bounds(edge - badge_width, edge - badge_height,
                          badge_width, badge_height);
    Gdiplus::SolidBrush background(Gdiplus::Color(255, 197, 35, 54));
    graphics.FillEllipse(&background, bounds);

    const std::wstring number = count > 99 ? L"99+" : std::to_wstring(count);
    const float font_scale = count < 10 ? 0.75f : count < 100 ? 0.64f : 0.53f;
    Gdiplus::Font font(L"Segoe UI", badge_height * font_scale,
                       Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    Gdiplus::StringFormat format(Gdiplus::StringFormat::GenericTypographic());
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    Gdiplus::SolidBrush foreground(Gdiplus::Color(255, 255, 255, 255));
    graphics.DrawString(number.c_str(), -1, &font, bounds, &format, &foreground);
    bitmap.GetHICON(&icon);
  }
  Gdiplus::GdiplusShutdown(token);
  return icon;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::ActivateExistingWindow() {
  const HWND window = FindExistingWindow();
  if (!window || !kReopenWindow) return false;
  DWORD process = 0;
  GetWindowThreadProcessId(window, &process);
  AllowSetForegroundWindow(process);
  return PostMessageW(window, kReopenWindow, 0, 0) != FALSE;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  flutter::MethodChannel<flutter::EncodableValue> window_channel(
      flutter_controller_->engine()->messenger(),
      "io.github.h0ng95.patchbell/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel.SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "installedApplications") {
      result->Success(flutter::EncodableValue(InstalledApplications()));
      return;
    }
    const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
    if (call.method_name() == "setTrayBadge") {
      if (!args || args->size() != 4) {
        result->Error("invalid-arguments", "Expected badge and tray menu text.");
        return;
      }
      const auto* count = std::get_if<int32_t>(&(*args)[0]);
      const auto* description = std::get_if<std::string>(&(*args)[1]);
      const auto* open = std::get_if<std::string>(&(*args)[2]);
      const auto* quit = std::get_if<std::string>(&(*args)[3]);
      if (!count || *count < 0 || !description || !open || !quit) {
        result->Error("invalid-arguments", "Invalid tray badge.");
        return;
      }
      badge_count_ = *count;
      badge_description_ = ToWideString(*description);
      tray_open_label_ = ToWideString(*open);
      tray_quit_label_ = ToWideString(*quit);
      UpdateTaskbarBadge();
      result->Success(flutter::EncodableValue(UpdateTrayIcon()));
      return;
    }
    if (call.method_name() != "setCaptionColors") {
      result->NotImplemented();
      return;
    }
    if (!args || args->size() != 3) {
      result->Error("invalid-arguments", "Expected two colors and a dark flag.");
      return;
    }
    const auto* background = std::get_if<int32_t>(&(*args)[0]);
    const auto* foreground = std::get_if<int32_t>(&(*args)[1]);
    const auto* dark = std::get_if<bool>(&(*args)[2]);
    if (!background || !foreground || !dark) {
      result->Error("invalid-arguments", "Expected two colors and a dark flag.");
      return;
    }
    SetCaptionColors(ToColorRef(*background), ToColorRef(*foreground), *dark);
    result->Success();
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  UpdateTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

bool FlutterWindow::UpdateTrayIcon() {
  const int size = SmallIconSize(GetDpiForSystem());
  HICON icon = static_cast<HICON>(LoadImageW(GetModuleHandleW(nullptr),
      MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON, size, size, LR_DEFAULTCOLOR));
  if (!icon) return false;
  if (badge_count_ > 0) {
    if (HICON badged_icon = DrawBadgeIcon(badge_count_, size, icon)) {
      DestroyIcon(icon);
      icon = badged_icon;
    }
  }

  auto data = TrayIconData(GetHandle());
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
  data.hIcon = icon;
  data.uCallbackMessage = kTrayEvent;
  wcsncpy_s(data.szTip, badge_description_.c_str(), _TRUNCATE);
  if (!tray_icon_added_ || !Shell_NotifyIconW(NIM_MODIFY, &data)) {
    tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
    if (tray_icon_added_) {
      data.uVersion = NOTIFYICON_VERSION_4;
      Shell_NotifyIconW(NIM_SETVERSION, &data);
    }
  }
  DestroyIcon(icon);
  return tray_icon_added_;
}

void FlutterWindow::UpdateTaskbarBadge() {
  if (!taskbar_button_ready_) return;

  Microsoft::WRL::ComPtr<ITaskbarList3> taskbar;
  if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(taskbar.GetAddressOf()))) ||
      FAILED(taskbar->HrInit())) {
    return;
  }

  const HWND hwnd = GetHandle();
  if (badge_count_ == 0) {
    taskbar->SetOverlayIcon(hwnd, nullptr, nullptr);
    return;
  }
  if (HICON icon = DrawBadgeIcon(badge_count_, SmallIconSize(GetDpiForWindow(hwnd)))) {
    taskbar->SetOverlayIcon(hwnd, icon, badge_description_.c_str());
    DestroyIcon(icon);
  }
}

void FlutterWindow::RemoveTrayIcon(HWND hwnd) {
  if (!tray_icon_added_) return;
  auto data = TrayIconData(hwnd);
  Shell_NotifyIconW(NIM_DELETE, &data);
  tray_icon_added_ = false;
}

void FlutterWindow::ShowTrayMenu(HWND hwnd, POINT point) {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, kOpenCommand, tray_open_label_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kQuitCommand, tray_quit_label_.c_str());
  SetMenuDefaultItem(menu, kOpenCommand, FALSE);
  SetForegroundWindow(hwnd);
  const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY |
                                      TPM_RIGHTBUTTON, point.x, point.y, 0,
                                      hwnd, nullptr);
  DestroyMenu(menu);
  PostMessageW(hwnd, WM_NULL, 0, 0);
  if (command == kOpenCommand) RestoreWindow(hwnd);
  if (command == kQuitCommand) DestroyWindow(hwnd);
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (kTaskbarCreated && message == kTaskbarCreated) {
    tray_icon_added_ = false;
    taskbar_button_ready_ = false;
    UpdateTrayIcon();
    return 0;
  }
  if (kTaskbarButtonCreated && message == kTaskbarButtonCreated) {
    taskbar_button_ready_ = true;
    UpdateTaskbarBadge();
    return 0;
  }
  if (kReopenWindow && message == kReopenWindow) {
    RestoreWindow(hwnd);
    return 0;
  }
  if (message == kTrayEvent) {
    const UINT event = LOWORD(lparam);
    if (event == NIN_SELECT || event == NIN_KEYSELECT || event == WM_LBUTTONUP) {
      RestoreWindow(hwnd);
    } else if (event == WM_CONTEXTMENU || event == WM_RBUTTONUP) {
      POINT point{GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam)};
      if (event == WM_RBUTTONUP || (point.x == -1 && point.y == -1)) {
        GetCursorPos(&point);
      }
      ShowTrayMenu(hwnd, point);
    }
    return 0;
  }
  if (message == WM_CLOSE && tray_icon_added_) {
    taskbar_button_ready_ = false;
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }
  if (message == WM_DESTROY) RemoveTrayIcon(hwnd);

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
