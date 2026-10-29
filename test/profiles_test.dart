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
    await phone.addExtension(const Extension('Sala', '300'));
    engine.dialogsCtl.add(const BlfEvent('300@a.test', BlfStatus.busy));

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

    expect(await phone.login('default'), isTrue);
    expect(engine.accounts.single.username, '305');
    // BLF: tornando al profilo, l'ultimo stato resta "da confermare".
    const sala = Extension('Sala', '300');
    expect(phone.blfStale(sala), isTrue);
    expect(phone.blfOf(sala), BlfStatus.busy);
    engine.dialogsCtl.add(const BlfEvent('300@a.test', BlfStatus.idle));
    expect(phone.blfStale(sala), isFalse);
    expect(phone.blfOf(sala), BlfStatus.idle);
    expect(phone.personal, isEmpty);
    expect(phone.settings.others.single.name, 'Trunk');

    await phone.deleteProfile(trunk);
    expect(phone.settings.others, isEmpty);
    expect(File('${tmp.path}${sep}contacts-$trunk.json').existsSync(), isFalse);
    final reloaded = await store.load();
    expect(reloaded.allAccounts.map((a) => a.password), ['uno']);
    await phone.shutdown();
  });

  test(
    'avvio: più account senza predefinito → scelta; logout e rientro',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SettingsStore(path);
      await store.save(
        const Settings(
          profileName: 'Uno',
          accounts: [
            SipAccount(username: '305', password: 'p', domain: 'a.test'),
          ],
          others: [
            Profile(
              id: 'p2',
              name: 'Due',
              accounts: [
                SipAccount(
                  id: 'b2',
                  username: '902',
                  password: 'q',
                  domain: 'b.test',
                ),
              ],
            ),
          ],
        ),
      );
      var engine = FakeSipEngine();
      var phone = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await phone.init();
      expect(phone.loggedIn, isFalse);
      expect(engine.accounts, isEmpty);

      expect(await phone.login('p2'), isTrue);
      expect(engine.accounts.single.username, '902');
      await phone.setDefaultAccount('p2');
      expect(await phone.logout(), isTrue);
      expect(phone.loggedIn, isFalse);
      // Logout = nessuna registrazione viva.
      expect(engine.accounts, isEmpty);
      await phone.shutdown();

      // Riavvio: si rientra nel predefinito.
      engine = FakeSipEngine();
      phone = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await phone.init();
      expect(phone.loggedIn, isTrue);
      expect(phone.settings.profileId, 'p2');
      expect(engine.accounts.single.username, '902');
      await phone.shutdown();
    },
  );

  test('un solo account: si entra sempre, anche senza predefinito', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SettingsStore(path);
    await store.save(
      const Settings(
        accounts: [
          SipAccount(username: '305', password: 'p', domain: 'a.test'),
        ],
      ),
    );
    final engine = FakeSipEngine();
    final phone = PhoneController(
      engine,
      store,
      engineDataDir: tmp.path,
      logDir: tmp.path,
    );
    await phone.init();
    expect(phone.loggedIn, isTrue);
    expect(engine.accounts.single.username, '305');
    await phone.shutdown();
  });

  test(
    'profilo con due interni: diviso in due account, contatti copiati',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final sep = Platform.pathSeparator;
      final store = SettingsStore(path);
      await store.save(
        const Settings(
          profileName: 'Econnet',
          accounts: [
            SipAccount(username: '305', password: 'uno', domain: 'drin.test'),
            SipAccount(
              id: 'b2',
              username: '902',
              password: 'due',
              domain: 'me.test',
            ),
          ],
          pbx: [
            PbxConnectionInfo('default', 'Skillworks'),
            PbxConnectionInfo('c2', 'Cloud Me'),
          ],
          favorites: [':300', 'default:301', 'c2:401'],
        ),
      );
      String contacts(String id) => '${tmp.path}${sep}contacts-$id.json';
      await PersonalContactsStore(contacts('default')).save(const [
        PersonalContact(id: 'x', name: 'Casa', numbers: [('Casa', '06 1')]),
      ]);
      final engine = FakeSipEngine();
      final phone = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
        personalStoreFor: (id) => PersonalContactsStore(contacts(id)),
      );
      await phone.init();
      final all = phone.settings.profiles;
      expect(all.length, 2);
      expect(
        all.every((p) => p.accounts.length == 1 && p.pbx.length == 1),
        isTrue,
      );
      final first = all.firstWhere((p) => p.id == 'default');
      final second = all.firstWhere((p) => p.id != 'default');
      expect(first.name, '305 · Skillworks');
      expect(first.favorites, [':300', 'default:301']);
      expect(second.name, '902 · Cloud Me');
      expect(second.pbx.single.id, 'c2');
      expect(second.favorites, ['c2:401']);
      // Due account, nessun predefinito: si sceglie.
      expect(phone.loggedIn, isFalse);
      expect(
        (await PersonalContactsStore(contacts(second.id)).load()).single.name,
        'Casa',
      );
      final reloaded = await store.load();
      expect(reloaded.allAccounts.map((a) => a.password).toSet(), {
        'uno',
        'due',
      });
      await phone.shutdown();
    },
  );

  test(
    'account avanzato e opzioni globali: salvati, TURN nello storage sicuro',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SettingsStore(path);
      await store.save(
        const Settings(
          callOptions: CallOptions(
            encryption: MediaEncryption.srtp,
            encryptionMandatory: true,
            keepAlive: false,
            dtmfInfo: true,
          ),
          accounts: [
            SipAccount(
              username: '705',
              password: 'p',
              domain: 'me.drin.cloud',
              proxy: 'sbc.drin.cloud:5060',
              registrar: 'reg.drin.cloud',
              authUser: 'auth705',
              realm: 'drin',
              expires: 300,
              registerEnabled: false,
              hideCallerId: true,
              voicemailCode: '*97',
              stunServer: 'stun.drin.cloud:3478',
              ice: true,
              turn: true,
              turnUser: 'tu',
              turnPassword: 'turn-secret',
            ),
          ],
        ),
      );
      expect(await File(path).readAsString(), isNot(contains('turn-secret')));
      var s = await store.load();
      final a = s.account!;
      expect(
        [
          a.proxy,
          a.registrar,
          a.authUser,
          a.realm,
          a.voicemailCode,
          a.stunServer,
          a.turnUser,
        ],
        [
          'sbc.drin.cloud:5060',
          'reg.drin.cloud',
          'auth705',
          'drin',
          '*97',
          'stun.drin.cloud:3478',
          'tu',
        ],
      );
      expect(
        [a.expires, a.registerEnabled, a.hideCallerId, a.ice, a.turn],
        [300, false, true, true, true],
      );
      expect(a.turnPassword, 'turn-secret');
      expect(s.callOptions.encryption, MediaEncryption.srtp);
      expect(s.callOptions.encryptionMandatory, isTrue);
      expect(s.callOptions.keepAlive, isFalse);
      expect(s.callOptions.dtmfInfo, isTrue);

      final engine = FakeSipEngine();
      final phone = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await phone.init();
      expect(engine.options.encryption, MediaEncryption.srtp);
      // Account eliminato: via anche la password TURN.
      await phone.logout();
      await phone.deleteProfile('default');
      s = await store.load();
      expect(s.allAccounts, isEmpty);
      await store.save(
        const Settings(
          accounts: [
            SipAccount(username: '705', password: 'p', domain: 'x', turn: true),
          ],
        ),
      );
      expect((await store.load()).account!.turnPassword, '');
      await phone.shutdown();
    },
  );
}
