// Credenziali "Database Grant" di Yeastar P-Series (MySQL, porta 3306) per
// leggere il CDR. Come le credenziali API: le inserisce l'amministratore,
// cifrate con DPAPI, mai mostrate né nei log (DECISIONS 2026-10-30 "CDR dal
// database del PBX").
import 'dart:convert';

import 'api_credential_store.dart' show DpapiBox;

class CdrDbCredentials {
  const CdrDbCredentials({
    required this.host,
    required this.user,
    required this.password,
    this.port = 3306,
    this.secure = true,
    this.wholePbx = false,
  });

  final String host;
  final int port;
  final String user;
  final String password;

  /// TLS verso il database (cifra, ma la libreria non verifica il
  /// certificato: usare in LAN/VPN con gli IP consentiti sul PBX).
  final bool secure;

  /// L'amministratore permette a questo utente il CDR di tutto il PBX; se no
  /// solo le chiamate del proprio interno.
  final bool wholePbx;

  // Mai stampare utente o password.
  @override
  String toString() => 'CdrDbCredentials($host:$port)';
}

class CdrDbStore {
  CdrDbStore(String path) : _box = DpapiBox(path);
  final DpapiBox _box;

  bool get isSet => _box.exists;

  Future<void> save(CdrDbCredentials c) => _box.write(
    jsonEncode({
      'host': c.host,
      'port': c.port,
      'user': c.user,
      'password': c.password,
      'secure': c.secure,
      'wholePbx': c.wholePbx,
    }),
  );

  /// Null se assenti o non decifrabili da questo utente/PC/app.
  Future<CdrDbCredentials?> load() async {
    final plain = await _box.read();
    if (plain == null) return null;
    try {
      final m = jsonDecode(plain) as Map<String, dynamic>;
      return CdrDbCredentials(
        host: m['host'] as String,
        port: m['port'] as int? ?? 3306,
        user: m['user'] as String,
        password: m['password'] as String,
        secure: m['secure'] as bool? ?? true,
        wholePbx: m['wholePbx'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _box.clear();
}
