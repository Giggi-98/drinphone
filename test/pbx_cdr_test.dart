import 'dart:io';

import 'package:drinphone/core/pbx/pbx_cdr.dart';
import 'package:drinphone/core/security/cdr_db_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Database finto: registra le query e risponde con righe fisse.
class FakeCdrDb implements CdrSource {
  FakeCdrDb({this.schema = 'ysdb'});
  final String schema;
  final queries = <(String, List<Object?>)>[];
  int opened = 0;
  bool closed = false;

  @override
  Future<List<Map<String, String?>>> query(
    String sql,
    List<Object?> params,
  ) async {
    queries.add((sql, params));
    if (sql.contains('information_schema')) {
      return [
        {'s': schema},
      ];
    }
    return [
      {
        'datetime': '2026-10-30 14:05:09',
        'src': '301',
        'srcname': 'Paolo Guerra',
        'dst': '305',
        'dstname': 'Luigi Ruocco',
        'duration': '75',
        'talkduration': '61',
        'disposition': 'ANSWERED',
        'calltype': 'Internal',
      },
    ];
  }

  @override
  Future<void> close() async => closed = true;
}

const _creds = CdrDbCredentials(host: 'pbx.test', user: 'u', password: 'p');

void main() {
  late FakeCdrDb db;
  PbxCdr cdr([CdrDbCredentials c = _creds]) => PbxCdr(
    c,
    open: (_) async {
      db.opened++;
      return db;
    },
  );

  setUp(() => db = FakeCdrDb());

  test('proprio interno: filtro con parametri, righe lette', () async {
    final rows = await cdr().read(ownExtension: '305');
    final (sql, params) = db.queries.last;
    expect(sql, contains('FROM `ysdb`.`cdr`'));
    expect(sql, contains('WHERE (`src` = ? OR `dst` = ?)'));
    expect(params, ['305', '305']);
    expect(db.closed, isTrue);
    final r = rows.single;
    expect(r.time, DateTime(2026, 10, 30, 14, 5, 9));
    expect((r.src, r.dst, r.talk, r.answered), ('301', '305', 61, true));
  });

  test(
    'senza proprio interno niente righe, senza aprire il database',
    () async {
      expect(await cdr().read(ownExtension: null), isEmpty);
      expect(await cdr().read(ownExtension: ''), isEmpty);
      expect(db.opened, 0);
    },
  );

  test('tutto il PBX solo se concesso dall’amministratore', () async {
    await expectLater(
      cdr().read(ownExtension: '305', wholePbx: true),
      throwsStateError,
    );
    expect(db.opened, 0);
    const whole = CdrDbCredentials(
      host: 'pbx.test',
      user: 'u',
      password: 'p',
      wholePbx: true,
    );
    await cdr(whole).read(ownExtension: '305', wholePbx: true);
    expect(db.queries.last.$1, isNot(contains('`src` = ?')));
  });

  test('ricerca e periodo come parametri, caratteri jolly protetti', () async {
    await cdr().read(
      ownExtension: '305',
      search: r"a%_b'\",
      from: DateTime(2026, 10, 24),
      offset: 50,
    );
    final (sql, params) = db.queries.last;
    expect(sql, isNot(contains("a%")));
    expect(params.sublist(2, 6), everyElement(r"%a\%\_b'\\%"));
    expect(params.last, '2026-10-24 00:00:00');
    expect(sql, endsWith('LIMIT 50 OFFSET 50'));
  });

  test('nome del database sospetto: rifiutato', () async {
    db = FakeCdrDb(schema: 'x`; DROP TABLE cdr; --');
    await expectLater(cdr().read(ownExtension: '305'), throwsStateError);
    expect(db.queries.length, 1);
    expect(db.closed, isTrue);
  });

  test('credenziali CDR: cifrate su disco, rilette uguali', () async {
    final tmp = await Directory.systemTemp.createTemp('drin_cdr');
    addTearDown(() => tmp.delete(recursive: true));
    final store = CdrDbStore('${tmp.path}${Platform.pathSeparator}db.dpapi');
    await store.save(
      const CdrDbCredentials(
        host: '10.0.0.5',
        user: 'cdr_user',
        password: 'S3greta!',
        wholePbx: true,
      ),
    );
    final raw = await File('${tmp.path}${Platform.pathSeparator}db.dpapi')
        .readAsString();
    expect(raw, isNot(contains('S3greta!')));
    expect(raw, isNot(contains('cdr_user')));
    final back = (await store.load())!;
    expect(
      (back.host, back.user, back.password, back.wholePbx, back.port),
      ('10.0.0.5', 'cdr_user', 'S3greta!', true, 3306),
    );
    expect('$back', isNot(contains('S3greta!')));
  }, skip: !Platform.isWindows);
}
