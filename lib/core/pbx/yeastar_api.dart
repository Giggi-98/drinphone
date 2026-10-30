// Client minimo Yeastar P-Series OpenAPI v1.0, sola lettura (docs/yeastar-openapi.md).
// Token in query string per specifica Yeastar: gli URL non vanno MAI nei log
// né nei messaggi d'errore. TLS con verifica standard (nessun bypass certificati).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../security/api_credential_store.dart';

class YeastarApiException implements Exception {
  YeastarApiException(this.operation, this.errcode, this.errmsg);
  final String operation;
  final int errcode;
  final String errmsg;
  @override
  String toString() => 'Yeastar API $operation: errcode=$errcode $errmsg';
}

class PbxExtension {
  const PbxExtension({
    this.id = 0,
    required this.number,
    required this.name,
    this.email = '',
    this.mobile = '',
    this.presence = '',
  });

  /// ID interno del PBX: è quello elencato in `ext_list` dei reparti.
  final int id;
  final String number;
  final String name;
  final String email;
  final String mobile;

  /// `available`, `away`, `business_trip`, `do_not_disturb`, `lunch`, `off_work`.
  final String presence;
}

/// Contatto della rubrica aziendale (company_contact/list).
class PbxContact {
  const PbxContact({
    required this.id,
    required this.name,
    this.company = '',
    this.jobTitle = '',
    this.email = '',
    this.numbers = const [],
    this.phonebooks = const [],
  });
  final int id;
  final String name;
  final String company;
  final String jobTitle;
  final String email;

  /// (etichetta, numero) dei soli campi valorizzati, fax esclusi.
  final List<(String, String)> numbers;
  final List<String> phonebooks;
}

/// Partecipante di una chiamata in corso (call/query, evento 30011).
class LiveMember {
  const LiveMember({
    required this.kind,
    required this.channel,
    required this.status,
    this.number = '',
    this.from = '',
    this.to = '',
    this.trunk = '',
    this.path = '',
  });

  /// `extension`, `internal`, `inbound`, `outbound`.
  final String kind;
  final String channel;

  /// ALERT, RING, EARLYMEDIA, ANSWERED, ANSWER, HOLD, BYE.
  final String status;
  final String number;
  final String from;
  final String to;
  final String trunk;

  /// IVR, Queue, Ring Group… se la chiamata ci è passata.
  final String path;

  /// Identità nella chiamata: l'interno per numero, le tratte per estremi.
  /// Il `channel_id` può cambiare (risposta, trasferimento): non basta.
  String get key => number.isEmpty && from.isEmpty && to.isEmpty
      ? '$kind|$channel'
      : (kind == 'extension' ? '$kind|$number' : '$kind|$from|$to');

  static List<LiveMember> parse(List<dynamic> members) => [
    for (final m in members.whereType<Map<String, dynamic>>())
      for (final e in m.entries)
        if (e.value is Map<String, dynamic>)
          LiveMember(
            kind: e.key,
            channel: '${e.value['channel_id'] ?? ''}',
            status: '${e.value['member_status'] ?? ''}'.toUpperCase(),
            number: '${e.value['number'] ?? ''}',
            from: '${e.value['from'] ?? ''}',
            to: '${e.value['to'] ?? ''}',
            trunk: '${e.value['trunk_name'] ?? ''}',
            path: '${e.value['call_path'] ?? ''}',
          ),
  ];
}

/// Inoltro di una condizione di una presenza (vista su `presence_list`).
class PresenceForward {
  const PresenceForward({
    required this.enabled,
    required this.dest,
    this.value = '',
    this.number = '',
    this.prefix = '',
    this.callConfirm = false,
  });
  final bool enabled;

  /// `extension`, `ext_vm`, `ivr`, `queue`, `ring_group`, `mobile_number`,
  /// `external_num`, `play_greeting`, `end_call`, `send_busy`…
  final String dest;

  /// Id della destinazione interna (o file del messaggio).
  final String value;

  /// Numero esterno per `external_num`.
  final String number;

  /// Prefisso di uscita (numeri) o ripetizioni (messaggio registrato).
  final String prefix;

  /// Il destinatario esterno deve premere un tasto per accettare.
  final bool callConfirm;

  /// Campi di `presence_list` per la condizione [cond] (es. `ex_busy`).
  Map<String, Object> toJson(String cond) => {
    'enb_${cond}_forward': enabled ? 1 : 0,
    '${cond}_forward_dest': dest,
    '${cond}_forward_value': value,
    '${cond}_forward_num': number,
    '${cond}_forward_prefix': prefix,
    '${cond}_forward_call_confirm': callConfirm ? 1 : 0,
  };
}

/// Una delle sei presenze: inoltri per chiamate interne ed esterne e, su
/// Yeastar P-Series, anche squillo, cellulare, gruppi e messaggio di benvenuto
/// (verificato sul pilota: questi campi stanno qui, non sull'interno).
class PresenceSetting {
  const PresenceSetting(this.raw);
  final Map<String, dynamic> raw;

  static const conditions = [
    'in_always',
    'in_no_answer',
    'in_busy',
    'ex_always',
    'ex_no_answer',
    'ex_busy',
  ];

  String get status => _s(raw, 'status');

  Map<String, PresenceForward> get forwards => {
    for (final k in conditions)
      k: PresenceForward(
        enabled: _flag(raw, 'enb_${k}_forward'),
        dest: _s(raw, '${k}_forward_dest'),
        value: _s(raw, '${k}_forward_value'),
        number: _s(raw, '${k}_forward_num'),
        prefix: _s(raw, '${k}_forward_prefix'),
        callConfirm: _flag(raw, '${k}_forward_call_confirm'),
      ),
  };

  int? get ringTimeout => int.tryParse(_s(raw, 'ring_timeout'));
  bool get ringMobile => _flag(raw, 'enb_ring_mobile');
  bool get mobileCallConfirm => _flag(raw, 'mobile_call_confirm');
  bool get acceptRingGroup => _flag(raw, 'enb_accept_call_from_rg');

  /// Messaggio di benvenuto della casella in questa presenza ('' = predefinito).
  String get greeting => _s(raw, 'vm_greeting');

  PresenceSetting withValues(Map<String, Object> changes) =>
      PresenceSetting({...raw, ...changes});

  PresenceSetting withForward(String cond, PresenceForward f) =>
      withValues(f.toJson(cond));
}

String _s(Map<String, dynamic> m, String k) => '${m[k] ?? ''}';

/// Valore con il tipo che il PBX ha usato per quel campo: `"0"` dove si
/// aspetta `0` dà errcode 40002 (verificato sul pilota).
Object _typed(Object v, Object? like) => switch (like) {
  int() => v is int ? v : int.tryParse('$v') ?? v,
  String() => '$v',
  _ => v,
};
bool _flag(Map<String, dynamic> m, String k) => _s(m, k) == '1';

/// Dettaglio del proprio interno (`extension/get`). Tiene la risposta del PBX
/// senza i segreti (password, PIN: [_secret]); le modifiche sono copie
/// ([withValues], [withPresence]) e [changesFrom] dà solo i campi utente
/// ammessi in scrittura ([YeastarApi.ownWritable]).
class PbxExtensionDetail {
  PbxExtensionDetail._(this._j);
  final Map<String, dynamic> _j;

  /// Campi che non si tengono nemmeno in memoria o in cache (`vm_pin`,
  /// `reg_password`…); restano gli interruttori `enb_…` (es. `enb_vm_pin`).
  static final _secret = RegExp(
    r'^(?!enb_).*(^|_)(pin|password|secret|token)$',
    caseSensitive: false,
  );

  static PbxExtensionDetail parse(Map<String, dynamic> j) =>
      PbxExtensionDetail._(_clean(j) as Map<String, dynamic>);

  static Object? _clean(Object? v) {
    if (v is Map) {
      return <String, dynamic>{
        for (final e in v.entries)
          if (!_secret.hasMatch('${e.key}')) '${e.key}': _clean(e.value),
      };
    }
    if (v is List) return [for (final x in v) _clean(x)];
    return v;
  }

  /// Forma letta da [parse] (cache su disco, cifrata).
  Map<String, dynamic> toJson() => _j;

  int? get id => int.tryParse(_s(_j, 'id'));
  String field(String k) => _s(_j, k);
  bool flag(String k) => _flag(_j, k);

  String get presence => field('presence_status');
  String get customPresence => field('custom_presence_status');

  List<PresenceSetting> get presences => [
    for (final p
        in (_j['presence_list'] as List? ?? const [])
            .whereType<Map<String, dynamic>>())
      PresenceSetting(p),
  ];

  PresenceSetting? settingOf(String status) =>
      presences.where((p) => p.status == status).firstOrNull;

  PbxExtensionDetail withValues(Map<String, Object> changes) =>
      PbxExtensionDetail._({..._j, ...changes});

  PbxExtensionDetail withPresence(String p) =>
      withValues({'presence_status': p});

  PbxExtensionDetail withSetting(PresenceSetting s) => PbxExtensionDetail._({
    ..._j,
    'presence_list': [
      for (final p in presences) p.status == s.status ? s.raw : p.raw,
    ],
  });

  /// Campi cambiati rispetto a [old], solo quelli scrivibili; per
  /// `presence_list` solo le presenze cambiate, con i loro campi scrivibili.
  Map<String, Object> changesFrom(PbxExtensionDetail old) {
    final out = <String, Object>{};
    for (final k in YeastarApi.ownWritable) {
      final v = _j[k];
      if (v != null && '$v' != '${old._j[k]}') out[k] = _typed(v, old._j[k]);
    }
    final list = <Map<String, Object>>[];
    for (final p in presences) {
      final before = old.settingOf(p.status)?.raw ?? const {};
      final writable = {
        for (final e in p.raw.entries)
          if (YeastarApi.presenceWritable(e.key) && e.value != null)
            e.key: _typed(e.value as Object, before[e.key]),
      };
      // Presenza cambiata: si manda intera (campi scrivibili), così il PBX
      // non deve completare un elemento parziale della lista.
      if (writable.entries.any((e) => '${e.value}' != '${before[e.key]}')) {
        list.add({'status': p.status, ...writable});
      }
    }
    if (list.isNotEmpty) out['presence_list'] = list;
    return out;
  }
}

/// Messaggio in casella vocale (vm/get).
class PbxVoicemail {
  const PbxVoicemail({
    required this.id,
    required this.callerName,
    required this.callerNumber,
    required this.time,
    required this.seconds,
    required this.read,
  });
  final String id;
  final String callerName;
  final String callerNumber;

  /// Formato del PBX, es. `2024/04/23 10:49:15`.
  final String time;
  final int seconds;
  final bool read;
}

class PbxOrg {
  const PbxOrg({
    required this.id,
    this.parentId = 0,
    required this.name,
    required this.depth,
    required this.extIds,
  });
  final int id;

  /// 0 = radice.
  final int parentId;
  final String name;
  final int depth;
  final Set<int> extIds;
}

class YeastarApi {
  YeastarApi(this._creds, {HttpClient? http}) : _http = http ?? HttpClient();

  final ApiCredentials _creds;
  final HttpClient _http;
  String? _accessToken;
  String? _refreshToken;
  Timer? _refreshTimer;
  static const userAgent = 'DrinPhone/0.1.0';
  static const _userAgent = userAgent;

  /// Chiamato a ogni nuovo token (rilascio o rinnovo): chi usa il WebSocket
  /// eventi si ricollega con il token nuovo.
  void Function()? onTokens;

  /// URL del WebSocket eventi (`wss://…/openapi/v1.0/subscribe?access_token=…`).
  /// Contiene il token: MAI nei log o nei messaggi d'errore.
  Uri eventsUri() {
    final base = Uri.parse(_creds.baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/openapi/v1.0/subscribe'.replaceAll('//', '/'),
      queryParameters: {'access_token': _accessToken ?? ''},
    );
  }

  Uri _uri(String endpoint, [Map<String, String> query = const {}]) {
    final base = Uri.parse(_creds.baseUrl);
    // get_token e refresh_token sono le uniche chiamate senza access_token.
    final withToken = endpoint != 'get_token' && endpoint != 'refresh_token';
    final params = {
      if (withToken) 'access_token': _accessToken ?? '',
      ...query,
    };
    return base.replace(
      path: '${base.path}/openapi/v1.0/$endpoint'.replaceAll('//', '/'),
      queryParameters: params.isEmpty ? null : params,
    );
  }

  Future<Map<String, dynamic>> _call(
    String op,
    String method,
    Uri uri, [
    Map<String, dynamic>? body,
  ]) async {
    final req = await _http
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 15));
    req.headers
      ..set(HttpHeaders.userAgentHeader, _userAgent)
      ..contentType = ContentType.json;
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close().timeout(const Duration(seconds: 15));
    final text = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw YeastarApiException(op, -res.statusCode, 'HTTP ${res.statusCode}');
    }
    final j = jsonDecode(text) as Map<String, dynamic>;
    final code = j['errcode'] as int? ?? -1;
    if (code != 0) {
      throw YeastarApiException(op, code, '${j['errmsg'] ?? ''}');
    }
    return j;
  }

  void _takeTokens(Map<String, dynamic> j) {
    _accessToken = j['access_token'] as String;
    _refreshToken = j['refresh_token'] as String;
    final ttl = j['access_token_expire_time'] as int? ?? 1800;
    _refreshTimer?.cancel();
    // Rinnovo 5 minuti prima della scadenza (30 min da specifica).
    _refreshTimer = Timer(
      Duration(seconds: ttl > 600 ? ttl - 300 : ttl ~/ 2),
      _refresh,
    );
    onTokens?.call();
  }

  bool get connected => _accessToken != null;

  Future<void> connect() async {
    final j = await _call('get_token', 'POST', _uri('get_token'), {
      'username': _creds.clientId,
      'password': _creds.clientSecret,
    });
    _takeTokens(j);
  }

  Future<void> _refresh() async {
    try {
      final j = await _call('refresh_token', 'POST', _uri('refresh_token'), {
        'refresh_token': _refreshToken,
      });
      _takeTokens(j);
    } on Object {
      // Refresh scaduto o rifiutato: un solo nuovo get_token, niente loop
      // (limite 8 token per app e blocco IP sui fallimenti). Se fallisce anche
      // quello, il token resta assente e la prossima sincronizzazione riprova.
      _accessToken = null;
      try {
        await connect();
      } on Object {
        _refreshToken = null;
      }
    }
  }

  Future<List<PbxExtension>> listExtensions() async {
    final out = <PbxExtension>[];
    for (var page = 1; ; page++) {
      final j = await _call(
        'extension/list',
        'GET',
        _uri('extension/list', {
          'page': '$page',
          'page_size': '100',
          'sort_by': 'number',
          'order_by': 'asc',
        }),
      );
      final data = (j['data'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final e in data) {
        out.add(
          PbxExtension(
            id: (e['id'] as num?)?.toInt() ?? 0,
            number: '${e['number'] ?? ''}',
            name: '${e['caller_id_name'] ?? ''}',
            email: '${e['email_addr'] ?? ''}',
            mobile: '${e['mobile_number'] ?? ''}',
            presence: '${e['presence_status'] ?? ''}',
          ),
        );
      }
      final total = j['total_number'] as int? ?? out.length;
      if (data.isEmpty || out.length >= total) return out;
    }
  }

  /// Reparti del PBX, appiattiti in ordine di albero (`depth` = livello).
  /// `extIds` di un reparto comprende anche gli interni dei sotto-reparti.
  Future<List<PbxOrg>> listOrganizations() async {
    final j = await _call(
      'organization/list',
      'GET',
      _uri('organization/list', {'is_all': '1'}),
    );
    final out = <PbxOrg>[];
    void walk(List<dynamic> nodes, int depth, int parent) {
      for (final n in nodes.cast<Map<String, dynamic>>()) {
        final id = (n['id'] as num?)?.toInt() ?? 0;
        out.add(
          PbxOrg(
            id: id,
            parentId: parent,
            name: '${n['name'] ?? ''}',
            depth: depth,
            extIds: {
              for (final x in (n['ext_list'] as List? ?? const []))
                (x as num).toInt(),
            },
          ),
        );
        walk(n['children'] as List? ?? const [], depth + 1, id);
      }
    }

    walk(j['organization_list'] as List? ?? const [], 0, 0);
    return out;
  }

  /// Campi numero di Contact_Info con l'etichetta mostrata (fax esclusi).
  static const _contactNumberFields = {
    'business': 'Ufficio',
    'business2': 'Ufficio 2',
    'mobile': 'Cellulare',
    'mobile2': 'Cellulare 2',
    'home': 'Casa',
    'home2': 'Casa 2',
    'other': 'Altro',
  };

  Future<List<PbxContact>> listCompanyContacts() async {
    final out = <PbxContact>[];
    for (var page = 1; ; page++) {
      final j = await _call(
        'company_contact/list',
        'GET',
        _uri('company_contact/list', {
          'page': '$page',
          'page_size': '500',
          'sort_by': 'contact_name',
          'order_by': 'asc',
        }),
      );
      final data = (j['data'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final c in data) {
        out.add(
          PbxContact(
            id: (c['id'] as num?)?.toInt() ?? 0,
            name: '${c['contact_name'] ?? ''}',
            company: '${c['company'] ?? ''}',
            jobTitle: '${c['job_title'] ?? ''}',
            email: '${c['email'] ?? ''}',
            numbers: [
              for (final f in _contactNumberFields.entries)
                if ('${c[f.key] ?? ''}'.trim().isNotEmpty)
                  (f.value, '${c[f.key]}'.trim()),
            ],
            phonebooks: [
              for (final b in (c['phonebook_list'] as List? ?? const []))
                '${(b as Map<String, dynamic>)['name'] ?? ''}',
            ],
          ),
        );
      }
      final total = j['total_number'] as int? ?? out.length;
      if (data.isEmpty || out.length >= total) return out;
    }
  }

  /// Chiamate in corso di un tipo (`inbound`, `outbound`, `internal`):
  /// call_id -> membri. Fotografia iniziale; poi aggiornano gli eventi 30011.
  Future<Map<String, List<LiveMember>>> queryCalls(String type) async {
    final j = await _call(
      'call/query',
      'GET',
      _uri('call/query', {'type': type}),
    );
    return {
      for (final c
          in (j['data'] as List? ?? const []).whereType<Map<String, dynamic>>())
        '${c['call_id']}': LiveMember.parse(c['members'] as List? ?? const []),
    };
  }

  /// Codice funzione di registrazione (`auto_record`, pausa/ripresa e
  /// registrazione a richiesta) se abilitato; null se disattivato.
  Future<String?> recordFeatureCode() async {
    final j = await _call(
      'feature_code/get',
      'GET',
      _uri('feature_code/get', const {}),
    );
    final f = j['feature_code'];
    if (f is! Map<String, dynamic>) return null;
    final code = '${f['auto_record'] ?? ''}';
    return '${f['enb_auto_record']}' == '1' && code.isNotEmpty ? code : null;
  }

  /// Dettaglio di un interno (presenze, inoltri, squillo, casella vocale).
  Future<PbxExtensionDetail> getExtension(int id) async {
    final j = await _call(
      'extension/get',
      'GET',
      _uri('extension/get', {'id': '$id'}),
    );
    final d = j['data'];
    return PbxExtensionDetail.parse(d is Map<String, dynamic> ? d : j);
  }

  /// Campi dell'interno che DrinPhone può cambiare, solo sul **proprio**
  /// interno (DECISIONS "Scrittura sul proprio interno"): impostazioni da
  /// utente come in Linkus. Tutto il resto (password, PIN, trasporto, permessi
  /// di uscita, ruolo, Linkus, DOD…) resta solo in lettura.
  static const ownWritable = {
    'presence_status',
    'presence_office_time_switch',
    'presence_break_time_switch',
    'presence_holiday_switch',
    'presence_other_time_switch',
    'enb_vm',
    'enb_vm_pin',
    'new_vm_notification',
    'vm_after_notification',
    'enb_vm_play_datetime',
    'vm_new_email_notify',
    'vm_email_with_audio',
    'vm_play_time_format',
    'vm_greeting',
    'vm_lang',
    'user_lang',
    'enb_all_busy_mode_for_endpoints',
    'enb_all_reject_mode_for_endpoints',
  };

  static final _presenceField = RegExp(
    r'^(status|ring_timeout|enb_ring_mobile|mobile_call_confirm|'
    r'enb_accept_call_from_rg|vm_greeting|'
    r'enb_(in|ex)_(always|no_answer|busy)_forward|'
    r'(in|ex)_(always|no_answer|busy)_forward_(dest|value|num|prefix|call_confirm))$',
  );

  /// Campo di un elemento di `presence_list` scrivibile.
  static bool presenceWritable(String k) => _presenceField.hasMatch(k);

  /// `extension/update` sul proprio interno [id] con i soli campi ammessi;
  /// qualunque altro campo è un errore di programmazione e non parte.
  Future<void> updateOwnExtension(int id, Map<String, Object> changes) async {
    for (final e in changes.entries) {
      if (e.key == 'presence_list') {
        for (final item in e.value as List) {
          final bad = (item as Map).keys.where((k) => !presenceWritable('$k'));
          if (bad.isNotEmpty) throw ArgumentError('campo non ammesso: $bad');
        }
      } else if (!ownWritable.contains(e.key)) {
        throw ArgumentError('campo non ammesso: ${e.key}');
      }
    }
    if (changes.isEmpty) return;
    await _call('extension/update', 'POST', _uri('extension/update'), {
      'id': id,
      ...changes,
    });
  }

  /// Messaggi della casella vocale di un interno (più recenti per primi).
  Future<List<PbxVoicemail>> listVoicemail(String number) async {
    final j = await _call(
      'vm/get',
      'GET',
      _uri('vm/get', {'number': number, 'page': '1', 'page_size': '200'}),
    );
    return [
      for (final m
          in (j['data'] as List? ?? const []).cast<Map<String, dynamic>>())
        PbxVoicemail(
          id: '${m['msg_id'] ?? ''}',
          callerName: '${m['name'] ?? ''}',
          callerNumber: '${m['number'] ?? ''}',
          time: '${m['time'] ?? ''}',
          seconds: (m['duration'] as num?)?.toInt() ?? 0,
          read: m['is_read'] == 1,
        ),
    ]..sort((a, b) => b.time.compareTo(a.time));
  }

  /// Revoca il token: alla chiusura, per non consumare uno degli 8 slot.
  Future<void> close() async {
    _refreshTimer?.cancel();
    if (_accessToken != null) {
      try {
        await _call('del_token', 'GET', _uri('del_token'));
      } on Object {
        // Scadrà comunque entro 30 minuti.
      }
    }
    _accessToken = null;
    _refreshToken = null;
    _http.close(force: true);
  }
}
