# DESIGN — DrinPhone "Squillo"

Fonte unica dello stile visivo. Ogni schermata, componente o funzione nuova
usa **questi** token e queste regole; se qualcosa manca, si aggiunge qui
(nello stesso commit) prima di usarlo nel codice. Riferimento grafico:
`docs/design/drin-design-system.html` (aprirlo nel browser). Decisione:
`DECISIONS.md` 2026-10-30 "Identità visiva Squillo".

**Idea.** "Drin!" è il suono dello squillo: lo squillo è il marchio. Base
**Squillo** (blu DRIN, giallo riservato a ciò che squilla, il "!" del logo
quando qualcuno chiama) con la **densità del Centralino** (righe compatte,
presenze come spie luminose, numeri in evidenza, molti interni a colpo
d'occhio).

## 1. Colore

Token in `lib/app/theme.dart` (`DrinColors`). Mai colori scritti a mano nei
widget.

| Token | Chiaro | Scuro | Uso |
|---|---|---|---|
| `brand` | `#1380C6` | `#4BA9EC` | logo, accenti grandi, selezione, focus |
| `primary` | `#0E6BA8` | `#4BA9EC` | pulsanti e testo d'azione (contrasto AA con `onPrimary`) |
| `onPrimary` | `#FFFFFF` | `#06182A` | testo su `primary` |
| `ink` | `#0B2A43` | `#E8F2FA` | testo principale |
| `muted` | `#4F6478` | `#93AABD` | testo secondario, icone a riposo |
| `ground` | `#EEF3F7` | `#0A1825` | fondo dell'app |
| `surface` | `#FFFFFF` | `#0F2233` | pannelli, finestre |
| `raised` | `#F6F9FC` | `#14293C` | righe, schede, campi |
| `panel` | `#E3EAF0` | `#1A3045` | tasti, chip, fondo delle spie |
| `line` | `#D3DFE8` | `#1E3A52` | bordi e divisori |
| `squillo` | `#FFB800` | `#FFC53D` | **solo** ciò che squilla (chiamata in arrivo, interno che squilla) |
| `onSquillo` | `#3D2C00` | `#2B1F00` | testo su `squillo` |
| `squilloLine` | `#B88300` | `#FFC53D` | bordi e onde dello squillo (il giallo pieno sul bianco non si vede) |
| `free` | `#1A9E68` | `#3CCB8C` | libero, registrato, rispondi |
| `onFree` | `#FFFFFF` | `#06182A` | icona su `free` (es. Rispondi) |
| `busy` | `#DC3E43` | `#FF6B6F` | occupato, errore, termina |
| `onBusy` | `#FFFFFF` | `#06182A` | icona su `busy` (es. Termina) |
| `away` | `#7C8B99` | `#7F93A6` | in attesa, non raggiungibile, offline |

Regole:
- Uno stato = un colore = un significato, ovunque (spia, chip, pulsante).
- Il giallo `squillo` non si usa per avvisi, novità o decorazione.
- Verde solo per "rispondi/libero", rosso solo per "termina/occupato/errore";
  tutte le altre azioni sono neutre (`panel` + `ink`) o `primary`.
- Neutri leggermente blu, mai grigi puri; il tema scuro non è l'inverso del
  chiaro: stessi ruoli, contrasto AA (4.5:1 testo, 3:1 icone e bordi attivi).
  Verificato il 2026-10-30 su tutte le coppie d'uso (testo ≥ 5.05, icone
  ≥ 3.16); un token nuovo si aggiunge solo dopo la stessa verifica.
- `brand` (#1380C6) sul bianco fa 4.26: va bene per icone e testo ≥ 18 px
  grassetto, non per testo piccolo (lì `primary`).

## 2. Carattere

Font inclusi nell'app (`assets/fonts/`, OFL): identici su ogni piattaforma.

| Ruolo (`DrinText`) | Font | Dimensione / interlinea | Peso | Uso |
|---|---|---|---|---|
| `display` | Bricolage Grotesque | 28 / 34 | 800 | nome di chi chiama, titolo di schermata vuota |
| `title` | Bricolage Grotesque | 20 / 26 | 700 | titolo di sezione e di dialogo |
| `heading` | Onest | 15 / 20 | 600 | nome in una riga, intestazioni di gruppo |
| `body` | Onest | 14 / 20 | 400 | testo dell'interfaccia |
| `detail` | Onest | 12.5 / 16 | 400 | testo secondario (`muted`) |
| `label` | Onest | 12 / 16 | 600 | pulsanti piccoli, chip, badge |
| `number` | Red Hat Mono | 13 / 18 | 500 | interni e numeri nelle righe (cifre tabulari) |
| `numberLarge` | Red Hat Mono | 22 / 28 | 600 | numero in composizione, interno di chi chiama |

Regole:
- Solo questi otto stili; niente `fontSize` scritto nei widget.
- Bricolage solo per `display` e `title`: è la voce del marchio, va dosata.
- Numeri (interni, telefoni, durate) sempre in `number`/`numberLarge`.
- Niente maiuscolo spaziato per le etichette, niente parola evidenziata in un
  titolo.

## 3. Spazio, densità, forme

- Griglia da 4: `s1`=4, `s2`=8, `s3`=12, `s4`=16, `s5`=24, `s6`=32 (`DrinSpace`).
- **Densità Centralino** con il puntatore (desktop): righe da 40, spaziatura
  `s2`. **Al tocco** (telefono, tablet): righe da 52 e bersagli da almeno 48
  (Material) / 44 pt (Apple). La densità si sceglie dal tipo di input, non
  dalla piattaforma.
- Raggi per ruolo (`DrinRadius`): controllo 8, riga/scheda 10, pannello 14,
  foglio e dialogo 20, pillola 999. Mai lo stesso raggio su tutto.
- Ombra solo per ciò che sta **sopra** (finestra di chiamata, dialoghi, menu);
  righe e schede si separano con `line` e `raised`, non con ombre.

## 4. Spie di presenza

Pallino da 8 con alone morbido del suo colore quando lo stato è vivo
(`free`, `busy`, `squillo`); `away` senza alone. L'interno che squilla usa
`squillo` con un impulso lento (non lampeggio). Cambio di stato: il pallino
si riempie in `fast`.

## 5. Movimento (`DrinMotion`)

| Token | Durata | Curva | Uso |
|---|---|---|---|
| `fast` | 120 ms | `easeOutCubic` | stati, spie, hover, pressione |
| `base` | 200 ms | `easeOutCubic` | pannelli, liste, chip, comparsa di elementi |
| `wide` | 320 ms | `easeInOutCubicEmphasized` | cambio schermata, finestra di chiamata |
| `ring` | 900 ms ciclo | oscillazione smorzata | avatar che squilla (±9° che si spegne) |
| `wave` | 1600 ms ciclo | `easeOut` | onde `squillo` attorno all'avatar |

Regole:
- Il movimento risponde a un'azione o a uno squillo; niente animazioni
  decorative in loop, niente entrate a cascata delle sezioni.
- Ovunque: pressione dei pulsanti (leggera molla), comparsa/scomparsa
  (dissolvenza + 4 px), cambio sezione (dissolvenza `base`), apertura della
  chiamata (`wide`).
- Con "riduci movimento" del sistema (`MediaQuery.disableAnimations`) tutto
  diventa immediato e lo squillo resta solo colore.

## 6. Componenti chiave

- **Chiamata in arrivo**: avatar `brand` con oscillazione `ring`, due onde
  `squilloLine`, il "!" del logo in `squilloLine`, bordo `squilloLine`;
  Rispondi `free`/`onFree`, Rifiuta `busy`/`onBusy`; nome in `display`,
  interno in `numberLarge`.
- **Riga interno** (densa): spia, nome `heading`, stato `detail`, interno
  `number` allineato a destra, azioni che compaiono all'hover (sempre visibili
  al tocco).
- **Controlli di chiamata**: tasti rotondi `panel`, attivo = `primary`;
  Termina `busy` sempre a destra (desktop) o al centro in basso (telefono).
- **Badge**: pillola `label`; non letti in `busy`, "nuovo" in `primary`.
- **Tabella chiamate** (registro di questo PC e CDR del PBX): intestazione
  `label` in `muted` su riga da 36 con bordo `line`; righe da 52 separate da
  `line`, hover `raised` con raggio riga; Ora in `number` con il giorno sotto
  in `detail`; nomi `heading` con numero sotto in `number`; "risposto da" di
  gruppi e code in `detail` con freccia `primary`; esito come pillola `label`
  con spia (risposta `freeText`, persa/abbandonata/non riuscita `busyText`,
  casella vocale `primary`, occupato e altro `away`, fondo al 14%); durate
  allineate a destra in `number` (`m:ss`, `h:mm:ss`, "—" se zero); Richiama
  all'hover. Sotto una certa larghezza spariscono prima Durata e Tipo, poi
  Conversazione; i filtri vanno a capo sotto il titolo.
  Nel CDR del PBX, come nella pagina CDR del PBX: intestazioni ordinabili
  (testo `primary` e freccia sulla colonna attiva, doppia freccia `muted`
  sulle altre; di default Ora dalla più recente); sopra la tabella il numero
  di chiamate in `label` `muted`, Aggiorna, scelta delle colonne (menu con
  spunte) ed "Esporta CSV" (pulsante bordato); sotto le pagine con "righe
  per pagina". Coda / gruppo / IVR con l'icona del passaggio in `primary`
  (IVR, call flow, coda, gruppo) e "+n" in `label` `muted`. Clic sulla riga:
  dialogo "Dettagli chiamata" con i campi in griglia (`label` `muted` sopra,
  `body` sotto, "—" in `muted` se vuoti) e la tabella delle gambe.
- **Filtro a pillola** (sopra le tabelle): alto 36, raggio `pill`, testo
  `label` "Etichetta: valore" con freccia; a riposo fondo `raised` e bordo
  `line`, etichetta `muted`, valore `ink`; con un valore diverso dal
  predefinito bordo e valore `primary`, fondo `primary` al 14%. Accanto,
  "Azzera filtri" (pulsante testo) solo se un filtro è attivo.

## 7. Struttura adattiva

Barra laterale su desktop (≥ 1024), binario di icone su tablet (600–1023),
barra in basso su telefono (< 600). Stessi token in tutte; la chiamata in
corso su telefono occupa lo schermo intero.

Su desktop l'interfaccia è in scala con la finestra (`DrinScale`): fattore
`larghezza / 1366`, tra 0,9 e 1,3, applicato a tutto (testo, icone, spazi,
colonne), così i caratteri seguono la larghezza e i contenuti occupano
l'intera finestra. Le larghezze di soglia qui sopra si misurano dopo la
scala. I contenuti non hanno larghezza massima: schede e campi si
allargano fino al bordo.

## 8. Come si verifica

Ogni modifica UI si fotografa (CLAUDE.md §8) nei due temi, a 390 px e a
1280 px, e si confronta con `docs/design/drin-design-system.html`. Un
colore, una misura o un'animazione che non sono qui sono un errore da
correggere, non una variante.
