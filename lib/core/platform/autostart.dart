// Avvio con Windows: valore in HKCU\...\Run (solo l'utente corrente, niente
// privilegi), con --autostart per partire nella barra di sistema.
import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

abstract final class Autostart {
  static const _run = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _name = 'DrinPhone';
  static const flag = '--autostart';

  static String get _command => '"${Platform.resolvedExecutable}" $flag';

  /// Attivo e punta a questo eseguibile (dopo un aggiornamento il percorso
  /// resta lo stesso: installazione per utente in una cartella fissa).
  static bool get enabled {
    if (!Platform.isWindows) return false;
    final key = CURRENT_USER.create(_run);
    try {
      return key.getString(_name) == _command;
    } finally {
      key.close();
    }
  }

  static void set(bool on) {
    if (!Platform.isWindows) return;
    final key = CURRENT_USER.create(_run);
    try {
      if (on) {
        key.setValue(_name, RegistryValue.string(_command));
      } else if (key.getString(_name) != null) {
        key.removeValue(_name);
      }
    } finally {
      key.close();
    }
  }
}
