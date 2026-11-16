import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/pbx/pbx_connection.dart';
import 'package:drinphone/core/pbx/yeastar_api.dart';
import 'package:drinphone/core/security/api_credential_store.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/shell/home_screen.dart';
import 'package:flutter/gestures.dart';
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
    pbx = FakePbx();
    await pbx.start();
    tmp = await Directory.systemTemp.createTemp('drinphone_s7_');
  });

  tearDown(() async {
    await pbx.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  Future<(PhoneController, FakeSipEngine)> createPhone() async {
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
    engine.registrationsCtl.add(
      const RegistrationEvent(RegistrationStatus.ok),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (phone, engine);
  }

  test('Busy Callback: osserva interno occupato, scatta su idle e chiama', () async {
    final (phone, engine) = await createPhone();
    addTearDown(() async {
      await phone.shutdown();
      phone.dispose();
    });

    final ext301 = phone.allExtensions.firstWhere((e) => e.number == '301');

    // Su libero non si attiva.
    engine.dialogsCtl.add(const BlfEvent('301@127.0.0.1', BlfStatus.idle));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    phone.toggleBusyWatch(ext301);
    expect(phone.isWatchingBusy(ext301), isFalse);

    // Su occupato si attiva e si può annullare o tenere.
    engine.dialogsCtl.add(const BlfEvent('301@127.0.0.1', BlfStatus.busy));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    phone.toggleBusyWatch(ext301);
    expect(phone.isWatchingBusy(ext301), isTrue);
    expect(phone.activeBusyWatches, hasLength(1));
    expect(phone.readyBusyCallbacks, isEmpty);

    // Se liveCalls 30011 lo vede ancora in conversazione, BLF idle non scatta ancora.
    final conn = phone.connections.single;
    conn.liveCalls['c-1'] = LiveCall('c-1', [
      const LiveMember(
        kind: 'extension',
        channel: 'ch-301',
        status: 'ANSWER',
        number: '301',
      ),
    ]);
    engine.dialogsCtl.add(const BlfEvent('301@127.0.0.1', BlfStatus.idle));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(phone.readyBusyCallbacks, isEmpty);

    // Appena sparisce anche la chiamata live, scatta pronto.
    conn.liveCalls.clear();
    conn.onUpdate(conn, false);
    expect(phone.readyBusyCallbacks, hasLength(1));
    expect(phone.activeBusyWatches, isEmpty);

    // Chiama dal callback: avvia dial e rimuove il banner.
    await phone.callBusyCallback(phone.readyBusyCallbacks.single.key);
    expect(engine.log, contains('dial 301'));
    expect(phone.readyBusyCallbacks, isEmpty);
  });

  testWidgets('HomeScreen: Pickup BLF 1-clic su squillo e banner Busy Callback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late PhoneController phone;
    late FakeSipEngine engine;
    await tester.runAsync(() async {
      (phone, engine) = await createPhone();
      // 301 squilla via BLF.
      engine.dialogsCtl.add(
        const BlfEvent('301@127.0.0.1', BlfStatus.ringing),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        await phone.shutdown();
        phone.dispose();
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: HomeScreen(phone: phone),
      ),
    );
    await tester.pumpAndSettle();

    // Pulsante Pickup BLF visibile nella scheda di 301 -> chiama *04301.
    final pickupBtn = find.byIcon(Icons.phone_in_talk_rounded);
    expect(pickupBtn, findsOneWidget);
    await tester.tap(pickupBtn);
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.log, contains('dial *04301'));

    // 301 passa a busy -> menu tasto destro -> Avvisami appena si libera.
    await tester.runAsync(() async {
      engine.dialogsCtl.add(const BlfEvent('301@127.0.0.1', BlfStatus.busy));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('301'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Avvisami appena si libera'), findsOneWidget);
    await tester.tap(find.text('Avvisami appena si libera'));
    await tester.pumpAndSettle();

    // Campanella attiva sulla scheda di 301.
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);

    // 301 torna libero -> compare il banner in alto con Chiama ora.
    await tester.runAsync(() async {
      engine.dialogsCtl.add(const BlfEvent('301@127.0.0.1', BlfStatus.idle));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('ora è libero'), findsOneWidget);
    await tester.tap(find.text('Chiama ora'));
    await tester.pumpAndSettle();

    expect(engine.log, contains('dial 301'));
    expect(find.textContaining('ora è libero'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tema scuro a larghezza minima desktop (1024px): nessun overflow su banner e pickup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late PhoneController phone;
    late FakeSipEngine engine;
    await tester.runAsync(() async {
      (phone, engine) = await createPhone();
      engine.dialogsCtl.add(const BlfEvent('301@127.0.0.1', BlfStatus.busy));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        await phone.shutdown();
        phone.dispose();
      });
    });

    final ext301 = phone.allExtensions.firstWhere((e) => e.number == '301');
    phone.toggleBusyWatch(ext301);

    await tester.runAsync(() async {
      engine.dialogsCtl.add(const BlfEvent('301@127.0.0.1', BlfStatus.idle));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: HomeScreen(phone: phone),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ora è libero'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
