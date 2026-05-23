; Sparxie – Windows installer script (Inno Setup 6)
; Required /D defines (passed on the command line):
;   MyAppVersion       – e.g. 1.0.0
;   MyAppBundleDir     – absolute Windows path to the Flutter release bundle
;   MyAppArch          – x64compatible  or  arm64
;   MyAppOutputDir     – directory for the output .exe
;   MyAppOutputFilename – output filename without extension

#define MyAppName        "Sparxie"
#define MyAppPublisher   "Sparxie"
#define MyAppURL         "https://github.com/UruhaLushia/sparxie"
#define MyAppExeName     "sparxie.exe"

[Setup]
; AppId uniquely identifies this application across installs/uninstalls.
; Do NOT change it once released; changing it breaks upgrade detection.
AppId={{7C2A1F3E-B5D8-4E9A-82C6-F0143A7B5E21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir={#MyAppOutputDir}
OutputBaseFilename={#MyAppOutputFilename}
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; Allow non-admin install; user can escalate if they want a per-machine install.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed={#MyAppArch}
ArchitecturesInstallIn64BitMode={#MyAppArch}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Copy the entire Flutter release bundle (exe, dlls, data/) into {app}.
Source: "{#MyAppBundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}";                          Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}";    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}";                    Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
