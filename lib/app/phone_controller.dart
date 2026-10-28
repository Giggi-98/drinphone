import 'dart:async';

import 'package:flutter/foundation.dart';

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
    this.apiStore,
    YeastarApi Function(ApiCredentials)? apiFactory,
  }) : _apiFactory = apiFactory ?? YeastarApi.new;

  final SipEngine _engine;
  final SettingsStore _store;
  final String engineDataDir;
  final String logDir;
  final _subs = <StreamSubscription<Object>>[];
  final ApiCredentialStore? apiStore;
  final YeastarApi Function(ApiCredentials) _apiFactory;
  YeastarApi? _api;

  /// Interni importati dal PBX via OpenAPI (vuoto se l'integrazione è spenta).
  List<PbxExtension> pbxDirectory = const [];

  /// Stato leggibile dell'integrazione API; null = non configurata.
  String? apiStatus;

  /// Limite delle subscription BLF contemporanee (docs/sip-e-blf.md: provare 1/10/50).
  static const maxBlf = 100;

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
    _subs.add(_engine.registrations.listen(_onRegistration));
    _subs.add(_engine.calls.listen(_onCall));
    _subs.add(_engine.dialogs.listen(_onDialog));
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
    await _connectApi();
    notifyListeners();
  }

  bool get apiConfigured => apiStore?.isSet ?? false;

  /// Sovrascrive le credenziali API: non esiste un metodo per rileggerle.
  Future<void> saveApiCredentials(ApiCredentials c) async {
    await apiStore!.save(c);
    await _connectApi();
    notifyListeners();
  }

  Future<void> clearApiCredentials() async {
    await _api?.close();
    _api = null;
    await apiStore?.clear();
    pbxDirectory = const [];
    apiStatus = null;
    await _syncDialogs();
    notifyListeners();
  }

  Future<void> _connectApi() async {
    await _api?.close();
    _api = null;
    final creds = await apiStore?.load();
    if (creds == null) {
      apiStatus = apiConfigured
          ? 'Credenziali non leggibili su questo PC'
          : null;
      return;
    }
    final api = _apiFactory(creds);
    try {
      await api.connect();
      pbxDirectory = await api.listExtensions();
      _api = api;
      apiStatus = 'Connessa · ${pbxDirectory.length} interni';
      debugPrint('[drinphone] api yeastar: ${pbxDirectory.length} interni');
      await _syncDialogs();
    } catch (e) {
      // e non contiene URL né token (YeastarApiException), solo operazione e codice.
      apiStatus = 'Errore: $e';
      debugPrint('[drinphone] api yeastar: $e');
      await api.close();
    }
  }

  /// Interni mostrati: quelli inseriti a mano più quelli del PBX, senza il proprio.
  List<Extension> get allExtensions {
    final own = settings.account?.username;
    final seen = <String>{};
    return [
      for (final e in [
        ...settings.extensions,
        for (final x in pbxDirectory)
          Extension(x.name.isEmpty ? x.number : x.name, x.number),
      ])
        if (e.number != own && seen.add(e.number)) e,
    ];
  }

  bool isManual(Extension e) => settings.extensions.contains(e);

  Future<void> saveAccount(SipAccount account, {required bool debugLog}) async {
    settings = Settings(
      account: account,
      debugLog: debugLog,
      extensions: settings.extensions,
    );
    await _store.save(settings);
    if (engineError == null) await _engine.register(account);
    notifyListeners();
  }

  Future<void> removeAccount() async {
    settings = Settings(
      debugLog: settings.debugLog,
      extensions: settings.extensions,
    );
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
    settings = Settings(
      account: settings.account,
      debugLog: settings.debugLog,
      extensions: list,
    );
    await _store.save(settings);
    await _syncDialogs();
    notifyListeners();
  }

  Set<String> get _watched => {
    for (final e in allExtensions.take(maxBlf)) e.number,
  };

  Future<void> _syncDialogs() async {
    blf.removeWhere((n, _) => !_watched.contains(n));
    if (engineError == null && registration.status == RegistrationStatus.ok) {
      await _engine.watchDialogs(_watched);
    }
  }

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
    registration = e;
    if (e.status == RegistrationStatus.ok) {
      _engine.watchDialogs(_watched);
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
    if (e.phase == CallPhase.ended || e.phase == CallPhase.error) {
      if (e.phase == CallPhase.error) {
        notice = 'Chiamata non riuscita: ${e.message}';
      }
      call = null;
      callConnectedAt = null;
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

  /// Chiusura ordinata (uscita dall'app): revoca il token API e ferma il motore,
  /// che invia l'un-REGISTER e scarica il log.
  Future<void> shutdown() async {
    await _api?.close();
    _api = null;
    await _engine.stop();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _engine.stop();
    super.dispose();
  }
}
