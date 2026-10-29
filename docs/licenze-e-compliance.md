# Licenze, IP e passaggio a prodotto chiuso — RELEASE BLOCKER

**Non è un parere legale.** Revisione di legale/licensing prima di ogni distribuzione esterna a clienti, beta inclusa.

## Regola fondamentale
Liblinphone/linphone-sdk sono disponibili con condizioni open source copyleft (secondo componente/versione, GPLv3 o AGPLv3) **oppure licenza proprietaria commerciale** da Belledonne Communications. La scelta di licenza deve essere verificata per versione e librerie effettivamente collegate. Un repository Git privato **non** rende legale distribuire binari closed-source in violazione dei termini copyleft. Sviluppo e test interni non sono automaticamente equivalenti a distribuzione a clienti.

## Strategia
1. F0: inventario di SDK/plugin/transitive dependencies e loro licenze, repository, commit, binari, provenienza.
2. Prima di codificare il binding definitivo, contattare Belledonne per **preventivo e copertura contrattuale**: Flutter/custom binding, Android/iOS/desktop, distribuzione B2B white-label, aggiornamenti, supporto, codec, numero installazioni e sublicenze.
3. Evitare dipendenze GPL/AGPL aggiuntive non coperte dalla licenza commerciale del vendor; verificare flags di build `GPL third parties`, FFmpeg, codec e brevetti.
4. Prototipo interno: mantenerne tracciabilità licenze e notices; non chiamarlo 'vendibile' finché non c'è conferma legale.
5. Prima della beta esterna: approvazione documentata di compliance, privacy e sicurezza; accordo di licenza effettivo se si intende codice chiuso.

## Registro componenti (da compilare, non presunto)
| Componente | Versione/commit | Licenza verificata | Uso | Fonte/approvazione |
|---|---|---|---|---|
| Flutter SDK | TBD | TBD | framework | TBD |
| liblinphone/linphone-sdk | TBD | GPL/AGPL oppure commerciale: verificare | SIP/media | TBD |
| Flutter native bridge | TBD | TBD | FFI/platform channels | TBD |
| OpenH264 (Cisco, binario) | 2.2.0, SHA-256 DLL `9b392bf0…d2d0` | BSD-2 (codice); brevetti H264 coperti da Cisco **solo** se il binario è scaricato da Cisco sul PC dell'utente | codec H264 | DECISIONS 2026-10-29 "Videochiamate"; non ridistribuire |
| `libmsopenh264` (plugin SDK) | msopenh264 1.2.1 | come linphone-sdk | ponte verso OpenH264 | incluso nel pacchetto |
| Push provider | TBD | ToS/DPA da verificare | notifiche | TBD |
| Altre dipendenze e asset | TBD | TBD | varie | TBD |

## Artefatti obbligatori per release
`SBOM` CycloneDX/SPDX, third-party notices, repository commit pinning, report license scanner, approvazione legale, policy delle vulnerabilità, accordo commerciale firmato ove necessario, provenienza binari e firma release. Nessun codice o icona presi dal client proprietario Linkus. Branding e marchio DRIN da approvare internamente.

Fonti: https://www.linphone.org/en/faq/ ; https://wiki.linphone.org/xwiki/wiki/public/view/Lib/ ; https://gitlab.com/linphone2/linphone-sdk/-/blob/master/README.md
