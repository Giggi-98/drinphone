import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/call_history.dart';
import '../../core/sip/sip_engine.dart';
import '../shell/widgets.dart';

/// Registro chiamate locale (CallHistoryStore), a pagine.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key, required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  bool _onlyMissed = false;
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

  Widget _chip(DrinColors c, String label, bool on, VoidCallback onTap) =>
      Material(
        color: on ? c.keyBtn : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: on ? c.accent : c.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: on ? c.accent : c.text),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final p = widget.phone;
    final list = [
      for (final r in p.history)
        if (!_onlyMissed || r.missed) r,
    ];
    final pages = (list.length + pageSize - 1) ~/ pageSize;
    if (_page >= pages && pages > 0) _page = pages - 1;
    final slice = Pager.slice(list, _page, pageSize);
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
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: c.text,
                ),
              ),
              const SizedBox(width: 16),
              _chip(c, tr('Tutte'), !_onlyMissed, () {
                setState(() {
                  _onlyMissed = false;
                  _page = 0;
                });
              }),
              const SizedBox(width: 6),
              _chip(c, tr('Perse'), _onlyMissed, () {
                setState(() {
                  _onlyMissed = true;
                  _page = 0;
                });
              }),
              const Spacer(),
              if (p.history.isNotEmpty)
                IconButton(
                  tooltip: tr('Svuota registro'),
                  onPressed: p.clearHistory,
                  icon: Icon(Icons.delete_sweep_outlined, color: c.muted),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      _onlyMissed
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
                        height: 56,
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
          const SizedBox(height: 8),
          Pager(
            total: list.length,
            page: _page,
            pageSize: pageSize,
            onPage: (i) => setState(() => _page = i),
          ),
        ],
      ),
    );
  }
}
