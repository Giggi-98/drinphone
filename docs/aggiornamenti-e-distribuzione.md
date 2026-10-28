# Aggiornamenti & distribuzione

## Principio
Tutti i client leggono all'avvio un **manifest di aggiornamento** unico. Il
manifest dice, per ogni piattaforma: ultima versione, versione minima
supportata, note, URL degli artefatti firmati. Cosa succede poi dipende dalla
piattaforma.

Esempio di manifest (forma indicativa):
```json
{
  "android": { "latest": "1.2.0", "min_supported": "1.0.0", "url": "https://.../app-1.2.0.apk", "store": "https://play.google.com/..." },
  "windows": { "latest": "1.2.0", "min_supported": "1.0.0", "url": "https://.../DrinPhone-1.2.0.exe" },
  "linux":   { "latest": "1.2.0", "min_supported": "1.0.0", "url": "https://.../DrinPhone-1.2.0.AppImage" },
  "notes_url": "https://.../changelog/1.2.0"
}
```

## Cosa può fare ogni piattaforma
- **Desktop (Windows/macOS/Linux):** può **scaricare e auto-aggiornarsi** da un
  artefatto firmato. Verifica sempre la firma prima di installare.
- **Android:** su Play Store l'aggiornamento lo fa lo store (il client al più
  avvisa e rimanda). Fuori Play (APK diretto/MDM) l'app può scaricare il nuovo
  APK, ma con avvisi di sicurezza e solo se la distribuzione lo prevede.
- **iOS:** **solo** App Store o MDM aziendale. Il client può solo rilevare la
  versione e rimandare. Nessun download di binari da sé.

## Repo privato: niente token nei client
Il repo del **codice** resta privato. Gli **artefatti + manifest** vanno su un
**canale pubblico separato** (es. un repo "releases" pubblico, o un endpoint
Econnet). Non mettere mai un token di accesso dentro un'app distribuita:
chiunque la apre lo estrae.

## Decisioni (vedi DECISIONS.md)
- Canale iniziale: **repo "releases" pubblico separato** (semplice, sicuro).
- Modello di distribuzione mobile: **differito**, primo bersaglio Play Store.
- Architettura: **astrai il canale di update** dietro un'interfaccia, così
  passare a un endpoint Econnet o a MDM non tocca il resto dell'app.

## Requisiti di integrità e rollback
Un manifest HTTPS **da solo non autentica** la release. Usare firma digitale del manifest o metadati di update firmati, hash SHA-256 degli artefatti, chiavi pubbliche pin nel client e controllo anti-rollback. La firma del pacchetto OS è addizionale, non sostitutiva. Definire ambiente `dev/staging/prod`, rollout graduale, quarantena di release compromesse e rotazione chiavi.

Non promettere auto-update universale desktop: il meccanismo dipende da installer/Store (Windows MSIX/installer, macOS signed/notarized, Linux AppImage/deb/repository) e richiede test di privilegi/rollback. Release cliente solo dopo gate licenze in `docs/licenze-e-compliance.md`.
