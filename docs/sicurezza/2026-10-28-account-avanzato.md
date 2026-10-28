# Audit di sicurezza — account SIP avanzato e opzioni globali (2026-10-28)

Oggetto: campi tecnici dell'account (proxy, registrar, utente di
autenticazione, realm, scadenza, privacy, STUN/ICE/TURN) e opzioni globali
(cifratura media, keep-alive, DTMF).
Codice: `lib/core/sip/sip_engine.dart`, `lib/core/sip/linphone_ffi_engine.dart`,
`lib/core/security/settings_store.dart`, `lib/features/preferences/preferences_view.dart`.
Verifica: `test/profiles_test.dart` (andata e ritorno, segreti), avvio sul
pilota con gli account esistenti (nessun campo avanzato: comportamento invariato).

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Password TURN | OK | Solo in `flutter_secure_storage` (`turn_password_<id>`), mai nel JSON (test); cancellata se TURN è spento o l'account viene rimosso (test) |
| Log | OK | `SipAccount.toString()` invariato (utente@dominio, trasporto); nessun nuovo `debugPrint` con campi dell'account; il log SIP di liblinphone contiene il digest (hash), non la password |
| Cifratura media | ATTENZIONE | Globale e di default **Nessuna**: l'audio è in chiaro salvo scelta SRTP/ZRTP/DTLS; con PBX pubblici la segnalazione va comunque in TLS (CLAUDE.md §9). "Obbligatoria" rifiuta le chiamate non cifrate |
| TLS della segnalazione | INVARIATO | Verifica certificati di liblinphone di default; il proxy in uscita eredita il trasporto dell'account (`;transport=tls`) |
| Registrazioni fallite ripetute | NOTA | Con credenziali errate liblinphone ritenta il REGISTER (osservato sul pilota: 403 ogni ~60 s verso un trunk): alcuni provider bloccano l'IP. Interruttore "Registrazione attiva" per sospendere l'account |

## Riscontri
- **confirmed**: nessuno.
