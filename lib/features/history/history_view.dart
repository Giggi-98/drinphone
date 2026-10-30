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

enum _Kind { all, incoming, missed, outgoing }

enum _Period { today, week, month, all }

/// Da dove vengono le chiamate: questo PC, il CDR del PBX per il proprio
/// interno, il CDR di tutto il PBX (se l'amministratore lo concede).
enum _Source { local, pbx, wholePbx }

/// Registro chiamate locale (CallHistoryStore), a pagine.
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (_period) {
      _Period.today => today,
      _Period.week => today.subtract(const Duration(days: 6)),
      _Period.month => today.subtract(const Duration(days: 29)),
      _Period.all => DateTime(2000),
    };
    final q = _filter.text.trim().toLowerCase();
    return kindOk &&
        !r.start.isBefore(from) &&
        (q.isEmpty || r.number.contains(q) || r.name.toLowerCase().contains(q));
  }

  int _page = 0;
  static const pageSize = 50;

  static String _two(int n) => n.toString().padLeft(2, '0');

  String _when(DateTime t) {
    final now = DateTime.now();
    final time = '${_two(t.hour)}:${_two(t.minute)}';
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return tr('Oggi {t}', {'t': time});
    if (diff == 1) return tr('Ieri {t}', {'t': time});
    return '${_two(t.day)}/${_two(t.month)}/${t.year} $time';
  }

  String _duration(CallRecord r) {
    if (!r.answered) return r.missed ? tr('Persa') : tr('Non risposta');
    final m = r.seconds ~/ 60;
    return m > 0
        ? tr('{m} min {s} s', {'m': m, 's': _two(r.seconds % 60)})
        : tr('{s} s', {'s': r.seconds});
  }

  Widget _menu<T>(T value, Map<T, String> items, ValueChanged<T> onPick) =>
      DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) onPick(v);
        },
      );

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
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                tr('Registro chiamate'),
                style: DrinText.title.copyWith(color: c.ink),
              ),
              const SizedBox(width: DrinSpace.s4),
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
                ),
              const SizedBox(width: 12),
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
              const Spacer(),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() => _page = 0),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    hintText: tr('Nome o numero'),
                    hintStyle: TextStyle(fontSize: 13, color: c.muted),
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
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: !local
                ? _CdrList(
                    key: ValueKey('$_source|$_period|${_filter.text.trim()}'),
                    conn: conn!,
                    wholePbx: _source == _Source.wholePbx,
                    search: _filter.text.trim(),
                    from: _from,
                    canDial: p.canDial,
                    onCall: widget.onCall,
                    when: _when,
                  )
                : list.isEmpty
                ? Center(
                    child: Text(
                      _kind == _Kind.missed
                          ? tr('Nessuna chiamata persa.')
                          : tr('Nessuna chiamata.'),
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: slice.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: c.border, height: 1),
                    itemBuilder: (_, i) {
                      final r = slice[i];
                      final (icon, color, kind) = r.missed
                          ? (Icons.call_missed_rounded, c.busyText, tr('Persa'))
                          : r.direction == CallDirection.incoming
                          ? (
                              Icons.call_received_rounded,
                              c.okText,
                              tr('In arrivo'),
                            )
                          : (
                              Icons.call_made_rounded,
                              c.accent,
                              tr('In uscita'),
                            );
                      return SizedBox(
                        // Una riga in più se c'è la nota.
                        height: r.note.isEmpty ? 56 : 72,
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            Tooltip(
                              message: kind,
                              child: Icon(icon, size: 20, color: color),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.name.isNotEmpty ? r.name : r.number,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: r.missed ? c.busyText : c.text,
                                    ),
                                  ),
                                  if (r.name.isNotEmpty)
                                    Text(
                                      r.number,
                                      style: mono(c.muted, size: 12),
                                    ),
                                  // Nota scritta durante la chiamata.
                                  if (r.note.isNotEmpty)
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.sticky_note_2_outlined,
                                          size: 13,
                                          color: c.accent,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            r.note,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: c.muted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: Text(
                                _when(r.start),
                                style: TextStyle(fontSize: 13, color: c.muted),
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: Text(
                                _duration(r),
                                style: TextStyle(fontSize: 13, color: c.muted),
                              ),
                            ),
                            CallIconButton(
                              tooltip: tr('Richiama {n}', {'n': r.number}),
                              onPressed: p.canDial && r.number.isNotEmpty
                                  ? () => widget.onCall(r.number)
                                  : null,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (local) ...[
            const SizedBox(height: 8),
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
    required this.canDial,
    required this.onCall,
    required this.when,
  });
  final PbxConnection conn;
  final bool wholePbx;
  final String search;
  final DateTime? from;
  final bool canDial;
  final ValueChanged<String> onCall;
  final String Function(DateTime) when;

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

  String _talk(CdrRecord r) {
    final m = r.talk ~/ 60;
    return m > 0
        ? tr('{m} min {s} s', {
            'm': m,
            's': (r.talk % 60).toString().padLeft(2, '0'),
          })
        : tr('{s} s', {'s': r.talk});
  }

  /// Esito come lo scrive il PBX, a parole.
  static String _disposition(String d) => switch (d.toUpperCase()) {
    'ANSWERED' => tr('Risposta'),
    'NO ANSWER' => tr('Non risposta'),
    'BUSY' => tr('Occupato'),
    'FAILED' => tr('Non riuscita'),
    'VOICEMAIL' => tr('Casella vocale'),
    _ => d,
  };

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
    return ListView.separated(
      itemCount: _rows.length + (_more || _error != null ? 1 : 0),
      separatorBuilder: (_, _) => Divider(color: c.line, height: 1),
      itemBuilder: (_, i) {
        if (i == _rows.length) {
          return Padding(
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
          );
        }
        final r = _rows[i];
        // Dal punto di vista del proprio interno: entrante se chiamato.
        final incoming = own != null ? r.dst == own : r.callType == 'Inbound';
        final missed = !r.answered && incoming;
        final (icon, color) = missed
            ? (Icons.call_missed_rounded, c.busyText)
            : incoming
            ? (Icons.call_received_rounded, c.freeText)
            : (Icons.call_made_rounded, c.primary);
        String who(String name, String number) =>
            name.isNotEmpty && name != number ? '$name ($number)' : number;
        final other = incoming ? r.src : r.dst;
        final title = widget.wholePbx
            ? '${who(r.srcName, r.src)}  →  ${who(r.dstName, r.dst)}'
            : who(incoming ? r.srcName : r.dstName, other);
        return SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: DrinSpace.s1),
              Tooltip(
                message: r.callType,
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: DrinSpace.s3),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: DrinText.heading.copyWith(
                    color: missed ? c.busyText : c.ink,
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                child: Text(
                  r.time == null ? '' : widget.when(r.time!),
                  style: DrinText.detail.copyWith(color: c.muted),
                ),
              ),
              SizedBox(
                width: 130,
                child: Text(
                  r.answered ? _talk(r) : _disposition(r.disposition),
                  style: DrinText.detail.copyWith(color: c.muted),
                ),
              ),
              CallIconButton(
                tooltip: tr('Richiama {n}', {'n': other}),
                onPressed: widget.canDial && other.isNotEmpty
                    ? () => widget.onCall(other)
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
