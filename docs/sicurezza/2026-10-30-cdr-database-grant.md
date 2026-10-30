# Audit di sicurezza — CDR dal database del PBX (2026-10-30)

Funzione nuova: il registro chiamate legge il CDR dal MySQL del PBX con
Database Grant (`DECISIONS.md` 2026-10-30 "CDR dal database del PBX"). Nuova
integrazione, nuove credenziali e nuova dipendenza (CLAUDE.md §6), quindi
security test mirato (§9): un revisore indipendente, solo sorgente, run-7
(`~/security-audit-skill/drinphone/run-7/`).

## Rivisto e OK
| Punto | Esito | Evidenza |
|---|---|---|
| Iniezione SQL | OK | Valori (interno, ricerca, data) come parametri di statement preparati (binding binario di `mysql_client`); nome del database da `information_schema` validato `^[A-Za-z0-9_]{1,64}$`; LIMIT costante, OFFSET intero |
| Filtro sul proprio interno | OK | Uguaglianza su `src`/`dst` con `voicemailOf` (interno scelto dall'amministratore); ricerca in AND, non allarga; username cambiato = nessuna riga (test) |
| CDR di tutto il PBX | OK | Imposto in `PbxCdr.read` da `wholePbx` salvato con le credenziali dall'amministratore, non solo nascondendo la scheda (test) |
| Credenziali | OK | DPAPI per connessione, sola scrittura nel dialogo, mai in log o messaggi (solo il tipo d'errore); cancellate con la connessione o il profilo |
| TLS | ACCETTATO | `secure` rifiuta un server senza TLS (nessun ritorno silenzioso al chiaro) ma il certificato non è verificato: LAN/VPN, IP consentiti sul PBX |
| Licenza dipendenza | OK | `mysql_client` BSD-3 (file verificati); scartato `mysql1` (GPL v2 nel file, MIT su pub.dev) |

## Riscontri e correzioni
| Riscontro | Gravità | Esito |
|---|---|---|
| Timeout di connessione o lettura lasciavano la connessione MySQL aperta e la query attiva sul PBX; ogni ricerca ne apriva un'altra | bassa (disponibilità) | **corretto**: limite lato server `MAX_EXECUTION_TIME(20000)`, una lettura alla volta per connessione, chiusura che non copre l'errore, connessione chiusa se l'handshake fallisce |
| Cambiando PBX nelle credenziali API restava il database CDR del PBX vecchio (filtrato sull'interno nuovo) | bassa | **corretto**: credenziali CDR e permesso cancellati quando cambia l'indirizzo API; asserzione nel test "cambio PBX" |
| TLS spegnibile senza avviso; host precompilato anche se pubblico | bassa | **corretto**: avviso esplicito a TLS spento; host precompilato solo se in rete locale |

## Verifica
`flutter test` 78/78 (due giri), `flutter analyze` pulito. Prova sul PBX vero
con Database Grant: `DA VALIDARE`.
