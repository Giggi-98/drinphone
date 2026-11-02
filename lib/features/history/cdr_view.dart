// CDR del PBX (Database Grant) come nella pagina CDR del PBX: pagine con il
// totale, ordinamento dalle intestazioni (di default dalla più recente),
// colonne a scelta, dettaglio con le gambe, esportazione CSV.
import 'dart:io';

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
    final own = widget.conn.voicemailOf;
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
        (r) => party(
          r.srcName,
          r.src,
          color: !r.answered && own != null && r.src != own ? c.busyText : null,
        ),
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
            width: 84,
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
            width: 120,
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

/// Dettaglio di una chiamata: tutti i campi del CDR e le gambe.
class _CdrDetails extends StatelessWidget {
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

  static String _dur(int s) => s <= 0 ? '—' : DurationCell.format(s);

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final (outcomeLabel, outcomeColor) = _CdrViewState.outcome(
      r.disposition,
      c,
    );
    final fields = <(String, String)>[
      (tr('Ora'), _when(r.time)),
      (tr('Tipo'), _CdrViewState.kind(r.callType).$2),
      (tr('Da'), _party(r.srcName, r.src)),
      (tr('A'), _party(r.dstName, r.dst)),
      (tr('Secondo partecipante'), _party(r.secondDstName, r.secondDst)),
      (tr('Ultimo partecipante'), _party(r.lastDstName, r.lastDst)),
      (tr('IVR'), r.ivrs.map(_pretty).join(', ')),
      (tr('Call flow'), r.callFlows.map(_pretty).join(', ')),
      (tr('Coda'), r.queues.map(_pretty).join(', ')),
      (tr('Gruppo di squillo'), r.ringGroups.map(_pretty).join(', ')),
      (tr('Durata'), _dur(r.duration)),
      (tr('Squillo'), _dur(r.ring)),
      (tr('Conversazione'), _dur(r.talk)),
      (tr('In attesa'), _dur(r.hold)),
      (tr('Chiuso da'), r.disconnectBy),
      (tr('Trunk in ingresso'), r.srcTrunk),
      (tr('Trunk in uscita'), r.dstTrunk),
      (tr('DID'), r.did),
      (tr('DOD'), r.dod),
      (tr('Registrazione'), r.hasRecording ? tr('Sì') : ''),
    ];
    Widget field(String label, String value) => SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: DrinText.label.copyWith(color: c.muted)),
          const SizedBox(height: 2),
          SelectableText(
            value.isEmpty ? '—' : value,
            style: DrinText.body.copyWith(
              color: value.isEmpty ? c.muted : c.ink,
            ),
          ),
        ],
      ),
    );
    Widget head(String s, {bool end = false}) => Text(
      s,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: DrinText.label.copyWith(color: c.muted),
    );
    Widget cell(String s, {bool end = false, bool number = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: DrinSpace.s2),
      child: Text(
        s.isEmpty ? '—' : s,
        textAlign: end ? TextAlign.end : TextAlign.start,
        style: (number ? DrinText.number : DrinText.body).copyWith(
          color: c.ink,
        ),
      ),
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(DrinSpace.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Dettagli chiamata'),
                      style: DrinText.title.copyWith(color: c.ink),
                    ),
                  ),
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
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: DrinSpace.s5,
                        runSpacing: DrinSpace.s4,
                        children: [for (final f in fields) field(f.$1, f.$2)],
                      ),
                      if (r.legs.isNotEmpty) ...[
                        const SizedBox(height: DrinSpace.s5),
                        Text(
                          tr('Gambe della chiamata'),
                          style: DrinText.heading.copyWith(color: c.ink),
                        ),
                        const SizedBox(height: DrinSpace.s2),
                        Table(
                          columnWidths: const {
                            0: FixedColumnWidth(84),
                            1: FlexColumnWidth(2),
                            2: FlexColumnWidth(2),
                            3: FixedColumnWidth(132),
                            4: FixedColumnWidth(72),
                            5: FixedColumnWidth(96),
                            6: FlexColumnWidth(2),
                          },
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          border: TableBorder(
                            horizontalInside: BorderSide(color: c.line),
                          ),
                          children: [
                            TableRow(
                              children: [
                                head(tr('Ora')),
                                head(tr('Da')),
                                head(tr('A')),
                                head(tr('Esito')),
                                head(tr('Squillo'), end: true),
                                head(tr('Conversazione'), end: true),
                                head(tr('Trunk')),
                              ],
                            ),
                            for (final l in r.legs)
                              TableRow(
                                children: [
                                  cell(
                                    l.time == null
                                        ? ''
                                        : _when(l.time).split(' ').last,
                                    number: true,
                                  ),
                                  cell(_party(l.srcName, l.src)),
                                  cell(_party(l.dstName, l.dst)),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Builder(
                                      builder: (context) {
                                        final (t, col) = _CdrViewState.outcome(
                                          l.disposition,
                                          c,
                                        );
                                        return OutcomePill(t, col);
                                      },
                                    ),
                                  ),
                                  cell(_dur(l.ring), end: true, number: true),
                                  cell(_dur(l.talk), end: true, number: true),
                                  cell(
                                    [
                                      l.srcTrunk,
                                      l.dstTrunk,
                                    ].where((s) => s.isNotEmpty).join(' → '),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
