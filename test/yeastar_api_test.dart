import 'dart:convert';
import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/core/pbx/pbx_cache.dart';
import 'package:drinphone/core/pbx/pbx_connection.dart';
import 'package:drinphone/core/pbx/pbx_sync.dart';
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

  /// Ultimo WebSocket eventi aperto dal client e messaggi ricevuti.
  WebSocket? events;
  final eventMessages = <String>[];

  /// Risposte di call/query per tipo; null = errore (PBX senza la funzione).
  Map<String, List<Map<String, Object>>>? calls;

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/openapi/v1.0/subscribe' &&
          WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        events = ws;
        ws.listen((m) {
          eventMessages.add('$m');
          if ('$m'.contains('topic_list')) {
            ws.add(jsonEncode({'errcode': 0, 'errmsg': 'SUCCESS'}));
          }
        });
        return;
      }
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
        case '/openapi/v1.0/company_contact/list':
          reply = {
            'errcode': 0,
            'errmsg': 'SUCCESS',
            'total_number': 1,
            'data': [
              {
                'id': 7,
                'contact_name': 'Mario Rossi',
                'company': 'Fornitore Srl',
                'business': '02 5550 1234',
                'mobile': '',
                'business_fax': '02 5550 9999',
                'phonebook_list': [
                  {'id': 1, 'name': 'Fornitori'},
                ],
              },
            ],
          };
        case '/openapi/v1.0/call/query' when calls != null:
          reply = {
            'errcode': 0,
            'errmsg': 'SUCCESS',
            'data': calls![req.uri.queryParameters['type']] ?? const [],
          };
        case '/openapi/v1.0/extension/get':
          reply = {
            'errcode': 0,
            'errmsg': 'SUCCESS',
            'data': {
              'id': 15,
              'number': '305',
              'presence_status': 'available',
              'custom_presence_status': 'Ufficio',
              'enb_vm': 1,
              'enb_vm_pin': 1,
              'vm_pin': '6666',
              'new_vm_notification': 'with_attach',
              'vm_after_notification': 'mark_read',
              'reg_password': 'segreta',
              'enb_all_busy_mode_for_endpoints': 1,
              'presence_list': [
                {
                  'status': 'available',
                  'enb_in_always_forward': 0,
                  'ring_timeout': 60,
                  'enb_ring_mobile': 0,
                  'enb_accept_call_from_rg': 1,
                },
                {
                  'status': 'off_work',
                  'enb_ex_always_forward': 1,
                  'ex_always_forward_dest': 'extension',
                  'ex_always_forward_value': '11',
                  'enb_in_busy_forward': 1,
                  'in_busy_forward_dest': 'ext_vm',
                },
              ],
            },
          };
        case '/openapi/v1.0/extension/update':
          reply = {'errcode': 0, 'errmsg': 'SUCCESS'};
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
    Map<String, String> pbxUrls, {
    PbxCache Function(String id)? cacheFor,
    Map<String, int> sync = const {},
  }) async {
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
        accounts: const [
          SipAccount(username: '305', password: 'p', domain: '127.0.0.1'),
        ],
        extensions: const [
          Extension('Manuale', '400'),
          Extension('Doppione', '301'),
        ],
        pbx: [
          for (final id in pbxUrls.keys)
            PbxConnectionInfo(id, 'PBX $id', sync: sync),
        ],
      ),
    );
    final phone = PhoneController(
      engine,
      settings,
      engineDataDir: tmp.path,
      logDir: tmp.path,
      apiStoreFor: storeFor,
      cacheFor: cacheFor,
    );
    await phone.init();
    await phone.connectionsStarted;
    return phone;
  }

  test('cache dati PBX: cifrata su disco, mostrata subito anche a PBX irraggiungibile', () async {
    final sep = Platform.pathSeparator;
    final path = '${tmp.path}${sep}cache-a.dpapi';
    PbxCache cacheFor(String id) => PbxCache(path);
    var phone = await controllerWith(FakeSipEngine(), {
      'a': pbx.baseUrl,
    }, cacheFor: cacheFor);
    for (var i = 0; i < 50 && !File(path).existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await phone.shutdown();
    // Nomi di interni e contatti mai in chiaro.
    final raw = await File(path).readAsString();
    expect(raw, isNot(contains('Paolo Guerra')));
    expect(raw, isNot(contains('Mario')));

    // Secondo avvio con il PBX giù: dati della volta scorsa a schermo.
    phone = await controllerWith(FakeSipEngine(), {
      'a': 'http://127.0.0.1:1',
    }, cacheFor: cacheFor);
    final conn = phone.connections.single;
    expect(conn.ok, isFalse);
    expect(conn.directory.map((e) => e.number), contains('301'));
    expect(conn.orgs.length, 2);
    expect(conn.contacts.single.numbers, [('Ufficio', '02 5550 1234')]);
    await phone.shutdown();
  }, skip: !Platform.isWindows);

  test(
    'accesso con cache fresca: rubrica non riscaricata, sì con Sincronizza ora',
    () async {
      final sep = Platform.pathSeparator;
      final path = '${tmp.path}${sep}cache-a.dpapi';
      PbxCache cacheFor(String id) => PbxCache(path);
      int contactReads() => pbx.requests
          .where((r) => r.uri.path.endsWith('company_contact/list'))
          .length;
      final base = contactReads();
      var phone = await controllerWith(FakeSipEngine(), {
        'a': pbx.baseUrl,
      }, cacheFor: cacheFor);
      for (var i = 0; i < 50 && !File(path).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await phone.shutdown();
      expect(contactReads() - base, 1);

      phone = await controllerWith(FakeSipEngine(), {
        'a': pbx.baseUrl,
      }, cacheFor: cacheFor);
      final conn = phone.connections.single;
      expect(conn.ok, isTrue);
      expect(conn.contacts.single.name, 'Mario Rossi');
      expect(contactReads() - base, 1);

      await phone.resync();
      expect(contactReads() - base, 2);
      await phone.shutdown();
      await cacheFor('a').saved;
    },
    skip: !Platform.isWindows,
  );

  test('sincronizzazione: voci spente mai lette, scelte salvate', () async {
    int reads(String path) =>
        pbx.requests.where((r) => r.uri.path.endsWith(path)).length;
    final contacts0 = reads('company_contact/list');
    final vm0 = reads('vm/get');
    final ext0 = reads('extension/list');
    final phone = await controllerWith(
      FakeSipEngine(),
      {'a': pbx.baseUrl},
      sync: {'contacts': 0, 'voicemail': 0, 'extensions': 0, 'bogus': 5},
    );
    final conn = phone.connections.single;
    expect(conn.ok, isTrue);
    expect(reads('company_contact/list') - contacts0, 0);
    expect(reads('vm/get') - vm0, 0);
    // Gli interni non si spengono: 0 = predefinito.
    expect(reads('extension/list') - ext0, greaterThan(0));
    expect(conn.every(PbxSync.extensions), PbxSync.extensions.byDefault);
    expect(conn.every(PbxSync.orgs), PbxSync.orgs.byDefault);

    // "Sincronizza ora" rispetta le voci spente.
    await phone.resync();
    expect(reads('company_contact/list') - contacts0, 0);

    // Riaccesa: letta subito e salvata in settings.json.
    await phone.setSyncEvery(conn, PbxSync.contacts, const Duration(hours: 24));
    for (var i = 0; i < 50 && conn.syncing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(reads('company_contact/list') - contacts0, 1);
    final saved = await SettingsStore(
      '${tmp.path}${Platform.pathSeparator}s.json',
    ).load();
    expect(saved.pbx.single.sync['contacts'], 86400);
    expect(saved.pbx.single.sync['voicemail'], 0);
    await phone.shutdown();
  });

  test(
    'controller: interni dal PBX uniti ai manuali, senza il proprio, in BLF',
    () async {
      final engine = FakeSipEngine();
      final phone = await controllerWith(engine, {'a': pbx.baseUrl});
      final conn = phone.connections.single;

      expect(conn.status, 'Sincronizzata · 3 interni, 2 reparti, 1 contatti');
      final mario = conn.contacts.single;
      expect(mario.numbers, [
        ('Ufficio', '02 5550 1234'),
      ]); // fax e vuoti esclusi
      expect(mario.phonebooks, ['Fornitori']);
      expect(phone.nameFor('+390255501234'), 'Mario Rossi');
      expect(phone.nameFor('350'), 'Jack Egards');
      expect(phone.contactsMatching('forn').single.$2.name, 'Mario Rossi');
      final hit = phone.search('mario').single;
      expect(
        (hit.name, hit.number, hit.label),
        ('Mario Rossi', '02 5550 1234', 'Ufficio'),
      );
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
      // Econnet include Commerciale (301): coi soli diretti il 301 sparisce.
      phone.selectGroup('a:1');
      expect(phone.visibleExtensions.map((e) => e.number), contains('301'));
      phone.setDirectMembersOnly(true);
      expect(
        phone.visibleExtensions.map((e) => e.number),
        isNot(contains('301')),
      );
      phone.setDirectMembersOnly(false);
      phone.selectGroup(null);
      expect(phone.visibleExtensions.length, 3);

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      expect(engine.watched, {
        '400@127.0.0.1',
        '301@127.0.0.1',
        '350@127.0.0.1',
      });
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
    'due PBX e un interno: resta solo il PBX dell’account (stesso host)',
    () async {
      final other = FakePbx();
      await other.start();
      final engine = FakeSipEngine();
      // 'a' ha host 127.0.0.1 = dominio SIP: è il PBX dell'account.
      final phone = await controllerWith(engine, {
        'a': pbx.baseUrl,
        'b': other.baseUrl.replaceFirst('127.0.0.1', 'localhost'),
      });
      // Un account vivo alla volta: la connessione senza interno resta fuori.
      expect(phone.connections.map((c) => c.id), ['a']);
      expect(phone.primaryConnection!.id, 'a');
      expect(phone.allExtensions.any((e) => e.source == 'b'), isFalse);

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      // BLF solo per manuali + PBX dell'account (numeri, senza il proprio 305).
      expect(engine.watched, {
        '400@127.0.0.1',
        '301@127.0.0.1',
        '350@127.0.0.1',
      });
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

  test('eventi WebSocket: sottoscrizione, 30008, presenza 30009, live calls 30011', () async {
    final phone = await controllerWith(FakeSipEngine(), {'a': pbx.baseUrl});
    final conn = phone.connections.single;
    await phone.setRealtime(conn, true);
    for (var i = 0; i < 50 && pbx.eventMessages.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(jsonDecode(pbx.eventMessages.first)['topic_list'], [
      30007,
      30008,
      30009,
      30011,
      30022,
    ]);
    pbx.events!.add(
      jsonEncode({
        'type': 30008,
        'sn': 'X',
        'msg': jsonEncode({'extension': '301', 'status': 'Ringing'}),
      }),
    );
    pbx.events!.add(
      jsonEncode({
        'type': 30009,
        'msg': {'extension': '350', 'presence_status': 'do_not_disturb'},
      }),
    );
    // Live Calls: entrante da trunk che squilla sul 301, poi risposta, poi BYE.
    Map<String, dynamic> call(String status) => {
      'type': 30011,
      'msg': jsonEncode({
        'call_id': 'C1',
        'members': [
          {
            'inbound': {
              'from': '0612345',
              'to': '301',
              'trunk_name': 'Trunk1',
              'channel_id': 'ch-in',
              'member_status': status == 'RING' ? 'ALERT' : status,
            },
          },
          {
            'extension': {
              'number': '301',
              'channel_id': 'ch-301',
              'member_status': status,
            },
          },
        ],
      }),
    };
    pbx.events!.add(jsonEncode(call('RING')));
    for (var i = 0; i < 50 && conn.liveCalls.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final live = conn.liveCalls['C1']!;
    expect(live.ringing, isTrue);
    expect(live.caller, '0612345');
    expect(live.callee, '301');
    expect(live.trunk, 'Trunk1');
    pbx.events!.add(jsonEncode(call('ANSWERED')));
    for (var i = 0; i < 50 && live.answered == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(live.talking, isTrue);
    pbx.events!.add(jsonEncode(call('BYE')));
    for (var i = 0; i < 50 && conn.liveCalls.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(conn.liveCalls, isEmpty);
    for (var i = 0; i < 50 && conn.callStatus.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(conn.eventsConnected, isTrue);
    expect(conn.eventsStatus, 'Eventi in tempo reale attivi');
    expect(conn.callStatus['301'], BlfStatus.ringing);
    final jack = phone.allExtensions.firstWhere((e) => e.number == '350');
    expect(phone.presenceOf(jack), 'do_not_disturb');
    // Il token resta solo nell'URL del WebSocket, mai nello stato mostrato.
    expect(conn.eventsStatus, isNot(contains('AT1')));
    await phone.setRealtime(conn, false);
    expect(conn.eventsConnected, isFalse);
    await phone.shutdown();
  }, skip: !Platform.isWindows);

  test(
    'dettaglio interno: presenze e inoltri letti, PIN della casella non tenuto',
    () async {
      // Due PBX con host diversi: il principale si riconosce solo dall'host.
      final phone = await controllerWith(FakeSipEngine(), {
        'a': pbx.baseUrl,
        'b': pbx.baseUrl.replaceFirst('127.0.0.1', 'localhost'),
      });
      expect(phone.primaryConnection?.id, 'a');
      final d = phone.ownDetail!;
      expect(d.presence, 'available');
      expect(d.customPresence, 'Ufficio');
      expect(d.id, 15);
      final av = d.settingOf('available')!;
      expect(av.ringTimeout, 60);
      expect(av.acceptRingGroup, isTrue);
      expect(d.flag('enb_vm_pin'), isTrue);
      final off = d.settingOf('off_work')!;
      expect(off.forwards['ex_always']!.enabled, isTrue);
      expect(off.forwards['ex_always']!.dest, 'extension');
      expect(off.forwards['ex_always']!.value, '11');
      expect(off.forwards['in_busy']!.dest, 'ext_vm');
      expect(off.forwards['in_always']!.enabled, isFalse);
      // PIN e password non restano nemmeno in memoria (né in cache).
      expect(jsonEncode(d.toJson()), isNot(contains('6666')));
      expect(jsonEncode(d.toJson()), isNot(contains('segreta')));
      expect(d.toJson().containsKey('enb_vm_pin'), isTrue);
      await phone.shutdown();
    },
    skip: !Platform.isWindows,
  );

  test('proprio interno: si scrivono solo i campi utente cambiati, con i tipi del PBX', () async {
    final phone = await controllerWith(FakeSipEngine(), {'a': pbx.baseUrl});
    final d = phone.ownDetail!;
    final av = d.settingOf('available')!;
    final edited = d
        .withSetting(
          av
              .withValues({'ring_timeout': '30'})
              .withForward(
                'ex_busy',
                const PresenceForward(
                  enabled: true,
                  dest: 'external_num',
                  number: '+39021234',
                ),
              ),
        )
        .withValues({'enb_all_busy_mode_for_endpoints': '0'});
    final changes = edited.changesFrom(d);
    expect(changes.keys, {'enb_all_busy_mode_for_endpoints', 'presence_list'});
    // Tipo originale del PBX: "0"/"30" -> 0/30 (errcode 40002 altrimenti).
    expect(changes['enb_all_busy_mode_for_endpoints'], 0);
    final item = (changes['presence_list'] as List).single as Map;
    expect(item['status'], 'available');
    expect(item['ring_timeout'], 30);
    expect(item['ex_busy_forward_num'], '+39021234');
    // Solo la presenza cambiata; off_work non parte.
    expect(jsonEncode(changes), isNot(contains('off_work')));

    final before = pbx.bodies.length;
    await phone.updateOwnExtension(edited);
    final sent = pbx.requests
        .skip(before)
        .toList()
        .indexWhere((r) => r.uri.path.endsWith('extension/update'));
    final body = jsonDecode(pbx.bodies[before + sent]) as Map<String, dynamic>;
    expect(body['id'], 15);
    expect(body.keys, {
      'id',
      'enb_all_busy_mode_for_endpoints',
      'presence_list',
    });

    // Campi da amministratore: rifiutati prima di partire.
    final api = YeastarApi(
      ApiCredentials(
        baseUrl: pbx.baseUrl,
        clientId: _id,
        clientSecret: _secret,
      ),
    );
    await expectLater(
      api.updateOwnExtension(15, {'reg_password': 'x'}),
      throwsArgumentError,
    );
    await expectLater(
      api.updateOwnExtension(15, {
        'presence_list': [
          {'status': 'available', 'outbound_route_permission': 1},
        ],
      }),
      throwsArgumentError,
    );
    await phone.shutdown();
  }, skip: !Platform.isWindows);

  test('live calls: BYE con canale cambiato chiude; call/query riallinea e dà il tipo', () async {
    final phone = await controllerWith(FakeSipEngine(), {'a': pbx.baseUrl});
    final conn = phone.connections.single;
    pbx.calls = {
      'outbound': [
        {
          'call_id': 'OUT1',
          'members': [
            {
              'extension': {
                'number': '305',
                'channel_id': 'a',
                'member_status': 'ANSWERED',
              },
            },
          ],
        },
      ],
    };
    await phone.setRealtime(conn, true);
    for (var i = 0; i < 50 && conn.liveCalls.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Fotografia iniziale: chiamata uscente anche senza membro `outbound`.
    expect(conn.liveCalls['OUT1']!.outbound, isTrue);

    Map<String, Object> ev(String id, List<Map<String, Object>> m) => {
      'type': 30011,
      'msg': jsonEncode({'call_id': id, 'members': m}),
    };
    Map<String, Object> ext(String n, String ch, String st) => {
      'extension': {'number': n, 'channel_id': ch, 'member_status': st},
    };
    // Interna 305 -> 301; alla risposta il canale cambia, poi BYE di uno solo.
    pbx.events!.add(
      jsonEncode(
        ev('I1', [ext('305', 'c1', 'RING'), ext('301', 'c2', 'ALERT')]),
      ),
    );
    pbx.events!.add(
      jsonEncode(
        ev('I1', [ext('305', 'c1b', 'ANSWERED'), ext('301', 'c2b', 'ANSWER')]),
      ),
    );
    for (var i = 0; i < 50 && conn.liveCalls['I1']?.talking != true; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(conn.liveCalls['I1']!.members.length, 2);
    pbx.events!.add(jsonEncode(ev('I1', [ext('301', 'c2c', 'bye')])));
    for (var i = 0; i < 50 && conn.liveCalls.containsKey('I1'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(conn.liveCalls.containsKey('I1'), isFalse);

    // OUT1 termina senza BYE: la prossima call/query la toglie.
    pbx.calls = {};
    pbx.events!.add(
      jsonEncode(ev('N2', [ext('305', 'z', 'RING'), ext('350', 'y', 'ALERT')])),
    );
    for (var i = 0; i < 200 && conn.liveCalls.containsKey('OUT1'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(conn.liveCalls.containsKey('OUT1'), isFalse);

    // Stessa conversazione con due id (tratta trunk + tratta dell'interno):
    // una sola riga, quella col trunk. Senza trunk la direzione viene dagli
    // interni noti.
    LiveMember m(
      String kind,
      String st, {
      String n = '',
      String f = '',
      String t = '',
      String trunk = '',
    }) => LiveMember(
      kind: kind,
      channel: '$kind$n$f',
      status: st,
      number: n,
      from: f,
      to: t,
      trunk: trunk,
    );
    conn.liveCalls
      ..clear()
      ..['T'] = LiveCall('T', [
        m('inbound', 'ANSWERED', f: '0612345', t: '301', trunk: 'Trunk1'),
      ])
      ..['E'] = LiveCall('E', [
        m('extension', 'ANSWERED', n: '301'),
        m('internal', 'ANSWERED', f: '301', t: '0612345'),
      ])
      ..['O'] = LiveCall('O', [
        m('extension', 'ANSWERED', n: '305'),
        m('internal', 'ANSWERED', f: '305', t: '3331234567'),
      ]);
    final shown = conn.visibleCalls;
    expect(shown.map((x) => x.id), ['T', 'O']);
    expect(shown.first.outbound, isFalse);
    expect(shown.last.outbound, isTrue);
    await phone.setRealtime(conn, false);
    await phone.shutdown();
  }, skip: !Platform.isWindows);
}
