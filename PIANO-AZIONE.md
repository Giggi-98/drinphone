# Piano d'azione — DrinPhone

Suite **a fasi**: obiettivo → passi → verifica. Piattaforma pilota **Windows**
(DECISIONS 2026-10-28), PBX di prova **Yeastar P-Series** reale (RAS + Cloud).
Qui restano **solo le cose aperte**; il completato è riassunto in fondo con la
prova. Stato aggiornato al **2026-11-10** (v0.1.6).

Regole: nessuna voce si chiude per deduzione — "fatto" = provato contro un PBX
vero (audio nei due versi per le chiamate, CLAUDE.md §5) e, per la UI, reso e
guardato (§8). Ogni chiusura aggiorna questo file nello stesso commit.

## Da validare (implementato, manca la prova vera)
Chiamate (F3):
- Attesa/riprendi, muto, DTMF, avviso di chiamata, **trasferimento cieco e
  assistito** via RAS.
- Registrazione che si ristabilisce dopo una caduta di rete; 20 chiamate ripetute;
  rete cattiva (perdita pacchetti, cambio rete).

Live Calls e CDR (F6):
- Dopo la correzione del 2026-10-28: chiamata che **sparisce al riaggancio**,
  uscenti nella tabella giusta, **una riga** per le esterne verso un interno.
- **Evento 30039 (`Call End Timeline Notification`)**: ricezione WebSocket a fine
  chiamata e visualizzazione in `Dettagli chiamata` (con fallback verificato su
  `cdr_basic` + `cdr_clip`).

Account e sistema (DECISIONS "Un account vivo alla volta"):
- **Scelta all'avvio** e radio del predefinito; **logout** con un-REGISTER nel
  log; rientro veloce con le sezioni piene dalla cache (305, 902, NovoOne).
- Stato BLF **Squilla** dal vivo.
- **Procedura guidata** su un PC nuovo; "Aggiungi account" di tipo SIP generico.
- Account **avanzato**: chiamate in uscita tramite **proxy** (route; la
  registrazione è verificata), registrar separato, utente di autenticazione/realm,
  nascondi ID chiamante, intervallo di registrazione, **STUN/ICE/TURN**.
- Opzioni globali: **cifratura SRTP/ZRTP/DTLS** (con TLS), DTMF SIP INFO, keep-alive.
- Profilo TEST (Yeastar Cloud via SBC): chiamata entrante e uscente con audio.
- **Tray, notifiche toast Windows, avvio con Windows e link `tel:`/`sip:`** da
  browser/Outlook con conferma.
- **Aggiornamento automatico dall'app** (`update.json` firmato Ed25519 -> download ->
  installer silenzioso -> riavvio).

Video e finestra di chiamata (DECISIONS "Videochiamate" e "ANGLE"):
- **Videochiamata reale** in uscita ed entrante (Linkus con video, videocitofono
  SIP): immagine nei due versi, H264 e VP8, anteprima, webcam accesa/spenta in
  chiamata, "Rispondi in video", ingrandisci; finestra video che segue il pannello
  quando si ridimensiona la finestra.
- **Video in arrivo e anteprima visibili** con ANGLE ("Prova webcam" e chiamata
  vera); il crash spegnendo e riaccendendo il video non deve ripetersi.
- Riduci / schermo intero / pannelli in linea durante una chiamata vera.
- **Registra**: codice dalle API sul Yeastar (il PBX registra?), codice a mano,
  file locale riproducibile.
- **Conferenza a 3** (Aggiungi partecipante → Unisci): audio di tutti e tre.
- Note salvate nel registro.

Desktop (F5) e UI (§8):
- Scelta **microfono / cuffia / suoneria** con chiamata vera.
- **Importazione contatti** CSV e vCard con file reali (Outlook, Google, telefono).
- Screenshot degli **stati** (riposo, in chiamata, entrante, attesa, trasferimento,
  errore, rete assente) nei **due temi** e a finestra stretta.

## Da fare (Prossimi passi proposti)

### F3/F5 — Ergonomia e rifinitura softphone desktop
- **Ascolto e download registrazioni / casella vocale in-app**: player integrato
  nei `Dettagli chiamata` CDR (`recording/download`) e in `Casella vocale`
  (`vm/download`) senza dover chiamare `*2` o aprire il PBX via web.
- **Azioni rapide in `Dettagli chiamata` e header**: clic sulle pillole dei
  partecipanti (`Da`, `A`, `Ultimo partecipante`) per richiamare, copiare o
  salvare in rubrica; menu rapido sul chip presenza in alto per cambiare stato in
  un clic.
- **Scorciatoie da tastiera**: `Ctrl+F`/`Ctrl+K` (ricerca/composizione), `Invio`
  (rispondi), `Esc` (rifiuta/chiudi), `Ctrl+M` (muto).
- **Hot-swap dispositivi audio**: rilevamento automatico cuffie USB/Bluetooth
  collegate o scollegate a caldo.
- **Allineamento grafico allo stile "Squillo" (`DESIGN.md`)**: completare la
  migrazione tipografica (`DrinText` / `DrinSpace`) di `LiveCallsView`,
  `ContactsView` e `VoicemailView` sullo standard di `CdrView`.
- **Codec audio**: scelta e ordine Opus / G.711 PCMA-PCMU / G.722.
- **Risposta automatica** lato app per interfono/citofoni.
- **Agent Status** (code) e **scelta del numero in uscita** (DOD).
- **Plugin Media Foundation** per H264 con i codec di Windows, oppure licenza
  commerciale Belledonne.

### UX — Rifinitura "Squillo" (revisione degli screenshot v0.1.6, 2026-11-11)
Estende "Azioni rapide", "Scorciatoie" e "Allineamento grafico" qui sopra.
Ordine: prima **A** (sono errori), poi **B–C** (vincite rapide), poi il resto.
Ogni voce si chiude con screenshot nei due temi e a finestra stretta (§8).

**A. Errori visibili (prima di tutto)**
- **Riaggancio remoto non visto** (segnalato da Luigi 2026-11-11): se chiude
  l'altro capo o il PBX, la chiamata resta aperta in DrinPhone. Dai log: il
  motore gestisce bene il BYE quando arriva (4 casi, 28/10–03/11); nella
  chiamata del 10/11 18:11 verso il cellulare l'audio in arrivo va a zero alle
  18:13:08, nessun BYE dal PBX, il nostro BYE alle 18:13:12 riceve **200 OK**
  (per il PBX la chiamata era ancora viva). Nessun timeout RTP né session timer
  impostato da noi (Session-Expires 1800 del PBX). Prossimo passo: prova
  controllata (interna e via trunk, riaggancio remoto, attesa 30 s) e poi
  `rtp/nortp_timeout` esplicito + session timer più corto.
- `Dettagli chiamata` › Timeline: **tutti gli offset sono `00:00`** anche se la
  risposta arriva dopo 7 s (squillo 00:00:07). Capire perché `off(ev.time,
  legStart)` dà sempre zero (unità/fuso del campo `time`?) e coprirlo con un test.
- Timeline: chiavi grezze a schermo (`call_to: 305`) e "System ha
  riagganciato" → testi tradotti ("Chiamata verso 305", "Chiusa dal sistema").
- **Colori in conflitto con DESIGN §1**: nell'anello dei tempi lo *squillo* è
  verde e la *conversazione* gialla (giallo = solo ciò che squilla → va
  invertito; serve correggere anche DESIGN §6 che oggi lo prescrive); avatar
  giallo nella pillola `A`; pulsante **"Ascolta messaggi" verde** in Casella
  vocale (verde = solo rispondi/libero → `primary`).
- Testi misti: chip **"Available"** in inglese, voce **"Live Calls"** nel menu,
  "modificabile in **Impostazioni**" (la sezione si chiama Preferenze).
- Duplicati: "208 · 208", "211 211", "305 · 305", "PBX: PBX", ID ripetuto in
  testa e nel Riepilogo → se nome = numero, mostrare solo il numero.
- Rubrica: nomi con trattino iniziale ("- Alessandro Garrappa"); registro: ID
  chiamante con tag `:` ("…Damiano:Econnet Whitelist:0817347838") → nome pulito
  + tag in un chip `panel`.
- Menu account: è il menu Material di default (fondo grigio, non `surface`),
  spunte e icone disallineate tra Lingua e Tema.

**B. Zoom dell'interfaccia (richiesta di Luigi)** — IMPLEMENTATO 2026-11-11,
DA VALIDARE a schermo
- `Ctrl` + `+` / `−` / `0` (anche tastierino) e `Ctrl` + rotella (con Ctrl
  premuto le liste non scorrono) con la finestra a fuoco: moltiplica
  `DrinScale`, passi 10 %, 70–160 %, salvato nelle impostazioni (una scrittura
  sola dopo l'ultima pressione), pillola "110 %" in alto. `lib/app/zoom.dart`,
  test in `widget_test.dart`, DESIGN §7.
- Resta: cursore in Preferenze; pizzico del touchpad.
- Verifica: a 70 % e 160 % nessun overflow su tutte le schermate e nel dialogo
  `Dettagli chiamata`; finestra di chiamata e video compresi.

**C. Simboli per ogni stato** (un'icona + un colore + tooltip con il nome)
- **Presenza Yeastar**, oggi un generico ✓ verde per tutti: Disponibile ✓
  `free`, Assente orologio `away`, Non disturbare ⛔ `busy`, Pranzo posate,
  Trasferta aereo, Fuori ufficio luna (`away`). Stesso set in header, schede
  interni, lista laterale di Live Calls e Preferenze › Presenza.
- **Separare le due informazioni** oggi sovrapposte: anello dell'avatar = stato
  SIP/BLF (libero, occupato, squilla con impulso `squillo`, non registrato
  tratteggiato), badge in basso a destra = presenza. Legenda in un popover
  dall'icona "?" accanto ai filtri.
- Filtri in testa a Interni (`47` / `● 31` / `● 0`): etichetta al passaggio e
  aggiungere "Occupati" e "Squillano".
- Registro: colonna **Tipo** solo icona (entrante, uscente, interna, **persa**
  con freccia rossa) con tooltip; il nome non più tutto rosso (l'esito lo dice
  già la pillola).
- Preferenze › Informazioni dell'interno: "No/Sì" → icone ✓/✗; "udp,tcp,tls"
  → chip `UDP` `TCP` `TLS`; SRTP con lucchetto aperto/chiuso.
- Header: fondere "Registrato" e presenza in **un solo** gruppo cliccabile
  (spia di registrazione + icona presenza); errore di registrazione in `busy`
  con tooltip della causa e "Riprova".
- Badge nel menu laterale anche per **Casella vocale** (nuovi) e **Live Calls**
  (in corso), non solo per le perse.

**D. Scorciatoie e azioni cliccabili**
- Tastiera (oggi nessuna nel codice): `Ctrl+K` composizione, `Ctrl+F` filtro
  della schermata, `Ctrl+1…5` sezioni, `Ctrl+,` Preferenze, in chiamata `Ctrl+M`
  muto, `Ctrl+H` attesa, `Ctrl+T` trasferisci, `Ctrl+D` tastierino, `Ctrl+E`
  termina; `Invio`/`Esc` per rispondi/rifiuta **solo** con la finestra della
  chiamata in arrivo a fuoco (mai mentre si scrive in un campo). Foglio delle
  scorciatoie con `?` / `F1`; ogni tooltip mostra la sua scorciatoia.
- Globali Windows (finestra non a fuoco, opzionali): rispondi/riaggancia.
- Clic destro (menu contestuale) su interni, contatti, righe di registro e CDR:
  Chiama, Video, Copia numero, Aggiungi ai preferiti, Dettagli.
- Numeri della rubrica e del registro: clic = chiama, icona copia all'hover.
- **Preferiti**: stella all'hover sulla scheda interno (oggi la lista è 0/0 e
  non si capisce come riempirla).
- Registro: chiamate consecutive dallo stesso numero raggruppate "×3" (si
  espande); "Richiama" visibile anche in "Questo PC".

**E. Popup, overlay, menu**
- Tutti i menu e i dialoghi con fondo `surface`, raggio `sheet`, ombra e bordo
  `line`, comparsa dissolvenza + scala 0,97→1 in `base`.
- Menu account: tema come **controllo segmentato a 3 icone** (sistema / chiaro /
  scuro), lingua idem; aggiungere cambio presenza, Novità della versione,
  Diagnostica.
- **Popover sulla scheda interno** (hover 400 ms o clic sull'avatar): presenza
  con orario, ultima chiamata, azioni. Stesso popover sulle pillole Da/A/Ultimo
  partecipante dei Dettagli chiamata.
- Toast in-app (non solo di Windows) per eventi brevi: "Copiato", "Trasferita
  a 202", "Registrazione persa — riprovo…", con "Annulla" dove ha senso.
- Conferma prima delle azioni distruttive ("Rimuovi" PBX, "Esci", svuota
  registro) con il pulsante pericoloso in `busy`.

**F. Pulsanti e movimento** (tutto da `DrinMotion`, rispetta "riduci movimento")
- Un solo componente pulsante (`DrinButton`: primario, bordato, testo,
  pericolo, icona rotonda) con hover `raised`, pressione a molla 0,96 in
  `fast`, focus visibile da tastiera (anello `brand` 2 px), stato "in corso"
  con spinner al posto dell'icona (es. "Sincronizza ora").
- Interruttori: oggi il pallino scuro su blu si legge male → pallino `onPrimary`.
- Cambio sezione: dissolvenza + 4 px in `base` (DESIGN §5), indicatore del menu
  laterale che **scorre** tra le voci invece di comparire.
- Liste e tabelle: scheletri a riga (shimmer statico, non in loop) al posto
  degli spinner durante il caricamento; numeri dei contatori che contano
  (47 → 48) in `base`.
- Righe del CDR e di Live Calls nuove: entrata con dissolvenza; riga che squilla
  con impulso `squillo`; durata che scorre in tempo reale.
- Finestra di chiamata: apertura `wide` dal punto della scheda cliccata
  (transizione condivisa avatar → avatar grande).

**G. Per schermata**
- **Interni**: schede alte e vuote → modalità **compatta a righe** (densità
  Centralino, DESIGN §6) con interruttore griglia/righe; azioni all'hover;
  ricerca per interno o nome direttamente in testa al pannello.
- **Live Calls**: le due tabelle vuote occupano tutto lo schermo → un solo stato
  vuoto compatto e tabelle che compaiono quando c'è traffico; contatore nel
  titolo.
- **Rubrica**: lucchetto ripetuto su ogni riga → una sola nota "Sola lettura dal
  PBX" come in Interni; lista continua (virtualizzata) con indice A–Z al posto di
  90 pagine; filtro per rubrica come chip.
- **Casella vocale**: schede statistiche più basse, lista messaggi con player
  in linea (vedi voce registrazioni sopra), stato vuoto con icona.
- **CDR**: filtri su una sola riga che va a capo in modo ordinato ("Periodo"
  oggi resta da solo sulla seconda); chip "Azzera filtri".
- **Preferenze**: valori lunghi troncati (email) con tooltip e copia; la
  targhetta "Account SIP" sulla scheda PBX non dice niente → rimuovere o
  spiegare.
- **Mancano** gli screenshot degli stati di chiamata (in corso, entrante,
  attesa, trasferimento, errore, rete assente): senza questi la revisione UX
  della finestra di chiamata — la parte più importante — resta da fare.

**H. Impaginazione delle sezioni (Preferenze e dettagli)** — il principio,
non la grafica di Linkus (CLAUDE.md §0):
- Una scheda per gruppo che occupa **tutta la larghezza** del pannello, titolo
  `title` in testa separato da `line`, contenuto su **griglia a 2 colonne**
  (etichetta sopra il campo, campi alti uguali, `s5` tra le colonne, `s4` tra
  le righe). Un campo lungo (note, regole, tabelle) prende le 2 colonne.
- Regola intelligente: 2 colonne sopra ~900 px (misurati dopo `DrinScale` e
  zoom), 1 colonna sotto; un gruppo con un solo campo non si spezza a metà.
- Schede in sequenza verticale con `s4` di stacco, niente schede affiancate di
  altezza diversa; sotto-navigazione in **schede orizzontali** in alto oppure
  la colonna attuale, ma una sola delle due.
- Campi in sola lettura con lo stesso aspetto dei campi (fondo `panel`,
  lucchetto nell'etichetta del gruppo), non come scatoline di altezza diversa.
- Dove si modifica: barra "Salva / Annulla" fissa in basso, visibile solo con
  modifiche in sospeso. Va in DESIGN §6 come componente "Sezione a griglia".

### F1 — Banco PBX ripetibile
- Asterisk/FreePBX in Docker (con consenso, senza toccare container esistenti),
  interni 201/202, softphone di riferimento: serve per provare il profilo
  **SIP generico** e le voci avanzate senza dipendere dal Yeastar di produzione.

### F6 — Strato Yeastar avanzato
- **Capability discovery** e matrice edition/firmware (Appliance, Software,
  Cloud): endpoint e eventi disponibili, errori come 70120 ORGANIZATION DISABLED.
- Test **multi-tenant** Yeastar Cloud con API (il tenant di prova oggi è solo SIP).
- Valutare il **pinning TLS** verso i PBX pubblici.

### F4 — Mobile e chiamate ad app chiusa
- Spike push: RFC 8599 su Yeastar o gateway (Flexisip/equivalente) + APNs/FCM;
  CallKit / ConnectionService; costo e affidabilità. Da avviare prima del porting.
- **Android**: runtime liblinphone (F0-A: build PASS, runtime BLOCKED senza
  dispositivo), poi vertical slice su telefono fisico.
- **iOS / macOS**: richiedono un Mac (CLAUDE.md §10).

### F5 — Altre piattaforme desktop
- **Linux**: build e audio (F0-A: eventi PASS), dispositivi reali.

### F8 — Rilascio
- **Licenze**: liblinphone è GPLv3 / commerciale — risolvere la licenza
  commerciale e le transitive **prima** di distribuire (docs/licenze-e-compliance.md;
  F0-A: "License reviewed: NO").
- Code signing Windows, notarization macOS, store; provisioning account (QR/URL);
  beta interna Econnet, poi clienti pilota.

## Completato (verificato)
| Cosa | Prova |
|---|---|
| F0-A spike: liblinphone 5.5.39 via `dart:ffi` su Windows (e eventi su Linux) | `docs/spikes/F0-A.md` |
| Shell Flutter Windows: `SipEngine` + motore finto nei test, password nello storage sicuro, log senza segreti | test automatici (92), `docs/sicurezza/` |
| REGISTER, chiamata uscente ed entrante, **audio nei due versi** | `docs/test/2026-10-28-windows-yeastar-ras.md` |
| BLF SIP (Libero, Occupato, Non registrato) su ~50 interni | idem |
| OpenAPI Yeastar: token, interni, reparti, rubrica aziendale (4468), casella vocale | idem; credenziali DPAPI a sola scrittura |
| Presenza in tempo reale via WebSocket | confermata da Luigi il 2026-10-28 |
| Dettaglio presenze e inoltri del proprio interno (lettura e scrittura via `extension/update`) | verificato sul pilota via API |
| CDR dal PBX via Database Grant (`cdr_basic` + `cdr_clip`, filtri, CSV, dettaglio a 3 pannelli con timeline e grafico tempi) | letto dal vivo sul pilota 83.25 (`v0.1.3`–`v0.1.6`) |
| Due account SIP su due PBX registrati insieme | log del pilota |
| Profili Yeastar / SIP generico, migrazione dei dati, un-REGISTER e chiusura BLF al cambio | log 2026-10-28 17:45 |
| Registrazione via **proxy in uscita** (Yeastar Cloud multi-tenant, TLS) | 200 OK, log 2026-10-28 |
| Cache cifrata dei dati PBX: interni e rubrica a schermo in ~1 s all'avvio | misura sul pilota |
| Installer Windows Inno Setup + manifest `update.json` firmato Ed25519 su GitHub Releases | `v0.1.0`–`v0.1.6` |
| Audit di sicurezza per ogni funzione che tocca un confine | `docs/sicurezza/2026-10-28-*.md`, `2026-10-30-cdr-completo.md` |
