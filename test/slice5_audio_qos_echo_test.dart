import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/platform/audio_player.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/call/call_window.dart';
import 'package:drinphone/features/preferences/preferences_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

class _FakeAudioBackend implements AudioBackend {
  bool openCalled = false;
  bool playing = false;
  @override
  Future<int> open(String path) async {
    openCalled = true;
    return 1500;
  }

  @override
  Future<void> play() async => playing = true;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> resume() async => playing = true;
  @override
  Future<void> seek(int ms) async {}
  @override
  Future<int> positionMs() async => playing ? 200 : 0;
  @override
  Future<String> mode() async => playing ? 'playing' : 'stopped';
  @override
  Future<void> close() async => playing = false;
}

class _FakeEchoBackend implements EchoRecorderBackend {
  bool started = false;
  bool cancelled = false;
  String? savedPath;

  @override
  Future<void> startRecording() async {
    started = true;
    cancelled = false;
  }

  @override
  Future<void> stopAndSave(String outputPath) async {
    savedPath = outputPath;
    await File(outputPath).writeAsBytes(const [1, 2, 3, 4]);
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MicEchoTester registra, riproduce e pulisce file temporaneo senza toccare registrazioni utente', () async {
    final dir = await Directory.systemTemp.createTemp('drin_s5_echo_');
    addTearDown(() => dir.delete(recursive: true));

    final audioBackend = _FakeAudioBackend();
    final echoBackend = _FakeEchoBackend();
    final player = InAppAudioPlayer(backend: audioBackend);
    final tester = MicEchoTester(
      player,
      backend: echoBackend,
      tempDir: dir.path,
      maxSeconds: 5,
    );

    await tester.start();
    expect(echoBackend.started, isTrue);
    expect(tester.phase, EchoTestPhase.recording);

    await tester.finishRecordingAndPlay();
    expect(echoBackend.savedPath, isNotNull);
    final tempFile = File(echoBackend.savedPath!);
    expect(tester.phase, EchoTestPhase.playing);
    expect(audioBackend.openCalled, isTrue);

    await tester.stop();
    expect(tester.phase, EchoTestPhase.idle);
    expect(tempFile.existsSync(), isFalse);

    // Registrazione permanente dell'utente: cacheFile=false non deve cancellarla in dispose.
    final userRec = File('${dir.path}${Platform.pathSeparator}20261116-call.wav');
    await userRec.writeAsBytes(const [5, 6, 7]);
    await player.togglePlay('localrec:${userRec.path}', () async => userRec, cacheFile: false);
    player.dispose();
    tester.dispose();
    expect(userRec.existsSync(), isTrue);
  });

  testWidgets('CallWindow mostra codec e metriche QoS live durante la chiamata', (
    tester,
  ) async {
    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('drin_s5_qos_');
      final store = SettingsStore(
        '${dir.path}${Platform.pathSeparator}settings.json',
      );
      final engine = FakeSipEngine()
        ..nextAudioMetrics = const CallAudioMetrics(
          quality: 4.4,
          downloadKbps: 48,
          uploadKbps: 45,
          lossPct: 0.2,
          jitterMs: 4,
          rttMs: 22,
          codec: 'opus/48kHz',
        );
      final phone = PhoneController(
        engine,
        store,
        engineDataDir: dir.path,
        logDir: dir.path,
      );
      await phone.init();

      engine.callsCtl.add(
        const CallEvent(
          id: 51,
          phase: CallPhase.active,
          direction: CallDirection.outgoing,
          remoteNumber: '305',
          remoteName: 'Marco',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1150));

      expect(phone.callAudioMetrics(51)?.codec, 'opus/48kHz');

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              height: 700,
              child: Stack(children: [CallWindow(phone: phone)]),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('opus/48kHz'), findsOneWidget);

      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });

  testWidgets('Preferenze Audio mostra Echo Test e lista registrazioni locali', (
    tester,
  ) async {
    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('drin_s5_prefs_');
      final recDir = Directory('${dir.path}${Platform.pathSeparator}recs');
      await recDir.create();
      await File('${recDir.path}${Platform.pathSeparator}20261116-101010-305.wav')
          .writeAsBytes(const [1, 2, 3]);
      final store = SettingsStore(
        '${dir.path}${Platform.pathSeparator}settings.json',
      );
      final engine = FakeSipEngine();
      final echo = _FakeEchoBackend();
      final phone = PhoneController(
        engine,
        store,
        engineDataDir: dir.path,
        logDir: dir.path,
        recordingsDir: recDir.path,
        audioBackend: _FakeAudioBackend(),
        echoBackend: echo,
      );
      await phone.init();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: PreferencesView(phone: phone, initialTab: 3),
          ),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();

      expect(find.text('Prova audio (Echo Test)'), findsOneWidget);
      expect(find.text('Registrazioni locali'), findsOneWidget);
      expect(find.text('20261116-101010-305.wav'), findsOneWidget);

      await tester.ensureVisible(find.text('Prova audio (Echo Test)'));
      await tester.tap(find.text('Prova audio (Echo Test)'));
      await tester.pump();
      expect(echo.started, isTrue);

      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });
}

