# Agent instructions (Antigravity / Claude Code / coding agents)

**Leggere in ordine:** `CLAUDE.md`, `README.md`, `PIANO-AZIONE.md`, `ARCHITECTURE.md`, `DECISIONS.md`, documento della fase.

- Documenti contrattuali: distinguere sempre `DECISO`, `PROPOSTO`, `DA VALIDARE`, `IMPLEMENTATO`, `VERIFICATO SU DEVICE`.
- Non inventare nomi di package, API, eventi Yeastar, classi Flutter o compatibilità piattaforme. Confermare versione, repository upstream, changelog, licenza e prova minima riproducibile.
- Per ogni task: scope, ipotesi, file da cambiare, piano in massimo 7 punti, test, rischi residui. Implementare una sola vertical slice.
- Non modificare file di sicurezza e distribuzione per aggirare gate di release.
- Credenziali demo solo in `*.example` con valori fittizi. Mai file con token reali in repo o output degli agenti.
- Build riuscita NON equivale a chiamata riuscita. Per contrassegnare SIP/BLF/push come completato serve prova reale, evidenza e log redatti.
- In assenza di toolchain/telefono/PBX dichiarare `NON TESTATO` e indicare esattamente il comando o test mancante.
- Se `ARCHITECTURE.md` descrive un modulo pianificato, non riferirlo come implementato. Aggiornare quando diventa reale.
- Ogni PR: test automatici, checklist manuale, impatto licenze, impatto privacy, aggiornamento documenti se tocca contratto o architettura.
- `DECISIONS.md` è append-only; nuove scelte vanno in testa senza alterare la storia.
- Nessuna app cliente pubblicata prima della revisione licenze, provisioning, firma, security review e piano supporto.
