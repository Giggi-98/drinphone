# Audit di sicurezza — finestra di chiamata, registrazione, ANGLE (2026-10-29)

Oggetto: nuova finestra di chiamata (note, registrazione, conferenza),
endpoint `feature_code/get`, libreria ANGLE per la visualizzazione del video.
Decisioni: `DECISIONS.md` 2026-10-29 "ANGLE per il video" e "Finestra di chiamata".
Codice: `lib/features/call/call_window.dart`, `lib/app/phone_controller.dart`,
`lib/core/sip/linphone_ffi_engine.dart`, `lib/core/pbx/yeastar_api.dart`,
`tool/fetch_angle.ps1`, `windows/CMakeLists.txt`.
Verifica: test automatici (51); avvio sul pilota (registrazione e sync OK,
`feature_code/get` senza errori).

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Provenienza di ANGLE | OK | Estratto (senza eseguire) dall'installatore ufficiale Linphone 5.3.4, firma Authenticode "Belledonne Communications" valida; `libEGL.dll` e `libGLESv2.dll` firmate "The Qt Company Oy" (ANGLE di Qt 5.15.2); impronte SHA-256 di installatore e DLL fissate in `tool/fetch_angle.ps1` |
| Comportamento di ANGLE | OK | Importa solo DLL di sistema (USER32, KERNEL32, d3d9) e runtime MSVC; nessuna API di rete |
| Nuovo endpoint API | OK | `feature_code/get` in sola lettura (codice `auto_record`); errori solo con codice, mai URL o token |
| Registrazione locale | ATTENZIONE | File `.mkv` in `Documenti\DrinPhone\Registrazioni`, in chiaro: contengono la voce di terzi. Solo se scelta nell'account; avviso del consenso nell'editor; indicatore REC nella finestra |
| Registrazione col codice PBX | NOTA | Il codice va in DTMF: il PBX non conferma lo stato, l'indicatore mostra quello chiesto da DrinPhone |
| Note della chiamata | OK | Nel registro chiamate del profilo (JSON locale come il registro), mai nei log |
| Conferenza locale | OK | Mixer in DrinPhone (liblinphone): nessun servizio esterno |
| Contesto video passato al core | CORRETTO | MSOGL vuole un `MSOglContextInfo*` (msogl.h), non l'HWND: passare l'HWND faceva leggere memoria non valida (crash alla risposta in video e alla riaccensione del video). Ora struttura nativa per finestra, liberata solo a core distrutto. Prova: anteprima webcam disegnata (118/118 fotogrammi in 4 s), nessun crash |

## Riscontri
- **confirmed**: crash per puntatore errato al filtro video (sopra), corretto prima del commit; nessun altro.
