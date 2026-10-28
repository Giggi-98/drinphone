import 'dart:convert';
import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/core/pbx/pbx_connection.dart';
import 'package:drinphone/core/pbx/yeastar_api.dart';
import 'package:drinphone/core/security/api_credential_store.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

const _id = 'CLIENT-ID-123';
const _secret = 'CLIENT-SECRET-xyz';

/// Finto PBX Yeastar: registra le richieste e risponde come da documentazione.
class FakePbx {
  late HttpServer server;
  final requests = <HttpRequest>[];
  final bodies = <String>[];

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req);
      final body = await utf8.decoder.bind(req).join();
      bodies.add(body);
      Map<String, Object> reply;
      switch (req.uri.path) {
        case '/openapi/v1.0/get_token':
          final b = jsonDecode(body) as Map<String, dynamic>;
          reply = b['username'] == _id && b['password'] == _secret
              ? {
                  'errcode': 0,
                  'errmsg': 'SUCCESS',
                  'access_token_expire_time': 1800,
                  'access_token': 'AT1',
                  'refresh_token_expire_time': 86400,
                  'refresh_token': 'RT1',
                }
              : {'errcode': 10004, 'errmsg': 'FAILURE'};
        case '/openapi/v1.0/extension/list':
          final page = int.parse(req.uri.queryParameters['page']!);
          reply = {
            'errcode': 0,
            'errmsg': 'SUCCESS',
            'total_number': 3,
            'data': page == 1
                ? [
                    {
                      'id': 11,
                      'number': '301',
                      'caller_id_name': 'Paolo Guerra',
                      'presence_status': 'available',
                    },
                    {'id': 15, 'number': '305', 'caller_id_name': 'Giggi'},
                  ]
                : [
                    {
                      'id': 50,
                      'number': '350',
                      'caller_id_name': 'Jack Egards',
                      'email_addr': 'j@x.it',
                    },
                  ],
          };
        case '/openapi/v1.0/organization/list':
          reply = {
            'errcode': 0,
            'errmsg': 'SUCCESS',
            'organization_list': [
              {
                'id': 1,
                'name': 'Econnet',
                'parent_id': 0,
                'ext_list': [11, 15, 50],
                'children': [
                  {
                    'id': 2,
                    'name': 'Commerciale',
                    'parent_id': 1,
                    'ext_list': [11],
                  },
                ],
              },
            ],
          };
        case '/openapi/v1.0/del_token':
          reply = {'errcode': 0, 'errmsg': 'SUCCESS'};
        default:
          reply = {'errcode': 1, 'errmsg': 'FAILURE'};
      }
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(reply));
      await req.response.close();
    });
  }
}

void main() {
  late FakePbx pbx;
  late Directory tmp;

  setUp(() async {
    pbx = FakePbx();
    await pbx.start();
    tmp = await Directory.systemTemp.createTemp('drinphone_api');
  });

  tearDown(() async {
    await pbx.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  test('token, User-Agent, paginazione e revoca come da specifica', () async {
    final api = YeastarApi(
      ApiCredentials(
        baseUrl: pbx.baseUrl,
        clientId: _id,
        clientSecret: _secret,
      ),
    );
    await api.connect();
    final list = await api.listExtensions();
    await api.close();

    expect(list.map((e) => e.number), ['301', '305', '350']);
    expect(list.first.presence, 'available');
    final paths = pbx.requests.map((r) => r.uri.path).toList();
    expect(paths, [
      '/openapi/v1.0/get_token',
      '/openapi/v1.0/extension/list',
      '/openapi/v1.0/extension/list',
      '/openapi/v1.0/del_token',
    ]);
    expect(
      pbx.requests.every(
        (r) => r.headers.value('user-agent') == 'DrinPhone/0.1.0',
      ),
      isTrue,
    );
    expect(
      pbx.requests.first.uri.queryParameters,
      isNot(contains('access_token')),
    );
    expect(pbx.requests[1].uri.queryParameters['access_token'], 'AT1');
    expect(pbx.requests.last.uri.queryParameters['access_token'], 'AT1');
  });

  test(
    'credenziali errate: eccezione senza URL né token nel messaggio',
    () async {
      final api = YeastarApi(
        ApiCredentials(
          baseUrl: pbx.baseUrl,
          clientId: _id,
          clientSecret: 'sbagliato',
        ),
      );
      Object? err;
      try {
        await api.connect();
      } catch (e) {
        err = e;
      }
      expect(err, isA<YeastarApiException>());
      expect(
        '$err',
        allOf(
          contains('get_token'),
          isNot(contains('http')),
          isNot(contains(_secret)),
        ),
      );
      await api.close();
    },
  );

  test(
    'DPAPI: file senza ID/Secret in chiaro, illeggibile se manomesso',
    () async {
      final store = ApiCredentialStore(
        '${tmp.path}${Platform.pathSeparator}api.dpapi',
      );
      await store.save(
        ApiCredentials(
          baseUrl: 'https://pbx.test',
          clientId: _id,
          clientSecret: _secret,
        ),
      );
      final raw = await File(store.path).readAsString();
      expect(
        raw,
        allOf(
          isNot(contains(_id)),
          isNot(contains(_secret)),
          isNot(contains('pbx.test')),
        ),
      );
      final back = await store.load();
      expect(back!.clientSecret, _secret);

      // Sale diverso = entropia diversa: DPAPI rifiuta, load restituisce null.
      final j = jsonDecode(raw) as Map<String, dynamic>;
      j['salt'] = base64Encode(List.filled(32, 7));
      await File(store.path).writeAsString(jsonEncode(j));
      expect(await store.load(), isNull);
    },
    skip: !Platform.isWindows,
  );

  Future<PhoneController> controllerWith(
    FakeSipEngine engine,
    Map<String, String> pbxUrls,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final sep = Platform.pathSeparator;
    ApiCredentialStore storeFor(String id) =>
        ApiCredentialStore('${tmp.path}${sep}api-$id.dpapi');
    for (final e in pbxUrls.entries) {
      await storeFor(e.key).save(
        ApiCredentials(baseUrl: e.value, clientId: _id, clientSecret: _secret),
      );
    }
    final settings = SettingsStore('${tmp.path}${sep}s.json');
    await settings.save(
      Settings(
        account: const SipAccount(
          username: '305',
          password: 'p',
          domain: '127.0.0.1',
        ),
        extensions: const [
          Extension('Manuale', '400'),
          Extension('Doppione', '301'),
        ],
        pbx: [for (final id in pbxUrls.keys) PbxConnectionInfo(id, 'PBX $id')],
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
    return phone;
  }

  test(
    'controller: interni dal PBX uniti ai manuali, senza il proprio, in BLF',
    () async {
      final engine = FakeSipEngine();
      final phone = await controllerWith(engine, {'a': pbx.baseUrl});
      final conn = phone.connections.single;

      expect(conn.status, 'Sincronizzata · 3 interni, 2 reparti');
      expect(phone.allExtensions.map((e) => e.number), ['400', '301', '350']);
      expect(phone.isManual(phone.allExtensions.first), isTrue);
      expect(phone.isManual(phone.allExtensions.last), isFalse);
      expect(conn.orgs.map((o) => (o.name, o.depth, o.parentId)), [
        ('Econnet', 0, 0),
        ('Commerciale', 1, 1),
      ]);
      expect(phone.presenceOf(phone.allExtensions[1]), 'available');

      phone.selectGroup('a:2');
      expect(phone.visibleExtensions.map((e) => e.number), ['301']);
      phone.selectGroup(null);
      expect(phone.visibleExtensions.length, 3);

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      expect(engine.watched, {'400', '301', '350'});
      await phone.shutdown();
      expect(pbx.requests.last.uri.path, '/openapi/v1.0/del_token');
    },
    skip: !Platform.isWindows,
  );

  test(
    'sync: senza modifiche nessun cambio segnalato, gli id persistono',
    () async {
      final phone = await controllerWith(FakeSipEngine(), {'a': pbx.baseUrl});
      final conn = phone.connections.single;
      final before = pbx.requests.length;
      final changes = <bool>[];
      final probe = PbxConnection(
        id: 'probe',
        label: 'x',
        store: conn.store,
        apiFactory: YeastarApi.new,
        onUpdate: (_, changed) => changes.add(changed),
      );
      await probe.start();
      expect(changes.last, isTrue); // prima lettura
      await probe.sync(force: true);
      expect(changes.last, isFalse); // stessi dati: niente riallineamenti
      await probe.sync(); // < 10 s dall'ultima: saltata
      expect(pbx.requests.length - before, greaterThan(0));
      await probe.stop();
      await phone.shutdown();
    },
    skip: !Platform.isWindows,
  );

  test(
    'multi-PBX: interni di un PBX senza account SIP visibili ma non chiamabili',
    () async {
      final other = FakePbx();
      await other.start();
      final engine = FakeSipEngine();
      // 'a' ha host 127.0.0.1 = dominio SIP: è il PBX dell'account.
      final phone = await controllerWith(engine, {
        'a': pbx.baseUrl,
        'b': other.baseUrl.replaceFirst('127.0.0.1', 'localhost'),
      });
      expect(phone.primaryConnection!.id, 'a');
      final fromB = phone.allExtensions.where((e) => e.source == 'b').toList();
      expect(fromB.map((e) => e.number), ['301', '305', '350']);
      expect(fromB.every((e) => !phone.isCallable(e)), isTrue);
      phone.selectGroup('b');
      expect(phone.visibleExtensions.every((e) => e.source == 'b'), isTrue);

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      // BLF solo per manuali + PBX dell'account (numeri, senza il proprio 305).
      expect(engine.watched, {'400', '301', '350'});
      await phone.shutdown();
      await other.server.close(force: true);
    },
    skip: !Platform.isWindows,
  );

  test('migrazione da connessione singola: credenziali e interni manuali conservati', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final sep = Platform.pathSeparator;
    ApiCredentialStore storeFor(String id) =>
        ApiCredentialStore('${tmp.path}${sep}api-$id.dpapi');
    await storeFor(PhoneController.legacyConnectionId).save(
      ApiCredentials(
        baseUrl: pbx.baseUrl,
        clientId: _id,
        clientSecret: _secret,
      ),
    );
    final settings = SettingsStore('${tmp.path}${sep}s.json');
    await settings.save(
      const Settings(extensions: [Extension('Manuale', '400')]),
    );
    final phone = PhoneController(
      FakeSipEngine(),
      settings,
      engineDataDir: tmp.path,
      logDir: tmp.path,
      apiStoreFor: storeFor,
    );
    await phone.init();
    expect(phone.connections.single.id, 'default');
    final saved = await settings.load();
    expect(saved.pbx.single.id, 'default');
    expect(saved.extensions.single.number, '400');
    await phone.shutdown();
  }, skip: !Platform.isWindows);
}
