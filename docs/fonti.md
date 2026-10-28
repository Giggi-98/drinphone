# Fonti e verifica periodica (consultate 2026-10-28)

- DRIN PRO funzionalità pubbliche: https://drin.it/funzionalita.html — elenco feature di prodotto, non promessa disponibilità API terze parti.
- Linphone SDK platform/language docs: https://wiki.linphone.org/xwiki/wiki/public/view/Lib/ — API native e versioni supportate. **Non** dimostra compatibilità plugin Flutter all-platform.
- Linphone licensing FAQ: https://www.linphone.org/en/faq/ — dual licensing GPL/AGPL/commerciale.
- Liblinphone licensing: https://www.linphone.org/en/liblinphone-voip-sdk/
- Linphone SDK build/gpl third parties: https://gitlab.com/linphone2/linphone-sdk/-/blob/master/README.md
- Yeastar P-Series Appliance enable API: https://help.yeastar.com/en/p-series-appliance-edition/developer-guide/enable-yeastar-p-series-pbx-api.html
- Yeastar P-Series Software interfaces/events: https://help.yeastar.com/en/p-series-software-edition/developer-guide/api-interfaces-and-events-summary.html
- Yeastar P-Series Cloud interfaces/events: https://help.yeastar.com/en/p-series-cloud-edition/developer-guide/api-interfaces-and-events-summary.html
- Yeastar API auth example: https://support.yeastar.com/hc/en-us/articles/23744152078361-How-To-Login-the-API-of-Yeastar-P-Series-PBX
- SIP core RFC 3261; dialog event RFC 4235; SUBSCRIBE/NOTIFY RFC 6665; SIP push RFC 8599; RTP DTMF RFC 4733; REFER RFC 3515; Replaces RFC 3891. Verificare documenti normativi e supporto firmware al momento d'uso.

**Ricontrollare prima di implementare:** licenze delle versioni effettive, plugin Flutter effettivo, API edizione Yeastar, supporto push server, Apple/Google background policies, aggiornamenti Windows/Linux/macOS.
