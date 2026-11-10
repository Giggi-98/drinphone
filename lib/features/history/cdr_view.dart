// CDR del PBX (Database Grant) come nella pagina CDR del PBX: pagine con il
// totale, ordinamento dalle intestazioni (di default dalla più recente),
// colonne a scelta, dettaglio con le gambe, esportazione CSV.
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/pbx/pbx_cdr.dart';
import '../../core/pbx/pbx_connection.dart';
import '../shell/widgets.dart';
import 'call_table.dart';

/// Colonne che si possono nascondere (Ora, Da, A, Esito restano sempre).
enum _Col {
  type,
  last,
  route,
  duration,
  ring,
  talk,
  trunk,
  did,
  closedBy,
  legs,
}

class CdrView extends StatefulWidget {
  const CdrView({
    super.key,
    required this.conn,
    required this.filters,
    required this.canDial,
    required this.onCall,
  });
  final PbxConnection conn;

  /// Filtri scelti sopra la tabella (senza ordinamento né pagina).
  final CdrQuery filters;
  final bool canDial;
  final ValueChanged<String> onCall;

  @override
  State<CdrView> createState() => _CdrViewState();
}

class _CdrViewState extends State<CdrView> {
  // Ordinamento, righe per pagina e colonne valgono per la sessione: un
  // filtro nuovo ricrea la vista ma non li perde.
  static CdrSort _sort = CdrSort.time;
  static bool _desc = true;
  static int _pageSize = PbxCdr.pageSize;
  static final _hidden = {
    _Col.last,
    _Col.ring,
    _Col.trunk,
    _Col.did,
    _Col.closedBy,
    _Col.legs,
  };

  /// Righe al massimo in un'esportazione.
  static const _exportCap = 10000;

  CdrPage _data = CdrPage.empty;
  int _page = 0;
  bool _loading = true, _exporting = false;
  String? _error;

  /// Solo l'ultima lettura chiesta aggiorna la tabella.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    // Ogni filtro nuovo crea una vista nuova: digitando si interroga il
    // database una volta sola, quando ci si ferma.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
  }

  CdrQuery get _query => CdrQuery(
    wholePbx: widget.filters.wholePbx,
    search: widget.filters.search,
    callFrom: widget.filters.callFrom,
    callTo: widget.filters.callTo,
    from: widget.filters.from,
    to: widget.filters.to,
    kind: widget.filters.kind,
    outcome: widget.filters.outcome,
    sort: _sort,
    descending: _desc,
    offset: _page * _pageSize,
    limit: _pageSize,
  );

  Future<void> _load() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.conn.readCdr(_query);
      if (!mounted || gen != _gen) return;
      _data = data;
    } catch (e) {
      if (!mounted || gen != _gen) return;
      // Solo il tipo d'errore: niente host o credenziali.
      _error = '${e.runtimeType}';
    }
    setState(() => _loading = false);
  }

  void _sortBy(Object key) {
    final k = key as CdrSort;
    // Stessa colonna: si inverte; colonna nuova: prima dal valore più alto
    // (più recente, più lunga), come nel PBX.
    _desc = k == _sort ? !_desc : true;
    _sort = k;
    _page = 0;
    _load();
  }

  Future<void> _export() async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final loc = await getSaveLocation(
      suggestedName:
          'cdr-${now.year}${two(now.month)}${two(now.day)}-'
          '${two(now.hour)}${two(now.minute)}.csv',
      acceptedTypeGroups: [
        XTypeGroup(label: 'CSV', extensions: const ['csv']),
      ],
    );
    if (loc == null || !mounted) return;
    setState(() => _exporting = true);
    String msg;
    try {
      final all = <CdrRecord>[];
      while (all.length < _exportCap) {
        final p = await widget.conn.readCdr(
          _query.page(all.length, PbxCdr.maxLimit),
        );
        all.addAll(p.rows);
        if (p.rows.length < PbxCdr.maxLimit) break;
      }
      final rows = all.take(_exportCap).toList();
      // BOM: Excel legge gli accenti come UTF-8.
      await File(loc.path).writeAsString('﻿${cdrCsv(rows)}');
      msg = tr('Esportate {n} chiamate', {'n': rows.length});
    } catch (e) {
      msg = tr('Esportazione non riuscita: {e}', {'e': e.runtimeType});
    }
    if (!mounted) return;
    setState(() => _exporting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------ Colonne

  static String _colName(_Col c) => switch (c) {
    _Col.type => tr('Tipo'),
    _Col.last => tr('Ultimo partecipante'),
    _Col.route => tr('Coda / gruppo / IVR'),
    _Col.duration => tr('Durata'),
    _Col.ring => tr('Squillo'),
    _Col.talk => tr('Conversazione'),
    _Col.trunk => tr('Trunk'),
    _Col.did => tr('DID / DOD'),
    _Col.closedBy => tr('Chiuso da'),
    _Col.legs => tr('Gambe'),
  };

  /// Colonne nell'ordine del PBX, con la cella di ogni chiamata.
  List<(CallColumn, Widget Function(CdrRecord))> _columns(DrinColors c) {
    bool on(_Col x) => !_hidden.contains(x);
    return [
      (
        CallColumn(tr('Ora'), width: 112, sortKey: CdrSort.time),
        (r) => WhenCell(r.time),
      ),
      if (on(_Col.type))
        (
          CallColumn(
            tr('Tipo'),
            width: 116,
            hideBelow: 900,
            sortKey: CdrSort.type,
          ),
          (r) => _kindCell(r),
        ),
      (
        CallColumn(tr('Da'), flex: 3),
        (r) => party(r.srcName, r.src),
      ),
      (
        CallColumn(tr('A'), flex: 3),
        (r) {
          // Gruppo, coda, IVR: chi ha risposto (o l'ultimo squillo), se la
          // colonna Ultimo partecipante è nascosta.
          final via =
              !on(_Col.last) && r.lastDst.isNotEmpty && r.lastDst != r.dst;
          return party(
            r.dstName,
            r.dst,
            extra: via
                ? SubLine(
                    Icons.subdirectory_arrow_right_rounded,
                    r.answered
                        ? tr('Risposto da {n}', {'n': _last(r)})
                        : tr('Ultimo squillo: {n}', {'n': _last(r)}),
                  )
                : null,
          );
        },
      ),
      if (on(_Col.last))
        (
          CallColumn(tr('Ultimo partecipante'), flex: 3),
          (r) => party(r.lastDstName, r.lastDst),
        ),
      (
        CallColumn(tr('Esito'), width: 132, sortKey: CdrSort.status),
        (r) {
          final (label, color) = outcome(r.disposition, c);
          return OutcomePill(label, color);
        },
      ),
      if (on(_Col.route))
        (
          CallColumn(tr('Coda / gruppo / IVR'), flex: 2, hideBelow: 760),
          (r) => _RouteCell(r),
        ),
      if (on(_Col.duration))
        (
          CallColumn(
            tr('Durata'),
            width: 92,
            end: true,
            hideBelow: 1000,
            sortKey: CdrSort.duration,
          ),
          (r) => DurationCell(r.duration),
        ),
      if (on(_Col.ring))
        (
          CallColumn(tr('Squillo'), width: 76, end: true),
          (r) => DurationCell(r.ring),
        ),
      if (on(_Col.talk))
        (
          CallColumn(
            tr('Conversazione'),
            width: 128,
            end: true,
            hideBelow: 680,
            sortKey: CdrSort.talk,
          ),
          (r) => DurationCell(r.talk, strong: true),
        ),
      if (on(_Col.trunk))
        (
          CallColumn(tr('Trunk'), flex: 2),
          (r) => _text(r.srcTrunk.isNotEmpty ? r.srcTrunk : r.dstTrunk, c),
        ),
      if (on(_Col.did))
        (
          CallColumn(tr('DID / DOD'), width: 132),
          (r) => _text(r.did.isNotEmpty ? r.did : r.dod, c, number: true),
        ),
      if (on(_Col.closedBy))
        (CallColumn(tr('Chiuso da'), flex: 2), (r) => _text(r.disconnectBy, c)),
      if (on(_Col.legs))
        (
          CallColumn(tr('Gambe'), width: 64, end: true),
          (r) => _text(
            '${r.segments > 0 ? r.segments : r.legs.length}',
            c,
            number: true,
          ),
        ),
    ];
  }

  static String _last(CdrRecord r) =>
      r.lastDstName.isNotEmpty ? '${r.lastDstName} · ${r.lastDst}' : r.lastDst;

  static Widget _text(String s, DrinColors c, {bool number = false}) => Text(
    s.isEmpty ? '—' : s,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: (number ? DrinText.number : DrinText.body).copyWith(
      color: s.isEmpty ? c.muted : c.ink,
    ),
  );

  static Widget _kindCell(CdrRecord r) {
    final (icon, label) = kind(r.callType);
    return KindCell(icon, label);
  }

  /// Tipo di chiamata a parole, con l'icona.
  static (IconData, String) kind(String t) => switch (t) {
    'Inbound' => (Icons.call_received_rounded, tr('In arrivo')),
    'Outbound' => (Icons.call_made_rounded, tr('In uscita')),
    'Internal' => (Icons.swap_horiz_rounded, tr('Interna')),
    _ => (Icons.call_rounded, t),
  };

  /// Esito come lo scrive il PBX, a parole e col suo colore.
  static (String, Color) outcome(String d, DrinColors c) =>
      switch (d.toUpperCase()) {
        'ANSWERED' => (tr('Risposta'), c.freeText),
        'NO ANSWER' => (tr('Non risposta'), c.busyText),
        'ABANDONED' => (tr('Abbandonata'), c.busyText),
        'BUSY' => (tr('Occupato'), c.away),
        'FAILED' => (tr('Non riuscita'), c.busyText),
        'VOICEMAIL' => (tr('Casella vocale'), c.primary),
        _ => (d, c.away),
      };

  CallRow _row(CdrRecord r, List<Widget Function(CdrRecord)> cells) {
    // Chi richiamare: l'altro capo rispetto al proprio interno; nel CDR di
    // tutto il PBX chi ha chiamato.
    final own = widget.conn.voicemailOf;
    final other = own != null && r.src == own ? r.dst : r.src;
    return CallRow(
      cells: [for (final f in cells) f(r)],
      callTooltip: tr('Richiama {n}', {'n': other}),
      call: widget.canDial && other.isNotEmpty
          ? () => widget.onCall(other)
          : null,
      onTap: () =>
          showDialog<void>(context: context, builder: (_) => _CdrDetails(r)),
    );
  }

  // --------------------------------------------------------------- Vista

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final cols = _columns(c);
    final total = _data.total;
    final toolbar = Row(
      children: [
        Text(
          _loading && _data.rows.isEmpty
              ? tr('Lettura del CDR…')
              : tr('{n} chiamate', {'n': total}),
          style: DrinText.label.copyWith(color: c.muted),
        ),
        if (_loading && _data.rows.isNotEmpty) ...[
          const SizedBox(width: DrinSpace.s2),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
        const Spacer(),
        IconButton(
          tooltip: tr('Aggiorna'),
          onPressed: _loading ? null : _load,
          icon: Icon(Icons.refresh_rounded, color: c.muted),
        ),
        PopupMenuButton<_Col>(
          tooltip: tr('Colonne'),
          icon: Icon(Icons.view_column_outlined, color: c.muted),
          onSelected: (x) => setState(
            () => _hidden.contains(x) ? _hidden.remove(x) : _hidden.add(x),
          ),
          itemBuilder: (_) => [
            for (final x in _Col.values)
              CheckedPopupMenuItem(
                value: x,
                checked: !_hidden.contains(x),
                child: Text(_colName(x)),
              ),
          ],
        ),
        const SizedBox(width: DrinSpace.s1),
        OutlinedButton.icon(
          onPressed: _exporting || total == 0 ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded, size: 16),
          label: Text(tr('Esporta CSV')),
        ),
      ],
    );
    final Widget body;
    if (_data.rows.isEmpty) {
      body = Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error != null
                        ? tr('CDR non leggibile: {e}', {'e': _error!})
                        : widget.conn.voicemailOf == null &&
                              !widget.filters.wholePbx
                        ? tr('Nessun proprio interno per questo PBX.')
                        : tr('Nessuna chiamata.'),
                    style: DrinText.body.copyWith(
                      color: _error != null ? c.busyText : c.muted,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: DrinSpace.s3),
                    OutlinedButton(
                      onPressed: _load,
                      child: Text(tr('Riprova')),
                    ),
                  ],
                ],
              ),
      );
    } else {
      final cells = [for (final x in cols) x.$2];
      body = CallTable(
        columns: [for (final x in cols) x.$1],
        rows: [for (final r in _data.rows) _row(r, cells)],
        sortKey: _sort,
        descending: _desc,
        onSort: _loading ? null : _sortBy,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        if (_error != null && _data.rows.isNotEmpty)
          Text(
            tr('CDR non leggibile: {e}', {'e': _error!}),
            style: DrinText.detail.copyWith(color: c.busyText),
          ),
        Expanded(child: body),
        const SizedBox(height: DrinSpace.s2),
        Row(
          children: [
            Expanded(
              child: Pager(
                total: total,
                page: _page,
                pageSize: _pageSize,
                onPage: (i) {
                  _page = i;
                  _load();
                },
              ),
            ),
            const SizedBox(width: DrinSpace.s3),
            PopupMenuButton<int>(
              tooltip: tr('Righe per pagina'),
              initialValue: _pageSize,
              onSelected: (n) {
                _pageSize = n;
                _page = 0;
                _load();
              },
              itemBuilder: (_) => [
                for (final n in const [20, 50, 100, 200])
                  PopupMenuItem(
                    value: n,
                    child: Text(tr('{n} per pagina', {'n': n})),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(DrinSpace.s2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('{n} per pagina', {'n': _pageSize}),
                      style: DrinText.label.copyWith(color: c.muted),
                    ),
                    Icon(Icons.expand_more_rounded, size: 16, color: c.muted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// `Nome<numero>` del PBX in "Nome · numero".
String _pretty(String s) {
  final m = RegExp(r'^(.*?)\s*<([^>]*)>$').firstMatch(s.trim());
  return m == null ? s : '${m[1]} · ${m[2]}';
}

/// Coda, gruppo di squillo, IVR, call flow attraversati: il primo con la
/// sua icona, gli altri nel tooltip.
class _RouteCell extends StatelessWidget {
  const _RouteCell(this.r);
  final CdrRecord r;

  static List<(IconData, String)> steps(CdrRecord r) => [
    for (final s in r.ivrs) (Icons.account_tree_outlined, _pretty(s)),
    for (final s in r.callFlows) (Icons.alt_route_rounded, _pretty(s)),
    for (final s in r.queues) (Icons.groups_outlined, _pretty(s)),
    for (final s in r.ringGroups) (Icons.ring_volume_outlined, _pretty(s)),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final all = steps(r);
    if (all.isEmpty) {
      return Text('—', style: DrinText.body.copyWith(color: c.muted));
    }
    final (icon, text) = all.last;
    return Tooltip(
      message: all.map((e) => e.$2).join(' → '),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: c.primary),
          const SizedBox(width: DrinSpace.s2),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DrinText.body.copyWith(color: c.ink),
            ),
          ),
          if (all.length > 1) ...[
            const SizedBox(width: DrinSpace.s1),
            Text(
              '+${all.length - 1}',
              style: DrinText.label.copyWith(color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dettaglio di una chiamata a 3 pannelli (come CDR Details di Yeastar):
/// Riepilogo a sinistra, Timeline per Leg al centro (da evento 30039 o
/// ricostruita dalle gambe CDR), Ripartizione tempi con ciambella a destra.
class _CdrDetails extends StatefulWidget {
  const _CdrDetails(this.r);
  final CdrRecord r;

  static String _party(String name, String number) => number.isEmpty
      ? name
      : name.isEmpty || name == number
      ? number
      : '$name · $number';

  static String _when(DateTime? t) {
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// Formato `00:00:31` per la timeline e la ripartizione tempi.
  static String _hms(int s) {
    final v = s < 0 ? 0 : s;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = v ~/ 3600;
    final m = (v % 3600) ~/ 60;
    final sec = v % 60;
    return '${two(h)}:${two(m)}:${two(sec)}';
  }

  /// Formato offset `00:05` dall'inizio chiamata.
  static String _mmss(int s) {
    final v = s < 0 ? 0 : s;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = v ~/ 3600;
    final m = (v % 3600) ~/ 60;
    final sec = v % 60;
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  @override
  State<_CdrDetails> createState() => _CdrDetailsState();
}

enum _StepTone { info, answered, ended }

class _TimelineStep {
  const _TimelineStep({
    required this.offsetSec,
    required this.title,
    this.subtitle = '',
    this.icon,
    this.tone = _StepTone.info,
    this.children = const [],
  });
  final int offsetSec;
  final String title;
  final String subtitle;
  final IconData? icon;
  final _StepTone tone;
  final List<(_TimelineStep, bool)> children;
}

class _TimelineLeg {
  const _TimelineLeg(this.number, this.steps);
  final int number;
  final List<_TimelineStep> steps;
}

class _CdrDetailsState extends State<_CdrDetails> {
  final Set<String> _collapsed = {};

  CdrRecord get r => widget.r;

  String _closedByLabel() {
    final raw = r.disconnectBy.trim();
    if (raw.isEmpty) return '';
    if (raw.toLowerCase() == 'external') {
      final ext = r.callType == 'Inbound'
          ? _CdrDetails._party(r.srcName, r.src)
          : '';
      return ext.isEmpty
          ? tr('Interlocutore esterno')
          : '${tr('Interlocutore esterno')} ($ext)';
    }
    return _pretty(raw);
  }

  String _closerParty(String finalTarget) {
    final raw = r.disconnectBy.trim();
    if (raw.toLowerCase() == 'external') {
      return r.callType == 'Inbound'
          ? _CdrDetails._party(r.srcName, r.src)
          : finalTarget;
    }
    if (raw.isNotEmpty) return _pretty(raw);
    return finalTarget.isNotEmpty
        ? finalTarget
        : _CdrDetails._party(r.srcName, r.src);
  }

  List<_TimelineLeg> _buildTimeline(DrinColors c) {
    if (r.timeline.isNotEmpty) {
      return _fromEvent30039(c);
    }
    return _fromCdrRecord(c);
  }

  List<_TimelineLeg> _fromEvent30039(DrinColors c) {
    final t0 =
        r.time ??
        r.timeline
            .map((l) => l.timeStart)
            .whereType<DateTime>()
            .firstOrNull;
    int off(DateTime? t, int fallback) =>
        t != null && t0 != null ? math.max(0, t.difference(t0).inSeconds) : fallback;
    final out = <_TimelineLeg>[];
    for (final leg in r.timeline) {
      final steps = <_TimelineStep>[];
      final legStart = off(leg.timeStart, 0);
      if (leg.events.isEmpty) {
        if (leg.callFrom.isNotEmpty) {
          steps.add(
            _TimelineStep(
              offsetSec: legStart,
              icon: Icons.call_rounded,
              title: tr('Chiamata da {n}', {'n': _pretty(leg.callFrom)}),
              subtitle: [
                if (leg.srcTrunk.isNotEmpty) 'via ${leg.srcTrunk}',
                if (leg.dstTrunk.isNotEmpty) '→ ${leg.dstTrunk}',
              ].join(' · '),
            ),
          );
        }
        if (leg.callTo.isNotEmpty) {
          steps.add(
            _TimelineStep(
              offsetSec: legStart,
              title: tr('Tentativo di contatto {n}', {'n': _pretty(leg.callTo)}),
              subtitle: leg.ring > 0
                  ? tr('Squillo per {d}', {
                      'd': _CdrDetails._hms(leg.ring),
                    })
                  : '',
            ),
          );
        }
        if (leg.status.toUpperCase() == 'ANSWERED') {
          steps.add(
            _TimelineStep(
              offsetSec: legStart + leg.ring,
              icon: Icons.call_rounded,
              tone: _StepTone.answered,
              title: tr('{n} ha risposto alla chiamata', {
                'n': _pretty(leg.callTo),
              }),
              subtitle:
                  '${tr('Conversazione')}: ${_CdrDetails._hms(leg.talk)}',
            ),
          );
        }
      } else {
        for (final ev in leg.events) {
          final evOff = off(ev.time, legStart);
          final name = ev.name.toLowerCase();
          final target = _pretty(
            ev.content['dst'] ?? ev.content['target'] ?? ev.content['name'] ?? leg.callTo,
          );
          final sub = [
            if ((ev.content['trunk'] ?? '').isNotEmpty)
              'via ${ev.content['trunk']}',
            if ((ev.content['endpoint'] ?? '').isNotEmpty)
              ev.content['endpoint']!,
          ].join(' · ');
          if (name.contains('call_from') || name == 'start') {
            steps.add(
              _TimelineStep(
                offsetSec: evOff,
                icon: Icons.call_rounded,
                title: tr('Chiamata da {n}', {
                  'n': _pretty(ev.content['src'] ?? leg.callFrom),
                }),
                subtitle: sub.isNotEmpty
                    ? sub
                    : (leg.srcTrunk.isNotEmpty ? 'via ${leg.srcTrunk}' : ''),
              ),
            );
          } else if (name.contains('route')) {
            steps.add(
              _TimelineStep(
                offsetSec: evOff,
                title: tr('Instradata a {d}', {'d': target}),
                subtitle: sub,
              ),
            );
          } else if (name.contains('enter')) {
            steps.add(
              _TimelineStep(
                offsetSec: evOff,
                title: tr('Ingresso in {d}', {'d': target}),
                subtitle: leg.ring > 0
                    ? tr('Squillo per {d}', {
                        'd': _CdrDetails._hms(leg.ring),
                      })
                    : sub,
              ),
            );
          } else if (name.contains('assign')) {
            final count = int.tryParse(ev.content['count'] ?? '') ?? 1;
            steps.add(
              _TimelineStep(
                offsetSec: evOff,
                title: tr('Assegnata a {n} interni', {'n': count}),
                subtitle: ev.rawContent.isNotEmpty ? ev.rawContent : sub,
              ),
            );
          } else if (name.contains('tried') || name.contains('dial')) {
            steps.add(
              _TimelineStep(
                offsetSec: evOff,
                title: tr('Tentativo di contatto {n}', {'n': target}),
                subtitle: sub,
              ),
            );
          } else if (name.contains('answer') && !name.contains('no_answer')) {
            steps.add(
              _TimelineStep(
                offsetSec: evOff,
                icon: Icons.call_rounded,
                tone: _StepTone.answered,
                title: tr('{n} ha risposto alla chiamata', {'n': target}),
                subtitle:
                    '${tr('Conversazione')}: ${_CdrDetails._hms(leg.talk)}',
              ),
            );
          } else if (name.contains('hang') ||
              name.contains('hung') ||
              name.contains('end')) {
            steps.add(
              _TimelineStep(
                offsetSec: evOff,
                icon: Icons.call_end_rounded,
                tone: _StepTone.ended,
                title: tr('{n} ha riagganciato', {
                  'n': _pretty(
                    ev.content['by'] ?? ev.content['party'] ?? _closerParty(target),
                  ),
                }),
              ),
            );
          } else {
            steps.add(
              _TimelineStep(
                offsetSec: evOff,
                title: '${ev.name}${target.isNotEmpty ? ': $target' : ''}',
                subtitle: sub,
              ),
            );
          }
        }
      }
      if (steps.isNotEmpty) {
        out.add(_TimelineLeg(leg.leg, steps));
      }
    }
    return out.isEmpty ? _fromCdrRecord(c) : out;
  }

  List<_TimelineLeg> _fromCdrRecord(DrinColors c) {
    final t0 =
        r.time ?? (r.legs.isNotEmpty ? r.legs.first.time : null);
    int off(DateTime? t, int fallback) =>
        t != null && t0 != null ? math.max(0, t.difference(t0).inSeconds) : fallback;

    final caller = _CdrDetails._party(r.srcName, r.src);
    final firstDst = _CdrDetails._party(r.dstName, r.dst);
    final finalTarget = r.lastDst.isNotEmpty
        ? _CdrDetails._party(r.lastDstName, r.lastDst)
        : firstDst;

    final leg1 = <_TimelineStep>[
      _TimelineStep(
        offsetSec: 0,
        icon: Icons.call_rounded,
        title: tr('Chiamata da {n}', {'n': caller.isEmpty ? '—' : caller}),
        subtitle: [
          if (r.srcTrunk.isNotEmpty) 'via ${r.srcTrunk}',
          if (r.did.isNotEmpty) 'DID ${r.did}',
        ].join(' · '),
      ),
    ];

    for (final s in r.ivrs) {
      leg1.add(
        _TimelineStep(
          offsetSec: 0,
          title: '${tr('IVR')}: ${_pretty(s)}',
        ),
      );
    }
    for (final s in r.callFlows) {
      leg1.add(
        _TimelineStep(
          offsetSec: 0,
          title: '${tr('Call flow')}: ${_pretty(s)}',
        ),
      );
    }

    // Individua se la chiamata è passata per un gruppo/coda (es. 6300 -> 200)
    final hasGroupRoute =
        r.queues.isNotEmpty ||
        r.ringGroups.isNotEmpty ||
        (r.lastDst.isNotEmpty && r.lastDst != r.dst) ||
        r.legs.length > 1;

    // Se la prima gamba di cdr_clip rappresenta il gruppo/coda (stesso dst del
    // record principale mentre le successive puntano agli interni), la usiamo
    // come intestazione del gruppo e le successive come interni assegnati.
    final bool firstLegIsContainer =
        r.legs.length > 1 &&
        r.legs.first.dst == r.dst &&
        r.legs.skip(1).any((l) => l.dst != r.dst);
    final memberLegs = firstLegIsContainer
        ? r.legs.skip(1).toList()
        : (r.legs.length > 1 ? r.legs : const <CdrLeg>[]);
    final groupRing = firstLegIsContainer && r.legs.first.ring > 0
        ? r.legs.first.ring
        : r.ring;

    if (hasGroupRoute) {
      final groupLabel = r.ringGroups.isNotEmpty
          ? _pretty(r.ringGroups.first)
          : r.queues.isNotEmpty
          ? _pretty(r.queues.first)
          : firstDst;
      if (groupLabel.isNotEmpty &&
          (groupLabel != finalTarget || memberLegs.isNotEmpty)) {
        leg1.add(
          _TimelineStep(
            offsetSec: 0,
            title: tr('Instradata a {d}', {'d': groupLabel}),
            subtitle: r.dstTrunk.isNotEmpty ? 'via ${r.dstTrunk}' : '',
          ),
        );
        leg1.add(
          _TimelineStep(
            offsetSec: 0,
            title: tr('Ingresso in {d}', {'d': groupLabel}),
            subtitle: tr('Squillo per {d}', {
              'd': _CdrDetails._hms(groupRing),
            }),
          ),
        );
      }
      if (memberLegs.isNotEmpty) {
        final assignOff = off(memberLegs.first.time, 1);
        final children = <(_TimelineStep, bool)>[
          for (final ml in memberLegs)
            () {
              final who = _CdrDetails._party(ml.dstName, ml.dst);
              final ans = ml.disposition.toUpperCase() == 'ANSWERED';
              final sub = [
                if (ml.srcTrunk.isNotEmpty) ml.srcTrunk,
                if (ml.dstTrunk.isNotEmpty) ml.dstTrunk,
              ].join(' → ');
              final String line;
              if (ans) {
                line = tr('{n}: Ha risposto alla chiamata', {'n': who});
              } else if (r.answered) {
                line = tr(
                  '{n}: Risposto da un altro interno dopo {d}',
                  {'n': who, 'd': _CdrDetails._hms(ml.ring)},
                );
              } else {
                final (outLabel, _) = _CdrViewState.outcome(ml.disposition, c);
                line = '$who: $outLabel (${_CdrDetails._hms(ml.ring)})';
              }
              return (
                _TimelineStep(
                  offsetSec: off(ml.time, assignOff),
                  title: line,
                  subtitle: sub,
                ),
                ans,
              );
            }(),
        ];
        leg1.add(
          _TimelineStep(
            offsetSec: assignOff,
            title: tr('Assegnata a {n} interni', {'n': memberLegs.length}),
            children: children,
          ),
        );
      }
    }

    // Passi finali: contatto dell'interlocutore, risposta/mancata risposta e
    // chiusura. Se c'è stato instradamento su gruppo/coda li separiamo in Leg 2
    // come nel CDR Details di Yeastar.
    final answeredLeg = memberLegs
        .where((l) => l.disposition.toUpperCase() == 'ANSWERED')
        .firstOrNull;
    final contactOff = answeredLeg != null
        ? off(answeredLeg.time, 1)
        : (hasGroupRoute ? 1 : 0);
    final answerOff = r.ring > 0 ? r.ring : contactOff;
    final endOff = math.max(r.duration, answerOff + r.talk);
    final closer = _closerParty(finalTarget);

    final handlingSteps = <_TimelineStep>[
      if (finalTarget.isNotEmpty)
        _TimelineStep(
          offsetSec: contactOff,
          title: tr('Tentativo di contatto {n}', {'n': finalTarget}),
          subtitle: r.dstTrunk.isNotEmpty
              ? 'via ${r.dstTrunk}'
              : (r.dod.isNotEmpty ? 'DOD ${r.dod}' : ''),
        ),
      if (r.answered)
        _TimelineStep(
          offsetSec: answerOff,
          icon: Icons.call_rounded,
          tone: _StepTone.answered,
          title: tr('{n} ha risposto alla chiamata', {
            'n': finalTarget.isEmpty ? '—' : finalTarget,
          }),
          subtitle: [
            '${tr('Conversazione')}: ${_CdrDetails._hms(r.talk)}',
            if (r.hold > 0) '${tr('In attesa')}: ${_CdrDetails._hms(r.hold)}',
          ].join(' · '),
        )
      else
        _TimelineStep(
          offsetSec: answerOff,
          icon: Icons.phone_missed_rounded,
          tone: _StepTone.ended,
          title:
              '${_CdrViewState.outcome(r.disposition, c).$1} (${_CdrDetails._hms(r.ring)})',
        ),
      _TimelineStep(
        offsetSec: endOff,
        icon: Icons.call_end_rounded,
        tone: _StepTone.ended,
        title: tr('{n} ha riagganciato', {
          'n': closer.isEmpty ? '—' : closer,
        }),
      ),
    ];

    if (hasGroupRoute) {
      return [_TimelineLeg(1, leg1), _TimelineLeg(2, handlingSteps)];
    }
    return [
      _TimelineLeg(1, [...leg1, ...handlingSteps]),
    ];
  }

  // --------------------------------------------------- Pannello 1: Riepilogo

  Widget _buildBasicCard(DrinColors c, String outcomeLabel, Color outcomeColor) {
    final (kindIcon, kindLabel) = _CdrViewState.kind(r.callType);
    final closedBy = _closedByLabel();
    final extraFields = <(String, String, bool)>[
      if (r.ivrs.isNotEmpty) (tr('IVR'), r.ivrs.map(_pretty).join(', '), false),
      if (r.callFlows.isNotEmpty)
        (tr('Call flow'), r.callFlows.map(_pretty).join(', '), false),
      if (r.queues.isNotEmpty)
        (tr('Coda'), r.queues.map(_pretty).join(', '), false),
      if (r.ringGroups.isNotEmpty)
        (tr('Gruppo di squillo'), r.ringGroups.map(_pretty).join(', '), false),
      if (r.srcTrunk.isNotEmpty) (tr('Trunk in ingresso'), r.srcTrunk, false),
      if (r.dstTrunk.isNotEmpty) (tr('Trunk in uscita'), r.dstTrunk, false),
      if (r.did.isNotEmpty) (tr('DID'), r.did, true),
      if (r.dod.isNotEmpty) (tr('DOD'), r.dod, true),
      if (r.hasRecording) (tr('Registrazione'), tr('Sì'), false),
    ];

    Widget sectionItem(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: DrinSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: DrinText.detail.copyWith(color: c.muted)),
          const SizedBox(height: DrinSpace.s1),
          child,
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(DrinRadius.panel),
        border: Border.all(color: c.line),
      ),
      padding: const EdgeInsets.all(DrinSpace.s4),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Riepilogo'),
              style: DrinText.heading.copyWith(color: c.ink),
            ),
            const SizedBox(height: DrinSpace.s3),
            if (r.uid.isNotEmpty)
              sectionItem(
                tr('ID'),
                SelectableText(
                  r.uid,
                  style: DrinText.number.copyWith(color: c.ink),
                ),
              ),
            sectionItem(
              tr('Ora'),
              SelectableText(
                _CdrDetails._when(r.time),
                style: DrinText.number.copyWith(color: c.ink),
              ),
            ),
            sectionItem(tr('Tipo'), KindCell(kindIcon, kindLabel)),
            sectionItem(
              tr('Da'),
              _PartyChip(name: r.srcName, number: r.src, accent: c.primary),
            ),
            sectionItem(
              tr('A'),
              _PartyChip(name: r.dstName, number: r.dst, accent: c.squillo),
            ),
            if (r.secondDst.isNotEmpty && r.secondDst != r.lastDst)
              sectionItem(
                tr('Secondo partecipante'),
                _PartyChip(
                  name: r.secondDstName,
                  number: r.secondDst,
                  accent: c.brand,
                ),
              ),
            if (r.lastDst.isNotEmpty)
              sectionItem(
                tr('Ultimo partecipante'),
                _PartyChip(
                  name: r.lastDstName,
                  number: r.lastDst,
                  accent: c.free,
                ),
              ),
            sectionItem(
              tr('Esito'),
              OutcomePill(outcomeLabel, outcomeColor),
            ),
            if (closedBy.isNotEmpty)
              sectionItem(
                tr('Chiuso da'),
                SelectableText(
                  closedBy,
                  style: DrinText.body.copyWith(color: c.ink),
                ),
              ),
            if (extraFields.isNotEmpty) ...[
              Divider(height: DrinSpace.s5, color: c.line),
              for (final (label, val, isNum) in extraFields)
                sectionItem(
                  label,
                  SelectableText(
                    val,
                    style: (isNum ? DrinText.number : DrinText.body).copyWith(
                      color: c.ink,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------- Pannello 2: Timeline

  Widget _buildTimelineCard(DrinColors c) {
    final legs = _buildTimeline(c);
    return Container(
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(DrinRadius.panel),
        border: Border.all(color: c.line),
      ),
      padding: const EdgeInsets.all(DrinSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Timeline'),
            style: DrinText.heading.copyWith(color: c.ink),
          ),
          const SizedBox(height: DrinSpace.s3),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var li = 0; li < legs.length; li++) ...[
                    if (li > 0) const SizedBox(height: DrinSpace.s3),
                    Text(
                      tr('Leg {n}', {'n': legs[li].number}),
                      style: DrinText.heading.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: DrinSpace.s2),
                    for (var si = 0; si < legs[li].steps.length; si++)
                      _buildStepRow(
                        c,
                        legs[li].steps[si],
                        keyId: '${legs[li].number}-$si',
                        drawLineBelow:
                            si < legs[li].steps.length - 1 ||
                            li < legs.length - 1,
                      ),
                  ],
                  const SizedBox(height: DrinSpace.s2),
                  Text(
                    tr('Fine chiamata'),
                    style: DrinText.heading.copyWith(color: c.ink),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(
    DrinColors c,
    _TimelineStep step, {
    required String keyId,
    required bool drawLineBelow,
  }) {
    final collapsed = _collapsed.contains(keyId);
    final (Color accent, Color softBg) = switch (step.tone) {
      _StepTone.answered => (c.free, c.free.withValues(alpha: 0.16)),
      _StepTone.ended => (c.busy, c.busy.withValues(alpha: 0.16)),
      _StepTone.info => (c.primary, c.primary.withValues(alpha: 0.16)),
    };

    final Widget indicator;
    if (step.icon != null) {
      indicator = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: softBg,
          borderRadius: BorderRadius.circular(DrinRadius.control),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Icon(step.icon, size: 14, color: accent),
      );
    } else {
      indicator = SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.raised,
              border: Border.all(color: accent, width: 2),
            ),
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                indicator,
                if (drawLineBelow)
                  Expanded(
                    child: Container(width: 1.5, color: c.line),
                  ),
              ],
            ),
          ),
          const SizedBox(width: DrinSpace.s2),
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                _CdrDetails._mmss(step.offsetSec),
                style: DrinText.number.copyWith(color: c.muted),
              ),
            ),
          ),
          const SizedBox(width: DrinSpace.s2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: DrinSpace.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      step.title,
                      style: DrinText.label.copyWith(color: c.ink),
                    ),
                  ),
                  if (step.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      step.subtitle,
                      style: DrinText.detail.copyWith(color: c.muted),
                    ),
                  ],
                  if (step.children.isNotEmpty) ...[
                    const SizedBox(height: DrinSpace.s1),
                    InkWell(
                      borderRadius: BorderRadius.circular(DrinRadius.control),
                      onTap: () => setState(() {
                        if (collapsed) {
                          _collapsed.remove(keyId);
                        } else {
                          _collapsed.add(keyId);
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              collapsed ? tr('Espandi') : tr('Comprimi'),
                              style: DrinText.detail.copyWith(color: c.primary),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              collapsed
                                  ? Icons.expand_more_rounded
                                  : Icons.expand_less_rounded,
                              size: 14,
                              color: c.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!collapsed) ...[
                      const SizedBox(height: DrinSpace.s2),
                      for (final (child, isAns) in step.children)
                        Padding(
                          padding: const EdgeInsets.only(bottom: DrinSpace.s2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isAns ? c.free : c.primary,
                                      width: 1.8,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: DrinSpace.s2),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      child.title,
                                      style: DrinText.body.copyWith(
                                        color: c.ink,
                                      ),
                                    ),
                                    if (child.subtitle.isNotEmpty)
                                      Text(
                                        child.subtitle,
                                        style: DrinText.detail.copyWith(
                                          color: c.muted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------ Pannello 3: Ripartizione tempi

  Widget _buildBreakdownCard(DrinColors c) {
    final ring = math.max(0, r.ring);
    final talk = math.max(0, r.talk);
    final hold = math.max(0, r.hold);
    final sumParts = ring + talk + hold;
    final total = math.max(r.duration, sumParts);
    final denom = sumParts > 0 ? sumParts : 1;

    String pct(int v) =>
        sumParts <= 0 ? '0.0%' : '${(v * 100.0 / denom).toStringAsFixed(1)}%';

    Widget topStat(String label, int sec) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DrinText.detail.copyWith(color: c.muted),
          ),
          const SizedBox(height: DrinSpace.s1),
          Text(
            _CdrDetails._hms(sec),
            style: DrinText.number.copyWith(
              color: c.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    Widget legendRow(Color dotColor, String label, int sec) => Padding(
      padding: const EdgeInsets.symmetric(vertical: DrinSpace.s1),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: DrinSpace.s2),
          Expanded(
            child: Text(
              label,
              style: DrinText.detail.copyWith(color: c.muted),
            ),
          ),
          Text(
            '${_CdrDetails._hms(sec)} · ${pct(sec)}',
            style: DrinText.number.copyWith(color: c.ink),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(DrinRadius.panel),
        border: Border.all(color: c.line),
      ),
      padding: const EdgeInsets.all(DrinSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Ripartizione tempi'),
            style: DrinText.heading.copyWith(color: c.ink),
          ),
          const SizedBox(height: DrinSpace.s3),
          Row(
            children: [
              topStat(tr('Durata totale'), total),
              const SizedBox(width: DrinSpace.s2),
              topStat(tr('Squillo'), ring),
              const SizedBox(width: DrinSpace.s2),
              topStat(tr('Conversazione'), talk),
            ],
          ),
          const SizedBox(height: DrinSpace.s5),
          Center(
            child: SizedBox(
              width: 168,
              height: 168,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(168),
                    painter: _DonutPainter(
                      slices: [
                        (ring.toDouble(), c.free),
                        (talk.toDouble(), c.squillo),
                        (hold.toDouble(), c.brand),
                      ],
                      emptyColor: c.line,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _CdrDetails._hms(total),
                        style: DrinText.number.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        tr('Durata totale'),
                        style: DrinText.detail.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: DrinSpace.s5),
          legendRow(c.free, tr('Squillo'), ring),
          legendRow(c.squillo, tr('Conversazione'), talk),
          legendRow(c.brand, tr('In attesa'), hold),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final (outcomeLabel, outcomeColor) = _CdrViewState.outcome(
      r.disposition,
      c,
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(DrinSpace.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    tr('Dettagli chiamata'),
                    style: DrinText.title.copyWith(color: c.ink),
                  ),
                  if (r.uid.isNotEmpty) ...[
                    const SizedBox(width: DrinSpace.s3),
                    Flexible(
                      child: SelectableText(
                        '(${tr('ID')} ${r.uid})',
                        maxLines: 1,
                        style: DrinText.number.copyWith(color: c.muted),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (r.uid.isNotEmpty) const Spacer(),
                  OutcomePill(outcomeLabel, outcomeColor),
                  const SizedBox(width: DrinSpace.s2),
                  IconButton(
                    tooltip: tr('Chiudi'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: DrinSpace.s4),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    if (box.maxWidth < 860) {
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildBasicCard(c, outcomeLabel, outcomeColor),
                            const SizedBox(height: DrinSpace.s3),
                            SizedBox(
                              height: 420,
                              child: _buildTimelineCard(c),
                            ),
                            const SizedBox(height: DrinSpace.s3),
                            _buildBreakdownCard(c),
                          ],
                        ),
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 272,
                          child: _buildBasicCard(c, outcomeLabel, outcomeColor),
                        ),
                        const SizedBox(width: DrinSpace.s3),
                        Expanded(child: _buildTimelineCard(c)),
                        const SizedBox(width: DrinSpace.s3),
                        SizedBox(
                          width: 296,
                          child: _buildBreakdownCard(c),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill con avatar circolare e nome/numero come nei campi Call From / Call To
/// di Yeastar CDR Details.
class _PartyChip extends StatelessWidget {
  const _PartyChip({
    required this.name,
    required this.number,
    required this.accent,
  });
  final String name;
  final String number;
  final Color accent;

  static String? _initials(String s) {
    final words = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]+')
        .allMatches(s)
        .map((m) => m.group(0)!)
        .toList();
    if (words.isEmpty) return null;
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final hasName = name.isNotEmpty && name != number;
    final label = _CdrDetails._party(name, number);
    final seed = hasName ? name : number;
    final ini = _initials(seed);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DrinSpace.s2,
        vertical: DrinSpace.s1,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(DrinRadius.pill),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.2),
            ),
            alignment: Alignment.center,
            child: ini != null
                ? Text(
                    ini,
                    style: DrinText.detail.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Icon(Icons.person_rounded, size: 13, color: accent),
          ),
          const SizedBox(width: DrinSpace.s2),
          Flexible(
            child: SelectableText(
              label.isEmpty ? '—' : label,
              maxLines: 1,
              style: (hasName ? DrinText.label : DrinText.number).copyWith(
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grafico a ciambella per la ripartizione tempi (Squillo, Conversazione, Attesa).
class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.slices, required this.emptyColor});
  final List<(double, Color)> slices;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 24.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final total = slices.fold<double>(0, (a, b) => a + b.$1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    if (total <= 0) {
      paint.color = emptyColor;
      canvas.drawArc(arcRect, 0, math.pi * 2, false, paint);
      return;
    }

    var start = -math.pi / 2;
    for (final (value, color) in slices) {
      if (value <= 0) continue;
      final sweep = (value / total) * math.pi * 2;
      paint.color = color;
      canvas.drawArc(arcRect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.emptyColor != emptyColor || old.slices != slices;
}
