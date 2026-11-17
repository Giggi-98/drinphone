import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/call/call_window.dart';
import 'package:drinphone/features/history/history_view.dart';
import 'package:drinphone/features/preferences/preferences_view.dart';
import 'package:drinphone/features/shell/home_screen.dart';
import 'package:drinphone/features/shell/search_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

void main() {
  testWidgets('Mini-HUD 2.0: timer chiamata, tastierino DTMF e trasferimento rapido', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final sep = Platform.pathSeparator;
      final dir = await Directory.systemTemp.createTemp('drin_s9_hud_');
      final engine = FakeSipEngine();
      final settings = SettingsStore('${dir.path}${sep}s.json');
      await settings.save(
        const Settings(
          accounts: [
            SipAccount(username: '301', password: 'pw', domain: 'pbx.local'),
          ],
          extensions: [Extension('Marco', '201')],
          favorites: [':201'],
        ),
      );
      final phone = PhoneController(
        engine,
        settings,
        engineDataDir: dir.path,
        logDir: dir.path,
      );
      await phone.init();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: HomeScreen(phone: phone),
        ),
      );
      await tester.pump();

      // Entra in Mini-HUD dal pulsante della barra superiore.
      await tester.tap(find.byTooltip('Mini-HUD compatto'));
      tester.view.physicalSize = const Size(420, 264);
      await tester.pump();
      expect(find.text('Espandi'), findsOneWidget);

      // Simula chiamata attiva: mostra durata, Tastiera DTMF e Trasferisci ai preferiti.
      engine.callsCtl.add(
        const CallEvent(
          id: 91,
          phase: CallPhase.active,
          direction: CallDirection.outgoing,
          remoteNumber: '301',
        ),
      );
      await tester.pump();
      expect(find.text('301'), findsWidgets);

      await tester.tap(find.byTooltip('Tastiera'));
      await tester.pump();
      await tester.tap(find.text('5').last);
      await tester.pump();
      expect(engine.log, contains('dtmf 91 5'));

      await tester.tap(find.byTooltip('Trasferisci'));
      await tester.pump();
      expect(find.text('Marco (201)'), findsOneWidget);
      await tester.tap(find.text('Marco (201)'));
      await tester.pump();
      expect(engine.log, contains('transfer 91 201'));

      await tester.pumpWidget(const SizedBox());
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });

  testWidgets('Command Palette (>): esegue dnd, tema scuro e mini', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final sep = Platform.pathSeparator;
      final dir = await Directory.systemTemp.createTemp('drin_s9_cmd_');
      final engine = FakeSipEngine();
      final settings = SettingsStore('${dir.path}${sep}s.json');
      await settings.save(
        const Settings(pbx: [PbxConnectionInfo('a', 'PBX', realtime: true)]),
      );
      final phone = PhoneController(
        engine,
        settings,
        engineDataDir: dir.path,
        logDir: dir.path,
      );
      await phone.init();

      var miniCalled = false;
      var prefsCalled = false;
      final focus = FocusNode();
      addTearDown(focus.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: SearchBox(
              phone: phone,
              focusNode: focus,
              onCall: (_) {},
              onOpenMiniHud: () => miniCalled = true,
              onOpenPreferences: () => prefsCalled = true,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '> tema scuro');
      await tester.pump();
      expect(find.text('Tema scuro'), findsOneWidget);
      await tester.tap(find.text('Tema scuro'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(appThemeMode.value, ThemeMode.dark);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '> preferenze');
      await tester.pump();
      await tester.tap(find.text('Preferenze'));
      await tester.pump();
      expect(prefsCalled, isTrue);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '> mini');
      await tester.pump();
      await tester.tap(find.text('Mini-HUD compatto'));
      await tester.pump();
      expect(miniCalled, isTrue);

      await tester.pumpWidget(const SizedBox());
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });

  testWidgets('CallWindow QoS: avviso Rete instabile e pannello Statistiche chiamata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final sep = Platform.pathSeparator;
      final dir = await Directory.systemTemp.createTemp('drin_s9_qos_');
      final engine = FakeSipEngine()
        ..nextAudioMetrics = const CallAudioMetrics(
          quality: 2.3,
          codec: 'opus/48000',
          downloadKbps: 38,
          uploadKbps: 36,
          jitterMs: 55,
          lossPct: 4.2,
          rttMs: 140,
        );
      final phone = PhoneController(
        engine,
        SettingsStore('${dir.path}${sep}s.json'),
        engineDataDir: dir.path,
        logDir: dir.path,
      );
      await phone.init();

      engine.callsCtl.add(
        const CallEvent(
          id: 55,
          phase: CallPhase.active,
          direction: CallDirection.outgoing,
          remoteNumber: '400',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: Stack(children: [CallWindow(phone: phone)]),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Rete instabile'), findsOneWidget);
      expect(phone.callAudioHistory(55), isNotEmpty);

      // Tocca l'indicatore qualità / rete instabile per aprire Qualità rete (QoS).
      await tester.tap(find.text('Rete instabile'));
      await tester.pump();
      expect(find.text('Qualità rete (QoS)'), findsOneWidget);
      expect(find.text('4.2 %'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });

  testWidgets('Wrap-up post-chiamata: tag rapido, nota e promemoria 15 min', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final sep = Platform.pathSeparator;
      final dir = await Directory.systemTemp.createTemp('drin_s9_wrap_');
      final engine = FakeSipEngine();
      final settings = SettingsStore('${dir.path}${sep}s.json');
      await settings.save(
        const Settings(
          accounts: [
            SipAccount(username: '301', password: 'pw', domain: 'pbx.local'),
          ],
        ),
      );
      final phone = PhoneController(
        engine,
        settings,
        engineDataDir: dir.path,
        logDir: dir.path,
      );
      await phone.init();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: HomeScreen(phone: phone),
        ),
      );
      await tester.pump();

      engine.callsCtl.add(
        const CallEvent(
          id: 77,
          phase: CallPhase.active,
          direction: CallDirection.incoming,
          remoteNumber: '220',
          remoteName: 'Mario',
        ),
      );
      await tester.pump();
      engine.callsCtl.add(
        const CallEvent(
          id: 77,
          phase: CallPhase.ended,
          direction: CallDirection.incoming,
          remoteNumber: '220',
          remoteName: 'Mario',
        ),
      );
      await tester.pump();

      expect(find.text('Mario · 220'), findsOneWidget);
      await tester.tap(find.text('Richiamare'));
      await tester.pump();
      expect(phone.wrapUpPinned, isTrue);

      await tester.tap(find.text('15 min'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(phone.lastEndedWrapUp, isNull);
      expect(phone.history.first.note, '[Richiamare]');
      expect(phone.reminders.any((r) => r.number == '220'), isTrue);

      await tester.pumpWidget(const SizedBox());
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });

  testWidgets('Slice E/F: suonerie, guadagni, tono 2a chiamata, tab Preferenze e Zoom UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final sep = Platform.pathSeparator;
      final dir = await Directory.systemTemp.createTemp('drin_s9_ef_');
      final engine = FakeSipEngine();
      final phone = PhoneController(
        engine,
        SettingsStore('${dir.path}${sep}s.json'),
        engineDataDir: dir.path,
        logDir: dir.path,
      );
      await phone.init();

      // Seconda chiamata entrante mentre una è già attiva suona incoming_chat.wav.
      engine.callsCtl.add(
        const CallEvent(
          id: 1,
          phase: CallPhase.active,
          direction: CallDirection.outgoing,
          remoteNumber: '201',
        ),
      );
      engine.callsCtl.add(
        const CallEvent(
          id: 2,
          phase: CallPhase.incoming,
          direction: CallDirection.incoming,
          remoteNumber: '202',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(engine.log, contains('play incoming_chat.wav'));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: PreferencesView(phone: phone, initialTab: 3)),
        ),
      );
      await tester.pump();

      expect(find.text('Audio & Suonerie'), findsOneWidget);
      expect(find.text('Chiamate & Automazioni'), findsOneWidget);
      expect(find.text('Rete & Sicurezza'), findsOneWidget);
      expect(find.text('Suonerie e guadagno audio'), findsOneWidget);

      await tester.ensureVisible(find.text('Prova suoneria'));
      await tester.tap(find.text('Prova suoneria'));
      await tester.pump();
      expect(engine.log, contains('play oldphone-mono.wav'));

      // Apri Diagnostica e aumenta lo Zoom UI.
      await tester.tap(find.text('Diagnostica'));
      await tester.pump();
      expect(find.text('Zoom interfaccia'), findsOneWidget);
      final beforeZoom = appZoom.value;
      await tester.tap(find.byTooltip('Aumenta zoom'));
      await tester.pump();
      expect(appZoom.value, closeTo(DrinScale.clampZoom(beforeZoom + 0.1), 0.01));
      phone.setZoom(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 550));

      await tester.pumpWidget(const SizedBox());
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });

  testWidgets('Slice H: Pannello Giornata in HistoryView mostra durata media e picco', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final sep = Platform.pathSeparator;
      final dir = await Directory.systemTemp.createTemp('drin_s9_h_');
      final engine = FakeSipEngine();
      final phone = PhoneController(
        engine,
        SettingsStore('${dir.path}${sep}s.json'),
        engineDataDir: dir.path,
        logDir: dir.path,
      );
      await phone.init();

      engine.callsCtl.add(
        const CallEvent(
          id: 11,
          phase: CallPhase.active,
          direction: CallDirection.outgoing,
          remoteNumber: '305',
        ),
      );
      engine.callsCtl.add(
        const CallEvent(
          id: 11,
          phase: CallPhase.ended,
          direction: CallDirection.outgoing,
          remoteNumber: '305',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: HistoryView(phone: phone, onCall: (_) {}),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('durata media'), findsOneWidget);
      expect(find.text('picco'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });
}
