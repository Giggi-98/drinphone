import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';

// ─── PERCHÉ NON BASTA showDateRangePicker ───
// Il selettore Material su desktop apre una pagina a tutto schermo, in
// inglese (settimana da domenica, "Start Date – End Date") e senza
// scorciatoie: per scegliere "la settimana scorsa" servivano sei clic.
// Qui: dialogo compatto, scorciatoie a sinistra, due mesi da lunedì.

/// Sceglie un intervallo di giorni (estremi inclusi) tra [first] e oggi.
Future<DateTimeRange?> showRangePicker(
  BuildContext context, {
  DateTimeRange? initial,
  DateTime? first,
}) => showDialog<DateTimeRange>(
  context: context,
  builder: (_) =>
      _RangeDialog(initial: initial, first: first ?? DateTime(2015)),
);

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

String _two(int n) => n.toString().padLeft(2, '0');
String _fmt(DateTime t) => '${_two(t.day)}/${_two(t.month)}/${t.year}';

List<String> _months() => [
  tr('Gennaio'),
  tr('Febbraio'),
  tr('Marzo'),
  tr('Aprile'),
  tr('Maggio'),
  tr('Giugno'),
  tr('Luglio'),
  tr('Agosto'),
  tr('Settembre'),
  tr('Ottobre'),
  tr('Novembre'),
  tr('Dicembre'),
];

List<String> _weekdays() => [
  tr('Lun'),
  tr('Mar'),
  tr('Mer'),
  tr('Gio'),
  tr('Ven'),
  tr('Sab'),
  tr('Dom'),
];

class _RangeDialog extends StatefulWidget {
  const _RangeDialog({required this.initial, required this.first});
  final DateTimeRange? initial;
  final DateTime first;

  @override
  State<_RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<_RangeDialog> {
  late final DateTime _today = _d(DateTime.now());
  DateTime? _start, _end, _hover;

  /// Mese mostrato a destra; a sinistra quello prima.
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _start = widget.initial == null ? null : _d(widget.initial!.start);
    _end = widget.initial == null ? null : _d(widget.initial!.end);
    final anchor = _end ?? _today;
    _month = DateTime(anchor.year, anchor.month);
  }

  List<(String, DateTimeRange)> _presets() {
    final t = _today;
    final monday = t.subtract(Duration(days: t.weekday - 1));
    final firstOfMonth = DateTime(t.year, t.month);
    final lastMonthEnd = firstOfMonth.subtract(const Duration(days: 1));
    DateTimeRange r(DateTime a, DateTime b) => DateTimeRange(start: a, end: b);
    return [
      (tr('Oggi'), r(t, t)),
      (
        tr('Ieri'),
        r(
          t.subtract(const Duration(days: 1)),
          t.subtract(const Duration(days: 1)),
        ),
      ),
      (tr('Ultimi 7 giorni'), r(t.subtract(const Duration(days: 6)), t)),
      (tr('Questa settimana'), r(monday, t)),
      (
        tr('Settimana scorsa'),
        r(
          monday.subtract(const Duration(days: 7)),
          monday.subtract(const Duration(days: 1)),
        ),
      ),
      (tr('Ultimi 30 giorni'), r(t.subtract(const Duration(days: 29)), t)),
      (tr('Questo mese'), r(firstOfMonth, t)),
      (
        tr('Mese scorso'),
        r(DateTime(lastMonthEnd.year, lastMonthEnd.month), lastMonthEnd),
      ),
      (tr('Ultimi 90 giorni'), r(t.subtract(const Duration(days: 89)), t)),
    ];
  }

  void _tap(DateTime day) => setState(() {
    if (_start == null || _end != null) {
      _start = day;
      _end = null;
    } else if (day.isBefore(_start!)) {
      _end = _start;
      _start = day;
    } else {
      _end = day;
    }
  });

  void _preset(DateTimeRange r) => setState(() {
    _start = r.start;
    _end = r.end;
    _month = DateTime(r.end.year, r.end.month);
  });

  /// Non oltre il mese corrente (niente chiamate future).
  bool get _canNext => !DateTime(_month.year, _month.month + 1).isAfter(_today);

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final prev = DateTime(_month.year, _month.month - 1);
    final s = _start, e = _end;
    final summary = s == null
        ? tr('Scegli il primo giorno')
        : e == null
        ? '${_fmt(s)} – …'
        : '${_fmt(s)} – ${_fmt(e)}';
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(DrinSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Intervallo di date'),
                style: DrinText.title.copyWith(color: c.ink),
              ),
              const SizedBox(height: DrinSpace.s4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Scorciatoie: un clic per i periodi più usati.
                  SizedBox(
                    width: 168,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (label, r) in _presets())
                          _PresetTile(
                            label: label,
                            selected:
                                s != null &&
                                e != null &&
                                s == r.start &&
                                e == r.end,
                            onTap: () => _preset(r),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 300,
                    margin: const EdgeInsets.symmetric(
                      horizontal: DrinSpace.s4,
                    ),
                    color: c.line,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: tr('Mese precedente'),
                              onPressed: () => setState(
                                () => _month = DateTime(
                                  _month.year,
                                  _month.month - 1,
                                ),
                              ),
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: tr('Mese successivo'),
                              onPressed: _canNext
                                  ? () => setState(
                                      () => _month = DateTime(
                                        _month.year,
                                        _month.month + 1,
                                      ),
                                    )
                                  : null,
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _month0(prev)),
                            const SizedBox(width: DrinSpace.s5),
                            Expanded(child: _month0(_month)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DrinSpace.s4),
              Row(
                children: [
                  Icon(Icons.date_range_rounded, size: 18, color: c.muted),
                  const SizedBox(width: DrinSpace.s2),
                  Text(summary, style: DrinText.number.copyWith(color: c.ink)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Annulla')),
                  ),
                  const SizedBox(width: DrinSpace.s2),
                  FilledButton(
                    onPressed: s == null
                        ? null
                        : () => Navigator.pop(
                            context,
                            DateTimeRange(start: s, end: e ?? s),
                          ),
                    child: Text(tr('Applica')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Un mese: titolo, giorni della settimana da lunedì, griglia dei giorni.
  Widget _month0(DateTime month) {
    final c = context.drin;
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final s = _start;
    final e = _end ?? (s != null && _hover != null ? _hover : null);
    final (lo, hi) = s == null || e == null
        ? (s, s)
        : (e.isBefore(s) ? (e, s) : (s, e));
    return Column(
      children: [
        Text(
          '${_months()[month.month - 1]} ${month.year}',
          style: DrinText.heading.copyWith(color: c.ink),
        ),
        const SizedBox(height: DrinSpace.s2),
        Row(
          children: [
            for (final w in _weekdays())
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: DrinText.label.copyWith(color: c.muted),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: DrinSpace.s1),
        for (var row = 0; row < 6; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: () {
                    final n = row * 7 + col - lead + 1;
                    if (n < 1 || n > days) return const SizedBox(height: 36);
                    final day = DateTime(month.year, month.month, n);
                    final off =
                        day.isAfter(_today) || day.isBefore(_d(widget.first));
                    final inRange =
                        lo != null &&
                        hi != null &&
                        !day.isBefore(lo) &&
                        !day.isAfter(hi);
                    final edge = day == lo || day == hi;
                    return _DayCell(
                      day: n,
                      today: day == _today,
                      disabled: off,
                      inRange: inRange,
                      edge: edge,
                      rangeStart: day == lo && hi != lo,
                      rangeEnd: day == hi && hi != lo,
                      onTap: off ? null : () => _tap(day),
                      onHover: (h) {
                        if (_start != null && _end == null) {
                          setState(() => _hover = h ? day : null);
                        }
                      },
                    );
                  }(),
                ),
            ],
          ),
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DrinRadius.control),
        child: AnimatedContainer(
          duration: DrinMotion.of(context, DrinMotion.fast),
          padding: const EdgeInsets.symmetric(
            horizontal: DrinSpace.s3,
            vertical: DrinSpace.s2,
          ),
          decoration: BoxDecoration(
            color: selected ? c.primary.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(DrinRadius.control),
          ),
          child: Text(
            label,
            style: DrinText.body.copyWith(
              color: selected ? c.primary : c.ink,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Giorno: fascia `primary` al 14% dentro l'intervallo, estremi pieni
/// `primary`, oggi con anello.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.disabled,
    required this.inRange,
    required this.edge,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onTap,
    required this.onHover,
  });
  final int day;
  final bool today, disabled, inRange, edge, rangeStart, rangeEnd;
  final VoidCallback? onTap;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final band = c.primary.withValues(alpha: 0.14);
    return SizedBox(
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Fascia continua tra i giorni dell'intervallo.
          if (inRange)
            Positioned.fill(
              top: 4,
              bottom: 4,
              left: rangeStart ? 18 : 0,
              right: rangeEnd ? 18 : 0,
              child: ColoredBox(color: band),
            ),
          MouseRegion(
            onEnter: (_) => onHover(true),
            onExit: (_) => onHover(false),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: edge ? c.primary : null,
                  border: today && !edge ? Border.all(color: c.primary) : null,
                ),
                child: Text(
                  '$day',
                  style: DrinText.number.copyWith(
                    color: edge
                        ? c.onPrimary
                        : disabled
                        ? c.muted.withValues(alpha: 0.5)
                        : c.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
