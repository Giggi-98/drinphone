# DECISIONS — DrinPhone

Registro **append-only**. Non modificare né cancellare voci: per ribaltarne una,
aggiungi una voce nuova in cima che cita la vecchia. Il campo chiave è
**"Da rivedere se"**.

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
