#define AppName "Gang Chat"
#define AppPublisher "Gang Chat"
#define AppExeName "client.exe"
#ifndef AppVersion
#define AppVersion "0.0.0"
#endif
#ifndef SourceDir
#define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
#define OutputDir "..\build\installer"
#endif
#ifndef AppIconFile
#define AppIconFile "..\windows\runner\resources\app_icon.ico"
#endif

[Setup]
AppId={{8E770563-B46C-4F90-9B9D-12B4EF8D37C2}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\Gang Chat
DefaultGroupName=Gang Chat
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=GangChat-{#AppVersion}-windows-x64-setup
SetupIconFile={#AppIconFile}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
AppMutex=gang_chat_single_instance_mutex
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#AppExeName}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Gang Chat"; Filename: "{app}\{#AppExeName}"
Name: "{userdesktop}\Gang Chat"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,Gang Chat}"; Flags: nowait postinstall skipifsilent
