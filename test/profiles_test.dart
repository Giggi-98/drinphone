import 'dart:convert';
import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/core/call_history.dart';
import 'package:drinphone/core/contacts/personal_contacts.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

void main() {
  late Directory tmp;
  late String path;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('drinphone_prof');
    path = '${tmp.path}${Platform.pathSeparator}settings.json';
  });
  tearDown(() => tmp.delete(recursive: true));

  test(
    'file senza profili: migrato in un profilo Yeastar, password conservata',
    () async {
      FlutterSecureStorage.setMockInitialValues({'sip_password': 's3greta!'});
      await File(path).writeAsString(
        jsonEncode({
          'accounts': [
            {'id': 'main', 'username': '305', 'domain': 'drin.ras.yeastar.com'},
          ],
          'extensions': [
            {'name': 'Sala', 'number': '300'},
          ],
          'pbx': [
            {'id': 'default', 'label': 'PBX', 'realtime': true},
          ],
          'favorites': [':301'],
          'lang': 'en',
        }),
      );
      final store = SettingsStore(path);
      final s = await store.load();
      expect(s.profileId, Settings.defaultProfileId);
      expect(s.profileKind, ProfileKind.yeastar);
      expect(s.profileName, 'Econnet');
      expect(s.account!.password, 's3greta!');
      expect(s.pbx.single.realtime, isTrue);
      expect(s.favorites, [':301']);
      expect(s.lang, 'en');

      await store.save(s);
      // Copia del file vecchio, una sola volta.
      final backup = File(path.replaceFirst('.json', '.v1.json'));
      expect(await backup.readAsString(), contains('"accounts"'));
      final j = jsonDecode(await File(path).readAsString()) as Map;
      expect(j['activeProfile'], 'default');
      expect((j['profiles'] as List).single['extensions'], [
        {'name': 'Sala', 'number': '300'},
      ]);
      expect(await File(path).readAsString(), isNot(contains('s3greta!')));
      final again = await store.load();
      expect(again.account!.password, 's3greta!');
      expect(again.extensions.single.number, '300');
    },
  );

  test('file senza profili e senza API: profilo SIP generico', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await File(path).writeAsString(
      jsonEncode({
        'account': {'username': '100', 'domain': 'pbx.example.com'},
      }),
    );
    final s = await SettingsStore(path).load();
    expect(s.profileKind, ProfileKind.sip);
    expect(s.account!.username, '100');
  });

  test(
    'due profili: cambio, password del profilo non attivo conservate',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SettingsStore(path);
      const s = Settings(
        profileName: 'Econnet',
        accounts: [
          SipAccount(username: '305', password: 'uno', domain: 'a.example'),
        ],
        others: [
          Profile(
            id: 'p2',
            name: 'Trunk',
            kind: ProfileKind.sip,
            accounts: [
              SipAccount(
                id: 'b2',
                username: '0612345',
                password: 'due',
                domain: 'voip.example',
              ),
            ],
            extensions: [Extension('Casa', '200')],
          ),
        ],
      );
      await store.save(s);
      var loaded = await store.load();
      expect(loaded.profileName, 'Econnet');
      expect(loaded.others.single.accounts.single.password, 'due');

      await store.save(loaded.switchTo('p2'));
      loaded = await store.load();
      expect(loaded.profileId, 'p2');
      expect(loaded.profileKind, ProfileKind.sip);
      expect(loaded.extensions.single.name, 'Casa');
      expect(loaded.account!.password, 'due');
      // Il profilo lasciato tiene la sua password.
      expect(loaded.others.single.accounts.single.password, 'uno');
      expect(loaded.profiles.map((p) => p.name), ['Econnet', 'Trunk']);
    },
  );

  test('controller: nuovo profilo, cambio, eliminazione con pulizia', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final sep = Platform.pathSeparator;
    final store = SettingsStore(path);
    await store.save(
      const Settings(
        profileName: 'Econnet',
        accounts: [
          SipAccount(username: '305', password: 'uno', domain: 'a.test'),
        ],
      ),
    );
    final engine = FakeSipEngine();
    String hist(String id) => '${tmp.path}${sep}history-$id.json';
    final phone = PhoneController(
      engine,
      store,
      engineDataDir: tmp.path,
      logDir: tmp.path,
      historyStoreFor: (id) => CallHistoryStore(hist(id)),
      personalStoreFor: (id) =>
          PersonalContactsStore('${tmp.path}${sep}contacts-$id.json'),
    );
    await phone.init();
    expect(phone.needsSetup, isFalse);
    expect(engine.accounts.single.username, '305');

    expect(await phone.createProfile('Trunk', ProfileKind.sip), isTrue);
    final trunk = phone.settings.profileId;
    expect(phone.isYeastar, isFalse);
    expect(engine.accounts, isEmpty);
    await phone.saveAccount(
      SipAccount(
        id: phone.newAccountId(),
        username: '0612345',
        password: 'due',
        domain: 'voip.test',
      ),
    );
    // Id diverso da `main`, che è già del profilo Econnet.
    expect(phone.settings.account!.id, isNot('main'));
    await phone.savePersonal(
      const PersonalContact(id: 'x', name: 'Casa', numbers: [('Casa', '06 1')]),
    );

    expect(await phone.switchProfile('default'), isTrue);
    expect(engine.accounts.single.username, '305');
    expect(phone.personal, isEmpty);
    expect(phone.settings.others.single.name, 'Trunk');

    await phone.deleteProfile(trunk);
    expect(phone.settings.others, isEmpty);
    expect(File('${tmp.path}${sep}contacts-$trunk.json').existsSync(), isFalse);
    final reloaded = await store.load();
    expect(reloaded.allAccounts.map((a) => a.password), ['uno']);
    await phone.shutdown();
  });
}
