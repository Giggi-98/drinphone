# Chiamate mobili in background / app terminata

**Gate non negoziabile prima di vendere l'esperienza mobile.** Un REGISTER SIP in foreground non dimostra ricezione affidabile ad app terminata. Non promettere comportamento uguale tra Android/iOS né quando l'utente forza l'arresto dell'app.

## Domande da chiudere nello spike F4
- PBX supporta SIP push RFC 8599 oppure richiama un servizio notifiche autorizzato? Serve un proxy registrante sempre online? Dove termineranno le registrazioni e la route delle chiamate?
- Come sono associati tenant, extension, device e push token? Come si revoca token e si evita squillo del vecchio device?
- Chi gestisce APNs VoIP (PushKit), FCM e la loro disponibilità? In iOS rispettare obbligo di segnalare prontamente le chiamate VoIP a CallKit e le policy Apple correnti.
- Android: scegliere Telecom / ConnectionService (eventualmente Core-Telecom) e policy foreground service / full-screen intent correnti, testandole sui vendor Android reali.

## Opzioni
A. PBX/PBX proxy supporta direttamente SIP push RFC 8599, con app e token compatibili: preferita se prova end-to-end positiva.
B. Gateway VoIP di Econnet o proxy SIP con funzionalità push (es. Flexisip se compatibile) che mantiene i binding e inoltra gli inviti: richiede routing, sicurezza e disponibilità 24x7.
C. Soluzione limitata a foreground/desktop: ammessa nel prototipo, **non** pubblicizzabile come mobile always-on.

## Sequenza desiderata
`Incoming INVITE → PBX/proxy autorizzato → push gateway → APNs/FCM → app risvegliata → CallKit/Telecom UI → SIP INVITE disponibile/recuperato → answer → RTP`. Ogni freccia richiede test reale; il push **non** contiene credenziali SIP, dettagli sensibili o l'intero INVITE in chiaro.

## Casi limite
App foreground, background, schermo bloccato, processo terminato dal sistema, force-stop utente, riavvio telefono, cambio rete, token scaduto, DND, due device, chiamata cancellata prima del risveglio, push duplicato, rete assente. Registrare risultati separati per OS/versione.

## Non introdurre scorciatoie
Nessun polling perpetuo, nessun keepalive aggressivo per aggirare policy batteria, nessun token FCM/APNs hardcoded, nessuna promessa che una gateway generica si integri automaticamente con Yeastar.
