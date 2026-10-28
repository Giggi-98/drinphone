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
}
