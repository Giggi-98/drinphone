import 'dart:io';

import 'package:drinphone/core/pbx/pbx_cdr.dart';
import 'package:drinphone/core/security/cdr_db_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Database finto: registra le query e risponde con righe fisse.
class FakeCdrDb implements CdrSource {
  FakeCdrDb({this.schema = 'ysdb', this.advanced = true});
  final String schema;

  /// Firmware con CDR Advanced (`cdr_basic`) o solo la tabella `cdr`.
  final bool advanced;
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
        {'s': schema, 't': 'cdr'},
        if (advanced) ...[
          {'s': schema, 't': 'cdr_basic'},
          {'s': schema, 't': 'cdr_clip'},
        ],
      ];
    }
    return [
      {
        'datetime': '2026-10-30 15:59:21.864063',
        'src': '0496369001',
        'srcname': '',
        'dst': '6300',
        'dstname': 'RING_SKILLWORKS',
        'last_dst': '305',
        'last_dstname': 'Luigi Ruocco',
        'call_duration': '51',
        'routing_duration': '4',
        'talk_duration': '47',
        'disposition': 'ANSWERED',
        'call_type': 'Inbound',
        'disconnect_by': 'External',
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

  test('CDR Advanced: cdr_basic, anche le gambe del proprio interno', () async {
    final rows = await cdr().read(ownExtension: '305');
    final (sql, params) = db.queries.last;
    expect(sql, contains('FROM `ysdb`.`cdr_basic`'));
    expect(
      sql,
      contains('`uid` IN (SELECT `c`.`uid` FROM `ysdb`.`cdr_clip` `c`'),
    );
    expect(sql, contains('ORDER BY `timestamp` DESC'));
    expect(params, List.filled(6, '305'));
    expect(db.closed, isTrue);
    final r = rows.single;
    expect(r.time, DateTime(2026, 10, 30, 15, 59, 21, 864, 63));
    expect(
      (r.dstName, r.lastDst, r.lastDstName, r.ring, r.talk, r.answered),
      ('RING_SKILLWORKS', '305', 'Luigi Ruocco', 4, 47, true),
    );
    expect((r.callType, r.disconnectBy), ('Inbound', 'External'));
  });

  test('firmware senza CDR Advanced: tabella cdr', () async {
    db = FakeCdrDb(advanced: false);
    await cdr().read(ownExtension: '305', from: DateTime(2026, 10, 24));
    final (sql, params) = db.queries.last;
    expect(sql, contains('FROM `ysdb`.`cdr` WHERE (`src` = ? OR `dst` = ?)'));
    expect(sql, contains('ORDER BY `datetime` DESC'));
    expect(params, ['305', '305', '2026-10-24 00:00:00']);
  });

  test('cdr_basic senza cdr_clip nello stesso schema: tabella cdr', () async {
    db = FakeCdrDb(advanced: false);
    final odd = _OddSchemas(db);
    await PbxCdr(_creds, open: (_) async => odd).read(ownExtension: '305');
    expect(db.queries.last.$1, contains('FROM `ysdb`.`cdr` '));
  });

  test('tipo ed esito come filtro', () async {
    await cdr().read(ownExtension: '305', kind: CdrKind.outbound);
    expect(db.queries.last.$1, contains('`call_type` = ?'));
    expect(db.queries.last.$2.last, 'Outbound');
    await cdr().read(ownExtension: '305', kind: CdrKind.unanswered);
    expect(db.queries.last.$1, contains("`disposition` <> 'ANSWERED'"));
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
    final from = DateTime(2026, 10, 24);
    await cdr().read(
      ownExtension: '305',
      search: r"a%_b'\",
      from: from,
      offset: 50,
    );
    final (sql, params) = db.queries.last;
    expect(sql, isNot(contains("a%")));
    expect(params.sublist(6, 12), everyElement(r"%a\%\_b'\\%"));
    expect(params.last, from.microsecondsSinceEpoch);
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

/// `cdr_basic` in un altro schema, senza le gambe: non va scelto.
class _OddSchemas implements CdrSource {
  _OddSchemas(this.inner);
  final FakeCdrDb inner;

  @override
  Future<List<Map<String, String?>>> query(String sql, List<Object?> p) async {
    if (sql.contains('information_schema')) {
      inner.queries.add((sql, p));
      return [
        {'s': 'altro', 't': 'cdr_basic'},
        {'s': 'ysdb', 't': 'cdr'},
      ];
    }
    return inner.query(sql, p);
  }

  @override
  Future<void> close() => inner.close();
}
