# Modalità lavoro: Antigravity IDE e Claude Code

## Regola operativa
L'agente lavora in una cartella Git locale, non in produzione, e **non deve installare servizi, aprire porte, distruggere container, modificare firewall, fare push su remoto o pubblicare build senza consenso**. Può proporre comandi e prepararli in script idempotenti.

## Definizione task
```
TASK: F0-A — Flutter/Liblinphone binding spike
CONTESTO: leggi AGENTS.md, CLAUDE.md, ARCHITECTURE.md, DECISIONS.md,
         docs/licenze-e-compliance.md, docs/ambiente-di-sviluppo.md.
OBIETTIVO: dimostrare init/destroy engine, eventi register e chiamata di prova
           su Android, valutare fattibilità Linux e inventario licenze.
VINCOLI: non assumere che esista plugin ufficiale Flutter all-platform;
         nessun pacchetto non verificato, nessun secret e nessuna distribuzione.
OUTPUT: docs/spikes/F0-A.md con link a codice/versioni/commits,
        tabella piattaforma-binding-API-licenza, minimale codice funzionante
        solo se verificato, commands eseguiti e logs redatti.
STOP: se SDK non disponibile o binding non funzionante, documenta blocco e
      proponi Platform Channels/FFI o rivalutazione framework prima di F0-B.
```

## Per ogni iterazione
1. Stato iniziale (`git status`, `flutter --version`, `flutter doctor -v`, toolchain).
2. Conferma assunzioni e consulta documentazione ufficiale delle dipendenze.
3. Piano breve, uno scope, nessuna implementazione massiva.
4. Codifica/test automatici; risultati reali, niente claim inventati.
5. Test manuale richiesto e ambiente disponibile; in assenza indicare `BLOCKED`.
6. Update documenti/decisioni/registro licenze e `git diff --check`.
7. Report finale: file modificati, test PASS/FAIL/BLOCKED, rischi, prossimo step.

## Prompt F1 dopo F0-A
"Implementa SOLO il banco Asterisk locale documentato in docs/test-lab-e-qa.md, su Docker isolato, senza toccare container esistenti. Prima verifica porte/volumi e proponi una compose con password fornite solo via .env non versionato. Aggiungi test riproducibili e istruzioni per 201/202. Non dichiarare chiamata funzionante senza prova audio bidirezionale." 

## Prompt F2 dopo F1
"Implementa un percorso verticale SIP con engine astratto, login account demo, REGISTER, dial/answer/hangup ed eventi UI, partendo da Android e Asterisk. Verifica audio realmente in entrambe le direzioni. Mantieni Yeastar adapter non implementato finché non si convalida la documentazione."
