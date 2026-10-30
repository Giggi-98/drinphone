// Barra di sistema e notifiche di Windows: l'app resta raggiungibile con la
// finestra chiusa e avvisa delle chiamate in arrivo quando non è in primo
// piano (Rispondi / Rifiuta dalla notifica).
import 'dart:io';

import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../core/platform/window_attention.dart';
import '../../core/sip/sip_engine.dart';

class DesktopShell with TrayListener {
  DesktopShell._(this._phone);
  final PhoneController _phone;

  /// Attiva solo su Windows, dopo [start].
  static DesktopShell? instance;

  /// "Esci" scelto: la chiusura non va nella barra ma termina l'app.
  bool quitting = false;

  final _toasts = <int, LocalNotification>{};
  String _tooltip = '';

  static Future<void> start(PhoneController phone) async {
    if (!Platform.isWindows || instance != null) return;
    final s = DesktopShell._(phone);
    instance = s;
    await trayManager.setIcon('assets/brand/tray.ico');
    trayManager.addListener(s);
    await s._menu();
    await localNotifier.setup(appName: 'DrinPhone');
    phone.addListener(s._onPhone);
    appLang.addListener(s._menu);
    s._onPhone();
  }

  Future<void> _menu() => trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(key: 'show', label: tr('Apri DrinPhone')),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: tr('Esci')),
      ],
    ),
  );

  void _onPhone() {
    final p = _phone;
    final reg = switch (p.registration.status) {
      RegistrationStatus.ok => tr('Registrato'),
      RegistrationStatus.progress => tr('Registrazione…'),
      RegistrationStatus.failed => tr('Registrazione non riuscita'),
      _ => tr('Non registrato'),
    };
    final tip = 'DrinPhone · $reg';
    if (tip != _tooltip) {
      _tooltip = tip;
      trayManager.setToolTip(tip);
    }
    // Una notifica per chiamata in arrivo, solo se l'utente non guarda l'app.
    final ringing = {
      for (final c in p.calls.values)
        if (c.phase == CallPhase.incoming) c.id: c,
    };
    for (final id in [..._toasts.keys]) {
      // destroy, non close: il click su una notifica rimasta nel centro
      // notifiche non deve più arrivare qui.
      if (!ringing.containsKey(id)) _toasts.remove(id)?.destroy();
    }
    for (final c in ringing.values) {
      if (_toasts.containsKey(c.id) || WindowAttention.instance.inFront) {
        continue;
      }
      final name = c.remoteName.isNotEmpty
          ? c.remoteName
          : p.nameFor(c.remoteNumber);
      final n = LocalNotification(
        title: name.isNotEmpty ? name : c.remoteNumber,
        body: c.remoteVideo
            ? tr('Videochiamata in arrivo · {n}', {'n': c.remoteNumber})
            : tr('Chiamata in arrivo · {n}', {'n': c.remoteNumber}),
        actions: [
          LocalNotificationAction(text: tr('Rispondi')),
          LocalNotificationAction(text: tr('Rifiuta')),
        ],
      );
      n.onClick = WindowAttention.instance.show;
      n.onClickAction = (i) {
        // L'id della chiamata è un indirizzo nativo, riusabile: si agisce
        // solo se è ancora la stessa chiamata e squilla ancora.
        if (!identical(_toasts[c.id], n) ||
            p.calls[c.id]?.phase != CallPhase.incoming) {
          return;
        }
        if (i == 0) {
          WindowAttention.instance.show();
          p.answer(c.id);
        } else {
          p.hangup(c.id);
        }
      };
      _toasts[c.id] = n;
      n.show();
    }
  }

  @override
  void onTrayIconMouseDown() => WindowAttention.instance.show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        WindowAttention.instance.show();
      case 'quit':
        quit();
    }
  }

  /// Uscita vera (menu della barra): un-REGISTER, revoca token, poi fine.
  Future<void> quit() async {
    quitting = true;
    await _phone.shutdown();
    await dispose();
    exit(0);
  }

  Future<void> dispose() async {
    _phone.removeListener(_onPhone);
    appLang.removeListener(_menu);
    for (final n in _toasts.values) {
      await n.destroy();
    }
    _toasts.clear();
    trayManager.removeListener(this);
    await trayManager.destroy();
    instance = null;
  }
}
