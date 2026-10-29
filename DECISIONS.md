# DECISIONS — DrinPhone

Registro **append-only**. Non modificare né cancellare voci: per ribaltarne una,
aggiungi una voce nuova in cima che cita la vecchia. Il campo chiave è
**"Da rivedere se"**.

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
