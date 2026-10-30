# Audit di sicurezza — scrittura sul proprio interno Yeastar (2026-10-30)

Oggetto: modifica del proprio interno via `extension/update` (presenze, inoltri,
squillo, cellulare, casella vocale) e sincronizzazione PBX configurabile.
Decisioni: `DECISIONS.md` 2026-10-30 "Scrittura sul proprio interno" e
"Sincronizzazione PBX configurabile". Codice: `lib/core/pbx/yeastar_api.dart`
(`PbxExtensionDetail`, `ownWritable`, `updateOwnExtension`),
`lib/core/pbx/pbx_connection.dart`, `lib/core/pbx/pbx_sync.dart`,
`lib/features/preferences/own_extension.dart`, `lib/features/account/api_dialog.dart`.
Verifica: `test/yeastar_api_test.dart` (dettaglio, scrittura, campi rifiutati,
voci di sincronizzazione spente); sul pilota, interno 305: due modifiche
reversibili (presenza "Pranzo" e casella) → cambiati solo i campi voluti,
ripristino identico al confronto di tutti i campi scrivibili.

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Scrittura su altri interni | OK (limite dell'app) | id dall'elenco interni per numero dell'account SIP; dettaglio con id diverso → `StateError`; il PBX non lo impedisce (credenziali amministrative): rischio scritto in DECISIONS |
| Campi da amministratore | OK | Elenco chiuso `ownWritable` + regex per `presence_list`; `reg_password` o campi di uscita → `ArgumentError` prima della richiesta (test) |
| PIN e password | OK | `vm_pin`, `reg_password`, `user_password` e ogni `…pin`/`…password`/`…secret`/`…token` (tranne `enb_…`) scartati in `parse`: mai in memoria, cache o UI (test) |
| Log | OK | Solo nomi dei campi cambiati (`interno aggiornato (…)`), mai valori; errori = operazione e codice |
| Modifiche involontarie | OK | Bozza, "Salva sul PBX" esplicito, "Annulla"; validazione interno/numero esterno prima del salvataggio; solo presenze cambiate |
| Tipi dei valori | OK | Convertiti al tipo letto dal PBX (`"0"` → errcode 40002 visto sul pilota) |
| Numeri esterni di inoltro | ATTENZIONE | L'utente può inoltrare le proprie chiamate verso qualunque numero: costo per l'azienda come da Linkus; i permessi di uscita restano del PBX |
| Carico sulle API | OK | Voci spente = nessuna richiesta (test); scelte solo fra cadenze proposte |
| Dati personali | NOTA | Nome, email, cellulare dell'interno mostrati in sola lettura; in cache cifrata DPAPI come prima |

## Riscontri
- **confirmed**: nessuno.
- Durante la prova sul pilota un ripristino con `"0"` al posto di `0` è stato
  rifiutato (40002) e l'interno è rimasto modificato per circa un minuto
  (timeout "Pranzo" 31 s, annuncio data/ora): ripristinato a mano, poi corretto
  nel codice con la conversione dei tipi e coperto da test.
