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

/// Tipo di profilo (DECISIONS "Profili"): decide quali sezioni si vedono.
enum ProfileKind { yeastar, sip }

/// Profilo non attivo: stessi dati per-profilo di [Settings], fermi su disco.
class Profile {
  const Profile({
    required this.id,
    this.name = '',
    this.kind = ProfileKind.yeastar,
    this.accounts = const [],
    this.extensions = const [],
    this.pbx = const [],
    this.voicemailCode = '*2',
    this.favorites = const [],
    this.callWith = '',
    this.seenMissedAt = '',
    this.seenVoicemail = const [],
  });
  final String id;
  final String name;
  final ProfileKind kind;
  final List<SipAccount> accounts;
  final List<Extension> extensions;
  final List<PbxConnectionInfo> pbx;
  final String voicemailCode;
  final List<String> favorites;
  final String callWith;
  final String seenMissedAt;
  final List<String> seenVoicemail;
}

/// Impostazioni: i campi per-profilo descrivono il **profilo attivo**
/// ([profileId]); gli altri profili stanno in [others]. Lingua, audio e
/// diagnostica sono globali.
class Settings {
  const Settings({
    this.profileId = defaultProfileId,
    this.profileName = '',
    this.profileKind = ProfileKind.yeastar,
    this.others = const [],
    this.accounts = const [],
    this.debugLog = false,
    this.extensions = const [],
    this.pbx = const [],
    this.lang = 'it',
    this.voicemailCode = '*2',
    this.favorites = const [],
    this.audio = const ('', '', ''),
    this.callWith = '',
    this.callOptions = const CallOptions(),
    this.video = const VideoOptions(),
    this.seenMissedAt = '',
    this.seenVoicemail = const [],
  });

  /// Id del profilo nato dalla configurazione senza profili (file storici).
  static const defaultProfileId = 'default';

  final String profileId;
  final String profileName;
  final ProfileKind profileKind;

  /// Profili non attivi.
  final List<Profile> others;

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

  /// Dispositivi audio scelti (microfono, altoparlante, suoneria); '' = predefinito.
  final (String, String, String) audio;

  /// Account SIP per le chiamate a numeri liberi ("Chiama con"); '' = principale.
  final String callWith;

  /// Globale: cifratura media, keep-alive, DTMF (Preferenze > Avanzate).
  final CallOptions callOptions;

  /// Globale: videochiamate, webcam, anteprima (Preferenze > Video).
  final VideoOptions video;

  /// Badge del profilo: ultima visita al registro chiamate (ISO 8601, '' = mai)
  /// e messaggi vocali già visti (id del PBX; `mwi:<n>` per il solo conteggio SIP).
  final String seenMissedAt;
  final List<String> seenVoicemail;

  /// Il profilo attivo come [Profile].
  Profile get active => Profile(
    id: profileId,
    name: profileName,
    kind: profileKind,
    accounts: accounts,
    extensions: extensions,
    pbx: pbx,
    voicemailCode: voicemailCode,
    favorites: favorites,
    callWith: callWith,
    seenMissedAt: seenMissedAt,
    seenVoicemail: seenVoicemail,
  );

  /// Tutti i profili, per nome.
  List<Profile> get profiles =>
      [active, ...others]..sort((a, b) => a.name.compareTo(b.name));

  /// Account di tutti i profili (id univoci, password da conservare).
  List<SipAccount> get allAccounts => [
    ...accounts,
    for (final p in others) ...p.accounts,
  ];

  /// Rende attivo il profilo [id]; quello attivo torna tra gli altri.
  Settings switchTo(String id) {
    if (id == profileId) return this;
    final t = others.firstWhere((p) => p.id == id);
    return Settings(
      profileId: t.id,
      profileName: t.name,
      profileKind: t.kind,
      others: [
        for (final p in others)
          if (p.id != id) p,
        active,
      ],
      accounts: t.accounts,
      debugLog: debugLog,
      extensions: t.extensions,
      pbx: t.pbx,
      lang: lang,
      voicemailCode: t.voicemailCode,
      favorites: t.favorites,
      audio: audio,
      callWith: t.callWith,
      callOptions: callOptions,
      video: video,
      seenMissedAt: t.seenMissedAt,
      seenVoicemail: t.seenVoicemail,
    );
  }

  Settings copyWith({
    String? profileName,
    ProfileKind? profileKind,
    List<Profile>? others,
    List<SipAccount>? accounts,
    bool? debugLog,
    List<Extension>? extensions,
    List<PbxConnectionInfo>? pbx,
    String? lang,
    String? voicemailCode,
    List<String>? favorites,
    (String, String, String)? audio,
    String? callWith,
    CallOptions? callOptions,
    VideoOptions? video,
    String? seenMissedAt,
    List<String>? seenVoicemail,
  }) => Settings(
    profileId: profileId,
    profileName: profileName ?? this.profileName,
    profileKind: profileKind ?? this.profileKind,
    others: others ?? this.others,
    accounts: accounts ?? this.accounts,
    debugLog: debugLog ?? this.debugLog,
    extensions: extensions ?? this.extensions,
    pbx: pbx ?? this.pbx,
    lang: lang ?? this.lang,
    voicemailCode: voicemailCode ?? this.voicemailCode,
    favorites: favorites ?? this.favorites,
    audio: audio ?? this.audio,
    callWith: callWith ?? this.callWith,
    callOptions: callOptions ?? this.callOptions,
    video: video ?? this.video,
    seenMissedAt: seenMissedAt ?? this.seenMissedAt,
    seenVoicemail: seenVoicemail ?? this.seenVoicemail,
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
  static String _turnKey(String id) => 'turn_password_$id';

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
        proxy: a['proxy'] as String? ?? '',
        registrar: a['registrar'] as String? ?? '',
        authUser: a['authUser'] as String? ?? '',
        realm: a['realm'] as String? ?? '',
        expires: a['expires'] as int? ?? 0,
        registerEnabled: a['registerEnabled'] as bool? ?? true,
        hideCallerId: a['hideCallerId'] as bool? ?? false,
        voicemailCode: a['voicemailCode'] as String? ?? '',
        stunServer: a['stunServer'] as String? ?? '',
        ice: a['ice'] as bool? ?? false,
        turn: a['turn'] as bool? ?? false,
        turnUser: a['turnUser'] as String? ?? '',
        turnPassword: a['turn'] == true
            ? await _secure.read(key: _turnKey(id)) ?? ''
            : '',
      );

  Future<Profile> _profileFrom(Map<String, dynamic> j, String id) async {
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
    final pbx = [
      for (final c in (j['pbx'] as List? ?? const []))
        PbxConnectionInfo(
          (c as Map<String, dynamic>)['id'] as String,
          c['label'] as String? ?? 'PBX',
          realtime: c['realtime'] as bool? ?? false,
        ),
    ];
    final kind = j['kind'] as String?;
    return Profile(
      id: id,
      // Senza profili: "Econnet" (installazioni pilota) se c'era l'integrazione
      // API, altrimenti il dominio del primo account.
      name:
          j['name'] as String? ??
          (pbx.isNotEmpty ? 'Econnet' : accounts.firstOrNull?.domain ?? ''),
      // Senza profili: Yeastar se c'era un'integrazione API, altrimenti generico.
      kind: kind != null
          ? ProfileKind.values.byName(kind)
          : (pbx.isEmpty && accounts.isNotEmpty
                ? ProfileKind.sip
                : ProfileKind.yeastar),
      accounts: accounts,
      extensions: [
        for (final e in (j['extensions'] as List? ?? const []))
          Extension.fromJson(e as Map<String, dynamic>),
      ],
      pbx: pbx,
      voicemailCode: j['voicemailCode'] as String? ?? '*2',
      favorites: [for (final f in (j['favorites'] as List? ?? const [])) '$f'],
      callWith: j['callWith'] as String? ?? '',
      seenMissedAt: j['seenMissedAt'] as String? ?? '',
      seenVoicemail: [
        for (final v in (j['seenVoicemail'] as List? ?? const [])) '$v',
      ],
    );
  }

  Future<Settings> load() async {
    final file = File(path);
    if (!await file.exists()) return const Settings();
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    // Senza `profiles`: file della versione a profilo unico, migrato al volo.
    final profiles = j['profiles'] is List
        ? [
            for (final p
                in (j['profiles'] as List).cast<Map<String, dynamic>>())
              await _profileFrom(p, p['id'] as String),
          ]
        : [await _profileFrom(j, Settings.defaultProfileId)];
    final activeId = j['activeProfile'] as String?;
    final active =
        profiles.where((p) => p.id == activeId).firstOrNull ??
        profiles.firstOrNull;
    return Settings(
      profileId: active?.id ?? Settings.defaultProfileId,
      profileName: active?.name ?? '',
      profileKind: active?.kind ?? ProfileKind.yeastar,
      others: [
        for (final p in profiles)
          if (p != active) p,
      ],
      accounts: active?.accounts ?? const [],
      debugLog: j['debugLog'] as bool? ?? false,
      extensions: active?.extensions ?? const [],
      lang: j['lang'] as String? ?? 'it',
      voicemailCode: active?.voicemailCode ?? '*2',
      favorites: active?.favorites ?? const [],
      callWith: active?.callWith ?? '',
      seenMissedAt: active?.seenMissedAt ?? '',
      seenVoicemail: active?.seenVoicemail ?? const [],
      audio: (
        j['audioCapture'] as String? ?? '',
        j['audioPlayback'] as String? ?? '',
        j['audioRinger'] as String? ?? '',
      ),
      pbx: active?.pbx ?? const [],
      callOptions: CallOptions(
        encryption:
            MediaEncryption.values.asNameMap()[j['mediaEncryption']] ??
            MediaEncryption.none,
        encryptionMandatory: j['encryptionMandatory'] as bool? ?? false,
        keepAlive: j['keepAlive'] as bool? ?? true,
        dtmfInfo: j['dtmfInfo'] as bool? ?? false,
      ),
      video: VideoOptions(
        enabled: j['videoEnabled'] as bool? ?? true,
        camera: j['videoCamera'] as String? ?? '',
        preview: j['videoPreview'] as bool? ?? false,
      ),
    );
  }

  static Map<String, Object> _profileJson(Profile p) => {
    'id': p.id,
    'name': p.name,
    'kind': p.kind.name,
    'accounts': [
      for (final a in p.accounts)
        {
          'id': a.id,
          'pbxId': a.pbxId,
          'username': a.username,
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
        },
    ],
    'extensions': [for (final e in p.extensions) e.toJson()],
    'voicemailCode': p.voicemailCode,
    'favorites': p.favorites,
    'callWith': p.callWith,
    'seenMissedAt': p.seenMissedAt,
    'seenVoicemail': p.seenVoicemail,
    'pbx': [
      for (final c in p.pbx)
        {'id': c.id, 'label': c.label, 'realtime': c.realtime},
    ],
  };

  Future<void> save(Settings s) async {
    // Password nello storage sicuro, per gli account di **tutti** i profili;
    // quelle di account rimossi vengono cancellate.
    final all = s.allAccounts;
    final ids = {for (final a in all) a.id};
    final previous = (await _secure.read(key: _idsKey) ?? '')
        .split(',')
        .where((x) => x.isNotEmpty);
    for (final old in previous) {
      if (!ids.contains(old)) {
        await _secure.delete(key: _passwordKey(old));
        await _secure.delete(key: _turnKey(old));
      }
    }
    if (!ids.contains('main')) await _secure.delete(key: _passwordKey('main'));
    for (final a in all) {
      await _secure.write(key: _passwordKey(a.id), value: a.password);
      a.turn && a.turnPassword.isNotEmpty
          ? await _secure.write(key: _turnKey(a.id), value: a.turnPassword)
          : await _secure.delete(key: _turnKey(a.id));
    }
    await _secure.write(key: _idsKey, value: ids.join(','));
    final file = File(path);
    await file.parent.create(recursive: true);
    // Prima riscrittura nel formato a profili: copia del file vecchio, che una
    // versione precedente dell'app saprebbe ancora leggere.
    if (await file.exists() &&
        !(await file.readAsString()).contains('"profiles"')) {
      await file.copy(path.replaceFirst(RegExp(r'\.json$'), '.v1.json'));
    }
    await file.writeAsString(
      jsonEncode({
        'activeProfile': s.profileId,
        'profiles': [for (final p in s.profiles) _profileJson(p)],
        'debugLog': s.debugLog,
        'lang': s.lang,
        'audioCapture': s.audio.$1,
        'audioPlayback': s.audio.$2,
        'audioRinger': s.audio.$3,
        'mediaEncryption': s.callOptions.encryption.name,
        'encryptionMandatory': s.callOptions.encryptionMandatory,
        'keepAlive': s.callOptions.keepAlive,
        'dtmfInfo': s.callOptions.dtmfInfo,
        'videoEnabled': s.video.enabled,
        'videoCamera': s.video.camera,
        'videoPreview': s.video.preview,
      }),
    );
  }
}
