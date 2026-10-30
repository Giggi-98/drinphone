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
  const PbxConnectionInfo(
    this.id,
    this.label, {
    this.realtime = false,
    this.sync = const {},
  });
  final String id;
  final String label;

  /// Eventi in tempo reale via WebSocket (richiede i monitor attivi sul PBX).
  final bool realtime;

  /// Frequenze scelte per [PbxSync] (nome → secondi, 0 = spenta); le voci
  /// assenti valgono il predefinito.
  final Map<String, int> sync;
}

/// Tipo di profilo (DECISIONS "Profili"): decide quali sezioni si vedono.
enum ProfileKind { yeastar, sip }

/// Account non attivo: stessi dati per-account di [Settings], fermi su disco.
///
/// Nell'interfaccia è un **account**: una sola registrazione SIP ([accounts]
/// ha al più un elemento) e al più una connessione API ([pbx]). Un account
/// vivo alla volta (DECISIONS "Un account vivo alla volta").
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
  final String seenMissedAt;
  final List<String> seenVoicemail;

  Profile renamed(String n) => Profile(
    id: id,
    name: n,
    kind: kind,
    accounts: accounts,
    extensions: extensions,
    pbx: pbx,
    voicemailCode: voicemailCode,
    favorites: favorites,
    seenMissedAt: seenMissedAt,
    seenVoicemail: seenVoicemail,
  );
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
    this.theme = 'system',
    this.voicemailCode = '*2',
    this.favorites = const [],
    this.audio = const ('', '', ''),
    this.callOptions = const CallOptions(),
    this.video = const VideoOptions(),
    this.seenMissedAt = '',
    this.seenVoicemail = const [],
    this.defaultProfile = '',
  });

  /// Id del profilo nato dalla configurazione senza profili (file storici).
  static const defaultProfileId = 'default';

  final String profileId;
  final String profileName;
  final ProfileKind profileKind;

  /// Profili non attivi.
  final List<Profile> others;

  /// Registrazione SIP dell'account (al più una).
  final List<SipAccount> accounts;
  SipAccount? get account => accounts.firstOrNull;
  final bool debugLog;
  final List<Extension> extensions;
  final List<PbxConnectionInfo> pbx;

  /// Codice lingua dell'interfaccia (`it`, `en`).
  final String lang;

  /// Tema dell'interfaccia: `system`, `light`, `dark`.
  final String theme;

  /// Codice funzione per ascoltare la casella vocale. `*2` è il default di
  /// Yeastar P-Series: configurabile, non universale (docs/sip-e-blf.md).
  final String voicemailCode;

  /// Interni preferiti: `<connessione>:<numero>`, connessione vuota per il PBX
  /// dell'account SIP e per gli interni inseriti a mano.
  final List<String> favorites;

  /// Dispositivi audio scelti (microfono, altoparlante, suoneria); '' = predefinito.
  final (String, String, String) audio;

  /// Globale: cifratura media, keep-alive, DTMF (Preferenze > Avanzate).
  final CallOptions callOptions;

  /// Globale: videochiamate, webcam, anteprima (Preferenze > Video).
  final VideoOptions video;

  /// Badge del profilo: ultima visita al registro chiamate (ISO 8601, '' = mai)
  /// e messaggi vocali già visti (id del PBX; `mwi:<n>` per il solo conteggio SIP).
  final String seenMissedAt;
  final List<String> seenVoicemail;

  /// Globale: account in cui si entra all'avvio ('' = si sceglie a ogni avvio,
  /// se gli account sono più di uno).
  final String defaultProfile;

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
      theme: theme,
      voicemailCode: t.voicemailCode,
      favorites: t.favorites,
      audio: audio,
      callOptions: callOptions,
      video: video,
      seenMissedAt: t.seenMissedAt,
      seenVoicemail: t.seenVoicemail,
      defaultProfile: defaultProfile,
    );
  }

  /// Stessi dati globali con i profili [all]; attivo quello con lo stesso id,
  /// altrimenti il primo.
  Settings withProfiles(List<Profile> all) {
    final a = all.where((x) => x.id == profileId).firstOrNull ?? all.first;
    return Settings(
      profileId: a.id,
      profileName: a.name,
      profileKind: a.kind,
      others: [
        for (final x in all)
          if (x != a) x,
      ],
      accounts: a.accounts,
      debugLog: debugLog,
      extensions: a.extensions,
      pbx: a.pbx,
      lang: lang,
      theme: theme,
      voicemailCode: a.voicemailCode,
      favorites: a.favorites,
      audio: audio,
      callOptions: callOptions,
      video: video,
      seenMissedAt: a.seenMissedAt,
      seenVoicemail: a.seenVoicemail,
      defaultProfile: defaultProfile,
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
    String? theme,
    String? voicemailCode,
    List<String>? favorites,
    (String, String, String)? audio,
    CallOptions? callOptions,
    VideoOptions? video,
    String? seenMissedAt,
    List<String>? seenVoicemail,
    String? defaultProfile,
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
    theme: theme ?? this.theme,
    voicemailCode: voicemailCode ?? this.voicemailCode,
    favorites: favorites ?? this.favorites,
    audio: audio ?? this.audio,
    callOptions: callOptions ?? this.callOptions,
    video: video ?? this.video,
    seenMissedAt: seenMissedAt ?? this.seenMissedAt,
    seenVoicemail: seenVoicemail ?? this.seenVoicemail,
    defaultProfile: defaultProfile ?? this.defaultProfile,
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

  Future<SipAccount> _accountFrom(
    Map<String, dynamic> a,
    String id,
  ) async => SipAccount(
    id: id,
    pbxId: a['pbxId'] as String? ?? '',
    username: a['username'] as String,
    password: await _secure.read(key: _passwordKey(id)) ?? '',
    domain: a['domain'] as String,
    transport: SipTransport.values.byName(a['transport'] as String? ?? 'udp'),
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
    recording:
        RecordingMode.values.asNameMap()[a['recording']] ?? RecordingMode.auto,
    recordCode: a['recordCode'] as String? ?? '',
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
          sync: {
            for (final e in (c['sync'] as Map? ?? const {}).entries)
              if (e.value is int) e.key as String: e.value as int,
          },
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
      theme: j['theme'] as String? ?? 'system',
      voicemailCode: active?.voicemailCode ?? '*2',
      favorites: active?.favorites ?? const [],
      seenMissedAt: active?.seenMissedAt ?? '',
      seenVoicemail: active?.seenVoicemail ?? const [],
      defaultProfile: j['defaultProfile'] as String? ?? '',
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
        quality:
            VideoQuality.values.asNameMap()[j['videoQuality']] ??
            VideoQuality.medium,
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
          'recording': a.recording.name,
          'recordCode': a.recordCode,
        },
    ],
    'extensions': [for (final e in p.extensions) e.toJson()],
    'voicemailCode': p.voicemailCode,
    'favorites': p.favorites,
    'seenMissedAt': p.seenMissedAt,
    'seenVoicemail': p.seenVoicemail,
    'pbx': [
      for (final c in p.pbx)
        {
          'id': c.id,
          'label': c.label,
          'realtime': c.realtime,
          if (c.sync.isNotEmpty) 'sync': c.sync,
        },
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
        'defaultProfile': s.defaultProfile,
        'profiles': [for (final p in s.profiles) _profileJson(p)],
        'debugLog': s.debugLog,
        'lang': s.lang,
        'theme': s.theme,
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
        'videoQuality': s.video.quality.name,
      }),
    );
  }
}

/// Divide un profilo con più registrazioni SIP (versioni con più account vivi
/// insieme) in un account per registrazione, ognuno con la connessione API
/// del suo PBX: quella scelta nell'account, poi quella con lo stesso host
/// ([hosts]: id connessione → host API), poi le rimaste in ordine. Il primo
/// tiene id, registro, interni manuali e badge del profilo; [newId] dà l'id
/// agli altri. Le connessioni senza account restano fuori.
List<Profile> splitProfile(
  Profile p, {
  required String Function() newId,
  Map<String, String> hosts = const {},
}) {
  if (p.accounts.length <= 1 && p.pbx.length <= 1) return [p];
  if (p.accounts.isEmpty) return [p];
  final free = [...p.pbx];
  final conn = <SipAccount, PbxConnectionInfo>{};
  void assign(PbxConnectionInfo? Function(SipAccount) pick) {
    for (final a in p.accounts) {
      if (conn.containsKey(a)) continue;
      final c = pick(a);
      if (c == null) continue;
      conn[a] = c;
      free.remove(c);
    }
  }

  assign((a) => free.where((c) => c.id == a.pbxId).firstOrNull);
  assign((a) => free.where((c) => hosts[c.id] == a.host).firstOrNull);
  assign((a) => free.firstOrNull);
  return [
    for (final (i, a) in p.accounts.indexed)
      () {
        final c = conn[a];
        bool fav(String f) =>
            f.startsWith('${c?.id ?? '\u0000'}:') ||
            (i == 0 && f.startsWith(':'));
        return Profile(
          id: i == 0 ? p.id : newId(),
          name: [a.username, c?.label ?? a.domain].join(' · '),
          kind: c != null
              ? ProfileKind.yeastar
              : (i == 0 ? p.kind : ProfileKind.sip),
          accounts: [a],
          extensions: i == 0 ? p.extensions : const [],
          pbx: [?c],
          voicemailCode: p.voicemailCode,
          favorites: p.favorites.where(fav).toList(),
          seenMissedAt: p.seenMissedAt,
          seenVoicemail: p.seenVoicemail,
        );
      }(),
  ];
}
