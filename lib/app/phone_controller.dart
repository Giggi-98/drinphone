import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/call_history.dart';
import 'l10n.dart';
import '../core/pbx/pbx_connection.dart';
import '../core/pbx/yeastar_api.dart';
import '../core/security/api_credential_store.dart';
import '../core/security/settings_store.dart';
import '../core/sip/sip_engine.dart';

/// Stato dell'app verso la UI: registrazione, chiamata corrente, impostazioni.
/// Una sola chiamata alla volta (F2); hold/transfer arrivano in F3.
class PhoneController extends ChangeNotifier {
  PhoneController(
    this._engine,
    this._store, {
    required this.engineDataDir,
    required this.logDir,
    this.apiStoreFor,
    this.historyStore,
    this.onIncomingCall,
    YeastarApi Function(ApiCredentials)? apiFactory,
  }) : _apiFactory = apiFactory ?? YeastarApi.new;

  final CallHistoryStore? historyStore;

  /// Chiamata entrante: richiamo di attenzione della piattaforma (finestra davanti).
  final void Function()? onIncomingCall;

  /// Cronologia, più recenti per prime.
  List<CallRecord> history = [];

  // Contatori SIP MWI (per PBX che inviano message-summary abbinabile).
  int _mwiNew = 0;
  int _mwiOld = 0;

  /// Messaggi in casella letti via API dal PBX dell'account; null = non disponibili.
  List<PbxVoicemail>? get voicemailMessages => primaryConnection?.voicemail;

  /// Casella vocale: dall'API se disponibile, altrimenti da SIP MWI.
  int get voicemailNew =>
      voicemailMessages?.where((m) => !m.read).length ?? _mwiNew;
  int get voicemailOld =>
      voicemailMessages?.where((m) => m.read).length ?? _mwiOld;

  // Salvataggi della cronologia in coda: mai due scritture del file insieme.
  Future<void> _historySaving = Future.value();

  /// Completa quando l'ultima scrittura della cronologia è finita.
  Future<void> get historySaved => _historySaving;

  // Chiamata in corso, per la cronologia.
  DateTime? _callStart;
  bool _callAnswered = false;

  final SipEngine _engine;
  final SettingsStore _store;
  final String engineDataDir;
  final String logDir;
  final _subs = <StreamSubscription<Object>>[];

  /// Deposito credenziali per connessione (null = piattaforma senza DPAPI).
  final ApiCredentialStore Function(String connectionId)? apiStoreFor;
  final YeastarApi Function(ApiCredentials) _apiFactory;

  /// Connessioni API, una per PBX, indipendenti tra loro.
  final connections = <PbxConnection>[];

  /// Gruppo selezionato: null = tutti; `conn` = tutto un PBX; `conn:org` = reparto.
  String? selectedGroup;

  /// Limite delle subscription BLF contemporanee (docs/sip-e-blf.md: provare 1/10/50).
  static const maxBlf = 100;

  /// Id della connessione creata prima del multi-PBX (file `yeastar-api.dpapi`).
  static const legacyConnectionId = 'default';

  Settings settings = const Settings();
  String engineVersion = '';
  String? engineError;
  RegistrationEvent registration = const RegistrationEvent(
    RegistrationStatus.none,
  );
  CallEvent? call;
  DateTime? callConnectedAt;
  bool muted = false;
  String? notice;

  /// Stato BLF per numero interno; assente = sconosciuto.
  final blf = <String, BlfEvent>{};

  Future<void> init() async {
    settings = await _store.load();
    appLang.value = AppLang.fromCode(settings.lang);
    history = await historyStore?.load() ?? [];
    _subs.add(_engine.registrations.listen(_onRegistration));
    _subs.add(_engine.calls.listen(_onCall));
    _subs.add(_engine.dialogs.listen(_onDialog));
    _subs.add(
      _engine.transfers.listen((ok) {
        notice = ok
            ? tr('Chiamata trasferita')
            : tr('Trasferimento non riuscito');
        notifyListeners();
      }),
    );
    _subs.add(
      _engine.voicemail.listen((v) {
        debugPrint(
          '[drinphone] casella vocale ${v.newMessages}/${v.oldMessages}',
        );
        _mwiNew = v.newMessages;
        _mwiOld = v.oldMessages;
        notifyListeners();
      }),
    );
    try {
      engineVersion = await _engine.start(
        dataDir: engineDataDir,
        logDir: logDir,
        debug: settings.debugLog,
      );
      debugPrint('[drinphone] motore liblinphone $engineVersion avviato');
      final account = settings.account;
      if (account != null) await _engine.register(account);
    } catch (e) {
      engineError = '$e';
      debugPrint('[drinphone] avvio motore fallito: $e');
    }
    await _startConnections();
    notifyListeners();
  }

  // ---------------------------------------------------------------- PBX API

  bool get apiAvailable => apiStoreFor != null;

  Future<void> _startConnections() async {
    final storeFor = apiStoreFor;
    if (storeFor == null) return;
    var infos = settings.pbx;
    // Migrazione dalla versione a connessione singola.
    if (infos.isEmpty && storeFor(legacyConnectionId).isSet) {
      infos = const [PbxConnectionInfo(legacyConnectionId, 'PBX')];
      settings = settings.copyWith(pbx: infos);
      await _store.save(settings);
    }
    for (final i in infos) {
      connections.add(_newConnection(i.id, i.label));
    }
    _assignVoicemail();
    for (final c in connections) {
      await c.start();
    }
  }

  PbxConnection _newConnection(String id, String label) => PbxConnection(
    id: id,
    label: label,
    store: apiStoreFor!(id),
    apiFactory: _apiFactory,
    onUpdate: _onConnectionUpdate,
  );

  /// Solo il PBX dell'account SIP legge la casella, quella del proprio interno.
  void _assignVoicemail() {
    final primary = primaryConnection;
    for (final c in connections) {
      c.voicemailOf = c == primary ? settings.account?.username : null;
    }
  }

  void _onConnectionUpdate(PbxConnection c, bool directoryChanged) {
    if (!c.syncing && (!c.ok || c.optionalErrors.isNotEmpty)) {
      debugPrint(
        '[drinphone] pbx ${c.id}: ${c.status} ${c.optionalErrors.join('; ')}',
      );
    }
    if (directoryChanged) {
      debugPrint(
        '[drinphone] pbx ${c.id}: ${c.directory.length} interni, '
        '${c.orgs.length} reparti, ${c.contacts.length} contatti, '
        '${c.voicemail?.length ?? '-'} messaggi in casella',
      );
      final g = selectedGroup;
      if (g != null && !_groupExists(g)) selectedGroup = null;
      _syncDialogs();
    }
    notifyListeners();
  }

  bool _groupExists(String g) {
    final parts = g.split(':');
    final c = connections.where((c) => c.id == parts[0]).firstOrNull;
    if (c == null) return false;
    return parts.length == 1 || c.orgs.any((o) => '${o.id}' == parts[1]);
  }

  /// Nuova connessione PBX; le credenziali si possono solo sovrascrivere.
  Future<PbxConnection> addConnection(
    String label,
    ApiCredentials creds,
  ) async {
    final id = List.generate(
      8,
      (_) => Random.secure().nextInt(16).toRadixString(16),
    ).join();
    final c = _newConnection(id, label);
    await c.store.save(creds);
    connections.add(c);
    _assignVoicemail();
    await _saveConnectionList();
    await c.start();
    return c;
  }

  Future<void> updateConnection(
    PbxConnection c, {
    String? label,
    ApiCredentials? creds,
  }) async {
    if (label != null) c.label = label;
    await _saveConnectionList();
    if (creds != null) {
      await c.store.save(creds);
      await c.start();
    }
    notifyListeners();
  }

  Future<void> removeConnection(PbxConnection c) async {
    await c.forget();
    connections.remove(c);
    if (selectedGroup?.split(':').first == c.id) selectedGroup = null;
    await _saveConnectionList();
    await _syncDialogs();
    notifyListeners();
  }

  Future<void> _saveConnectionList() async {
    settings = settings.copyWith(
      pbx: [for (final c in connections) PbxConnectionInfo(c.id, c.label)],
    );
    await _store.save(settings);
  }

  /// Forza la rilettura (tasto "Sincronizza ora"); senza [force] le connessioni
  /// saltano se hanno letto da meno di 10 s (rientro nella finestra, re-REGISTER).
  Future<void> resync({PbxConnection? only, bool force = true}) async {
    for (final c in [if (only != null) only else ...connections]) {
      await c.sync(force: force);
    }
  }

  /// Connessione del PBX su cui è registrato l'account SIP: i suoi interni si
  /// possono chiamare e osservare in BLF. Se il nome host non coincide (API via
  /// IP, SIP via FQDN) e c'è una sola connessione, si assume quella.
  PbxConnection? get primaryConnection {
    final sipHost = settings.account?.domain.split(':').first;
    return connections.where((c) => c.host == sipHost).firstOrNull ??
        (connections.length == 1 ? connections.first : null);
  }

  String get apiSummary {
    if (connections.isEmpty) return '';
    if (connections.length == 1) return connections.first.status;
    final ok = connections.where((c) => c.ok).length;
    return tr('{ok}/{n} PBX sincronizzati', {
      'ok': ok,
      'n': connections.length,
    });
  }

  void selectGroup(String? key) {
    selectedGroup = key;
    notifyListeners();
  }

  PbxConnection? _connectionOf(Extension e) => e.source.isEmpty
      ? primaryConnection
      : connections.where((c) => c.id == e.source).firstOrNull;

  /// Presenza Yeastar dell'interno (`available`, `away`, …); vuota se ignota.
  String presenceOf(Extension e) {
    final c = _connectionOf(e);
    if (c == null) return '';
    for (final x in c.directory) {
      if (x.number == e.number) return x.presence;
    }
    return '';
  }

  /// Chiamabile solo se è sul PBX dell'account SIP (o inserito a mano).
  bool isCallable(Extension e) =>
      e.source.isEmpty || e.source == primaryConnection?.id;

  /// Risultati per il popup di ricerca: interni, poi contatti della rubrica.
  /// Prima le corrispondenze a inizio parola o numero.
  List<SearchHit> search(String text, {int limit = 8}) {
    final q = text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final digits = _digits(q);
    int rank(String name, String number) {
      final n = name.toLowerCase();
      if (number.startsWith(q) || n.startsWith(q)) return 0;
      if (n.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) return 1;
      if (n.contains(q) ||
          (digits.isNotEmpty && _digits(number).contains(digits))) {
        return 2;
      }
      return -1;
    }

    final hits = <(int, SearchHit)>[];
    for (final e in allExtensions) {
      final r = rank(e.name, e.number);
      if (r >= 0) hits.add((r, SearchHit(e.name, e.number, extension: e)));
    }
    for (final c in connections) {
      for (final x in c.contacts) {
        for (final (label, number) in x.numbers) {
          final r = rank('${x.name} ${x.company}', number);
          if (r >= 0) {
            hits.add((r + 3, SearchHit(x.name, number, label: label)));
            break;
          }
        }
        if (hits.length > 200) break;
      }
    }
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final h in hits.take(limit)) h.$2];
  }

  Future<void> setLanguage(AppLang lang) async {
    appLang.value = lang;
    settings = settings.copyWith(lang: lang.name);
    await _store.save(settings);
    notifyListeners();
  }

  Future<void> setVoicemailCode(String code) async {
    settings = settings.copyWith(voicemailCode: code.trim());
    await _store.save(settings);
    notifyListeners();
  }

  /// Ascolto messaggi: si chiama il codice funzione della casella vocale.
  Future<void> callVoicemail() => dial(settings.voicemailCode);

  /// Interni della griglia secondo il gruppo selezionato.
  List<Extension> get visibleExtensions {
    final g = selectedGroup;
    if (g == null) return allExtensions;
    final parts = g.split(':');
    final c = connections.where((c) => c.id == parts[0]).firstOrNull;
    if (c == null) return allExtensions;
    final org = parts.length > 1
        ? c.orgs.where((o) => '${o.id}' == parts[1]).firstOrNull
        : null;
    final numbers = {
      for (final x in c.directory)
        if (org == null || org.extIds.contains(x.id)) x.number,
    };
    final primary = c.id == primaryConnection?.id;
    return [
      for (final e in allExtensions)
        if (numbers.contains(e.number) &&
            (e.source == c.id || (primary && e.source.isEmpty)))
          e,
    ];
  }

  /// Interni mostrati: manuali, poi quelli di ogni PBX; senza il proprio.
  /// Un interno manuale e uno del PBX principale con lo stesso numero sono lo stesso.
  List<Extension> get allExtensions {
    final own = settings.account?.username;
    final primaryId = primaryConnection?.id;
    final seen = <String>{};
    String key(Extension e) =>
        '${e.source.isEmpty || e.source == primaryId ? '' : e.source}:${e.number}';
    return [
      for (final e in [
        ...settings.extensions,
        for (final c in connections)
          for (final x in c.directory)
            Extension(
              x.name.isEmpty ? x.number : x.name,
              x.number,
              source: c.id,
            ),
      ])
        if (!(isCallable(e) && e.number == own) && seen.add(key(e))) e,
    ];
  }

  bool isManual(Extension e) => settings.extensions.contains(e);

  /// Rubrica aziendale di tutti i PBX filtrata da [filter] (nome, azienda, cifre).
  List<(PbxConnection, PbxContact)> contactsMatching(String filter) {
    final q = filter.trim().toLowerCase();
    return [
      for (final c in connections)
        for (final x in c.contacts)
          if (q.isEmpty ||
              x.name.toLowerCase().contains(q) ||
              x.company.toLowerCase().contains(q) ||
              x.numbers.any((n) => _digits(n.$2).contains(q)))
            (c, x),
    ];
  }

  static String _digits(String n) => n.replaceAll(RegExp(r'[^0-9]'), '');

  /// Stesso numero a meno di spazi/simboli e prefissi (+39, 0039): uguali, o
  /// stesse cifre finali se entrambi lunghi almeno 7 (mai per gli interni brevi).
  static bool sameNumber(String a, String b) {
    final x = _digits(a), y = _digits(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    if (x.length < 7 || y.length < 7) return false;
    return x.endsWith(y) || y.endsWith(x);
  }

  /// Nome per un numero: interni (anche di altri PBX), poi rubrica aziendale.
  String nameFor(String number) {
    if (number.isEmpty) return '';
    for (final e in allExtensions) {
      if (e.number == number && e.name != e.number) return e.name;
    }
    for (final c in connections) {
      for (final x in c.contacts) {
        if (x.numbers.any((n) => sameNumber(n.$2, number))) return x.name;
      }
    }
    return '';
  }

  // ---------------------------------------------------------------- account

  Future<void> saveAccount(SipAccount account, {required bool debugLog}) async {
    settings = settings.copyWith(account: account, debugLog: debugLog);
    await _store.save(settings);
    _assignVoicemail();
    if (engineError == null) await _engine.register(account);
    notifyListeners();
  }

  Future<void> removeAccount() async {
    settings = settings.copyWith(clearAccount: true);
    await _store.save(settings);
    if (engineError == null) await _engine.unregister();
    registration = const RegistrationEvent(RegistrationStatus.none);
    notifyListeners();
  }

  Future<void> addExtension(Extension e) =>
      _saveExtensions([...settings.extensions, e]);

  Future<void> removeExtension(Extension e) =>
      _saveExtensions(settings.extensions.where((x) => x != e).toList());

  Future<void> _saveExtensions(List<Extension> list) async {
    settings = settings.copyWith(extensions: list);
    await _store.save(settings);
    await _syncDialogs();
    notifyListeners();
  }

  Set<String> get _watched => {
    for (final e in allExtensions.where(isCallable).take(maxBlf)) e.number,
  };

  Future<void> _syncDialogs() async {
    final watched = _watched;
    blf.removeWhere((n, _) => !watched.contains(n));
    if (engineError == null && registration.status == RegistrationStatus.ok) {
      await _engine.watchDialogs(watched);
    }
  }

  // ---------------------------------------------------------------- chiamate

  bool get canDial =>
      engineError == null &&
      registration.status == RegistrationStatus.ok &&
      call == null;

  Future<void> dial(String number) async {
    final n = number.trim();
    if (n.isEmpty || !canDial) return;
    await _engine.dial(n);
  }

  Future<void> answer() => _engine.answer();
  Future<void> hangup() => _engine.hangup();
  Future<void> sendDtmf(String d) => _engine.sendDtmf(d);

  /// Chiamata in attesa messa da noi (non dall'altro capo).
  bool onHold = false;

  Future<void> toggleHold() async {
    onHold = !onHold;
    await (onHold ? _engine.hold() : _engine.resume());
    notifyListeners();
  }

  Future<void> transfer(String number) => _engine.transfer(number.trim());

  Future<void> toggleMute() async {
    muted = !muted;
    await _engine.setMicMuted(muted);
    notifyListeners();
  }

  void clearNotice() {
    notice = null;
    notifyListeners();
  }

  void _onRegistration(RegistrationEvent e) {
    debugPrint('[drinphone] registrazione ${e.status.name} ${e.message}');
    final wasOk = registration.status == RegistrationStatus.ok;
    registration = e;
    if (e.status == RegistrationStatus.ok) {
      _engine.watchDialogs(_watched);
      // Rete tornata dopo una caduta: riallinea anche i dati dal PBX.
      if (!wasOk) resync(force: false);
    } else {
      blf.clear();
    }
    notifyListeners();
  }

  void _onDialog(BlfEvent e) {
    debugPrint('[drinphone] blf ${e.number} ${e.status.name} ${e.reason}');
    blf[e.number] = e;
    notifyListeners();
  }

  void _onCall(CallEvent e) {
    debugPrint(
      '[drinphone] chiamata ${e.direction.name} ${e.phase.name} ${e.message}',
    );
    if (call == null && e.phase == CallPhase.incoming) onIncomingCall?.call();
    if (call == null) {
      _callStart = DateTime.now();
      _callAnswered = false;
    }
    if (e.phase == CallPhase.active) _callAnswered = true;
    if (e.phase == CallPhase.ended || e.phase == CallPhase.error) {
      _record(e);
      if (e.phase == CallPhase.error) {
        notice = tr('Chiamata non riuscita: {m}', {'m': e.message});
      }
      call = null;
      callConnectedAt = null;
      onHold = false;
      if (muted) {
        muted = false;
        _engine.setMicMuted(false);
      }
    } else {
      if (e.phase == CallPhase.active && callConnectedAt == null) {
        callConnectedAt = DateTime.now();
      }
      call = e;
    }
    notifyListeners();
  }

  void _record(CallEvent e) {
    final start = _callStart ?? DateTime.now();
    final connected = callConnectedAt;
    final number = e.remoteNumber.isNotEmpty
        ? e.remoteNumber
        : (call?.remoteNumber ?? '');
    final sipName = e.remoteName.isNotEmpty
        ? e.remoteName
        : (call?.remoteName ?? '');
    history = [
      CallRecord(
        number: number,
        name: sipName.isNotEmpty ? sipName : nameFor(number),
        direction: e.direction,
        start: start,
        seconds: connected == null
            ? 0
            : DateTime.now().difference(connected).inSeconds,
        answered: _callAnswered,
      ),
      ...history,
    ].take(CallHistoryStore.maxRecords).toList();
    _callStart = null;
    final store = historyStore;
    final snapshot = history;
    if (store != null) {
      _historySaving = _historySaving.then((_) => store.save(snapshot));
    }
  }

  Future<void> clearHistory() async {
    history = [];
    final store = historyStore;
    if (store != null) {
      _historySaving = _historySaving.then((_) => store.clear());
      await _historySaving;
    }
    notifyListeners();
  }

  /// Chiusura ordinata (uscita dall'app): revoca i token API e ferma il motore,
  /// che invia l'un-REGISTER e scarica il log.
  Future<void> shutdown() async {
    for (final c in connections) {
      await c.stop();
    }
    await _engine.stop();
  }

  @override
  void dispose() {
    for (final c in connections) {
      c.stop();
    }
    for (final s in _subs) {
      s.cancel();
    }
    _engine.stop();
    super.dispose();
  }
}

/// Una riga del popup di ricerca: un interno o un numero della rubrica.
class SearchHit {
  const SearchHit(this.name, this.number, {this.extension, this.label = ''});
  final String name;
  final String number;

  /// Interno della griglia (per stato e chiamabilità); null = contatto rubrica.
  final Extension? extension;

  /// Etichetta del numero in rubrica (Ufficio, Cellulare…).
  final String label;
}
