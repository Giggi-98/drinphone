import '../../app/l10n.dart';

/// Cosa si legge dalle API del PBX e ogni quanto (DECISIONS "Sincronizzazione
/// PBX configurabile"). Una voce per funzione: aggiungerne una = un valore qui
/// (scelte, predefinito, testi) e il suo blocco in `PbxConnection.sync`; le
/// impostazioni salvate senza la voce nuova prendono il predefinito, quelle con
/// voci non più esistenti le ignorano.
enum PbxSync {
  /// Interni e presenza: base della connessione, non si spegne.
  extensions(
    [Duration(seconds: 30), _min1, Duration(minutes: 5), _min15],
    _min1,
    canDisable: false,
  ),
  voicemail([_min1, Duration(minutes: 5), _min15], _min1),
  orgs([_min10, _hour1, _hour6], _min10),
  ownDetail([_min10, _hour1, _hour6], _min10),
  featureCodes([_min10, _hour1, _hour6], _min10),
  contacts([_hour1, _hour6, Duration(hours: 24)], _hour6);

  const PbxSync(this.choices, this.byDefault, {this.canDisable = true});

  /// Frequenze proposte; spento ([Duration.zero]) in più se [canDisable].
  final List<Duration> choices;
  final Duration byDefault;
  final bool canDisable;

  String get label => switch (this) {
    extensions => tr('Interni e presenza'),
    voicemail => tr('Casella vocale'),
    orgs => tr('Reparti'),
    ownDetail => tr('Presenze e inoltri del mio interno'),
    featureCodes => tr('Codici funzione (registrazione)'),
    contacts => tr('Rubrica aziendale'),
  };

  String get help => switch (this) {
    extensions => tr(
      'Elenco interni, nomi e presenza. Con gli eventi in tempo reale attivi '
      'si rilegge al più ogni 5 minuti.',
    ),
    voicemail => tr('Messaggi del proprio interno. Spenta: avviso SIP (MWI).'),
    orgs => tr('Pannello reparti nella vista Interni.'),
    ownDetail => tr(
      'Preferenze > Presenza: inoltri, squillo, cellulare. Si rilegge anche '
      'quando il PBX segnala una modifica.',
    ),
    featureCodes => tr('Codice per registrare le chiamate sul PBX.'),
    contacts => tr(
      'Migliaia di contatti, letti a pagine: cadenza lunga. "Sincronizza ora" '
      'la rilegge subito.',
    ),
  };

  /// Frequenza scelta in [settings] (secondi per nome; 0 = spenta).
  Duration of(Map<String, int> settings) {
    final s = settings[name];
    if (s == null) return byDefault;
    final d = Duration(seconds: s);
    if (d == Duration.zero) return canDisable ? d : byDefault;
    return choices.contains(d) ? d : byDefault;
  }
}

const _min1 = Duration(minutes: 1);
const _min10 = Duration(minutes: 10);
const _min15 = Duration(minutes: 15);
const _hour1 = Duration(hours: 1);
const _hour6 = Duration(hours: 6);

/// "30 s", "10 min", "6 ore", "Spenta".
String syncEveryLabel(Duration d) {
  if (d == Duration.zero) return tr('Spenta');
  if (d.inHours > 0) {
    return d.inHours == 1 ? tr('1 ora') : tr('{n} ore', {'n': d.inHours});
  }
  if (d.inMinutes > 0) return tr('{n} min', {'n': d.inMinutes});
  return tr('{n} s', {'n': d.inSeconds});
}
