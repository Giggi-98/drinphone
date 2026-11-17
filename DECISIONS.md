# DECISIONS — DrinPhone

Registro **append-only**. Non modificare né cancellare voci: per ribaltarne una,
aggiungi una voce nuova in cima che cita la vecchia. Il campo chiave è
**"Da rivedere se"**.

---

## 2026-11-17 · Selezione BLF unica e impegno diretto al clic (`IMPLEMENTATO`, `DA VALIDARE` su PBX reale)
Ribalta/semplifica la voce precedente `2026-11-17 · Estensione BLF: Trunk logici (VoIP/FXO/ISDN)`:
1. **Selezione BLF unica (`FunctionKeyKind.blf`):** rimosso il tipo separato `trunk` dall'interfaccia (in `FunctionKey.fromJson` i vecchi `'trunk'` migrano automaticamente a `blf`). Un unico tasto BLF riconosce in automatico interni, codici funzione `*8XX`/`*9XX` e nomi di linea/trunk (compresi trunk numerici riconosciuti da `knownTrunkNames` o con `dialCode`), dando priorita' in `_watched` ai tasti BLF configurati prima della griglia interni fino a `maxBlf`.
2. **Impegno diretto e motivo rifiuto PBX visibile:** se `dialCode` (accessorio e opzionale) e' vuoto, il clic su un BLF impegna direttamente `target` sul PBX (`dial(target)`). Se il PBX rifiuta la `SUBSCRIBE` (es. `404 Not Found` osservato in `linphone.log` su Yeastar S-Series verso `TG100-Acc`, dove i trunk SIP/account senza hint Seize-Line o SLA `<interno>_<trunk>` restituiscono `404`), il sottotitolo mostra `Stato sconosciuto (<motivo>)` senza falsare un verde fittizio.
   - **Da rivedere se:** il PBX attiva un feed OpenAPI `trunk/list` (Yeastar P-Series) da affiancare al `SUBSCRIBE` SIP.

## 2026-11-17 · Estensione BLF: Trunk logici (VoIP/FXO/ISDN), impegno linea (`dialCode`) e codici Yeastar `*8XX`/`*9XX` (`IMPLEMENTATO`, `DA VALIDARE` su PBX reale)
Estende la voce `2026-11-17 · Tasti funzione / BLF accanto alla barra di composizione`:
1. **Monitoraggio Trunk e codici funzione (`FunctionKeyKind.trunk`, `FunctionKeyKind.blf`, `LinphoneFfiEngine._sipAddressFor`):** i tasti `trunk` (e i `blf` con nome logico non numerico o codice `*8XX`/`*9XX`) vengono inclusi in `PhoneController._watched` ed emettono `SUBSCRIBE Event: dialog` verso `<target>@<host>` con percent-encoding RFC 3261 della parte userinfo quando il nome logico contiene spazi o caratteri non sicuri, mantenendo la chiave originale per il matching dei `NOTIFY` (`DialogInfoTracker`). Su integrazione Yeastar, `blfOfNumber` e `trunkLiveCalls` integrano le chiamate attive da `liveCalls` (`LiveMember.trunk`) per mostrare anche lo stato e gli interlocutori del trunk.
2. **Impegno della linea (`FunctionKey.dialCode`, `PhoneController.seizeTrunk`):** poiche' un nome logico trunk non e' un numero SIP componibile, il campo opzionale `dialCode` specifica il prefisso/codice PBX per impegnare la linea (al clic o tramite il dialogo *Chiama tramite questa linea…* -> `<dialCode><numero>`). I codici `*8XX`/`*9XX` compongono direttamente `target` senza anteporre `extPickupCode`.
   - **Da rivedere se:** un PBX Yeastar reale espone gli stati di linee FXO/ISDN/SIP solo tramite `SUBSCRIBE` con formato userinfo diverso o richiede uno specifico header/URI di trunk dialing.

## 2026-11-17 · Tasti funzione / BLF accanto alla barra di composizione (`IMPLEMENTATO`, `DA VALIDARE` su PBX reale)
1. **Accesso rapido in top bar (`HomeScreen._functionKeysButton`, `FunctionKeysPanel`):** pulsante pillola `BLF` subito accanto a `SearchBox` che evidenzia eventuali squilli (`c.squillo`) o linee occupate (`c.busy`) e apre un pannello laterale destro affiancato su finestre larghe (persistito in `viewFlag('fnKeys.open')`) o modale sotto `940 px`.
2. **Tipologie supportate (`FunctionKeyKind` in `SettingsStore`):** `blf` (BLF interno con `SUBSCRIBE dialog` automatica in `_watched`, pickup 1-clic se squilla, trasferimento cieco se in chiamata attiva o chiamata diretta), `speedDial` (chiamata rapida / trasferimento), `dtmf` (invio sequenza DTMF in chiamata, es. apri-portone), `park` (parcheggio/ripresa slot), `pickup` (codice o pickup diretto), `dnd` e `queuePause` (su integrazione Yeastar).
   - **Scartato:** aprire solo un menu popup temporaneo — un pannello affiancabile consente di osservare i LED BLF in tempo reale mentre si lavora nelle altre viste.

## 2026-11-17 · Auto Preview video in arrivo (Early Media videocitofono) (`IMPLEMENTATO`, `DA VALIDARE` su videocitofono/PBX reale)
1. **Meccanismo SIP (`LinphoneFfiEngine.acceptEarlyMedia`):** quando arriva una chiamata con offerta video (`CallEvent.remoteVideo == true`), se `VideoOptions.autoPreviewIncoming` e `videoEnabled` sono attivi e non ci sono altre chiamate `active`/`outgoing`, `PhoneController._onCall` chiama `acceptEarlyMedia(id, video: true)`. Nell'adattatore FFI usa le API reali di `linphone-sdk 5.5.39` (`linphone_call_accept_early_media_with_params` con `linphone_call_params_enable_video(1)`, `linphone_call_params_enable_camera(0)`, `linphone_call_params_set_video_direction(RecvOnly)`). In `answer(id, video)` imposta esplicitamente camera e `video_direction` (`SendRecv` o `Inactive`) per non ereditare la modalità solo ricezione.
2. **UI in arrivo (`CallWindow._incoming`):** quando `call.earlyMedia && call.video && p.videoEnabled`, sostituisce l'avatar squillante con il riquadro `VideoSlot(surface: p.remoteSurface)` (`420 px` card, `210 px` preview) e il tag `Auto Preview` nell'header sopra il video (mai sovrapposto all'HWND nativo), mantenendo i pulsanti *Rifiuta*, *Rispondi in video* e *Rispondi*.
   - **Scartato:** aprire una risposta automatica mutata (`200 OK`) — chiude l'invito sugli altri interni in un gruppo di squillo e apre il microfono/tariffazione sul PBX.
   - **Da rivedere se:** specifici videocitofoni non supportano `183 Session Progress` con video o richiedono un elenco di interni/whitelist per evitare il preview su normali videochiamate tra colleghi.

## 2026-11-17 · Pulizia disinstallazione, riconciliazione BLF, restyling CallWindow e Piano Migliorie A–H (`IMPLEMENTATO`, `DA VALIDARE` su Windows/PBX reale)
1. **Disinstallazione completa Windows (`installer/drinphone.iss`):** aggiunto `CloseApplications=force`, `taskkill /F /IM drinphone.exe` prima della rimozione file (l'app ridotta nella tray altrimenti blocca `{app}`), pulizia ricorsiva `DelTree('{app}')` in `usPostUninstall` e dialogo interattivo in `InitializeUninstall()` per scegliere se conservare o eliminare i profili utente in `{userappdata}\Econnet\DrinPhone` (default: conserva).
2. **Eliminazione stati "squilla" appesi (`DialogInfoTracker`, `PbxConnection`, `PhoneController`):** normalizzato il parsing XML `dialog-info` (`FULL`/`PARTIAL`, `EARLY`/`TERMINATED` case-insensitive); potati i ring group `30011` rimasti senza rami vivi e accelerato il controllo periodico `call/query` a 4 s finché esistono chiamate in squillo; svuotato lo stato live al disconnect WS e riconciliato in `PhoneController._blfFresh` un eventuale `BlfStatus.ringing` SIP precedente allo snapshot `call/query` se l'interno non ha più chiamate attive.
   - **Da rivedere se:** il PBX dovesse emettere eventi SIP BLF con clock/latenza superiori a 2 s dopo l'inizio effettivo di uno squillo rispetto allo snapshot REST.
3. **Leggibilità CallWindow & QoS proattivo (Slice D):** aggiunto scrim opaco dietro la modale, bordi `c.line`, header ad alto contrasto con avviso `Rete instabile` cliccabile per aprire il pannello `Qualità rete (QoS)` (ultimi 20 campioni `CallAudioMetrics` + RX/TX/Jitter/Perdita/RTT), identità su card `surface` con alone di stato, e chiusura automatica di eventuali `PopupRoute` aperti quando si attiva il video nativo MSOGL (Slice G).
4. **Workflow operatore (Slices A, B, C, H):**
   - **Mini-HUD 2.0:** altezza `264 px`, presenza/DND rapido nell'header, timer chiamata live, mini-tastierino DTMF e trasferimento 1-clic verso i preferiti.
   - **Post-call Wrap-up & Promemoria CDR:** mini-scheda a fine chiamata (`8 s` auto-hide, fissabile/editabile) con tag rapidi (`[Richiamare]`, `[Supporto]`, `[Preventivo]`, `[Risolto]`), nota e promemoria `15 min` / `1 ora` / `Domani 09:00`; aggiunti promemoria rapidi anche alle righe `CdrView`.
   - **Command Palette `>` / `/` (`SearchBox`):** comandi testuali (`> disponibile`, `> dnd`, `> pausa code`, `> mini`, `> tema scuro/chiaro`, `> preferenze`, `> pickup <n>`, `> trasf <n>`) + azioni rapide Copia/Video (`Shift+Invio`).
   - **Pannello Giornata (`HistoryView`):** aggiunti *durata media* e *picco orario* nella barra riepilogo.
5. **Audio avanzato & Preferenze "Squillo" (Slices E, F, G):**
   - **API verificate su `linphone-sdk 5.5.39` (`third_party/linphone-sdk/win64/include/linphone/core.h`):** `linphone_core_set_mic_gain_db`, `linphone_core_set_playback_gain_db`, `linphone_core_set_ring`, `linphone_core_play_local`, `linphone_core_stop_ringing` per scelta suoneria (SDK + `.wav` locale), prova suoneria, guadagni `-10..+15 dB` e tono discreto in cuffia su seconda chiamata entrante.
   - **Preferenze & Token:** divisa la colonna in **Audio & Suonerie**, **Chiamate & Automazioni**, **Rete & Sicurezza**, **Video**, **Diagnostica** (mantenendo `initialTab: 3` su `Audio & Suonerie`), aggiunto selettore **Zoom interfaccia**, sostituito il dropdown rubriche con filtri a pillola in `ContactsView`, e allineati `DrinMotion.of(context, ...)` e `snackBarTheme`.

## 2026-11-16 · Azioni BLF su Interni: Pickup 1-clic & Busy Callback ("Avvisami appena si libera") (`IMPLEMENTATO`, `DA VALIDARE` su PBX reale)
1. **Pickup BLF 1-clic da `Interni` (`PhoneController.pickupExtension`, `_ExtensionTile`):** quando un interno squilla (`BlfStatus.ringing` o `LiveState.ringing`) e il PBX espone `extPickupCode` (`feature_code/get`), la scheda/riga mostra il pulsante `squillo` (`c.squillo` / `c.onSquillo`) e la voce nel menu contestuale per rispondere subito con `<extPickupCode><interno>`.
   - **Scartato:** limitare il pickup alla sola vista `Live` (l'utente passa gran parte del tempo su `Interni`).
2. **Busy Callback lato client (`PhoneController.toggleBusyWatch`, `BusyCallbackWatch`, `HomeScreen._busyCallbackBanner`, `DesktopShell._busyToasts`):** monitoraggio effimero di sessione (non persistito, azzerato al logout) su interni occupati (`BlfStatus.busy`); al rientro a `BlfStatus.idle` senza chiamate live `30011` sull'interno, mostra un banner in-app e un toast Windows con `Chiama ora` / `Chiudi`.
   - **Scartato:** inviare `SUBSCRIBE` o codici proprietari `CCBS` lato PBX (dipendenza da firmware/trunk eterogenei e permessi operatore); l'osservazione su BLF/WebSocket già aperti è a costo zero sul PBX.
   - **Da rivedere se:** in futuro si desidera persistenza tra riavvii o accodamento automatico lato PBX.

## 2026-11-16 · Esportazione & Importazione profilo cifrato `.drinprof` (`IMPLEMENTATO`, `DA VALIDARE` su Windows interattivo)
1. **Formato portabile cifrato (`lib/core/security/profile_bundle.dart`):** busta JSON `drinprof-v1` cifrata con `PBKDF2-HMAC-SHA256` (120.000 iterazioni di default, sale 16 byte casuali) + `AES-256-GCM` (`package:cryptography`), con passphrase utente obbligatoria di almeno 8 caratteri e controllo anti-DoS sul numero di iterazioni in apertura.
2. **Controllo granulare ed isolamento:** all'esportazione l'utente sceglie se includere password SIP, credenziali PBX API/CDR e contatti personali; le credenziali API/CDR restano gestite esclusivamente dentro `PhoneController` / `ProfileBundleCodec` (mai esposte o stampate nei log). All'importazione tutti gli ID interni di profilo, account e connessioni PBX vengono rigenerati (rimappando `pbxId` e `favorites`) e sostituiti al profilo segnaposto vuoto se si tratta del primo avvio.
   - **Scartato:** esportazione in JSON in chiaro o basata su DPAPI (legato al singolo PC Windows e quindi non portabile tra colleghi/postazioni).

## 2026-11-16 · Auto-DND intelligente & Mini-HUD compatto Always-on-top (`IMPLEMENTATO`, `DA VALIDARE` su Windows/PBX reale)
1. **Auto-DND su microfono esterno e fascia oraria (`lib/core/platform/mic_busy_monitor.dart`, `PhoneController.evaluateAutoDnd`):** su Windows interroga in sola lettura `HKCU\...\CapabilityAccessManager\ConsentStore\microphone` tramite `win32_registry` (`LastUsedTimeStop == 0` escludendo `drinphone`) solo quando nessuna chiamata DrinPhone è attiva, oltre a valutare la fascia oraria configurata (`isWithinDndSchedule`). Quando scatta, imposta `do_not_disturb` sul PBX (`extension/update`) salvando lo stato precedente per ripristinarlo al termine e blocca `autoAnswer` finché è attivo.
   - **Scartato:** hooking audio globale a basso livello (COM WASAPI `IAudioSessionManager2`) finché il Registro Privacy di Windows garantisce il rilevamento per app senza dipendenze C++.
   - **Da rivedere se:** Teams/Zoom su future versioni Windows mantengono il dispositivo microfono aperto anche a microfono mutato in call.
2. **Mini-HUD compatto Always-on-top (`WindowAttention.setMiniHud`, `HomeScreen._miniHudView`):** ridimensiona e fissa la finestra esistente via `SetWindowPos(HWND_TOPMOST)` (`420×230` px in alto a destra, salvando le dimensioni originali) senza creare una seconda finestra/engine Flutter; mostra chiamata attiva/entrante o composizione rapida + fino a 6 preferiti con pallino BLF live.

## 2026-11-16 · Audio Intelligence: QoS live in chiamata, Echo Test microfono Win32 e archivio registrazioni locali (`IMPLEMENTATO`, `DA VALIDARE` su PC Windows/PBX)
1. **QoS RTP & codec negoziato live (`SipEngine.callAudioMetrics`, `CallAudioMetrics`):** in `LinphoneFfiEngine` riusiamo gli header reali di `linphone-sdk 5.5.39` (`linphone_call_get_audio_stats`, `download_bandwidth`, `upload_bandwidth`, `local_loss_rate`, `receiver_interarrival_jitter`, `round_trip_delay`, `linphone_call_params_get_used_audio_payload_type`), letti nello stesso tick da 1 s già usato dal watchdog audio (`_watchAudio`) senza thread o timer nativi extra.
2. **Echo Test microfono (`MicEchoTester`, `WindowsMciEchoRecorder` in `lib/core/platform/audio_player.dart`):** registrazione fino a 5 s su file WAV temporaneo via `winmm.dll` MCI (`waveaudio`) e riascolto immediato su `InAppAudioPlayer` (`cacheFile: false`) dietro interfaccia testabile `EchoRecorderBackend`, senza aggiungere dipendenze native.
   - **Da rivedere se:** un driver audio Windows rifiuta MCI `waveaudio` o serve porting Linux/macOS (estendere `EchoRecorderBackend`).
3. **Archivio registrazioni locali (`recordingsDir` in `Preferenze > Audio`):** `InAppAudioPlayer.togglePlay(..., cacheFile: false)` evita che i file permanenti dell'utente vengano eliminati in `dispose()`; i `.wav`/`.mp3` si riproducono inline, mentre i `.mkv` vengono aperti/evidenziati in Esplora file (`explorer.exe /select,`).

## 2026-11-16 · Contesto chiamante, perse da richiamare, note post-chiamata, promemoria e Screen Pop CRM (`IMPLEMENTATO`, `DA VALIDARE` su Windows)
Richiesto da Luigi di procedere con la prima vertical slice delle nuove funzionalità desktop:
1. **Contesto chiamante + perse da richiamare + modifica note post-chiamata:** calcolati localmente in `PhoneController` sullo storico (`history`) del profilo attivo, così funzionano anche offline o con account SIP generici senza dipendere dal CDR remoto. Una chiamata persa resta "da richiamare" finché non segue sullo stesso numero una chiamata risposta o una richiamata uscente.
   - **Da rivedere se:** in team multi-postazione si vorrà considerare "richiamata" anche la risposta avvenuta da un altro interno sul CDR del PBX (`cdr_basic`).
2. **Promemoria di richiamata locali (`lib/core/recall_reminders.dart`):** persistenza JSON locale per profilo (`recall-reminders.json` in `AppPaths`), banner in-app + notifica toast Windows (`DesktopShell`) con conferma `Chiama ora` (`pendingCallLink`) o rinvio di 15 min.
   - **Scartato:** dipendere da Task Scheduler di Windows o notifiche schedulate esterne non controllabili dallo stato in-app.
   - **Da rivedere se:** l'utente vuole i promemoria sincronizzati tra più PC.
3. **Screen Pop CRM HTTP/HTTPS (`lib/core/platform/screen_pop.dart`):** validazione stretta (`scheme` solo `http`/`https`, host non vuoto, `{number}` e `{name}` codificati con `Uri.encodeQueryComponent`), apertura su Windows tramite `ShellExecuteW` (`shell32.dll`) senza passare da `cmd.exe`, con apertura automatica all'arrivo chiamata **spenta di default**.
   - **Scartato:** esecuzione di schemi/comandi arbitrari da stringa utente (`javascript:`, `file:`, eseguibili locali) per prevenire command/URI injection da configurazioni errate o condivise.

## 2026-11-13 · Ergonomia desktop & operatore (v0.1.13-dev): player audio Windows MCI, controlli Live avanzati, audio hot-swap/codec, risposta automatica e scorciatoie globali Win32
Richiesto da Luigi di completare le funzionalità tecniche e desktop rimandando alla fine la sola parte commerciale/vendita.
1. **Player audio in-app (`lib/core/platform/audio_player.dart`):** riproduzione dei messaggi vocali (`vm/download`) e delle registrazioni CDR (`recording/list` + `recording/download`) tramite API Win32 native `mciSendStringW` (`winmm.dll`) dietro interfaccia testabile `AudioBackend`, con file temporanei nella cache app e pulizia allo scarico/chiusura.
   - **Scartato:** dipendenze esterne con codec/runtime aggiuntivi o apertura automatica del player di Windows ad ogni ascolto (l'utente perde controllo dentro DrinPhone); scrivere su disco file permanenti non richiesti (il salvataggio resta un'azione esplicita).
   - **Da rivedere se:** si apre il porting macOS/Linux (aggiungere un `AudioBackend` specifico per piattaforma).
2. **Operazioni avanzate pannello `Live`:** pickup diretto su BLF che squillano (`feature_code/get` `ext_pickup`/`pickup` → composizione codice+interno), stato pausa agente nelle code (`queue/agent_pause` / `agent/pause`), ripresa rapida parcheggio e trasferimento con consultazione (`call/transfer` `type: "attended"` + `attended_operate`: `swap`/`threeway`/`complete`/`abort`) dall'elenco chiamate.
   - **Da rivedere se:** Yeastar cambia i campi di `feature_code/get` o `queue/agent_pause` in versioni firmware future (ogni chiamata resta `DA VALIDARE` contro PBX reale).
3. **Audio desktop e scorciatoie globali:** callback nativo `linphone_core_cbs_set_audio_devices_list_updated` + ripristino automatico dei dispositivi salvati in `Settings.audio`, priorità/abilitazione codec audio via `linphone_core_set_audio_payload_types` / `linphone_payload_type_enable`, risposta automatica opzionale in `CallOptions` (solo se nessuna chiamata attiva/uscente), e scorciatoie globali Win32 opzionali (`RegisterHotKey` disattivate di default nel runner Windows, `Ctrl+Alt+D` passa da `pendingCallLink` con finestra di conferma).
   - **Scartato:** composizione immediata senza conferma su `Ctrl+Alt+D` (rischio di chiamare testo arbitrario dagli appunti); scorciatoie globali attive di default (possibili conflitti con altre app Windows).
   - **Da rivedere se:** su alcune macchine USB/Bluetooth Windows WASAPI non notifica `audio_devices_list_updated` fuori chiamata (valutare `IMMNotificationClient` nativo) o un'altra app occupa le combinazioni scelte.

## 2026-11-13 · Sezione "Live" (pannello operatore): trasferimento cieco drag & drop, controllo chiamate e monitoraggio condizionale
Cita "Modello di fiducia: utente finale meno fidato dell'amministratore" (2026-10-30).
Richiesto da Luigi: rinominare "Chiamate in corso" in **"Live"** e dotare la
vista delle funzioni da pannello operatore Yeastar:
1. **Drag & drop di una chiamata attiva** verso un interno (colonna destra) o
   verso le destinazioni in basso (`Gruppi di squillo`, `Code`, `Parcheggio`,
   `Casella vocale di gruppo`) per eseguire un **trasferimento cieco**
   (`POST /openapi/v1.0/call/transfer`, `type: "blind"`).
2. **Menu contestuale (tasto destro)** sulle chiamate in corso con `Trasferisci`,
   `Riaggancia` (`call/hangup`), `Registra` (`call/record_start`), `Parcheggia`
   (`call/transfer` verso slot di parcheggio) e **monitoraggio** (`Intromettiti` /
   `barge`, `Ascolta` / `listen`, `Suggerisci` / `whisper` via
   `POST /openapi/v1.0/call/listen` con `monitor: ownExtension`).
3. **Vincolo di sicurezza e permessi sul monitoraggio:** le voci `Ascolta`,
   `Suggerisci` e `Intromettiti` compaiono e sono invocabili **solo** se:
   - l'account SIP coincide con `ownExtension` fissato dall'amministratore nelle
     credenziali API (`voicemailOf != null`), **e**
   - l'interno ha il monitoraggio attivo sul PBX (verificato sui gruppi interni
     `extensiongroup/list` + `extensiongroup/query`: `mgr_enb_monitor` /
     `mgr_enb_ext_monitor` per `role: "manager"`, `user_enb_monitor` /
     `user_enb_ext_monitor` per `role: "user"`, `enb_monitor` /
     `enb_ext_monitor` per `role: "custom"`, oppure sul dettaglio dell'interno
     `extension/get`), e i relativi codici funzione (`enb_listen`, `enb_whisper`,
     `enb_barge_in` in `feature_code/get`) non sono disabilitati.
**Scartato:** mostrare sempre `Listen`/`Whisper`/`Barge In` lasciando fallire
la chiamata API (viola la richiesta esplicita e il modello di fiducia: la chiave
OpenAPI è amministrativa e `call/listen` accetterebbe qualsiasi `monitor` se non
filtrato dal client); usare codici funzione SIP `*51`/`*52`/`*53` al posto di
`call/listen` (non permettono di scegliere lo specifico `channel_id` quando un
interno ha più chiamate).
**Da rivedere se:** Yeastar introduce un token OpenAPI per singolo utente con
permessi applicati lato server, o cambia lo schema di `extensiongroup/query`.

## 2026-11-11 · Chiamata chiusa dal client dopo 20 s senza audio in arrivo
Segnalato da Luigi: se riaggancia l'altro capo o il PBX la chiamata resta
aperta in DrinPhone. Dai log (10/11, 18:11): audio in arrivo a zero, nessun
BYE dal PBX, il nostro BYE 4 s dopo riceve 200 OK; quando il BYE arriva il
motore chiude bene (4 casi su 4). **Scelta:** watchdog nel `PhoneController`:
ogni secondo legge i kbit/s RTP ricevuti (`linphone_call_get_audio_stats`);
chiamata attiva e non in attesa a zero per 20 s → riaggancio e avviso
"Chiamata chiusa: nessun audio dall'altro capo". Soglia scelta da Luigi.
**Scartato:** `rtp/nortp_timeout` di liblinphone (comportamento e messaggio
di fine non controllabili dall'app, nessun avviso chiaro); session timer più
corto (rinnovo ogni N secondi, carico sul PBX e non aiuta se il PBX stesso
tiene viva la sessione); attendere solo il BYE (il bug).
**Da rivedere se:** si trova perché il PBX non manda il BYE (allora va
corretto lì); codec con soppressione del silenzio (Opus DTX, CN) o reti con
buchi lunghi chiudono chiamate vive; chiamate solo video.

## 2026-10-30 · CDR come la pagina del PBX: pagine e ordinamento sul server
Cita "CDR: `cdr_basic` (CDR Advanced) prima di `cdr`". **Scelta:** il CDR
nell'app ricalca la pagina CDR del PBX: totale (`COUNT(*)` con lo stesso
WHERE), pagine numerate, ordinamento fatto da MySQL su un elenco fisso di
colonne (Ora di default dalla più recente), filtri Da/A separati e tutti gli
esiti. Le gambe (`cdr_clip`) si leggono con una seconda query solo per le
righe della pagina; il dettaglio della chiamata le mostra senza un'altra
lettura. Esportazione CSV dall'app (fino a 10.000 righe, a blocchi di 500).
**Scartato:** "Carica altre" con ordinamento nell'app (ordina solo ciò che
è già scaricato, nessun totale); JOIN con `cdr_clip` nella query principale
(una riga per gamba, pagine sbagliate); sottoquery correlate per trunk e DID
(una per riga e per colonna); colonna di ordinamento passata dalla UI come
testo (iniezione).
**Da rivedere se:** il `COUNT(*)` con il filtro sul proprio interno diventa
lento su PBX con molto traffico (allora totale stimato o solo "pagina
successiva"), o Yeastar documenta il formato di `queues`/`ringgroups`/`ivrs`.

## 2026-10-30 · CDR: `cdr_basic` (CDR Advanced) prima di `cdr`
Cita "CDR dal database del PBX (Database Grant)". **Scelta:** il registro del
PBX legge `cdr_basic` quando esiste e ricade su `cdr` solo sui firmware che
non ce l'hanno. Sul pilota (83.25) `cdr` si è fermata al 29/01/2026 (passaggio
al CDR Advanced): con "Ultimi 7 giorni" non c'era nulla. Le chiamate del
proprio interno includono quelle dove l'interno compare solo come gamba
(`cdr_clip`: squillo di un gruppo o di una coda), come nel CDR del PBX.
**Scartato:** leggere solo `cdr` (vuota dopo l'aggiornamento); unire `cdr` e
`cdr_basic` (righe doppie nel periodo di passaggio, formati diversi);
`cdr_clip` come elenco principale (una riga per gamba: un gruppo da 8 interni
= 8 righe).
**Da rivedere se:** Yeastar cambia lo schema di `cdr_basic`/`cdr_clip`, o la
sottoquery sulle gambe diventa lenta su PBX con molto traffico.

## 2026-10-30 · Link telefonici: sempre con conferma, senza prendersi i link
**Scelta:** i link `tel:`, `callto:`, `sip:`, `sips:` aprono DrinPhone (istanza
unica, `WM_COPYDATA`) ma il numero si chiama **solo dopo conferma** nell'app.
L'installatore registra DrinPhone come **app candidata** (ProgID +
`RegisteredApplications`); è l'utente a sceglierla nelle app predefinite di
Windows. Da `sip:utente@dominio` si prende solo la parte prima di `@` e si
chiama dal proprio PBX; nomi non numerici si scartano.
**Scartato:** chiamata immediata al click (una pagina web può aprire un link
verso un numero a pagamento); scrivere `HKCU\Software\Classes\tel` per
prendersi i link da soli (Windows lo ignora per `tel:` e scavalca la scelta
dell'utente); chiamare il dominio del link sip: (chiamate verso server
sconosciuti, fuori dalle regole del PBX); named pipe o socket locale per
l'istanza unica (`WM_COPYDATA` basta, nessuna porta aperta).
**Da rivedere se:** serve il click-to-call senza conferma da un CRM fidato
(-> opzione esplicita), o l'istanza unica va portata su macOS/Linux.

## 2026-10-30 · CDR dal database del PBX (Database Grant)
**Scelta:** il registro chiamate legge anche il **CDR del PBX** collegandosi
al suo MySQL con **Database Grant** (Yeastar P-Series: porta 3306, utente e
password generati dal PBX, IP consentiti), tabella `cdr`, sola lettura, a
pagine da 50 con statement preparati. Credenziali inserite
dall'amministratore (dialogo "Database CDR"), cifrate DPAPI per connessione
(`pbx-db-<id>.dpapi`), mai mostrate. Di default **solo il proprio interno**
(`voicemailOf`, legato all'interno scelto dall'amministratore); il CDR di
**tutto il PBX** solo se l'amministratore lo concede (opzione salvata con le
credenziali), coerente con "Modello di fiducia".
Libreria: `mysql_client` 0.0.27 (BSD-3, Dart puro, TLS, `caching_sha2`).
**Rischio accettato:** la libreria cifra con TLS ma **non verifica il
certificato** del PBX: protegge da ascolto passivo, non da un server falso;
da usare in LAN/VPN con gli IP consentiti sul PBX. Chi ha le credenziali del
database può leggere quello che Database Grant concede (non solo `cdr`).
**Scartato:** `mysql1` (pub.dev dice MIT ma il file `LICENSE` è **GPL v2**:
copyleft evitabile); API Yeastar per il CDR (non dà il CDR di tutto il PBX
con le stesse colonne); mostrare all'utente il CDR di tutti senza consenso
dell'amministratore (dati personali dei colleghi).
**Da rivedere se:** serve il CDR fuori dalla LAN (→ gateway Econnet o
verifica del certificato), Yeastar cambia lo schema della tabella `cdr`, o la
libreria non è più mantenuta.

---

## 2026-10-30 · Identità visiva "Squillo" (sostituisce la palette della proposta D del 2026-10-28)
**Scelta:** stile **Squillo** con la densità del **Centralino**: "Drin!" è il
suono dello squillo, quindi lo squillo è il marchio. Blu DRIN del logo come
colore principale (prima l'accento era verde acqua, scollegato dal logo);
giallo riservato a ciò che squilla; presenze come spie; righe dense col
puntatore e larghe al tocco. Font inclusi nell'app (Bricolage Grotesque,
Onest, Red Hat Mono, OFL) invece di quelli di sistema, per avere lo stesso
aspetto su Windows, Android, iOS e macOS. Token e regole in `DESIGN.md`,
riferimento grafico `docs/design/drin-design-system.html`.
**Scartato:** direzione "Centralino" pura (precisa ma fredda) e "Voce"
(accogliente ma mostra pochi interni); font di sistema (Segoe esiste solo su
Windows); un pacchetto di componenti esterno (lo stile deve restare nostro).
**Da rivedere se:** il marchio DRIN cambia, test con utenti mostrano che la
densità al tocco non basta, o un font non copre una lingua da supportare.

---

## 2026-10-30 · Modello di fiducia: utente finale meno fidato dell'amministratore (precisa "Scrittura sul proprio interno" 2026-10-30)
**Scelta:** chi inserisce le credenziali API Yeastar (amministratore, che il
client non mostra più dopo il salvataggio) è **più fidato** dell'utente
finale che usa il telefono. L'app non deve permettere all'utente finale, con
le sole azioni dell'interfaccia, di usare la chiave dell'amministratore oltre
il proprio interno: per esempio cambiando lo username SIP per far diventare
"proprio" l'interno di un collega. Resta valido il rischio accettato della
voce citata: chi **estrae** le credenziali dal PC (stesso utente Windows) può
già modificare qualunque interno; il confine qui è l'uso dalla UI senza
estrazione.
**Origine:** audit di sicurezza fase 2 (`docs/sicurezza/2026-10-30-audit-fase2-credenziali-yeastar.md`),
punto rimandato 2.
**Attuazione:** l'amministratore indica l'**interno dell'utente** insieme alle
credenziali API (stesso blob DPAPI, `ApiCredentials.ownExtension`); l'app
legge e scrive il proprio interno solo se lo username SIP coincide. Credenziali
nuove = dati e cache della connessione buttati.
**Scartato:** utente e amministratore allo stesso livello (renderebbe inutile
nascondere le credenziali API nella UI); "proprio interno" = account SIP
registrato con successo (con `authUser` separato la registrazione non prova
lo username, e il comportamento del PBX non è verificabile dal client);
scegliere la connessione solo per `pbxId` (la UI non lo imposta: resta il
legame per host, coperto dall'interno fissato per connessione).
**Da rivedere se:** la postazione è sempre gestita da una sola persona che è
anche amministratore del PBX, o arriva il gateway Econnet che firma le modifiche.

---

## 2026-10-30 · Scrittura sul proprio interno (di Gigi; ribalta la parte "solo endpoint in lettura" di "Credenziali OpenAPI Yeastar nel client" 2026-10-28 bis)
**Scelta:** DrinPhone può **modificare il proprio interno** con
`extension/update`, come farebbe l'utente da Linkus: presenza attuale, per
ognuna delle 6 presenze inoltri interni/esterni (sempre, nessuna risposta,
occupato → casella, interno, cellulare, numero esterno, termina, occupato;
IVR/code/gruppi/messaggi si tengono se già impostati), timeout squillo,
cellulare in contemporanea con conferma, gruppi di squillo; cambio automatico
della presenza per orario; più dispositivi (occupato/rifiuto su tutti);
casella vocale (attiva, PIN richiesto, data e ora, email, allegato, dopo
l'email, formato ora). Vincoli: **solo l'id del proprio interno** (dall'elenco,
per numero dell'account SIP); **elenco chiuso** di campi
(`YeastarApi.ownWritable` e campi di `presence_list`), qualunque altro campo
non parte (`ArgumentError`); bozza salvata solo con "Salva sul PBX";
password, PIN e segreti scartati già alla lettura (non in memoria né in
cache); valori mandati con il tipo letto dal PBX (`"0"` per `0` = errcode
40002, visto sul pilota). Resto dell'interno (nome, email, ID chiamante,
trasporti, SRTP, blocchi di uscita, Linkus) **solo in lettura**.
Verificato sul pilota (interno 305): modifica e ripristino di campi di una
presenza e della casella, nessun altro campo cambiato.
**Rischio accettato (in più rispetto alla bis):** il limite "solo il proprio
interno" lo impone l'app, non il PBX: chi estrae le credenziali dal PC può
già modificare **qualunque** interno; un difetto dell'app che sbagliasse id
cambierebbe l'interno di un altro (mitigato: id ricavato dall'elenco, test).
**Scartato:** credenziali API per utente (Yeastar non le offre: le API sono
dell'amministratore); gateway Econnet che firma le modifiche (più sicuro, da
fare se la distribuzione esce dal gruppo interno); scrittura di tutti i 90
campi (molti sono da amministratore).
**Da rivedere se:** distribuzione a clienti esterni o più di qualche postazione
per PBX (→ gateway), Yeastar introduce token per utente, o serve cambiare
anche messaggi registrati, PIN o orari dell'interno.

---

## 2026-10-30 · Sincronizzazione PBX configurabile (aggiorna "Rubrica aziendale ogni 6 ore" e "Multi-PBX e sincronizzazione dati API")
**Scelta:** cosa leggere dalle API del PBX e ogni quanto lo sceglie l'utente,
per connessione, in Preferenze (scheda del PBX > "Cosa sincronizzare e ogni
quanto"): una riga per funzione con frequenze a radio button e "Spenta".
Registro unico `PbxSync` (`lib/core/pbx/pbx_sync.dart`): per voce scelte,
predefinito, testo e se si può spegnere. Salvato in `settings.json`
(`pbx[].sync`, nome → secondi, 0 = spenta); voci assenti = predefinito, voci
sconosciute ignorate: aggiungere o togliere una funzione non rompe le
impostazioni esistenti. Predefiniti = cadenze di prima (interni e casella 1
min, reparti/dettaglio/codici 10 min, rubrica 6 ore). Interni e presenza non si
spengono (provano le credenziali, servono a BLF e casella); con gli eventi in
tempo reale restano al più ogni 5 min. "Sincronizza ora" rilegge solo le voci
accese. Eventi WebSocket: interruttore a parte, come prima.
**Scartato:** un solo intervallo globale (la rubrica da migliaia di contatti
non può seguire la presenza); valori liberi (con le API Yeastar limitate a 8
token e il blocco IP, solo scelte provate); impostazioni globali per tutti i
PBX (ogni PBX ha licenze e permessi API diversi).
**Da rivedere se:** si aggiungono funzioni API (CDR, registrazioni, code), un
PBX diverso da Yeastar ha capacità diverse (allora le voci per tipo di PBX), o
serve imporre le cadenze dall'amministratore (provisioning).

---

## 2026-10-30 · ID di installazione: solo locale
**Scelta:** ogni installazione crea al primo avvio un codice casuale di 16 byte
(`install-id` nella cartella dati: resta fra aggiornamenti e reinstallazioni
dello stesso utente), mostrato in Preferenze > Diagnostica e scritto in
`flutter-errors.log`. Serve a riconoscere il PC nel supporto; **non** viene
inviato a GitHub e non autentica.
**Scartato:** credenziali per installazione emesse da GitHub (GitHub non le
emette; un repo privato richiederebbe un token estraibile nel client);
mandare l'ID a GitHub nel controllo aggiornamenti (GitHub non ce lo mostra:
solo un dato in più a terzi).
**Da rivedere se:** servono conteggi, versioni installate o revoca per
installazione → endpoint Econnet che riceve il controllo con l'ID.

---

## 2026-10-30 · Aggiornamenti dalle GitHub Releases, manifest firmato (aggiorna "Canale aggiornamenti" del 2026-10-26 e "Installer Windows della Alpha")
**Scelta:** il client Windows legge `update.json` dall'**ultima release** del
repo `Giggi-98/drinphone` (`/releases/latest/download/update.json`, niente API
né token) all'avvio (+30 s) e ogni 6 ore, o con "Verifica ora" (Preferenze >
Diagnostica). Il manifest è **firmato Ed25519**: chiave pubblica fissata in
`Updater.publicKey`, privata fuori dal repo (`%USERPROFILE%\.drinphone\update-signing.key`
di chi pubblica). Accettato solo con firma valida, versione più recente
(niente rollback) e installer con l'impronta SHA-256 del manifest; URL
ricavato dal repo fissato, non dal manifest. "Installa e riavvia" (mai in
chiamata): download in `%APPDATA%\Econnet\DrinPhone\updates`, installer Inno
`/SILENT`, un-REGISTER, uscita; l'installer riapre l'app. Pubblicazione:
`tool/build_installer.ps1 -Notes … -Publish` (gh).
**Scartato:** repo "releases" separato (il repo del codice risulta già pubblico,
verificato il 2026-10-30: un secondo repo non toglie nulla); solo HTTPS + hash
(chi ottiene la scrittura sul repo distribuirebbe un eseguibile a tutti);
API GitHub `releases/latest` (limite 60 richieste/ora per IP: un ufficio dietro
un NAT lo supera); aggiornamento silenzioso senza conferma (riavvia il telefono
sotto l'utente); Authenticode (serve un certificato, vedi Installer).
**Vincolo aperto:** perdita della chiave privata = i client installati non
accettano più aggiornamenti (reinstallazione a mano con la nuova chiave).
**Da rivedere se:** servono canali (alpha/beta), rollout graduale, versione
minima forzata, il repo torna privato (allora → endpoint Econnet), o arriva la
firma del codice.

---

## 2026-10-29 · Installer Windows della Alpha: Inno Setup per utente
**Scelta:** `DrinPhone-Alpha-<v>-setup.exe` con Inno Setup 6, installazione
**per utente** (niente UAC) in `%LOCALAPPDATA%\Programs\DrinPhone`, runtime MSVC
copiato accanto all'exe, non firmato. "Alpha" nel titolo della finestra, nel
badge della barra laterale (tooltip con la versione) e nel nome dell'installer.
Versione da `pubspec.yaml` (ora 0.1.0). Logo: wordmark "Drin!" bianco unico,
colorato da Flutter (blu DRIN sul chiaro, testo sullo scuro); icona = nuvola DRIN.
**Scartato:** MSIX (serve un certificato anche per i tester, sideload più
scomodo); ZIP portabile (niente collegamenti né disinstallazione); redistributable
VC++ lanciato dall'installer (richiederebbe privilegi di amministratore).
**Vincolo aperto:** il gate licenze ("Commercializzazione / licensing",
2026-10-28) resta: la Alpha va solo a tester interni finché non è chiuso.
**Da rivedere se:** serve auto-aggiornamento desktop, firma del codice o
installazione per macchina (MDM/GPO), o la distribuzione esce dal gruppo interno.

---

## 2026-10-29 · Rubrica aziendale ogni 6 ore (di Luigi; aggiorna "Multi-PBX e sincronizzazione dati API")
**Scelta:** la rubrica aziendale (`company_contact/list`, sul pilota 4469 contatti
in 9 pagine) non si rilegge più con i reparti ogni 10 min e a ogni accesso, ma
ogni **6 ore** (data salvata nella cache cifrata, vale anche fra un accesso e
l'altro) o con **"Sincronizza ora"**. All'accesso con cache fresca si leggono solo
interni, reparti, casella e dettaglio. Cache letta e scritta in un isolate.
**Scartato:** lettura incrementale (l'API non ha un filtro "modificati da");
rubrica solo a mano (resterebbe vecchia per giorni); WebSocket (nessun evento per
la rubrica).
**Da rivedere se:** gli utenti trovano contatti nuovi mancanti per ore, o l'API
aggiunge un filtro per data di modifica.

---

## 2026-10-29 · Un account vivo alla volta (di Luigi; ribalta "Profili" e "Multi-account SIP ed eventi WebSocket" del 2026-10-28)
**Scelta:** un **account** = una registrazione SIP + al più una connessione API
Yeastar; ne è viva **una alla volta**. Con un solo account si entra sempre lì;
con più account si entra nel **predefinito** (radio nella schermata di scelta),
altrimenti si sceglie. In app solo **Logout** (un-REGISTER, connessioni ferme,
ritorno alla scelta); il predefinito resta per l'avvio successivo. Spariscono
"Chiama con", l'elenco di più account, il trunk dentro un profilo Yeastar (ora è
un account a sé) e la scelta del PBX collegato. Contatti personali e registro
**per account**. Migrazione: un profilo con più interni si divide in un account
per interno, ognuno con la connessione del suo PBX (id scelto, poi host, poi
ordine), nome `<interno> · <PBX>`, copia dei contatti personali; il registro
resta al primo. Accesso veloce: la sincronizzazione non blocca più
l'interfaccia (parte in sottofondo) e la cache cifrata copre anche casella
vocale, dettaglio del proprio interno e codice di registrazione.
**Scartato:** più account registrati insieme (ordine, prestazioni: BLF e sync di
N PBX a ogni avvio o cambio); tenere registrati in sottofondo gli account non in
uso (chiamate in arrivo su un account non visibile); logout che toglie il
predefinito (scelta dell'utente: il predefinito vale all'avvio).
**Da rivedere se:** serve ricevere chiamate su più interni insieme (es.
centralinista), o un trunk solo in uscita accanto all'interno Yeastar.

---

## 2026-10-29 · ANGLE per il video e finestra di chiamata (di Luigi)
**Scelta — ANGLE:** il solo filtro di visualizzazione dell'SDK è `MSOGL` (OpenGL ES
via EGL): senza `libEGL.dll`/`libGLESv2.dll` il video arriva e si decodifica ma
non si vede. Si usano le DLL **ANGLE di Qt 5.15.2** contenute nell'installatore
ufficiale **Linphone 5.3.4** (firmato Belledonne; DLL firmate The Qt Company),
estratte da `tool/fetch_angle.ps1` con **impronte SHA-256 fissate** e incluse
nel pacchetto (BSD-3). **Finestra di chiamata** stile Linkus: scheda in arrivo,
finestra grande riducibile a barra o a schermo intero, pannelli in linea (non
dialoghi, coperti dal video nativo). **Registra:** codice del PBX letto dalle
API Yeastar (`feature_code/get`, `auto_record`) o impostato nell'account, oppure
file locale (liblinphone) o disattivata, per account. **Conferenza** locale a 3
mixata da DrinPhone. **Note** della chiamata nel registro.
**Scartato:** ANGLE compilato da noi (toolchain di molti GB, ore); disegno del
video in Flutter con plugin C++ (più lavoro; da rivedere per togliere il limite
del video sopra i menu); Linphone 6 come fonte (usa un filtro Qt, niente ANGLE).
**Da rivedere se:** si fa il plugin texture Flutter o Media Foundation, la
versione di Qt/ANGLE crea problemi con driver o GPU, o serve la registrazione
centralizzata sul PBX con stato confermato (API di registrazione).

---

## 2026-10-29 · Videochiamate (di Luigi; ribalta "Esclusi: … video" della voce "UI desktop: proposta D")
**Scelta:** videochiamate 1:1 con dispositivi SIP (videocitofoni, telefoni, softphone).
Codec **VP8** (libvpx nell'SDK, senza brevetti) e **H264** tramite **OpenH264 di
Cisco** scaricato sul PC dell'utente, con consenso, da `ciscobinary.openh264.org`:
così la licenza dei brevetti H264 è coperta da Cisco e il binario **non** sta nel
nostro pacchetto. Versione fissata **2.2.0** (quella del plugin `libmsopenh264`
dell'SDK) e **impronta SHA-256 fissata** (archivio e DLL), verificata a ogni avvio
prima del caricamento. Controllo del 2026-10-29: firma Authenticode "Cisco WebEx
LLC" valida, importa solo KERNEL32 (nessuna funzione di rete). Video nel pannello
di chiamata (finestra nativa figlia), anteprima della webcam **spenta di default**,
"Rispondi" e "Rispondi in video" distinti. Restano esclusi videoconferenza, chat,
pannello operatore.
**Scartato:** OpenH264 compilato da noi e incluso (brevetti H264 a carico di
Econnet); solo VP8 (molti videocitofoni/telefoni vogliono H264); finestra video
separata.
**Da rivedere se:** si ottiene la licenza commerciale Belledonne o si scrive un
plugin **Media Foundation** (codec H264 di Windows, già licenziato, accelerato),
oppure cambia la versione di OpenH264 richiesta dall'SDK.

---

## 2026-10-28 · Cache dati PBX e BLF al cambio profilo (di Luigi; aggiorna "Rubrica solo in memoria" di ARCHITECTURE)
**Scelta:** interni, reparti e rubrica aziendale di ogni connessione PBX si
salvano su disco **cifrati DPAPI** (`pbx-cache-<id>.dpapi`, stesso schema delle
credenziali) e si mostrano subito all'avvio e al cambio profilo; la sync li
aggiorna in sottofondo e riscrive la cache solo se i dati cambiano. Gli stati BLF
**non** si salvano: al ritorno su un profilo si mostra l'ultimo stato della
sessione **attenuato, "da confermare"**, finché il PBX non risponde. SUBSCRIBE
BLF a gruppi (10 ogni 200 ms) e ridisegno raggruppato (100 ms) per gli eventi a
raffica.
**Scartato:** cache solo in memoria (all'avvio liste vuote); cache in chiaro
(4000+ contatti aziendali leggibili); BLF da cache come stato vero (mostrerebbe
"libero" chi è in chiamata).
**Da rivedere se:** la cache diventa troppo grande o lenta da cifrare (rubriche
da decine di migliaia di contatti), o servono più postazioni con gli stessi dati
(allora gateway).

---

## 2026-10-28 · Profili: "Yeastar integrato" e "SIP generico" (di Luigi)
**Scelta:** l'app gestisce **profili** (utenze) scelti in alto a destra, **uno attivo
alla volta**: cambiare profilo de-registra gli account del precedente e registra
quelli del nuovo. Tipo del profilo:
- **Yeastar integrato** — 1..3 PBX Yeastar con i loro account SIP registrati
  insieme, API e eventi facoltativi per PBX; interni da API + manuali, reparti,
  presenza, Live Calls (solo con eventi attivi), rubrica aziendale.
- **SIP generico** (PBX qualunque o trunk diretto) — interni solo manuali con BLF
  SIP, niente Live Calls né presenza, casella vocale MWI + codice.
In entrambi: **contatti personali** creati dall'utente e **registro chiamate**
legati al profilo. Un profilo Yeastar può includere un account SIP generico
(trunk) usato **solo per chiamare** ("Chiama con"), senza cambiare la schermata.
Globali: lingua, audio, diagnostica. Configurazione attuale migrata in un profilo
Yeastar. Primo avvio e "Nuovo profilo": **procedura guidata** (lingua → tipo →
account con prova di registrazione → API facoltative → audio).
**Scartato:** più profili registrati insieme (interfaccia mista Yeastar/generica);
contatti personali solo nei profili generici; import da file al primo avvio (per ora).
**Da rivedere se:** serve ricevere chiamate su più profili insieme (es. reperibilità),
o il provisioning centralizzato Econnet sostituisce la configurazione manuale.

---

## 2026-10-28 · Multi-account SIP ed eventi WebSocket (aggiorna "Multi-PBX e sincronizzazione dati API")
**Scelta:** più account SIP registrati insieme, ognuno collegato a una connessione
PBX (scelta esplicita o stesso host). Gli interni di un PBX si chiamano e vanno in
BLF tramite il suo account: chiamata con `linphone_call_params_set_account`, BLF
con risorsa `interno@host` (il core la instrada sull'account di quel dominio, DA
VALIDARE sul secondo PBX). Eventi API in tempo reale per connessione, attivabili
dall'utente: WebSocket `subscribe` con 30007/30008/30009/30022, heartbeat 30 s,
riconnessione con backoff; con eventi attivi la lettura periodica scende a 5 min.
30008 fa da stato linea dove manca il BLF SIP.
**Supera:** "gli interni di un PBX senza account SIP non si chiamano" della voce
"Multi-PBX e sincronizzazione" (resta vero solo se quel PBX non ha un account).
**Da rivedere se:** il core non instrada le SUBSCRIBE sull'account giusto (allora
`linphone_core_create_subscribe_2` per account), o i payload 30009/30007 reali
differiscono da quelli assunti (chiavi `extension` / `presence_status`).

---

## 2026-10-28 · Multi-PBX e sincronizzazione dati API
**Scelta:** ogni PBX è una `PbxConnection` indipendente (credenziali DPAPI proprie,
token, ciclo di sync). Sync a **polling adattivo**: interni+presenza ogni 60 s,
reparti ogni 10 min o se cambia l'elenco interni, backoff esponenziale fino a
15 min sugli errori, risync immediata (max 1 ogni 10 s) al rientro nella finestra
e dopo una re-REGISTER; BLF e UI si riallineano solo se l'impronta dei dati cambia.
Gli interni di un PBX diverso da quello dell'account SIP si vedono ma **non si
chiamano** e non vanno in BLF (manca un account SIP su quel PBX).
**Scartato per ora:** WebSocket eventi 30006/30009/30022 (richiede monitor
abilitati sul PBX e gestione heartbeat/riconnessione; non verificato sul pilota);
multi-account SIP.
**Da rivedere se:** serve presenza istantanea, molte postazioni sullo stesso PBX
(carico/limite token), o chiamate verso più PBX (allora multi-account SIP).

---

## 2026-10-28 (bis) · Credenziali OpenAPI Yeastar nel client (ribalta "Credenziali API e AMI" del 2026-10-28)
**Scelta (di Luigi):** Client ID e Client Secret OpenAPI si inseriscono **nell'app**
DrinPhone. Vincoli: campi di **sola scrittura** (si sovrascrivono, non si rileggono
dalla UI); file cifrato con **DPAPI** (utente Windows + PC) ed entropia = segreto
compilato nell'app + sale casuale per installazione; mai nei log, compreso
l'`access_token` (che Yeastar vuole in query string); il client usa **solo
endpoint in lettura** (`get_token`, `refresh_token`, `del_token`, `extension/list`);
token rinnovato a 25 min e revocato all'uscita. Codice: `lib/core/security/api_credential_store.dart`,
`lib/core/pbx/yeastar_api.dart`.
**Scartato:** gateway Econnet lato server (`docs/yeastar-openapi.md` §6), per ora.
**Rischio accettato:** su Windows il confine è l'account utente: codice eseguito
come lo stesso utente che estragga il segreto dall'exe, o un amministratore del PC,
può decifrare le credenziali, che sono **amministrative** (aprono anche
`extension/getpassword`). Limite di 8 token per applicazione: molti client
contemporanei sullo stesso PBX lo esauriscono.
**Da rivedere se:** più di qualche postazione per PBX, distribuzione a clienti
esterni, o si chiede presence/eventi in tempo reale per molti utenti (allora gateway).

---

## 2026-10-28 · UI desktop: proposta D (struttura a pannelli) e gruppi interni opzionali
**Scelta:** grafica desktop = proposta "D · Struttura a pannelli" (barra sezioni,
griglia di schede interni con stato BLF, barra con composizione e tastierino a
comparsa). Ispirata alla *struttura* di Linkus Desktop; logo, palette, icone e
tipografia sono propri. Esclusi: videoconferenza, video, chat, pannello operatore,
console call center. Canvas: https://claude.ai/artifact/NPEZ2hdFBTfgWNkFH99tHp
**Gruppi:** il pannello gruppi **non c'è di default** (solo "Tutti" / "Preferiti").
Compare se (a) l'utente crea gruppi personali, salvati localmente, oppure (b) il
provider Yeastar fornisce l'organigramma, in sola lettura. Endpoint Yeastar per
reparti/organizzazioni **DA VALIDARE** sulla documentazione OpenAPI per edition.
**Scartato:** albero organizzativo fisso e obbligatorio (non esiste su PBX SIP generici).
**Da rivedere se:** i clienti pilota chiedono gruppi condivisi gestiti centralmente
(allora servirebbe provisioning/backend).

---

## 2026-10-28 · Piattaforma pilota: Windows desktop (integra "F2 — piattaforma pilota: Android")
**Scelta:** su indicazione di Luigi, la prima vertical slice si fa su **Windows desktop**;
Android segue. Bridge: `dart:ffi` sull'API C di liblinphone con l'**SDK ufficiale
`linphone-sdk-win64`** (5.5.39), lo stesso bridge già provato su Linux.
**Scartate (per ora):** Android come pilota (richiede dispositivo e push F4 prima di
essere utile); plugin Flutter di terze parti (nessuno copre Windows).
**Perché:** la workstation di sviluppo è Windows, l'SDK Windows è ufficiale e completo
(DLL, header, plugin WASAPI) e lo spike F0-A lo ha inizializzato senza ripieghi.
**Da rivedere se:** la licenza commerciale Belledonne non copre Windows desktop, o
il primo cliente pilota è solo mobile.

---

## 2026-10-26 · Framework: Flutter
**Scelta:** un unico codebase Flutter per Android, iOS, Windows, macOS, Linux.
**Scartate:** React Native (binding liblinphone comunitari/deboli),
Capacitor/Ionic (VoIP in background fragile), Electron+RN separati (due shell).
**Perché:** liblinphone ha il pairing più collaudato con Flutter; un solo codice
per tutte le piattaforme riduce la manutenzione; il linguaggio lo scrive l'agente.
**Da rivedere se:** liblinphone perde il supporto Flutter, o serve una feature
nativa non esponibile dal plugin.

## 2026-10-26 · Motore chiamate: liblinphone
**Scelta:** liblinphone (linphone-sdk).
**Scartate:** PJSIP (integrazione più laboriosa), SIP.js/JsSIP over WSS (limiti
mobile in background), librerie leggere di piattaforma (incomplete).
**Perché:** SDK completo (audio/video, SRTP/ZRTP, codec, push) già multipiattaforma.
**Da rivedere se:** serve controllo SIP di basso livello che l'SDK non offre.

## 2026-10-26 · Protocollo: nucleo SIP standard + strato Yeastar separato
**Scelta:** il prodotto registra via SIP standard a qualunque PBX/trunk; le
funzioni UC Yeastar stanno in uno strato isolato e opzionale.
**Scartate:** legarsi all'API Yeastar come trasporto primario (lock-in, come Linkus).
**Perché:** portabilità su qualunque PBX, con integrazione profonda dove serve.
**Da rivedere se:** Econnet decide di vendere esclusivamente su Yeastar.

## 2026-10-26 · Push ad app chiusa: da decidere in F4
**Stato:** differita. Dipende dal supporto di Yeastar P-Series al push SIP
RFC 8599. Piano di riserva: gateway push proprio (stile Flexisip) + APNs/FCM.
**Da rivedere/chiudere:** in F4, dopo il test su un P-Series reale.

## 2026-10-26 · Canale aggiornamenti: repo "releases" pubblico separato (iniziale)
**Scelta (di partenza):** codice in repo privato; **manifest + artefatti firmati**
in un canale pubblico separato, così **nessun token finisce nei client**.
**Scartate (per ora):** endpoint proxy Econnet e GitHub Releases privato con
backend — più controllo (metriche, versioni minime, revoca) ma più infrastruttura;
si adotteranno se servirà.
**Perché:** semplice e sicuro per iniziare; il client legge un manifest, non il repo.
**Da rivedere se:** servono metriche/forzature di versione o distribuzione
controllata per cliente (allora → endpoint Econnet).

## 2026-10-26 · Distribuzione mobile: differita
**Stato:** differita. Primo bersaglio **Play Store Android**; iOS e il modello
(store pubblici vs enterprise/MDM vs sideload) si scelgono al rilascio.
L'architettura di update astrae il *canale* per non chiudere nessuna di queste strade.
**Da rivedere/chiudere:** prima di F8.

---

## 2026-10-28 · F0-A prima dell'integrazione SDK (integrazione, non cancellazione scelta 2026-10-26)
**Stato:** DA VALIDARE.
**Scelta:** provare binding native Flutter per Android e Linux con versioni/commit verificati, prima di affermare che `liblinphone` è plugin Flutter multipiattaforma maturo.
**Alternativa:** Platform Channels/FFI con plugin interno e librerie native; ulteriore alternativa rivalutare framework se costo ingestibile.
**Motivo:** il supporto native cross-platform dell'SDK non equivale al supporto di un singolo wrapper Flutter. La motivazione "pairing collaudato" del 2026-10-26 non è ancora dimostrata.
**Da rivedere se:** spike mostra package ufficiale mantenuto e supporto multipiattaforma, o ostacoli nativi non sostenibili.

## 2026-10-28 · BLF generico vs API Yeastar
**Scelta:** preferire SIP SUBSCRIBE/NOTIFY per BLF quando il PBX lo supporta; Yeastar OpenAPI arricchisce, non sostituisce, il core SIP. Non assumere AMI su Yeastar P-Series.
**Scartato:** far dipendere tutti i BLF da token API amministrativi in ogni client.
**Da rivedere se:** il PBX target non espone il dialog event package e ha un endpoint eventi documentato e autorizzato, con backend appropriato.

## 2026-10-28 · Commercializzazione / licensing
**Scelta:** gate di revisione licensing e negoziazione Belledonne prima di distribuire closed-source a esterni. Prototipo interno prima, senza rappresentarlo come pubblicabile.
**Scartato:** "repo privato" inteso come sufficiente a superare gli obblighi della licenza copyleft.
**Da rivedere se:** cambio SDK o licenza commerciale ottenuta e audit dipendenze completato.

## 2026-10-28 · Credenziali API e AMI
**Scelta:** secret amministrativi Yeastar e AMI solo su backend fidato, mai nel client. Privilegi minimi; lato client token limitati e revocabili.
**Da rivedere se:** esiste autenticazione user-scoped ufficiale con garanzie equivalenti e autorizzazione verificata.

## Nome ufficiale del prodotto — 2026-10-28

**Decisione:** il prodotto si chiama **DrinPhone**. Nome tecnico repository, directory locale e progetto Flutter: `drinphone`. Directory di lavoro raccomandata: `/opt/drinphone`. Il nome non è più provvisorio.

**Identificatori app proposti (da verificare prima di pubblicare):** Android `it.drin.drinphone`, iOS/macOS `it.drin.drinphone`. Verificare disponibilità, titolarità del dominio/namespace, marchi e account degli store; questi identificatori non sono ancora approvati. Evitare di modificarli dopo la prima distribuzione.

**Coerenza:** package del bridge nativo `drinphone_linphone_bridge`, binari, namespace, documentazione, pipeline e asset di UI devono usare DrinPhone. Il riferimento a DRIN indica l’ecosistema di prodotto, non un vincolo sulla compatibilità con PBX SIP generici.
