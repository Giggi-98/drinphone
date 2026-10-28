# Banco di prova, QA e criteri di promozione

## Topologia (proposta)
```
Android fisico / emulator ──LAN/VPN── Asterisk laboratorio ── est. 201/202
Linux desktop / Linphone ──────┘
Android fisico / desktop ──TLS── Yeastar P-Series test / DRIN pilota
Test WAN: hotspot LTE + NAT/firewall, niente porte SIP esposte senza ACL
```

## Sicurezza banco
Usare rete isolata / VPN e credenziali demo. Non esporre Asterisk direttamente su Internet con password banali. Alcuna porta 5060/5061/8088/AMI deve essere pubblica per default. Se esistono PBX/Docker preesistenti sulla macchina, **non** modificare o eliminare servizi senza approvazione; verificare porte e namespace prima di creare compose.

## Checklist laboratorio
- Asterisk config versionata come template, due interni 201/202, password solo environment/secrets locali, intervalli RTP e codecs espliciti.
- Softphone di riferimento su 201; DrinPhone su 202; numerazione fake e contatti sintetici.
- Yeastar test: edizione, firmware, licenze e permessi API registrati, senza copia di credenziali in evidenze.
- Misure: `flutter doctor -v`, `flutter test`, `flutter analyze`, compilazione, packet capture redatta, confronto SDP/offerte, cattura screenshot UI.

## Matrice manuale
| Caso | Ambiente | Passa quando | Stato |
|---|---|---|---|
| LAB-001 | Asterisk LAN | REGISTER + 200 e recupero rete | NON TESTATO |
| LAB-002 | Asterisk LAN | A→B audio due vie, hangup pulito | NON TESTATO |
| LAB-003 | Asterisk LTE | inbound/outbound con NAT | NON TESTATO |
| LAB-004 | Yeastar/DRIN | REGISTER, chiamata e codec | NON TESTATO |
| LAB-005 | Yeastar/DRIN | 1 BLF occupato/libero/squilla/unknown | NON TESTATO |
| LAB-006 | Yeastar/DRIN | transfer e pickup secondo capacità | NON TESTATO |
| LAB-007 | Android fisico | background/lock screen | NON TESTATO |
| LAB-008 | Android fisico | app terminata secondo policy | NON TESTATO |
| LAB-009 | desktop Linux | audio periferiche, tray | NON TESTATO |
| LAB-010 | tutte release | segreti assenti logs e aggiornamenti validati | NON TESTATO |

## Evidenza richiesta per ogni test
`Test ID`, data, commit SHA, OS/versione, PBX edition/firmware, topologia, config senza secret, passi, atteso/reale, esito, screenshot o traccia redatta e issue correlata. Stato consentito: `PASS`, `FAIL`, `BLOCKED`, `NOT RUN`; no esiti presunti.

## Gate CI e manuali
Lint+unit+widget test per PR; compilazioni native per piattaforme supportate; integration test contro banco reale pre-release; security scan/SBOM prima di rilascio. L'assenza di accesso a PBX/telefoni significa `BLOCKED`, non `PASS`.
