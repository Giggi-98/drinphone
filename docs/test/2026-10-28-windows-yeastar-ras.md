# Prova reale — DrinPhone Windows contro Yeastar P-Series via RAS (2026-10-28)

**Ambiente:** DrinPhone 0.1.0 debug (Flutter 3.47.8, linphone-sdk-win64 5.5.39),
Windows 11, workstation in LAN 192.168.55.0/24 dietro NAT. PBX Yeastar P-Series
raggiunto tramite Remote Access Service (`*.ras.yeastar.com`), trasporto **TCP**,
interno di prova 305. Log di debug del motore attivo. Linkus Desktop aperto in
parallelo sullo stesso interno. Nessuno STUN/ICE configurato.

| Prova | Esito | Evidenza (log motore) |
|---|---|---|
| REGISTER con digest | PASS | 401 → 200 OK; rinnovi ogni 33–80 s imposti dal RAS; Contact riscritto dal RAS con `;webpc` |
| Chiamata uscente verso numero esterno | PASS | PCMA/8000; 757 pacchetti RTP inviati / 761 ricevuti, 1 perso, jitter 0,5 ms, RTT 20 ms; BYE 200 OK |
| Chiamata entrante da interno | PASS | IncomingReceived → pannello Rispondi/Rifiuta → Connected; Opus/48000; 401 pacchetti ricevuti, 0 persi |
| Audio nei due versi | PASS (ascoltato) | Confermato dall'utente sulla chiamata entrante: "l'audio funzionava perfettamente" |
| Coesistenza con Linkus Desktop sullo stesso interno | PASS | Registrazioni ed entrante funzionanti con Linkus aperto |
| BLF SIP (SUBSCRIBE dialog) su interno 301 | PASS (solo Libero) | `Subscription-State: active;expires=613`; NOTIFY `dialog-info` full con dialog `terminated` → Libero. Squilla/Occupato non ancora osservati |
| OpenAPI via FQDN: token + `extension/list` + `organization/list?is_all=1` | PASS | 50 interni, 6 reparti annidati; presenza mostrata sulle schede |
| BLF su 49 interni (lista PBX) | PASS | 32 Libero, 1 Occupato, 16 **Non registrato**: Yeastar invia `<state>unregister</state>` (fuori RFC 4235), prima mostrato per errore come Squilla, corretto con test |
| Password nel log di debug | OK (parole chiave) | vedi `docs/sicurezza/2026-10-28-account-sip-windows.md` |

**Non provato:** muto, DTMF, rifiuto, chiamata persa/occupato, rete degradata o
cambio rete, UDP/TLS, PBX senza RAS, chiamata a lungo termine (> 1 min), app in
secondo piano (non c'è ancora notifica Windows né ritorno in primo piano della finestra).
