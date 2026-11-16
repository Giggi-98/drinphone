import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

/// Ritorna true se l'orario di [now] cade nell'intervallo `[fromMinute, toMinute)`
/// (minuti dalla mezzanotte, 0..1439). Gestisce intervalli notturni es. 18:00 -> 09:00.
bool isWithinDndSchedule(DateTime now, int fromMinute, int toMinute) {
  final cur = now.hour * 60 + now.minute;
  final from = fromMinute.clamp(0, 1439);
  final to = toMinute.clamp(0, 1439);
  if (from == to) return false;
  if (from < to) return cur >= from && cur < to;
  return cur >= from || cur < to;
}

/// Verifica su Windows se un'altra applicazione (Teams, Meet, Zoom, ecc.,
/// escluso DrinPhone) sta usando il microfono adesso tramite CapabilityAccessManager.
bool isExternalMicInUseWindows() {
  if (!Platform.isWindows) return false;
  const rootPath =
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone';
  RegistryKey? root;
  try {
    final r = CURRENT_USER.open(rootPath);
    root = r;
    for (final name in r.keys) {
      final lower = name.toLowerCase();
      if (lower.contains('drinphone')) continue;
      if (name == 'NonPackaged') {
        if (_hasActiveEntry(r, subPath: 'NonPackaged')) return true;
      } else {
        final start = r.getInt('LastUsedTimeStart', path: name);
        final stop = r.getInt('LastUsedTimeStop', path: name);
        if (start != null && start > 0 && stop == 0) return true;
      }
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    root?.close();
  }
}

bool _hasActiveEntry(RegistryKey parent, {required String subPath}) {
  RegistryKey? sub;
  try {
    final s = parent.open(subPath);
    sub = s;
    for (final name in s.keys) {
      if (name.toLowerCase().contains('drinphone')) continue;
      final start = s.getInt('LastUsedTimeStart', path: name);
      final stop = s.getInt('LastUsedTimeStop', path: name);
      if (start != null && start > 0 && stop == 0) return true;
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    sub?.close();
  }
}
