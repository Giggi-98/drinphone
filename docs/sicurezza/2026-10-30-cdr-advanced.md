# 2026-10-30 — CDR del PBX da `cdr_basic` (CDR Advanced) e tabella chiamate

Run: `~/security-audit-skill/drinphone/run-10` (profilo `quick`, scoped sul
diff di `lib/core/pbx`). Revisione solo sul sorgente; query poi provate in
sola lettura sul PBX pilota (83.25) con le credenziali Database Grant già
salvate nell'app, senza stamparle.

## Oggetto
- `lib/core/pbx/pbx_cdr.dart` (`read`, `_findTable`, `_kindFilter`)
- `lib/core/pbx/pbx_connection.dart` (`readCdr` passa `CdrKind`)
- `lib/features/history/history_view.dart`, `call_table.dart` (solo interfaccia)

## Riscontri
| # | Gravità | Riscontro | Esito |
|---|---|---|---|
| 1 | bassa | Scelta dello schema non deterministica se più schemi hanno `cdr_basic`/`cdr`; `cdr_clip` dato per scontato nello stesso schema. | **corretto**: `ORDER BY TABLE_SCHEMA`, CDR Advanced solo dove ci sono sia `cdr_basic` sia `cdr_clip`, altrimenti `cdr`; test. |
| 2 | info | Il proprio interno ora vede anche le chiamate dove è stato solo una gamba (gruppo di squillo, coda), compreso chi ha risposto. | **voluto**: è una chiamata che ha fatto squillare il suo telefono, come nel CDR del PBX (DECISIONS "CDR: `cdr_basic`"). |
| 3 | info | Colonne della sottoquery su `cdr_clip` non qualificate. | **corretto**: alias `c`. |
| 4 | bassa | Su MariaDB il limite `MAX_EXECUTION_TIME` è ignorato e il filtro con OR + sottoquery non usa un indice solo. | **accettato**: restano i timeout del client (10/15/30 s); sul pilota 50 righe in ~200 ms. |

## Verificato senza riscontri
- Iniezione SQL: interno, ricerca (con `%`/`_` protetti), periodo, tipo sono parametri dello statement preparato; nomi di colonna costanti; schema validato con `^[A-Za-z0-9_]{1,64}$`; LIMIT costante, OFFSET intero.
- Ogni pezzo del WHERE è tra parentesi e unito con AND: ricerca e tipo non scavalcano il filtro sul proprio interno.
- `wholePbx` controllato prima di aprire il database; senza proprio interno nessuna connessione.
- Errori mostrati solo come tipo (`runtimeType`), niente host, utente o SQL.

## Test
`test/pbx_cdr_test.dart`: tabella `cdr_basic` con gambe, ricaduta su `cdr`,
schema con `cdr_basic` senza `cdr_clip`, filtri tipo/esito, ricerca e periodo
come parametri, schema sospetto rifiutato. Suite: 84/84. Prova dal vivo sul
pilota: proprio interno 7 giorni, tutto, tutto il PBX "non risposte".
