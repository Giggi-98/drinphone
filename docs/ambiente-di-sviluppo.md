# Ambiente di sviluppo

Sviluppo sul **mini PC Ubuntu** (consigliato) o su Windows/PowerShell. iOS fa
eccezione: richiede un Mac (vedi fondo).

## Ubuntu (consigliato)
1. **Flutter SDK** — installa dal sito ufficiale (o `snap install flutter --classic`), poi `flutter doctor`.
2. **Android Studio** + Android SDK + un emulatore (o un telefono fisico in debug USB).
3. **Build desktop Linux**: `flutter config --enable-linux-desktop` e le librerie GTK richieste da `flutter doctor`.
4. **Docker** (per il banco PBX, F1): un Asterisk/FreePBX in container.
5. **Softphone di riferimento**: Linphone desktop o Zoiper, per avere l'altro capo della chiamata.
6. **liblinphone**: si aggiunge come plugin Flutter in F0 (lo fa Claude Code).

Verifica minima: `flutter doctor` senza errori bloccanti per Android e Linux.

## Windows/PowerShell (alternativa)
Stessi passi con Flutter per Windows + `flutter config --enable-windows-desktop`.
Android ok; il banco PBX gira in Docker Desktop o WSL2.

## iOS (quando ci arriverai)
**Obbligatorio un Mac con Xcode.** Senza Mac: build su cloud (Codemagic o GitHub
Actions con runner macOS). Finché non c'è, sviluppi e provi su Android + desktop.

## Usare Claude Code
- Apri Claude Code **nella cartella del repo** (così legge CLAUDE.md da solo).
- Lavora **una fase alla volta** dal `PIANO-AZIONE.md`; non saltare le verifiche.
- Ricorda a Claude di aggiornare `ARCHITECTURE.md` e `DECISIONS.md` nei commit
  che cambiano la forma del sistema (lo dice CLAUDE.md, ma ripeterlo aiuta).
- Per le chiamate: niente è "fatto" finché non l'hai provato sul banco PBX e
  **ascoltato** l'audio.

## Setup verificabile e senza distruzioni
Prima di ogni installazione `id`, `pwd`, `uname -a`, `flutter --version`, `flutter doctor -v`, `docker ps --format '{{.Names}} {{.Ports}}'`, `ss -lntup`. Non aprire porte pubbliche/alterare immagini o container esistenti. A differenza del testo introduttivo, **non assumere** plugin liblinphone ufficiale e multipiattaforma; prima F0-A.

Per Android su Linux: toolchain Flutter + Android SDK/Java compatibili con release effettiva, licenze accettate, dispositivo fisico con debug USB; `flutter devices` e `adb devices` devono individuarlo. Per Linux: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev` per shell Flutter (verificare requisiti Flutter attuali) e SDK native Linphone effettivamente disponibile.

**Server headless `/opt` vs desktop:** il server Ubuntu può ospitare Git, CI, Docker, Asterisk e test headless, ma non sostituisce un dispositivo Android con microfono/audio né un ambiente grafico desktop per verificare UI. Per Windows compilazione preferibilmente su runner Windows; iOS/macOS richiedono macOS/Xcode.

**Git:** non ignorare `pubspec.lock` per app Flutter: versionare il lockfile per build riproducibili, dopo la creazione del progetto. Tenere fuori `android/key.properties`, keystore, token e `.env`.
