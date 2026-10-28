import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

const _account = SipAccount(
  username: '201',
  password: 's3greta!',
  domain: 'pbx.test',
  displayName: 'Prova',
);

void main() {
  late Directory tmp;
  late FakeSipEngine engine;
  late SettingsStore store;
  late PhoneController phone;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('drinphone_test');
    engine = FakeSipEngine();
    store = SettingsStore('${tmp.path}${Platform.pathSeparator}settings.json');
    phone = PhoneController(
      engine,
      store,
      engineDataDir: tmp.path,
      logDir: tmp.path,
    );
    await phone.init();
  });

  tearDown(() => tmp.delete(recursive: true));

  test(
    'la password va nello storage sicuro, non nel file impostazioni',
    () async {
      await phone.saveAccount(_account, debugLog: true);
      final json = await File(store.path).readAsString();
      expect(json, isNot(contains(_account.password)));
      expect(json, contains('pbx.test'));
      final reloaded = await store.load();
      expect(reloaded.account!.password, _account.password);
      expect(reloaded.debugLog, isTrue);
      expect(engine.registered!.username, '201');
    },
  );

  test('SipAccount.toString non espone la password', () {
    expect('$_account', isNot(contains(_account.password)));
  });

  test('si compone solo da registrato e senza chiamate in corso', () async {
    await phone.dial('202');
    expect(engine.log, isNot(contains('dial 202')));

    engine.registrationsCtl.add(const RegistrationEvent(RegistrationStatus.ok));
    await phone.dial('202');
    expect(engine.log, contains('dial 202'));

    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.outgoing,
        direction: CallDirection.outgoing,
        remoteNumber: '202',
      ),
    );
    expect(phone.canDial, isFalse);
    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.active,
        direction: CallDirection.outgoing,
        remoteNumber: '202',
      ),
    );
    expect(phone.callConnectedAt, isNotNull);
    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.ended,
        direction: CallDirection.outgoing,
        remoteNumber: '202',
      ),
    );
    expect(phone.call, isNull);
    expect(phone.canDial, isTrue);
  });

  test('errore di chiamata produce un avviso e resetta il muto', () async {
    engine.registrationsCtl.add(const RegistrationEvent(RegistrationStatus.ok));
    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.active,
        direction: CallDirection.incoming,
        remoteNumber: '300',
      ),
    );
    await phone.toggleMute();
    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.error,
        direction: CallDirection.incoming,
        remoteNumber: '300',
        message: 'Busy',
      ),
    );
    expect(phone.notice, contains('Busy'));
    expect(phone.muted, isFalse);
    expect(engine.log, contains('mute false'));
  });

  test(
    'BLF: sottoscrive gli interni da registrato, sconosciuto se cade',
    () async {
      await phone.addExtension(const Extension('Paolo', '301'));
      expect(engine.watched, isEmpty);
      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      expect(engine.watched, {'301'});

      engine.dialogsCtl.add(const BlfEvent('301', BlfStatus.busy));
      expect(phone.blf['301']!.status, BlfStatus.busy);

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.failed),
      );
      expect(phone.blf, isEmpty);

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      await phone.addExtension(const Extension('Sala', '300'));
      expect(engine.watched, {'301', '300'});
      await phone.removeExtension(phone.settings.extensions.first);
      expect(engine.watched, {'300'});
    },
  );

  testWidgets('chiamata in arrivo mostra Rispondi e Rifiuta', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(DrinPhoneApp(phone: phone));
    expect(find.text('Nessun account SIP configurato.'), findsOneWidget);

    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.incoming,
        direction: CallDirection.incoming,
        remoteNumber: '205',
        remoteName: 'Magazzino',
      ),
    );
    await tester.pump();
    expect(find.text('Chiamata in arrivo'), findsOneWidget);
    await tester.tap(find.text('Rispondi'));
    expect(engine.log, contains('answer'));
  });
}
