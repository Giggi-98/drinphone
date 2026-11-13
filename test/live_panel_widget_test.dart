import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/pbx/yeastar_api.dart';
import 'package:drinphone/core/security/api_credential_store.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/live/live_calls_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';
import 'yeastar_api_test.dart' show FakePbx;

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
    pbx = FakePbx()..include305InQueue = true;
    await pbx.start();
    tmp = await Directory.systemTemp.createTemp('drinphone_s2_live');
  });

  tearDown(() async {
    await pbx.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  testWidgets(
    'LiveCallsView: pickup su BLF ringing, pausa coda, Riprendi parcheggio',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        FlutterSecureStorage.setMockInitialValues({});
        final sep = Platform.pathSeparator;
        final engine = FakeSipEngine();
        ApiCredentialStore storeFor(String id) =>
            ApiCredentialStore('${tmp.path}${sep}api-$id.dpapi');
        await storeFor('a').save(
          ApiCredentials(
            baseUrl: pbx.baseUrl,
            clientId: 'CLIENT-ID-123',
            clientSecret: 'CLIENT-SECRET-xyz',
            ownExtension: '305',
          ),
        );
        final settings = SettingsStore('${tmp.path}${sep}s.json');
        await settings.save(
          const Settings(
            accounts: [
              SipAccount(username: '305', password: 'p', domain: '127.0.0.1'),
            ],
            pbx: [PbxConnectionInfo('a', 'PBX')],
          ),
        );
        final phone = PhoneController(
          engine,
          settings,
          engineDataDir: tmp.path,
          logDir: tmp.path,
          apiStoreFor: storeFor,
        );
        await phone.init();
        await phone.connectionsStarted;

        // SIP registrato così canDial è true + interno 301 che squilla via BLF
        engine.registrationsCtl.add(
          const RegistrationEvent(RegistrationStatus.ok),
        );
        engine.dialogsCtl.add(
          const BlfEvent('301@127.0.0.1', BlfStatus.ringing),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final conn = phone.connections.single;
        conn.parkedCalls = const [
          PbxParkedCall(
            slot: '6000',
            parker: '305',
            parkedParty: '02999888',
            channelId: 'ch-p1',
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: Scaffold(
              body: LiveCallsView(phone: phone, onOpenPreferences: () {}),
            ),
          ),
        );
        await tester.pump();

        // Pulsante Pickup BLF sul 301 in stato ringing
        expect(find.byIcon(Icons.phone_in_talk_rounded), findsAtLeastNWidgets(1));
        await tester.tap(find.byIcon(Icons.phone_in_talk_rounded).first);
        await tester.pump();
        expect(engine.log.any((x) => x.contains('*04301')), isTrue);

        // Slot parcheggio occupato con azione Riprendi
        expect(find.text('Riprendi'), findsOneWidget);
        await tester.tap(find.text('Riprendi'));
        await tester.pump();
        expect(engine.log.any((x) => x.contains('6000')), isTrue);

        // Pill Code attive -> Pausa su tutte le code
        expect(find.text('Code attive'), findsOneWidget);
        await tester.tap(find.text('Code attive'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text('Pausa su tutte le code'));
        for (var i = 0; i < 40 && conn.pausedQueueIds.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump(const Duration(milliseconds: 25));
        }
        await tester.pump(const Duration(milliseconds: 150));
        expect(conn.pausedQueueIds, {2});
        expect(find.text('In pausa coda'), findsOneWidget);

        await phone.shutdown();
        phone.dispose();
      });
    },
    skip: !Platform.isWindows,
  );
}
