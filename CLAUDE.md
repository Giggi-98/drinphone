# Linee guida di progetto — DrinPhone (softphone Econnet)

Fonte unica per tutti gli agenti (umani e AI) che lavorano su questo repo.
Modificare qui, non duplicare. Deriva dalle linee guida di casa Econnet (suite
Gest) e le riadatta a un prodotto nuovo: un softphone VoIP multipiattaforma.

**Tradeoff:** queste regole privilegiano la cautela sulla velocità. Per task
banali, usa il giudizio.

## 0. Cos'è questo prodotto

Softphone SIP **proprietario di Econnet srl**, multipiattaforma da **un unico
codice Flutter** (Android, iOS, Windows, macOS, Linux). Motore chiamate:
**liblinphone** (linphone-sdk). Due strati:

- **Nucleo SIP standard** — si registra a qualunque PBX o trunk VoIP (Asterisk,
  FreePBX, Kamailio, Yeastar via estensione SIP). Nessun lock-in.
- **Strato Yeastar P-Series** (opzionale, target primario) — funzioni UC
  (presence, rubrica, CDR, BLF) via API P-Series ufficiale.

**Non** è un clone di Linkus e **non** riusa codice o asset di Yeastar: l'API
Yeastar è un'interfaccia documentata (interoperabilità), non codice copiato.

## 1. Pensa prima di scrivere codice

Prima di tutto leggi `ARCHITECTURE.md` (la mappa) e poi `DECISIONS.md` (il
perché). Se ARCHITECTURE contraddice il codice, fermati e segnalalo. Dichiara le
assunzioni; se ci sono più interpretazioni presentale invece di sceglierne una
in silenzio; se esiste una strada più semplice, dillo; se qualcosa non è chiaro,
fermati e chiedi. Non riproporre un'alternativa già scartata in `DECISIONS.md`
senza citarla.

## 2. Semplicità prima di tutto

Codice minimo che risolve il problema. Niente feature non chieste, niente
astrazioni per codice usato una volta, niente "flessibilità" non richiesta,
niente gestione di errori impossibili. Se scrivi 200 righe e ne bastano 50,
riscrivi.

## 3. Modifiche chirurgiche

Tocca solo ciò che serve. Non "migliorare" codice adiacente, non rifattorizzare
ciò che non è rotto, rispetta lo stile esistente. Rimuovi gli orfani creati
dalle TUE modifiche; non cancellare codice morto preesistente senza chiederlo.
Ogni riga cambiata deve tracciare direttamente alla richiesta.

## 4. Esecuzione guidata dall'obiettivo

Trasforma i task in obiettivi verificabili. Per il VoIP, **"funziona" = provata
contro un PBX vero con audio ascoltato nei due versi** (vedi §5 e §8), non "il
codice compila". Per task multi-step, dichiara un piano breve con la verifica di
ogni passo.

## 5. Le realtà del VoIP (leggi prima di toccare le chiamate)

È l'equivalente, per la voce, della regola "rendi e guarda" della UI: il codice
è pulito e la chiamata è comunque sbagliata. Trappole che dal diff non si vedono:

- La chiamata "parte" nel codice ma **non c'è audio**: RTP bloccato, NAT,
  profili SRTP che non combaciano, codec che non combaciano.
- **Audio a senso unico** = quasi sempre NAT / RTP simmetrico / assenza di
  STUN/TURN.
- **Registrazione OK ma le chiamate in arrivo non arrivano ad app chiusa**
  (mobile) → serve il push che sveglia l'app. Non è un bug del codice: è
  architettura (vedi `docs/aggiornamenti-e-distribuzione.md` e DECISIONS).
- **Codec**: concordare sempre **Opus + G.711 (PCMA/PCMU)** come fallback;
  Yeastar di default parla PCMA.
- **TLS/SRTP**: se i profili non combaciano, la chiamata cade o resta muta.

Non fidarti mai del "sembra a posto": prova la chiamata vera, ascolta l'audio
nei due versi, in rete buona **e** cattiva. Il banco PBX è obbligatorio come gli
screenshot lo sono per la UI.

## 6. Documentazione architetturale (`ARCHITECTURE.md`)

Se cambi la forma del sistema, aggiorna `ARCHITECTURE.md` **nello stesso commit**.
Obbligatorio se la modifica:

| Cambiamento | Dove |
|---|---|
| Nuovo servizio core (SIP, push, storage, audio, update) | albero · moduli · flussi |
| Nuovo canale piattaforma (CallKit / ConnectionService / audio device) | moduli · flussi |
| Nuova dipendenza nativa o plugin Flutter rilevante | dipendenze |
| Cambio del modello di stato (macchina a stati della chiamata) | moduli · flussi |
| Nuova integrazione API Yeastar (endpoint, token, evento) | moduli · flussi · §attenzione |
| Nuovo flusso di registrazione / push / provisioning / aggiornamento | flussi |
| Cambio di auth, storage credenziali, TLS/SRTP | moduli · flussi · §attenzione |

Non serve per bugfix, refactor interni a un file, UI che non cambia contratti,
test. Chirurgico, descrivi cosa c'è (non cosa vorresti), rimuovi ciò che non
esiste più.

## 7. Registro decisioni (`DECISIONS.md`) — append-only

`ARCHITECTURE.md` dice *com'è*; `DECISIONS.md` dice *perché, e cosa è stato
scartato*. Aggiungi una voce quando c'era più di una strada e ne hai chiusa una.
Il campo che conta è **"Da rivedere se"**. **Non modificare né cancellare voci
esistenti**: se una decisione viene ribaltata, aggiungi una voce nuova in cima
che cita la vecchia. Se la decisione riguarda un file solo, va in testa a quel
file con l'intestazione di casa:
`─── PERCHÉ NON BASTA <l'alternativa ovvia> ───` e in `DECISIONS.md` solo un
rimando.

## 8. Lavoro di interfaccia — rendi, guarda (su ogni piattaforma)

Una modifica alla UI non è verificata finché non l'hai resa e **guardata**, su
ogni target rilevante (emulatore Android, Linux/Windows desktop; iOS solo con un
Mac). Fotografa gli **stati**, non la pagina: a riposo, in chiamata, chiamata in
arrivo, in attesa, trasferimento, errore, assenza di rete — e sempre nei due temi
(chiaro/scuro) e a larghezza di telefono piccolo. Per il softphone, allo
screenshot si aggiunge la prova della **chiamata reale** (§5).

## 9. Audit di sicurezza (VoIP)

**Obbligatorio prima del commit** per ogni funzione che tocca un confine:
credenziali SIP, storage sicuro (`flutter_secure_storage` → Keychain/Keystore),
TLS della segnalazione, SRTP/ZRTP del media, token push, chiamate all'API
Yeastar, permessi (microfono, fotocamera, notifiche, rete). Regole:

- **Mai** loggare password SIP, chiavi SRTP, token push o di sessione.
- Credenziali solo nello storage sicuro della piattaforma, mai in chiaro.
- TLS obbligatorio per la segnalazione verso PBX pubblici; valuta il pinning.
- Ogni riscontro `confirmed` si corregge prima del commit, con un test che lo
  riproduce. Nel messaggio finale: cosa è stato rivisto e cosa è emerso (anche
  "niente"). Report datato in `docs/sicurezza/AAAA-MM-GG-<oggetto>.md`.
- **Fase di security test mirata** (dal 2026-10-30): ogni funzione nuova e ogni
  modifica strutturale (i casi della tabella §6) chiude con un run della skill
  `security-audit` ([cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill)),
  profilo `quick`, *scoped* sui file toccati e sui confini che attraversano.
  Output fuori dal repo (`~/security-audit-skill/drinphone/run-<N>`, i run sono
  additivi); la sintesi va nel report datato qui sopra. I validatori `.cjs`
  della skill girano solo in WSL (`wsl -d Ubuntu node …`): su Windows nativo
  rifiutano l'input per mancanza di protezione no-follow.

## 10. Vincoli di piattaforma (conoscili prima di promettere date)

- **iOS si compila SOLO su macOS con Xcode.** Senza un Mac: build su cloud
  (Codemagic / GitHub Actions con runner macOS) o iOS rimandato. Android, Linux
  e Windows si fanno dal tuo PC.
- **Aggiornamento automatico**: sul **desktop** l'app può auto-aggiornarsi; su
  **mobile no** — iOS/Android passano dagli store (o da MDM aziendale). Il client
  legge comunque un *manifest* e, su mobile, rimanda allo store. Dettagli in
  `docs/aggiornamenti-e-distribuzione.md`.
- **Note di rilascio**: ogni versione buildata ha `release-notes/<versione>.md`,
  scritte per l'utente finale (sezioni `## Novità`, `## Miglioramenti`,
  `## Correzioni`, `## Sicurezza`, `## Da fare dopo l'aggiornamento`; voci
  `- …`). Senza, la build e i test falliscono; l'app le mostra in un popup.
- **Push VoIP**: iOS = PushKit + entitlement (serve Apple Developer); Android =
  FCM ad alta priorità + ConnectionService.
- **Firma**: code signing Windows (certificato), notarization su macOS,
  keystore di firma per Android.

## 11. Strumenti

Flutter SDK + Dart, Android Studio (+ SDK/emulatore), Xcode (solo su Mac),
`linphone-sdk` via plugin Flutter, un **PBX di prova** in Docker
(Asterisk/FreePBX) e un **softphone di riferimento** (Linphone, Zoiper) per avere
l'altro capo della chiamata. Un Yeastar P-Series di test per lo strato UC.

---

**Queste regole funzionano se:** meno modifiche inutili nei diff, meno riscritture
da sovra-ingegnerizzazione, e le chiamate si provano contro un PBX vero prima di
dichiararle fatte.

## 12. Integrazioni e licenze — regole aggiornate 2026-10-28
- `AGENTS.md` e `docs/operativita-agenti.md` contengono workflow condiviso con Antigravity.
- **Non dare per verificato** che il plugin Flutter liblinphone sia ufficiale o completo per Android/iOS/Windows/macOS/Linux: prima F0-A produce matrice supporto e PoC. `linphone_flutter_plugin` di terze parti può essere limitato ad Android.
- **Non promettere software proprietario distribuibile** usando una SDK copyleft GPL/AGPL senza risolvere la licenza commerciale e le licenze transitive. Vedi `docs/licenze-e-compliance.md`.
- **AMI non è Yeastar OpenAPI**: evitare AMI in client utenti; backend-only per Asterisk se necessario. BLF SIP SUBSCRIBE/NOTIFY prima delle API private.
- Separare `IMPLEMENTATO`, `DA VALIDARE` e `NON TESTATO`; `ARCHITECTURE.md` non deve spacciare componenti pianificati per esistenti.
- F4/push richiede prova end-to-end con PBX/proxy, non si presume solo installando CallKit o FCM.
- Credenziali API amministrative Yeastar nel client **solo** come da `DECISIONS.md` 2026-10-28 (bis): sola scrittura, cifrate DPAPI, mai nei log, endpoint in lettura; in scrittura **solo** il proprio interno e i campi utente di `YeastarApi.ownWritable` (`DECISIONS.md` 2026-10-30 "Scrittura sul proprio interno"). Mai AMI nel client.
