# ARCHITECTURE — DrinPhone

> Scheletro da riempire a partire da F0. Mantienilo contestuale ai commit
> (CLAUDE.md §6). Descrivi cosa c'è, non cosa vorresti.

## 1. Sintesi
Softphone Flutter. Motore: liblinphone (linphone-sdk 5.5.39) via `dart:ffi`.
Piattaforma pilota: **Windows desktop** (DECISIONS 2026-10-28). Nucleo SIP
standard; strato Yeastar non ancora presente. UI: proposta D (struttura a pannelli).

Stato: `IMPLEMENTATO` = codice presente e compilato; `DA VALIDARE` = non ancora
provato contro un PBX reale con audio nei due versi (CLAUDE.md §5).

## 2. Albero del progetto
```
lib/main.dart                       bootstrap: AppPaths -> PhoneController -> HomeScreen
lib/app/phone_controller.dart       stato UI (registrazione, chiamata, impostazioni)
lib/app/theme.dart                  palette D chiaro/scuro (DrinColors)
lib/core/app_paths.dart             cartelle dati: %APPDATA%\Econnet\DrinPhone
lib/core/sip/sip_engine.dart        porta astratta SipEngine + tipi neutri
lib/core/sip/linphone_ffi_engine.dart  unico adattatore liblinphone (FFI, API C)
lib/core/security/settings_store.dart  impostazioni JSON + password in storage sicuro
lib/features/shell/home_screen.dart barra sezioni, barra composizione, griglia interni
lib/features/call/                  pannello chiamata, tastierino (anche DTMF)
lib/features/account/               editor account SIP, pannello connessioni PBX
lib/features/preferences/           Preferenze a schede (utente, audio, PBX, lingua…)
lib/features/live/                  Live Calls: chiamate in corso del PBX + colonna BLF
lib/features/contacts|history|voicemail/  rubrica, registro chiamate, casella vocale
lib/features/setup/                 procedura guidata (primo avvio, nuovo profilo)
lib/core/contacts/                  contatti personali + import CSV/vCard
test/                               controller e UI con FakeSipEngine
windows/                            runner Flutter; CMake installa l'SDK accanto all'exe
tool/fetch_linphone_sdk.ps1         scarica SDK in third_party/ (non versionato)
spikes/f0a/                         spike F0-A (non prodotto)
```

## 3. Moduli
- **SipEngine** (`IMPLEMENTATO`; REGISTER, uscente, entrante e audio bidirezionale
  `VERIFICATO` su Windows contro Yeastar via RAS/TCP, `docs/test/2026-10-28-windows-yeastar-ras.md`;
  resto `DA VALIDARE`) — interfaccia: start, register,
  unregister, dial, answer, hangup, mute, DTMF; eventi `RegistrationEvent` e
  `CallEvent`. La UI non vede tipi liblinphone.
- **LinphoneFfiEngine** — core creato con config `NULL` (nessun `linphonerc`),
  `iterate()` ogni 20 ms da timer Dart: tutti i callback sul thread UI. Porte SIP
  locali casuali, video disattivato. Più chiamate contemporanee, per id.
- **Macchina a stati chiamata** — `CallPhase`: incoming / outgoing / active /
  paused / ended / error, mappata dagli stati `LinphoneCallState`; `Released` libera
  il puntatore. Attesa (`linphone_call_pause/resume`) e trasferimento cieco
  (`linphone_call_transfer_to`, REFER) con esito dal callback transfer-state
  (`DA VALIDARE` sul PBX). **Più chiamate**: id = indirizzo del LinphoneCall; avviso
  di chiamata (rispondere mette in attesa la conversazione), scambio, trasferimento
  assistito (`consult` = attesa + nuova chiamata, poi `linphone_call_transfer_to_another`,
  REFER con Replaces). `DA VALIDARE` sul PBX via RAS.
- **BLF SIP** (`IMPLEMENTATO`; stato Libero `VERIFICATO` su Yeastar via RAS) —
  `watchDialogs(numeri)`: una SUBSCRIBE `Event: dialog` (600 s, `Accept:
  application/dialog-info+xml`) per interno della lista locale, a registrazione OK;
  NOTIFY -> `DialogInfoTracker` (`lib/core/sip/dialog_info.dart`, regex senza
  espansione di entità, full/partial) -> `BlfStatus` unknown/idle/ringing/busy.
  `<state>unregister</state>` di Yeastar -> `offline` (Non registrato).
  Subscription terminata o rifiutata: stato sconosciuto con motivo, ritentata al
  rinnovo REGISTER successivo. Registrazione caduta: tutto sconosciuto.
- **Account SIP multipli** (`IMPLEMENTATO`, verificato solo l'account principale) —
  `SipEngine.setAccounts`, eventi di registrazione per account, `dial(numero,
  accountId)`; `Settings.accounts` (password per account nello storage sicuro,
  `main` = chiave storica), account ↔ connessione PBX in Preferenze > Utente.
- **Eventi PBX in tempo reale** (`IMPLEMENTATO`, `DA VALIDARE` sul pilota) —
  `PbxConnection.setRealtime`: WebSocket `wss://…/openapi/v1.0/subscribe`, topic
  30007/30008/30009/30011/30022, heartbeat, riconnessione; interruttore in
  Preferenze > Integrazione PBX. Presenza via 30009 `VERIFICATA` sul pilota.
- **Live Calls** (`IMPLEMENTATO`; eventi osservati sul pilota, riaggancio `DA VALIDARE`) —
  `PbxConnection.liveCalls`: evento 30011 (membri per identità — interno per numero,
  tratte per estremi — perché `channel_id` cambia; i `BYE` escono; dopo un BYE con al
  più un capo rimasto la chiamata è finita: Yeastar manda `[extension:BYE,
  outbound:ANSWER]` e nient'altro). `call/query?type=inbound|outbound|internal` dopo
  la sottoscrizione, 2 s dopo ogni chiamata nuova e ogni 15 s finché ce ne sono:
  toglie le chiamate sparite e dà il tipo. `visibleCalls`: una riga per coppia di
  capi (il PBX dà id diversi a tratta trunk e tratta dell'interno), direzione da
  tratte trunk, poi interni noti, poi tipo. Log: solo tipo e stato dei membri.
  Inizio = prima volta vista, durata da prima risposta. Vista `features/live/`:
  tabelle "Entranti e interne" / "Uscenti", scelta del PBX, colonna BLF a gruppi
  (Preferiti + reparti, attivi/totale); solo lettura, nessun controllo di chiamata.
- **Presenza in profondità** (`IMPLEMENTATO`, verificato sul pilota) — `extension/get`
  del proprio interno (cadenza dei reparti, su 30022, su "Rileggi"): presenza e testo,
  per ognuna delle 6 presenze gli inoltri interni/esterni (sempre, nessuna risposta,
  occupato → destinazione), timeout squillo, cellulare in contemporanea, gruppi di
  squillo, impostazioni casella vocale. **Sola lettura** (DECISIONS 2026-10-28 bis):
  `vm_pin` arriva nella risposta e viene scartato nel parse. Preferenze > Presenza e
  Casella vocale; chip presenza in alto.
- **Chiama con** — menu in alto a sinistra (come "Call Using" di Linkus): account SIP
  per i numeri liberi (`Settings.callWith`, '' = principale) con stato di registrazione.
- **Dispositivi audio** (`IMPLEMENTATO`, `DA VALIDARE`) — `linphone_core_get_sound_devices`
  + set capture/playback/ringer; scelta in Preferenze > Audio, salvata in
  `settings.json` e riapplicata all'avvio.
- **Connessioni PBX** (`IMPLEMENTATO`) — `PbxConnection` (`lib/core/pbx/pbx_connection.dart`),
  una per PBX, elenco id/etichetta in `settings.json`, credenziali in
  `yeastar-api[-<id>].dpapi` (`default` = file della versione singola, migrato).
  Sync adattiva (DECISIONS "Multi-PBX e sincronizzazione"); "Sincronizza ora"
  per connessione o globale. PBX dell'account SIP = host uguale al dominio SIP
  (o unica connessione): solo i suoi interni sono chiamabili e in BLF.
- **Yeastar OpenAPI** (`IMPLEMENTATO`, verificato sul pilota) — `YeastarApi`
  (`lib/core/pbx/`): `get_token` con Client ID/Secret, refresh a 25 min, `del_token`
  all'uscita, `extension/list` paginato e `organization/list` (reparti), riletti
  ogni 60 s per la presenza. Interni del PBX uniti a quelli manuali
  (senza il proprio, max 100 in BLF). Solo Windows. Credenziali in
  `ApiCredentialStore` (DPAPI, sola scrittura dalla UI, DECISIONS 2026-10-28 bis).
- **Rubrica aziendale** (`IMPLEMENTATO`, verificato sul pilota) — `company_contact/list`
  (pagine da 500) letta con i reparti ogni 10 min, **solo in memoria**; vista
  `features/contacts/` con menu delle phonebook e un pulsante Chiama per numero
  (fax esclusi). `nameFor(numero)` dà il nome del chiamante da interni e rubrica
  (cifre finali se ≥ 7 cifre). Errori di reparti/rubrica non bloccano gli interni.
- **Casella vocale** (`IMPLEMENTATO`, verificata sul pilota via API) — `vm/get` del
  proprio interno a ogni sync (60 s) sulla connessione del PBX dell'account;
  ripiego SIP MWI (`message-summary`, callback account + NOTIFY). Yeastar via RAS
  invia NOTIFY fuori dialogo senza `Message-Account` (liblinphone non lo abbina)
  e risponde 500 alla SUBSCRIBE esplicita: lì vale solo l'API. Ascolto = chiamata
  al codice configurabile (default `*2`).
- **Preferiti** — stella sulle schede (al passaggio del mouse o se attiva), salvati
  in `settings.json` come `<connessione>:<numero>`; vista "Preferiti" nel pannello
  reparti o, senza pannello, filtro a stella nell'intestazione.
- **Reparti: solo membri diretti** — casella nell'intestazione di un reparto:
  `extIds` meno quelli dei sotto-reparti diretti (non salvata).
- **Lingua** — `tr('testo italiano')` + `l10n_en.dart`; scelta in Preferenze,
  immediata (rebuild di MaterialApp) e salvata in `settings.json`; un test
  verifica che ogni chiave abbia la traduzione.
- **UI** — Segoe UI Variable + Cascadia Mono; schede compatte a simboli
  (anello = stato linea, badge = presenza, testo nei tooltip); pagine (60 interni,
  50 contatti/registro); ricerca con popup sotto il campo (frecce/Invio/Esc).
- **Registro chiamate** (`IMPLEMENTATO`) — `CallHistoryStore` (`lib/core/call_history.dart`):
  `history[-<profilo>].json` locale, per profilo, ultime 200 chiamate, salvataggi in coda; persa = entrante
  non risposta. Vista `features/history/` con filtri tipo (tutte/in arrivo/perse/
  in uscita), periodo (oggi/7/30 giorni/tutto) e nome/numero.
- **Ricerca** — il campo in alto filtra la griglia per nome/numero; Invio chiama
  il numero o l'unico interno trovato.
- **Attenzione chiamata entrante** (Windows) — `WindowAttention` (user32 via FFI):
  ripristina la finestra, `SetForegroundWindow`, `FlashWindowEx` sulla barra.
  Nessuna notifica toast (servirebbe un plugin/WinRT).
- **Profili** (`IMPLEMENTATO`; cambio profilo `DA VALIDARE` sul PBX: un-REGISTER
  degli account lasciati) — DECISIONS "Profili". `Settings`: i campi per-profilo
  (account, connessioni PBX, interni manuali, preferiti, "Chiama con", codice
  casella) sono quelli del profilo **attivo**, gli altri in `others`; globali
  lingua, audio, diagnostica. `settings.json` = `{activeProfile, profiles[…]}`;
  file senza profili letto come profilo `default` ("Econnet" se aveva API) e
  copiato in `settings.v1.json` alla prima riscrittura. Password SIP di **tutti**
  i profili in `flutter_secure_storage` (chiave per id account, unico). Tipo
  `yeastar` / `sip`: i profili SIP generici non mostrano Live Calls, Presenza,
  Integrazione PBX. `PhoneController.switchProfile/createProfile/deleteProfile`:
  mai durante una chiamata; elimina = credenziali DPAPI delle sue connessioni,
  registro, contatti. Menu in alto a destra.
- **Account avanzato** (`IMPLEMENTATO`, `DA VALIDARE` campo per campo su PBX/trunk) —
  finestra account, sezione "Avanzate": proxy in uscita (route `sip:<proxy>;lr`,
  lista via `bctbx_list_new` di `bctoolbox.dll`), registrar, utente di
  autenticazione e realm (auth info), intervallo di registrazione, registrazione
  attiva sì/no, `Privacy: id`, codice casella per account, NAT policy per account
  (STUN, ICE, TURN con credenziali in auth info). Password TURN nello storage
  sicuro (`turn_password_<id>`).
- **Opzioni globali chiamate** (Preferenze > Avanzate) — cifratura media
  (`linphone_core_set_media_encryption[_mandatory]`: in 5.5 non esiste per
  account), keep-alive, DTMF RFC 2833 / SIP INFO; applicate all'avvio.
- **Procedura guidata** (`IMPLEMENTATO`, `features/setup/`) — al primo avvio
  (nessun account in nessun profilo) e da "Nuovo profilo…": lingua → tipo e nome →
  account (con stato di registrazione) → API (solo Yeastar, facoltative) → audio.
- **Contatti personali** (`IMPLEMENTATO`, `core/contacts/`) — per profilo,
  `contacts[-<profilo>].json` in chiaro come il registro; nome, azienda, email,
  numeri con etichetta. Import CSV (virgola/punto e virgola, intestazioni it/en,
  Outlook/Google) e vCard 2.1/3.0/4.0 (righe piegate, fax esclusi), anteprima e
  doppioni per numero (`sameNumber`). In Rubrica, ricerca e nome del chiamante.
- **SettingsStore** — `settings.json` (profili, come sopra) + password in
  `flutter_secure_storage`.
- **UI** — `ChangeNotifier` senza librerie di stato. Sezioni: Interni (lista locale,
  pallino e testo da BLF SIP + presenza Yeastar; pannello reparti solo se il PBX
  li fornisce, sola lettura), Live Calls, Rubrica, Registro chiamate, Casella
  vocale; in fondo Preferenze (schede Utente, Presenza, Casella vocale, Audio,
  Funzionalità — solo segnaposto —, Integrazione PBX, Lingua, Diagnostica).
- **Push / Yeastar / Update** — non implementati (F4 / F6 / F7).

## 4. Flussi
- **Avvio**: `AppPaths` -> `SettingsStore.load()` -> `engine.start(dataDir, logDir,
  debug)` -> se c'è un account `engine.register()`.
- **Registrazione**: Preferenze > Utente -> `saveAccount` (password nello storage
  sicuro) -> `clear_accounts` + `auth_info` + `account_params` (server =
  `sip:<dominio>`, trasporto UDP/TCP/TLS) -> evento registrazione -> chip in alto.
- **Uscente**: campo/scheda -> `dial(numero)` -> `linphone_core_invite` (numero
  completato col dominio dell'account) -> eventi -> `CallPanel`.
- **Entrante**: callback `IncomingReceived` -> `CallPanel` con Rispondi/Rifiuta.
- **Live Calls**: sottoscrizione WebSocket OK -> `call/query` (3 tipi) -> eventi
  30011 -> `liveCalls` -> `LiveCallsView` (timer 1 s per le durate).
- **API PBX**: Preferenze > Integrazione PBX -> `ApiCredentialStore.save` -> `get_token` ->
  `extension/list` -> griglia Interni + `watchDialogs`. Uscita dall'app
  (`AppLifecycleListener.onExitRequested`) -> `del_token` + `engine.stop()` (un-REGISTER).
- **Log di debug**: flag nelle impostazioni, attivo al prossimo avvio:
  `linphone_logging_service` a livello Debug su `logs/linphone.log` (rotazione 10 MB).

## 5. Dipendenze
Flutter 3.47.8 / Dart 3.13.7; `ffi` ^2.2.0; `file_selector` ^1.1.0 (scelta del
file da importare, plugin flutter.dev); `flutter_secure_storage` ^11.2.0
(Windows: richiede componente VS "C++ ATL"); linphone-sdk-win64 5.5.39 (GPLv3 /
commerciale, `docs/licenze-e-compliance.md`). Toolchain: VS 2022 Build Tools 17.14
(C++ + ATL), Windows SDK 10.0.26100.

## 6. Punti di attenzione
- Il core cerca grammatiche belr e plugin WASAPI sotto `<exe>\linphone\`; senza
  quei file abort o nessuna scheda audio (F0-A punti 2 e 6).
- Log di debug = messaggi SIP completi (numeri, header Authorization digest). Non
  contengono la password in chiaro ma vanno trattati come dati personali.
- `history.json` contiene numeri e nomi in chiaro (dati personali locali): da
  includere nella policy privacy prima di distribuire.
- Il log su file è bufferizzato: con kill del processo le ultime righe si perdono.
- Nessun STUN/ICE configurato: audio unidirezionale probabile dietro NAT (F2).
- TLS: CA di `share/linphone/rootca.pem` dell'SDK; nessun pinning.
- Una sola istanza: due avvii contemporanei condividerebbero DB e log.

## 7. Architettura target (PROPOSTA, non implementata)
```
UI Flutter (Dialer/Call/Contacts/BLF/Settings/Diagnostics)
  ├── State controllers (sessione/account/call/presence)
  ├── Application use cases
  │     ├── CallService -> SipEngine interface -> Native Linphone bridge (DA VALIDARE F0-A)
  │     ├── BlfService -> SIP SUBSCRIBE/NOTIFY oppure Unknown
  │     ├── ContactsService -> Local + ProviderAdapter
  │     └── PbxCapabilities -> Generic SIP / Yeastar P-Series provider
  ├── Local storage (secure credentials, preferences, call history)
  └── Platform adapters (audio routes, telecom UI, native notifications, updater)
         [futuro backend Econnet: provisioning, privileged API broker, push gateway]
```

**Stato:** `SipEngine`, adattatore liblinphone, storage sicuro e UI base esistono (sezioni 2–4); `BlfService`, `ContactsService`, `PbxCapabilities`, provider Yeastar, push e updater sono ancora solo proposta.

### Confini e regole di dipendenza
- `SipEngine` è porta astratta; un solo adattatore incapsula la SDK nativa; non esporre i tipi liblinphone alla UI.
- `PbxCapabilities` impedisce funzioni non permesse; il Generic SIP adapter non richiede endpoint Yeastar.
- Provider Yeastar si basa solo su OpenAPI pubblica/ufficiale per edition; token privilegiati rimangono su backend.
- `BlfService` usa prima la subscription SIP dialog e tratta le sessioni non supportate come `unknown`.
- Push gateway è un componente separato, opzionale **solo per prototipo foreground**; blocco per distribuzione mobile always-on.
- Nessuna assunzione che Flutter plugin terzi supportino le 5 piattaforme: milestone F0-A valida binding, licensing e artefatti.

### Percorsi suggeriti DOPO lo spike
```
lib/app/                 # bootstrap, navigation, DI
lib/features/dialer/     # UI e stato
lib/features/call/       # chiamata e controller
lib/features/contacts/   # rubrica
lib/features/blf/        # BLF e lifecycle
lib/features/settings/   # configurazione account
lib/core/sip/            # contratti senza riferimenti native
lib/core/pbx/            # capabilities e provider
lib/core/security/       # secure storage e redaction
packages/drinphone_linphone_bridge/  # eventuale plugin privato con binding nativi
integration_test/        # test device/PBX
```
Creare cartelle solo se il modulo è in sviluppo. Risultato reale dello spike in `docs/spikes/F0-A.md`.

### Flusso chiamata minimal
`UI -> CallController -> SipEngine -> native SDK -> PBX -> RTP` con eventi SDK riportati verso UI attraverso stream a stati; retry SIP e chiamate separate, niente retry di INVITE alla cieca.

### Flusso BLF
`Account registrato -> SUBSCRIBE -> NOTIFY -> parser dialog -> stato (idle/ringing/busy/unknown) -> UI`; timer rinnovi, unsubscribe e backoff gestiti dentro servizio.

### Flusso UC
`User -> ProviderCapabilities -> YeastarAdapter (backend per scope privilegiati) -> OpenAPI/eventi`; non blocca il core SIP quando backend offline.
