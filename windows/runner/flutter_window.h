#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "win32_window.h"

// Istanza unica (main.cpp): la copia nuova trova la finestra con classe,
// titolo ed eseguibile uguali e le passa la riga di comando con WM_COPYDATA.
inline constexpr const wchar_t* kSingleInstanceMutex =
    L"Local\\DrinPhone.SingleInstance";
inline constexpr const wchar_t* kWindowClass = L"FLUTTER_RUNNER_WIN32_WINDOW";
inline constexpr const wchar_t* kWindowTitle = L"DrinPhone Alpha";
inline constexpr ULONG_PTR kInstanceArgs = 0x44524E31;  // "DRN1"
inline constexpr size_t kInstanceArgsMax = 2048;        // caratteri

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

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

  // Riga di comando di un'altra copia verso Dart ("drinphone/instance").
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      instance_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
