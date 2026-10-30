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

  /// Query di pagina (né schema, né conteggio, né gambe).
  (String, List<Object?>) get page =>
      queries.lastWhere((q) => q.$1.contains('ORDER BY') && !_legs(q.$1));

  static bool _legs(String sql) => sql.contains('`cdr_clip` WHERE `uid` IN');

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
    if (sql.contains('COUNT(*)')) {
      return [
        {'n': '110'},
      ];
    }
    if (_legs(sql)) {
      return [
        {
          'uid': 'U1',
          'datetime': '2026-10-30 15:59:21',
          'src': '0496369001',
          'dst': '6300',
          'disposition': 'ANSWERED',
          'srctrunk': 'SKILLWORKS_0308373176',
          'didnumber': '0308373176',
        },
        {'uid': 'U1', 'src': '0496369001', 'dst': '305', 'srctrunk': ''},
      ];
    }
    return [
      {
        'uid': advanced ? 'U1' : null,
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
        'ringgroups': '["RING_SKILLWORKS<6300>"]',
        'segments': '2',
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
    final page = await cdr().read(ownExtension: '305');
    final (sql, params) = db.page;
    expect(sql, contains('FROM `ysdb`.`cdr_basic`'));
    expect(
      sql,
      contains('`uid` IN (SELECT `c`.`uid` FROM `ysdb`.`cdr_clip` `c`'),
    );
    expect(sql, contains('ORDER BY `timestamp` DESC LIMIT 50 OFFSET 0'));
    expect(params, List.filled(6, '305'));
    expect(db.closed, isTrue);
    expect(page.total, 110);
    final r = page.rows.single;
    expect(r.time, DateTime(2026, 10, 30, 15, 59, 21, 864, 63));
    expect(
      (r.dstName, r.lastDst, r.lastDstName, r.ring, r.talk, r.answered),
      ('RING_SKILLWORKS', '305', 'Luigi Ruocco', 4, 47, true),
    );
    expect((r.callType, r.disconnectBy), ('Inbound', 'External'));
    expect(r.ringGroups, ['RING_SKILLWORKS<6300>']);
    expect(r.queues, isEmpty);
    expect(r.segments, 2);
  });

  test('conteggio con gli stessi filtri della pagina', () async {
    await cdr().read(
      ownExtension: '305',
      q: const CdrQuery(kind: CdrKind.inbound),
    );
    final count = db.queries.firstWhere((q) => q.$1.contains('COUNT(*)'));
    expect(count.$1, contains('FROM `ysdb`.`cdr_basic` WHERE'));
    expect(count.$2, db.page.$2);
  });

  test('gambe della pagina: trunk e DID, uid come parametri', () async {
    final r = (await cdr().read(ownExtension: '305')).rows.single;
    final legs = db.queries.last;
    expect(legs.$1, contains('FROM `ysdb`.`cdr_clip` WHERE `uid` IN (?)'));
    expect(legs.$2, ['U1']);
    expect(r.legs.length, 2);
    expect((r.srcTrunk, r.did), ('SKILLWORKS_0308373176', '0308373176'));
  });

  test('firmware senza CDR Advanced: tabella cdr, niente gambe', () async {
    db = FakeCdrDb(advanced: false);
    final page = await cdr().read(
      ownExtension: '305',
      q: CdrQuery(from: DateTime(2026, 10, 24)),
    );
    final (sql, params) = db.page;
    expect(sql, contains('FROM `ysdb`.`cdr` WHERE (`src` = ? OR `dst` = ?)'));
    expect(sql, contains('ORDER BY `datetime` DESC'));
    expect(params, ['305', '305', '2026-10-24 00:00:00']);
    expect(db.queries.where((q) => q.$1.contains('cdr_clip')), isEmpty);
    expect(page.rows.single.legs, isEmpty);
  });

  test('cdr_basic senza cdr_clip nello stesso schema: tabella cdr', () async {
    db = FakeCdrDb(advanced: false);
    final odd = _OddSchemas(db);
    await PbxCdr(_creds, open: (_) async => odd).read(ownExtension: '305');
    expect(db.page.$1, contains('FROM `ysdb`.`cdr` '));
  });

  test('tipo ed esito come filtro', () async {
    await cdr().read(
      ownExtension: '305',
      q: const CdrQuery(kind: CdrKind.outbound),
    );
    expect(db.page.$1, contains('`call_type` = ?'));
    expect(db.page.$2.last, 'Outbound');
    await cdr().read(
      ownExtension: '305',
      q: const CdrQuery(outcome: CdrOutcome.unanswered),
    );
    expect(db.page.$1, contains("`disposition` <> 'ANSWERED'"));
    await cdr().read(
      ownExtension: '305',
      q: const CdrQuery(outcome: CdrOutcome.noAnswer),
    );
    expect(db.page.$1, contains('`disposition` = ?'));
    expect(db.page.$2.last, 'NO ANSWER');
  });

  test('intervallo di date: fine esclusa, come parametro', () async {
    final from = DateTime(2026, 1, 1), to = DateTime(2026, 2, 1);
    await cdr().read(
      ownExtension: '305',
      q: CdrQuery(from: from, to: to),
    );
    expect(db.page.$1, contains('`timestamp` < ?'));
    expect(db.page.$2.last, to.microsecondsSinceEpoch);
    db = FakeCdrDb(advanced: false);
    await cdr().read(
      ownExtension: '305',
      q: CdrQuery(from: from, to: to),
    );
    expect(db.page.$1, contains('`datetime` < ?'));
    expect(db.page.$2.last, '2026-02-01 00:00:00');
  });

  test('ordinamento da elenco fisso, la più recente a parità', () async {
    await cdr().read(
      ownExtension: '305',
      q: const CdrQuery(sort: CdrSort.duration, descending: false),
    );
    expect(
      db.page.$1,
      contains('ORDER BY `call_duration` ASC, `timestamp` DESC'),
    );
    await cdr().read(ownExtension: '305', q: const CdrQuery(descending: false));
    expect(db.page.$1, contains('ORDER BY `timestamp` ASC LIMIT'));
  });

  test('Da e A separati, righe per pagina limitate', () async {
    await cdr().read(
      ownExtension: '305',
      q: const CdrQuery(callFrom: '305', callTo: 'Rossi', limit: 100000),
    );
    final (sql, params) = db.page;
    expect(sql, contains('(`src` LIKE ? OR `srcname` LIKE ?)'));
    expect(sql, contains('`last_dstname` LIKE ?'));
    expect(params.sublist(6, 8), everyElement('%305%'));
    expect(params.sublist(8), everyElement('%Rossi%'));
    expect(sql, endsWith('LIMIT ${PbxCdr.maxLimit} OFFSET 0'));
  });

  test(
    'senza proprio interno niente righe, senza aprire il database',
    () async {
      expect((await cdr().read(ownExtension: null)).rows, isEmpty);
      expect((await cdr().read(ownExtension: '')).rows, isEmpty);
      expect(db.opened, 0);
    },
  );

  test('tutto il PBX solo se concesso dall’amministratore', () async {
    await expectLater(
      cdr().read(ownExtension: '305', q: const CdrQuery(wholePbx: true)),
      throwsStateError,
    );
    expect(db.opened, 0);
    const whole = CdrDbCredentials(
      host: 'pbx.test',
      user: 'u',
      password: 'p',
      wholePbx: true,
    );
    await cdr(whole)
        .read(ownExtension: '305', q: const CdrQuery(wholePbx: true));
    expect(db.page.$1, isNot(contains('`src` = ?')));
  });

  test('ricerca e periodo come parametri, caratteri jolly protetti', () async {
    final from = DateTime(2026, 10, 24);
    await cdr().read(
      ownExtension: '305',
      q: CdrQuery(search: r"a%_b'\", from: from, offset: 50),
    );
    final (sql, params) = db.page;
    expect(sql, isNot(contains("a%")));
    expect(params.sublist(6, 14), everyElement(r"%a\%\_b'\\%"));
    expect(params.last, from.microsecondsSinceEpoch);
    expect(sql, endsWith('LIMIT 50 OFFSET 50'));
  });

  test('code, gruppi, IVR: JSON, oggetti o testo con virgole', () {
    expect(CdrRecord.names(null), isEmpty);
    expect(CdrRecord.names('0'), isEmpty);
    expect(CdrRecord.names('[]'), isEmpty);
    expect(CdrRecord.names('["A<1>","B<2>"]'), ['A<1>', 'B<2>']);
    expect(CdrRecord.names('[{"name":"Commerciale","number":"6403"}]'), [
      'Commerciale · 6403',
    ]);
    expect(CdrRecord.names('IVR ECONNET, Coda'), ['IVR ECONNET', 'Coda']);
    expect(CdrRecord.names('6403'), ['6403']);
  });

  test('CSV: colonne del PBX, formule disinnescate, virgolette', () {
    final csv = cdrCsv([
      CdrRecord(
        time: DateTime(2026, 10, 30, 17, 54, 21),
        src: '305',
        srcName: '=HYPERLINK("x")',
        dst: '364',
        dstName: 'Cancello, Esterno',
        duration: 35,
        talk: 34,
        disposition: 'ANSWERED',
        callType: 'Internal',
      ),
    ]);
    final lines = csv.split('\r\n');
    expect(lines.first, startsWith('Time,Communication Type,Call From,'));
    expect(
      lines[1],
      startsWith(
        '30/10/2026 17:54:21,Internal,"\'=HYPERLINK(""x"")<305>",'
        '"Cancello, Esterno<364>",',
      ),
    );
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
