import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../contacts/personal_contacts.dart';
import '../sip/sip_engine.dart';
import 'api_credential_store.dart';
import 'cdr_db_store.dart';
import 'settings_store.dart';

/// Connessione PBX esportabile (opzionalmente con credenziali API e CDR).
class ExportedPbxConnection {
  const ExportedPbxConnection({
    required this.oldId,
    required this.label,
    this.realtime = false,
    this.sync = const {},
    this.apiCreds,
    this.cdrCreds,
  });

  final String oldId;
  final String label;
  final bool realtime;
  final Map<String, int> sync;
  final ApiCredentials? apiCreds;
  final CdrDbCredentials? cdrCreds;

  @override
  String toString() => 'ExportedPbxConnection($label)';
}

/// Dati completi di un profilo pronti per essere cifrati in `.drinprof`.
class ProfileBundle {
  const ProfileBundle({
    required this.name,
    required this.kind,
    this.accounts = const [],
    this.extensions = const [],
    this.pbx = const [],
    this.voicemailCode = '*2',
    this.favorites = const [],
    this.personalContacts = const [],
    this.crmUrlTemplate = '',
  });

  final String name;
  final ProfileKind kind;
  final List<SipAccount> accounts;
  final List<Extension> extensions;
  final List<ExportedPbxConnection> pbx;
  final String voicemailCode;
  final List<String> favorites;
  final List<PersonalContact> personalContacts;
  final String crmUrlTemplate;

  @override
  String toString() =>
      'ProfileBundle($name, kind: ${kind.name}, accounts: ${accounts.length}, pbx: ${pbx.length})';

  Map<String, Object?> toJson() => {
    'v': 1,
    'name': name,
    'kind': kind.name,
    'voicemailCode': voicemailCode,
    'favorites': favorites,
    'crmUrlTemplate': crmUrlTemplate,
    'extensions': [for (final e in extensions) e.toJson()],
    'accounts': [
      for (final a in accounts)
        {
          'pbxId': a.pbxId,
          'username': a.username,
          'password': a.password,
          'domain': a.domain,
          'transport': a.transport.name,
          'displayName': a.displayName,
          'proxy': a.proxy,
          'registrar': a.registrar,
          'authUser': a.authUser,
          'realm': a.realm,
          'expires': a.expires,
          'registerEnabled': a.registerEnabled,
          'hideCallerId': a.hideCallerId,
          'voicemailCode': a.voicemailCode,
          'stunServer': a.stunServer,
          'ice': a.ice,
          'turn': a.turn,
          'turnUser': a.turnUser,
          'turnPassword': a.turnPassword,
          'recording': a.recording.name,
          'recordCode': a.recordCode,
        },
    ],
    'pbx': [
      for (final c in pbx)
        {
          'oldId': c.oldId,
          'label': c.label,
          'realtime': c.realtime,
          'sync': c.sync,
          if (c.apiCreds != null)
            'api': {
              'baseUrl': c.apiCreds!.baseUrl,
              'clientId': c.apiCreds!.clientId,
              'clientSecret': c.apiCreds!.clientSecret,
              'ownExtension': c.apiCreds!.ownExtension,
            },
          if (c.cdrCreds != null)
            'cdr': {
              'host': c.cdrCreds!.host,
              'port': c.cdrCreds!.port,
              'user': c.cdrCreds!.user,
              'password': c.cdrCreds!.password,
              'secure': c.cdrCreds!.secure,
              'wholePbx': c.cdrCreds!.wholePbx,
            },
        },
    ],
    'personal': [for (final p in personalContacts) p.toJson()],
  };

  static ProfileBundle fromJson(Map<String, dynamic> j) {
    final kind =
        ProfileKind.values.asNameMap()[j['kind']] ?? ProfileKind.yeastar;
    return ProfileBundle(
      name: '${j['name'] ?? ''}',
      kind: kind,
      voicemailCode: '${j['voicemailCode'] ?? '*2'}',
      crmUrlTemplate: '${j['crmUrlTemplate'] ?? ''}',
      favorites: [for (final f in (j['favorites'] as List? ?? const [])) '$f'],
      extensions: [
        for (final e in (j['extensions'] as List? ?? const []))
          if (e is Map<String, dynamic>) Extension.fromJson(e),
      ],
      accounts: [
        for (final raw in (j['accounts'] as List? ?? const []))
          if (raw is Map<String, dynamic>)
            SipAccount(
              id: 'main',
              pbxId: '${raw['pbxId'] ?? ''}',
              username: '${raw['username'] ?? ''}',
              password: '${raw['password'] ?? ''}',
              domain: '${raw['domain'] ?? ''}',
              transport:
                  SipTransport.values.asNameMap()[raw['transport']] ??
                  SipTransport.udp,
              displayName: '${raw['displayName'] ?? ''}',
              proxy: '${raw['proxy'] ?? ''}',
              registrar: '${raw['registrar'] ?? ''}',
              authUser: '${raw['authUser'] ?? ''}',
              realm: '${raw['realm'] ?? ''}',
              expires: (raw['expires'] as num?)?.toInt() ?? 0,
              registerEnabled: raw['registerEnabled'] as bool? ?? true,
              hideCallerId: raw['hideCallerId'] as bool? ?? false,
              voicemailCode: '${raw['voicemailCode'] ?? ''}',
              stunServer: '${raw['stunServer'] ?? ''}',
              ice: raw['ice'] as bool? ?? false,
              turn: raw['turn'] as bool? ?? false,
              turnUser: '${raw['turnUser'] ?? ''}',
              turnPassword: '${raw['turnPassword'] ?? ''}',
              recording:
                  RecordingMode.values.asNameMap()[raw['recording']] ??
                  RecordingMode.auto,
              recordCode: '${raw['recordCode'] ?? ''}',
            ),
      ],
      pbx: [
        for (final raw in (j['pbx'] as List? ?? const []))
          if (raw is Map<String, dynamic>) _pbxFromJson(raw),
      ],
      personalContacts: [
        for (final p in (j['personal'] as List? ?? const []))
          if (p is Map<String, dynamic>) PersonalContact.fromJson(p),
      ],
    );
  }

  static ExportedPbxConnection _pbxFromJson(Map<String, dynamic> j) {
    final apiMap = j['api'] as Map<String, dynamic>?;
    final cdrMap = j['cdr'] as Map<String, dynamic>?;
    return ExportedPbxConnection(
      oldId: '${j['oldId'] ?? ''}',
      label: '${j['label'] ?? 'PBX'}',
      realtime: j['realtime'] as bool? ?? false,
      sync: {
        for (final e in (j['sync'] as Map? ?? const {}).entries)
          if (e.value is int) '${e.key}': e.value as int,
      },
      apiCreds: apiMap == null
          ? null
          : ApiCredentials(
              baseUrl: '${apiMap['baseUrl'] ?? ''}',
              clientId: '${apiMap['clientId'] ?? ''}',
              clientSecret: '${apiMap['clientSecret'] ?? ''}',
              ownExtension: '${apiMap['ownExtension'] ?? ''}',
            ),
      cdrCreds: cdrMap == null
          ? null
          : CdrDbCredentials(
              host: '${cdrMap['host'] ?? ''}',
              port: (cdrMap['port'] as num?)?.toInt() ?? 3306,
              user: '${cdrMap['user'] ?? ''}',
              password: '${cdrMap['password'] ?? ''}',
              secure: cdrMap['secure'] as bool? ?? true,
              wholePbx: cdrMap['wholePbx'] as bool? ?? false,
            ),
    );
  }
}

/// Cifratura e decifratura AEAD (PBKDF2-HMAC-SHA256 + AES-256-GCM) del file
/// portabile `.drinprof`.
abstract final class ProfileBundleCodec {
  static const format = 'drinprof-v1';
  static const minPassphraseLength = 8;
  static const defaultIterations = 120000;

  static Future<String> seal(
    ProfileBundle bundle,
    String passphrase, {
    int iterations = defaultIterations,
  }) async {
    if (passphrase.length < minPassphraseLength) {
      throw ArgumentError(
        'La passphrase deve contenere almeno $minPassphraseLength caratteri',
      );
    }
    final rng = Random.secure();
    final salt = [for (var i = 0; i < 16; i++) rng.nextInt(256)];
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final key = await kdf.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    final cipher = AesGcm.with256bits();
    final box = await cipher.encrypt(
      utf8.encode(jsonEncode(bundle.toJson())),
      secretKey: key,
    );
    return jsonEncode({
      'format': format,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  static Future<ProfileBundle> open(String raw, String passphrase) async {
    if (passphrase.isEmpty) {
      throw const FormatException('Passphrase mancante');
    }
    final Map<String, dynamic> env;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Formato file .drinprof non valido');
      }
      env = decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Formato file .drinprof non valido');
    }
    if (env['format'] != format) {
      throw const FormatException('Formato file .drinprof non supportato');
    }
    final iterations = (env['iterations'] as num?)?.toInt() ?? 0;
    if (iterations < 10000 || iterations > 1000000) {
      throw const FormatException('Parametri di cifratura non validi');
    }
    try {
      final salt = base64Decode(env['salt'] as String);
      final nonce = base64Decode(env['nonce'] as String);
      final cipherText = base64Decode(env['ciphertext'] as String);
      final mac = Mac(base64Decode(env['mac'] as String));
      final kdf = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      );
      final key = await kdf.deriveKeyFromPassword(
        password: passphrase,
        nonce: salt,
      );
      final cipher = AesGcm.with256bits();
      final clear = await cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: key,
      );
      final payload = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      return ProfileBundle.fromJson(payload);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Passphrase errata o file manomesso');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Impossibile leggere il file .drinprof');
    }
  }
}

