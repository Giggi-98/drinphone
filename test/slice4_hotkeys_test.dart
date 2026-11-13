import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/core/platform/global_hotkeys.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GlobalHotkeys.sanitizeClipboardNumber estrae numeri e scarta testo libero', () {
    expect(GlobalHotkeys.sanitizeClipboardNumber('+39 02 1234-5678'), '+390212345678');
    expect(GlobalHotkeys.sanitizeClipboardNumber('tel:+39(06)987654'), '+3906987654');
    expect(GlobalHotkeys.sanitizeClipboardNumber('sip:301@pbx.local'), '301');
    expect(GlobalHotkeys.sanitizeClipboardNumber('ciao mondo'), isNull);
    expect(GlobalHotkeys.sanitizeClipboardNumber('5'), isNull);
    expect(GlobalHotkeys.sanitizeClipboardNumber(''), isNull);
  });

  test('GlobalHotkeys.handleAction gestisce answerHangup, mute e dialClipboard', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('drin_s4_');
    final store = SettingsStore('${dir.path}${Platform.pathSeparator}settings.json');
    final engine = FakeSipEngine();
    final phone = PhoneController(
      engine,
      store,
      engineDataDir: dir.path,
      logDir: dir.path,
    );

    final channelLog = <(String, Object?)>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GlobalHotkeys.channel, (call) async {
      channelLog.add((call.method, call.arguments));
      return {'answerHangup': true, 'mute': true, 'dialClipboard': true};
    });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(GlobalHotkeys.channel, null);
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });

    await phone.init();
    await phone.login(phone.settings.profileId);

    final status = await phone.setGlobalHotkeys(true);
    expect(status['answerHangup'], isTrue);
    expect(phone.settings.globalHotkeys, isTrue);
    expect(channelLog.last, ('setEnabled', true));

    // Chiamata in arrivo -> Ctrl+Alt+A risponde
    engine.callsCtl.add(
      const CallEvent(
        id: 201,
        phase: CallPhase.incoming,
        direction: CallDirection.incoming,
        remoteNumber: '305',
      ),
    );
    var shown = false;
    await GlobalHotkeys.handleAction(
      'answerHangup',
      phone,
      onShowWindow: () => shown = true,
    );
    expect(shown, isTrue);
    expect(engine.log, contains('answer 201'));

    // Chiamata attiva -> Ctrl+Alt+M mette/toglie muto, Ctrl+Alt+A riaggancia
    engine.callsCtl.add(
      const CallEvent(
        id: 201,
        phase: CallPhase.active,
        direction: CallDirection.incoming,
        remoteNumber: '305',
      ),
    );
    await GlobalHotkeys.handleAction('mute', phone);
    expect(phone.muted, isTrue);

    await GlobalHotkeys.handleAction('answerHangup', phone);
    expect(engine.log, contains('hangup 201'));

    // Appunti -> Ctrl+Alt+D propone il numero sanificato
    String? candidate;
    await GlobalHotkeys.handleAction(
      'dialClipboard',
      phone,
      readClipboard: () async => '02 55443322',
      onDialCandidate: (n) => candidate = n,
    );
    expect(candidate, '0255443322');
  });
}
