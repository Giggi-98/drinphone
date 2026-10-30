# Audit di sicurezza — run-3: legame "proprio interno" ↔ chiave admin (2026-10-30)

Terzo run della skill `security-audit`, profilo `quick`, *scoped* sui 3 punti
rimandati dalla fase 2 (`2026-10-30-audit-fase2-credenziali-yeastar.md`).
Modello di fiducia deciso dal titolare (`DECISIONS.md`, voce in cima):
**l'utente finale è meno fidato dell'amministratore** che inserisce le
credenziali API Yeastar. Sorgente `c3d448b`.
Artefatti: `~/security-audit-skill/drinphone/run-3/`
(`findings.json`, `NEEDS-VALIDATION.md` con i piani di prova completi).

**Solo sorgente**: nessuna sandbox OS, nessuna esecuzione; i due riscontri
sono `needs_validation`. Ognuno è stato verificato da un agente indipendente,
che non è riuscito a confutarlo.

## Riscontri needs_validation (da provare, poi correggere)

### 1. L'utente sceglie su quale interno scrive la chiave admin cambiando lo username SIP
`preferences_view.dart:746` → `_assignVoicemail` (`phone_controller.dart:333`)
→ `sync` carica il dettaglio dell'interno con quel numero
(`pbx_connection.dart:371`) → `updateOwnExtension` (`:434-439`, controllo id
autoreferenziale) → `extension/update` con la chiave admin
(`yeastar_api.dart:648`).
I passi sono: Preferenze → Account SIP → Modifica, username = numero del
collega; poi "Sincronizza ora" e "Salva sul PBX". Effetto possibile: inoltro
delle chiamate del collega verso un numero esterno e modifica della sua
casella vocale; in più la lista dei suoi messaggi vocali (`vm/get`) diventa
leggibile.
**Prova locale:** test con `FakePbx` in `test/yeastar_api_test.dart`
(username `301` → atteso `extension/update` con id 11).
**Correzione proposta:** fissare l'interno dell'utente (numero o id) dentro
il blob DPAPI delle credenziali API. Lo scrive solo il dialogo
dell'amministratore; scritture e letture usano solo quel valore e si
rifiutano se non coincide con lo username SIP.

### 2. Dopo un cambio di PBX la scrittura può usare l'id dell'interno del PBX precedente
`updateConnection` → `start()` cambia `_api` ma non svuota
`directory`/`ownDetail`/cache (`pbx_connection.dart:252-288`, `stop()`
`:732-739`). Questo dura finché `extension/list` sul nuovo PBX non riesce,
anche dopo un riavvio, perché la cache è legata all'id della connessione.
La finestra si apre solo se quella lettura fallisce: il dialogo attende la
prima sincronizzazione.
**Prova locale:** due `FakePbx`, B con `extension/list` in errore → atteso
`extension/update` con id 15 su B.
**Correzione proposta:** svuotare dati e cache quando cambiano URL o
credenziali (come fa `forget()`), oppure salvare `baseUrl` nella cache e
ignorarla se non coincide; legare la scrittura ai dati letti con l'`_api`
corrente.

## Rivisto e OK
- URL API precompilato dal dominio SIP: non supera il confine, perché il
  segreto va ridigitato a ogni cambio di URL (nota: meglio lasciarlo vuoto).

## Rimandato (critico di copertura)
- La connessione PBX usata per scrivere si sceglie per `pbxId`, poi per host
  SIP, poi "l'unica". L'interfaccia non imposta mai `pbxId`: con più
  connessioni admin, cambiando solo il dominio SIP le scritture passano a un
  altro PBX. Da chiudere insieme alla correzione 1, legando la connessione in
  modo esplicito.
