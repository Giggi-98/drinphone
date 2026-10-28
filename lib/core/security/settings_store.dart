import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../sip/sip_engine.dart';

class Extension {
  const Extension(this.name, this.number, {this.source = ''});
  final String name;
  final String number;

  /// '' = inserito a mano; altrimenti l'id della connessione PBX da cui arriva.
  /// Solo gli interni manuali vengono salvati.
  final String source;

  Map<String, String> toJson() => {'name': name, 'number': number};
  static Extension fromJson(Map<String, dynamic> j) =>
      Extension(j['name'] as String? ?? '', j['number'] as String? ?? '');
}

/// Connessione API a un PBX: solo dati non segreti. Le credenziali stanno nel
/// file DPAPI della connessione (ApiCredentialStore).
class PbxConnectionInfo {
  const PbxConnectionInfo(this.id, this.label, {this.realtime = false});
  final String id;
  final String label;

  /// Eventi in tempo reale via WebSocket (richiede i monitor attivi sul PBX).
  final bool realtime;
}

class Settings {
  const Settings({
    this.accounts = const [],
    this.debugLog = false,
    this.extensions = const [],
    this.pbx = const [],
    this.lang = 'it',
    this.voicemailCode = '*2',
    this.favorites = const [],
  });

  /// Account SIP; il primo è il principale (predefinito per le chiamate).
  final List<SipAccount> accounts;
  SipAccount? get account => accounts.firstOrNull;
  final bool debugLog;
  final List<Extension> extensions;
  final List<PbxConnectionInfo> pbx;

  /// Codice lingua dell'interfaccia (`it`, `en`).
  final String lang;

  /// Codice funzione per ascoltare la casella vocale. `*2` è il default di
  /// Yeastar P-Series: configurabile, non universale (docs/sip-e-blf.md).
  final String voicemailCode;

  /// Interni preferiti: `<connessione>:<numero>`, connessione vuota per il PBX
  /// dell'account SIP e per gli interni inseriti a mano.
  final List<String> favorites;

  Settings copyWith({
    List<SipAccount>? accounts,
    bool? debugLog,
    List<Extension>? extensions,
    List<PbxConnectionInfo>? pbx,
    String? lang,
    String? voicemailCode,
    List<String>? favorites,
  }) => Settings(
    accounts: accounts ?? this.accounts,
    debugLog: debugLog ?? this.debugLog,
    extensions: extensions ?? this.extensions,
    pbx: pbx ?? this.pbx,
    lang: lang ?? this.lang,
    voicemailCode: voicemailCode ?? this.voicemailCode,
    favorites: favorites ?? this.favorites,
  );
}

/// Impostazioni in chiaro su file JSON; la password SIP SOLO nello storage
/// sicuro della piattaforma (flutter_secure_storage), mai nel JSON né nei log.
class SettingsStore {
  SettingsStore(this.path, {FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  final String path;
  final FlutterSecureStorage _secure;
  // `main` mantiene la chiave della versione a account singolo.
  static String _passwordKey(String id) =>
      id == 'main' ? 'sip_password' : 'sip_password_$id';
  static const _idsKey = 'sip_password_ids';

  Future<SipAccount> _accountFrom(Map<String, dynamic> a, String id) async =>
      SipAccount(
        id: id,
        pbxId: a['pbxId'] as String? ?? '',
        username: a['username'] as String,
        password: await _secure.read(key: _passwordKey(id)) ?? '',
        domain: a['domain'] as String,
        transport: SipTransport.values.byName(
          a['transport'] as String? ?? 'udp',
        ),
        displayName: a['displayName'] as String? ?? '',
      );

  Future<Settings> load() async {
    final file = File(path);
    if (!await file.exists()) return const Settings();
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final accounts = <SipAccount>[
      for (final a in (j['accounts'] as List? ?? const []))
        await _accountFrom(
          a as Map<String, dynamic>,
          a['id'] as String? ?? 'main',
        ),
    ];
    // Versione a account singolo: campo `account`.
    final legacy = j['account'] as Map<String, dynamic>?;
    if (accounts.isEmpty && legacy != null) {
      accounts.add(await _accountFrom(legacy, 'main'));
    }
    return Settings(
      accounts: accounts,
      debugLog: j['debugLog'] as bool? ?? false,
      extensions: [
        for (final e in (j['extensions'] as List? ?? const []))
          Extension.fromJson(e as Map<String, dynamic>),
      ],
      lang: j['lang'] as String? ?? 'it',
      voicemailCode: j['voicemailCode'] as String? ?? '*2',
      favorites: [for (final f in (j['favorites'] as List? ?? const [])) '$f'],
      pbx: [
        for (final c in (j['pbx'] as List? ?? const []))
          PbxConnectionInfo(
            (c as Map<String, dynamic>)['id'] as String,
            c['label'] as String? ?? 'PBX',
            realtime: c['realtime'] as bool? ?? false,
          ),
      ],
    );
  }

  Future<void> save(Settings s) async {
    // Password nello storage sicuro; quelle di account rimossi vengono cancellate.
    final ids = {for (final a in s.accounts) a.id};
    final previous = (await _secure.read(key: _idsKey) ?? '')
        .split(',')
        .where((x) => x.isNotEmpty);
    for (final old in previous) {
      if (!ids.contains(old)) await _secure.delete(key: _passwordKey(old));
    }
    if (s.accounts.isEmpty) await _secure.delete(key: _passwordKey('main'));
    for (final a in s.accounts) {
      await _secure.write(key: _passwordKey(a.id), value: a.password);
    }
    await _secure.write(key: _idsKey, value: ids.join(','));
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'accounts': [
          for (final a in s.accounts)
            {
              'id': a.id,
              'pbxId': a.pbxId,
              'username': a.username,
              'domain': a.domain,
              'transport': a.transport.name,
              'displayName': a.displayName,
            },
        ],
        'debugLog': s.debugLog,
        'extensions': [for (final e in s.extensions) e.toJson()],
        'lang': s.lang,
        'voicemailCode': s.voicemailCode,
        'favorites': s.favorites,
        'pbx': [
          for (final c in s.pbx)
            {'id': c.id, 'label': c.label, 'realtime': c.realtime},
        ],
      }),
    );
  }
}
