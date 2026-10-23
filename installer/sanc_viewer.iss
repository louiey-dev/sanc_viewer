#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#define ProjectRoot SourcePath + ".."
#define ReleaseDir ProjectRoot + "\build\windows\x64\runner\Release"

[Setup]
AppId={{670B1802-33DB-40BF-8AC5-8665E8E25074}
AppName=Sanc Viewer
AppVersion={#AppVersion}
AppVerName=Sanc Viewer {#AppVersion}
DefaultDirName={localappdata}\Programs\SancViewer
DefaultGroupName=Sanc Viewer
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#ProjectRoot}\dist
OutputBaseFilename=SancViewer-{#AppVersion}-windows-x64-Setup
SetupIconFile={#ProjectRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\sanc_viewer.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ChangesAssociations=yes
VersionInfoDescription=Sanc Viewer Setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
Name: "fileassociations"; Description: "Register supported image formats (default app selection stays in Windows Settings)"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ProjectRoot}\build\installer-runtime\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Sanc Viewer"; Filename: "{app}\sanc_viewer.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Sanc Viewer"; Filename: "{app}\sanc_viewer.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Classes\SancViewer.Image"; ValueType: string; ValueData: "Sanc Viewer Image"; Flags: uninsdeletekey; Tasks: fileassociations
Root: HKCU; Subkey: "Software\Classes\SancViewer.Image\DefaultIcon"; ValueType: string; ValueData: """{app}\sanc_viewer.exe"",0"; Tasks: fileassociations
Root: HKCU; Subkey: "Software\Classes\SancViewer.Image\shell\open\command"; ValueType: string; ValueData: """{app}\sanc_viewer.exe"" ""%1"""; Tasks: fileassociations
Root: HKCU; Subkey: "Software\Classes\Applications\sanc_viewer.exe"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "Sanc Viewer"; Flags: uninsdeletekey; Tasks: fileassociations
Root: HKCU; Subkey: "Software\Classes\Applications\sanc_viewer.exe\shell\open\command"; ValueType: string; ValueData: """{app}\sanc_viewer.exe"" ""%1"""; Tasks: fileassociations
Root: HKCU; Subkey: "Software\SancViewer\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Sanc Viewer"; Flags: uninsdeletekey; Tasks: fileassociations
Root: HKCU; Subkey: "Software\SancViewer\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "View images with Sanc Viewer"; Tasks: fileassociations
Root: HKCU; Subkey: "Software\SancViewer\Capabilities"; ValueType: string; ValueName: "ApplicationIcon"; ValueData: """{app}\sanc_viewer.exe"",0"; Tasks: fileassociations
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "Sanc Viewer"; ValueData: "Software\SancViewer\Capabilities"; Flags: uninsdeletevalue; Tasks: fileassociations
#sub ImageType
Root: HKCU; Subkey: "Software\SancViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".{#Extension}"; ValueData: "SancViewer.Image"; Tasks: fileassociations
Root: HKCU; Subkey: "Software\Classes\Applications\sanc_viewer.exe\SupportedTypes"; ValueType: string; ValueName: ".{#Extension}"; ValueData: ""; Tasks: fileassociations
Root: HKCU; Subkey: "Software\Classes\.{#Extension}\OpenWithProgids"; ValueType: string; ValueName: "SancViewer.Image"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassociations
#endsub
#define Extension "jpg"
#emit ImageType
#define Extension "jpeg"
#emit ImageType
#define Extension "png"
#emit ImageType
#define Extension "gif"
#emit ImageType
#define Extension "webp"
#emit ImageType
#define Extension "bmp"
#emit ImageType
#define Extension "ico"
#emit ImageType

[Run]
Filename: "{app}\sanc_viewer.exe"; Description: "Launch Sanc Viewer"; Flags: nowait postinstall skipifsilent
