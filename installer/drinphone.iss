; Installatore Windows di DrinPhone (Inno Setup 6). Non si lancia a mano:
;   powershell -File tool/build_installer.ps1
; che compila la release e passa AppVersion e CrtDir (runtime MSVC app-local).
; Installazione per utente (niente UAC) in %LOCALAPPDATA%\Programs\DrinPhone.
; Disinstallando restano account e cache in %APPDATA%\Econnet\DrinPhone.

#ifndef AppVersion
  #error "Manca AppVersion: usa tool/build_installer.ps1"
#endif
#ifndef CrtDir
  #error "Manca CrtDir: usa tool/build_installer.ps1"
#endif

#define AppName "DrinPhone"
#define Channel "Alpha"
#define Release "..\build\windows\x64\runner\Release"

[Setup]
; AppId fisso: non cambiarlo, o gli aggiornamenti diventano installazioni doppie.
AppId={{6B8E2F4A-3C1D-4E7B-9A52-D1F0C8B3E7A1}
AppName={#AppName} {#Channel}
AppVersion={#AppVersion}
AppVerName={#AppName} {#Channel} {#AppVersion}
AppPublisher=Econnet srl
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\build\installer
OutputBaseFilename=DrinPhone-{#Channel}-{#AppVersion}-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\drinphone.exe
InfoBeforeFile=ALPHA.txt
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "it"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#CrtDir}\msvcp140*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#CrtDir}\vcruntime140*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "ALPHA.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName} {#Channel}"; Filename: "{app}\drinphone.exe"
Name: "{autodesktop}\{#AppName} {#Channel}"; Filename: "{app}\drinphone.exe"; Tasks: desktopicon

; L'app scrive da sola il valore di avvio con Windows (Preferenze) e il
; collegamento delle notifiche (local_notifier): si tolgono con l'app.
[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "DrinPhone"; Flags: uninsdeletevalue dontcreatekey
; Link tel:, callto:, sip:, sips: (click-to-call). Solo la capacità: Windows
; chiede all'utente quale app usare, DrinPhone non si prende i link da sola.
Root: HKCU; Subkey: "Software\Classes\DrinPhone.Call"; ValueType: string; ValueName: ""; ValueData: "DrinPhone"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\DrinPhone.Call\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\drinphone.exe,0"
Root: HKCU; Subkey: "Software\Classes\DrinPhone.Call\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\drinphone.exe"" ""%1"""
; Disinstallando le voci si tolgono in ordine inverso: prima le chiavi figlie.
Root: HKCU; Subkey: "Software\Econnet"; Flags: uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\Econnet\DrinPhone"; Flags: uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\Econnet\DrinPhone\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "{#AppName}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Econnet\DrinPhone\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Softphone di Econnet"
Root: HKCU; Subkey: "Software\Econnet\DrinPhone\Capabilities\URLAssociations"; ValueType: string; ValueName: "tel"; ValueData: "DrinPhone.Call"
Root: HKCU; Subkey: "Software\Econnet\DrinPhone\Capabilities\URLAssociations"; ValueType: string; ValueName: "callto"; ValueData: "DrinPhone.Call"
Root: HKCU; Subkey: "Software\Econnet\DrinPhone\Capabilities\URLAssociations"; ValueType: string; ValueName: "sip"; ValueData: "DrinPhone.Call"
Root: HKCU; Subkey: "Software\Econnet\DrinPhone\Capabilities\URLAssociations"; ValueType: string; ValueName: "sips"; ValueData: "DrinPhone.Call"
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "DrinPhone"; ValueData: "Software\Econnet\DrinPhone\Capabilities"; Flags: uninsdeletevalue

[UninstallDelete]
Type: files; Name: "{userprograms}\DrinPhone.lnk"

[Run]
Filename: "{app}\drinphone.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; Aggiornamento dall'app (installer lanciato con /SILENT): si riapre da sola.
Filename: "{app}\drinphone.exe"; Flags: nowait skipifnotsilent
