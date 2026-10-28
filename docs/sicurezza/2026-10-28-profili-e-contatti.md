# Audit di sicurezza — profili, procedura guidata, contatti personali (2026-10-28)

Oggetto: profili "Yeastar integrato" / "SIP generico" (DECISIONS "Profili"),
procedura guidata, contatti personali con import CSV/vCard.
Codice: `lib/core/security/settings_store.dart`, `lib/app/phone_controller.dart`
(profili), `lib/core/contacts/personal_contacts.dart`, `lib/features/setup/`,
`lib/features/contacts/contacts_view.dart`.
Verifica: test automatici (`test/profiles_test.dart`, `test/personal_contacts_test.dart`);
avvio sul pilota con il file della versione precedente (registrazione e API OK).

## Rivisto
| Punto | Esito | Evidenza |
|---|---|---|
| Password SIP dei profili non attivi | OK | `save` scrive in `flutter_secure_storage` gli account di **tutti** i profili (`allAccounts`); il JSON non le contiene (test: file senza password, password del profilo lasciato ancora leggibile dopo il cambio) |
| Pulizia all'eliminazione di un profilo | OK | Password tolte dallo storage sicuro (id non più presenti), file DPAPI delle sue connessioni cancellati (`ApiCredentialStore.clear`), registro e contatti cancellati (test) |
| Collisione di chiavi tra profili | OK | Id account `main` solo se nessun profilo ha account (`newAccountId` su `allAccounts`), altrimenti 8 cifre esadecimali casuali (test); id connessione casuali; la migrazione della connessione singola `default` vale solo per il profilo storico |
| Credenziali API nella procedura guidata | OK | Stesso `PbxConnectionsPanel` e dialogo a sola scrittura delle Preferenze |
| Copia `settings.v1.json` | OK | Contiene solo dati non segreti (come `settings.json`): utente, dominio, interni |
| Contatti personali in chiaro | ACCETTATO | Scelta di Luigi (JSON come il registro, protetto dall'account Windows); dati personali di terzi: non nei log, non inviati fuori dal PC |
| Import da file | OK | Parser senza esecuzione di contenuti: CSV e vCard letti come testo, nessuna espansione o URL seguito; righe senza numero e fax scartati; file scelto dall'utente |
| Cambio profilo durante una chiamata | OK | Rifiutato (`switchProfile`/`createProfile` restituiscono false con chiamate attive) |

| Cache dati PBX su disco | OK | Cifrata DPAPI (`DpapiBox`, entropia segreto + sale per file); test: nomi di interni e contatti assenti dal file; cancellata con la connessione o il profilo; scrittura atomica (temporaneo + rinomina) |
| Stati BLF dopo il cambio profilo | OK | Solo in memoria, mostrati come "da confermare"; mai su disco |

## Riscontri
- **confirmed**: nessuno.

## Da validare
- Al cambio profilo gli account lasciati vengono rimossi dal core (`clear_accounts`):
  verificare sul PBX che parta l'un-REGISTER (altrimenti restano registrati fino
  alla scadenza).
