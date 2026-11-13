import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/pbx/pbx_cdr.dart';
import 'package:drinphone/core/pbx/yeastar_api.dart';
import 'package:drinphone/core/platform/audio_player.dart';
import 'package:drinphone/core/security/api_credential_store.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/history/cdr_view.dart';
import 'package:drinphone/features/voicemail/voicemail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';
import 'yeastar_api_test.dart' show FakePbx;

class _WidgetAudioBackend implements AudioBackend {
  String? lastPath;
  String curMode = 'stopped';

  @override
  Future<int> open(String path) async {
    lastPath = path;
    curMode = 'stopped';
    return 15000;
  }

  @override
  Future<void> play() async => curMode = 'playing';

  @override
  Future<void> pause() async => curMode = 'paused';

  @override
  Future<void> resume() async => curMode = 'playing';

  @override
  Future<void> seek(int ms) async => curMode = 'playing';

  @override
  Future<int> positionMs() async => 1000;

  @override
  Future<String> mode() async => curMode;

  @override
  Future<void> close() async => curMode = 'stopped';
}

void main() {
  HttpOverrides? prevHttp;
  late FakePbx pbx;
  late Directory tmp;

  setUpAll(() {
    prevHttp = HttpOverrides.current;
    HttpOverrides.global = null;
  });

  tearDownAll(() {
    HttpOverrides.global = prevHttp;
  });

  setUp(() async {
    pbx = FakePbx();
    await pbx.start();
    tmp = await Directory.systemTemp.createTemp('drinphone_s1_widget');
  });

  tearDown(() async {
    await pbx.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  Future<PhoneController> makePhone(
    String label,
    _WidgetAudioBackend backend,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final sep = Platform.pathSeparator;
    ApiCredentialStore storeFor(String id) =>
        ApiCredentialStore('${tmp.path}${sep}api-$label-$id.dpapi');
    await storeFor('a').save(
      ApiCredentials(
        baseUrl: pbx.baseUrl,
        clientId: 'CLIENT-ID-123',
        clientSecret: 'CLIENT-SECRET-xyz',
        ownExtension: '305',
      ),
    );
    final settings = SettingsStore('${tmp.path}${sep}s-$label.json');
    await settings.save(
      const Settings(
        accounts: [SipAccount(username: '305', password: 'p', domain: '127.0.0.1')],
        pbx: [PbxConnectionInfo('a', 'PBX')],
      ),
    );
    final phone = PhoneController(
      FakeSipEngine(),
      settings,
      engineDataDir: tmp.path,
      logDir: tmp.path,
      audioBackend: backend,
      apiStoreFor: storeFor,
    );
    await phone.init();
    await phone.connectionsStarted;
    return phone;
  }

  testWidgets(
    'VoicemailView riproduce messaggio in-app tramite InlineAudioPlayerBar',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        final backend = _WidgetAudioBackend();
        final phone = await makePhone('vm', backend);
        final conn = phone.connections.single;
        conn.voicemail = [
          const PbxVoicemail(
            id: 'msg-42',
            callerName: 'Mario Rossi',
            callerNumber: '025551234',
            time: '2026/11/13 10:15:00',
            seconds: 18,
            read: false,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: Scaffold(
              body: VoicemailView(phone: phone, onCall: (_) {}),
            ),
          ),
        );
        await tester.pump();

        expect(find.textContaining('Mario Rossi'), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        for (var i = 0; i < 40 && !phone.mediaPlayer.isPlaying; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }

        expect(phone.mediaPlayer.isPlaying, isTrue);
        expect(backend.lastPath, isNotNull);
        expect(File(backend.lastPath!).existsSync(), isTrue);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

        await phone.shutdown();
        phone.dispose();
      });
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'CdrDetailsDialog mostra player registrazione e azioni rapide sui partecipanti',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        final backend = _WidgetAudioBackend();
        final phone = await makePhone('cdr', backend);
        final conn = phone.connections.single;
        final saved = <(String, String)>[];
        final called = <String>[];

        final rec = CdrRecord(
          uid: 'UID-REC-1',
          time: DateTime(2026, 11, 13, 11, 0),
          callType: 'Inbound',
          disposition: 'ANSWERED',
          src: '02123456',
          srcName: 'Cliente Uno',
          dst: '305',
          dstName: 'Luigi',
          duration: 50,
          ring: 8,
          talk: 42,
          hasRecording: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: Scaffold(
              body: CdrDetailsDialog(
                rec,
                conn: conn,
                player: phone.mediaPlayer,
                audioCacheDir: tmp,
                canDial: true,
                onCall: called.add,
                onSaveContact: (name, number) async => saved.add((name, number)),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        for (var i = 0; i < 40 && !phone.mediaPlayer.isPlaying; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        expect(phone.mediaPlayer.isPlaying, isTrue);
        expect(
          File(backend.lastPath!).readAsStringSync(),
          'RIFF-FAKE-WAV-rec_91.wav',
        );

        // Azioni rapide su Da (Cliente Uno · 02123456)
        await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Richiama'), findsOneWidget);
        expect(find.text('Copia numero'), findsOneWidget);
        expect(find.text('Salva in rubrica'), findsOneWidget);

        await tester.tap(find.text('Salva in rubrica'));
        await tester.pump();
        expect(saved, [('Cliente Uno', '02123456')]);

        await phone.shutdown();
        phone.dispose();
      });
    },
    skip: !Platform.isWindows,
  );
}
