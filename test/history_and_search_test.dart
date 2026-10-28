import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/core/call_history.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

void main() {
  late Directory tmp;
  late FakeSipEngine engine;
  late PhoneController phone;
  late CallHistoryStore history;
  var attention = 0;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('drinphone_hist');
    final sep = Platform.pathSeparator;
    engine = FakeSipEngine();
    history = CallHistoryStore('${tmp.path}${sep}history.json');
    final settings = SettingsStore('${tmp.path}${sep}s.json');
    await settings.save(
      const Settings(
        extensions: [
          Extension('Paolo Guerra', '301'),
          Extension('Sala Riunioni', '210'),
        ],
      ),
    );
    attention = 0;
    phone = PhoneController(
      engine,
      settings,
      engineDataDir: tmp.path,
      logDir: tmp.path,
      historyStore: history,
      onIncomingCall: () => attention++,
    );
    await phone.init();
  });

  tearDown(() async {
    await phone.historySaved;
    await tmp.delete(recursive: true);
  });

  void ev(CallPhase phase, CallDirection dir, String n, [String name = '']) =>
      engine.callsCtl.add(
        CallEvent(
          phase: phase,
          direction: dir,
          remoteNumber: n,
          remoteName: name,
        ),
      );

  test('ricerca per nome o numero, senza distinzione maiuscole', () {
    phone.setQuery('paolo');
    expect(phone.visibleExtensions.map((e) => e.number), ['301']);
    phone.setQuery('21');
    expect(phone.visibleExtensions.map((e) => e.number), ['210']);
    phone.setQuery('');
    expect(phone.visibleExtensions.length, 2);
  });

  test(
    'entrante non risposta = persa; richiamo attenzione una volta',
    () async {
      ev(CallPhase.incoming, CallDirection.incoming, '350', 'Jack');
      ev(CallPhase.incoming, CallDirection.incoming, '350', 'Jack');
      ev(CallPhase.ended, CallDirection.incoming, '350');
      expect(attention, 1);
      final r = phone.history.single;
      expect((r.number, r.name, r.missed, r.seconds), ('350', 'Jack', true, 0));
      // Persistita su file e riletta.
      await phone.historySaved;
      expect((await history.load()).single.missed, isTrue);
    },
  );

  test('uscente risposta: non persa, più recenti in cima', () {
    ev(CallPhase.outgoing, CallDirection.outgoing, '301');
    ev(CallPhase.active, CallDirection.outgoing, '301');
    ev(CallPhase.ended, CallDirection.outgoing, '301');
    ev(CallPhase.outgoing, CallDirection.outgoing, '210');
    ev(CallPhase.error, CallDirection.outgoing, '210');
    expect(phone.history.map((r) => (r.number, r.answered)), [
      ('210', false),
      ('301', true),
    ]);
    expect(phone.history.any((r) => r.missed), isFalse);
    expect(attention, 0);
  });
}
