# Installatore Windows della Alpha: build release + Inno Setup + update.json
# firmato (aggiornamenti dalle GitHub Releases, lib/core/update/updater.dart).
#   powershell -File tool/build_installer.ps1 -Notes "Cosa cambia"
#   powershell -File tool/build_installer.ps1 -Notes "Cosa cambia" -Publish
# Prerequisiti: Flutter, Visual Studio Build Tools (C++), linphone-sdk e ANGLE
# (tool/fetch_linphone_sdk.ps1, tool/fetch_angle.ps1), Inno Setup 6
# (winget install JRSoftware.InnoSetup). Versione letta da pubspec.yaml: alzarla
# prima di ogni pubblicazione, i client accettano solo versioni più recenti.
# Chiave di firma: %USERPROFILE%\.drinphone\update-signing.key (o $env:DRIN_UPDATE_KEY),
# creata una volta con `dart run tool/sign_update.dart keygen <file>`. Mai nel repo.
# -Publish crea la release v<versione> su GitHub con installer e update.json:
# i client la vedono come "latest" (serve gh: winget install GitHub.cli; gh auth login).
# Uscita: build/installer/DrinPhone-Alpha-<versione>-setup.exe (non firmato:
# SmartScreen avvisa al primo avvio) e build/installer/update.json.
param([string]$Notes = "", [switch]$Publish)
$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$Line = Select-String -Path (Join-Path $Root "pubspec.yaml") -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $Line) { throw "version: non trovata in pubspec.yaml" }
$Version = $Line.Matches[0].Groups[1].Value.Split('+')[0]
# PowerShell 5.1 non passa gli argomenti vuoti agli eseguibili.
if (-not $Notes) { $Notes = "DrinPhone Alpha $Version" }

$Iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Iscc) { throw "Inno Setup 6 non trovato: winget install JRSoftware.InnoSetup" }

# Runtime MSVC accanto all'exe: i PC dei tester possono non avere il redistributable.
$Crt = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\x64\Microsoft.VC14*.CRT",
                     "$env:ProgramFiles\Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\x64\Microsoft.VC14*.CRT" -Directory -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
if (-not $Crt) { throw "Runtime MSVC (VC\Redist) non trovato: installa Visual Studio Build Tools C++" }

$Key = if ($env:DRIN_UPDATE_KEY) { $env:DRIN_UPDATE_KEY } else { "$env:USERPROFILE\.drinphone\update-signing.key" }
if (-not (Test-Path $Key)) { throw "Chiave di firma degli aggiornamenti non trovata: $Key" }

Push-Location $Root
try {
    flutter build windows --release "--dart-define=DRIN_VERSION=$Version"
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows fallito" }
    & $Iscc "/DAppVersion=$Version" "/DCrtDir=$($Crt.FullName)" "installer\drinphone.iss"
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup fallito" }
    $Setup = "build\installer\DrinPhone-Alpha-$Version-setup.exe"
    $Manifest = "build\installer\update.json"
    dart run tool/sign_update.dart sign $Key $Setup $Version $Notes $Manifest
    if ($LASTEXITCODE -ne 0) { throw "firma di update.json fallita" }
    if ($Publish) {
        gh release create "v$Version" $Setup $Manifest --title "DrinPhone Alpha $Version" --notes $Notes
        if ($LASTEXITCODE -ne 0) { throw "gh release create fallito" }
    }
} finally {
    Pop-Location
}
Get-Item (Join-Path $Root "build\installer\DrinPhone-Alpha-$Version-setup.exe"), (Join-Path $Root "build\installer\update.json")
