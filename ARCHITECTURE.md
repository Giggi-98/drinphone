# ARCHITECTURE — DrinPhone

> Scheletro da riempire a partire da F0. Mantienilo contestuale ai commit
> (CLAUDE.md §6). Descrivi cosa c'è, non cosa vorresti.

## 1. Sintesi
Softphone Flutter multipiattaforma. Motore: liblinphone. Nucleo SIP standard +
strato Yeastar P-Series opzionale. *(da espandere)*

## 2. Albero del progetto
`lib/`, `android/`, `ios/`, `linux/`, `windows/`, `macos/`, `test/`, `docs/`.
*(dettaglia i moduli di `lib/` man mano)*

## 3. Moduli (da riempire)
- **SIP core** — wrapper su liblinphone: account, registrazione, chiamate, media.
- **Macchina a stati chiamata** — idle / in uscita / squilla / attiva / in attesa / chiusa.
- **Push** — ricezione chiamate ad app chiusa (gateway + APNs/FCM). *(F4)*
- **Storage sicuro** — credenziali SIP e token.
- **Strato Yeastar** — client API P-Series, isolato dal nucleo SIP. *(F6)*
- **Update** — lettura manifest, auto-update desktop, rimando store mobile. *(F7)*
- **UI/State** — gestione stato (es. Riverpod/Bloc), schermate.

## 4. Flussi (da riempire)
- Registrazione account → PBX.
- Chiamata uscente / entrante (con e senza app in foreground).
- Risveglio da push → CallKit/ConnectionService → risposta.
- Controllo aggiornamenti all'avvio.

## 5. Dipendenze
Flutter/Dart, linphone-sdk (plugin Flutter), flutter_secure_storage,
(push/callkeep da definire), client HTTP per lo strato Yeastar. *(elenca le versioni reali)*

## 6. Punti di attenzione
Qui vanno fragilità, vincoli, trappole. (Es. push ad app chiusa, NAT/RTP,
vincolo build iOS/Mac.)

## 7. Architettura target (PROPOSTA, non implementata)
```
UI Flutter (Dialer/Call/Contacts/BLF/Settings/Diagnostics)
  ├── State controllers (sessione/account/call/presence)
  ├── Application use cases
  │     ├── CallService -> SipEngine interface -> Native Linphone bridge (DA VALIDARE F0-A)
  │     ├── BlfService -> SIP SUBSCRIBE/NOTIFY oppure Unknown
  │     ├── ContactsService -> Local + ProviderAdapter
  │     └── PbxCapabilities -> Generic SIP / Yeastar P-Series provider
  ├── Local storage (secure credentials, preferences, call history)
  └── Platform adapters (audio routes, telecom UI, native notifications, updater)
         [futuro backend Econnet: provisioning, privileged API broker, push gateway]
```

**Non implementato:** nessuno dei moduli descritti sopra è codice esistente nel bootstrap. I nomi sono contratti di progetto, non API reali del SDK.

### Confini e regole di dipendenza
- `SipEngine` è porta astratta; un solo adattatore incapsula la SDK nativa; non esporre i tipi liblinphone alla UI.
- `PbxCapabilities` impedisce funzioni non permesse; il Generic SIP adapter non richiede endpoint Yeastar.
- Provider Yeastar si basa solo su OpenAPI pubblica/ufficiale per edition; token privilegiati rimangono su backend.
- `BlfService` usa prima la subscription SIP dialog e tratta le sessioni non supportate come `unknown`.
- Push gateway è un componente separato, opzionale **solo per prototipo foreground**; blocco per distribuzione mobile always-on.
- Nessuna assunzione che Flutter plugin terzi supportino le 5 piattaforme: milestone F0-A valida binding, licensing e artefatti.

### Percorsi suggeriti DOPO lo spike
```
lib/app/                 # bootstrap, navigation, DI
lib/features/dialer/     # UI e stato
lib/features/call/       # chiamata e controller
lib/features/contacts/   # rubrica
lib/features/blf/        # BLF e lifecycle
lib/features/settings/   # configurazione account
lib/core/sip/            # contratti senza riferimenti native
lib/core/pbx/            # capabilities e provider
lib/core/security/       # secure storage e redaction
packages/drinphone_linphone_bridge/  # eventuale plugin privato con binding nativi
integration_test/        # test device/PBX
```
Creare cartelle solo se il modulo è in sviluppo. Risultato reale dello spike in `docs/spikes/F0-A.md`.

### Flusso chiamata minimal
`UI -> CallController -> SipEngine -> native SDK -> PBX -> RTP` con eventi SDK riportati verso UI attraverso stream a stati; retry SIP e chiamate separate, niente retry di INVITE alla cieca.

### Flusso BLF
`Account registrato -> SUBSCRIBE -> NOTIFY -> parser dialog -> stato (idle/ringing/busy/unknown) -> UI`; timer rinnovi, unsubscribe e backoff gestiti dentro servizio.

### Flusso UC
`User -> ProviderCapabilities -> YeastarAdapter (backend per scope privilegiati) -> OpenAPI/eventi`; non blocca il core SIP quando backend offline.
