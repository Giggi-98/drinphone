import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/platform/mic_busy_monitor.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/shell/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isWithinDndSchedule gestisce fasce diurne e notturne', () {
    expect(isWithinDndSchedule(DateTime(2026, 11, 16, 13, 30), 13 * 60, 14 * 60), isTrue);
    expect(isWithinDndSchedule(DateTime(2026, 11, 16, 14, 0), 13 * 60, 14 * 60), isFalse);
    expect(isWithinDndSchedule(DateTime(2026, 11, 16, 21, 0), 18 * 60, 9 * 60), isTrue);
    expect(isWithinDndSchedule(DateTime(2026, 11, 16, 8, 59), 18 * 60, 9 * 60), isTrue);
    expect(isWithinDndSchedule(DateTime(2026, 11, 16, 9, 0), 18 * 60, 9 * 60), isFalse);
    expect(isWithinDndSchedule(DateTime(2026, 11, 16, 12, 0), 18 * 60, 9 * 60), isFalse);
  });

  test('Auto-DND su microfono esterno e orario salva preferenze e blocca autoAnswer', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('drin_s6_');
    final store = SettingsStore(
      '${dir.path}${Platform.pathSeparator}settings.json',
    );
    final engine = FakeSipEngine();
    var micBusy = true;
    var now = DateTime(2026, 11, 16, 11, 0);
    final phone = PhoneController(
      engine,
      store,
      engineDataDir: dir.path,
      logDir: dir.path,
      clock: () => now,
      externalMicBusyProbe: () => micBusy,
    );
    await phone.init();
    await phone.setCallOptions(
      const CallOptions(autoAnswer: true, autoAnswerDelaySeconds: 0),
    );
    await phone.setAutoDndPreferences(
      onExternalMic: true,
      scheduleEnabled: true,
      fromMinute: 18 * 60,
      toMinute: 9 * 60,
    );

    expect(phone.autoDndActive, isTrue);
    expect(phone.autoDndAlertId, 1);
    expect(
      phone.autoDndAlertMessage,
      'Microfono in uso da un’altra app: Non disturbare attivo.',
    );

    // Con Auto-DND attivo (senza OpenAPI) la chiamata entrante viene rifiutata e mai risposta.
    engine.callsCtl.add(
      const CallEvent(
        id: 19,
        phase: CallPhase.incoming,
        direction: CallDirection.incoming,
        remoteNumber: '302',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(engine.log.where((e) => e.startsWith('answer')), isEmpty);
    expect(engine.log, contains('hangup 19'));
    engine.callsCtl.add(
      const CallEvent(
        id: 19,
        phase: CallPhase.ended,
        direction: CallDirection.incoming,
        remoteNumber: '302',
      ),
    );

    // Libera il microfono fuori orario -> Auto-DND si disattiva.
    micBusy = false;
    await phone.evaluateAutoDnd();
    expect(phone.autoDndActive, isFalse);

    // Alle 20:00 scatta la fascia oraria.
    now = DateTime(2026, 11, 16, 20, 0);
    await phone.evaluateAutoDnd();
    expect(phone.autoDndActive, isTrue);

    // Ricarica impostazioni da disco.
    final reloaded = await store.load();
    expect(reloaded.autoDndOnExternalMic, isTrue);
    expect(reloaded.autoDndScheduleEnabled, isTrue);
    expect(reloaded.autoDndFromMinute, 18 * 60);
    expect(reloaded.autoDndToMinute, 9 * 60);

    await phone.shutdown();
    phone.dispose();
    await dir.delete(recursive: true);
  });

  testWidgets('HomeScreen entra ed esce dal Mini-HUD mostrando preferiti e controlli chiamata', (
    tester,
  ) async {
    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('drin_s6_hud_');
      final store = SettingsStore(
        '${dir.path}${Platform.pathSeparator}settings.json',
      );
      await store.save(
        const Settings(
          accounts: [
            SipAccount(username: '301', password: 'pw', domain: 'pbx.local'),
          ],
          extensions: [Extension('Luca', '305')],
          favorites: [':305'],
        ),
      );
      final engine = FakeSipEngine();
      final phone = PhoneController(
        engine,
        store,
        engineDataDir: dir.path,
        logDir: dir.path,
      );
      await phone.init();

      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: HomeScreen(phone: phone),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Mini-HUD compatto'));
      tester.view.physicalSize = const Size(420, 230);
      await tester.pump();

      expect(find.text('DrinPhone HUD'), findsOneWidget);
      expect(find.text('Luca (305)'), findsOneWidget);

      // Chiamata entrante dentro il Mini-HUD.
      engine.callsCtl.add(
        const CallEvent(
          id: 91,
          phase: CallPhase.incoming,
          direction: CallDirection.incoming,
          remoteNumber: '309',
          remoteName: 'Sara',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      expect(find.text('Sara · 309'), findsOneWidget);
      expect(find.text('Rispondi'), findsOneWidget);

      tester.view.physicalSize = const Size(1100, 700);
      await tester.tap(find.text('Espandi'));
      await tester.pump();
      expect(find.text('DrinPhone HUD'), findsNothing);

      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });

  test('isExternalMicInUseWindows esegue probe WASAPI e registro senza eccezioni', () {
    expect(isExternalMicInUseWindows(), isA<bool>());
  });

  testWidgets('HomeScreen mostra popup in finestra quando scatta Auto-DND', (
    tester,
  ) async {
    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('drin_s6_pop_');
      final store = SettingsStore(
        '${dir.path}${Platform.pathSeparator}settings.json',
      );
      await store.save(
        const Settings(
          accounts: [
            SipAccount(username: '301', password: 'pw', domain: 'pbx.local'),
          ],
        ),
      );
      final engine = FakeSipEngine();
      var micBusy = false;
      final phone = PhoneController(
        engine,
        store,
        engineDataDir: dir.path,
        logDir: dir.path,
        externalMicBusyProbe: () => micBusy,
      );
      await phone.init();

      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: HomeScreen(phone: phone),
        ),
      );
      await tester.pump();

      micBusy = true;
      await phone.setAutoDndPreferences(onExternalMic: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Auto-DND'), findsOneWidget);
      expect(
        find.text('Microfono in uso da un’altra app: Non disturbare attivo.'),
        findsOneWidget,
      );

      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });
}

