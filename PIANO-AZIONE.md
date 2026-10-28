# Piano d'azione — DrinPhone

Suite completa **a fasi**. Ogni fase: **obiettivo → passi → verifica**. Non
passare alla successiva finché la verifica non è vera. Le fasi F3→F8 sono
l'incremento della suite.

## F0 — Fondamenta
**Obiettivo:** progetto che parte su Android e desktop Linux, repo con i 4 file base.
1. Toolchain (vedi `docs/ambiente-di-sviluppo.md`): Flutter, Android Studio + emulatore, build desktop Linux abilitata.
2. Repo GitHub privato; `flutter create`; nome/bundle id; incolla qui CLAUDE.md, ARCHITECTURE.md, DECISIONS.md.
3. Integra `linphone-sdk` (plugin Flutter); l'app vuota carica il core liblinphone senza crash.
**Verifica:** `flutter doctor` verde · app vuota su emulatore Android e su Linux · core liblinphone inizializzato.

## F1 — Banco PBX (l'altro capo della chiamata)
**Obiettivo:** un PBX vero su cui provare tutto.
1. Docker con Asterisk/FreePBX in locale, due interni di test.
2. Registra un softphone di riferimento (Linphone/Zoiper) e verifica una chiamata tra due interni.
**Verifica:** dal softphone di riferimento chiami l'altro interno e **senti l'audio nei due versi**.

## F2 — Core SIP (piattaforma pilota: Android)
**Obiettivo:** DrinPhone fa e riceve una chiamata vera.
1. Servizio SIP: REGISTER verso il PBX di F1.
2. Chiamata in uscita, in entrata, risposta, hangup; macchina a stati della chiamata.
3. Audio bidirezionale (STUN; Opus + PCMA).
**Verifica:** DrinPhone ↔ softphone di riferimento, audio nei due versi; registrazione che si ristabilisce dopo caduta rete.

## F3 — MVP chiamate
**Obiettivo:** le funzioni base di un softphone, provate sul banco.
1. Hold/resume, mute, DTMF, trasferimento cieco e assistito.
2. Cronologia chiamate, multi-account, UI degli stati (screenshot, §8 di CLAUDE.md).
3. Rete cattiva: perdita pacchetti, cambio Wi-Fi↔dati.
**Verifica:** ogni funzione provata end-to-end sul banco, nei due temi.

## F4 — Mobile vero: chiamate ad app chiusa (lo scoglio)
**Obiettivo:** ricevere una chiamata con l'app TERMINATA su un telefono fisico.
1. **Decisione push** (vedi DECISIONS): verifica se Yeastar P-Series supporta il
   push SIP RFC 8599; altrimenti predisponi un **gateway push** (Flexisip o
   equivalente) + APNs/FCM.
2. CallKit (iOS) / ConnectionService (Android): schermata chiamata di sistema.
3. Background, permessi, batteria, riconnessione.
**Verifica:** telefono reale, app chiusa → la chiamata entrante squilla e si
risponde. *(iOS richiede un Mac — vedi §10.)*

## F5 — Desktop
**Obiettivo:** DrinPhone usabile da PC.
1. Build Linux (e Windows/macOS secondo i target); selezione microfono/altoparlante; ring sul device giusto.
2. Tray, avvio automatico, finestra chiamata.
**Verifica:** chiamata completa da desktop con scelta delle periferiche audio.

## F6 — Strato Yeastar P-Series + sicurezza
**Obiettivo:** funzioni UC verso Yeastar, dietro un'interfaccia separata dal nucleo SIP.
1. Integrazione API P-Series ufficiale (login/token, rubrica, presence, CDR) —
   vedi `docs/yeastar-interop.md`.
2. TLS + SRTP obbligatori verso PBX pubblici; storage credenziali sicuro; **audit di sicurezza** e report datato.
**Verifica:** presence/rubrica reali da un P-Series di test; audit §9 passato.

## F7 — Aggiornamenti & distribuzione
**Obiettivo:** i client sanno quando sono vecchi e sanno come aggiornarsi.
1. **Manifest di aggiornamento** unico (versione, note, URL artefatti firmati per
   piattaforma, versione minima supportata) letto all'avvio.
2. **Desktop:** scarica e si auto-aggiorna. **Mobile:** mostra "aggiornamento
   disponibile → store" (o via MDM). Astrai il *canale* così il modello mobile si
   sceglie dopo. Vedi `docs/aggiornamenti-e-distribuzione.md`.
**Verifica:** un client vecchio rileva la nuova versione dal manifest e agisce
secondo la piattaforma.

## F8 — Rilascio
**Obiettivo:** primo rilascio pubblico.
1. **Play Store Android** (primo bersaglio): keystore, build firmata, scheda store, review.
2. A seguire le altre piattaforme: code signing Windows, notarization macOS, App Store (serve Mac).
3. Provisioning account clienti (QR/URL), beta interna Econnet.
**Verifica:** build firmate installabili; un cliente pilota registrato e operativo.

## Revisione operativa delle fasi (2026-10-28)
**F0-A — Spike SDK/licensing (PRIMA di F0):** verificare package Flutter, API e binari nativi Android e Linux, licenze, registrazione di prova se possibile; documento `docs/spikes/F0-A.md` con `PASS/FAIL/BLOCKED`. Se manca binding, decidere plugin interno FFI/Platform Channels. Solo dopo questo gate procedere a F0-B `flutter create`.

**F0-B — Shell minima:** naming tecnico `drinphone`, bundle ID riservato a Econnet, design tokens provvisori DRIN da approvare, secure storage su Android, logging redatto, DI e interfaccia SipEngine, test fake engine.

**F1 — PBX isolation:** Asterisk Docker senza conflitti con container già esistenti. 201/202; scenario SIP valido contro softphone esterno. Verifica audio.

**F2 — Vertical slice:** singolo account su Android (nessun multi-account), REGISTER + inbound/outbound + answer/reject/hangup + audio; logging di transizione e cleanup. 20 chiamate ripetute.

**F3 — Usabilità + BLF base:** DTMF/hold/transfer, rubrica locale, SIP BLF con subscription lifecycle; se PBX non supporta BLF mostrare sconosciuto. Multi-account solo dopo stabilità.

**F4 — Spike push architetturale:** avviare la fattibilità già in parallelo a F2, non attendere la fine del core per scoprire una incompatibilità. iOS PushKit/CallKit, Android Telecom, PBX compatibilità RFC 8599, gateway, costo hosting e affidabilità: non pubblicare mobile always-on senza gate reale.

**F5 — Linux desktop:** audio devices, focus/notification/tray, session persistence e suite dispositivi reali; Windows/macOS solo dopo binding e CI.

**F6 — DRIN/Yeastar:** capability discovery, edition/firmware matrix, API client con endpoint **verificati**, eventi eventuali, rubrica. AMI solo backend Asterisk e solo su richiesta approvata. Multi-tenant test.

**F7 — Delivery:** manifest con firma, rollback, code signing e install/upgrade QA. L'implementazione auto-update differisce per sistema e tipo installer.

**F8 — Pilot-to-market:** prima beta interna, poi beta clienti solo dopo licenze e privacy, checklist security, push, SLA/supporto, branding, commercial terms e store policy.

### Ogni fase deve produrre
- codice, test, documentazione modificata nello stesso commit;
- report con `pass/fail/blocked` e dispositivi/PBX/versioni;
- issue aperte per blocchi; nessuna fase marcata completa per deduzione.

### Ordine raccomandato primo sprint
1. F0-A SDK bindings/licensing feasibility;
2. F0-B Flutter shell con engine fake;
3. F1 banco Asterisk isolato;
4. F2 demo su Android fisico;
5. F3 BLF SIP con Yeastar reale come secondo PBX.
