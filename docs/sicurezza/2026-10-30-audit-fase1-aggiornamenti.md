# Audit di sicurezza — fase 1: aggiornamenti e supply chain (2026-10-30)

Primo run della skill `security-audit` (cloudflare/security-audit-skill),
profilo `quick`, *scoped* sulla fase 1 del piano in 4 fasi: updater, firma e
pubblicazione delle release, input di build di terze parti, download di
OpenH264 e caricamento delle DLL. Sorgente: `c3d448b`.
Artefatti completi fuori dal repo: `~/security-audit-skill/drinphone/run-1/`
(`REPORT.md`, `coverage-ledger.json`, `findings.json`).

**Solo sorgente.** Su questo PC non c'è una sandbox OS (Docker spento, niente
Flutter in WSL), quindi la skill vieta di eseguire codice del progetto.
Nessuna prova d'esecuzione.

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Firma del manifest | OK | Ed25519 sul payload esatto, chiave fissata, verifica prima del parsing, nessun ripiego senza firma (`updater.dart:172-202`) |
| Rollback / riuso di manifest vecchi | OK | Solo versione strettamente maggiore; build `dev` mai aggiornata |
| Scambio dell'installer | OK | URL dal repo fisso + versione/nome firmati; SHA-256 firmato confrontato prima dell'avvio |
| Blocco degli aggiornamenti | NOTA | Payload senza scadenza/canale: chi ha scrittura sul repo (senza chiave) può tenere "latest" su un manifest vecchio |
| OpenH264 via `http://` | OK | Impronta fissata su archivio e DLL, riverificata a ogni avvio; un attaccante in rete causa solo il mancato codec |
| `SetDllDirectoryW(codecs)` | NOTA | Aggiunge tutta la cartella al percorso di ricerca DLL, ma verifica solo `openh264.dll`; meglio caricare la DLL per percorso assoluto |
| Gara verifica→avvio (installer, codec) | ACCETTATO | Raggiungibile solo dallo stesso utente Windows (installazione per utente, nessuna elevazione) |
| Pipeline di rilascio | NOTA | Nessuna verifica di `update.json` con la chiave pubblica prima di `-Publish`; `gh release create` senza `--target`; cartella Release non pulita (l'ISS copia tutto) |
| Input di build | NOTA | `fetch_linphone_sdk.ps1` salta la verifica se la DLL c'è già; CMake copia `*.dll` senza impronta. Unico scrittore: chi pubblica |
| Segreti nel repo | OK | Nessuno; `pubspec.lock` con sha256. `.gitignore` non elenca `*.key`/`*.pem` |

## Riscontri
- **confirmed**: nessuno.
- **needs_validation**: nessuno.
- **Rimandati** (critico di copertura, da fare in un run successivo):
  - `APPDATA` non impostato → radice relativa alla cartella corrente
    `null\Econnet\DrinPhone` (`app_paths.dart:10`), usata per codec e
    aggiornamenti.
  - `Process.run('explorer', …)` per nome nudo
    (`preferences_view.dart:1566`).

## Prossime fasi
2. Credenziali, storage sicuro, API Yeastar.
3. SIP/media/FFI (anche `video_surface.dart`, segnalato dal critico) e runner
   nativo.
4. Dati locali, cache, import, log.
