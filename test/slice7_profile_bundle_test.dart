import 'dart:convert';
import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/contacts/personal_contacts.dart';
import 'package:drinphone/core/security/api_credential_store.dart';
import 'package:drinphone/core/security/cdr_db_store.dart';
import 'package:drinphone/core/security/profile_bundle.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/preferences/preferences_view.dart';
import 'package:drinphone/features/setup/account_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ProfileBundleCodec cifra, autentica, rifiuta passphrase errate e non logga segreti', () async {
    const bundle = ProfileBundle(
      name: 'Ufficio Napoli',
      kind: ProfileKind.yeastar,
      accounts: [
        SipAccount(
          id: 'main',
          pbxId: 'c1',
          username: '305',
          password: 'sip-secret-value',
          domain: 'pbx.example.com',
          transport: SipTransport.tls,
          turn: true,
          turnPassword: 'turn-secret-value',
        ),
      ],
      pbx: [
        ExportedPbxConnection(
          oldId: 'c1',
          label: 'Sede',
          realtime: true,
          apiCreds: ApiCredentials(
            baseUrl: 'https://pbx.example.com',
            clientId: 'client-id-secret',
            clientSecret: 'client-secret-value',
            ownExtension: '305',
          ),
          cdrCreds: CdrDbCredentials(
            host: '10.0.0.5',
            user: 'cdr_user',
            password: 'db-secret-value',
            wholePbx: true,
          ),
        ),
      ],
      favorites: ['c1:301'],
      personalContacts: [
        PersonalContact(id: 'p1', name: 'Mario', numbers: [('Cellulare', '333111222')]),
      ],
      crmUrlTemplate: 'https://crm.example.com?q={number}',
    );

    // Non deve stampare segreti nel toString().
    expect(bundle.toString(), isNot(contains('secret')));

    // Passphrase corta rifiutata.
    await expectLater(
      ProfileBundleCodec.seal(bundle, 'short', iterations: 10000),
      throwsArgumentError,
    );

    final raw = await ProfileBundleCodec.seal(
      bundle,
      'SuperPassphrase!2026',
      iterations: 10000,
    );
    expect(raw, isNot(contains('sip-secret-value')));
    expect(raw, isNot(contains('client-secret-value')));
    expect(raw, isNot(contains('db-secret-value')));

    // Passphrase errata -> FormatException.
    await expectLater(
      ProfileBundleCodec.open(raw, 'WrongPassphrase!'),
      throwsFormatException,
    );

    // Manomissione ciphertext -> FormatException.
    final tampered = jsonDecode(raw) as Map<String, dynamic>;
    final ct = base64Decode(tampered['ciphertext'] as String);
    ct[0] ^= 0xFF;
    tampered['ciphertext'] = base64Encode(ct);
    await expectLater(
      ProfileBundleCodec.open(jsonEncode(tampered), 'SuperPassphrase!2026'),
      throwsFormatException,
    );

    // Apertura valida.
    final opened = await ProfileBundleCodec.open(raw, 'SuperPassphrase!2026');
    expect(opened.name, 'Ufficio Napoli');
    expect(opened.accounts.single.password, 'sip-secret-value');
    expect(opened.accounts.single.turnPassword, 'turn-secret-value');
    expect(opened.pbx.single.apiCreds?.clientSecret, 'client-secret-value');
    expect(opened.pbx.single.cdrCreds?.password, 'db-secret-value');
    expect(opened.personalContacts.single.name, 'Mario');
    expect(opened.crmUrlTemplate, 'https://crm.example.com?q={number}');
  });

  test('PhoneController esporta da PC A e importa su PC B rimappando ID, preferiti e segreti', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final dirA = await Directory.systemTemp.createTemp('drin_s7_a_');
    final dirB = await Directory.systemTemp.createTemp('drin_s7_b_');
    addTearDown(() async {
      if (dirA.existsSync()) await dirA.delete(recursive: true);
      if (dirB.existsSync()) await dirB.delete(recursive: true);
    });

    final storeA = SettingsStore('${dirA.path}${Platform.pathSeparator}settings.json');
    await storeA.save(
      const Settings(
        profileId: 'profA',
        profileName: 'Econnet 305',
        profileKind: ProfileKind.yeastar,
        accounts: [
          SipAccount(
            id: 'main',
            pbxId: 'connOld',
            username: '305',
            password: 'pw-305',
            domain: 'sip.econnet.it',
          ),
        ],
        pbx: [PbxConnectionInfo('connOld', 'PBX Principale', realtime: true)],
        extensions: [Extension('Reception', '200')],
        favorites: ['connOld:200', ':201'],
        crmUrlTemplate: 'https://crm.econnet.it/find?n={number}',
      ),
    );
    final apiA = ApiCredentialStore('${dirA.path}${Platform.pathSeparator}api-connOld.bin');
    await apiA.save(
      const ApiCredentials(
        baseUrl: 'https://pbx.econnet.it',
        clientId: 'cidA',
        clientSecret: 'csecA',
        ownExtension: '305',
      ),
    );
    final cdrA = CdrDbStore('${dirA.path}${Platform.pathSeparator}cdr-connOld.bin');
    await cdrA.save(
      const CdrDbCredentials(
        host: '192.168.10.2',
        user: 'cdr',
        password: 'cdr-pw-A',
        wholePbx: true,
      ),
    );
    final contactsA = PersonalContactsStore('${dirA.path}${Platform.pathSeparator}contacts.json');
    await contactsA.save(const [
      PersonalContact(id: 'pc1', name: 'Cliente Uno', numbers: [('Ufficio', '081123456')]),
    ]);

    final phoneA = PhoneController(
      FakeSipEngine(),
      storeA,
      engineDataDir: dirA.path,
      logDir: dirA.path,
      apiStoreFor: (id) => ApiCredentialStore('${dirA.path}${Platform.pathSeparator}api-$id.bin'),
      cdrStoreFor: (id) => CdrDbStore('${dirA.path}${Platform.pathSeparator}cdr-$id.bin'),
      personalStoreFor: (_) => contactsA,
    );
    await phoneA.init();

    // Esportazione senza segreti -> password e credenziali assenti.
    final noSecrets = await phoneA.exportProfileBundle(
      'PassphraseSafe!1',
      includeSipPassword: false,
      includePbxSecrets: false,
      includeContacts: false,
      iterations: 10000,
    );
    final openNoSec = await ProfileBundleCodec.open(noSecrets, 'PassphraseSafe!1');
    expect(openNoSec.accounts.single.password, isEmpty);
    expect(openNoSec.pbx.single.apiCreds, isNull);
    expect(openNoSec.pbx.single.cdrCreds, isNull);
    expect(openNoSec.personalContacts, isEmpty);

    // Esportazione completa.
    final full = await phoneA.exportProfileBundle('PassphraseSafe!1', iterations: 10000);
    await phoneA.shutdown();
    phoneA.dispose();

    // Importazione su PC B vuoto (con store mock separato).
    FlutterSecureStorage.setMockInitialValues({});
    final storeB = SettingsStore('${dirB.path}${Platform.pathSeparator}settings.json');
    final phoneB = PhoneController(
      FakeSipEngine(),
      storeB,
      engineDataDir: dirB.path,
      logDir: dirB.path,
      apiStoreFor: (id) => ApiCredentialStore('${dirB.path}${Platform.pathSeparator}api-$id.bin'),
      cdrStoreFor: (id) => CdrDbStore('${dirB.path}${Platform.pathSeparator}cdr-$id.bin'),
      personalStoreFor: (id) => PersonalContactsStore('${dirB.path}${Platform.pathSeparator}contacts-$id.json'),
    );
    await phoneB.init();
    expect(phoneB.needsSetup, isTrue);

    final imported = await phoneB.importProfileBundle(full, 'PassphraseSafe!1');
    expect(phoneB.settings.profiles.length, 1); // Sostituito placeholder vuoto.
    expect(imported.name, 'Econnet 305');
    expect(phoneB.loggedIn, isTrue);
    expect(phoneB.settings.account?.username, '305');
    expect(phoneB.settings.account?.password, 'pw-305');
    expect(phoneB.settings.pbx.length, 1);
    final newCid = phoneB.settings.pbx.single.id;
    expect(newCid, isNot('connOld'));
    expect(phoneB.settings.account?.pbxId, newCid);
    expect(phoneB.settings.favorites, ['$newCid:200', ':201']);
    expect(phoneB.personal.single.name, 'Cliente Uno');
    expect(phoneB.settings.crmUrlTemplate, 'https://crm.econnet.it/find?n={number}');

    final apiB = await ApiCredentialStore('${dirB.path}${Platform.pathSeparator}api-$newCid.bin').load();
    expect(apiB?.clientSecret, 'csecA');
    final cdrB = await CdrDbStore('${dirB.path}${Platform.pathSeparator}cdr-$newCid.bin').load();
    expect(cdrB?.password, 'cdr-pw-A');

    await phoneB.shutdown();
    phoneB.dispose();
  });

  testWidgets('AccountPicker e Preferenze espongono esportazione/importazione .drinprof', (
    tester,
  ) async {
    await tester.runAsync(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('drin_s7_ui_');
      final store = SettingsStore('${dir.path}${Platform.pathSeparator}settings.json');
      await store.save(
        const Settings(
          accounts: [SipAccount(username: '301', password: 'pw', domain: 'pbx.local')],
        ),
      );
      final phone = PhoneController(
        FakeSipEngine(),
        store,
        engineDataDir: dir.path,
        logDir: dir.path,
      );
      await phone.init();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: AccountPicker(phone: phone),
        ),
      );
      await tester.pump();
      expect(find.text('Importa (.drinprof)'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: PreferencesView(phone: phone, initialTab: 0),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Trasferimento e backup profilo'), findsOneWidget);
      expect(find.text('Esporta profilo (.drinprof)'), findsOneWidget);
      expect(find.text('Importa profilo (.drinprof)'), findsOneWidget);

      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });
}

