# Yeastar / DRIN P-Series — interoperabilità operativa

**Stato:** specifica da convalidare contro PBX reali e documentazione della propria edition/firmware. Distinguere `Yeastar P-Series Appliance`, `Software Edition`, `Cloud Edition`; il solo marchio DRIN non determina la versione API installata.

## Tre piani separati
1. **SIP core** (UDP/TCP/TLS + RTP): registrazione, chiamate, REFER, DTMF; nessuna autenticazione API necessaria.
2. **SIP BLF** (SUBSCRIBE/NOTIFY): stati linea se abilitati dal PBX e gestiti dall'SDK.
3. **Yeastar OpenAPI/Eventi**: funzionalità autorizzate, rubrica, controlli e monitoraggio *solo se esplicitamente presenti* nelle API di quella edition; API separate dalle credenziali SIP.

**AMI:** Asterisk Manager Interface è un protocollo amministrativo specifico dell'ecosistema Asterisk, **non** un'interfaccia standard promessa da Yeastar P-Series. Non collegare il client AMI direttamente a Internet né inserire credenziali AMI in un'app utente. Per Asterisk/FreePBX l'eventuale adattatore AMI/ARI deve vivere su un **backend controllato**, con permessi minimi e accesso autenticato. Per Yeastar preferire OpenAPI ufficiale.

## Discovery prima dell'integrazione
- Rilevare tramite configurazione provisioning (preferita) / endpoint ufficiale PBX e edition+firmware; non eseguire scanning aggressivo.
- Ogni feature ha `supported`, `unsupported`, `requiresAdmin`, `requiresBackend`, `unknown` e una fonte di supporto verificata.
- Se API manca/non autorizzata: il client continua a chiamare in SIP puro. Non fingere stati/contatti aggiornati.
- I server-to-server secret e Client Secret dell'integrazione sono **solo backend** in produzione. Client mobile/desktop usa un token utente a privilegi limitati verso gateway Econnet, se realizzato.

## Catalogo iniziale (NON assumere endpoint specifici senza doc)
| Feature | Piano preferito | Proprietario | Verifica necessaria |
|---|---|---|---|
| REGISTER e chiamata | SIP | client | account SIP, TLS, codec |
| BLF interni | SIP dialog subscription | client | 200/NOTIFY, event package e ACL |
| Pickup | SIP feature code oppure API | PBX | codice configurabile e permessi |
| Presence / DND | Yeastar OpenAPI/event oppure SIP presence | adapter | semantica stato per edition |
| Directory aziendale | endpoint ufficiale o LDAP/autorizzato | adapter/backend | scope e paginazione |
| CDR e registrazioni | OpenAPI via backend se consentito | backend | autorizzazioni e privacy |
| Queue / agent status | OpenAPI/eventi se previsto | backend | edition, eventi e ruoli |
| CTI click-to-call | OpenAPI se previsto | adapter | chiamata originata dal server vs da client |

## Setup PBX laboratorio
1. Ambiente dedicato, estensioni `201` e `202`, account senza privilegi admin, dati fittizi.
2. Abilitare `Integrations > API` **solo** se serve e limitare IP; configurare client ID/secret di test con privilegi minimi. La documentazione ufficiale indica API per P-Series e monitor extension status configurabile.
3. Confermare URL e path dal manuale di edition (esempio pubblicato: `/openapi/v1.0/get_token`; porta HTTPS locale spesso 8088, **non** garantita).
4. Inviare `User-Agent` come richiesto da Yeastar; gestire token refresh e revoca, timeout e 401.
5. Verificare eventuali endpoint/eventi nella pagina `API Interfaces & Events Summary` relativa all'edition, NON indovinarli.
6. Documentare casi `API disabled`, licenza API non attiva, 403, feature non disponibile, firmware differente e rete remota.

## Contratto adattatore
- `PbxCapabilities`, `PbxDirectory`, `PbxPresence`, `PbxCallControl`; implementazione `GenericSipAdapter` di base e `YeastarPSeriesAdapter` opzionale.
- Non condividere la stessa sessione tra account di clienti diversi. Tenant/accountId obbligatorio in cache e subscription.
- Eventi asincroni con ordinamento, deduplica, reconnect, expiry e TTL; al disallineamento mostrare `unknown`.
- HTTP: HTTPS validato, timeouts, retry solo safe/idempotent; mai ignorare errori certificato.

## Matrice da compilare con test vero
| PBX/edition | Firmware | SIP TLS/SRTP | BLF SIP | OpenAPI | Push terminated | Esito/data |
|---|---|---|---|---|---|---|
| DRIN PRO (istanza pilota, via RAS) | TBD | TLS/SRTP non testati | PARZIALE: SUBSCRIBE dialog accettata, NOTIFY full ricevuto | TBD | TBD | 2026-10-28, `docs/test/2026-10-28-windows-yeastar-ras.md` |
| Yeastar P-Series Appliance | TBD | TBD | TBD | TBD | TBD | NON TESTATO |
| Yeastar P-Series Software | TBD | TBD | TBD | TBD | TBD | NON TESTATO |
| Yeastar P-Series Cloud | TBD | TBD | TBD | TBD | TBD | NON TESTATO |
| Asterisk/FreePBX | TBD | TBD | TBD | n/a | TBD | NON TESTATO |

Dettaglio OpenAPI (token, refresh, endpoint interni/reparti/rubrica, eventi, architettura gateway): `docs/yeastar-openapi.md`.

Riferimenti: `docs/fonti.md`. Non usare reversing del client Linkus come fonte autoritativa né copiare asset o codice di Yeastar.
