# DrinPhone — primo avvio con Claude Code / Antigravity

Questo ZIP contiene **specifiche e istruzioni, NON il softphone**. Il nome ufficiale del prodotto è **DrinPhone**: softphone proprietario per l'ecosistema DRIN, interoperabile con SIP generico.

## 1. Preparare directory (Linux)

Il file ZIP contiene la cartella `drinphone-bootstrap/`. Dopo il download sul server, esegui ad esempio `unzip drinphone-operational-bootstrap.zip` e copia il suo contenuto in `/opt/drinphone`.
```bash
sudo mkdir -p /opt/drinphone
sudo chown -R "$(id -u):$(id -g)" /opt/drinphone
# Copia i contenuti di drinphone-bootstrap/ dentro /opt/drinphone
cd /opt/drinphone
git init
git add .
git commit -m "docs: initial DrinPhone specification"
```
Se sei già root, `mkdir -p /opt/drinphone` funziona ma è consigliabile uno user di sviluppo dedicato. Prima di estrarre l'archivio controlla sempre la struttura: nello ZIP c'è la directory `drinphone-bootstrap/`.

## 2. Leggere i file nell'ordine
`README.md` → `AGENTS.md` → `CLAUDE.md` → `ARCHITECTURE.md` → `DECISIONS.md` → `PIANO-AZIONE.md` → `docs/operativita-agenti.md`.

## 3. Primo prompt da incollare nell'IDE
> Leggi integralmente AGENTS.md, CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, PIANO-AZIONE.md, docs/licenze-e-compliance.md e docs/operativita-agenti.md. Esegui SOLO lo spike F0-A: verifica possibilità concreta di integrare liblinphone in Flutter Android e Linux, API, binding e licenze. Scrivi docs/spikes/F0-A.md con fonti upstream, versioni, comandi riproducibili, PASS/FAIL/BLOCKED e matrice alternative. Non generare l'intera app e non dichiarare supporto multipiattaforma senza una build dimostrata. Non installare servizi o cambiare Docker senza consenso.

## 4. Cosa significa pronto a codificare
F0-A dimostra che il motore può inizializzarsi, emettere eventi e avere API invocabili dal codice Flutter sul target pilota, con licenze catalogate e percorso plausibile per le altre piattaforme. Se non passa, decidere esplicitamente bridging nativo oppure SDK alternativo.

Riferimenti principali: `docs/prodotto-e-requisiti.md`, `docs/sip-e-blf.md`, `docs/yeastar-interop.md`, `docs/test-lab-e-qa.md`, `docs/push-e-background.md`, `docs/sicurezza-e-privacy.md`.
