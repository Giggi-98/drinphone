import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../sip/sip_engine.dart';

class Extension {
  const Extension(this.name, this.number);
  final String name;
  final String number;

  Map<String, String> toJson() => {'name': name, 'number': number};
  static Extension fromJson(Map<String, dynamic> j) =>
      Extension(j['name'] as String? ?? '', j['number'] as String? ?? '');
}

class Settings {
  const Settings({
    this.account,
    this.debugLog = false,
    this.extensions = const [],
  });
  final SipAccount? account;
  final bool debugLog;
  final List<Extension> extensions;
}

/// Impostazioni in chiaro su file JSON; la password SIP SOLO nello storage
/// sicuro della piattaforma (flutter_secure_storage), mai nel JSON né nei log.
class SettingsStore {
  SettingsStore(this.path, {FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  final String path;
  final FlutterSecureStorage _secure;
  static const _passwordKey = 'sip_password';

  Future<Settings> load() async {
    final file = File(path);
    if (!await file.exists()) return const Settings();
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final a = j['account'] as Map<String, dynamic>?;
    SipAccount? account;
    if (a != null) {
      account = SipAccount(
        username: a['username'] as String,
        password: await _secure.read(key: _passwordKey) ?? '',
        domain: a['domain'] as String,
        transport: SipTransport.values.byName(
          a['transport'] as String? ?? 'udp',
        ),
        displayName: a['displayName'] as String? ?? '',
      );
    }
    return Settings(
      account: account,
      debugLog: j['debugLog'] as bool? ?? false,
      extensions: [
        for (final e in (j['extensions'] as List? ?? const []))
          Extension.fromJson(e as Map<String, dynamic>),
      ],
    );
  }

  Future<void> save(Settings s) async {
    final a = s.account;
    if (a != null) {
      await _secure.write(key: _passwordKey, value: a.password);
    } else {
      await _secure.delete(key: _passwordKey);
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        if (a != null)
          'account': {
            'username': a.username,
            'domain': a.domain,
            'transport': a.transport.name,
            'displayName': a.displayName,
          },
        'debugLog': s.debugLog,
        'extensions': [for (final e in s.extensions) e.toJson()],
      }),
    );
  }
}
