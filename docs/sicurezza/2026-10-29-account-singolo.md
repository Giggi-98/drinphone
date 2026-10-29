# Audit di sicurezza — un account vivo alla volta (2026-10-29)

Oggetto: un account = una registrazione SIP + al più una connessione API, scelta
all'avvio, logout, divisione dei profili con più interni, cache PBX v2
(DECISIONS "Un account vivo alla volta").
Codice: `lib/core/security/settings_store.dart` (`splitProfile`, `withProfiles`,
`defaultProfile`), `lib/app/phone_controller.dart` (`login`, `logout`,
`_splitProfiles`, `deleteProfile`), `lib/core/pbx/pbx_cache.dart`,
`lib/core/pbx/yeastar_api.dart` (`PbxExtensionDetail.toJson`),
`lib/features/setup/account_picker.dart`.
Verifica: test automatici (`test/profiles_test.dart`, `test/widget_test.dart`,
`test/yeastar_api_test.dart`); avvio sul pilota con il file della versione
precedente (profilo Econnet con 305 e 902): diviso correttamente, nessun
REGISTER finché non si sceglie l'account.

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Password SIP dopo la divisione | OK | Gli account tengono il loro id, quindi la chiave nello storage sicuro non cambia; `save` riscrive le password di tutti gli account (test: password `uno` e `due` leggibili dopo la divisione, assenti dal JSON) |
| Nuovi id | OK | `_newId` = 8 cifre esadecimali da `Random.secure`, come prima |
| Credenziali API alla divisione | OK | Le connessioni restano con il loro id e il loro file DPAPI; gli host per l'abbinamento si leggono in memoria e non si salvano né si loggano |
| Copia dei contatti personali | OK | Copiati per scelta dell'utente (contatti per account) nel file del nuovo account, stesso formato e stessa protezione del file di origine |
| Eliminazione di un account dalla scelta | OK | Anche quello attivo ma fuori dall'account: credenziali DPAPI e cache della connessione, registro e contatti cancellati; password SIP e TURN tolte al salvataggio (test TURN) |
| Cache PBX v2 | OK | Casella vocale (nomi e numeri di terzi) e dettaglio del proprio interno nello stesso file DPAPI; `toJson` non contiene `vm_pin` (già scartato nel parse); casella e dettaglio rimessi a schermo solo per la connessione del proprio account |
| Logout | OK | `setAccounts([])` = stesso percorso del cambio profilo, che sul pilota faceva l'un-REGISTER (`Expires: 0`) e chiudeva le sottoscrizioni BLF |
| Log | OK | Nuovo messaggio `profili divisi: N account`, senza dati di account |
| Account predefinito | OK | Solo un id in `settings.json`, nessun dato segreto |

## Riscontri
- **confirmed**: nessuno.
- **accettato**: al logout la revoca del token API prosegue in sottofondo; se l'app
  si chiude subito dopo, il token resta valido fino alla sua scadenza sul PBX (non è
  salvato su disco).
- **accettato**: una connessione API senza interno abbinabile alla divisione resta
  fuori dagli account, ma il suo file DPAPI rimane sul disco (cifrato). Non succede
  con i dati del pilota.

## Da validare sul pilota
- Logout dal vivo: un-REGISTER visibile nel log e interno non più registrato sul PBX.
