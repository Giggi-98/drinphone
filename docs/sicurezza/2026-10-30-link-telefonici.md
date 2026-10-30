# 2026-10-30 — Istanza unica e link telefonici (click-to-call)

Run: `~/security-audit-skill/drinphone/run-9` (profilo `quick`, scoped sul
diff della funzione). Revisione solo sul sorgente (nessuna sandbox).

## Oggetto
- `windows/runner/main.cpp`, `flutter_window.cpp/.h` (mutex, `WM_COPYDATA`, canale `drinphone/instance`)
- `lib/core/platform/call_links.dart` (`numberFromLink`, `listenForCallLinks`)
- `lib/features/shell/home_screen.dart` (dialogo di conferma)
- `installer/drinphone.iss` (ProgID, `URLAssociations`, `RegisteredApplications`)
- `lib/features/preferences/preferences_view.dart` (pulsante "App predefinite")

Minaccia principale: una pagina web o un'email che apre link `tel:`/`sip:`
(chiamate indesiderate, numeri a pagamento).

## Riscontri
| # | Gravità | Riscontro | Esito |
|---|---|---|---|
| 1 | media | "Chiama" aveva il fuoco e la finestra veniva in primo piano: un Invio/Spazio digitato per un'altra finestra faceva partire la chiamata. | **corretto**: fuoco su Annulla; Chiama si attiva dopo 1,2 s. |
| 2 | medio-bassa | Il numero poteva cambiare col dialogo aperto (secondo link all'ultimo istante): si legge A, si chiama B. | **corretto**: a ogni numero nuovo Chiama si disattiva di nuovo per 1,2 s. |
| 3 | medio-bassa | I link accettavano `*` e `#`: codici di servizio del PBX (es. inoltro verso esterno, casella vocale). | **corretto**: dai link solo cifre e `+`. |
| 4 | bassa | `AllowSetForegroundWindow(ASFW_ANY)` più largo del necessario. | **corretto**: diritto ceduto solo al processo della finestra trovata. |
| 5 | info | Mutex dal nome prevedibile: un processo dello stesso utente può impedire l'avvio. | **accettato** (stesso utente non è un confine; ARCHITECTURE §6). |
| 6 | info | `sip:301@altro-dominio` chiama 301 dal proprio PBX. | **voluto** (DECISIONS "Link telefonici"); il numero mostrato è quello chiamato. |
| 7 | info | Dopo la disinstallazione restava la chiave vuota `HKCU\Software\Econnet\DrinPhone`. | **corretto**: `uninsdeletekeyifempty` nell'ordine giusto. |

## Verificato senza riscontri
- `WM_COPYDATA`: tag `DRN1`, lunghezza pari e limitata, stringa costruita con lunghezza esplicita (nessuna lettura oltre il buffer), troncata al primo terminatore; Dart ricontrolla il tipo.
- `Utf8FromUtf16` con `WC_ERR_INVALID_CHARS`: surrogati spaiati -> stringa vuota -> nessun numero.
- UIPI: nessun `ChangeWindowMessageFilterEx`; processi a integrità bassa (sandbox del browser) non consegnano `WM_COPYDATA`.
- `%1` tra virgolette; gli argomenti servono solo a `numberFromLink` e a `--autostart` (nasconde e basta). Avvio con link: il dialogo compare comunque, nessuna chiamata automatica.
- Parser: cifre ASCII, spazi Unicode tolti, lettere simili e caratteri bidi rifiutati, max 32.
- Installatore: solo capacità (HKCU), nessuna scrittura di `UserChoice` o di `Classes\tel`.
- `dial` controlla `canDial` (niente chiamata se non registrati).

## Test
`test/call_links_test.dart` (parser, compresi `*`/`#` rifiutati) e
`test/widget_test.dart` "link tel: chiama solo dopo conferma" (Annulla non
chiama; Chiama inattivo appena aperto e dopo un cambio di numero; poi chiama
il numero mostrato). Prova manuale: seconda copia con `tel:` -> la copia
aperta mostra il dialogo (build Release, 2026-10-30). Da validare con browser
e Outlook dopo l'installazione.
