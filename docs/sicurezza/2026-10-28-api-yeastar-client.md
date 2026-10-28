# Audit sicurezza — credenziali OpenAPI Yeastar nel client Windows (2026-10-28)

Ambito (CLAUDE.md §9): nuovo confine "chiamate all'API Yeastar" e storage delle
credenziali API. Decisione di riferimento: `DECISIONS.md` 2026-10-28 (bis).
Codice: `lib/core/security/api_credential_store.dart`, `lib/core/pbx/yeastar_api.dart`,
`lib/features/account/api_dialog.dart`, `lib/app/phone_controller.dart`.
Verifica: test automatici contro un finto PBX locale e DPAPI reale su Windows.
**Nessuna chiamata ancora contro il PBX vero.**

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Client ID/Secret su disco in chiaro | OK | Blob DPAPI (`CryptProtectData`, `CRYPTPROTECT_UI_FORBIDDEN`) con entropia = segreto compilato + sale casuale 32 byte; test: il file non contiene ID, Secret né URL |
| File copiato/manomesso | OK | Entropia diversa → `CryptUnprotectData` fallisce → `load()` null (test); altro utente/PC: DPAPI rifiuta per costruzione |
| Rilettura dalla UI | OK | Campi sempre vuoti, `obscureText`; nessun metodo pubblico restituisce le credenziali alla UI (solo `load()` usato da `PhoneController._connectApi`) |
| Credenziali/token nei log | OK | `ApiCredentials.toString()` senza ID/Secret; `YeastarApiException` riporta solo operazione e `errcode` (test: niente URL né Secret nel messaggio); `debugPrint` solo conteggi |
| Buffer DPAPI in memoria | PARZIALE | Il buffer restituito da DPAPI viene azzerato e liberato con `LocalFree`; le stringhe Dart restano in memoria finché il GC non le raccoglie |
| TLS verso il PBX | OK | `HttpClient` con verifica certificati standard, nessun `badCertificateCallback`; la UI accetta solo `https://` |
| Superficie API usata | OK | Solo `get_token`, `refresh_token`, `del_token`, `extension/list` (GET) |
| Consumo token (max 8/app) | OK | Un token per sessione, refresh a 25 min, `del_token` all'uscita (test); un solo nuovo `get_token` se il refresh fallisce, niente loop |
| WebSocket eventi | OK | Token nell'URL `wss://…?access_token=` per specifica: l'URL non è mai loggato, gli errori di connessione riportano solo il tipo (`WebSocketException`), i log eventi solo tipo e nomi dei campi (test) |
| Blocco IP per tentativi falliti | RESIDUO | Credenziali errate → un tentativo per avvio o salvataggio; nessun retry automatico |

## Riscontri
- **confirmed**: nessuno aperto.

## Rischi accettati (DECISIONS 2026-10-28 bis)
- Codice eseguito con lo stesso utente Windows, o un amministratore del PC, può
  estrarre il segreto dall'eseguibile e decifrare il file: le credenziali sono
  **amministrative** (aprono anche `extension/getpassword`, create/delete interni,
  call control, CDR).
- Limite di 8 token per applicazione condiviso da tutte le postazioni.
- Consigliato sul PBX: IP Restriction sull'IP pubblico della sede.
