import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/call_history.dart';
import '../../core/pbx/pbx_cdr.dart';
import '../../core/sip/sip_engine.dart';
import '../shell/widgets.dart';
import 'call_table.dart';
import 'cdr_view.dart';

enum _Kind { all, incoming, missed, outgoing }

enum _Period { today, week, month, all, custom }

/// Da dove vengono le chiamate: questo PC, il CDR del PBX per il proprio
/// interno, il CDR di tutto il PBX (se l'amministratore lo concede).
enum _Source { local, pbx, wholePbx }

/// Registro chiamate: locale (CallHistoryStore, a pagine) o CDR del PBX.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key, required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  /// Filtri: tipo, esito (CDR), periodo o intervallo di date, nome/numero.
  _Kind _kind = _Kind.all;
  CdrKind _cdrKind = CdrKind.all;
  CdrOutcome _cdrOutcome = CdrOutcome.all;
  _Period _period = _Period.week;
  DateTimeRange? _range;
  _Source _source = _Source.local;
  final _filter = TextEditingController();

  /// Solo CDR: chi chiama e chi è chiamato, separati.
  final _callFrom = TextEditingController();
  final _callTo = TextEditingController();

  DateTime? get _from {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.today => today,
      _Period.week => today.subtract(const Duration(days: 6)),
      _Period.month => today.subtract(const Duration(days: 29)),
      _Period.all => null,
      _Period.custom => _range?.start,
    };
  }

  /// Fine esclusa: il giorno dopo l'ultimo dell'intervallo.
  DateTime? get _to {
    final end = _period == _Period.custom ? _range?.end : null;
    return end == null ? null : DateTime(end.year, end.month, end.day + 1);
  }

  bool get _filtered =>
      _kind != _Kind.all ||
      _cdrKind != CdrKind.all ||
      _cdrOutcome != CdrOutcome.all ||
      _period != _Period.week ||
      _filter.text.isNotEmpty ||
      _callFrom.text.isNotEmpty ||
      _callTo.text.isNotEmpty;

  void _reset() => setState(() {
    _kind = _Kind.all;
    _cdrKind = CdrKind.all;
    _cdrOutcome = CdrOutcome.all;
    _period = _Period.week;
    _range = null;
    _filter.clear();
    _callFrom.clear();
    _callTo.clear();
    _page = 0;
  });

  /// Campo Da / A del CDR, stretto, dentro la riga dei filtri.
  Widget _partyField(TextEditingController ctl, String label) => Padding(
    padding: const EdgeInsets.only(right: DrinSpace.s2),
    child: SizedBox(
      width: 180,
      height: 36,
      child: TextField(
        controller: ctl,
        onChanged: (_) => setState(() {}),
        style: DrinText.body.copyWith(color: context.drin.ink),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.person_search_outlined, size: 16),
          hintText: label,
          hintStyle: DrinText.body.copyWith(color: context.drin.muted),
        ),
      ),
    ),
  );

  static String _day(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickPeriod(_Period v) async {
    if (v != _Period.custom) {
      setState(() {
        _period = v;
        _page = 0;
      });
      return;
    }
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: now,
      initialDateRange: _range,
      helpText: tr('Intervallo di date'),
    );
    if (r == null || !mounted) return;
    setState(() {
      _range = r;
      _period = _Period.custom;
      _page = 0;
    });
  }

  @override
  void dispose() {
    _filter.dispose();
    _callFrom.dispose();
    _callTo.dispose();
    super.dispose();
  }

  bool _matches(CallRecord r) {
    final kindOk = switch (_kind) {
      _Kind.all => true,
      _Kind.incoming => r.direction == CallDirection.incoming && !r.missed,
      _Kind.missed => r.missed,
      _Kind.outgoing => r.direction == CallDirection.outgoing,
    };
    final from = _from, to = _to;
    final q = _filter.text.trim().toLowerCase();
    return kindOk &&
        (from == null || !r.start.isBefore(from)) &&
        (to == null || r.start.isBefore(to)) &&
        (q.isEmpty || r.number.contains(q) || r.name.toLowerCase().contains(q));
  }

  int _page = 0;
  static const pageSize = 50;

  /// Filtro a pillola "Etichetta: valore ▾"; evidenziato se non è quello
  /// predefinito ([initial]).
  Widget _menu<T>(
    String label,
    T value,
    T initial,
    Map<T, String> items,
    ValueChanged<T> onPick, {
    String? shown,
  }) {
    final c = context.drin;
    final on = value != initial;
    return Padding(
      padding: const EdgeInsets.only(right: DrinSpace.s2),
      child: PopupMenuButton<T>(
        tooltip: label,
        initialValue: value,
        onSelected: onPick,
        itemBuilder: (_) => [
          for (final e in items.entries)
            PopupMenuItem(value: e.key, child: Text(e.value)),
        ],
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: DrinSpace.s3),
          decoration: BoxDecoration(
            color: on ? c.primary.withValues(alpha: 0.14) : c.raised,
            border: Border.all(color: on ? c.primary : c.line),
            borderRadius: BorderRadius.circular(DrinRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$label: ', style: DrinText.label.copyWith(color: c.muted)),
              Text(
                shown ?? items[value]!,
                style: DrinText.label.copyWith(color: on ? c.primary : c.ink),
              ),
              const SizedBox(width: DrinSpace.s1),
              Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: on ? c.primary : c.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Colonne del registro di questo PC.
  static List<CallColumn> get _localColumns => [
    CallColumn(tr('Ora'), width: 112),
    CallColumn(tr('Tipo'), width: 116, hideBelow: 640),
    CallColumn(tr('Contatto'), flex: 1),
    CallColumn(tr('Esito'), width: 124),
    CallColumn(tr('Conversazione'), width: 112, end: true, hideBelow: 480),
  ];

  CallRow _localRow(CallRecord r, DrinColors c, bool canDial) {
    final (icon, color, kind) = r.missed
        ? (Icons.call_missed_rounded, c.busyText, tr('In arrivo'))
        : r.direction == CallDirection.incoming
        ? (Icons.call_received_rounded, c.freeText, tr('In arrivo'))
        : (Icons.call_made_rounded, c.primary, tr('In uscita'));
    final (outcome, outcomeColor) = r.answered
        ? (tr('Risposta'), c.freeText)
        : r.missed
        ? (tr('Persa'), c.busyText)
        : (tr('Non risposta'), c.away);
    return CallRow(
      cells: [
        WhenCell(r.start),
        KindCell(icon, kind, color: color),
        party(
          r.name,
          r.number,
          color: r.missed ? c.busyText : null,
          // Nota scritta durante la chiamata.
          extra: r.note.isEmpty
              ? null
              : SubLine(Icons.sticky_note_2_outlined, r.note),
        ),
        OutcomePill(outcome, outcomeColor),
        DurationCell(r.seconds, strong: true),
      ],
      callTooltip: tr('Richiama {n}', {'n': r.number}),
      call: canDial && r.number.isNotEmpty
          ? () => widget.onCall(r.number)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final p = widget.phone;
    final list = [
      for (final r in p.history)
        if (_matches(r)) r,
    ];
    final pages = (list.length + pageSize - 1) ~/ pageSize;
    if (_page >= pages && pages > 0) _page = pages - 1;
    final slice = Pager.slice(list, _page, pageSize);
    final conn = p.primaryConnection;
    final cdr = conn != null && conn.cdrConfigured;
    if (!cdr) _source = _Source.local;
    final local = _source == _Source.local;
    return Container(
      margin: const EdgeInsets.all(DrinSpace.s4),
      padding: const EdgeInsets.all(DrinSpace.s4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(DrinRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Una riga sola se c'è spazio; altrimenti titolo e ricerca sopra,
          // fonte e filtri sotto (vanno a capo se non entrano).
          LayoutBuilder(
            builder: (context, box) {
              final title = Text(
                tr('Registro chiamate'),
                style: DrinText.title.copyWith(color: c.ink),
              );
              final filters = <Widget>[
                if (cdr) ...[
                  SegmentedButton<_Source>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: _Source.local,
                        icon: const Icon(Icons.computer_rounded, size: 16),
                        label: Text(tr('Questo PC')),
                      ),
                      ButtonSegment(
                        value: _Source.pbx,
                        icon: const Icon(Icons.dns_outlined, size: 16),
                        label: Text(tr('PBX')),
                      ),
                      if (conn.cdrWholePbx)
                        ButtonSegment(
                          value: _Source.wholePbx,
                          icon: const Icon(Icons.hub_outlined, size: 16),
                          label: Text(tr('Tutto il PBX')),
                        ),
                    ],
                    selected: {_source},
                    onSelectionChanged: (s) => setState(() {
                      _source = s.first;
                      _page = 0;
                    }),
                  ),
                  const SizedBox(width: DrinSpace.s3),
                ],
                if (local)
                  _menu(
                    tr('Tipo'),
                    _kind,
                    _Kind.all,
                    {
                      _Kind.all: tr('Tutte'),
                      _Kind.incoming: tr('In arrivo'),
                      _Kind.missed: tr('Perse'),
                      _Kind.outgoing: tr('In uscita'),
                    },
                    (v) => setState(() {
                      _kind = v;
                      _page = 0;
                    }),
                  )
                else ...[
                  _menu(tr('Tipo'), _cdrKind, CdrKind.all, {
                    CdrKind.all: tr('Tutte'),
                    CdrKind.inbound: tr('In arrivo'),
                    CdrKind.outbound: tr('In uscita'),
                    CdrKind.internal: tr('Interne'),
                  }, (v) => setState(() => _cdrKind = v)),
                  _menu(tr('Esito'), _cdrOutcome, CdrOutcome.all, {
                    CdrOutcome.all: tr('Tutti'),
                    CdrOutcome.answered: tr('Risposta'),
                    CdrOutcome.unanswered: tr('Non risposte (tutte)'),
                    CdrOutcome.noAnswer: tr('Non risposta'),
                    CdrOutcome.abandoned: tr('Abbandonata'),
                    CdrOutcome.busy: tr('Occupato'),
                    CdrOutcome.failed: tr('Non riuscita'),
                    CdrOutcome.voicemail: tr('Casella vocale'),
                  }, (v) => setState(() => _cdrOutcome = v)),
                  _partyField(_callFrom, tr('Da')),
                  Padding(
                    padding: const EdgeInsets.only(right: DrinSpace.s2),
                    child: IconButton(
                      tooltip: tr('Scambia Da e A'),
                      onPressed: () => setState(() {
                        final t = _callFrom.text;
                        _callFrom.text = _callTo.text;
                        _callTo.text = t;
                      }),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    ),
                  ),
                  _partyField(_callTo, tr('A')),
                ],
                _menu(
                  tr('Periodo'),
                  _period,
                  _Period.week,
                  {
                    _Period.today: tr('Oggi'),
                    _Period.week: tr('Ultimi 7 giorni'),
                    _Period.month: tr('Ultimi 30 giorni'),
                    _Period.all: tr('Tutto'),
                    _Period.custom: tr('Intervallo di date…'),
                  },
                  _pickPeriod,
                  shown: _period == _Period.custom && _range != null
                      ? '${_day(_range!.start)} – ${_day(_range!.end)}'
                      : null,
                ),
                if (_filtered)
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                    label: Text(tr('Azzera filtri')),
                  ),
              ];
              final search = <Widget>[
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _filter,
                    onChanged: (_) => setState(() => _page = 0),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText: tr('Nome o numero'),
                      hintStyle: DrinText.body.copyWith(color: c.muted),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (local && p.history.isNotEmpty)
                  IconButton(
                    tooltip: tr('Svuota registro'),
                    onPressed: p.clearHistory,
                    icon: Icon(Icons.delete_sweep_outlined, color: c.muted),
                  ),
              ];
              if (box.maxWidth >= 1120) {
                return Row(
                  children: [
                    title,
                    const SizedBox(width: DrinSpace.s4),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: DrinSpace.s2,
                        children: filters,
                      ),
                    ),
                    ...search,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [title, const Spacer(), ...search]),
                  const SizedBox(height: DrinSpace.s3),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: DrinSpace.s2,
                    children: filters,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: DrinSpace.s3),
          Expanded(
            child: AnimatedSwitcher(
              duration: DrinMotion.of(context, DrinMotion.base),
              child: !local
                  ? CdrView(
                      key: ValueKey(
                        '$_source|$_period|$_range|$_cdrKind|$_cdrOutcome|'
                        '${_filter.text.trim()}|${_callFrom.text.trim()}|'
                        '${_callTo.text.trim()}',
                      ),
                      conn: conn!,
                      filters: CdrQuery(
                        wholePbx: _source == _Source.wholePbx,
                        search: _filter.text.trim(),
                        callFrom: _callFrom.text.trim(),
                        callTo: _callTo.text.trim(),
                        from: _from,
                        to: _to,
                        kind: _cdrKind,
                        outcome: _cdrOutcome,
                      ),
                      canDial: p.canDial,
                      onCall: widget.onCall,
                    )
                  : list.isEmpty
                  ? Center(
                      key: const ValueKey('empty'),
                      child: Text(
                        _kind == _Kind.missed
                            ? tr('Nessuna chiamata persa.')
                            : tr('Nessuna chiamata.'),
                        style: DrinText.body.copyWith(color: c.muted),
                      ),
                    )
                  : CallTable(
                      key: const ValueKey('local'),
                      columns: _localColumns,
                      rows: [for (final r in slice) _localRow(r, c, p.canDial)],
                    ),
            ),
          ),
          if (local) ...[
            const SizedBox(height: DrinSpace.s2),
            Pager(
              total: list.length,
              page: _page,
              pageSize: pageSize,
              onPage: (i) => setState(() => _page = i),
            ),
          ],
        ],
      ),
    );
  }
}
