import 'dart:ffi';
import 'dart:io';

import 'package:win32/win32.dart';
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
/// escluso DrinPhone) sta usando il microfono adesso:
/// 1. Interroga le sessioni attive WASAPI (`IAudioSessionManager2` su `eCapture`)
///    escludendo il PID corrente di DrinPhone (rileva in tempo reale browser,
///    app Electron/Win32 e driver senza ritardi del registro).
/// 2. Come complemento, controlla il registro Privacy `CapabilityAccessManager`.
bool isExternalMicInUseWindows() {
  if (!Platform.isWindows) return false;
  return _isWasapiCaptureInUse() || _isConsentStoreMicInUse();
}

const _clsidMMDeviceEnumeratorStr = '{bcde0395-e52f-467c-8e3d-c4579291692e}';

bool _isWasapiCaptureInUse() {
  final comHr = CoInitializeEx(COINIT_APARTMENTTHREADED);
  final shouldUninit = comHr == S_OK || comHr == S_FALSE;
  // RPC_E_CHANGED_MODE significa COM già inizializzato su questo thread: OK.
  if (comHr.isError && comHr != RPC_E_CHANGED_MODE) return false;

  final selfPid = GetCurrentProcessId();
  IMMDeviceEnumerator? enumerator;
  IMMDeviceCollection? collection;
  Pointer<GUID>? pClsid;
  try {
    pClsid = GUID(_clsidMMDeviceEnumeratorStr).toNative();
    enumerator = CoCreateInstance<IMMDeviceEnumerator>(
      pClsid,
      null,
      CLSCTX_ALL,
    );

    collection = enumerator.enumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE);
    if (collection == null) return false;
    final devCount = collection.getCount();
    for (var i = 0; i < devCount; i++) {
      final device = collection.item(i);
      if (device == null) continue;
      IAudioSessionManager2? mgr;
      IAudioSessionEnumerator? sessions;
      try {
        mgr = device.activate<IAudioSessionManager2>(CLSCTX_ALL, null);
        sessions = mgr.getSessionEnumerator();
        if (sessions == null) continue;
        final sCount = sessions.getCount();
        for (var j = 0; j < sCount; j++) {
          final ctrl = sessions.getSession(j);
          if (ctrl == null) continue;
          IAudioSessionControl2? ctrl2;
          try {
            if (ctrl.getState() != AudioSessionStateActive) continue;
            ctrl2 = IAudioSessionControl2.from(ctrl);
            if (ctrl2.isSystemSoundsSession() == S_OK) continue;
            final pid = ctrl2.getProcessId();
            if (pid != 0 && pid != selfPid) return true;
          } catch (_) {
            // Singola sessione non accessibile/scaduta: continua sulle altre.
          } finally {
            ctrl2?.release();
            ctrl.release();
          }
        }
      } catch (_) {
        // Endpoint disconnesso o senza session manager: passa al successivo.
      } finally {
        sessions?.release();
        mgr?.release();
        device.release();
      }
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    if (pClsid != null) free(pClsid);
    collection?.release();
    enumerator?.release();
    if (shouldUninit) CoUninitialize();
  }
}

bool _isConsentStoreMicInUse() {
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
        if (start != null && start > 0 && (stop == null || stop == 0)) {
          return true;
        }
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
      if (start != null && start > 0 && (stop == null || stop == 0)) {
        return true;
      }
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    sub?.close();
  }
}
