# F0-A Windows runner (host build: Flutter + VS 2022 Build Tools, no container).
#   powershell -File spikes/f0a/run-windows.ps1 [-Flutter C:\src\flutter\bin\flutter.bat]
# SDK: official linphone-sdk-win64-5.5.39.zip from download.linphone.org, extracted
# under vendor/ (not versioned). No upstream checksum is published; this is the
# sha256 of the archive fetched on 2026-10-28.
param([string]$Flutter = "C:\src\flutter\bin\flutter.bat")
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$Zip = "linphone-sdk-win64-5.5.39.zip"
$ZipSha256 = "77dcb9007a9b304b568d9cf57ab69c9dab7c45f577d08366a747afcbef214e29"
$Sdk = "$PSScriptRoot\vendor\win64-5.5.39\linphone-sdk\win64"

if (-not (Test-Path "$Sdk\bin\liblinphone.dll")) {
    New-Item -ItemType Directory -Force vendor | Out-Null
    if (-not (Test-Path "vendor\$Zip")) {
        Invoke-WebRequest "https://download.linphone.org/releases/windows/sdk/$Zip" -OutFile "vendor\$Zip"
    }
    if ((Get-FileHash "vendor\$Zip" -Algorithm SHA256).Hash -ne $ZipSha256) { throw "sha256 mismatch: vendor\$Zip" }
    Expand-Archive "vendor\$Zip" "vendor\win64-5.5.39" -Force
}

# The SDK DLLs resolve each other through the normal DLL search order: put bin/ on PATH.
$env:Path = "$Sdk\bin;$env:Path"
$env:F0A_LIBLINPHONE = "$Sdk\bin\liblinphone.dll"
$env:F0A_RESOURCES = "$Sdk\share"
$env:F0A_MSPLUGINS = "$Sdk\lib\mediastreamer\plugins"

Set-Location probe
& $Flutter pub get
# `flutter run` relays the app's print() output; the probe calls exit(0) when done.
& $Flutter run -d windows --debug 2>&1 | Tee-Object -FilePath ..\windows-run.log
