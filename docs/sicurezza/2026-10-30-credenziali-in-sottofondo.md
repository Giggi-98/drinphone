# Audit di sicurezza — salvataggio credenziali senza attesa (2026-10-30)

Bug segnalato sulla 0.1.2: "Salva e connetti" restava su "Connessione…"
finché la prima lettura dal PBX non finiva. Correzione in 0.1.3:
`PbxConnection.replaceCredentials` fa subito e in locale fermo → dati e cache
buttati → credenziali salvate; revoca del token vecchio e prima lettura in
sottofondo. Tocca il ciclo di vita delle credenziali (CLAUDE.md §6), quindi
fase di security test mirata (§9): un verificatore indipendente sul diff,
solo sorgente. Artefatti: `~/security-audit-skill/drinphone/run-6/`.

## Riscontri e correzioni
| Riscontro | Origine | Esito |
|---|---|---|
| Se `clearData`/`store.save` falliscono, il client vecchio staccato non veniva chiuso: sessione admin orfana, niente `del_token`, timer di rinnovo vivo (limite 8 token) | introdotto dalla modifica | **corretto**: chiusura e riavvio in `finally`; test `nuove credenziali non salvabili` (fallisce senza la correzione) |
| Un `start()` già in corso (es. quello d'avvio dentro `cache.load`) poteva rimettere dati o client del PBX precedente dopo il cambio | preesistente, stessa impronta del run-3 | **corretto**: generazione `_gen`, l'avvio superato si ferma dopo ogni attesa |
| Un WebSocket aperto dal client precedente poteva installarsi sul nuovo; il rinnovo token del client staccato chiudeva il socket nuovo | preesistente, solo dati mostrati | **corretto**: controllo del client dopo la connessione e in `onTokens` |

## Rivisto e OK (dal verificatore)
- Sync del client staccato: nessuna scrittura dopo `clearData` (guardia).
- Finestra con `_api` nullo: `updateOwnExtension` rifiuta, nessun id vecchio.
- Uscita a metà: cache svuotata prima del salvataggio, mai credenziali nuove
  con la cache vecchia.
- Messaggio d'errore del dialogo: solo il tipo d'eccezione, nessun dato delle
  credenziali.

## Verifica
`flutter test` 70/70 (tre giri), `flutter analyze` pulito.
