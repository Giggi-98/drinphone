# Audit di sicurezza — aggiornamenti dall'app e log degli errori (2026-10-30)

Oggetto: controllo e installazione degli aggiornamenti dalle GitHub Releases,
firma del manifest, log degli errori non gestiti. Decisione: `DECISIONS.md`
2026-10-30 "Aggiornamenti dalle GitHub Releases, manifest firmato".
Codice: `lib/core/update/updater.dart`, `lib/features/update/update_panel.dart`,
`tool/sign_update.dart`, `tool/build_installer.ps1`, `installer/drinphone.iss`,
`lib/main.dart`. Verifica: `test/updater_test.dart`; `update.json` prodotto da
`tool/build_installer.ps1` con la chiave reale e verificato con
`Updater.publicKey` (0.1.0, impronta dell'installer coincidente).

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Autenticità della release | OK | Payload firmato Ed25519; chiave pubblica fissata nel client; firma errata o payload alterato → rifiutato (test) |
| Integrità dell'installer | OK | SHA-256 calcolata durante il download e confrontata con quella firmata; diversa → file cancellato, niente avviato |
| Rollback a versioni vecchie e vulnerabili | OK | Solo versione strettamente maggiore di `DRIN_VERSION`; build `dev` mai aggiornata (test) |
| URL / percorso dal manifest | OK | URL costruito dal repo fissato (`github.com/Giggi-98/drinphone`, HTTPS); nome file solo `[A-Za-z0-9._-]+.exe` (test con `..\`) |
| Token nel client | OK | Nessuno: URL pubblico `releases/latest/download`, niente API GitHub |
| Chiave privata | ATTENZIONE | Solo in `%USERPROFILE%\.drinphone\update-signing.key` di chi pubblica, fuori dal repo (`.gitignore` non serve: non è sotto il repo). Furto = chi ha anche la scrittura sul repo può distribuire codice; perdita = niente più aggiornamenti |
| Installer non firmato Authenticode | ACCETTATO | Come l'installer della Alpha; la firma Ed25519 copre l'autenticità del contenuto, non l'avviso di SmartScreen |
| Esecuzione da cartella scrivibile (`updates\`) | ACCETTATO | Fra verifica e avvio un processo dello stesso utente potrebbe sostituire il file: ha già pieno controllo dell'account |
| Installazione durante una chiamata | OK | Bloccata ("Non durante una chiamata"); prima dell'uscita `shutdown()` (un-REGISTER, revoca token API) |
| Privacy | NOTA | GitHub riceve IP e ora a ogni controllo (avvio e ogni 6 ore) |
| Log errori `flutter-errors.log` | OK | Eccezioni e stack; `token`/`password`/`secret` in forma `chiave=valore` oscurati. Possono contenere numeri: dato personale come i log SIP |
| Repo del codice pubblico | NOTA | Verificato il 2026-10-30 (API GitHub senza autenticazione: 200), mentre `docs/aggiornamenti-e-distribuzione.md` lo presume privato. Da confermare con il gate licenze |

## Riscontri
- **confirmed**: nessuno.
