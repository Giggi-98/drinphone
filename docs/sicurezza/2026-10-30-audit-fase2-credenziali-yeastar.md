# Audit di sicurezza — fase 2: credenziali, storage, API Yeastar (2026-10-30)

Secondo run della skill `security-audit`, profilo `quick`, *scoped* sulla
fase 2: credenziali SIP/TURN e Yeastar, DPAPI e Credential Manager, client
OpenAPI, controllo di scrittura sul proprio interno, ciclo di vita degli
account. Sorgente `c3d448b`. Il run è additivo al run-1 (fase 1).
Artefatti: `~/security-audit-skill/drinphone/run-2/`.

**Solo sorgente**: nessuna sandbox OS disponibile, nessuna esecuzione.

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Campi scrivibili sul PBX | OK | `ownWritable`/`presenceWritable` ricontrollati in `updateOwnExtension` prima della richiesta; `id` non sovrascrivibile |
| Bersaglio della scrittura | OK con NOTA | Id dall'elenco per numero == username SIP, non dal dettaglio modificato. Il controllo `edited.id` salta se è null |
| Valori del PBX → azioni | OK | Codice di registrazione solo come DTMF nella propria chiamata su richiesta; eventi WebSocket senza scritture |
| Trasporto credenziali admin | OK con NOTA | `https` obbligatorio all'inserimento, niente bypass TLS. Non ricontrollato al caricamento |
| Token in URL / testo di stato | NOTA | Eccezione grezza in `status` (`pbx_connection.dart:412-419`): può contenere `?access_token=`; usare `_short(e)` |
| DPAPI | OK | CurrentUser, salt `Random.secure`, nessun ripiego in chiaro, tmp+rename |
| Password SIP/TURN | OK | Solo Credential Manager; cancellate con l'account |
| Cambio account / logout | OK con NOTA | Nessun dato del profilo precedente raggiunge scrittura o chiamata; cache ricreabile dopo la cancellazione; `login` senza guardia sui doppi clic |
| `APPDATA` non impostato | NOTA | Radice relativa alla cartella corrente; solo chi lancia il processo può causarlo |

## Riscontri
- **confirmed**: nessuno.
- **needs_validation**: nessuno.
- **Rimandati dal critico di copertura** (da chiudere in un run-3 mirato):
  1. **Cambio PBX di una connessione**: `start()` passa `_api` al nuovo PBX ma
     tiene `directory`/`ownDetail` del vecchio finché una sync non riesce.
     `updateOwnExtension` userebbe l'id del proprio interno del vecchio PBX
     **sul nuovo**, cioè forse un altro interno. Struttura confermata nel
     sorgente; effetto non provato.
  2. **Username SIP modificabile dall'utente** = "proprio interno". È un
     confine solo se l'utente finale vale meno dell'amministratore che ha
     inserito la chiave API (che il client non mostra più): va deciso il
     modello di fiducia.
  3. **URL API precompilato dal dominio SIP**: le credenziali admin vanno
     all'host del dominio SIP se nessuno lo corregge.
