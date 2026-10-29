# ANGLE (libEGL.dll + libGLESv2.dll) per il video: il filtro di visualizzazione
# MSOGL dell'SDK disegna con OpenGL ES tramite EGL e senza queste DLL non mostra
# nulla (log: "Fail to load EGL plugin libEGL.dll: error 126").
#   powershell -File tool/fetch_angle.ps1
# Fonte: installatore ufficiale Linphone 5.3.4 (firmato Belledonne Communications),
# che contiene l'ANGLE di Qt 5.15.2 (DLL firmate The Qt Company). Impronte fissate
# il 2026-10-29: installatore e DLL; dipendono solo da Windows/MSVC, nessuna API
# di rete. Licenza ANGLE: BSD-3 (docs/licenze-e-compliance.md). Serve 7-Zip.
# Estrae in third_party/angle/ (non versionato); il CMake del runner le copia
# accanto all'exe. DECISIONS 2026-10-29 "ANGLE per il video".
$ErrorActionPreference = "Stop"
$Installer = "Linphone-5.3.4-win64.exe"
$Url = "https://download.linphone.org/releases/windows/app/$Installer"
$Sha = @{
    $Installer      = "89f67157aaa469a5af18e06f5eb5aedb6f73776efd29f30be4e09ceb427ad266"
    "libEGL.dll"    = "32092de077fd57b6ef355705ec46c6d21f6d72fbe3d3a5dd628f2a29185a96fa"
    "libGLESv2.dll" = "50fad5605b3d57627848b3b84a744dfb6a045609b8236b04124f2234676758d8"
}
$Dir = Join-Path $PSScriptRoot "..\third_party"
$Dest = Join-Path $Dir "angle"

function Test-Sha($Path, $Name) {
    (Test-Path $Path) -and ((Get-FileHash $Path -Algorithm SHA256).Hash.ToLower() -eq $Sha[$Name])
}

if ((Test-Sha (Join-Path $Dest "libEGL.dll") "libEGL.dll") -and
    (Test-Sha (Join-Path $Dest "libGLESv2.dll") "libGLESv2.dll")) { "ANGLE già presente"; exit 0 }

$SevenZip = "$env:ProgramFiles\7-Zip\7z.exe"
if (-not (Test-Path $SevenZip)) { throw "7-Zip non trovato: $SevenZip" }
New-Item -ItemType Directory -Force $Dest | Out-Null
$InstallerPath = Join-Path $Dir $Installer
if (-not (Test-Sha $InstallerPath $Installer)) {
    Invoke-WebRequest $Url -OutFile $InstallerPath
}
if (-not (Test-Sha $InstallerPath $Installer)) { throw "sha256 non corrisponde: $InstallerPath" }
# Solo estrazione (nessuna esecuzione dell'installatore).
& $SevenZip e -y "-o$Dest" $InstallerPath "bin\libEGL.dll" "bin\libGLESv2.dll" | Out-Null
foreach ($n in "libEGL.dll", "libGLESv2.dll") {
    if (-not (Test-Sha (Join-Path $Dest $n) $n)) { throw "sha256 non corrisponde: $n" }
}
"ANGLE estratto in $Dest"
