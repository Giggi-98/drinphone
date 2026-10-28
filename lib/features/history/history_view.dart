import 'package:flutter/material.dart';

import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/call_history.dart';
import '../../core/sip/sip_engine.dart';

/// Cronologia chiamate locale (CallHistoryStore).
class HistoryView extends StatefulWidget {
  const HistoryView({super.key, required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  bool _onlyMissed = false;

  static String _two(int n) => n.toString().padLeft(2, '0');

  String _when(DateTime t) {
    final now = DateTime.now();
    final time = '${_two(t.hour)}:${_two(t.minute)}';
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Oggi $time';
    if (diff == 1) return 'Ieri $time';
    return '${_two(t.day)}/${_two(t.month)}/${t.year} $time';
  }

  String _duration(CallRecord r) {
    if (!r.answered) return r.missed ? 'Persa' : 'Non risposta';
    final m = r.seconds ~/ 60;
    return m > 0 ? '$m min ${_two(r.seconds % 60)} s' : '${r.seconds} s';
  }

  Widget _chip(DrinColors c, String label, bool on, VoidCallback onTap) =>
      Material(
        color: on ? c.keyBtn : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: on ? c.accent : c.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: on ? c.accent : c.text),
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
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Cronologia',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
              const SizedBox(width: 16),
              _chip(
                c,
                'Tutte',
                !_onlyMissed,
                () => setState(() => _onlyMissed = false),
              ),
              const SizedBox(width: 6),
              _chip(
                c,
                'Perse',
                _onlyMissed,
                () => setState(() => _onlyMissed = true),
              ),
              const Spacer(),
              if (p.history.isNotEmpty)
                TextButton.icon(
                  onPressed: p.clearHistory,
                  icon: Icon(
                    Icons.delete_sweep_outlined,
                    size: 18,
                    color: c.muted,
                  ),
                  label: Text('Svuota', style: TextStyle(color: c.muted)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      _onlyMissed
                          ? 'Nessuna chiamata persa.'
                          : 'Nessuna chiamata.',
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: c.border, height: 1),
                    itemBuilder: (_, i) {
                      final r = list[i];
                      final (icon, color, kind) = r.missed
                          ? (Icons.call_missed, c.busyText, 'Persa')
                          : r.direction == CallDirection.incoming
                          ? (Icons.call_received, c.okText, 'In arrivo')
                          : (Icons.call_made, c.accent, 'In uscita');
                      return SizedBox(
                        height: 60,
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
                                      fontWeight: FontWeight.w500,
                                      color: r.missed ? c.busyText : c.text,
                                    ),
                                  ),
                                  if (r.name.isNotEmpty)
                                    Text(
                                      r.number,
                                      style: TextStyle(
                                        fontFamily: monoFont,
                                        fontSize: 12,
                                        color: c.muted,
                                      ),
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
                            IconButton(
                              tooltip: 'Richiama',
                              onPressed: p.canDial && r.number.isNotEmpty
                                  ? () => widget.onCall(r.number)
                                  : null,
                              icon: Icon(Icons.call, size: 18, color: c.accent),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
