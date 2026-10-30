# 2026-10-30 — Barra di sistema, notifiche di chiamata, avvio con Windows

Run: `~/security-audit-skill/drinphone/run-8` (profilo `quick`, scoped sul
diff della funzione). Revisione solo sul sorgente (nessuna sandbox): i
riscontri sono `needs_validation` finché non corretti.

## Oggetto
- `lib/features/shell/desktop_shell.dart` (icona, menu, notifiche Rispondi/Rifiuta)
- `lib/core/platform/autostart.dart` (valore HKCU `Run`)
- `lib/core/platform/window_attention.dart` (nascondi/mostra)
- `lib/main.dart`, `home_screen.dart`, `preferences_view.dart` (chiusura nella barra, `--autostart`)
- plugin `tray_manager` 0.5.3, `local_notifier` 0.1.6 (WinToast), `win32_registry` 3.0.3

## Riscontri
| # | Gravità | Riscontro | Esito |
|---|---|---|---|
| 1 | media | Rispondi/Rifiuta da una notifica rimasta nel centro notifiche agiva sull'id della chiamata (indirizzo nativo, riusabile) senza verificare che fosse ancora la stessa chiamata in squillo: poteva rispondere a un altro chiamante o chiudere una chiamata in corso. Il listener restava registrato (`close()` invece di `destroy()`). | **corretto**: l'azione parte solo se la notifica è ancora quella della chiamata e la chiamata è ancora `incoming`; le notifiche finite si distruggono (`destroy()`), anche all'uscita. |
| 2 | bassa | Nome e numero del chiamante restano nella cronologia notifiche di Windows; l'uscita per aggiornamento non chiudeva icona e notifiche. | **corretto in parte**: prima del riavvio di aggiornamento si chiama `DesktopShell.dispose()`. La scadenza della notifica non è esposta dal plugin: **rischio accettato** (stesso utente Windows, DECISIONS "modello di fiducia"). |
| 3 | bassa | Dopo la disinstallazione restavano il valore `Run` e il collegamento `DrinPhone.lnk` creato da WinToast. | **corretto**: `installer/drinphone.iss` li rimuove (`uninsdeletevalue`, `[UninstallDelete]`). |

## Verificato senza riscontri
- Iniezione XML nella notifica: WinToast costruisce il DOM con `CreateTextNode`/`SetAttribute`; il nome del chiamante non può aggiungere azioni o link.
- Nessun attivatore COM: Rispondi/Rifiuta arrivano solo dagli eventi delle notifiche create dal processo.
- Valore `Run`: HKCU, percorso dell'eseguibile tra virgolette, nessun input utente; `--autostart` nasconde solo la finestra.
- Uscita: "Esci" e chiusura senza barra fanno un-REGISTER e revoca token; chiusura nella barra mantiene la registrazione di proposito.
- Nessuna credenziale, token o segreto SIP passa da icona, notifiche o registro.

## Test
Il riscontro 1 dipende dal plugin nativo delle notifiche e non si riproduce
in `flutter test`: da validare a mano (chiamata in arrivo con finestra
nascosta, chiamante che chiude, click su Rispondi dalla cronologia → nessun
effetto). Suite completa: 80/80.
