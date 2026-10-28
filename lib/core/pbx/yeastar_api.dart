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
  static const _userAgent = 'DrinPhone/0.1.0';

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
