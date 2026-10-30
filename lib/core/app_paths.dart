import 'dart:io';

/// Cartelle private dell'app. Windows: %APPDATA%\Econnet\DrinPhone.
class AppPaths {
  AppPaths._(this.root);

  factory AppPaths.forPlatform() {
    final env = Platform.environment;
    final base = Platform.isWindows
        ? '${env['APPDATA']}\\Econnet\\DrinPhone'
        : '${env['XDG_DATA_HOME'] ?? '${env['HOME']}/.local/share'}/drinphone';
    return AppPaths._(base);
  }

  final String root;
  String get _s => Platform.pathSeparator;
  String get engineData => '$root${_s}linphone';
  String get logs => '$root${_s}logs';
  String get settingsFile => '$root${_s}settings.json';
  String get installIdFile => '$root${_s}install-id';

  /// Versione di cui si sono già mostrate le novità.
  String get notesSeenFile => '$root${_s}notes-seen';

  /// Registro chiamate del profilo; `default` = file della versione senza profili.
  String historyFileFor(String profileId) => profileId == 'default'
      ? '$root${_s}history.json'
      : '$root${_s}history-$profileId.json';

  /// Registrazioni locali delle chiamate: Documenti\DrinPhone\Registrazioni.
  String get recordings {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        root;
    return '$home${_s}Documents${_s}DrinPhone${_s}Registrazioni';
  }

  /// Codec scaricati (OpenH264 di Cisco).
  String get codecs => '$root${_s}codecs';

  /// Installer scaricati dagli aggiornamenti.
  String get updates => '$root${_s}updates';

  /// Cache cifrata (DPAPI) dei dati letti da una connessione PBX.
  String pbxCacheFileFor(String id) => '$root${_s}pbx-cache-$id.dpapi';

  /// Contatti personali del profilo; `default` come per il registro.
  String contactsFileFor(String profileId) => profileId == 'default'
      ? '$root${_s}contacts.json'
      : '$root${_s}contacts-$profileId.json';

  /// Un file DPAPI per connessione PBX; `default` = file della versione
  /// a connessione singola.
  String apiCredentialsFileFor(String id) => id == 'default'
      ? '$root${_s}yeastar-api.dpapi'
      : '$root${_s}yeastar-api-$id.dpapi';
}
