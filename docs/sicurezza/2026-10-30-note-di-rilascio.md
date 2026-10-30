# Audit di sicurezza — note di rilascio e popup "Novità" (2026-10-30)

Fase di security test mirata (CLAUDE.md §9): run-5 della skill
`security-audit`, profilo `quick`, sul diff della funzione. Artefatti:
`~/security-audit-skill/drinphone/run-5/`. Solo sorgente: un hunter e il
critico finale, che non ha trovato altro da coprire.

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Provenienza delle note prima dell'installazione | OK | Solo dal payload firmato Ed25519 (`verifyManifest`), lo stesso di versione, file e impronta; il testo della release GitHub non viene mai letto |
| Rendering | OK | Parser a righe, solo `Text`: niente markdown, HTML, link né azioni dal contenuto |
| Note incluse nell'app | OK | Percorso `release-notes/<versione>.md` con la versione fissata in compilazione; build `dev` esclusa |
| File `notes-seen` | OK | Stesso utente; decide solo se mostrare il popup |
| Firma in build | OK | Note lette dalla radice del repo per la versione di `pubspec.yaml`, firmate con il resto del payload; build fermata se il file manca o non ha voci |
| Scadenza/canale del manifest | NOTA (già nota, fase 1) | Payload senza scadenza: chi scrive sul repo senza chiave può bloccare gli aggiornamenti |

## Riscontri
- **confirmed**: nessuno. **needs_validation**: nessuno.
