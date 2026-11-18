; z2roN Net 설치 파일(Inno Setup) - GitHub Actions 에서 자동으로 만들어집니다.
#define MyAppName "z2roN Net"
#ifndef AppVersion
  #define AppVersion "1.2.0"
#endif

[Setup]
AppId={{B7C2F1E4-5A31-4B6E-9D1F-2A7C0E5D9A11}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher=z2roN
DefaultDirName={autopf}\z2roN Net
DefaultGroupName=z2roN Net
OutputDir=..\..\dist
OutputBaseFilename=z2roN_Net_Setup_v{#AppVersion}
SetupIconFile=..\..\windows_patch\app_icon.ico
UninstallDisplayIcon={app}\z2ron_net.exe
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "바탕화면에 바로가기 만들기"; GroupDescription: "추가 작업:"; Flags: unchecked

[Files]
Source: "..\..\app_tmp\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\z2roN Net"; Filename: "{app}\z2ron_net.exe"
Name: "{autodesktop}\z2roN Net"; Filename: "{app}\z2ron_net.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\z2ron_net.exe"; Description: "z2roN Net 실행"; Flags: nowait postinstall skipifsilent
