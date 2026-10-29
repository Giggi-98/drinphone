import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/call_history.dart';
import '../core/contacts/personal_contacts.dart';
import 'l10n.dart';
import '../core/pbx/pbx_cache.dart';
import '../core/platform/video_surface.dart';
import '../core/video/openh264.dart';
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
    this.historyStoreFor,
    this.personalStoreFor,
    this.cacheFor,
    this.openH264,
    this.recordingsDir = '',
    this.onIncomingCall,
    YeastarApi Function(ApiCredentials)? apiFactory,
  }) : _apiFactory = apiFactory ?? YeastarApi.new;

  /// Registro chiamate per profilo (DECISIONS "Profili").
  final CallHistoryStore Function(String profileId)? historyStoreFor;
  CallHistoryStore? get historyStore =>
      historyStoreFor?.call(settings.profileId);

  /// Codec H264 di Cisco, scaricato a richiesta (DECISIONS "Videochiamate").
  final OpenH264? openH264;

  /// Cartella delle registrazioni locali ('' = registrazione locale non disponibile).
  final String recordingsDir;

  /// OpenH264 installato e con impronta verificata all'avvio.
  bool h264Installed = false;

  /// Installato dopo l'avvio: il core lo carica al prossimo avvio dell'app.
  bool h264NeedsRestart = false;

  /// Cache cifrata dei dati di ogni connessione PBX (DECISIONS "Cache dati PBX").
  final PbxCache Function(String connectionId)? cacheFor;

  /// Contatti personali per profilo (DECISIONS "Profili").
  final PersonalContactsStore Function(String profileId)? personalStoreFor;
  List<PersonalContact> personal = [];

  /// Nome della rubrica dei contatti personali nel menu delle rubriche.
  static const personalBook = '*personal';

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

  // Inizio, connessione e risposta di ogni chiamata viva, per il registro.
  final _meta = <int, ({DateTime start, DateTime? connected, bool answered})>{};

  // Trasferimento assistito in corso: chiamata messa in attesa -> consultazione.
  int? _consultFrom;
  int? _consultTo;

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

  /// Stato di registrazione per account.
  final registrations = <String, RegistrationEvent>{};

  /// Registrazione dell'account principale (chip in alto).
  RegistrationEvent get registration =>
      registrations[settings.account?.id] ??
      const RegistrationEvent(RegistrationStatus.none);

  /// Chiamate in corso per id, in ordine di inizio.
  final calls = <int, CallEvent>{};

  /// Chiamata in primo piano: attiva, poi in uscita, poi in arrivo, poi in attesa.
  CallEvent? get call {
    for (final phase in [
      CallPhase.active,
      CallPhase.outgoing,
      CallPhase.incoming,
      CallPhase.paused,
    ]) {
      final c = calls.values.where((c) => c.phase == phase).lastOrNull;
      if (c != null) return c;
    }
    return null;
  }

  /// Le altre chiamate (in attesa o in arrivo durante una conversazione).
  List<CallEvent> get otherCalls => [
    for (final c in calls.values)
      if (c.id != call?.id) c,
  ];

  DateTime? get callConnectedAt => _meta[call?.id]?.connected;
  bool muted = false;
  String? notice;

  /// Stato BLF per numero interno; assente = sconosciuto.
  final blf = <String, BlfEvent>{};

  /// Ultimi stati BLF di ogni profilo (in memoria): dopo il cambio profilo si
  /// mostrano attenuati, "da confermare", finché il PBX non risponde.
  final _blfByProfile = <String, Map<String, BlfStatus>>{};
  Map<String, BlfStatus> _staleBlf = const {};

  /// Ridisegno raggruppato per gli aggiornamenti a raffica (BLF, eventi PBX).
  Timer? _notifyTimer;
  void _notifySoon() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 100), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> init() async {
    settings = await _store.load();
    appLang.value = AppLang.fromCode(settings.lang);
    history = await historyStore?.load() ?? [];
    personal = await personalStoreFor?.call(settings.profileId).load() ?? [];
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
    h264Installed = await openH264?.verified() ?? false;
    try {
      engineVersion = await _engine.start(
        dataDir: engineDataDir,
        logDir: logDir,
        debug: settings.debugLog,
        codecDir: h264Installed ? openH264!.dir : null,
      );
      debugPrint('[drinphone] motore liblinphone $engineVersion avviato');
      if (settings.accounts.isNotEmpty) {
        await _engine.setAccounts(settings.accounts);
      }
      await _engine.setCallOptions(settings.callOptions);
      await _engine.setVideo(settings.video);
      _engine.setRecordingDir(recordingsDir);
      // Dispositivi audio scelti in Preferenze > Audio ('' = predefinito).
      final (cap, play, ring) = settings.audio;
      await _engine.setAudioDevices(capture: cap, playback: play, ringer: ring);
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
    if (infos.isEmpty &&
        settings.profileId == Settings.defaultProfileId &&
        storeFor(legacyConnectionId).isSet) {
      infos = const [PbxConnectionInfo(legacyConnectionId, 'PBX')];
      settings = settings.copyWith(pbx: infos);
      await _store.save(settings);
    }
    for (final i in infos) {
      connections.add(_newConnection(i.id, i.label)..realtime = i.realtime);
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
    cache: cacheFor?.call(id),
  );

  /// Solo il PBX dell'account SIP legge la casella, quella del proprio interno.
  void _assignVoicemail() {
    final primary = primaryConnection;
    for (final c in connections) {
      c.voicemailOf = c == primary ? settings.account?.username : null;
    }
  }

  void _onConnectionUpdate(PbxConnection c, bool directoryChanged) {
    // Il PBX principale si riconosce dall'host, noto solo dopo aver letto le
    // credenziali: si riassegna qui (arriva a inizio sync, prima delle letture).
    _assignVoicemail();
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
      notifyListeners();
    } else {
      // Eventi in tempo reale a raffica (stato chiamata, presenza): raggruppati.
      _notifySoon();
    }
  }

  bool _groupExists(String g) {
    if (g == favoritesGroup) return true;
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

  /// Interruttore "Eventi in tempo reale" di una connessione (salvato).
  Future<void> setRealtime(PbxConnection c, bool on) async {
    c.setRealtime(on);
    await _saveConnectionList();
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
      pbx: [
        for (final c in connections)
          PbxConnectionInfo(c.id, c.label, realtime: c.realtime),
      ],
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
    final a = settings.account;
    return a == null ? null : connectionOf(a);
  }

  /// PBX di un account: quello scelto nelle impostazioni, altrimenti quello con
  /// lo stesso host, altrimenti (solo per il principale) l'unica connessione.
  PbxConnection? connectionOf(SipAccount a) =>
      connections.where((c) => c.id == a.pbxId).firstOrNull ??
      connections.where((c) => c.host == a.host).firstOrNull ??
      (a == settings.account && connections.length == 1
          ? connections.first
          : null);

  /// Account SIP con cui chiamare gli interni di una connessione PBX.
  SipAccount? accountForConnection(String connectionId) {
    for (final a in settings.accounts) {
      if (connectionOf(a)?.id == connectionId) return a;
    }
    return null;
  }

  /// Account per un interno: manuali sul principale, gli altri sul loro PBX.
  SipAccount? accountFor(Extension e) =>
      e.source.isEmpty ? settings.account : accountForConnection(e.source);

  bool _isRegistered(SipAccount? a) =>
      a != null && registrations[a.id]?.status == RegistrationStatus.ok;

  /// Chiave BLF di un interno: `numero@host` dell'account che lo osserva.
  String? _blfKey(Extension e) {
    final a = accountFor(e);
    return a == null ? null : '${e.number}@${a.host}';
  }

  /// Stato linea: BLF SIP, altrimenti stato chiamata dagli eventi API (30008).
  BlfStatus? blfOf(Extension e) => _blfFresh(e) ?? _staleOf(e);

  /// Stato non ancora confermato dal PBX dopo il cambio profilo.
  bool blfStale(Extension e) => _blfFresh(e) == null && _staleOf(e) != null;

  BlfStatus? _staleOf(Extension e) {
    final k = _blfKey(e);
    return k == null ? null : _staleBlf[k];
  }

  BlfStatus? _blfFresh(Extension e) {
    final k = _blfKey(e);
    final sip = k == null ? null : blf[k]?.status;
    if (sip != null && sip != BlfStatus.unknown) return sip;
    final c = e.source.isEmpty
        ? primaryConnection
        : connections.where((x) => x.id == e.source).firstOrNull;
    final api = c?.callStatus[e.number];
    if (api != null) return api;
    // "Sconosciuto" esplicito resta tale se non c'è uno stato precedente.
    return sip == BlfStatus.unknown && _staleOf(e) == null ? sip : null;
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

  /// Solo i membri diretti del reparto, senza i sotto-reparti (stile Linkus).
  bool directMembersOnly = false;

  void setDirectMembersOnly(bool v) {
    directMembersOnly = v;
    notifyListeners();
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
  bool isCallable(Extension e) => accountFor(e) != null;

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
    for (final x in personal) {
      for (final (label, number) in x.numbers) {
        final r = rank('${x.name} ${x.company}', number);
        if (r >= 0) {
          hits.add((r + 3, SearchHit(x.name, number, label: label)));
          break;
        }
      }
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

  // ---------------------------------------------------------------- profili

  /// Cambia profilo (mai durante una chiamata): un profilo attivo alla volta,
  /// DECISIONS "Profili". Restituisce false se non è stato possibile.
  Future<bool> switchProfile(String id) async {
    if (calls.isNotEmpty || id == settings.profileId) return false;
    await _loadProfile(settings.switchTo(id));
    return true;
  }

  /// Nuovo profilo vuoto, subito attivo.
  Future<bool> createProfile(String name, ProfileKind kind) async {
    if (calls.isNotEmpty) return false;
    final id = List.generate(
      8,
      (_) => Random.secure().nextInt(16).toRadixString(16),
    ).join();
    await _loadProfile(
      Settings(
        profileId: id,
        profileName: name.trim(),
        profileKind: kind,
        others: [...settings.others, settings.active],
        debugLog: settings.debugLog,
        lang: settings.lang,
        audio: settings.audio,
        callOptions: settings.callOptions,
        video: settings.video,
      ),
    );
    return true;
  }

  /// Primo avvio: nessun account in nessun profilo → procedura guidata.
  bool get needsSetup =>
      settings.allAccounts.isEmpty && settings.others.isEmpty;

  /// Nome e (nella procedura guidata) tipo del profilo attivo.
  Future<void> renameProfile(String name, {ProfileKind? kind}) async {
    if (name.trim().isEmpty) return;
    settings = settings.copyWith(profileName: name.trim(), profileKind: kind);
    await _store.save(settings);
    notifyListeners();
  }

  /// Elimina un profilo non attivo con le sue credenziali API, il registro e
  /// i contatti; le password SIP spariscono al salvataggio.
  Future<void> deleteProfile(String id) async {
    final p = settings.others.where((x) => x.id == id).firstOrNull;
    if (p == null) return;
    for (final c in p.pbx) {
      await apiStoreFor?.call(c.id).clear();
      await cacheFor?.call(c.id).clear();
    }
    _blfByProfile.remove(id);
    await historyStoreFor?.call(id).clear();
    await personalStoreFor?.call(id).clear();
    settings = settings.copyWith(
      others: [
        for (final x in settings.others)
          if (x.id != id) x,
      ],
    );
    await _store.save(settings);
    notifyListeners();
  }

  /// Ferma il profilo attivo e avvia [next]: account, connessioni PBX,
  /// registro e contatti.
  Future<void> _loadProfile(Settings next) async {
    for (final c in connections) {
      await c.stop();
    }
    connections.clear();
    selectedGroup = null;
    registrations.clear();
    _blfByProfile[settings.profileId] = {
      ..._staleBlf,
      for (final e in blf.entries)
        if (e.value.status != BlfStatus.unknown) e.key: e.value.status,
    };
    _staleBlf = _blfByProfile[next.profileId] ?? const {};
    blf.clear();
    _mwiNew = 0;
    _mwiOld = 0;
    settings = next;
    await _store.save(settings);
    history = await historyStore?.load() ?? [];
    personal = await personalStoreFor?.call(settings.profileId).load() ?? [];
    if (engineError == null) await _engine.setAccounts(settings.accounts);
    await _startConnections();
    _assignVoicemail();
    await _syncDialogs();
    notifyListeners();
  }

  /// Profilo Yeastar integrato (altrimenti SIP generico: niente API PBX).
  bool get isYeastar => settings.profileKind == ProfileKind.yeastar;

  /// Live Calls solo nei profili Yeastar con eventi in tempo reale attivi.
  bool get hasLiveCalls => isYeastar && connections.any((c) => c.realtime);

  // ------------------------------------------------------------------ video

  bool get videoEnabled => settings.video.enabled && engineError == null;

  List<String> videoDevices() =>
      engineError == null ? _engine.videoDevices() : const [];

  List<String> videoCodecs() =>
      engineError == null ? _engine.videoCodecs() : const [];

  Future<void> setVideoOptions(VideoOptions o) async {
    settings = settings.copyWith(video: o);
    await _store.save(settings);
    if (engineError == null) await _engine.setVideo(o);
    notifyListeners();
  }

  /// Finestre video permanenti (video remoto e anteprima), create una volta
  /// all'avvio e consegnate al core: il pannello e "Prova webcam" le mostrano,
  /// spostano e nascondono (core/platform/video_surface.dart).
  VideoSurface? remoteSurface, previewSurface;

  /// Chiamato dalla schermata principale quando la finestra dell'app esiste.
  Future<void> attachVideoSurfaces() async {
    if (engineError != null || remoteSurface != null) return;
    final remote = await VideoSurface.create();
    final preview = await VideoSurface.create();
    if (remote == null || preview == null) return;
    remoteSurface = remote;
    previewSurface = preview;
    await _engine.setVideoWindows(
      remote: remote.handle,
      preview: preview.handle,
    );
    notifyListeners();
  }

  // ------------------------------------------- finestra di chiamata

  final _notes = <int, String>{};
  final _recording = <int>{};

  String noteOf(int id) => _notes[id] ?? '';

  /// Nota della chiamata: finisce nel registro alla chiusura.
  void setNote(int id, String text) {
    text.trim().isEmpty ? _notes.remove(id) : _notes[id] = text.trim();
    notifyListeners();
  }

  SipAccount? _accountOfCall(CallEvent c) =>
      settings.accounts.where((a) => a.id == c.accountId).firstOrNull ??
      settings.account;

  /// Codice di registrazione del PBX per la chiamata: dalle API (Yeastar) in
  /// automatico o impostato nell'account; null = nessun codice.
  String? recordCodeFor(CallEvent c) {
    final a = _accountOfCall(c);
    if (a == null) return null;
    return switch (a.recording) {
      RecordingMode.auto => connectionOf(a)?.recordCode,
      RecordingMode.pbxCode => a.recordCode.isEmpty ? null : a.recordCode,
      _ => null,
    };
  }

  bool _recordsLocally(CallEvent c) =>
      _accountOfCall(c)?.recording == RecordingMode.local &&
      recordingsDir.isNotEmpty;

  /// Pulsante Registra disponibile per la chiamata.
  bool canRecord(CallEvent c) =>
      engineError == null && (_recordsLocally(c) || recordCodeFor(c) != null);

  /// Registrazione chiesta (locale o con codice PBX). Col codice il PBX non
  /// conferma lo stato: è quello chiesto da DrinPhone.
  bool isRecording(int id) => _recording.contains(id);

  /// Registra / ferma: file locale o codice funzione inviato in DTMF.
  Future<void> toggleRecording() async {
    final c = call;
    if (c == null || c.phase != CallPhase.active || !canRecord(c)) return;
    final on = !_recording.contains(c.id);
    if (_recordsLocally(c)) {
      on
          ? await _engine.startRecording(c.id)
          : await _engine.stopRecording(c.id);
    } else {
      for (final d in recordCodeFor(c)!.split('')) {
        await _engine.sendDtmf(c.id, d);
      }
    }
    on ? _recording.add(c.id) : _recording.remove(c.id);
    notifyListeners();
  }

  /// Qualità della chiamata da 0 a 5 (-1 = non nota), per le tacche del segnale.
  double callQuality(int id) =>
      engineError == null ? _engine.callQuality(id) : -1;

  /// Nuova chiamata durante una conversazione: quella attuale va in attesa.
  Future<void> newCall(String number) => consult(number);

  /// Conferenza: due o più chiamate stabilite da unire.
  bool get canMergeConference =>
      calls.values
          .where(
            (c) =>
                (c.phase == CallPhase.active || c.phase == CallPhase.paused) &&
                !c.inConference,
          )
          .length >=
      2;

  /// Unisce tutte le chiamate in una conferenza locale (mixata da DrinPhone).
  Future<void> mergeConference() async {
    if (!canMergeConference || engineError != null) return;
    _consultFrom = null;
    _consultTo = null;
    await _engine.conferenceAll();
    notifyListeners();
  }

  /// "Prova webcam" in Preferenze: anteprima della webcam fuori dalle chiamate.
  Future<void> setCameraTest(bool on) async {
    if (engineError == null) await _engine.setCameraPreview(on);
  }

  /// Webcam accesa/spenta nella chiamata corrente.
  Future<void> toggleCallVideo() async {
    final c = call;
    if (c == null || !videoEnabled) return;
    await _engine.setCallVideo(c.id, !c.video);
  }

  /// Download con consenso (la UI lo chiede prima) e verifica dell'impronta.
  Future<void> installH264() async {
    final o = openH264;
    if (o == null) return;
    await o.install();
    h264NeedsRestart = !h264Installed;
    notifyListeners();
  }

  Future<void> removeH264() async {
    await openH264?.remove();
    h264NeedsRestart = h264Installed;
    notifyListeners();
  }

  // ------------------------------------------------------------------ badge

  /// Chiamate perse arrivate dopo l'ultima visita al registro.
  int get missedUnseen {
    final since = DateTime.tryParse(settings.seenMissedAt);
    return history
        .where((r) => r.missed && (since == null || r.start.isAfter(since)))
        .length;
  }

  /// Messaggi nuovi non ancora visti nella sezione Casella vocale.
  int get voicemailUnseen {
    final seen = settings.seenVoicemail.toSet();
    final msgs = voicemailMessages;
    if (msgs != null) {
      return msgs.where((m) => !m.read && !seen.contains(m.id)).length;
    }
    final was =
        int.tryParse(
          seen.where((s) => s.startsWith('mwi:')).firstOrNull?.substring(4) ??
              '',
        ) ??
        0;
    return _mwiNew > was ? _mwiNew - was : 0;
  }

  Future<void> markHistorySeen() async {
    if (missedUnseen == 0) return;
    settings = settings.copyWith(
      seenMissedAt: DateTime.now().toIso8601String(),
    );
    await _store.save(settings);
    notifyListeners();
  }

  Future<void> markVoicemailSeen() async {
    if (voicemailUnseen == 0) return;
    settings = settings.copyWith(
      seenVoicemail: [
        for (final m in voicemailMessages ?? const <PbxVoicemail>[])
          if (!m.read) m.id,
        'mwi:$_mwiNew',
      ],
    );
    await _store.save(settings);
    notifyListeners();
  }

  /// Account per le chiamate a numeri liberi ("Chiama con" in alto).
  SipAccount? get outgoingAccount =>
      settings.accounts.where((a) => a.id == settings.callWith).firstOrNull ??
      settings.account;

  Future<void> setCallWith(String accountId) async {
    settings = settings.copyWith(callWith: accountId);
    await _store.save(settings);
    notifyListeners();
  }

  /// Dettaglio del proprio interno sul PBX dell'account (presenze, inoltri).
  PbxExtensionDetail? get ownDetail => primaryConnection?.ownDetail;

  /// Presenza del proprio interno; '' se il PBX non è collegato.
  String get ownPresence {
    final own = settings.account?.username;
    return primaryConnection?.directory
            .where((x) => x.number == own)
            .firstOrNull
            ?.presence ??
        '';
  }

  Future<void> refreshOwnDetail() async => primaryConnection?.refreshDetail();

  /// Ascolto messaggi: codice dell'account in uso, altrimenti del profilo.
  Future<void> callVoicemail() {
    final own = outgoingAccount?.voicemailCode ?? '';
    return dial(own.isNotEmpty ? own : settings.voicemailCode);
  }

  /// Opzioni globali delle chiamate (Preferenze > Avanzate).
  Future<void> setCallOptions(CallOptions o) async {
    settings = settings.copyWith(callOptions: o);
    await _store.save(settings);
    if (engineError == null) await _engine.setCallOptions(o);
    notifyListeners();
  }

  /// Chiave di gruppo per la vista Preferiti.
  static const favoritesGroup = '*favorites';

  String _favKey(Extension e) {
    final primary = primaryConnection?.id;
    final src = e.source.isEmpty || e.source == primary ? '' : e.source;
    return '$src:${e.number}';
  }

  bool isFavorite(Extension e) => settings.favorites.contains(_favKey(e));

  List<Extension> get favorites => allExtensions.where(isFavorite).toList();

  Future<void> toggleFavorite(Extension e) async {
    final key = _favKey(e);
    final favs = [...settings.favorites];
    favs.contains(key) ? favs.remove(key) : favs.add(key);
    settings = settings.copyWith(favorites: favs);
    await _store.save(settings);
    notifyListeners();
  }

  /// Interni della griglia secondo il gruppo selezionato.
  List<Extension> get visibleExtensions {
    final g = selectedGroup;
    if (g == null) return allExtensions;
    if (g == favoritesGroup) return favorites;
    final parts = g.split(':');
    final c = connections.where((c) => c.id == parts[0]).firstOrNull;
    if (c == null) return allExtensions;
    final org = parts.length > 1
        ? c.orgs.where((o) => '${o.id}' == parts[1]).firstOrNull
        : null;
    // extIds di un reparto include i sotto-reparti: per i diretti si tolgono.
    final ids = {...?org?.extIds};
    if (org != null && directMembersOnly) {
      for (final o in c.orgs) {
        if (o.parentId == org.id) ids.removeAll(o.extIds);
      }
    }
    final numbers = {
      for (final x in c.directory)
        if (org == null || ids.contains(x.id)) x.number,
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
    final primaryId = primaryConnection?.id;
    // Il proprio interno su ciascun PBX non compare nella griglia.
    bool isOwn(Extension e) {
      final a = accountFor(e);
      return a != null && a.username == e.number;
    }

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
        if (!isOwn(e) && seen.add(key(e))) e,
    ];
  }

  bool isManual(Extension e) => settings.extensions.contains(e);

  /// Rubrica aziendale di tutti i PBX filtrata da [filter] (nome, azienda, cifre).
  /// Righe della rubrica: prima i contatti personali (connessione null,
  /// rubrica [personalBook]), poi quelli dei PBX.
  List<(PbxConnection?, PbxContact, PersonalContact?)> contactsMatching(
    String filter,
  ) {
    final q = filter.trim().toLowerCase();
    bool hit(String name, String company, List<(String, String)> numbers) =>
        q.isEmpty ||
        name.toLowerCase().contains(q) ||
        company.toLowerCase().contains(q) ||
        numbers.any((n) => _digits(n.$2).contains(q));
    final own = [...personal]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [
      for (final x in own)
        if (hit(x.name, x.company, x.numbers))
          (
            null,
            PbxContact(
              id: 0,
              name: x.name,
              company: x.company,
              email: x.email,
              numbers: x.numbers,
              phonebooks: const [personalBook],
            ),
            x,
          ),
      for (final c in connections)
        for (final x in c.contacts)
          if (hit(x.name, x.company, x.numbers)) (c, x, null),
    ];
  }

  /// Aggiunge o sostituisce (stesso id) un contatto personale.
  Future<void> savePersonal(PersonalContact contact) async {
    final list = [...personal];
    final i = list.indexWhere((x) => x.id == contact.id);
    i >= 0 ? list[i] = contact : list.add(contact);
    await _setPersonal(list);
  }

  Future<void> deletePersonal(String id) =>
      _setPersonal(personal.where((x) => x.id != id).toList());

  /// Già in rubrica personale: almeno un numero uguale ([sameNumber]).
  bool isPersonalDuplicate(PersonalContact c) => personal.any(
    (x) => x.numbers.any((a) => c.numbers.any((b) => sameNumber(a.$2, b.$2))),
  );

  /// Importa [list]; con [skipDuplicates] salta chi ha un numero già presente.
  /// Restituisce quanti contatti sono stati aggiunti.
  Future<int> importPersonal(
    List<PersonalContact> list, {
    bool skipDuplicates = true,
  }) async {
    final add = [
      for (final c in list)
        if (!skipDuplicates || !isPersonalDuplicate(c)) c,
    ];
    await _setPersonal([...personal, ...add]);
    return add.length;
  }

  Future<void> _setPersonal(List<PersonalContact> list) async {
    personal = list;
    await personalStoreFor?.call(settings.profileId).save(list);
    notifyListeners();
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

  /// Nome per un numero: interni (anche di altri PBX), contatti personali,
  /// poi rubrica aziendale.
  String nameFor(String number) {
    if (number.isEmpty) return '';
    for (final e in allExtensions) {
      if (e.number == number && e.name != e.number) return e.name;
    }
    for (final x in personal) {
      if (x.numbers.any((n) => sameNumber(n.$2, number))) return x.name;
    }
    for (final c in connections) {
      for (final x in c.contacts) {
        if (x.numbers.any((n) => sameNumber(n.$2, number))) return x.name;
      }
    }
    return '';
  }

  // ---------------------------------------------------------------- account

  /// Aggiunge o sostituisce (stesso id) un account SIP e riregistra tutti.
  Future<void> saveAccount(SipAccount account) async {
    final list = [...settings.accounts];
    final i = list.indexWhere((a) => a.id == account.id);
    i >= 0 ? list[i] = account : list.add(account);
    await _applyAccounts(list);
  }

  Future<void> removeAccount(String id) =>
      _applyAccounts(settings.accounts.where((a) => a.id != id).toList());

  /// Dispositivi audio del sistema (rilettura a ogni apertura di Preferenze > Audio).
  List<SoundDevice> soundDevices() =>
      engineError == null ? _engine.soundDevices() : const [];

  /// Dispositivi in uso nel motore: (microfono, altoparlante, suoneria).
  (String, String, String) get audioDevices =>
      engineError == null ? _engine.audioDevices() : ('', '', '');

  Future<void> setAudio({
    String? capture,
    String? playback,
    String? ringer,
  }) async {
    final (c, p, r) = settings.audio;
    settings = settings.copyWith(
      audio: (capture ?? c, playback ?? p, ringer ?? r),
    );
    await _store.save(settings);
    await _engine.setAudioDevices(
      capture: capture,
      playback: playback,
      ringer: ringer,
    );
    notifyListeners();
  }

  Future<void> setDebugLog(bool on) async {
    settings = settings.copyWith(debugLog: on);
    await _store.save(settings);
    notifyListeners();
  }

  /// Nuovo id per un account aggiunto (il primo resta `main`).
  String newAccountId() => settings.allAccounts.isEmpty
      ? 'main'
      : List.generate(
          8,
          (_) => Random.secure().nextInt(16).toRadixString(16),
        ).join();

  Future<void> _applyAccounts(List<SipAccount> list) async {
    settings = settings.copyWith(accounts: list);
    await _store.save(settings);
    registrations.removeWhere((id, _) => !list.any((a) => a.id == id));
    blf.clear();
    _assignVoicemail();
    if (engineError == null) await _engine.setAccounts(list);
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

  /// Interni in BLF: solo quelli con l'account del loro PBX registrato.
  Set<String> get _watched => {
    for (final e
        in allExtensions
            .where((e) => _isRegistered(accountFor(e)))
            .take(maxBlf))
      _blfKey(e)!,
  };

  Future<void> _syncDialogs() async {
    final watched = _watched;
    blf.removeWhere((n, _) => !watched.contains(n));
    if (engineError == null) await _engine.watchDialogs(watched);
  }

  // ---------------------------------------------------------------- chiamate

  bool get _registered =>
      engineError == null && settings.accounts.any(_isRegistered);

  /// Nuova chiamata dal campo o dalle schede: solo senza altre chiamate.
  bool get canDial => _registered && calls.isEmpty;

  /// Chiama [number]; con [via] (un interno) usa l'account del suo PBX.
  Future<void> dial(String number, {Extension? via, bool video = false}) async {
    final n = number.trim();
    if (n.isEmpty || !canDial) return;
    final a = via == null ? outgoingAccount : accountFor(via);
    await _engine.dial(
      n,
      accountId: a == null || a == settings.account ? null : a.id,
      video: video && videoEnabled,
    );
  }

  /// Risponde alla chiamata in arrivo; un'eventuale conversazione va in attesa.
  Future<void> answer([int? id, bool video = false]) async {
    final target =
        id ??
        calls.values
            .where((c) => c.phase == CallPhase.incoming)
            .firstOrNull
            ?.id;
    if (target == null) return;
    await _holdOthers(target);
    await _engine.answer(target, video: video && videoEnabled);
  }

  Future<void> hangup([int? id]) async {
    final target = id ?? call?.id;
    if (target != null) await _engine.hangup(target);
  }

  Future<void> sendDtmf(String d) async {
    final id = call?.id;
    if (id != null) await _engine.sendDtmf(id, d);
  }

  Future<void> _holdOthers(int keep) async {
    for (final c in calls.values.toList()) {
      if (c.id != keep && c.phase == CallPhase.active) await _engine.hold(c.id);
    }
  }

  /// Chiamata in primo piano messa in attesa da noi o dall'altro capo.
  bool get onHold => call?.phase == CallPhase.paused;

  Future<void> toggleHold() async {
    final c = call;
    if (c == null) return;
    await (c.phase == CallPhase.paused ? resumeCall(c.id) : _engine.hold(c.id));
  }

  /// Riprende [id] mettendo in attesa la conversazione attiva (scambio).
  Future<void> resumeCall(int id) async {
    await _holdOthers(id);
    await _engine.resume(id);
  }

  /// Trasferimento cieco della chiamata in primo piano.
  Future<void> transfer(String number) async {
    final id = call?.id;
    if (id != null) await _engine.transfer(id, number.trim());
  }

  /// Trasferimento assistito, passo 1: la chiamata va in attesa e si chiama
  /// [number] per consultarsi.
  Future<void> consult(String number) async {
    final from = call;
    final n = number.trim();
    if (from == null || n.isEmpty || from.phase != CallPhase.active) return;
    await _engine.hold(from.id);
    final to = await _engine.dial(n);
    if (to == null) return;
    _consultFrom = from.id;
    _consultTo = to;
    notifyListeners();
  }

  /// Consultazione in corso con l'interlocutore che risponde: si può completare.
  bool get canCompleteTransfer =>
      calls.containsKey(_consultFrom) &&
      calls[_consultTo]?.phase == CallPhase.active;

  /// Trasferimento assistito, passo 2: collega le due chiamate e si esce.
  Future<void> completeTransfer() async {
    final from = _consultFrom, to = _consultTo;
    if (from == null || to == null || !canCompleteTransfer) return;
    await _engine.transferAttended(from, to);
  }

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
    debugPrint(
      '[drinphone] registrazione ${e.accountId} ${e.status.name} ${e.message}',
    );
    final wasOk = registrations[e.accountId]?.status == RegistrationStatus.ok;
    registrations[e.accountId] = e;
    if (e.status == RegistrationStatus.ok) {
      _syncDialogs();
      // Rete tornata dopo una caduta: riallinea anche i dati dal PBX.
      if (!wasOk) resync(force: false);
    } else {
      // Stato linea non più affidabile per gli interni di quell'account.
      final host = settings.accounts
          .where((a) => a.id == e.accountId)
          .firstOrNull
          ?.host;
      blf.removeWhere((k, _) => host != null && k.endsWith('@$host'));
    }
    notifyListeners();
  }

  void _onDialog(BlfEvent e) {
    debugPrint('[drinphone] blf ${e.number} ${e.status.name} ${e.reason}');
    blf[e.number] = e;
    _notifySoon();
  }

  void _onCall(CallEvent e) {
    debugPrint(
      '[drinphone] chiamata ${e.id} ${e.direction.name} ${e.phase.name} ${e.message}',
    );
    final isNew = !calls.containsKey(e.id);
    if (isNew && e.phase == CallPhase.incoming) onIncomingCall?.call();
    final m =
        _meta[e.id] ??
        (start: DateTime.now(), connected: null, answered: false);
    if (e.phase == CallPhase.ended || e.phase == CallPhase.error) {
      _record(e, calls[e.id], m);
      if (e.phase == CallPhase.error) {
        notice = tr('Chiamata non riuscita: {m}', {'m': e.message});
      }
      calls.remove(e.id);
      _meta.remove(e.id);
      _recording.remove(e.id);
      if (e.id == _consultFrom || e.id == _consultTo) {
        _consultFrom = null;
        _consultTo = null;
      }
      if (calls.isEmpty && muted) {
        muted = false;
        _engine.setMicMuted(false);
      }
    } else {
      final active = e.phase == CallPhase.active;
      _meta[e.id] = (
        start: m.start,
        connected: m.connected ?? (active ? DateTime.now() : null),
        answered: m.answered || active,
      );
      // Il nome remoto arriva solo nei primi eventi: non perderlo dopo.
      final prev = calls[e.id];
      calls[e.id] = e.remoteName.isEmpty && prev != null
          ? CallEvent(
              id: e.id,
              phase: e.phase,
              direction: e.direction,
              remoteNumber: e.remoteNumber.isNotEmpty
                  ? e.remoteNumber
                  : prev.remoteNumber,
              remoteName: prev.remoteName,
              message: e.message,
              video: e.video,
              remoteVideo: e.remoteVideo,
              accountId: e.accountId,
              inConference: e.inConference,
            )
          : e;
    }
    notifyListeners();
  }

  void _record(
    CallEvent e,
    CallEvent? last,
    ({DateTime start, DateTime? connected, bool answered}) m,
  ) {
    final number = e.remoteNumber.isNotEmpty
        ? e.remoteNumber
        : (last?.remoteNumber ?? '');
    final sipName = e.remoteName.isNotEmpty
        ? e.remoteName
        : (last?.remoteName ?? '');
    final connected = m.connected;
    history = [
      CallRecord(
        number: number,
        name: sipName.isNotEmpty ? sipName : nameFor(number),
        direction: e.direction,
        start: m.start,
        seconds: connected == null
            ? 0
            : DateTime.now().difference(connected).inSeconds,
        answered: m.answered,
        note: _notes.remove(e.id) ?? '',
      ),
      ...history,
    ].take(CallHistoryStore.maxRecords).toList();
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
    _notifyTimer?.cancel();
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
