import 'package:mysql_client/mysql_client.dart';

import '../security/cdr_db_store.dart';

/// Una chiamata del CDR del PBX (help.yeastar.com "CDR Table in the PBX
/// Database"): `cdr_basic` (CDR Advanced, una riga per chiamata) o, sui
/// firmware che non ce l'hanno, la tabella storica `cdr`.
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
    this.lastDst = '',
    this.lastDstName = '',
    this.ring = 0,
    this.disconnectBy = '',
  });

  /// Ora del PBX (la scrive già nel suo fuso).
  final DateTime? time;
  final String src, srcName, dst, dstName;

  /// Ultimo partecipante: chi ha risposto (o l'ultimo che ha squillato) di un
  /// gruppo di squillo, coda, IVR. Uguale a [dst] per le chiamate dirette.
  final String lastDst, lastDstName;

  /// Secondi: totale, fino alla risposta, in conversazione.
  final int duration, ring, talk;

  /// Esito (ANSWERED, NO ANSWER, BUSY, FAILED, VOICEMAIL, ABANDONED) e tipo
  /// (Inbound, Outbound, Internal) come li scrive il PBX.
  final String disposition, callType;

  /// Chi ha chiuso (Extension, External, System; vuoto sulla tabella `cdr`).
  final String disconnectBy;

  bool get answered => disposition.toUpperCase() == 'ANSWERED';

  static CdrRecord fromRow(Map<String, String?> r) => CdrRecord(
    time: DateTime.tryParse((r['datetime'] ?? '').replaceFirst(' ', 'T')),
    src: r['src'] ?? '',
    srcName: r['srcname'] ?? '',
    dst: r['dst'] ?? '',
    dstName: r['dstname'] ?? '',
    lastDst: r['last_dst'] ?? '',
    lastDstName: r['last_dstname'] ?? '',
    duration: int.tryParse(r['call_duration'] ?? '') ?? 0,
    ring: int.tryParse(r['routing_duration'] ?? '') ?? 0,
    talk: int.tryParse(r['talk_duration'] ?? '') ?? 0,
    disposition: r['disposition'] ?? '',
    callType: r['call_type'] ?? '',
    disconnectBy: r['disconnect_by'] ?? '',
  );
}

/// Filtro per tipo ed esito, come nel CDR del PBX.
enum CdrKind { all, inbound, outbound, internal, unanswered }

/// Accesso al database (sostituibile nei test).
abstract class CdrSource {
  /// Query con parametri posizionali `?` (statement preparato).
  Future<List<Map<String, String?>>> query(String sql, List<Object?> params);
  Future<void> close();
}

typedef CdrSourceOpener = Future<CdrSource> Function(CdrDbCredentials c);

/// Lettura del CDR. Il filtro sul proprio interno lo decide l'app, non chi
/// usa la UI: senza [CdrDbCredentials.wholePbx] solo le chiamate in cui
/// [ownExtension] ha chiamato, è stato chiamato o ha squillato.
class PbxCdr {
  PbxCdr(this.creds, {CdrSourceOpener? open}) : _open = open ?? _mysql;

  final CdrDbCredentials creds;
  final CdrSourceOpener _open;

  static const pageSize = 50;
  static final _identifier = RegExp(r'^[A-Za-z0-9_]{1,64}$');

  /// [ownExtension] nullo o vuoto = nessun proprio interno (niente righe,
  /// salvo [wholePbx] concesso dall'amministratore).
  Future<List<CdrRecord>> read({
    required String? ownExtension,
    bool wholePbx = false,
    String search = '',
    DateTime? from,
    CdrKind kind = CdrKind.all,
    int offset = 0,
  }) async {
    if (wholePbx && !creds.wholePbx) {
      throw StateError('CDR di tutto il PBX non concesso');
    }
    final own = ownExtension ?? '';
    if (!wholePbx && own.isEmpty) return const [];
    final db = await _open(creds);
    try {
      final (schema, advanced) = await _findTable(db);
      final where = <String>[];
      final params = <Object?>[];
      final q = search.trim();
      final like = q.isEmpty
          ? ''
          : '%${q.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}')}%';
      final String sql;
      if (advanced) {
        if (!wholePbx) {
          // Anche le gambe (cdr_clip): un gruppo di squillo che ha fatto
          // suonare il proprio interno compare solo lì.
          where.add(
            '(`src` = ? OR `dst` = ? OR `second_dst` = ? OR `last_dst` = ? '
            'OR `uid` IN (SELECT `c`.`uid` FROM `$schema`.`cdr_clip` `c` '
            'WHERE `c`.`src` = ? OR `c`.`dst` = ?))',
          );
          params.addAll(List.filled(6, own));
        }
        if (like.isNotEmpty) {
          where.add(
            '(`src` LIKE ? OR `dst` LIKE ? OR `last_dst` LIKE ? OR '
            '`srcname` LIKE ? OR `dstname` LIKE ? OR `last_dstname` LIKE ?)',
          );
          params.addAll(List.filled(6, like));
        }
        if (from != null) {
          // `timestamp` = microsecondi epoch, indicizzato.
          where.add('`timestamp` >= ?');
          params.add(from.microsecondsSinceEpoch);
        }
        _kindFilter(kind, 'call_type', where, params);
        sql =
            // Limite lato server (MySQL; MariaDB ignora il commento): una
            // lettura lenta si ferma sul PBX prima del timeout del client.
            'SELECT /*+ MAX_EXECUTION_TIME(20000) */ `datetime`, `src`, '
            '`srcname`, `dst`, `dstname`, `last_dst`, `last_dstname`, '
            '`disposition`, `call_duration`, `routing_duration`, '
            '`talk_duration`, `call_type`, `disconnect_by` '
            'FROM `$schema`.`cdr_basic`${_where(where)} '
            'ORDER BY `timestamp` DESC';
      } else {
        if (!wholePbx) {
          where.add('(`src` = ? OR `dst` = ?)');
          params.addAll([own, own]);
        }
        if (like.isNotEmpty) {
          where.add(
            '(`src` LIKE ? OR `dst` LIKE ? OR `srcname` LIKE ? OR '
            '`dstname` LIKE ?)',
          );
          params.addAll(List.filled(4, like));
        }
        if (from != null) {
          where.add('`datetime` >= ?');
          params.add(_sqlTime(from));
        }
        _kindFilter(kind, 'calltype', where, params);
        sql =
            'SELECT /*+ MAX_EXECUTION_TIME(20000) */ `datetime`, `src`, '
            '`srcname`, `dst`, `dstname`, `dst` AS `last_dst`, '
            '`dstname` AS `last_dstname`, `disposition`, '
            '`duration` AS `call_duration`, '
            '`ringduration` AS `routing_duration`, '
            '`talkduration` AS `talk_duration`, `calltype` AS `call_type` '
            'FROM `$schema`.`cdr`${_where(where)} ORDER BY `datetime` DESC';
      }
      final page =
          '$sql LIMIT ${pageSize.toInt()}'
          ' OFFSET ${offset < 0 ? 0 : offset.toInt()}';
      return [
        for (final r in await db.query(page, params)) CdrRecord.fromRow(r),
      ];
    } finally {
      // Un errore di chiusura non copre quello della lettura.
      try {
        await db.close();
      } catch (_) {}
    }
  }

  static String _where(List<String> w) =>
      w.isEmpty ? '' : ' WHERE ${w.join(' AND ')}';

  static void _kindFilter(
    CdrKind kind,
    String typeColumn,
    List<String> where,
    List<Object?> params,
  ) {
    switch (kind) {
      case CdrKind.all:
        return;
      case CdrKind.unanswered:
        where.add("`disposition` <> 'ANSWERED'");
      case CdrKind.inbound || CdrKind.outbound || CdrKind.internal:
        where.add('`$typeColumn` = ?');
        params.add(switch (kind) {
          CdrKind.inbound => 'Inbound',
          CdrKind.outbound => 'Outbound',
          _ => 'Internal',
        });
    }
  }

  /// Il nome del database non è documentato: quello che contiene
  /// `cdr_basic` (CDR Advanced) o, sui firmware precedenti, `cdr`. Dopo
  /// l'aggiornamento al CDR Advanced la tabella `cdr` resta ma non cresce più.
  static Future<(String, bool)> _findTable(CdrSource db) async {
    final rows = await db.query(
      'SELECT `TABLE_SCHEMA` AS s, `TABLE_NAME` AS t '
      'FROM `information_schema`.`TABLES` WHERE `TABLE_NAME` IN (?, ?, ?) '
      'ORDER BY `TABLE_SCHEMA`',
      ['cdr_basic', 'cdr_clip', 'cdr'],
    );
    bool has(String? s, String t) =>
        rows.any((r) => r['s'] == s && r['t'] == t);
    // CDR Advanced solo dove ci sono sia le chiamate sia le gambe.
    final advanced = rows
        .map((r) => r['s'])
        .where((s) => has(s, 'cdr_basic') && has(s, 'cdr_clip'))
        .firstOrNull;
    final s =
        advanced ??
        rows.where((r) => r['t'] == 'cdr').map((r) => r['s']).firstOrNull;
    if (s == null || !_identifier.hasMatch(s)) {
      throw StateError('tabella cdr non trovata');
    }
    return (s, advanced != null);
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
