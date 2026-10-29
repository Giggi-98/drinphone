# Piano d'azione — DrinPhone

Suite **a fasi**: obiettivo → passi → verifica. Piattaforma pilota **Windows**
(DECISIONS 2026-10-28), PBX di prova **Yeastar P-Series** reale (RAS + Cloud).
Qui restano **solo le cose aperte**; il completato è riassunto in fondo con la
prova. Stato aggiornato al **2026-10-29**.

Regole: nessuna voce si chiude per deduzione — "fatto" = provato contro un PBX
vero (audio nei due versi per le chiamate, CLAUDE.md §5) e, per la UI, reso e
guardato (§8). Ogni chiusura aggiorna questo file nello stesso commit.

## In attesa di una decisione di Luigi
- **Cambio presenza e inoltri dall'app** (pulsanti stile Linkus): serve l'API in
  scrittura `extension/update`, oggi esclusa (DECISIONS 2026-10-28 bis).
  Strade: scrittura limitata alla sola presenza del proprio interno (nuova voce in
  DECISIONS) oppure gateway Econnet lato server.
- Da questa dipendono anche **Agent Status** (code) e **scelta del numero in uscita** (DOD).

## Da validare (implementato, manca la prova vera)
Chiamate (F3):
- Attesa/riprendi, muto, DTMF, avviso di chiamata, **trasferimento cieco e
  assistito** via RAS.
- Registrazione che si ristabilisce dopo una caduta di rete; 20 chiamate ripetute;
  rete cattiva (perdita pacchetti, cambio rete).

Live Calls (F6):
- Dopo la correzione del 2026-10-28: chiamata che **sparisce al riaggancio**,
  uscenti nella tabella giusta, **una riga** per le esterne verso un interno.

Multi-account e profili:
- BLF degli interni del **secondo PBX** instradato sul suo account; stato
  **Squilla** mai osservato.
- **Procedura guidata** su un PC nuovo; creazione di un profilo "SIP generico".
- Account **avanzato**: chiamate in uscita tramite **proxy** (route; la
  registrazione è verificata), registrar separato, utente di autenticazione/realm,
  nascondi ID chiamante, intervallo di registrazione, **STUN/ICE/TURN**.
- Opzioni globali: **cifratura SRTP/ZRTP/DTLS** (con TLS), DTMF SIP INFO, keep-alive.
- Profilo TEST (Yeastar Cloud via SBC): chiamata entrante e uscente con audio.

Desktop (F5) e UI (§8):
- Scelta **microfono / cuffia / suoneria** con chiamata vera.
- **Importazione contatti** CSV e vCard con file reali (Outlook, Google, telefono).
- Screenshot degli **stati** (riposo, in chiamata, entrante, attesa, trasferimento,
  errore, rete assente) nei **due temi** — il tema chiaro non è mai stato guardato —
  e a finestra stretta.

## Da fare

### F1 — Banco PBX ripetibile
- Asterisk/FreePBX in Docker (con consenso, senza toccare container esistenti),
  interni 201/202, softphone di riferimento: serve per provare il profilo
  **SIP generico** e le voci avanzate senza dipendere dal Yeastar di produzione.

### F3/F5 — Softphone desktop completo
- **Codec**: scelta e ordine Opus / G.711 PCMA-PCMU (e G.722) per account o globale.
- Tray, **avvio con Windows**, notifica di sistema sulla chiamata entrante.
- Funzionalità lato app in Preferenze > Funzionalità: risposta automatica
  (interfono/citofoni), inoltro (se si sceglie la scrittura API).

### F6 — Strato Yeastar
- **CDR** dal PBX (registro chiamate dell'interno, non solo locale).
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

### F7 — Aggiornamenti e distribuzione
- Manifest firmato (versione, minima supportata, artefatti), auto-update desktop,
  rimando allo store su mobile, rollback; installer Windows e QA di upgrade.

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
| Shell Flutter Windows: `SipEngine` + motore finto nei test, password nello storage sicuro, log senza segreti | test automatici (47), `docs/sicurezza/` |
| REGISTER, chiamata uscente ed entrante, **audio nei due versi** | `docs/test/2026-10-28-windows-yeastar-ras.md` |
| BLF SIP (Libero, Occupato, Non registrato) su ~50 interni | idem |
| OpenAPI Yeastar: token, interni, reparti, rubrica aziendale (4468), casella vocale | idem; credenziali DPAPI a sola scrittura |
| Presenza in tempo reale via WebSocket | confermata da Luigi il 2026-10-28 |
| Dettaglio presenze del proprio interno (6 presenze, inoltri, squillo) in sola lettura | visto sul pilota |
| Due account SIP su due PBX registrati insieme | log del pilota |
| Profili Yeastar / SIP generico, migrazione dei dati, un-REGISTER e chiusura BLF al cambio | log 2026-10-28 17:45 |
| Registrazione via **proxy in uscita** (Yeastar Cloud multi-tenant, TLS) | 200 OK, log 2026-10-28 |
| Cache cifrata dei dati PBX: interni e rubrica a schermo in ~1 s all'avvio | misura sul pilota |
| Audit di sicurezza per ogni funzione che tocca un confine | `docs/sicurezza/2026-10-28-*.md` |
