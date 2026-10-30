import 'package:mysql_client/mysql_client.dart';

import '../security/cdr_db_store.dart';

/// Una riga del CDR del PBX (tabella `cdr`, help.yeastar.com "CDR Table in
/// the PBX Database").
class CdrRecord {
  const CdrRecord({
    required this.time,
    required this.src,
    required this.srcName,
    required this.dst,
    required this.dstName,
    required this.duration,
    required this.talk,
    required this.disposition,
    required this.callType,
  });

  final DateTime? time;
  final String src, srcName, dst, dstName;

  /// Secondi: totale e in conversazione.
  final int duration, talk;

  /// Esito (ANSWERED, NO ANSWER, BUSY, FAILED, VOICEMAIL…) e tipo (Inbound,
  /// Outbound, Internal…) come li scrive il PBX.
  final String disposition, callType;

  bool get answered => disposition.toUpperCase() == 'ANSWERED';

  static CdrRecord fromRow(Map<String, String?> r) => CdrRecord(
    time: DateTime.tryParse((r['datetime'] ?? '').replaceFirst(' ', 'T')),
    src: r['src'] ?? '',
    srcName: r['srcname'] ?? '',
    dst: r['dst'] ?? '',
    dstName: r['dstname'] ?? '',
    duration: int.tryParse(r['duration'] ?? '') ?? 0,
    talk: int.tryParse(r['talkduration'] ?? '') ?? 0,
    disposition: r['disposition'] ?? '',
    callType: r['calltype'] ?? '',
  );
}

/// Accesso al database (sostituibile nei test).
abstract class CdrSource {
  /// Query con parametri posizionali `?` (statement preparato).
  Future<List<Map<String, String?>>> query(String sql, List<Object?> params);
  Future<void> close();
}

typedef CdrSourceOpener = Future<CdrSource> Function(CdrDbCredentials c);

/// Lettura del CDR. Il filtro sul proprio interno lo decide l'app, non chi
/// usa la UI: senza [CdrDbCredentials.wholePbx] solo righe con [ownExtension]
/// come chiamante o chiamato.
class PbxCdr {
  PbxCdr(this.creds, {CdrSourceOpener? open}) : _open = open ?? _mysql;

  final CdrDbCredentials creds;
  final CdrSourceOpener _open;
  String? _schema;

  static const pageSize = 50;
  static final _identifier = RegExp(r'^[A-Za-z0-9_]{1,64}$');

  /// [ownExtension] nullo o vuoto = nessun proprio interno (niente righe,
  /// salvo [wholePbx] concesso dall'amministratore).
  Future<List<CdrRecord>> read({
    required String? ownExtension,
    bool wholePbx = false,
    String search = '',
    DateTime? from,
    int offset = 0,
  }) async {
    if (wholePbx && !creds.wholePbx) {
      throw StateError('CDR di tutto il PBX non concesso');
    }
    final own = ownExtension ?? '';
    if (!wholePbx && own.isEmpty) return const [];
    final db = await _open(creds);
    try {
      final schema = _schema ??= await _findSchema(db);
      final where = <String>[];
      final params = <Object?>[];
      if (!wholePbx) {
        where.add('(`src` = ? OR `dst` = ?)');
        params.addAll([own, own]);
      }
      final q = search.trim();
      if (q.isNotEmpty) {
        final like =
            '%${q.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}')}%';
        where.add(
          '(`src` LIKE ? OR `dst` LIKE ? OR `srcname` LIKE ? OR `dstname` LIKE ?)',
        );
        params.addAll([like, like, like, like]);
      }
      if (from != null) {
        where.add('`datetime` >= ?');
        params.add(_sqlTime(from));
      }
      final sql =
          // Limite lato server (MySQL; MariaDB ignora il commento): una lettura
          // lenta si ferma sul PBX prima del timeout del client.
          'SELECT /*+ MAX_EXECUTION_TIME(20000) */ `datetime`, `src`, `srcname`, `dst`, `dstname`, `duration`, '
          '`talkduration`, `disposition`, `calltype` FROM `$schema`.`cdr`'
          '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
          ' ORDER BY `datetime` DESC LIMIT ${pageSize.toInt()}'
          ' OFFSET ${offset < 0 ? 0 : offset.toInt()}';
      return [
        for (final r in await db.query(sql, params)) CdrRecord.fromRow(r),
      ];
    } finally {
      // Un errore di chiusura non copre quello della lettura.
      try {
        await db.close();
      } catch (_) {}
    }
  }

  /// Il nome del database non è documentato: quello che contiene `cdr`.
  static Future<String> _findSchema(CdrSource db) async {
    final rows = await db.query(
      'SELECT `TABLE_SCHEMA` AS s FROM `information_schema`.`TABLES` '
      'WHERE `TABLE_NAME` = ? LIMIT 1',
      ['cdr'],
    );
    final s = rows.isEmpty ? null : rows.first['s'];
    if (s == null || !_identifier.hasMatch(s)) {
      throw StateError('tabella cdr non trovata');
    }
    return s;
  }

  static String _sqlTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  static Future<CdrSource> _mysql(CdrDbCredentials c) async {
    final conn = await MySQLConnection.createConnection(
      host: c.host,
      port: c.port,
      userName: c.user,
      password: c.password,
      secure: c.secure,
    ).timeout(const Duration(seconds: 10));
    try {
      await conn.connect(timeoutMs: 10000);
    } catch (_) {
      try {
        await conn.close();
      } catch (_) {}
      rethrow;
    }
    return _MySqlSource(conn);
  }
}

class _MySqlSource implements CdrSource {
  _MySqlSource(this._c);
  final MySQLConnection _c;

  @override
  Future<List<Map<String, String?>>> query(
    String sql,
    List<Object?> params,
  ) async {
    // Statement preparato: i valori non entrano mai nel testo SQL.
    final stmt = await _c.prepare(sql).timeout(const Duration(seconds: 15));
    try {
      final res = await stmt
          .execute(params)
          .timeout(const Duration(seconds: 30));
      return [for (final r in res.rows) r.assoc()];
    } finally {
      try {
        await stmt.deallocate();
      } catch (_) {}
    }
  }

  @override
  Future<void> close() => _c.close();
}
