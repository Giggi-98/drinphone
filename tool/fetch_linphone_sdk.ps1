# Scarica ed estrae linphone-sdk ufficiale per Windows in third_party/ (non versionato).
#   powershell -File tool/fetch_linphone_sdk.ps1
# Belledonne non pubblica checksum: lo sha256 è quello dell'archivio scaricato il
# 2026-10-28 (vedi docs/spikes/F0-A.md). Licenza SDK: GPLv3 / commerciale, vedi
# docs/licenze-e-compliance.md prima di distribuire.
$ErrorActionPreference = "Stop"
$Version = "5.5.39"
$Zip = "linphone-sdk-win64-$Version.zip"
$Sha256 = "77dcb9007a9b304b568d9cf57ab69c9dab7c45f577d08366a747afcbef214e29"
$Dir = Join-Path $PSScriptRoot "..\third_party"
$Dest = Join-Path $Dir "linphone-sdk"

if (Test-Path (Join-Path $Dest "win64\bin\liblinphone.dll")) { "linphone-sdk $Version già presente"; exit 0 }
New-Item -ItemType Directory -Force $Dir | Out-Null
$ZipPath = Join-Path $Dir $Zip
if (-not (Test-Path $ZipPath)) {
    Invoke-WebRequest "https://download.linphone.org/releases/windows/sdk/$Zip" -OutFile $ZipPath
}
if ((Get-FileHash $ZipPath -Algorithm SHA256).Hash -ne $Sha256) { throw "sha256 non corrisponde: $ZipPath" }
# L'archivio contiene linphone-sdk/win64/...
Expand-Archive $ZipPath $Dir -Force
"linphone-sdk $Version estratto in $Dest"
