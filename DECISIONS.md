# DECISIONS — DrinPhone

Registro **append-only**. Non modificare né cancellare voci: per ribaltarne una,
aggiungi una voce nuova in cima che cita la vecchia. Il campo chiave è
**"Da rivedere se"**.

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
