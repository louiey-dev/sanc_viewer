# Sanc Viewer Windows installer

## Distribution

- Installer: `dist/SancViewer-0.1.0-windows-x64-Setup.exe`
- Checksum: `dist/SancViewer-0.1.0-windows-x64-Setup.exe.sha256`
- Target: Windows 10/11, x64.
- The installer is generated with Inno Setup 6.4.3, rather than the
  proprietary InstallShield product.
- The generated executable is not code signed.

Send the installer executable to users. They do not need Flutter, Visual Studio,
or the project files. The installer includes the Flutter runtime, plugins,
assets, and app-local Visual C++ runtime DLLs from Visual Studio's redistributable
directory.

## Installation behavior

- Installs for the current user without administrator privileges.
- Default directory: `%LOCALAPPDATA%\Programs\SancViewer`.
- Creates a Start menu shortcut; the desktop shortcut is optional.
- Registers JPG, JPEG, PNG, GIF, WebP, BMP, and ICO when the registration task
  is selected. Windows retains control of default-app selection.
- Users can choose **File > File associations** to open Windows Default apps.
- Provides an uninstaller through Windows Installed apps.
- Updates use the same application ID and installation directory.
- User settings in `%APPDATA%\SancViewer\settings.json` survive updates
  and uninstallations.

## Rebuild in PowerShell

The script reads the version from `pubspec.yaml`, builds the Release application,
collects the matching Visual Studio app-local runtime, compiles the installer,
and generates a SHA-256 file.

```powershell
Set-Location D:\GIT\GitHub\sanc_viewer
powershell -NoProfile -ExecutionPolicy Bypass -File installer/build.ps1
```

To package an existing Release build:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File installer/build.ps1 -SkipBuild
```

The current portable compiler is under `build/installer-tools/inno/ISCC.exe`.
The build directory is disposable. On another machine, install Inno Setup or
provide its compiler path with `-IsccPath`. Optional parameters are
`-FlutterPath` and `-VCRuntimeDirectory`.

The compiler used here is available from the
[official Inno Setup 6.4.3 release](https://github.com/jrsoftware/issrc/releases/tag/is-6_4_3).
Its downloaded installer was verified with Authenticode: valid signature from
Pyrsys B.V.

## Verification performed

- Compiled the installer successfully.
- Installed silently into `build/installer-smoke`, with shortcut creation and
  image registration disabled for this test.
- Verified all 20 packaged application files against the Release source hashes.
- Verified the three primary Visual C++ runtime DLLs were present.
- Launched the installed executable and confirmed its process and window existed.
- Closed the test application and uninstalled successfully with exit code 0.
- Confirmed the installed executable and uninstall registration were removed.
- Tests ran on the development PC; a clean Windows VM was not tested.
- Interactive wizard appearance and actual default-app selection were not tested.

Logs are in `build/installer-build.log`, `build/installer-smoke-install.log`,
and `build/installer-smoke-uninstall.log`.
