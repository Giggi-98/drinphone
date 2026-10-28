# DrinPhone — softphone proprietario per DRIN

**Stato: specifica e bootstrap, NON applicazione funzionante.** Repository destinato a Claude Code e Antigravity IDE. Owner prodotto: Econnet s.r.l.; branding/nome finale da approvare. Data base: 2026-10-28.

**Visione:** client SIP aziendale white-label orientato a DRIN PRO / Yeastar P-Series, interoperabile con PBX SIP standard. Android primo target eseguibile; desktop Linux secondo. iOS, Windows e macOS dopo prova di fattibilità SDK.

## Avvio rapido sul server Linux
```bash
sudo mkdir -p /opt/drinphone
sudo chown -R "$(id -u):$(id -g)" /opt/drinphone
# estrarre il contenuto di drinphone-bootstrap/ in /opt/drinphone
cd /opt/drinphone
git init
git add . && git commit -m "docs: bootstrap drinphone"
```
Eseguire i comandi come utente di sviluppo, NON root. Per creare una cartella senza cambiare proprietario, `mkdir -p /opt/drinphone` è sufficiente. `/opt/drinphone` ospita i sorgenti; non scrivere credenziali PBX in Git.

## Prima sessione dell'agente
Leggi `START-HERE.md` e `AGENTS.md`. Esegui **solo F0-A (spike SDK)** prima di inizializzare un'app definitiva. Gli esiti negativi sono risultati validi; non simulare chiamate funzionanti.

## Navigazione
- `CLAUDE.md`: regole di collaborazione e Definition of Done.
- `AGENTS.md`: istruzioni condivise per agenti IDE.
- `PIANO-AZIONE.md`: milestone, gate e backlog.
- `ARCHITECTURE.md`: architettura pianificata vs implementata.
- `DECISIONS.md`: scelte e aspetti da convalidare.
- `docs/ambiente-di-sviluppo.md`: setup e comandi.
- `docs/prodotto-e-requisiti.md`: utenti, scenari, priorità e non-obiettivi.
- `docs/sip-e-blf.md`: protocolli SIP, BLF, trasferimenti, test.
- `docs/yeastar-interop.md`: matrice P-Series / API / AMI.
- `docs/push-e-background.md`: inbound mobile e gateway.
- `docs/licenze-e-compliance.md`: gate prima della distribuzione chiusa.
- `docs/test-lab-e-qa.md`: banco e casi di prova.
- `docs/sicurezza-e-privacy.md`: minacce, dati, auditing.
- `docs/aggiornamenti-e-distribuzione.md`: release firmate, update.
- `docs/operativita-agenti.md`: workflow e task pronti da dare all'agente.
- `docs/fonti.md`: riferimenti e punti da riconfermare.
