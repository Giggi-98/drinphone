import 'dart:convert';
import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/security/api_credential_store.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/dialog_info.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/call/call_window.dart';
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
    pbx = FakePbx()
      ..calls = {
        'inbound': const [],
        'outbound': const [],
        'internal': const [],
      };
    await pbx.start();
    tmp = await Directory.systemTemp.createTemp('drinphone_s8_');
  });

  tearDown(() async {
    await pbx.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  test('DialogInfoTracker: gestisce tag/state maiuscoli e terminated', () {
    final t = DialogInfoTracker();
    expect(
      t.apply('''
<dialog-info xmlns="urn:ietf:params:xml:ns:dialog-info" version="1" state="FULL" entity="sip:301@pbx">
  <dialog id="d1" direction="recipient"><state>EARLY</state></dialog>
</dialog-info>'''),
      BlfStatus.ringing,
    );
    expect(
      t.apply('''
<dialog-info xmlns="urn:ietf:params:xml:ns:dialog-info" version="2" state="PARTIAL" entity="sip:301@pbx">
  <dialog id="d1"><state>TERMINATED</state></dialog>
</dialog-info>'''),
      BlfStatus.idle,
    );
  });

  test('BLF / 30011 appesi: ring group interrotto e riconciliazione con snapshot call/query', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final sep = Platform.pathSeparator;
    final engine = FakeSipEngine();
    var now = DateTime.now();
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
        pbx: [PbxConnectionInfo('a', 'PBX', realtime: true)],
      ),
    );
    final phone = PhoneController(
      engine,
      settings,
      engineDataDir: tmp.path,
      logDir: tmp.path,
      apiStoreFor: storeFor,
      clock: () => now,
    );
    addTearDown(() async {
      await phone.shutdown();
      phone.dispose();
    });
    await phone.init();
    await phone.connectionsStarted;
    engine.registrationsCtl.add(
      const RegistrationEvent(RegistrationStatus.ok),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final conn = phone.connections.single;
    // Simula ring group 30011 con 3 interni in RING e trunk inbound.
    pbx.events!.add(
      jsonEncode({
        'type': 30011,
        'msg': {
          'call_id': 'rg-1',
          'members': [
            {
              'inbound': {
                'channel_id': 'ch-in',
                'member_status': 'ALERT',
                'from': '021234',
                'to': '6300',
              },
            },
            {
              'extension': {
                'channel_id': 'ch-301',
                'member_status': 'RING',
                'number': '301',
              },
            },
            {
              'extension': {
                'channel_id': 'ch-350',
                'member_status': 'RING',
                'number': '350',
              },
            },
          ],
        },
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(conn.extensionCalls.containsKey('301'), isTrue);
    expect(conn.extensionCalls.containsKey('350'), isTrue);

    // Il trunk chiude con BYE ma restano >1 interni in RING: la chiamata va rimossa subito!
    pbx.events!.add(
      jsonEncode({
        'type': 30011,
        'msg': {
          'call_id': 'rg-1',
          'members': [
            {
              'inbound': {
                'channel_id': 'ch-in',
                'member_status': 'BYE',
                'from': '021234',
                'to': '6300',
              },
            },
          ],
        },
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(conn.liveCalls.containsKey('rg-1'), isFalse);
    expect(conn.extensionCalls.containsKey('301'), isFalse);

    // Simula BLF SIP rimasto su ringing prima di uno snapshot call/query successivo:
    // _blfFresh lo riconcilia a idle invece di mostrarlo appeso su ringing.
    final ext301 = phone.allExtensions.firstWhere((e) => e.number == '301');
    engine.dialogsCtl.add(const BlfEvent('301@127.0.0.1', BlfStatus.ringing));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(phone.blfOf(ext301), BlfStatus.ringing);

    now = now.add(const Duration(seconds: 5));
    conn.lastCallsSnapshotAt = now;
    expect(phone.blfOf(ext301), BlfStatus.idle);
  });

  for (final brightness in Brightness.values) {
    testWidgets('CallWindow leggibile e senza overflow in tema ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        FlutterSecureStorage.setMockInitialValues({});
        final sep = Platform.pathSeparator;
        final dir = await Directory.systemTemp.createTemp('drin_s8_cw_');
        final engine = FakeSipEngine()
          ..nextAudioMetrics = const CallAudioMetrics(
            quality: 4.4,
            codec: 'PCMU/8kHz',
            downloadKbps: 64,
            uploadKbps: 64,
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
            id: 42,
            phase: CallPhase.active,
            direction: CallDirection.outgoing,
            remoteNumber: '6218',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 1100));

        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(brightness),
            home: Scaffold(
              body: Stack(children: [CallWindow(phone: phone)]),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('6218'), findsWidgets);
        expect(find.text('PCMU/8kHz'), findsOneWidget);
        expect(find.text('Termina'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await phone.shutdown();
        phone.dispose();
        await dir.delete(recursive: true);
      });
    });
  }
}
