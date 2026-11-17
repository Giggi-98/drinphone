# Piano prossime migliorie — DrinPhone (`IMPLEMENTATO`, `DA VALIDARE` su Windows/PBX reale)

> Aggiornato il **2026-11-17** (`0.1.17+18`): tutte le slice **A–H** e le 3 correzioni prioritarie (pulizia disinstallazione, riconciliazione BLF appesi, leggibilità `CallWindow`) sono **implementate** e verificate con test automatici (`flutter analyze` + suite completa `flutter test`). Resta la validazione su Windows interattivo e PBX Yeastar reale (`DA VALIDARE`).

---

## 0. Punto di partenza attuale

- **Appena completato (`IMPLEMENTATO`, `DA VALIDARE` su PBX reale):**
  - Pickup BLF 1-clic dalla griglia/righe `Interni` (`PhoneController.pickupExtension`, `_ExtensionTile`).
  - Busy Callback di sessione ("Avvisami appena si libera": `BusyCallbackWatch`, banner in `HomeScreen`, toast Windows in `DesktopShell`).
  - Fix overflow nei menu contestuali `showActionsMenu` (`lib/features/shell/widgets.dart`).
  - Installer locale `0.1.16` generato in `build/installer/DrinPhone-Alpha-0.1.16-setup.exe` + `update.json` firmato (release OTA GitHub `v0.1.16` non ancora pubblicata).
- **Già implementato in `0.1.15` (`IMPLEMENTATO`, `DA VALIDARE` sul campo):**
  - Contesto chiamante, filtro "Da richiamare", note post-chiamata, promemoria richiamata (`RecallReminderStore`), Screen Pop CRM HTTP/HTTPS, QoS live & Echo Test & registrazioni locali, Auto-DND (mic esterno + fasce orarie), Mini-HUD Always-on-top, import/export cifrato `.drinprof`.

---

## 1. Vertical Slice funzionali proposte (in ordine di priorità)

### Slice A — Mini-HUD 2.0 (`PROPOSTO`)
- **Obiettivo:** rendere il Mini-HUD (`HomeScreen._miniHudView`, `420×230` px) autosufficiente anche durante chiamate lunghe o IVR.
- **Cosa aggiungere:**
  1. Timer **durata chiamata live** (`callConnectedAt`) nella card di chiamata attiva dell'HUD.
  2. **Mini-tastierino DTMF** compatto a comparsa in chiamata per navigare gli IVR senza espandere l'intera finestra.
  3. **Trasferimento rapido 1-clic** (o consulta/cieco) verso uno dei preferiti visibili in chiamata.
  4. **Chip cambio presenza / DND rapido** nell'intestazione dell'HUD (oggi mostra solo lo stato DND passivo).
- **File principali:** `lib/features/shell/home_screen.dart` (`_miniHudView`), `lib/app/l10n_en.dart`, test widget dedicato.

### Slice B — Post-call Wrap-up & Promemoria rapidi (`PROPOSTO`)
- **Obiettivo:** chiudere il giro operativo della chiamata senza perdere appunti o richiamate.
- **Cosa aggiungere:**
  1. Mini-scheda opzionale **Wrap-up post-chiamata** (6–8 s a fine chiamata, chiudibile/fissabile mentre si scrive) per completare la nota e scegliere un tag esito rapido (es. *Richiamare*, *Supporto*, *Preventivo*, *Risolto*).
  2. Creazione **promemoria di richiamata 1-clic** (`Tra 15 min`, `Tra 1 ora`, `Domani alle 09:00` sfruttando `RecallReminder.nextMorning` già in `lib/core/recall_reminders.dart`) dalla chiusura chiamata e dal menu tasto destro in `HistoryView` / `CdrView`.
- **File principali:** `lib/app/phone_controller.dart`, `lib/features/call/call_window.dart`, `lib/features/history/history_view.dart`, `lib/core/call_history.dart`.

### Slice C — Command Palette `Ctrl+K` potenziata (`PROPOSTO`)
- **Obiettivo:** velocizzare tutte le operazioni frequenti da tastiera senza mouse.
- **Cosa aggiungere:**
  1. Supporto comandi con prefisso `>` (o `/`) dentro `SearchBox` (`lib/features/shell/search_box.dart`): es. `> dnd`, `> disponibile`, `> pausa code`, `> mini`, `> tema scuro`, `> pickup 208`, `> trasf 205`.
  2. Azioni rapide sulle righe risultato della ricerca: pulsante **Video** (se abilitato), **Copia numero**, e `Shift+Invio` per avviare videochiamata.
- **File principali:** `lib/features/shell/search_box.dart`, `lib/features/shell/home_screen.dart`, `lib/app/l10n_en.dart`.

### Slice D — QoS proattivo & "Stats for Nerds" in chiamata (`PROPOSTO`)
- **Obiettivo:** rendere visibili le metriche audio già raccolte (`CallAudioMetrics`) prima che l'audio si degradi o scatti il watchdog dei 20 s.
- **Cosa aggiungere:**
  1. Micro-avviso discreto nella testata di `CallWindow` quando `lossPct > 2%` o `jitterMs > 40` (*"Rete instabile · perdita X%"*).
  2. Popover cliccabile sulle tacche `_SignalBars` (`lib/features/call/call_window.dart`) con dettaglio live RX/TX, codec attivo, RTT, jitter, perdita pacchetti e micro-andamento degli ultimi campioni.
- **File principali:** `lib/features/call/call_window.dart`, `lib/app/phone_controller.dart`.

### Slice E — Audio avanzato & Suonerie (`PROPOSTO`)
- **Obiettivo:** completare il controllo audio desktop in `Preferenze`.
- **Cosa aggiungere:**
  1. Selezione file suoneria (set incluso nell'SDK + file `.wav` personalizzato via `linphone_core_set_ring` in `LinphoneFfiEngine`).
  2. Pulsante **"Prova suoneria"** sul dispositivo `Suoneria` configurato (`AudioSettings`).
  3. Regolazione guadagno microfono / volume ascolto e opzione **tono discreto in cuffia** per seconda chiamata in arrivo (avviso di chiamata).
- **File principali:** `lib/core/sip/sip_engine.dart`, `lib/core/sip/linphone_ffi_engine.dart`, `lib/core/security/settings_store.dart`, `lib/features/preferences/preferences_view.dart`.

---

## 2. Vertical Slice UX & Rifinitura grafica "Squillo" (`PROPOSTO`)

### Slice F — Riorganizzazione `Preferenze` & controllo Zoom UI
- **Problema attuale:** la scheda `Audio` in `lib/features/preferences/preferences_view.dart` accorpa 5 card diverse (dispositivi, Echo Test, codec, registrazioni locali, cifratura SRTP/ZRTP, rete/DTMF, risposta automatica, app predefinite, Screen Pop CRM, Auto-DND, scorciatoie globali).
- **Intervento:**
  1. Dividere la sezione in tre voci nette nella colonna sinistra: **Audio & Suonerie**, **Chiamate & Automazioni** (Screen Pop, Auto-DND, Risposta automatica, Scorciatoie, App predefinite), **Rete & Sicurezza** (SRTP/ZRTP/DTLS, Keep-alive, DTMF).
  2. Aggiungere il selettore visivo dello **Zoom UI** (`70% – 160%`, pulsanti `-` / `+` / `100%`) collegato ad `appZoom` (oggi accessibile solo da `Ctrl`+`+`/`−`/`0` o rotella).

### Slice G — Allineamento completo a `DESIGN.md` ("Squillo") + Toast in-app
- **Intervento:**
  1. **Migrazione token residui:** sostituire gli alias legacy (`c.side`, `c.card`, `c.field`, `c.border`, `c.text`, `c.accent`, `c.keyBtn`, `c.ok`, `c.ringing`) e gli `TextStyle(fontSize: ...)` scritti a mano con i token `DrinColors`, `DrinText` e `DrinRadius` in `home_screen.dart`, `contacts_view.dart`, `call_window.dart`, `preferences_view.dart`.
  2. **Rispetto completo di "Riduci movimento":** sostituire le durate hardcoded (`180 ms` / `220 ms`) in `StatusAvatar`, `AnimatedSectionSwitch` (`widgets.dart`) e `_Sidebar` (`home_screen.dart`) con `DrinMotion.of(context, ...)`.
  3. **Toast in-app "Squillo":** sostituire i `ScaffoldMessenger.showSnackBar` sparsi (`home_screen.dart`, `live_calls_view.dart`, `widgets.dart`) con un overlay toast compatto in basso a destra (`surface`, bordo `line`, raggio `DrinRadius.panel`, azione `Annulla` opzionale).
  4. **Rifinitura `ContactsView` & `CallWindow`:** sostituire il `DropdownButton` delle rubriche con **filtri a pillola** (`DESIGN.md` §6); in `CallWindow._toolbar` separare visivamente i controlli audio/stato da trasferimento/conferenza/registrazione; in `CallWindow._identity` aggiungere un alone morbido attorno all'avatar durante chiamata attiva.
  5. **VideoSlot & popup:** chiudere automaticamente menu/overlay aperti all'avvio di uno stream video MSOGL per evitare sovrapposizioni con le finestre native.

### Slice H — Pannello "Giornata" / Riepilogo personale
- **Cosa aggiungere:** striscia KPI collassabile in testa a `HistoryView` (calcolata localmente da `history` + `PbxCdr`): *Risposte oggi*, *Perse da richiamare* (cliccabile per applicare il filtro), *Durata media*, *Fascia oraria di picco*.

---

## 3. Validazione sul campo prima del rilascio pubblico (`DA VALIDARE`)

Riferimento completo in [PIANO-AZIONE.md](file:///c:/DrinPhone/drinphone/drinphone/PIANO-AZIONE.md):
- Test dal vivo su Yeastar P-Series reale (LAN / RAS / Cloud) per tutte le slice `0.1.13`–`0.1.16`:
  - Player audio VM/CDR (`winmm.dll` MCI) su file reali, Echo Test, registrazioni locali.
  - Controlli `Live` estesi (`extPickupCode`, pausa coda, parcheggio, consultazione `swap`/`threeway`/`complete`/`abort`, `listen`/`whisper`/`barge`).
  - Pickup BLF 1-clic da `Interni` + Busy Callback (`NOTIFY` + `30011` + toast Windows).
  - Auto-DND (Teams/Meet/Zoom + fascia oraria), Mini-HUD `TopMost`, `.drinprof` export/import tra PC diversi, Screen Pop CRM.
  - Watchdog 20 s zero-audio su chiamata interna/trunk e videochiamate reali H264/VP8 con screenshot nei due temi (`CLAUDE.md` §8).
- Quando pronto per distribuire l'aggiornamento OTA ai tester: `powershell -File tool/build_installer.ps1 -Publish`.
