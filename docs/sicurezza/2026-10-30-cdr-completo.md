# 2026-10-30 — CDR completo: totale, ordinamento, gambe, esportazione CSV

Revisione manuale del sorgente. **Run della skill `security-audit` non
eseguito** (da fare prima del commit, CLAUDE.md §9). **Prova sul PBX pilota
non eseguita**: la lettura dal vivo è stata bloccata dai permessi della
sessione; sonda pronta in sola lettura (vedi "Da fare").

## Oggetto
- `lib/core/pbx/pbx_cdr.dart`: `CdrQuery`, `CdrPage`, `CdrLeg`, `read`
  (conteggio, ordinamento, query sulle gambe), `cdrCsv`, `CdrRecord.names`
- `lib/core/pbx/pbx_connection.dart`: `readCdr(CdrQuery)`
- `lib/features/history/cdr_view.dart`: esportazione su file

## Riscontri
| # | Gravità | Riscontro | Esito |
|---|---|---|---|
| 1 | media | Ordinamento scelto dalla UI: se la colonna passasse come testo nell'SQL sarebbe iniettabile. | **evitato**: `CdrSort` è un enum mappato su nomi di colonna costanti; direzione solo `ASC`/`DESC`; test. |
| 2 | media | Esportazione CSV: i nomi del CDR li scrive chi chiama (caller ID esterno); `=…`, `+…`, `@…` diventano formule in Excel (CSV injection). | **corretto**: apostrofo davanti alle celle che iniziano con `= + - @` tab o a capo, virgolette raddoppiate; test. |
| 3 | bassa | `limit` dalla UI senza tetto: una pagina enorme blocca il PBX. | **corretto**: `limit` limitato a `PbxCdr.maxLimit` (500), esportazione al più 10.000 righe a blocchi; test. |
| 4 | info | Le gambe di una chiamata del proprio interno mostrano anche gli altri interni del gruppo o della coda che hanno squillato, e i trunk. | **voluto**: è la stessa chiamata, come nel CDR del PBX; senza `wholePbx` restano solo le chiamate dove il proprio interno compare (filtro invariato). |
| 5 | info | Da `cdr_clip` non si leggono `recordfile`/`recordpath`, `accountcode` (PIN), `srcaddr`/IP del chiamante. | **voluto**: non servono alla vista. |
| 6 | bassa | `COUNT(*)` raddoppia il lavoro sul PBX a ogni pagina. | **accettato**: stesso WHERE e stessi timeout della pagina; DECISIONS "CDR come la pagina del PBX". |

## Verificato senza riscontri
- Da, A, ricerca: parametri dello statement preparato, `%`/`_`/`\` protetti;
  ogni pezzo del WHERE tra parentesi e unito con AND al filtro sul proprio
  interno.
- `uid` delle gambe: parametri `?` generati in numero uguale agli uid della
  pagina (al più 500).
- Conteggio con gli stessi parametri della pagina (test).
- Errori ancora solo come tipo (`runtimeType`), anche nell'esportazione.
- File CSV scritto solo dove l'utente sceglie nel dialogo di salvataggio.

## Test
`test/pbx_cdr_test.dart`: conteggio con gli stessi filtri, gambe con uid
come parametri, ordinamento da elenco fisso, Da/A separati, tetto alle
righe, esiti, intervallo di date, formato di code/gruppi/IVR, CSV con formule
disinnescate. Suite 91/91 con Flutter 3.38 su una copia del progetto (il
progetto richiede Dart ≥ 3.13, non installato su questo PC).

## Da fare
- Run `security-audit` `quick` scoped su questi file.
- Prova in sola lettura sul pilota: colonne `queues`, `ringgroups`, `ivrs`,
  `callflows`, `segments`, `has_recording`, `hold_duration`,
  `second_dstname` di `cdr_basic` e `holdduration`, `srctrunk`, `dsttrunk`,
  `didnumber`, `dodnumber` di `cdr_clip` (nomi dalla guida Yeastar "Tables
  in the PBX Database"), formato dei campi code/gruppi/IVR, tempi.
