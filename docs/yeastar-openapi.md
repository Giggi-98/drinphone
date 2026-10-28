# Yeastar P-Series OpenAPI — autenticazione, token e dati utili a DrinPhone

**Stato:** ricerca sulla documentazione ufficiale Yeastar (2026-10-28).
**Nessuna chiamata ancora fatta contro un PBX reale**: tutto ciò che segue è
`DA VALIDARE` sul PBX pilota (edition, firmware, piano). Fonti in fondo.

## 1. Prerequisiti sul PBX
| Requisito | Dettaglio | Fonte |
|---|---|---|
| Piano | API indicata per piano **Enterprise o Ultimate** (Cloud: Enterprise di default). Le tabelle dei piani non sono univoche: verificare sul PBX | blog Yeastar 2022-05, release notes, Central Management |
| Modello (Appliance) | Solo **P550, P560, P570** (P520 no); firmware Appliance ≥ 37.7.0.16 | Developer Guide Appliance (PDF) |
| Attivazione | Web portal **Integrations > API** → attiva API; mostra **Client ID** e **Client Secret** | Enable … API (tutte le edition) |
| Restrizione IP | Opzionale **IP Restriction**: solo gli IP ammessi usano l'API | idem |
| Monitor eventi | **Advanced Settings > Extension Status Monitor**: Registration (30007), Call Status (30008), Presence (30009), per gli interni scelti | idem |
| Accesso remoto (FQDN Yeastar) | **Features > Remote Access > API Access** = Enabled (+ IP restriction opzionale, sincronizzata con l'allow-list API). Base URL = `https://{pbx_fqdn_domain}` | Configure Network for Remote API Access by a Yeastar FQDN |
| Blocco IP | Superati i tentativi di autenticazione falliti, il PBX **blocca l'IP** del client (sbloccabile da portale) | Enable … API (Cloud) |

Il PBX pilota è raggiunto come `drin.ras.yeastar.com`, un FQDN Yeastar per
l'accesso remoto. Che si tratti di Appliance o Software Edition (non Cloud, che
usa `*.yeastarcloud.com`) è un'**inferenza**: confermarlo dal portale.

## 2. Struttura delle richieste
- URL: `{base_url}/openapi/v1.0/{endpoint}?access_token={access_token}`.
  Il token va **in query string**, non in un header.
- `base_url`: Cloud `https://{pbx_domain}`; Appliance/Software `https://{pbx_ip}:{https_port}`
  (8088 negli esempi, **non** garantito) o `https://{pbx_fqdn_domain}` via FQDN.
- Header **obbligatorio** `User-Agent` (es. `OpenAPI`); `Content-Type: application/json`.
- Risposte JSON con `errcode` (0 = successo) ed `errmsg` (`SUCCESS`/`FAILURE`).

## 3. Token: ottenere, rinnovare, revocare
**Ottenere** — `POST /openapi/v1.0/get_token`
```json
{ "username": "<Client ID>", "password": "<Client Secret>" }
```
Risposta: `access_token` (scade dopo **1800 s = 30 min**), `refresh_token`
(scade dopo **86400 s = 24 h**), `access_token_expire_time`, `refresh_token_expire_time`.
Massimo **8 access token validi per applicazione**: al limite serve attendere
la scadenza o revocarne uno.

**Rinnovare** — `POST /openapi/v1.0/refresh_token` con `{"refresh_token": "<ultimo>"}`;
restituisce una **nuova coppia** access/refresh. Usare sempre l'ultimo refresh
ricevuto. Se il refresh token è scaduto: nuovo `get_token`. (Non documentato se il
refresh token precedente viene invalidato: assumere di sì.)

**Revocare** — `GET /openapi/v1.0/del_token?access_token=<token>` (es. allo
spegnimento del servizio, o se il token è compromesso).

Ciclo consigliato: refresh a ~25 min dal rilascio; su `errcode` di token non
valido → refresh, poi `get_token`; mai ripetere `get_token` in loop (rischio
blocco IP e limite degli 8 token).

## 4. Dati che interessano DrinPhone
| Bisogno | Endpoint | Note |
|---|---|---|
| Elenco interni | `GET extension/list` (`page`, `page_size`, `sort_by`, `order_by`) | per ogni interno: `id`, `number`, `caller_id_name`, `email_addr`, `mobile_number`, `role_name`, `presence_status` (`available`, `away`, `business_trip`, `do_not_disturb`, `lunch`, `off_work`), `custom_presence_status`, `online_status` per `sip_phone` / `linkus_desktop` / `linkus_mobile` / `linkus_web` |
| Dettaglio interni | `extension/get`, `extension/query`, `extension/search` | |
| Reparti (gruppi opzionali, DECISIONS 2026-10-28) | `GET organization/list?is_all=1` | albero `children` con `ext_list` (ID degli interni) |
| Gruppi di interni | `extension_group/list` … | |
| Rubrica aziendale | `company_contact/list`, `/search`, `/get`, `/query`; `phonebook/list` … | campi da verificare sulla pagina dell'endpoint |
| Stato chiamata interni | evento **30008**: `{"extension":"2002","status":"Ringing"}`, `status` ∈ `Ringing`, `Busy`, `Idle` | richiede Call Status Monitor attivo per quegli interni |
| Registrazione / presenza | eventi **30007**, **30009** | formato payload da verificare |
| Cambi di anagrafica | eventi **30006** (struttura organizzativa), **30022** (info interno) | per invalidare la cache |

**Eventi via WebSocket:** `wss://{host}/openapi/v1.0/subscribe?access_token=…`,
poi `{"topic_list":[30007,30008,30009]}` → `{"errcode":0,"errmsg":"SUCCESS"}`.
La connessione cade dopo **60 s** senza traffico: inviare `heartbeat` (risposta
`heartbeat response`) ad es. ogni 30 s. Serve un token valido: alla scadenza va
rinnovato per mantenere la connessione. Alternativa: **Webhook** verso un URL
configurato nel portale (l'endpoint risponde 2xx).

## 5. Perché le credenziali API NON vanno nel client DrinPhone
- Lo stesso Client ID/Secret apre anche `extension/getpassword` (password SIP
  e PIN segreteria di **ogni** interno), `extension/create|update|delete`,
  `call/dial|listen|hangup`, CDR e registrazioni: è un'identità **amministrativa**.
  In ogni PC utente equivarrebbe a distribuire la chiave del centralino.
- **8 token per applicazione**: con più client contemporanei il limite si esaurisce.
- **Blocco IP** sui fallimenti: un client mal configurato può bloccare l'IP di un'intera sede.
- **IP Restriction** ha senso solo con pochi IP fissi (un server), non con i PC degli utenti.

Coerente con `DECISIONS.md` (2026-10-28 · Credenziali API e AMI) e CLAUDE.md §12.
**AMI** resta fuori: non è un'interfaccia offerta da Yeastar P-Series.

## 6. Architettura proposta (PROPOSTA, non implementata)
```
DrinPhone (client)  --HTTPS, token utente limitato-->  Gateway Econnet (1 per PBX/tenant)
                                                          | Client ID/Secret in secret store
                                                          | 1 coppia token, refresh ~25 min
                                                          | 1 WebSocket eventi 30006/30007/30008/30009/30022 + heartbeat 30 s
                                                          v
                                                     Yeastar P-Series OpenAPI (IP Restriction = IP del gateway)
```
Il gateway espone **solo lettura** e solo ciò che serve: elenco interni, reparti,
rubrica, stati. Il BLF SIP già funzionante resta il percorso standard; gli stati
dal gateway arricchiscono (presence, Linkus online) e coprono i PBX senza BLF.

Decisioni aperte prima di scriverlo: hosting (server Econnet / VM cliente),
come si autentica l'utente DrinPhone verso il gateway, un gateway per cliente o
multi-tenant, retention dei dati personali (rubrica, numeri).

## 7. Verificato sul PBX pilota (2026-10-28, via FQDN RAS)
`get_token`, `extension/list` (50 interni, `id`/`number`/`caller_id_name`/`presence_status`),
`organization/list?is_all=1` (6 reparti annidati con `ext_list`), `del_token`.
Il client rilegge interni e reparti ogni 60 s (presenza); WebSocket eventi non usato.

## 7b. Ancora da verificare sul PBX pilota
Edition e firmware; piano; API attivabile; `get_token` da IP ammesso; formato
reale di `extension/list`, `organization/list`, `company_contact/list`; payload
30007/30009; comportamento del refresh token precedente; codici di errore.

## Fonti
- Get Access Token: https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/get-access-token.html
- Refresh Access Token: https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/refresh-access-token.html
- Revoke Access Token: https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/revoke-access-token.html
- Authorization Rule: https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/authorization-rule.html
- Request Structure (Cloud): https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/request-structure.html
- Request Structure (Appliance): https://help.yeastar.com/en/p-series-appliance-edition/developer-guide/request-structure.html
- Request Structure (Software): https://help.yeastar.com/en/p-series-software-edition/developer-guide/request-structure.html
- Enable API (Appliance): https://help.yeastar.com/en/p-series-appliance-edition/developer-guide/enable-yeastar-p-series-pbx-api.html
- Enable API (Cloud): https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/enable-yeastar-p-series-pbx-api.html
- Remote API Access via FQDN: https://help.yeastar.com/en/p-series-software-edition/administrator-guide/configure-network-for-remote-api-access-by-a-yeastar-fqdn.html
- API Interfaces & Events Summary: https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/api-interfaces-and-events-summary.html
- Query Extension List: https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/query-extension-list.html
- Query Organization List: https://help.yeastar.com/en/p-series-software-edition/developer-guide/query-organization-list.html
- Event 30008: https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/event-extension-call-status-changed.html
- Monitor Events via WebSocket: https://help.yeastar.com/en/p-series-appliance-edition/developer-guide/monitor-events-via-websocket.html
- API Events Overview: https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/api-events-overview.html
- Developer Guide Appliance (PDF): https://help.yeastar.com/download/docs/p-series-developer-guide-appliance-edition-en.pdf
- Login API (supporto Yeastar): https://support.yeastar.com/hc/en-us/articles/23744152078361-How-To-Login-the-API-of-Yeastar-P-Series-PBX
