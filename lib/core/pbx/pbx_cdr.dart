import 'dart:convert';

import 'package:mysql_client/mysql_client.dart';

import '../security/cdr_db_store.dart';

/// Una chiamata del CDR del PBX (help.yeastar.com "Tables in the PBX
/// Database"): `cdr_basic` (CDR Advanced, una riga per chiamata) con le sue
/// gambe da `cdr_clip` o, sui firmware che non ce l'hanno, la tabella
/// storica `cdr` (senza gambe, code, gruppi, IVR).
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
    this.uid = '',
    this.secondDst = '',
    this.secondDstName = '',
    this.lastDst = '',
    this.lastDstName = '',
    this.ring = 0,
    this.hold = 0,
    this.disconnectBy = '',
    this.queues = const [],
    this.ringGroups = const [],
    this.ivrs = const [],
    this.callFlows = const [],
    this.segments = 0,
    this.hasRecording = false,
    this.legs = const [],
    this.timeline = const [],
  });

  /// Identificativo della chiamata (lega `cdr_basic` alle gambe).
  final String uid;

  /// Ora del PBX (la scrive già nel suo fuso).
  final DateTime? time;
  final String src, srcName, dst, dstName;

  /// Secondo partecipante (chi ha preso la chiamata dopo IVR, gruppo, coda).
  final String secondDst, secondDstName;

  /// Ultimo partecipante: chi ha risposto (o l'ultimo che ha squillato) di un
  /// gruppo di squillo, coda, IVR. Uguale a [dst] per le chiamate dirette.
  final String lastDst, lastDstName;

  /// Secondi: totale, fino alla risposta, in conversazione, in attesa.
  final int duration, ring, talk, hold;

  /// Esito (ANSWERED, NO ANSWER, BUSY, FAILED, VOICEMAIL, ABANDONED) e tipo
  /// (Inbound, Outbound, Internal) come li scrive il PBX.
  final String disposition, callType;

  /// Chi ha chiuso (vuoto sulla tabella `cdr`).
  final String disconnectBy;

  /// Code, gruppi di squillo, IVR, call flow attraversati.
  final List<String> queues, ringGroups, ivrs, callFlows;

  /// Numero di gambe secondo il PBX.
  final int segments;
  final bool hasRecording;

  /// Gambe della chiamata, in ordine di tempo (vuoto sulla tabella `cdr`).
  final List<CdrLeg> legs;

  /// Tratte ed eventi ricevuti dall'evento API 30039 (`Call End Timeline Notification`).
  final List<CdrTimelineLeg> timeline;

  bool get answered => disposition.toUpperCase() == 'ANSWERED';

  /// Primo valore non vuoto tra le gambe.
  String _fromLegs(String Function(CdrLeg) f) =>
      legs.map(f).firstWhere((v) => v.isNotEmpty, orElse: () => '');

  String get srcTrunk => _fromLegs((l) => l.srcTrunk);
  String get dstTrunk => _fromLegs((l) => l.dstTrunk);
  String get did => _fromLegs((l) => l.did);
  String get dod => _fromLegs((l) => l.dod);

  CdrRecord withLegs(List<CdrLeg> legs, {List<CdrTimelineLeg>? timeline}) =>
      CdrRecord(
        uid: uid,
        time: time,
        src: src,
        srcName: srcName,
        dst: dst,
        dstName: dstName,
        secondDst: secondDst,
        secondDstName: secondDstName,
        lastDst: lastDst,
        lastDstName: lastDstName,
        duration: duration,
        ring: ring,
        talk: talk,
        hold: hold,
        disposition: disposition,
        callType: callType,
        disconnectBy: disconnectBy,
        queues: queues,
        ringGroups: ringGroups,
        ivrs: ivrs,
        callFlows: callFlows,
        segments: segments,
        hasRecording: hasRecording,
        legs: legs,
        timeline: timeline ?? this.timeline,
      );

  static CdrRecord fromRow(Map<String, String?> r) => CdrRecord(
    uid: r['uid'] ?? '',
    time: _time(r['datetime']),
    src: r['src'] ?? '',
    srcName: r['srcname'] ?? '',
    dst: r['dst'] ?? '',
    dstName: r['dstname'] ?? '',
    secondDst: r['second_dst'] ?? '',
    secondDstName: r['second_dstname'] ?? '',
    lastDst: r['last_dst'] ?? '',
    lastDstName: r['last_dstname'] ?? '',
    duration: _int(r['call_duration']),
    ring: _int(r['routing_duration']),
    talk: _int(r['talk_duration']),
    hold: _int(r['hold_duration']),
    disposition: r['disposition'] ?? '',
    callType: r['call_type'] ?? '',
    disconnectBy: r['disconnect_by'] ?? '',
    queues: names(r['queues']),
    ringGroups: names(r['ringgroups']),
    ivrs: names(r['ivrs']),
    callFlows: names(r['callflows']),
    segments: _int(r['segments']),
    hasRecording: _int(r['has_recording']) > 0,
  );

  /// Code, gruppi, IVR: il formato nel database non è documentato ("system
  /// flag"). Si accettano JSON (elenco di testi o di oggetti con `name` /
  /// `number`) o testo separato da virgole; vuoto, `0`, `[]` = nessuno.
  static List<String> names(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty || s == '0' || s == '[]' || s == '{}') return const [];
    String one(Object? v) => switch (v) {
      Map() => [
        v['name'],
        v['number'],
      ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
      null => '',
      _ => '$v'.trim(),
    };
    try {
      final j = jsonDecode(s);
      return [
        for (final v in j is List ? j : [j]) one(v),
      ].where((x) => x.isNotEmpty).toList();
    } on FormatException {
      return [
        for (final p in s.split(','))
          if (p.trim().isNotEmpty) p.trim(),
      ];
    }
  }
}

/// Una gamba della chiamata (`cdr_clip`): chi ha chiamato chi, con quale
/// esito, su quali trunk.
class CdrLeg {
  const CdrLeg({
    required this.time,
    required this.src,
    required this.srcName,
    required this.dst,
    required this.dstName,
    required this.disposition,
    required this.callType,
    required this.duration,
    required this.ring,
    required this.talk,
    required this.hold,
    required this.srcTrunk,
    required this.dstTrunk,
    required this.did,
    required this.dod,
  });
  final DateTime? time;
  final String src, srcName, dst, dstName, disposition, callType;
  final int duration, ring, talk, hold;
  final String srcTrunk, dstTrunk, did, dod;

  static CdrLeg fromRow(Map<String, String?> r) => CdrLeg(
    time: _time(r['datetime']),
    src: r['src'] ?? '',
    srcName: r['srcname'] ?? '',
    dst: r['dst'] ?? '',
    dstName: r['dstname'] ?? '',
    disposition: r['disposition'] ?? '',
    callType: r['calltype'] ?? '',
    duration: _int(r['duration']),
    ring: _int(r['ringduration']),
    talk: _int(r['talkduration']),
    hold: _int(r['holdduration']),
    srcTrunk: r['srctrunk'] ?? '',
    dstTrunk: r['dsttrunk'] ?? '',
    did: r['didnumber'] ?? '',
    dod: r['dodnumber'] ?? '',
  );
}

/// Data del PBX: testo `2026/11/10 15:39:03` oppure timestamp Unix in
/// secondi o millisecondi (l'evento 30039 non dichiara il formato di
/// `event_ts`; senza questo tutti gli offset della timeline erano 00:00).
DateTime? _time(String? s) {
  final v = (s ?? '').trim();
  if (RegExp(r'^\d{9,13}$').hasMatch(v)) {
    final n = int.parse(v);
    return DateTime.fromMillisecondsSinceEpoch(v.length > 10 ? n : n * 1000);
  }
  return DateTime.tryParse(v.replaceAll('/', '-').replaceFirst(' ', 'T'));
}

int _int(String? s) => int.tryParse(s ?? '') ?? 0;

/// Un evento della timeline di chiamata (evento API 30039 `event_list`:
/// `event-call-end-timeline-notification.html`).
class CdrTimelineEvent {
  const CdrTimelineEvent({
    this.id = '',
    required this.name,
    this.type = '',
    this.time,
    this.content = const {},
    this.rawContent = '',
  });

  final String id, name, type;
  final DateTime? time;
  final Map<String, String> content;
  final String rawContent;

  static CdrTimelineEvent fromJson(Map<String, dynamic> j) {
    var raw = j['event_content'];
    var map = <String, String>{};
    var text = '';
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        text = raw.trim();
      }
    }
    if (raw is Map) {
      map = {
        for (final e in raw.entries)
          if (e.value != null && '${e.value}'.isNotEmpty)
            '${e.key}': '${e.value}',
      };
    } else if (raw != null && text.isEmpty) {
      text = '$raw'.trim();
    }
    return CdrTimelineEvent(
      id: '${j['event_id'] ?? ''}',
      name: '${j['event_name'] ?? ''}',
      type: '${j['event_type'] ?? ''}',
      time: _time('${j['event_ts'] ?? ''}'),
      content: map,
      rawContent: text,
    );
  }
}

/// Una tratta (`leg`) della timeline inviata dall'evento API 30039
/// (`Call End Timeline Notification`).
class CdrTimelineLeg {
  const CdrTimelineLeg({
    required this.uid,
    required this.leg,
    this.cdrId = '',
    this.timeStart,
    this.callFrom = '',
    this.callTo = '',
    this.srcTrunk = '',
    this.dstTrunk = '',
    this.status = '',
    this.ring = 0,
    this.talk = 0,
    this.hold = 0,
    this.events = const [],
  });

  final String uid, cdrId, callFrom, callTo, srcTrunk, dstTrunk, status;
  final int leg, ring, talk, hold;
  final DateTime? timeStart;
  final List<CdrTimelineEvent> events;

  static CdrTimelineLeg? fromEvent(Map<String, dynamic> msg) {
    final uid = '${msg['uid'] ?? ''}'.trim();
    if (uid.isEmpty) return null;
    final list = msg['event_list'];
    return CdrTimelineLeg(
      uid: uid,
      leg: _int('${msg['leg'] ?? 1}').clamp(1, 999),
      cdrId: '${msg['cdr_id'] ?? ''}',
      timeStart: _time('${msg['time_start'] ?? ''}'),
      callFrom: '${msg['call_from'] ?? ''}',
      callTo: '${msg['call_to'] ?? ''}',
      srcTrunk: '${msg['src_trunk'] ?? ''}',
      dstTrunk: '${msg['dst_trunk'] ?? ''}',
      status: '${msg['status'] ?? ''}',
      ring: _int('${msg['ring_duration'] ?? 0}'),
      talk: _int('${msg['talk_duration'] ?? 0}'),
      hold: _int('${msg['hold_duration'] ?? 0}'),
      events: [
        if (list is List)
          for (final e in list.whereType<Map<String, dynamic>>())
            CdrTimelineEvent.fromJson(e),
      ],
    );
  }
}

/// Filtro per tipo, come nel CDR del PBX.
enum CdrKind { all, inbound, outbound, internal }

/// Filtro per esito (`disposition`); [unanswered] = tutto tranne ANSWERED.
enum CdrOutcome {
  all,
  answered,
  unanswered,
  noAnswer,
  busy,
  failed,
  voicemail,
  abandoned,
}

/// Colonne per cui si può ordinare (sempre da un elenco fisso, mai testo
/// della UI dentro l'SQL).
enum CdrSort { time, type, status, duration, talk }

/// Cosa leggere: filtri, ordinamento, pagina.
class CdrQuery {
  const CdrQuery({
    this.wholePbx = false,
    this.search = '',
    this.callFrom = '',
    this.callTo = '',
    this.from,
    this.to,
    this.kind = CdrKind.all,
    this.outcome = CdrOutcome.all,
    this.sort = CdrSort.time,
    this.descending = true,
    this.offset = 0,
    this.limit = PbxCdr.pageSize,
  });
  final bool wholePbx;

  /// Nome o numero di uno qualunque dei partecipanti.
  final String search;

  /// Nome o numero di chi chiama / di chi è chiamato (anche secondo e ultimo
  /// partecipante).
  final String callFrom, callTo;

  /// Inizio incluso, fine esclusa.
  final DateTime? from, to;
  final CdrKind kind;
  final CdrOutcome outcome;
  final CdrSort sort;
  final bool descending;
  final int offset, limit;

  CdrQuery page(int offset, [int? limit]) => CdrQuery(
    wholePbx: wholePbx,
    search: search,
    callFrom: callFrom,
    callTo: callTo,
    from: from,
    to: to,
    kind: kind,
    outcome: outcome,
    sort: sort,
    descending: descending,
    offset: offset,
    limit: limit ?? this.limit,
  );
}

/// Una pagina di chiamate e quante sono in tutto con quei filtri.
class CdrPage {
  const CdrPage(this.rows, this.total);
  final List<CdrRecord> rows;
  final int total;
  static const empty = CdrPage([], 0);
}

/// CSV con le colonne dell'esportazione del PBX. Le celle che un foglio di
/// calcolo leggerebbe come formula (`=`, `+`, `-`, `@`, tab, a capo) hanno un
/// apostrofo davanti: i nomi nel CDR li scrive chi chiama.
String cdrCsv(List<CdrRecord> rows) {
  String two(int n) => n.toString().padLeft(2, '0');
  String when(DateTime? t) => t == null
      ? ''
      : '${two(t.day)}/${two(t.month)}/${t.year} '
            '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  String party(String name, String number) =>
      number.isEmpty ? name : (name.isEmpty ? number : '$name<$number>');
  String cell(Object v) {
    var s = '$v';
    if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
    return s.contains(RegExp('[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final out = StringBuffer()
    ..write(
      'Time,Communication Type,Call From,Call To,Second Participant,'
      'Last Participant,Last Status,Queue,Ring Group,Ivr,Call Flow,'
      'Total Duration,Routing Duration,Talk Duration,Hold Duration,'
      'Disconnected by,Call Legs,Source Trunk,Destination Trunk,DID/DDI,'
      'DOD\r\n',
    );
  for (final r in rows) {
    out
      ..writeAll(
        [
          when(r.time),
          r.callType,
          party(r.srcName, r.src),
          party(r.dstName, r.dst),
          party(r.secondDstName, r.secondDst),
          party(r.lastDstName, r.lastDst),
          r.disposition,
          r.queues.join(' | '),
          r.ringGroups.join(' | '),
          r.ivrs.join(' | '),
          r.callFlows.join(' | '),
          r.duration,
          r.ring,
          r.talk,
          r.hold,
          r.disconnectBy,
          r.segments,
          r.srcTrunk,
          r.dstTrunk,
          r.did,
          r.dod,
        ].map(cell),
        ',',
      )
      ..write('\r\n');
  }
  return out.toString();
}

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

  /// Righe al massimo per lettura (pagine ed esportazione).
  static const maxLimit = 500;
  static final _identifier = RegExp(r'^[A-Za-z0-9_]{1,64}$');

  /// [ownExtension] nullo o vuoto = nessun proprio interno (niente righe,
  /// salvo [CdrQuery.wholePbx] concesso dall'amministratore).
  Future<CdrPage> read({
    required String? ownExtension,
    CdrQuery q = const CdrQuery(),
  }) async {
    if (q.wholePbx && !creds.wholePbx) {
      throw StateError('CDR di tutto il PBX non concesso');
    }
    final own = ownExtension ?? '';
    if (!q.wholePbx && own.isEmpty) return CdrPage.empty;
    final db = await _open(creds);
    try {
      final (schema, advanced) = await _findTable(db);
      final where = <String>[];
      final params = <Object?>[];
      String like(String s) => s.trim().isEmpty
          ? ''
          : '%${s.trim().replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}')}%';
      void anyLike(List<String> cols, String value) {
        final v = like(value);
        if (v.isEmpty) return;
        where.add('(${cols.map((c) => '`$c` LIKE ?').join(' OR ')})');
        params.addAll(List.filled(cols.length, v));
      }

      final String table, select, timeCol;
      final Map<CdrSort, String> sortCol;
      if (advanced) {
        table = '`$schema`.`cdr_basic`';
        timeCol = '`timestamp`';
        if (!q.wholePbx) {
          // Anche le gambe (cdr_clip): un gruppo di squillo che ha fatto
          // suonare il proprio interno compare solo lì.
          where.add(
            '(`src` = ? OR `dst` = ? OR `second_dst` = ? OR `last_dst` = ? '
            'OR `uid` IN (SELECT `c`.`uid` FROM `$schema`.`cdr_clip` `c` '
            'WHERE `c`.`src` = ? OR `c`.`dst` = ?))',
          );
          params.addAll(List.filled(6, own));
        }
        const from = ['src', 'srcname'];
        const to = [
          'dst',
          'dstname',
          'second_dst',
          'second_dstname',
          'last_dst',
          'last_dstname',
        ];
        anyLike([...from, ...to], q.search);
        anyLike(from, q.callFrom);
        anyLike(to, q.callTo);
        if (q.from != null) {
          // `timestamp` = microsecondi epoch, indicizzato.
          where.add('`timestamp` >= ?');
          params.add(q.from!.microsecondsSinceEpoch);
        }
        if (q.to != null) {
          where.add('`timestamp` < ?');
          params.add(q.to!.microsecondsSinceEpoch);
        }
        _kindFilter(q.kind, 'call_type', where, params);
        select =
            '`uid`, `datetime`, `src`, `srcname`, `dst`, `dstname`, '
            '`second_dst`, `second_dstname`, `last_dst`, `last_dstname`, '
            '`disposition`, `call_duration`, `routing_duration`, '
            '`talk_duration`, `hold_duration`, `call_type`, `disconnect_by`, '
            '`queues`, `ringgroups`, `ivrs`, `callflows`, `segments`, '
            '`has_recording`';
        sortCol = const {
          CdrSort.time: '`timestamp`',
          CdrSort.type: '`call_type`',
          CdrSort.status: '`disposition`',
          CdrSort.duration: '`call_duration`',
          CdrSort.talk: '`talk_duration`',
        };
      } else {
        table = '`$schema`.`cdr`';
        timeCol = '`datetime`';
        if (!q.wholePbx) {
          where.add('(`src` = ? OR `dst` = ?)');
          params.addAll([own, own]);
        }
        anyLike(['src', 'dst', 'srcname', 'dstname'], q.search);
        anyLike(['src', 'srcname'], q.callFrom);
        anyLike(['dst', 'dstname'], q.callTo);
        if (q.from != null) {
          where.add('`datetime` >= ?');
          params.add(_sqlTime(q.from!));
        }
        if (q.to != null) {
          where.add('`datetime` < ?');
          params.add(_sqlTime(q.to!));
        }
        _kindFilter(q.kind, 'calltype', where, params);
        select =
            '`datetime`, `src`, `srcname`, `dst`, `dstname`, '
            '`dst` AS `last_dst`, `dstname` AS `last_dstname`, '
            '`disposition`, `duration` AS `call_duration`, '
            '`ringduration` AS `routing_duration`, '
            '`talkduration` AS `talk_duration`, `calltype` AS `call_type`';
        sortCol = const {
          CdrSort.time: '`datetime`',
          CdrSort.type: '`calltype`',
          CdrSort.status: '`disposition`',
          CdrSort.duration: '`duration`',
          CdrSort.talk: '`talkduration`',
        };
      }
      _outcomeFilter(q.outcome, where, params);
      final w = _where(where);
      // Limite lato server (MySQL; MariaDB ignora il commento): una lettura
      // lenta si ferma sul PBX prima del timeout del client.
      const hint = '/*+ MAX_EXECUTION_TIME(20000) */';
      final count = await db.query(
        'SELECT $hint COUNT(*) AS `n` FROM $table$w',
        params,
      );
      final total = _int(count.firstOrNull?['n']);
      final dir = q.descending ? 'DESC' : 'ASC';
      final order = q.sort == CdrSort.time
          ? '$timeCol $dir'
          : '${sortCol[q.sort]} $dir, $timeCol DESC';
      final limit = q.limit.clamp(1, maxLimit).toInt();
      final offset = q.offset < 0 ? 0 : q.offset.toInt();
      final rows = [
        for (final r in await db.query(
          'SELECT $hint $select FROM $table$w ORDER BY $order '
          'LIMIT $limit OFFSET $offset',
          params,
        ))
          CdrRecord.fromRow(r),
      ];
      if (!advanced || rows.isEmpty) return CdrPage(rows, total);
      // Gambe delle sole chiamate della pagina: trunk, DID, chi ha squillato.
      final uids = [
        for (final r in rows)
          if (r.uid.isNotEmpty) r.uid,
      ];
      if (uids.isEmpty) return CdrPage(rows, total);
      final legs = <String, List<CdrLeg>>{};
      for (final l in await db.query(
        'SELECT $hint `uid`, `datetime`, `src`, `srcname`, `dst`, '
        '`dstname`, `disposition`, `calltype`, `duration`, `ringduration`, '
        '`talkduration`, `holdduration`, `srctrunk`, `dsttrunk`, '
        '`didnumber`, `dodnumber` FROM `$schema`.`cdr_clip` '
        'WHERE `uid` IN (${List.filled(uids.length, '?').join(', ')}) '
        'ORDER BY `timestamp`',
        uids,
      )) {
        (legs[l['uid'] ?? ''] ??= []).add(CdrLeg.fromRow(l));
      }
      return CdrPage([
        for (final r in rows) r.withLegs(legs[r.uid] ?? const []),
      ], total);
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
    if (kind == CdrKind.all) return;
    where.add('`$typeColumn` = ?');
    params.add(switch (kind) {
      CdrKind.inbound => 'Inbound',
      CdrKind.outbound => 'Outbound',
      _ => 'Internal',
    });
  }

  static void _outcomeFilter(
    CdrOutcome outcome,
    List<String> where,
    List<Object?> params,
  ) {
    switch (outcome) {
      case CdrOutcome.all:
        return;
      case CdrOutcome.unanswered:
        where.add("`disposition` <> 'ANSWERED'");
      default:
        where.add('`disposition` = ?');
        params.add(switch (outcome) {
          CdrOutcome.answered => 'ANSWERED',
          CdrOutcome.noAnswer => 'NO ANSWER',
          CdrOutcome.busy => 'BUSY',
          CdrOutcome.failed => 'FAILED',
          CdrOutcome.voicemail => 'VOICEMAIL',
          _ => 'ABANDONED',
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
