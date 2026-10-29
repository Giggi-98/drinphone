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

/// Inoltro di una presenza (`extension/get` → `presence_list`).
class PresenceForward {
  const PresenceForward({
    required this.enabled,
    required this.dest,
    this.value = '',
    this.number = '',
  });
  final bool enabled;

  /// `extension`, `ext_vm`, `ivr`, `queue`, `ring_group`, `mobile_number`,
  /// `external_num`, `play_greeting`, `end_call`, `send_busy`…
  final String dest;

  /// Id della destinazione interna (o file del messaggio).
  final String value;

  /// Numero esterno per `external_num`.
  final String number;
}

/// Impostazioni di una presenza: inoltri per chiamate interne ed esterne.
class PresenceSetting {
  const PresenceSetting(this.status, this.forwards);
  final String status;

  /// Chiavi: `in_always`, `in_no_answer`, `in_busy`, `ex_always`,
  /// `ex_no_answer`, `ex_busy`.
  final Map<String, PresenceForward> forwards;

  static const conditions = [
    'in_always',
    'in_no_answer',
    'in_busy',
    'ex_always',
    'ex_no_answer',
    'ex_busy',
  ];
}

/// Dettaglio del proprio interno (`extension/get`), in sola lettura.
/// Il PIN della casella (`vm_pin`) arriva nella risposta ma non viene tenuto.
class PbxExtensionDetail {
  const PbxExtensionDetail({
    required this.presence,
    this.customPresence = '',
    this.presences = const [],
    this.ringTimeout,
    this.ringMobile = false,
    this.mobileNumber = '',
    this.acceptRingGroup = false,
    this.vmEnabled = false,
    this.vmPinAuth = false,
    this.vmNotification = '',
    this.vmAfterNotification = '',
    this.vmPlayDatetime = false,
    this.vmGreeting = '',
  });

  final String presence;
  final String customPresence;
  final List<PresenceSetting> presences;
  final int? ringTimeout;
  final bool ringMobile;
  final String mobileNumber;
  final bool acceptRingGroup;
  final bool vmEnabled;
  final bool vmPinAuth;
  final String vmNotification;
  final String vmAfterNotification;
  final bool vmPlayDatetime;
  final String vmGreeting;

  PresenceSetting? settingOf(String status) =>
      presences.where((p) => p.status == status).firstOrNull;

  PbxExtensionDetail withPresence(String p) => PbxExtensionDetail(
    presence: p,
    customPresence: customPresence,
    presences: presences,
    ringTimeout: ringTimeout,
    ringMobile: ringMobile,
    mobileNumber: mobileNumber,
    acceptRingGroup: acceptRingGroup,
    vmEnabled: vmEnabled,
    vmPinAuth: vmPinAuth,
    vmNotification: vmNotification,
    vmAfterNotification: vmAfterNotification,
    vmPlayDatetime: vmPlayDatetime,
    vmGreeting: vmGreeting,
  );

  /// Forma di `extension/get` letta da [parse] (cache su disco).
  Map<String, dynamic> toJson() {
    String flag(bool b) => b ? '1' : '0';
    return {
      'presence_status': presence,
      'custom_presence_status': customPresence,
      'presence_list': [
        for (final p in presences)
          {
            'status': p.status,
            for (final MapEntry(key: k, value: f) in p.forwards.entries) ...{
              'enb_${k}_forward': flag(f.enabled),
              '${k}_forward_dest': f.dest,
              '${k}_forward_value': f.value,
              '${k}_forward_num': f.number,
            },
          },
      ],
      'ring_timeout': ringTimeout ?? '',
      'enb_ring_mobile': flag(ringMobile),
      'mobile_number': mobileNumber,
      'enb_accept_call_from_rg': flag(acceptRingGroup),
      'enb_vm': flag(vmEnabled),
      'enb_vm_pin': flag(vmPinAuth),
      'new_vm_notification': vmNotification,
      'vm_after_notification': vmAfterNotification,
      'enb_vm_play_datetime': flag(vmPlayDatetime),
      'vm_greeting': vmGreeting,
    };
  }

  static PbxExtensionDetail parse(Map<String, dynamic> j) {
    String str(Map<String, dynamic> m, String k) => '${m[k] ?? ''}';
    bool flag(Map<String, dynamic> m, String k) => str(m, k) == '1';
    return PbxExtensionDetail(
      presence: str(j, 'presence_status'),
      customPresence: str(j, 'custom_presence_status'),
      presences: [
        for (final p
            in (j['presence_list'] as List? ?? const [])
                .whereType<Map<String, dynamic>>())
          PresenceSetting(str(p, 'status'), {
            for (final k in PresenceSetting.conditions)
              k: PresenceForward(
                enabled: flag(p, 'enb_${k}_forward'),
                dest: str(p, '${k}_forward_dest'),
                value: str(p, '${k}_forward_value'),
                number: str(p, '${k}_forward_num'),
              ),
          }),
      ],
      ringTimeout: int.tryParse(str(j, 'ring_timeout')),
      ringMobile: flag(j, 'enb_ring_mobile'),
      mobileNumber: str(j, 'mobile_number'),
      acceptRingGroup: flag(j, 'enb_accept_call_from_rg'),
      vmEnabled: flag(j, 'enb_vm'),
      vmPinAuth: flag(j, 'enb_vm_pin'),
      vmNotification: str(j, 'new_vm_notification'),
      vmAfterNotification: str(j, 'vm_after_notification'),
      vmPlayDatetime: flag(j, 'enb_vm_play_datetime'),
      vmGreeting: str(j, 'vm_greeting'),
    );
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
