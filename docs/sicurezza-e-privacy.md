# Sicurezza, dati personali e modello di fiducia

## Asset
Password SIP, refresh token/API secret, rubrica, CDR, numeri chiamati, indirizzi PBX, token push, log di chiamata. Sono dati potenzialmente personali; il prodotto deve prevedere informativa, retention e ruoli tra Econnet, cliente e fornitori cloud.

## Threat model minimo
- Furto dispositivo: credenziali cifrate in Android Keystore/iOS Keychain/secure storage desktop validato, logout e revoca provisioning.
- Man-in-the-middle: HTTPS e SIP TLS validati, SRTP secondo policy; no `badCertificateCallback=true`, no bypass certificati in produzione.
- Abuso API: secret privilegiati solo lato backend, rate limit, ACL tenant, scope minimi, rotation.
- Leakage diagnostica: debug SIP redatto; non salvare header `Authorization`, session token, numeri completi o SDP con informazioni sensibili nei crash report remoti.
- Replay provisioning: QR/link firmato a scadenza, monouso, bind tenant/device dove appropriato, revoca.
- Supply chain: dipendenze pin, provenance dei binari, SBOM, firme e verifica aggiornata delle vulnerabilità.
- SIP attacks: invite/subscribe flooding, enumerazione interni, spoofing caller ID; protezioni principalmente sul PBX/proxy, backoff nel client.

## Accesso di supporto
Diagnostica opt-in, durata limitata, bundle esportabile redatto, no remote shell implicita. Log retention e trasmissione definibili per tenant; nessuna registrazione audio automatica.

## Security checklist PR
[ ] No secret in Git/log/test/analytics
[ ] Cert validation non disattivata
[ ] Input SIP/API/XML validato
[ ] Errori e timeout non fanno fallback non sicuro
[ ] Isolamento tenant/account testato
[ ] Privacy impact e retention verificati
[ ] Test regressione aggiunto

## Release
Verificare obblighi GDPR (ruoli controller/processor, DPA, subprocessor, base giuridica, tempi di conservazione, richieste interessati), policy APNs/FCM e store. Revisione professionale prima del lancio.
