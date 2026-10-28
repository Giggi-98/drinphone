# Contratto SIP, chiamate, BLF e compatibilità generica

## Confine architetturale
`SipEngine` espone `register/unregister`, `dial/answer/reject/hangup`, `hold/resume`, `mute`, `sendDtmf`, `blindTransfer/attendedTransfer`, `watchDialog`, `watchPresence`, `setAudioDevice`. Eventi tipizzati e testabili; nessuna UI chiama direttamente SDK nativo. Le funzioni non supportate restituiscono errore `unsupported`, NON successo silenzioso.

## Standard e feature discovery
- Segnalazione: SIP RFC 3261; digest auth; registrar/proxy/outbound proxy, UDP/TCP/TLS quando supportati e consentiti.
- Trasferimenti: REFER RFC 3515 + Replaces RFC 3891 per assistito, verificare modalità PBX.
- BLF: SUBSCRIBE/NOTIFY RFC 6665; dialog event package RFC 4235; il formato e il `Event` effettivamente emesso dal PBX vanno catturati in trace.
- Presence non è BLF: presence `pidf` (RFC 3863) e dialog-status possono esporre semantiche diverse. Non mischiarli.
- Pickup: codice funzione PBX o comando API esplicitamente supportato; mai hardcodare `*8` come universale.
- DTMF: RFC 4733 preferito; SIP INFO e in-band opzionali, testati PBX per PBX.
- Media: RTP/RTCP, codec PCMA/PCMU baseline, Opus quando negoziato. ICE/STUN/TURN ove necessario: NAT e audio mono-direzionale sono diagnosticati con traces redatti.
- Sicurezza: SIP TLS e SRTP SDES/DTLS-SRTP solo secondo capacità negoziate e policy. Non attivare un fallback in chiaro senza consenso esplicito.

## Semantica stati BLF
| Notifica SIP | Stato UI | Nota |
|---|---|---|
| dialog terminated / nessun dialog attivo | libero | solo dopo subscription valida |
| dialog early | squilla | potrebbe dipendere dal PBX |
| dialog confirmed | occupato | chiamata in corso |
| `<state>unregister</state>` (Yeastar, fuori RFC 4235) | non registrato | osservato su P-Series via RAS 2026-10-28 |
| subscription pending / timeout / 403 / formato ignoto | sconosciuto | mai mostrare verde per deduzione |

## Implementazione BLF per iterazioni
1. Registrare la capability SIP BLF e impedire subscription quando non abilitata.
2. Per una estensione, registrare request `SUBSCRIBE`, loggare solo metadata redatti (Call-ID sintetico, code, `Event`, `Expires`).
3. Elaborare 200/202/401/403/404/481/489 + rinnovo e NOTIFY iniziale; inviare risposta appropriata a NOTIFY tramite SDK.
4. Parsare XML con parser hardened (no XXE / no external entities), distinguendo version e partial/full updates.
5. Gestire dialog multiple, subscription termination/retry con backoff/jitter e limite su numerosità.
6. Testare 1, 10 e 50 interni su PBX reale senza assumere che il PBX abiliti subscriptions illimitate.

## Casi di test e failure mode
- REGISTER errate credenziali, auth challenge, DNS timeout, 403, 423, 503 e failover.
- INVITE esterno/interno, no audio, BYE remoto, CANCEL, re-INVITE, hold musica, trasferimento rifiutato, race tra chiamate.
- Cambio Wi-Fi↔LTE, sospensione app, NAT simmetrico, rete captive, cambio codec e dispositivi Bluetooth.
- Due account stesso numero interno su PBX differenti: isolare subscription e contatti per `accountId`.
- `NOTIFY` tardivi di subscription vecchia: non riscrivere lo stato della nuova.

## Prove
Conservare `docs/evidence/YYYY-MM-DD/<test-id>.md` senza credenziali; tool `sngrep`, Wireshark o log Asterisk, catture cifrate e redatte fuori repo. I test unitari simulano `SipEngine`; i test E2E verificano wire-level e audio ascoltato.
