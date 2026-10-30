# Audit di sicurezza — correzione "proprio interno" e cambio PBX (2026-10-30)

Correzione dei due riscontri del run-3 (`2026-10-30-audit-run3-proprio-interno.md`),
verificata con la fase di security test mirata (CLAUDE.md §9): run-4 della
skill `security-audit`, profilo `quick`, sul diff. Artefatti:
`~/security-audit-skill/drinphone/run-4/`.

## Cosa cambia
- `ApiCredentials.ownExtension` è l'**interno dell'utente** scelto
  dall'amministratore. Sta nello stesso blob DPAPI e si inserisce nel dialogo
  delle credenziali insieme a Client ID e Secret (campo obbligatorio).
- `PbxConnection.voicemailOf` dà lo username SIP solo se coincide con
  `ownExtension`. Altrimenti niente dettaglio, casella vocale né scritture,
  e il dettaglio letto prima viene buttato.
- `updateOwnExtension` richiede `edited.id == own.id` e `current.id == own.id`,
  senza più l'eccezione per l'id null.
- Nuove credenziali: `stop()`, poi `clearData()` (memoria, cache, chiamate in
  corso e BLF), poi salvataggio e `start()`.
- `PbxCache.clear()` aspetta i salvataggi in coda.
- Una sync, un evento WebSocket o una fotografia `call/query` del client
  precedente non scrivono più stato.
- Credenziali salvate senza interno (0.1.1 e precedenti): niente proprio
  interno finché l'amministratore non le reinserisce.

## Verifica
- **Test** (`test/yeastar_api_test.dart`, eseguiti sul PC di sviluppo con
  `FakePbx` in locale):
  - username cambiato → nessuna lettura né scrittura dell'interno del collega;
  - cambio PBX con `extension/list` negato → niente dati né cache del PBX
    precedente e scrittura rifiutata;
  - cambio PBX durante una sync → il giro vecchio non riscrive nulla. Questo
    test fallisce se si toglie la guardia.
- **Esito:** `flutter test` 63/63, `flutter analyze` pulito.
- **Prima della correzione**, due test temporanei hanno osservato le scritture
  sbagliate: `{id: 11, presence_status: away}` sull'interno del collega e
  `{id: 15, …}` sul PBX B.

## Riesame indipendente (run-4, solo sorgente)
- Lo username SIP non sceglie più l'interno: **rejected (corretto)**.
- La scrittura dopo un cambio di PBX non usa più gli id del PBX precedente:
  **rejected (corretto)**, confermato da un secondo verificatore dopo la
  guardia sulla sync in corso.
- **Rimandato.** Gli eventi WebSocket e la fotografia delle chiamate del PBX
  precedente sono già corretti, ma nessun agente indipendente li ha ancora
  rivisti: da riprendere nel prossimo run.
- **Note.** Il campo "Interno dell'utente" è precompilato con lo username
  SIP, che l'utente può aver cambiato prima: chi inserisce le credenziali
  deve controllarlo. Un errore di battitura spegne le funzioni del proprio
  interno, ma senza danni.
