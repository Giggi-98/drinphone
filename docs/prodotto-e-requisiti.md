# PRD — DrinPhone per DRIN

## Contesto
DRIN PRO viene presentato pubblicamente con funzioni PBX, BLF, pannello operatore, CTI, rubrica e UC. **Non assumere** che ogni funzione pubblicizzata sia disponibile via API a un client terzo. Compatibilità con varianti Yeastar P-Series **Appliance, Software, Cloud** e rispettive release va verificata singolarmente.

## Utenti e workflow
1. **Operatore ufficio:** login interno, chiama/copia numero, risponde, mette in attesa, passa al collega, BLF su contatti preferiti.
2. **Receptionist:** lista interni, libero/occupato/squilla/sconosciuto, pickup/transfer se permessi e interoperabili, selezione account.
3. **Tecnico installatore:** configura account SIP, TLS e codec, esegue diagnostica di registrazione e audio senza esporre password.
4. **Amministratore DRIN:** onboarding clienti mediante QR firmato o link a breve scadenza in fase successiva; nessun accesso admin API dai client non fidati.
5. **Utente in mobilità:** riceve chiamate con schermo bloccato e app in background dove la piattaforma e l'infrastruttura lo consentono.

## Priorità
| ID | Requisito | Priorità | Acceptance test |
|---|---|---|---|
| P-001 | SIP REGISTER per account singolo | P0 | 200 OK, rete persa/ritornata, recovery |
| P-002 | Dial/answer/hangup + audio due vie | P0 | chiamata a estensione su due reti |
| P-003 | Mute, hold, DTMF RFC 4733 | P0 | conferma audio e IVR |
| P-004 | Codec G.711 PCMA/PCMU; Opus se negoziabile | P0 | SDP reale + audio |
| P-005 | TLS/SRTP configurabile secondo capability PBX | P0 | handshake/SDP e fallimento esplicito |
| P-006 | Storico locale delle chiamate | P1 | persist/restart senza segreti |
| P-007 | Transfer blind/attended | P1 | destinatario riceve, BYE corretti |
| P-008 | SIP BLF SUBSCRIBE/NOTIFY | P1 | idle/ringing/busy/unknown |
| P-009 | Rubrica locale e contatti PBX | P1 | mapping e conflitti risolti |
| P-010 | Stato Yeastar via API/eventi quando disponibile | P1 | test contro P-Series reale |
| P-011 | Incoming app terminata su mobile | Release blocker mobile | telefono fisico iOS/Android e backend verificato |
| P-012 | Audio device e tray desktop | P2 | cambio dispositivo durante chiamata |
| P-013 | Multi-account e account switching | P2 | registrazioni simultanee e isolate |
| P-014 | Provisioning centralizzato sicuro | P2 | token monouso, scadenza, revoca |
| P-015 | Updates firmati e rollback | Release blocker | signature/hash verificati |

## Perimetro MVP
**Incluso:** account SIP manuale, chiamata voce, UI semplicissima, controlli chiamata, diagnostica, lista BLF minima se supportata. **Escluso dal primo MVP:** video, chat, recording, CRM, ACD, omnichannel, WebRTC browser, chat Linkus, conference bridge proprietario, billing clienti. Il supporto chiamate ad app terminata è un **gate di produzione mobile**, non deve essere venduto sulla base del solo MVP foreground.

## Metriche di qualità / criteri operativi (target proposti, non SLA)
- Nessuna password/token nei log e nei crash report (obiettivo obbligatorio).
- Registrazione ripristinata dopo perdita e ripresa connessione: misurare tempi, retry con backoff.
- 20 chiamate consecutive per stack/trasporto senza crash; nessuna chiamata mono-audio nel set di rete previsto.
- BLF: stato sconosciuto dichiarato come tale, senza inferire `available` in assenza di NOTIFY.
- Definire latenza squillo, consumo batteria e MOS solo dopo baseline strumentata.

## Non-obiettivi e confini
- DrinPhone non sostituisce il PBX e non tenta accessi a funzionalità riservate all'app ufficiale.
- Non presumere che DRIN possieda le credenziali utente API o un contratto che le abiliti.
- Non promettere compatibilità universale con tutti i trunk SIP: alcune reti e policy PBX richiedono configurazione specifica.
