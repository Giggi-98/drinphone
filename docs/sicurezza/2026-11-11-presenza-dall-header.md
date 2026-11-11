# Audit di sicurezza — cambio presenza dall'header (2026-11-11)

Oggetto: menu sul chip di presenza in alto (v0.1.8+) che cambia lo stato di
presenza del proprio interno con un clic. Codice:
`lib/features/shell/home_screen.dart` (`_setPresence`, menu del chip),
`lib/features/shell/widgets.dart` (`presenceStatuses`). Confine attraversato:
scrittura API Yeastar `extension/update`, già rivista in
`2026-10-30-scrittura-proprio-interno.md` (DECISIONS 2026-10-30 "Scrittura sul
proprio interno").

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Percorso di scrittura | OK | Nessun percorso nuovo: `PhoneController.updateOwnExtension(ownDetail.withPresence(st))`, lo stesso di Preferenze > Presenza; `changesFrom` manda solo i campi cambiati, cioè `presence_status` |
| Campi ammessi | OK | `presence_status` è in `YeastarApi.ownWritable`; qualunque altro campo → `ArgumentError` prima della richiesta (test esistenti in `yeastar_api_test.dart`) |
| Interno bersaglio | OK | Solo `ownDetail` (proprio interno, id risolto dal numero dell'account SIP); con id diverso `StateError` come prima |
| Valori | OK | Solo i sei stati di `presenceStatuses` (elenco chiuso), mai testo libero |
| Modifica involontaria | ACCETTATO | Un clic cambia subito lo stato (come Linkus): è reversibile e visibile (simbolo nell'header), non tocca inoltri né casella |
| Log ed errori | OK | Avviso con il solo messaggio di `YeastarApiException` (operazione e codice); nessun URL, token o valore nel log |
| Senza dettaglio dell'interno | OK | Voci disattivate se `ownDetail` è null (API spenta o non ancora letta) |

## Riscontri
- **confirmed**: nessuno.
- Run della skill `security-audit` (profilo `quick`): **non eseguito** in questa
  sessione; la modifica non aggiunge confini né percorsi nuovi rispetto al run
  del 2026-10-30. Da includere nel prossimo run mirato.

## Da provare sul pilota
- Cambio da "Disponibile" a "Pranzo" e ritorno dal menu dell'header: sul PBX
  cambia solo la presenza (confronto dei campi scrivibili come il 2026-10-30).
