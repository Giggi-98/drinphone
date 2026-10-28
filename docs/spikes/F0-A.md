# F0-A — SDK/bridge feasibility report
**Stato:** ESEGUITO PARZIALMENTE (2026-10-28). Windows PASS e Linux PASS sul
percorso eventi; Android build PASS, runtime BLOCKED (nessun dispositivo).
Windows diventa piattaforma pilota (vedi `DECISIONS.md` 2026-10-28).
Nessuna prova SIP reale
(F1 non esiste ancora): REGISTER verso porta chiusa, solo per esercitare gli eventi.

## Ambiente
- Host: Windows 11 Pro (workstation) + Docker Desktop 29.7.2. Tutto gira nel
  container usa-e-getta `drinphone-spike:f0a` (`spikes/f0a/Dockerfile`, Ubuntu 24.04).
  Inizialmente avviato su server Ubuntu, spostato sulla workstation per risorse.
- Flutter 3.47.8 stable (framework 737ba8f885, engine dfd2e6cb7d), Dart 3.13.7,
  OpenJDK 17.0.20.1. Android: AGP 9.1.0, Kotlin 2.4.0, Gradle 9.3.1,
  NDK r28c (28.2.13676358), SDK Platform/Build-Tools 36.
- SDK native:
  - Android: `org.linphone:linphone-sdk-android:5.5.39` (AAR) dal repo ufficiale
    Belledonne `https://download.linphone.org/maven_repository` (non Maven Central).
  - Linux: nessun pacchetto SDK Linux binario ufficiale individuato; usate le
    librerie dentro `Linphone-6.2.4-x86_64.AppImage`
    (`https://download.linphone.org/releases/linux/app/`, sha256
    `585c6cc4…dacf6c`), che riportano `linphone_core_get_version()` = **5.5.36**.
  - Windows: **SDK ufficiale** `linphone-sdk-win64-5.5.39.zip`
    (`https://download.linphone.org/releases/windows/sdk/`, 301 MB, nessun checksum
    pubblicato upstream; sha256 locale `77dcb900…214e29`): `liblinphone.dll`,
    header C, `.lib`, grammatiche belr, plugin mediastreamer (WASAPI, openh264, webrtc).
  - Windows host: Flutter 3.47.8 nativo (`C:\src\flutter`), VS 2022 Build Tools
    17.14 (MSVC, Windows SDK 10.0.26100), nessun container.
- Plugin Flutter valutati: **nessuno** usato. Bridge scritti nello spike
  (`spikes/f0a/probe/`): Platform Channels → Kotlin su Android, `dart:ffi` → API C
  su Linux e Windows.
- Licenze: POM 5.5.39 dichiara **GPLv3**; Linphone desktop/AppImage GPLv3.
  Transitive (dall'AppImage): mbedTLS, opus, libsrtp/bzrtp, openh264, liboqs, Qt6
  (solo app desktop, non usate dal bridge), xerces-c, soci, sqlite, … — inventario
  completo con licenze **ancora da fare** (vedi `docs/licenze-e-compliance.md`).

## Matrice
| Target | Binding candidato | Init core | Eventi → Dart | REGISTER (API) | Call audio | License reviewed | Esito |
|---|---|---|---|---|---|---|---|
| Android | Platform Channels + AAR 5.5.39 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NO (GPLv3 dichiarata) | BUILD PASS, RUNTIME BLOCKED |
| Linux | dart:ffi + liblinphone.so.10 (5.5.36, da AppImage) | PASS | PASS | PASS (Progress→Failed, atteso) | NOT RUN | NO | PASS (eventi) |
| iOS | — | — | — | — | — | NO | OUT OF SCOPE |
| Windows | dart:ffi + liblinphone.dll (5.5.39, SDK ufficiale win64) | PASS | PASS | PASS (Progress→Failed, atteso) | NOT RUN (WASAPI caricato, nessun PBX) | NO | PASS (eventi) |
| macOS | — | — | — | — | — | NO | OUT OF SCOPE |

## Evidenze
Comandi (da `spikes/f0a/`, Git Bash su Windows o bash su Linux):
```
./run.sh image     # exit 0 — immagine 2.6 GB
./run.sh android   # exit 0 — "✓ Built build/app/outputs/flutter-apk/app-debug.apk"  (log: android-build.log)
./run.sh extract   # exit 0 — sha256 OK, AppImage estratta in vendor/ (non versionata)
./run.sh linux     # exit 0 — log: linux-run.log
```
Windows (PowerShell, dalla root del repo):
```
powershell -File spikes/f0a/run-windows.ps1   # "√ Built …\drinphone_f0a_probe.exe", log: windows-run.log
```
Output Windows: stessa sequenza di Linux con `INIT version=5.5.39`; belle-sip
logga `Cannot connect to [TCP://127.0.0.1:5999]` (porta chiusa, atteso).

APK debug: 270 MB, sha256 `c7d39381…ceda`, contiene `liblinphone.so` e
`libmediastreamer2.so` per arm64-v8a, armeabi-v7a, x86_64.

Output Linux (righe `F0A`, `linux-run.log`):
```
EVENT global state=1 msg=Starting up
INIT version=5.5.36
EVENT global state=4 msg=Configuring
REGISTER_REQUESTED domain=127.0.0.1:5999
EVENT global state=2 msg=On
EVENT registration state=1 msg=Registration in progress
EVENT registration state=4 msg=io error
EVENT global state=3 msg=Shutdown
EVENT registration state=0 msg=io error
EVENT global state=0 msg=Off
DESTROYED
DONE
```
Nel container non c'è scheda audio (`Could not find a suitable soundcard`):
atteso, e il motivo per cui l'audio resta NOT RUN.

## Limitazioni / problemi trovati (e come risolti nello spike)
1. **Android, Kotlin**: `CoreListenerStub` vuole override che ritornano `Unit`;
   un expression body su `Handler.post` (Boolean) non compila. Fix: body a blocco.
2. **Linux, risorse**: liblinphone cerca `<top_resources_dir>/belr/grammars`; il
   default compilato punta al prefix di build → `bctbx-fatal Unable to load VCARD
   grammar` e abort. Fix: `linphone_factory_set_top_resources_dir()` prima di
   `create_core_3`. Il prodotto dovrà distribuire `share/belr/grammars` e impostarlo.
3. **Linux, data dir**: liblinphone non crea `~/.local/share/linphone`; senza,
   il DB sqlite non si apre e `linphone_core_start` ritorna **-2**. Il prodotto
   dovrà creare/impostare la propria data dir.
4. **Linux, librerie**: `LD_LIBRARY_PATH` sull'intera `usr/lib` dell'AppImage
   sostituisce la glib di sistema e rompe GTK (`g_once_init_leave_pointer`).
   Non serve: liblinphone ha `RUNPATH $ORIGIN`, basta aprirla per percorso assoluto.
   Le librerie dell'AppImage sono un ripiego da spike, non un artefatto distribuibile:
   per il prodotto serve una build SDK Linux propria (CMake linphone-sdk) o
   pacchetto ufficiale.
5. **Windows host**: bind mount non permette `chmod` all'utente 1000 e Git Bash
   riscrive i path; `run.sh` gestisce entrambi. `.gitattributes` forza LF su
   `*.sh`/Dockerfile.

6. **Windows, audio**: nell'SDK win64 WASAPI è un *plugin* mediastreamer
   (`lib/mediastreamer/plugins/libmswasapi.dll`). Senza
   `linphone_factory_set_msplugins_dir()` il core non vede nessuna scheda audio
   (`Could not find a suitable soundcard`). Con la cartella impostata l'errore sparisce.
   `libmsopenh264.dll` fallisce con errore 126: manca `openh264.dll` (codec video
   Cisco, non redistribuito nell'SDK). Irrilevante per l'audio; da decidere se/come
   offrire video.
7. **Windows, DLL**: le 35 DLL dell'SDK si risolvono tra loro con il normale
   ordine di ricerca; nello spike `bin/` è in `PATH`. Il prodotto dovrà copiarle
   accanto all'exe (install CMake del runner Windows).

## Alternative FFI / Platform Channels
- Android: la API Java/Kotlin richiede un `Context` → Platform Channels (o JNI
  generato) è la strada naturale; FFI puro sulla `.so` è possibile ma perde il
  wrapper Java ufficiale.
- Linux (e plausibilmente Windows/macOS): `dart:ffi` sull'API C funziona; servono
  binding generati (`ffigen` sugli header linphone) invece di lookup a mano.
- Due bridge diversi dietro un'unica interfaccia `SipEngine` sono gestibili.

## Raccomandazione
**GO per Windows** (pilota) sul binding `dart:ffi` + SDK ufficiale: init, eventi,
API e plugin audio dimostrati; manca la chiamata con audio reale, che richiede F1.
Linux: GO tecnico, sorgente SDK da decidere. Android: compila, runtime da provare.

## Issue, owner, next action
| # | Azione | Owner | Note |
|---|---|---|---|
| 1 | Eseguire l'APK su telefono Android fisico (o emulatore) e raccogliere logcat `F0A` | Luigi | serve `adb`/platform-tools sull'host o device in rete |
| 2 | Decidere sorgente SDK Linux (build CMake linphone-sdk vs pacchetto ufficiale) | Econnet | AppImage solo per spike |
| 3 | Inventario licenze transitive + contatto Belledonne per licenza commerciale | Econnet | release blocker |
| 4 | Windows: bundle DLL+share+plugins accanto all'exe nel runner CMake (F0-B) | — | oggi via PATH |
| 5 | Dopo F1 (Asterisk): REGISTER reale + chiamata con audio nei due versi | — | non prima |
