import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/call_history.dart';
import '../../core/pbx/pbx_cdr.dart';
import '../../core/pbx/pbx_connection.dart';
import '../../core/sip/sip_engine.dart';
import '../shell/widgets.dart';
import 'call_table.dart';

enum _Kind { all, incoming, missed, outgoing }

enum _Period { today, week, month, all }

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
  /// Filtri come in Linkus: tipo, periodo, nome/numero.
  _Kind _kind = _Kind.all;
  CdrKind _cdrKind = CdrKind.all;
  _Period _period = _Period.week;
  _Source _source = _Source.local;
  final _filter = TextEditingController();

  DateTime? get _from {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.today => today,
      _Period.week => today.subtract(const Duration(days: 6)),
      _Period.month => today.subtract(const Duration(days: 29)),
      _Period.all => null,
    };
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _matches(CallRecord r) {
    final kindOk = switch (_kind) {
      _Kind.all => true,
      _Kind.incoming => r.direction == CallDirection.incoming && !r.missed,
      _Kind.missed => r.missed,
      _Kind.outgoing => r.direction == CallDirection.outgoing,
    };
    final from = _from;
    final q = _filter.text.trim().toLowerCase();
    return kindOk &&
        (from == null || !r.start.isBefore(from)) &&
        (q.isEmpty || r.number.contains(q) || r.name.toLowerCase().contains(q));
  }

  int _page = 0;
  static const pageSize = 50;

  Widget _menu<T>(T value, Map<T, String> items, ValueChanged<T> onPick) =>
      DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(DrinRadius.control),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) onPick(v);
        },
      );

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
                    _kind,
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
                else
                  _menu(_cdrKind, {
                    CdrKind.all: tr('Tutte'),
                    CdrKind.inbound: tr('In arrivo'),
                    CdrKind.outbound: tr('In uscita'),
                    CdrKind.internal: tr('Interne'),
                    CdrKind.unanswered: tr('Non risposte'),
                  }, (v) => setState(() => _cdrKind = v)),
                const SizedBox(width: DrinSpace.s3),
                _menu(
                  _period,
                  {
                    _Period.today: tr('Oggi'),
                    _Period.week: tr('Ultimi 7 giorni'),
                    _Period.month: tr('Ultimi 30 giorni'),
                    _Period.all: tr('Tutto'),
                  },
                  (v) => setState(() {
                    _period = v;
                    _page = 0;
                  }),
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
                    ...filters,
                    const Spacer(),
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
                  ? _CdrList(
                      key: ValueKey(
                        '$_source|$_period|$_cdrKind|${_filter.text.trim()}',
                      ),
                      conn: conn!,
                      wholePbx: _source == _Source.wholePbx,
                      search: _filter.text.trim(),
                      from: _from,
                      kind: _cdrKind,
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

/// Chiamate dal CDR del PBX (Database Grant), a pagine da [PbxCdr.pageSize].
class _CdrList extends StatefulWidget {
  const _CdrList({
    super.key,
    required this.conn,
    required this.wholePbx,
    required this.search,
    required this.from,
    required this.kind,
    required this.canDial,
    required this.onCall,
  });
  final PbxConnection conn;
  final bool wholePbx;
  final String search;
  final DateTime? from;
  final CdrKind kind;
  final bool canDial;
  final ValueChanged<String> onCall;

  @override
  State<_CdrList> createState() => _CdrListState();
}

class _CdrListState extends State<_CdrList> {
  final _rows = <CdrRecord>[];
  bool _loading = true;
  bool _more = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Ogni filtro nuovo crea una lista nuova: digitando si interroga il
    // database una volta sola, quando ci si ferma.
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.conn.readCdr(
        wholePbx: widget.wholePbx,
        search: widget.search,
        from: widget.from,
        kind: widget.kind,
        offset: _rows.length,
      );
      if (!mounted) return;
      _rows.addAll(page);
      _more = page.length == PbxCdr.pageSize;
    } catch (e) {
      // Solo il tipo d'errore: niente host o credenziali.
      _error = '${e.runtimeType}';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Esito come lo scrive il PBX, a parole e col suo colore.
  static (String, Color) _outcome(String d, DrinColors c) =>
      switch (d.toUpperCase()) {
        'ANSWERED' => (tr('Risposta'), c.freeText),
        'NO ANSWER' => (tr('Non risposta'), c.busyText),
        'ABANDONED' => (tr('Abbandonata'), c.busyText),
        'BUSY' => (tr('Occupato'), c.away),
        'FAILED' => (tr('Non riuscita'), c.busyText),
        'VOICEMAIL' => (tr('Casella vocale'), c.primary),
        _ => (d, c.away),
      };

  static List<CallColumn> get _columns => [
    CallColumn(tr('Ora'), width: 112),
    CallColumn(tr('Tipo'), width: 116, hideBelow: 900),
    CallColumn(tr('Da'), flex: 1),
    CallColumn(tr('A'), flex: 1),
    CallColumn(tr('Esito'), width: 132),
    CallColumn(tr('Durata'), width: 80, end: true, hideBelow: 1000),
    CallColumn(tr('Conversazione'), width: 112, end: true, hideBelow: 680),
  ];

  CallRow _row(CdrRecord r, DrinColors c, String? own) {
    final (icon, kind) = switch (r.callType) {
      'Inbound' => (Icons.call_received_rounded, tr('In arrivo')),
      'Outbound' => (Icons.call_made_rounded, tr('In uscita')),
      'Internal' => (Icons.swap_horiz_rounded, tr('Interna')),
      final t => (Icons.call_rounded, t),
    };
    final (outcome, outcomeColor) = _outcome(r.disposition, c);
    // Chi richiamare: l'altro capo rispetto al proprio interno; nel CDR di
    // tutto il PBX chi ha chiamato.
    final other = own != null && r.src == own ? r.dst : r.src;
    final missedByMe = !r.answered && own != null && r.src != own;
    // Gruppo di squillo, coda, IVR: chi ha risposto (o l'ultimo squillo).
    final via = r.lastDst.isNotEmpty && r.lastDst != r.dst;
    final last = r.lastDstName.isNotEmpty
        ? '${r.lastDstName} · ${r.lastDst}'
        : r.lastDst;
    return CallRow(
      cells: [
        WhenCell(r.time),
        KindCell(icon, kind),
        party(r.srcName, r.src, color: missedByMe ? c.busyText : null),
        party(
          r.dstName,
          r.dst,
          extra: via
              ? SubLine(
                  Icons.subdirectory_arrow_right_rounded,
                  r.answered
                      ? tr('Risposto da {n}', {'n': last})
                      : tr('Ultimo squillo: {n}', {'n': last}),
                )
              : null,
        ),
        OutcomePill(outcome, outcomeColor),
        DurationCell(r.duration),
        DurationCell(r.talk, strong: true),
      ],
      callTooltip: tr('Richiama {n}', {'n': other}),
      call: widget.canDial && other.isNotEmpty
          ? () => widget.onCall(other)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final own = widget.conn.voicemailOf;
    if (_rows.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          _error != null
              ? tr('CDR non leggibile: {e}', {'e': _error!})
              : own == null && !widget.wholePbx
              ? tr('Nessun proprio interno per questo PBX.')
              : tr('Nessuna chiamata.'),
          style: DrinText.body.copyWith(
            color: _error != null ? c.busyText : c.muted,
          ),
        ),
      );
    }
    return CallTable(
      columns: _columns,
      rows: [for (final r in _rows) _row(r, c, own)],
      footer: _more || _error != null
          ? Padding(
              padding: const EdgeInsets.all(DrinSpace.s3),
              child: Center(
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : OutlinedButton(
                        onPressed: _load,
                        child: Text(
                          _error != null ? tr('Riprova') : tr('Carica altre'),
                        ),
                      ),
              ),
            )
          : null,
    );
  }
}
