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
      await phone.saveAccount(_account);
      await phone.setDebugLog(true);
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
    await phone.saveAccount(_account);
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
    await phone.saveAccount(_account);
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
      await phone.saveAccount(_account);
      await phone.addExtension(const Extension('Paolo', '301'));
      expect(engine.watched, isEmpty); // account non ancora registrato
      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      expect(engine.watched, {'301@pbx.test'});

      engine.dialogsCtl.add(const BlfEvent('301@pbx.test', BlfStatus.busy));
      expect(phone.blfOf(phone.settings.extensions.first), BlfStatus.busy);

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.failed),
      );
      expect(phone.blf, isEmpty);

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      await phone.addExtension(const Extension('Sala', '300'));
      expect(engine.watched, {'301@pbx.test', '300@pbx.test'});
      await phone.removeExtension(phone.settings.extensions.first);
      expect(engine.watched, {'300@pbx.test'});
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
    expect(engine.log, contains('answer 0'));
  });

  test(
    'più account: password separate, chiamata via account del PBX',
    () async {
      const second = SipAccount(
        id: 'b2',
        username: '401',
        password: 'altra!',
        domain: 'pbx2.test',
      );
      await phone.saveAccount(_account);
      await phone.saveAccount(second);
      expect(engine.accounts.map((a) => a.id), ['main', 'b2']);
      final reloaded = await store.load();
      expect(reloaded.accounts.map((a) => a.password), ['s3greta!', 'altra!']);
      expect(await File(store.path).readAsString(), isNot(contains('altra!')));

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok, '', 'b2'),
      );
      // Interno manuale = PBX principale: si chiama senza account esplicito.
      await phone.dial('300', via: const Extension('Sala', '300'));
      expect(engine.log.last, 'dial 300');

      // "Chiama con": i numeri liberi passano dall'account scelto, salvato.
      await phone.setCallWith('b2');
      await phone.dial('0612345');
      expect(engine.log.last, 'dial 0612345 via b2');
      expect((await store.load()).callWith, 'b2');

      await phone.removeAccount('b2');
      // Account tolto: si torna al principale.
      expect(phone.outgoingAccount?.id, 'main');
      expect((await store.load()).accounts.single.id, 'main');
    },
  );
}
