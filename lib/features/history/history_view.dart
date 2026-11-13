import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/call_history.dart';
import '../../core/contacts/personal_contacts.dart';
import '../../core/pbx/pbx_cdr.dart';
import '../../core/pbx/pbx_connection.dart';
import '../../core/sip/sip_engine.dart';
import '../shell/widgets.dart';
import 'range_picker.dart';
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
      width: 148,
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
    final r = await showRangePicker(context, initial: _range);
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
    CallColumn(tr('Tipo'), width: 56, hideBelow: 640),
    CallColumn(tr('Contatto'), flex: 1),
    CallColumn(tr('Esito'), width: 124),
    CallColumn(tr('Conversazione'), width: 112, end: true, hideBelow: 480),
  ];

  /// Gruppi aperti (chiamate ripetute), per inizio della prima chiamata.
  final _open = <DateTime>{};

  // Preferenze di vista salvate, ognuna per conto suo (scelte dall'utente).
  bool get _byDay => widget.phone.viewFlag('hist.byDay');
  bool get _repeat => widget.phone.viewFlag('hist.repeat');
  bool get _summary => widget.phone.viewPref('hist.summary', '1') == '1';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Chiamate consecutive dallo/allo stesso numero, stesso tipo ed esito,
  /// nello stesso giorno: un gruppo (la prima è la più recente).
  List<List<CallRecord>> _groups(List<CallRecord> list) {
    final out = <List<CallRecord>>[];
    for (final r in list) {
      final g = out.isEmpty ? null : out.last;
      final h = g?.first;
      if (_repeat &&
          h != null &&
          h.number == r.number &&
          h.number.isNotEmpty &&
          h.direction == r.direction &&
          h.missed == r.missed &&
          _sameDay(h.start, r.start)) {
        g!.add(r);
      } else {
        out.add([r]);
      }
    }
    return out;
  }

  /// Menu "Vista del registro": scelte salvate, ognuna per conto suo.
  Widget _viewMenu(DrinColors c, bool local) {
    final p = widget.phone;
    PopupMenuItem<String> item(
      String key,
      IconData icon,
      String label,
      bool on,
    ) => PopupMenuItem(
      value: key,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.muted),
          const SizedBox(width: DrinSpace.s3),
          Expanded(child: Text(label)),
          if (on) Icon(Icons.check_rounded, size: 18, color: c.primary),
        ],
      ),
    );
    return PopupMenuButton<String>(
      tooltip: tr('Vista del registro'),
      icon: Icon(Icons.tune_rounded, color: c.muted),
      position: PopupMenuPosition.under,
      onSelected: (k) => k == 'hist.summary'
          ? p.setViewPref(k, _summary ? '0' : '1')
          : p.setViewFlag(k, !p.viewFlag(k)),
      itemBuilder: (_) => [
        item(
          'hist.summary',
          Icons.insights_rounded,
          tr('Riepilogo del giorno'),
          _summary,
        ),
        const PopupMenuDivider(),
        item(
          'hist.byDay',
          Icons.calendar_view_day_rounded,
          tr('Raggruppa per giorno'),
          _byDay,
        ),
        if (local)
          item(
            'hist.repeat',
            Icons.layers_outlined,
            tr('Raggruppa chiamate ripetute'),
            _repeat,
          ),
      ],
    );
  }

  /// Oggi su questo PC: chiamate, perse, secondi al telefono.
  static (int, int, int) _todayLocal(List<CallRecord> all) {
    final now = DateTime.now();
    final today = [
      for (final r in all)
        if (_sameDay(r.start, now)) r,
    ];
    return (
      today.length,
      today.where((r) => r.missed).length,
      today.fold(0, (t, r) => t + r.seconds),
    );
  }

  Future<(int, int, int)>? _pbxFuture;
  String _pbxKey = '';

  /// Oggi dal CDR del PBX (proprio interno o tutto il PBX, come la fonte).
  Widget _pbxSummary(DrinColors c, PbxConnection conn) {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final whole = _source == _Source.wholePbx;
    final key = '${conn.id}|$whole|$from';
    if (key != _pbxKey || _pbxFuture == null) {
      _pbxKey = key;
      _pbxFuture = conn
          .readCdr(
            CdrQuery(
              wholePbx: whole,
              from: from,
              to: from.add(const Duration(days: 1)),
              limit: 1000,
            ),
          )
          .then(
            (page) => (
              page.total,
              page.rows
                  .where((r) => !r.answered && r.callType == 'Inbound')
                  .length,
              page.rows.fold(0, (t, r) => t + r.talk),
            ),
          );
    }
    return FutureBuilder<(int, int, int)>(
      future: _pbxFuture,
      builder: (_, snap) => snap.hasData
          ? _summaryBar(c, snap.data!)
          : const SizedBox(height: 32),
    );
  }

  /// Tre contatori del giorno: chiamate, perse, tempo al telefono.
  Widget _summaryBar(DrinColors c, (int, int, int) d) {
    final (calls, missed, secs) = d;
    String two(int n) => n.toString().padLeft(2, '0');
    final time = secs >= 3600
        ? '${secs ~/ 3600}:${two(secs % 3600 ~/ 60)}:${two(secs % 60)}'
        : '${secs ~/ 60}:${two(secs % 60)}';
    Widget stat(IconData icon, Color color, String value, String label) =>
        Container(
          margin: const EdgeInsets.only(right: DrinSpace.s3),
          padding: const EdgeInsets.symmetric(
            horizontal: DrinSpace.s3,
            vertical: DrinSpace.s1,
          ),
          decoration: BoxDecoration(
            color: c.raised,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(DrinRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: DrinSpace.s2),
              Text(value, style: DrinText.number.copyWith(color: c.ink)),
              const SizedBox(width: DrinSpace.s1),
              Text(label, style: DrinText.detail.copyWith(color: c.muted)),
            ],
          ),
        );
    // Wrap: a finestra stretta i contatori vanno a capo invece di uscire.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: DrinSpace.s2,
      children: [
        Text(tr('Oggi'), style: DrinText.label.copyWith(color: c.muted)),
        const SizedBox(width: DrinSpace.s3),
        stat(Icons.call_rounded, c.primary, '$calls', tr('chiamate')),
        stat(
          Icons.call_missed_rounded,
          missed > 0 ? c.busyText : c.muted,
          '$missed',
          tr('perse'),
        ),
        stat(Icons.timer_outlined, c.freeText, time, tr('al telefono')),
      ],
    );
  }

  /// Righe della pagina: intestazioni per giorno (se scelto), gruppi chiusi
  /// con "×n" o aperti con le singole chiamate.
  List<CallRow> _localRows(
    List<List<CallRecord>> page,
    List<List<CallRecord>> all,
    DrinColors c,
    bool canDial,
  ) {
    final rows = <CallRow>[];
    DateTime? day;
    for (final g in page) {
      final first = g.first;
      if (_byDay && (day == null || !_sameDay(day, first.start))) {
        day = first.start;
        final n = all
            .where((x) => _sameDay(x.first.start, first.start))
            .fold(0, (t, x) => t + x.length);
        rows.add(
          CallRow.section(dayTitle(first.start), sectionDetail: callsCount(n)),
        );
      }
      final open = _open.contains(first.start);
      rows.add(
        _localRow(
          first,
          c,
          canDial,
          count: g.length,
          open: open,
          onToggle: g.length < 2
              ? null
              : () => setState(
                  () =>
                      open ? _open.remove(first.start) : _open.add(first.start),
                ),
        ),
      );
      if (open) {
        for (final r in g.skip(1)) {
          rows.add(_localRow(r, c, canDial));
        }
      }
    }
    return rows;
  }

  CallRow _localRow(
    CallRecord r,
    DrinColors c,
    bool canDial, {
    int count = 1,
    bool open = false,
    VoidCallback? onToggle,
  }) {
    final (icon, color, kind) = r.missed
        ? (Icons.call_missed_rounded, c.busyText, tr('In arrivo, persa'))
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
        KindCell(icon, kind, color: color, iconOnly: true),
        party(
          r.name,
          r.number,
          // L'esito "Persa" lo dice già la pillola: il nome resta neutro.
          // Gruppo di chiamate ripetute: "×n" con freccia; nota scritta
          // durante la chiamata.
          extra: count > 1
              ? SubLine(
                  open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  open
                      ? tr('{n} chiamate · chiudi', {'n': count})
                      : tr('×{n} · mostra tutte', {'n': count}),
                )
              : r.note.isEmpty
              ? null
              : SubLine(Icons.sticky_note_2_outlined, r.note),
        ),
        OutcomePill(outcome, outcomeColor),
        DurationCell(r.seconds, strong: true),
      ],
      callTooltip: tr('Richiama {n}', {'n': r.number}),
      number: r.number,
      onTap: onToggle,
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
    // Le pagine contano i gruppi (una riga "×3" vale una riga).
    final groups = _groups(list);
    final pages = (groups.length + pageSize - 1) ~/ pageSize;
    if (_page >= pages && pages > 0) _page = pages - 1;
    final slice = Pager.slice(groups, _page, pageSize);
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
          // Titolo, fonte e ricerca sopra; filtri sotto (a capo solo se
          // la finestra è stretta).
          LayoutBuilder(
            builder: (context, box) {
              final title = Text(
                tr('Registro chiamate'),
                style: DrinText.title.copyWith(color: c.ink),
              );
              final source = <Widget>[
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
                ],
              ];
              final filters = <Widget>[
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
                _viewMenu(c, local),
                const SizedBox(width: DrinSpace.s2),
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
                    onPressed: () async {
                      if (await confirmDanger(
                        context,
                        title: tr('Svuotare il registro?'),
                        body: tr(
                          'Si cancellano le chiamate registrate su questo PC. '
                          'Il CDR del PBX non cambia.',
                        ),
                        action: tr('Svuota'),
                      )) {
                        await p.clearHistory();
                      }
                    },
                    icon: Icon(Icons.delete_sweep_outlined, color: c.muted),
                  ),
              ];
              // Riga 1: titolo, fonte (se c'è spazio) e ricerca; riga 2: i
              // filtri tutti insieme (prima "Periodo" restava solo a capo).
              final wide = box.maxWidth >= 1000;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      title,
                      if (wide && source.isNotEmpty) ...[
                        const SizedBox(width: DrinSpace.s4),
                        ...source,
                      ],
                      const Spacer(),
                      ...search,
                    ],
                  ),
                  const SizedBox(height: DrinSpace.s3),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: DrinSpace.s2,
                    children: [
                      if (!wide && source.isNotEmpty) ...[
                        ...source,
                        const SizedBox(width: DrinSpace.s3),
                      ],
                      ...filters,
                    ],
                  ),
                ],
              );
            },
          ),
          if (_summary) ...[
            const SizedBox(height: DrinSpace.s3),
            local
                ? _summaryBar(c, _todayLocal(p.history))
                : _pbxSummary(c, conn!),
          ],
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
                      byDay: _byDay,
                      player: p.mediaPlayer,
                      audioCacheDir: Directory(
                        '${p.engineDataDir}${Platform.pathSeparator}audio_cache',
                      ),
                      onSaveContact: (name, number) =>
                          _savePartyAsContact(context, p, name, number),
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
                      rows: _localRows(slice, groups, c, p.canDial),
                    ),
            ),
          ),
          if (local) ...[
            const SizedBox(height: DrinSpace.s2),
            Pager(
              total: groups.length,
              page: _page,
              pageSize: pageSize,
              onPage: (i) => setState(() => _page = i),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _savePartyAsContact(
    BuildContext context,
    PhoneController p,
    String initialName,
    String number,
  ) async {
    final nameCtrl = TextEditingController(
      text: initialName.trim().isNotEmpty ? initialName.trim() : number,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Salva in rubrica')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Nome')),
              onSubmitted: (_) => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: DrinSpace.s2),
            Text(
              '${tr('Numero')}: $number',
              style: DrinText.number.copyWith(color: context.drin.muted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Annulla')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Salva')),
          ),
        ],
      ),
    );
    final finalName = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (saved != true || finalName.isEmpty) return;
    final contact = PersonalContact(
      id: PersonalContact.newId(),
      name: finalName,
      numbers: [('Ufficio', number)],
    );
    if (p.isPersonalDuplicate(contact)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Contatto già presente in rubrica'))),
        );
      }
      return;
    }
    await p.savePersonal(contact);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Salvato in rubrica: {n}', {'n': finalName}))),
      );
    }
  }
}
