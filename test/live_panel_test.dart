import 'dart:convert';
import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/core/pbx/pbx_connection.dart';
import 'package:drinphone/core/pbx/yeastar_api.dart';
import 'package:drinphone/core/security/api_credential_store.dart';
import 'package:drinphone/core/security/cdr_db_store.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';
import 'yeastar_api_test.dart' show FakePbx;

const _id = 'CLIENT-ID-123';
const _secret = 'CLIENT-SECRET-xyz';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    tmp = await Directory.systemTemp.createTemp('drinphone_live_ui');
  });

  tearDown(() async {
    await pbx.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  Future<PhoneController> startPhone() async {
    FlutterSecureStorage.setMockInitialValues({});
    final sep = Platform.pathSeparator;
    ApiCredentialStore storeFor(String id) =>
        ApiCredentialStore('${tmp.path}${sep}api-$id.dpapi');
    await storeFor('a').save(
      ApiCredentials(
        baseUrl: pbx.baseUrl,
        clientId: _id,
        clientSecret: _secret,
        ownExtension: '305',
      ),
    );
    final settings = SettingsStore('${tmp.path}${sep}s.json');
    await settings.save(
      const Settings(
        accounts: [
          SipAccount(username: '305', password: 'p', domain: '127.0.0.1'),
        ],
        pbx: [PbxConnectionInfo('a', 'PBX A')],
      ),
    );
    final phone = PhoneController(
      FakeSipEngine(),
      settings,
      engineDataDir: tmp.path,
      logDir: tmp.path,
      apiStoreFor: storeFor,
      cdrStoreFor: (id) => CdrDbStore('${tmp.path}${sep}db-$id.dpapi'),
    );
    await phone.init();
    await phone.connectionsStarted;
    return phone;
  }

  testWidgets(
    'UI pannello Live: voce Live, drag & drop su target e menu contestuale condizionale',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late PhoneController phone;
      late PbxConnection conn;
      await tester.runAsync(() async {
        phone = await startPhone();
        conn = phone.connections.single;
        await phone.setRealtime(conn, true);
        for (var i = 0; i < 50 && !conn.eventsConnected; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        conn.liveCalls['C-UI'] = LiveCall('C-UI', const [
          LiveMember(
            kind: 'inbound',
            channel: 'ch-ui-in',
            status: 'ANSWER',
            from: '+3902123456',
            to: '301',
            trunk: 'TrunkUI',
          ),
          LiveMember(
            kind: 'extension',
            channel: 'ch-ui-301',
            status: 'ANSWERED',
            number: '301',
          ),
        ]);
      });

      await tester.pumpWidget(DrinPhoneApp(phone: phone));
      await tester.pump(const Duration(milliseconds: 300));

      // Sidebar rinominata "Live".
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Chiamate in corso'), findsNothing);
      await tester.tap(find.text('Live'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Entranti e interne'), findsOneWidget);
      expect(find.text('Uscenti'), findsOneWidget);
      expect(find.text('Gruppi di squillo'), findsOneWidget);
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('Parcheggio'), findsOneWidget);
      expect(find.text('Casella vocale di gruppo'), findsOneWidget);
      expect(find.textContaining('6300 RING_SKILLWORKS'), findsOneWidget);
      expect(find.textContaining('6000 Libero'), findsOneWidget);
      expect(tester.takeException(), isNull);

      Future<int> waitPost(String pathSuffix, int afterIndex) async {
        for (var i = 0; i < 40; i++) {
          await tester.pump();
          final idx = pbx.requests.lastIndexWhere(
            (r) => r.uri.path.endsWith(pathSuffix),
          );
          if (idx > afterIndex && pbx.bodies.length > idx) return idx;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        return -1;
      }

      Future<void> dragTo(Finder source, Finder target) async {
        final from = tester.getCenter(source);
        final to = tester.getCenter(target);
        final g = await tester.startGesture(
          from,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await g.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 40));
        await g.moveTo(to);
        await tester.pump(const Duration(milliseconds: 40));
        await g.up();
        await tester.pump();
      }

      // Drag & drop della chiamata attiva su un Gruppo di squillo → blind transfer.
      final dragFinder = find.byType(Draggable<LiveCall>).first;
      final callRowTarget = find.descendant(
        of: dragFinder,
        matching: find.text('+3902123456'),
      );
      final ringGroupFinder = find.textContaining('6300 RING_SKILLWORKS').first;
      await dragTo(callRowTarget, ringGroupFinder);
      final trIdx = await waitPost('call/transfer', -1);
      await tester.pump(const Duration(milliseconds: 200));

      expect(trIdx, greaterThanOrEqualTo(0));
      expect(jsonDecode(pbx.bodies[trIdx]), {
        'type': 'blind',
        'channel_id': 'ch-ui-in',
        'number': '6300',
      });

      // Drag & drop sulla colonna destra degli interni (BLF) → blind transfer.
      final extRowFinder = find.text('Paolo Guerra').first;
      await dragTo(callRowTarget, extRowFinder);
      final trExtIdx = await waitPost('call/transfer', trIdx);
      await tester.pump(const Duration(milliseconds: 200));

      expect(trExtIdx, greaterThan(trIdx));
      expect(jsonDecode(pbx.bodies[trExtIdx]), {
        'type': 'blind',
        'channel_id': 'ch-ui-in',
        'number': '301',
      });

      // Tasto destro sulla chiamata senza permesso monitoraggio: niente Listen/Whisper/Barge.
      await tester.tapAt(
        tester.getCenter(callRowTarget),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Trasferisci'), findsWidgets);
      expect(find.text('Riaggancia'), findsOneWidget);
      expect(find.text('Registra'), findsOneWidget);
      expect(find.text('Parcheggia'), findsOneWidget);
      expect(find.text('Ascolta'), findsNothing);
      expect(find.text('Suggerisci'), findsNothing);
      expect(find.text('Intromettiti'), findsNothing);

      // Chiude il menu contestuale cliccando fuori.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Abilita monitoraggio sul PBX e rilegge il dettaglio → ora compaiono.
      await tester.runAsync(() async {
        pbx.allowMonitor305 = true;
        await conn.refreshDetail();
      });
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tapAt(
        tester.getCenter(callRowTarget),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Intromettiti'), findsOneWidget);
      expect(find.text('Ascolta'), findsOneWidget);
      expect(find.text('Suggerisci'), findsOneWidget);

      await tester.tap(find.text('Ascolta'));
      final lsIdx = await waitPost('call/listen', -1);
      await tester.pump(const Duration(milliseconds: 200));

      expect(lsIdx, greaterThanOrEqualTo(0));
      expect(jsonDecode(pbx.bodies[lsIdx]), {
        'monitor': '305',
        'channel_id': 'ch-ui-301',
        'type': 'listen',
      });

      expect(tester.takeException(), isNull);
      await tester.runAsync(phone.shutdown);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !Platform.isWindows,
  );
}

