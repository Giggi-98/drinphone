// Una connessione OpenAPI verso un PBX Yeastar: credenziali proprie (file DPAPI
// dedicato), token, elenco interni e reparti, ciclo di sincronizzazione.
// Più connessioni convivono senza condividere nulla (multi-PBX).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../app/l10n.dart';
import '../security/api_credential_store.dart';
import '../sip/sip_engine.dart' show BlfStatus;
import 'yeastar_api.dart';

/// Chiamata in corso sul PBX (Live Calls).
class LiveCall {
  LiveCall(this.id, this.members) : seen = DateTime.now();
  final String id;
  List<LiveMember> members;

  /// Prima volta vista (inizio approssimato) e prima risposta.
  final DateTime seen;
  DateTime? answered;

  bool get ringing =>
      members.any((m) => m.status == 'RING' || m.status == 'ALERT');
  bool get onHold => members.any((m) => m.status == 'HOLD');
  bool get talking =>
      members.any((m) => m.status == 'ANSWER' || m.status == 'ANSWERED');

  /// Chiamata verso l'esterno (Linkus: "Outbound Calls").
  bool get outbound => members.any((m) => m.kind == 'outbound');

  LiveMember? _of(String kind) =>
      members.where((m) => m.kind == kind).firstOrNull;

  /// Chiamante: da inbound/outbound/internal, altrimenti il primo interno.
  String get caller {
    for (final k in ['inbound', 'outbound', 'internal']) {
      final m = _of(k);
      if (m != null && m.from.isNotEmpty) return m.from;
    }
    return members.where((m) => m.kind == 'extension').firstOrNull?.number ??
        '';
  }

  /// Chiamato: interni coinvolti diversi dal chiamante, o il numero esterno.
  String get callee {
    final out = _of('outbound');
    if (out != null && out.to.isNotEmpty) return out.to;
    final exts = [
      for (final m in members)
        if (m.kind == 'extension' && m.number != caller) m.number,
    ];
    if (exts.isNotEmpty) return exts.join(', ');
    return (_of('inbound') ?? _of('internal'))?.to ?? '';
  }

  String get trunk =>
      members.map((m) => m.trunk).where((t) => t.isNotEmpty).firstOrNull ?? '';
  String get path =>
      members.map((m) => m.path).where((t) => t.isNotEmpty).firstOrNull ?? '';
}

class PbxConnection {
  PbxConnection({
    required this.id,
    required this.label,
    required this.store,
    required this.apiFactory,
    required this.onUpdate,
  });

  final String id;
  String label;
  final ApiCredentialStore store;
  final YeastarApi Function(ApiCredentials) apiFactory;

  /// `directoryChanged`: interni o reparti diversi dall'ultima lettura.
  final void Function(PbxConnection c, bool directoryChanged) onUpdate;

  YeastarApi? _api;
  List<PbxExtension> directory = const [];
  List<PbxOrg> orgs = const [];

  /// Rubrica aziendale; vuota se l'API non la espone o non è autorizzata.
  List<PbxContact> contacts = const [];

  /// Eventi in tempo reale via WebSocket (interruttore della connessione).
  bool realtime = false;

  /// Stato di chiamata per interno dall'evento 30008 (BLF senza SIP).
  final callStatus = <String, BlfStatus>{};

  /// Chiamate in corso sul PBX (evento 30011 + fotografia call/query).
  final liveCalls = <String, LiveCall>{};

  /// Stato leggibile del canale eventi; vuoto se spento.
  String eventsStatus = '';
  bool get eventsConnected => _ws != null;

  WebSocket? _ws;
  Timer? _heartbeat;
  Timer? _wsRetry;
  Timer? _resyncSoon;
  int _wsFailures = 0;

  /// Eventi sottoscritti: registrazione (30007), stato chiamata (30008),
  /// presenza (30009), anagrafica interno cambiata (30022).
  static const eventTopics = [30007, 30008, 30009, 30011, 30022];

  /// Tipi di call/query per la fotografia iniziale (DA VALIDARE sul PBX).
  static const _callTypes = ['inbound', 'outbound', 'internal'];

  /// Interno di cui leggere la casella vocale (l'account SIP); null = nessuno.
  String? voicemailOf;

  /// Messaggi in casella; null = non letti dall'API (non disponibile o errore).
  List<PbxVoicemail>? voicemail;
  String status = tr('Non connessa');
  bool ok = false;
  bool syncing = false;
  DateTime? lastSync;

  /// Indirizzo API (non segreto), per mostrarlo e per riconoscere il PBX
  /// dell'account SIP.
  String baseUrl = '';
  String get host => Uri.tryParse(baseUrl)?.host ?? '';

  /// Problemi delle letture facoltative dell'ultimo giro (reparti, rubrica).
  final optionalErrors = <String>[];

  // Messaggio breve: tipo ed eventuale codice, mai URL o token.
  static String _short(Object e) =>
      e is YeastarApiException ? '$e' : e.runtimeType.toString();

  Timer? _timer;
  int _failures = 0;
  DateTime? _orgsAt;
  String _fingerprint = '';
  bool _stopped = false;

  /// Presenza ogni minuto; reparti più di rado (cambiano poco); errori con
  /// attesa crescente fino a 15 minuti (limite 8 token e blocco IP).
  static const presenceEvery = Duration(seconds: 60);
  static const orgsEvery = Duration(minutes: 10);
  static const maxBackoff = Duration(minutes: 15);
  static const minGap = Duration(seconds: 10);

  Future<void> start() async {
    await stop();
    _stopped = false;
    final creds = await store.load();
    if (creds == null) {
      ok = false;
      status = store.isSet
          ? tr('Credenziali non leggibili su questo PC')
          : tr('Credenziali mancanti');
      onUpdate(this, false);
      return;
    }
    baseUrl = creds.baseUrl;
    final api = apiFactory(creds);
    // Token rinnovato: il WebSocket si ricollega con quello nuovo.
    api.onTokens = () {
      if (_ws != null) _ws!.close();
    };
    _api = api;
    await sync(force: true);
  }

  /// Rilettura dal PBX. Senza [force] viene saltata se l'ultima è troppo recente.
  Future<void> sync({bool force = false}) async {
    final api = _api;
    if (api == null || syncing || _stopped) return;
    final last = lastSync;
    if (!force && last != null && DateTime.now().difference(last) < minGap) {
      return;
    }
    _timer?.cancel();
    syncing = true;
    onUpdate(this, false);
    var changed = false;
    optionalErrors.clear();
    try {
      if (!api.connected) await api.connect();
      final ext = await api.listExtensions();
      final idsChanged =
          ext
              .map((e) => e.id)
              .toSet()
              .difference(directory.map((e) => e.id).toSet())
              .isNotEmpty ||
          ext.length != directory.length;
      var newOrgs = orgs;
      var newContacts = contacts;
      final orgsAt = _orgsAt;
      if (force ||
          idsChanged ||
          orgsAt == null ||
          DateTime.now().difference(orgsAt) > orgsEvery) {
        try {
          newOrgs = await api.listOrganizations();
        } catch (e) {
          // Reparti facoltativi: si tengono gli ultimi letti; non bloccano gli interni.
          optionalErrors.add('reparti: ${_short(e)}');
        }
        // Rubrica: stessa cadenza lenta dei reparti, cambia di rado.
        try {
          newContacts = await api.listCompanyContacts();
        } catch (e) {
          // Rubrica facoltativa (permessi, formato diverso dalla documentazione).
          optionalErrors.add('rubrica: ${_short(e)}');
        }
        _orgsAt = DateTime.now();
      }
      // Casella vocale a ogni giro: è ciò che l'utente si aspetta di vedere subito.
      final vmOf = voicemailOf;
      List<PbxVoicemail>? newVm;
      if (vmOf != null && vmOf.isNotEmpty) {
        try {
          newVm = await api.listVoicemail(vmOf);
        } catch (e) {
          optionalErrors.add('casella vocale: ${_short(e)}');
        }
      }
      final fp =
          '${_fingerprintOf(ext, newOrgs, newContacts)}\n'
          '${newVm?.map((m) => '${m.id}|${m.read}').join(',')}';
      changed = fp != _fingerprint;
      _fingerprint = fp;
      directory = ext;
      orgs = newOrgs;
      contacts = newContacts;
      voicemail = newVm;
      lastSync = DateTime.now();
      _failures = 0;
      ok = true;
      status = tr('Sincronizzata · {e} interni, {o} reparti, {c} contatti', {
        'e': ext.length,
        'o': newOrgs.length,
        'c': newContacts.length,
      });
    } catch (e) {
      // e non contiene URL né token (YeastarApiException), solo operazione e codice.
      _failures++;
      ok = false;
      status = tr('Errore: {e} · nuovo tentativo tra {m} min', {
        'e': e,
        'm': _nextDelay().inMinutes,
      });
    } finally {
      syncing = false;
      if (!_stopped) _timer = Timer(_nextDelay(), sync);
      onUpdate(this, changed);
    }
    if (ok && realtime && _ws == null && _wsRetry == null) _connectEvents();
  }

  /// Accende o spegne il canale eventi senza riavviare la connessione.
  void setRealtime(bool on) {
    realtime = on;
    if (on) {
      _connectEvents();
    } else {
      _closeEvents();
      eventsStatus = '';
      callStatus.clear();
      liveCalls.clear();
      onUpdate(this, false);
    }
  }

  Future<void> _connectEvents() async {
    _wsRetry = null;
    final api = _api;
    if (!realtime || _stopped || api == null || !api.connected || _ws != null) {
      return;
    }
    try {
      final ws = await WebSocket.connect(
        api.eventsUri().toString(),
        headers: {HttpHeaders.userAgentHeader: YeastarApi.userAgent},
      ).timeout(const Duration(seconds: 15));
      _ws = ws;
      ws.add(jsonEncode({'topic_list': eventTopics}));
      // Senza traffico il PBX chiude dopo 60 s.
      _heartbeat = Timer.periodic(
        const Duration(seconds: 30),
        (_) => ws.add('heartbeat'),
      );
      eventsStatus = tr('Eventi in tempo reale: collegamento…');
      ws.listen(
        _onEvent,
        onDone: _onEventsClosed,
        onError: (_) => _onEventsClosed(),
        cancelOnError: true,
      );
    } catch (e) {
      // Il messaggio di WebSocketException può contenere l'URL col token.
      _wsFailures++;
      eventsStatus = tr('Eventi non disponibili ({e}), nuovo tentativo', {
        'e': e.runtimeType,
      });
      _scheduleEvents();
    }
    onUpdate(this, false);
  }

  void _onEventsClosed() {
    _heartbeat?.cancel();
    _ws = null;
    if (!_stopped && realtime) {
      eventsStatus = tr('Eventi in tempo reale: riconnessione…');
      _scheduleEvents();
    }
    onUpdate(this, false);
  }

  void _scheduleEvents() {
    _wsRetry?.cancel();
    final secs = min(5 * pow(2, min(_wsFailures, 6)).toInt(), 300);
    _wsRetry = Timer(Duration(seconds: secs), _connectEvents);
  }

  void _closeEvents() {
    _wsRetry?.cancel();
    _wsRetry = null;
    _heartbeat?.cancel();
    _ws?.close();
    _ws = null;
  }

  /// Fotografia delle chiamate in corso: gli eventi 30011 arrivano solo sui cambi.
  Future<void> _snapshotCalls() async {
    final api = _api;
    if (api == null) return;
    for (final type in _callTypes) {
      try {
        final calls = await api.queryCalls(type);
        for (final e in calls.entries) {
          liveCalls.putIfAbsent(e.key, () => LiveCall(e.key, e.value)).members =
              e.value;
        }
      } catch (e) {
        debugPrint('[drinphone] call/query $type: ${_short(e)}');
      }
    }
    liveCalls.removeWhere((_, c) => c.members.isEmpty);
    onUpdate(this, false);
  }

  /// Evento 30011: aggiorna i membri per canale; i BYE escono, la chiamata
  /// sparisce quando non resta nessuno.
  void _applyCall(Map<String, dynamic> msg) {
    final id = '${msg['call_id'] ?? ''}';
    if (id.isEmpty) return;
    final incoming = LiveMember.parse(msg['members'] as List? ?? const []);
    final call = liveCalls.putIfAbsent(id, () => LiveCall(id, const []));
    final byChannel = {for (final m in call.members) m.channel: m};
    for (final m in incoming) {
      byChannel[m.channel] = m;
    }
    call.members = [
      for (final m in byChannel.values)
        if (m.status != 'BYE') m,
    ];
    if (call.talking) call.answered ??= DateTime.now();
    if (call.members.isEmpty) liveCalls.remove(id);
  }

  static BlfStatus? _callState(String s) => switch (s.toLowerCase()) {
    'idle' => BlfStatus.idle,
    'ringing' => BlfStatus.ringing,
    'busy' => BlfStatus.busy,
    _ => null,
  };

  void _onEvent(dynamic data) {
    if (data is! String || data.startsWith('heartbeat')) return;
    Map<String, dynamic> j;
    try {
      j = jsonDecode(data) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    // Risposta alla sottoscrizione.
    if (j.containsKey('errcode') && !j.containsKey('type')) {
      final code = j['errcode'];
      eventsStatus = code == 0
          ? tr('Eventi in tempo reale attivi')
          : tr('Eventi rifiutati dal PBX (errcode {c})', {'c': code});
      if (code == 0) {
        _wsFailures = 0;
        _snapshotCalls();
      }
      onUpdate(this, false);
      return;
    }
    final type = (j['type'] as num?)?.toInt();
    var msg = j['msg'];
    if (msg is String) {
      try {
        msg = jsonDecode(msg);
      } on FormatException {
        return;
      }
    }
    if (msg is! Map<String, dynamic>) return;
    // Solo tipo e nomi dei campi nel log (i valori sono dati personali).
    debugPrint('[drinphone] evento pbx $type ${msg.keys.toList()}');
    final ext = '${msg['extension'] ?? msg['number'] ?? ''}';
    switch (type) {
      case 30008:
        final st = _callState('${msg['status'] ?? ''}');
        if (ext.isNotEmpty && st != null) callStatus[ext] = st;
        onUpdate(this, false);
      case 30009:
        final presence = '${msg['presence_status'] ?? msg['status'] ?? ''}';
        if (ext.isNotEmpty && presence.isNotEmpty) {
          directory = [
            for (final e in directory)
              e.number == ext
                  ? PbxExtension(
                      id: e.id,
                      number: e.number,
                      name: e.name,
                      email: e.email,
                      mobile: e.mobile,
                      presence: presence,
                    )
                  : e,
          ];
          onUpdate(this, false);
        }
      case 30011:
        _applyCall(msg);
        onUpdate(this, false);
      case 30022:
        // Anagrafica cambiata: rilettura a breve (più eventi ravvicinati = una).
        _resyncSoon?.cancel();
        _resyncSoon = Timer(
          const Duration(seconds: 3),
          () => sync(force: true),
        );
      default:
        break;
    }
  }

  Duration _nextDelay() {
    // Con gli eventi attivi la presenza arriva in tempo reale: lettura di rado.
    if (_failures == 0 && _ws != null) return const Duration(minutes: 5);
    if (_failures == 0) return presenceEvery;
    final s = presenceEvery.inSeconds * pow(2, min(_failures, 4));
    return Duration(seconds: min(s.toInt(), maxBackoff.inSeconds));
  }

  static String _fingerprintOf(
    List<PbxExtension> ext,
    List<PbxOrg> orgs,
    List<PbxContact> contacts,
  ) => [
    for (final e in ext) '${e.id}|${e.number}|${e.name}|${e.presence}',
    for (final o in orgs) '${o.id}|${o.parentId}|${o.name}|${o.extIds.length}',
    for (final c in contacts) '${c.id}|${c.name}|${c.numbers}',
  ].join('\n');

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _resyncSoon?.cancel();
    _closeEvents();
    await _api?.close();
    _api = null;
  }

  /// Ferma e cancella le credenziali di questa connessione.
  Future<void> forget() async {
    await stop();
    await store.clear();
    directory = const [];
    orgs = const [];
    contacts = const [];
  }
}
