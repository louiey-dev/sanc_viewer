#ifndef RUNNER_FILE_ASSOCIATIONS_H_
#define RUNNER_FILE_ASSOCIATIONS_H_

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <string>

// Per-user registration only. Windows owns the final default-app choice.
inline bool RegisterImageAssociations() {
  wchar_t path[32768];
  const DWORD length = GetModuleFileNameW(nullptr, path, 32768);
  if (length == 0 || length >= 32768) return false;
  const std::wstring executable(path, length);
  const std::wstring command = L"\"" + executable + L"\" \"%1\"";
  const std::wstring icon = L"\"" + executable + L"\",0";
  const auto write = [](const std::wstring& key, const wchar_t* name,
                        const std::wstring& value) {
    HKEY handle;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, key.c_str(), 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &handle, nullptr) != ERROR_SUCCESS) return false;
    const LSTATUS status = RegSetValueExW(handle, name, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(value.c_str()),
        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(handle);
    return status == ERROR_SUCCESS;
  };
  const std::wstring prog = L"Software\\Classes\\SancViewer.Image";
  const std::wstring app = L"Software\\Classes\\Applications\\sanc_viewer.exe";
  const std::wstring capabilities = L"Software\\SancViewer\\Capabilities";
  if (!write(prog, nullptr, L"Sanc Viewer Image") ||
      !write(prog + L"\\DefaultIcon", nullptr, icon) ||
      !write(prog + L"\\shell\\open\\command", nullptr, command) ||
      !write(app, L"FriendlyAppName", L"Sanc Viewer") ||
      !write(app + L"\\shell\\open\\command", nullptr, command) ||
      !write(capabilities, L"ApplicationName", L"Sanc Viewer") ||
      !write(capabilities, L"ApplicationDescription", L"View images with Sanc Viewer") ||
      !write(capabilities, L"ApplicationIcon", icon)) return false;
  for (const auto* extension : {L".jpg", L".jpeg", L".png", L".gif", L".webp", L".bmp", L".ico"}) {
    if (!write(capabilities + L"\\FileAssociations", extension, L"SancViewer.Image") ||
        !write(app + L"\\SupportedTypes", extension, L"") ||
        !write(std::wstring(L"Software\\Classes\\") + extension + L"\\OpenWithProgids",
               L"SancViewer.Image", L"")) return false;
  }
  if (!write(L"Software\\RegisteredApplications", L"Sanc Viewer", capabilities)) return false;
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return true;
}

inline bool OpenImageAssociationSettings(HWND window) {
  auto status = reinterpret_cast<INT_PTR>(ShellExecuteW(window, L"open",
      L"ms-settings:defaultapps?registeredAppUser=Sanc%20Viewer",
      nullptr, nullptr, SW_SHOWNORMAL));
  if (status <= 32) {
    status = reinterpret_cast<INT_PTR>(ShellExecuteW(window, L"open",
        L"ms-settings:defaultapps", nullptr, nullptr, SW_SHOWNORMAL));
  }
  return status > 32;
}
#endif
