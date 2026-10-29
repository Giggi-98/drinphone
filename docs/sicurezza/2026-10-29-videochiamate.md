# Audit di sicurezza — videochiamate e codec H264 (2026-10-29)

Oggetto: video nelle chiamate, webcam, finestre native, download e caricamento
di OpenH264 (Cisco). Decisione: `DECISIONS.md` 2026-10-29 "Videochiamate".
Codice: `lib/core/video/openh264.dart`, `lib/core/sip/linphone_ffi_engine.dart`,
`lib/core/platform/video_surface.dart`, `lib/features/call/`, `lib/features/preferences/`.
Verifica: `test/openh264_test.dart`, `test/history_and_search_test.dart`; avvio sul
pilota con OpenH264 installato (plugin caricato, H264/VP8/AV1 disponibili, webcam vista).

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Integrità del codec scaricato | OK | Impronte SHA-256 fissate nel codice (archivio `799e08c4…ad7d`, DLL `9b392bf0…d2d0`); file diverso → rifiutato, niente installato (test); scrittura atomica |
| DLL in cartella scrivibile dall'utente (DLL planting) | OK | `SetDllDirectoryW` sulla cartella codec **solo** se l'impronta della DLL è verificata a quell'avvio; altrimenti la cartella non entra nel percorso di ricerca |
| Comportamento del binario Cisco | OK | Firma Authenticode "Cisco WebEx LLC" valida (DigiCert); importa solo KERNEL32, nessuna API di rete; gli URL nel file sono della catena del certificato |
| Privacy del download | ACCETTATO | Cisco riceve IP e ora del download, una volta, solo dopo consenso esplicito nel dialogo |
| Canale http del download | OK | Pubblicato da Cisco in http; l'integrità è data dall'impronta, non dal canale |
| Webcam | OK | Accesa solo in videochiamata scelta dall'utente ("Videochiamata" o "Rispondi in video"); anteprima spenta di default; "Rispondi" semplice = solo audio anche se il chiamante offre video |
| Media in chiaro | ATTENZIONE | Come l'audio: cifrato solo con SRTP/ZRTP/DTLS attivo in Preferenze > Avanzate |
| Finestre native sopra l'interfaccia | NOTA | Coprono menu e dialoghi aperti sopra il pannello video (usabilità, non sicurezza) |

## Riscontri
- **confirmed**: nessuno.
