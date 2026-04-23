#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shlobj.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

// Registers .stitches → StitchesFile under HKCU (no admin required).
// Runs on every launch so the association stays current if the exe moves.
static void RegisterFileAssociation() {
  wchar_t exe_path[MAX_PATH] = {};
  ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);

  auto write_sz = [](HKEY root, const wchar_t* subkey, const wchar_t* value,
                     const wchar_t* data) {
    HKEY key = nullptr;
    if (::RegCreateKeyExW(root, subkey, 0, nullptr, REG_OPTION_NON_VOLATILE,
                          KEY_WRITE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
      ::RegSetValueExW(key, value, 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(data),
                       static_cast<DWORD>((::wcslen(data) + 1) * sizeof(wchar_t)));
      ::RegCloseKey(key);
    }
  };

  // .stitches -> ProgID
  write_sz(HKEY_CURRENT_USER, L"Software\\Classes\\.stitches", nullptr,
           L"StitchesFile");

  // ProgID display name
  write_sz(HKEY_CURRENT_USER, L"Software\\Classes\\StitchesFile", nullptr,
           L"Stitches Pattern File");

  // Open command
  std::wstring cmd = std::wstring(L"\"") + exe_path + L"\" \"%1\"";
  write_sz(HKEY_CURRENT_USER,
           L"Software\\Classes\\StitchesFile\\shell\\open\\command", nullptr,
           cmd.c_str());

  // Notify shell so Explorer updates file icons/associations immediately.
  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

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

  RegisterFileAssociation();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Detect a .stitches file passed via file-association open.
  std::string initial_file_path;
  for (const auto& arg : command_line_arguments) {
    if (arg.size() > 8 &&
        arg.substr(arg.size() - 8) == ".stitches") {
      initial_file_path = arg;
      break;
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  if (!initial_file_path.empty()) {
    window.SetInitialFilePath(initial_file_path);
  }

  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"stitches", origin, size)) {
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
