#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Percorso dell'eseguibile di un processo, in minuscolo ("" se non leggibile).
std::wstring ExePath(DWORD pid) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) return L"";
  wchar_t buffer[MAX_PATH * 2];
  DWORD size = static_cast<DWORD>(std::size(buffer));
  std::wstring path;
  if (::QueryFullProcessImageNameW(process, 0, buffer, &size)) {
    path.assign(buffer, size);
    ::CharLowerBuffW(path.data(), static_cast<DWORD>(path.size()));
  }
  ::CloseHandle(process);
  return path;
}

// La finestra di DrinPhone aperta dallo stesso eseguibile: una build di
// sviluppo e quella installata restano copie distinte.
HWND FindOwnWindow(const std::wstring& exe) {
  struct Search {
    const std::wstring* exe;
    HWND found;
  } search{&exe, nullptr};
  ::EnumWindows(
      [](HWND hwnd, LPARAM lparam) -> BOOL {
        auto* s = reinterpret_cast<Search*>(lparam);
        wchar_t name[64];
        if (::GetClassNameW(hwnd, name, 64) == 0 ||
            wcscmp(name, kWindowClass) != 0 ||
            ::GetWindowTextW(hwnd, name, 64) == 0 ||
            wcscmp(name, kWindowTitle) != 0) {
          return TRUE;
        }
        DWORD pid = 0;
        ::GetWindowThreadProcessId(hwnd, &pid);
        if (pid == ::GetCurrentProcessId() || ExePath(pid) != *s->exe) {
          return TRUE;
        }
        s->found = hwnd;
        return FALSE;
      },
      reinterpret_cast<LPARAM>(&search));
  return search.found;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Istanza unica: una seconda copia (icona cliccata di nuovo, link tel: o
  // sip: da browser/Outlook) passa la riga di comando a quella aperta, che
  // si mostra e chiede conferma prima di chiamare; poi termina.
  // Un mutex per eseguibile (nome con l'hash del percorso).
  const std::wstring exe = ExePath(::GetCurrentProcessId());
  const std::wstring mutex_name =
      std::wstring(kSingleInstanceMutex) + L"." +
      std::to_wstring(std::hash<std::wstring>{}(exe));
  HANDLE single = ::CreateMutexW(nullptr, FALSE, mutex_name.c_str());
  if (single != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND other = FindOwnWindow(exe);
    if (other != nullptr) {
      std::wstring line = command_line != nullptr ? command_line : L"";
      if (line.size() > kInstanceArgsMax) line.resize(kInstanceArgsMax);
      COPYDATASTRUCT data{kInstanceArgs,
                          static_cast<DWORD>((line.size() + 1) * sizeof(wchar_t)),
                          const_cast<wchar_t*>(line.c_str())};
      // La copia nuova è in primo piano: cede il diritto solo a quella aperta.
      DWORD pid = 0;
      ::GetWindowThreadProcessId(other, &pid);
      ::AllowSetForegroundWindow(pid);
      DWORD_PTR result = 0;
      ::SendMessageTimeoutW(other, WM_COPYDATA, 0,
                            reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG,
                            3000, &result);
    }
    ::CloseHandle(single);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
