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
lib/app/theme.dart                  token dello stile Squillo (DrinColors/Text/Space/Radius/Motion, DESIGN.md)
lib/app/brand.dart                  logo DRIN per tema, badge canale (Alpha) e versione
lib/core/update/updater.dart        aggiornamenti dalle GitHub Releases (manifest firmato)
lib/features/update/                pannello e finestra "Aggiornamento"
assets/brand/                       logo "Drin!" bianco monocromatico (1x, 2.0x)
lib/core/app_paths.dart             cartelle dati: %APPDATA%\Econnet\DrinPhone
lib/core/install_id.dart            ID casuale dell'installazione (supporto, solo locale)
lib/core/sip/sip_engine.dart        porta astratta SipEngine + tipi neutri
lib/core/pbx/pbx_sync.dart          registro delle voci sincronizzabili dalle API PBX
lib/core/sip/linphone_ffi_engine.dart  unico adattatore liblinphone (FFI, API C)
lib/core/security/settings_store.dart  impostazioni JSON + password in storage sicuro
lib/features/shell/home_screen.dart barra sezioni, barra composizione, griglia interni
lib/features/call/                  pannello chiamata, tastierino (anche DTMF)
lib/features/account/               editor account SIP, pannello connessioni PBX
lib/features/preferences/           Preferenze a schede (utente, audio, PBX, lingua…)
lib/features/live/                  Live Calls: chiamate in corso del PBX + colonna BLF
lib/features/contacts|history|voicemail/  rubrica, registro chiamate, casella vocale
lib/features/setup/                 scelta dell'account, procedura guidata (primo avvio, nuovo account)
lib/core/contacts/                  contatti personali + import CSV/vCard
test/                               controller e UI con FakeSipEngine
windows/                            runner Flutter; CMake installa l'SDK accanto all'exe
tool/fetch_linphone_sdk.ps1         scarica SDK in third_party/ (non versionato)
tool/build_installer.ps1            build release + installer Inno Setup + update.json firmato (-Publish: release GitHub)
tool/sign_update.dart               chiave e firma Ed25519 di update.json
release-notes/<versione>.md         note di rilascio (popup "Novità", manifest, release GitHub)
installer/                          script Inno Setup e nota Alpha per i tester
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
- **Proprio interno in profondità** (`IMPLEMENTATO`; lettura e scrittura verificate
  sul pilota via API, effetto sulle chiamate `DA VALIDARE`) — DECISIONS "Scrittura
  sul proprio interno". `extension/get` del proprio interno (`PbxSync.ownDetail`, su
  30022, su "Rileggi") → `PbxExtensionDetail`: la risposta senza segreti
  (`…pin`/`…password`, tranne gli `enb_…`), letture per campo e `PresenceSetting`
  per presenza (inoltri, squillo, cellulare, gruppi, benvenuto: su P-Series stanno
  in `presence_list`). Modifiche come copie (`withValues`/`withSetting`), `changesFrom`
  = solo campi di `YeastarApi.ownWritable` / `presenceWritable`, presenze cambiate
  intere, tipi del PBX. `PbxConnection.updateOwnExtension` → `extension/update` con
  l'id del proprio interno, poi rilettura. Il proprio interno è lo username SIP
  **solo se coincide** con `ApiCredentials.ownExtension`, scelto con le
  credenziali dall'amministratore (DECISIONS "Modello di fiducia"); altrimenti
  niente dettaglio, casella né scritture (`PbxConnection.voicemailOf` = null).
  Nuove credenziali di una connessione (`PbxConnection.replaceCredentials`):
  subito e in locale stop, dati e cache buttati (`clearData`), credenziali
  salvate; revoca del token vecchio e prima lettura in sottofondo (il dialogo
  non aspetta la rete). Avvii superati si fermano (`_gen`): gli id di un altro
  PBX non guidano le scritture.
  UI `features/preferences/own_extension.dart`
  (part di `preferences_view.dart`): bozza + "Salva sul PBX"; Presenza (stato
  attuale, inoltri, squillo, cambio per orario, più dispositivi, info in sola
  lettura), Casella vocale (impostazioni sul PBX). Chip presenza in alto.
- **Stato registrazione** — pillola in alto a sinistra (pallino e testo; dettagli nel
  tooltip), accanto alla presenza. Una sola registrazione: niente "Chiama con".
- **Dispositivi audio** (`IMPLEMENTATO`, `DA VALIDARE`) — `linphone_core_get_sound_devices`
  + set capture/playback/ringer; scelta in Preferenze > Audio, salvata in
  `settings.json` e riapplicata all'avvio.
- **Sincronizzazione PBX configurabile** (`IMPLEMENTATO`, `DA VALIDARE` sul pilota) —
  DECISIONS "Sincronizzazione PBX configurabile". `PbxSync` (`core/pbx/pbx_sync.dart`):
  extensions, voicemail, orgs, ownDetail, featureCodes, contacts, con scelte e
  predefinito; `PbxConnectionInfo.sync` / `PbxConnection.syncSettings`; `sync()`
  legge le voci accese e scadute (`_due`), il timer punta alla prima scadenza.
  UI: `_SyncSettings` in `features/account/api_dialog.dart` (radio button).
- **Connessioni PBX** (`IMPLEMENTATO`) — `PbxConnection` (`lib/core/pbx/pbx_connection.dart`),
  una per PBX, elenco id/etichetta in `settings.json`, credenziali in
  `yeastar-api[-<id>].dpapi` (`default` = file della versione singola, migrato).
  Sync adattiva (DECISIONS "Multi-PBX e sincronizzazione"); "Sincronizza ora".
  Al più una connessione per account (DECISIONS "Un account vivo alla volta"):
  avviata senza aspettare la sync (`PhoneController.connectionsStarted` per i
  test), le sezioni partono dalla cache.
- **Yeastar OpenAPI** (`IMPLEMENTATO`, verificato sul pilota) — `YeastarApi`
  (`lib/core/pbx/`): `get_token` con Client ID/Secret, refresh a 25 min, `del_token`
  all'uscita, `extension/list` paginato e `organization/list` (reparti), riletti
  ogni 60 s per la presenza. Interni del PBX uniti a quelli manuali
  (senza il proprio, max 100 in BLF). Solo Windows. Credenziali in
  `ApiCredentialStore` (DPAPI, sola scrittura dalla UI, DECISIONS 2026-10-28 bis).
- **Rubrica aziendale** (`IMPLEMENTATO`, verificato sul pilota) — `company_contact/list`
  (pagine da 500) letta ogni 6 ore anche fra un accesso e l'altro (data nella
  cache) o con "Sincronizza ora" (`sync(full: true)`), in memoria e nella cache
  cifrata (sotto); vista
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
- **Account** (`IMPLEMENTATO`; logout `DA VALIDARE` sul PBX: un-REGISTER) —
  DECISIONS "Un account vivo alla volta". Nel codice restano `Profile`/`profileId`:
  un profilo = un account, con al più una registrazione (`accounts`) e una
  connessione (`pbx`). `Settings`: i campi per-account (registrazione, connessione,
  interni manuali, preferiti, codice casella, badge) sono quelli dell'account
  **attivo**, gli altri in `others`; globali lingua, audio, diagnostica, video,
  opzioni chiamate e `defaultProfile` (predefinito all'avvio). `settings.json` =
  `{activeProfile, defaultProfile, profiles[…]}`; file senza profili letto come
  `default` e copiato in `settings.v1.json` alla prima riscrittura; profili con più
  interni divisi all'avvio (`splitProfile` in `settings_store.dart`,
  `PhoneController._splitProfiles`). Password SIP di **tutti** gli account in
  `flutter_secure_storage` (chiave per id, unico). `PhoneController.loggedIn`:
  all'avvio `autoLoginId` (unico account o predefinito) altrimenti
  `features/setup/account_picker.dart` (entra, radio predefinito, aggiungi,
  rinomina, elimina); `login/logout/createProfile/deleteProfile` mai durante una
  chiamata; logout = `setAccounts([])`, connessioni ferme (revoca token in
  sottofondo). Elimina = credenziali DPAPI e cache della connessione, registro,
  contatti. Tipo `yeastar` / `sip`: gli account SIP generici non mostrano Live
  Calls, Presenza, Integrazione PBX. Menu account in alto a destra: Preferenze,
  Rinomina, Esci (logout).
- **Account avanzato** (`IMPLEMENTATO`, `DA VALIDARE` campo per campo su PBX/trunk) —
  finestra account, sezione "Avanzate": proxy in uscita (destinazione del REGISTER
  — in liblinphone il REGISTER va solo al server dell'account, le route no — e
  route `sip:<proxy>;lr` per le chiamate, lista via `bctbx_list_new` di
  `bctoolbox.dll`; `VERIFICATO` in registrazione su Yeastar Cloud multi-tenant:
  identità `interno@tenant`, proxy SBC in TLS), registrar, utente di
  autenticazione e realm (auth info), intervallo di registrazione, registrazione
  attiva sì/no, `Privacy: id`, codice casella per account, NAT policy per account
  (STUN, ICE, TURN con credenziali in auth info). Password TURN nello storage
  sicuro (`turn_password_<id>`).
- **Opzioni globali chiamate** (Preferenze > Avanzate) — cifratura media
  (`linphone_core_set_media_encryption[_mandatory]`: in 5.5 non esiste per
  account), keep-alive, DTMF RFC 2833 / SIP INFO; applicate all'avvio.
- **Videochiamate** (`IMPLEMENTATO`; codec H264/VP8 e webcam `VERIFICATI` al caricamento
  sul pilota, chiamata video reale `DA VALIDARE`) — DECISIONS "Videochiamate".
  `SipEngine`: `dial/answer(video)`, `setCallVideo`, `setVideo` (webcam, cattura e
  visualizzazione nel core), `videoDevices`, `videoCodecs`, `setVideoWindows`;
  `CallEvent.video/remoteVideo`. Video remoto e anteprima disegnati da MSOGL
  (contesto `MSOglContextInfo`, non l'HWND) in **due finestre permanenti**
  (`core/platform/video_surface.dart`): popup di proprietà della finestra
  dell'app, create all'avvio da un **thread dedicato** con il suo ciclo di
  messaggi e consegnate al core una volta sola (mai finestra assente né cambiata a
  stream avviato: evita i blocchi tra thread dell'interfaccia e thread di disegno).
  `VideoSlot` (`features/call/`) le sposta, mostra e nasconde con comandi
  asincroni; limite: stanno sopra a menu e dialoghi Flutter.
  H264: `OpenH264` (`core/video/openh264.dart`) scarica nella cartella `codecs`
  dei dati app e verifica SHA-256 di archivio e DLL; all'avvio, se verificata,
  `SetDllDirectoryW` fa trovare `openh264.dll` al plugin `libmsopenh264` (installato
  dal CMake). Preferenze > Video; pulsante videochiamata sulle schede interni.
- **Finestra di chiamata** (`IMPLEMENTATO`, `DA VALIDARE` dal vivo) —
  `features/call/call_window.dart` al posto del vecchio pannello: scheda in arrivo
  (Rifiuta / Rispondi in video / Rispondi); in conversazione finestra grande con
  intestazione (nome, numero, durata, tacche da `linphone_call_get_current_quality`,
  Conferenza, REC, Note, riduci, schermo intero), video o avatar, pannelli in linea
  (tastiera, trasferisci, nuova chiamata, aggiungi partecipante, note) e barra
  comandi; ridotta = barra in basso a destra.
- **Registrazione chiamate** — `SipAccount.recording`: `auto` usa il codice del PBX
  letto da `feature_code/get` (`PbxConnection.recordCode`, cadenza dei reparti),
  `pbxCode` il codice dell'account, inviato in DTMF; `local` registra con
  liblinphone (file impostato nei parametri di ogni chiamata, `.mkv` in
  `Documenti\DrinPhone\Registrazioni`); `off` nasconde il pulsante.
- **Conferenza** — `linphone_core_add_all_to_conference` (API deprecata ma presente
  in 5.5): "Aggiungi partecipante" = nuova chiamata con la prima in attesa, poi
  "Unisci in conferenza"; `CallEvent.inConference`. `DA VALIDARE`.
- **Note** — testo per chiamata nel controller, salvato in `CallRecord.note`.
- **ANGLE** — `libEGL.dll`/`libGLESv2.dll` accanto all'exe (da
  `third_party/angle`, `tool/fetch_angle.ps1`): servono al filtro video `MSOGL`.
- **Badge "già visti"** — per profilo: ora dell'ultima visita al registro
  (`seenMissedAt`) e messaggi vocali visti (`seenVoicemail`, `mwi:<n>` per il solo
  MWI); entrando o restando nella sezione il badge si spegne.
- **Cache dati PBX** (`IMPLEMENTATO`, verificato sul pilota: dati a schermo in
  ~1 s dall'avvio) — `PbxCache` (`core/pbx/pbx_cache.dart`) su `DpapiBox`
  (`core/security/api_credential_store.dart`, condiviso con le credenziali):
  `pbx-cache-<connessione>.dpapi` con interni, reparti, rubrica e (formato v2)
  casella vocale, dettaglio del proprio interno, codice di registrazione, data
  dell'ultima lettura della rubrica; letta a `PbxConnection.start`, riscritta
  (file temporaneo + rinomina, una scrittura alla volta per file) solo se la sync
  trova dati cambiati o ha riletto la rubrica; codifica, DPAPI e decodifica in un
  isolate (`Isolate.run`), fuori dal thread dell'interfaccia; cancellata con la
  connessione, il profilo o nuove credenziali (dopo i salvataggi in coda).
- **BLF al rientro** — ultimi stati della sessione per account, in memoria:
  `blfOf` li usa come ripiego e `blfStale` li segnala (anello/pallino attenuato,
  "da confermare"). SUBSCRIBE a gruppi di 10 ogni 200 ms (`watchDialogs`), ridisegno
  raggruppato a 100 ms per BLF ed eventi PBX.
- **Procedura guidata** (`IMPLEMENTATO`, `features/setup/`) — al primo avvio
  (nessun account) e da "Aggiungi account" nella scelta: lingua (solo primo avvio)
  → tipo e nome → registrazione SIP (con stato) → API (solo Yeastar, facoltative)
  → audio. Annulla = account creato eliminato, ritorno alla scelta.
- **Contatti personali** (`IMPLEMENTATO`, `core/contacts/`) — per account,
  `contacts[-<profilo>].json` in chiaro come il registro; nome, azienda, email,
  numeri con etichetta. Import CSV (virgola/punto e virgola, intestazioni it/en,
  Outlook/Google) e vCard 2.1/3.0/4.0 (righe piegate, fax esclusi), anteprima e
  doppioni per numero (`sameNumber`). In Rubrica, ricerca e nome del chiamante.
- **SettingsStore** — `settings.json` (profili, come sopra) + password in
  `flutter_secure_storage`.
- **UI** — `ChangeNotifier` senza librerie di stato. Sezioni con transizioni
  animate e indicatori di stato visivi: Interni (lista locale, anello BLF SIP +
  presenza Yeastar, filtro rapido per stato BLF; pannello reparti se il PBX li
  fornisce, sola lettura), Live Calls, Rubrica, Registro chiamate, Casella
  vocale; in fondo Preferenze organizzate in 2 ambiti (`Profilo`: Account SIP e
  Integrazione PBX, Presenza, Casella vocale; `Applicazione`: Audio/Cifratura/
  Funzionalità, Diagnostica). Lingua e tema (salvati) nel menu dell'account in
  alto a destra: si applicano senza ricreare la schermata (`_Relocalize` in `main.dart`).
- **Aggiornamenti** (`IMPLEMENTATO` solo Windows; installazione dall'app `DA VALIDARE`
  con una release vera) — DECISIONS "Aggiornamenti dalle GitHub Releases". `Updater`
  (`ChangeNotifier`, in `PhoneController.updater`): `update.json` =
  `{payload, sig}`, firma Ed25519 con chiave pubblica fissata, versione > `DRIN_VERSION`
  (build `dev`: nessun controllo automatico), nome file validato, impronta SHA-256
  dell'installer. Voce "Aggiorna a x.y.z" nella barra laterale, pannello in
  Preferenze > Diagnostica.
- **Note di rilascio** (`IMPLEMENTATO`) — `release-notes/<versione>.md` (sezioni
  `## …`, voci `- …`; obbligatorio per la versione di `pubspec.yaml`, controllato
  da un test e da `build_installer.ps1`): firmato nel campo `notes` di
  `update.json` e incluso nell'app come asset. `ReleaseNotes`
  (`core/update/release_notes.dart`, solo testo) → popup a sezioni
  `features/update/release_notes_dialog.dart`: "Cosa cambia" nel pannello
  aggiornamenti (note firmate del manifest) e al primo avvio di una versione
  (note incluse; `Updater.unseenNotes`, file `notes-seen` in `%APPDATA%`).
- **Errori non gestiti** — `main.dart`: `FlutterError.onError` e
  `PlatformDispatcher.onError` in `logs/flutter-errors.log` (token/password negli
  URL oscurati) con versione e ID di installazione; `ErrorWidget` mostra il messaggio al posto del riquadro grigio.
- **Push / Yeastar** — non implementati (F4 / F6).

## 4. Flussi
- **Installer Windows (Alpha)**: `tool/build_installer.ps1` legge la versione da
  `pubspec.yaml` -> `flutter build windows --release --dart-define=DRIN_VERSION`
  -> `ISCC installer/drinphone.iss` (Release + runtime MSVC app-local) ->
  `DrinPhone-Alpha-<v>-setup.exe`, per utente in `%LOCALAPPDATA%\Programs\DrinPhone`,
  non firmato. Disinstallando restano i dati in `%APPDATA%\Econnet\DrinPhone`.
  Poi `dart run tool/sign_update.dart sign` (note da `release-notes/<v>.md`) ->
  `build/installer/update.json`; con `-Publish` `gh release create v<v>` con
  installer, manifest e le stesse note (`--notes-file`).
- **Aggiornamento**: avvio +30 s e ogni 6 ore (o "Verifica ora") -> GET
  `github.com/Giggi-98/drinphone/releases/latest/download/update.json` -> firma,
  versione, nome -> `available` -> "Installa e riavvia" (non in chiamata) ->
  download in `updates\` + SHA-256 -> installer `/SILENT /SUPPRESSMSGBOXES
  /NORESTART` -> `shutdown()` (un-REGISTER, token) -> `exit(0)`; Inno riapre l'app
  (`[Run]` `skipifnotsilent`). Cartella `updates\` svuotata al controllo successivo.
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
Flutter 3.47.8 / Dart 3.13.7; `ffi` ^2.2.0; `archive` ^4.5 (bzip2 di OpenH264) e
`crypto` ^3.0 (SHA-256); ANGLE di Qt 5.15.2 (libEGL/libGLESv2, BSD-3, per il
video; `tool/fetch_angle.ps1`); `file_selector` ^1.1.0 (scelta del
file da importare, plugin flutter.dev); `flutter_secure_storage` ^11.2.0
(Windows: richiede componente VS "C++ ATL"); `cryptography` ^2.9.0 (Ed25519 in Dart
puro, firma degli aggiornamenti); linphone-sdk-win64 5.5.39 (GPLv3 /
commerciale, `docs/licenze-e-compliance.md`); font Bricolage Grotesque, Onest e Red Hat Mono
(variabili, OFL, `assets/fonts/`, stile in `DESIGN.md`). Toolchain: VS 2022 Build Tools 17.14
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
- Nomi di schede audio/webcam non UTF-8 (code page ANSI su alcuni PC): letti in
  Latin-1 e ripassati al core con gli stessi byte (`_deviceName`/`_deviceNative`).
- Chiave privata degli aggiornamenti: solo sul PC di chi pubblica; persa = niente
  più aggiornamenti per i client installati.
- Credenziali API salvate prima del campo "Interno dell'utente" (0.1.1 e
  precedenti): niente proprio interno (presenze, inoltri, casella) finché
  l'amministratore non le reinserisce indicando l'interno.

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
