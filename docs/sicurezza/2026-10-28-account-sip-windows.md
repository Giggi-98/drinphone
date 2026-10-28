# Audit sicurezza — account SIP e motore su Windows (2026-10-28)

Ambito (CLAUDE.md §9): credenziali SIP, storage sicuro, log, TLS della
segnalazione, porte di rete. Codice: `lib/core/security/settings_store.dart`,
`lib/core/sip/linphone_ffi_engine.dart`, `lib/app/phone_controller.dart`,
`lib/features/account/account_dialog.dart`. Revisione fatta da Claude Code sul
codice e sui log reali dell'app in esecuzione; **nessun PBX reale ancora** (la
REGISTER è stata provata solo verso una porta chiusa).

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Password SIP su disco in chiaro | OK | Password solo via `flutter_secure_storage` 11.2.0 (Windows 4.2.2): AES-GCM, chiave casuale nel Gestore credenziali (`CredWriteW`), file cifrato in `%APPDATA%`. `settings.json` non la contiene (test `la password va nello storage sicuro…`). |
| Password in `linphonerc` del motore | OK | Core creato con `config_path = NULL`; log del core: `Storage of accounts to config file is skipped.` |
| Password nei log dell'app | OK | `SipAccount.toString()` esclude la password (test); i `debugPrint` riportano solo stati e messaggi del motore. |
| Password nei log del motore (debug) | OK (parziale) | Log Debug dopo REGISTER reale (Yeastar RAS, 401 → 200) e una chiamata: le righe `findBestAuthInfoForChallenge` non stampano la password, l'header `Authorization` porta solo il digest MD5. Ricerca per parole chiave, non per il valore della password: conferma definitiva = cercare la password stessa nel log, fatta dall'utente. |
| Porte locali | Corretto in questa sessione | Default liblinphone: 5060 fisso su tutte le interfacce. Ora porte casuali UDP/TCP/TLS (`linphone_core_set_transports`, -1). |
| Video / webcam | Corretto | Il core apriva la webcam di sistema; ora cattura e visualizzazione video disattivate (prodotto solo audio). |
| TLS segnalazione | PARZIALE | Trasporto TLS selezionabile; CA = `rootca.pem` dell'SDK; nessun pinning; nessuna politica che *imponga* TLS verso PBX pubblici. |
| SRTP/ZRTP media | NON TESTATO | Nessuna configurazione esplicita: valgono i default del core. Da decidere e provare in F2/F6. |
| Permessi | n/a su Windows | Il microfono passa da WASAPI; nessun prompt applicativo. |

## Riscontri
- **confirmed**: nessuno aperto (porta 5060 fissa e video attivo corretti prima del commit).
- **da chiudere prima di distribuire a terzi**: TLS obbligatorio per domini
  pubblici, decisione SRTP, verifica password assente dal log debug, cartella log
  con dati personali (numeri, nomi) da mostrare/cancellare dall'utente.

## Residui
- Il file cifrato sta nel profilo **roaming**: in un dominio con profili roaming
  segue l'utente, ma la chiave nel Gestore credenziali potrebbe non seguirlo
  (password da reinserire). Da verificare su un PC aziendale in dominio.
- L'SDK è GPLv3 salvo licenza commerciale: prototipo interno, non distribuibile
  (`docs/licenze-e-compliance.md`).
