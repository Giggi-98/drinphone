import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/pbx/pbx_connection.dart';
import '../../core/security/settings_store.dart';
import '../../core/sip/sip_engine.dart';
import '../shell/widgets.dart';

/// Live Calls (stile pannello operatore): chi parla con chi, da quanto, chi
/// squilla; colonna BLF a destra. Dati: eventi API 30011 del PBX scelto.
class LiveCallsView extends StatefulWidget {
  const LiveCallsView({
    super.key,
    required this.phone,
    required this.onOpenPreferences,
  });
  final PhoneController phone;

  /// Apre Preferenze > Integrazione PBX (per attivare gli eventi).
  final VoidCallback onOpenPreferences;

  @override
  State<LiveCallsView> createState() => _LiveCallsViewState();
}

class _LiveCallsViewState extends State<LiveCallsView> {
  String? _connId;
  late final Timer _tick;

  PhoneController get p => widget.phone;

  @override
  void initState() {
    super.initState();
    // Durate che scorrono.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  PbxConnection? get _conn =>
      p.connections.where((c) => c.id == _connId).firstOrNull ??
      p.primaryConnection ??
      p.connections.firstOrNull;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final conn = _conn;
    if (conn == null) {
      return Center(
        child: Text(
          tr('Collega un PBX in Preferenze > Integrazione PBX.'),
          style: TextStyle(color: c.muted),
        ),
      );
    }
    final calls = conn.visibleCalls;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(c, conn),
                if (!conn.eventsConnected) _eventsBanner(c, conn),
                const SizedBox(height: 12),
                Expanded(
                  child: _CallsTable(
                    phone: p,
                    title: tr('Entranti e interne'),
                    icon: Icons.call_received_rounded,
                    calls: [
                      for (final x in calls)
                        if (!x.outbound) x,
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _CallsTable(
                    phone: p,
                    title: tr('Uscenti'),
                    icon: Icons.call_made_rounded,
                    calls: [
                      for (final x in calls)
                        if (x.outbound) x,
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 320,
            child: _BlfColumn(phone: p, conn: conn),
          ),
        ],
      ),
    );
  }

  Widget _header(DrinColors c, PbxConnection conn) => Row(
    children: [
      Text(
        tr('Live Calls'),
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: c.text,
        ),
      ),
      const SizedBox(width: 12),
      CountBadge(conn.visibleCalls.length),
      const Spacer(),
      Tooltip(
        message: conn.eventsStatus,
        child: Icon(
          Icons.bolt_rounded,
          color: conn.eventsConnected ? c.ok : c.muted,
        ),
      ),
      const SizedBox(width: 8),
      // Più PBX: si sceglie quale osservare.
      if (p.connections.length > 1)
        DropdownButton<String>(
          value: conn.id,
          underline: const SizedBox.shrink(),
          items: [
            for (final x in p.connections)
              DropdownMenuItem(value: x.id, child: Text(x.label)),
          ],
          onChanged: (v) => setState(() => _connId = v),
        )
      else
        Text(conn.label, style: TextStyle(color: c.muted)),
    ],
  );

  Widget _eventsBanner(DrinColors c, PbxConnection conn) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      border: Border.all(color: c.ringing),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: c.ringing),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            conn.realtime
                ? conn.eventsStatus
                : tr(
                    'Le chiamate in corso arrivano dagli eventi in tempo reale '
                    'del PBX: attivali per questa connessione.',
                  ),
            style: TextStyle(color: c.text),
          ),
        ),
        if (!conn.realtime)
          TextButton(
            onPressed: widget.onOpenPreferences,
            child: Text(tr('Integrazione PBX')),
          ),
      ],
    ),
  );
}

class _CallsTable extends StatefulWidget {
  const _CallsTable({
    required this.phone,
    required this.title,
    required this.icon,
    required this.calls,
  });
  final PhoneController phone;
  final String title;
  final IconData icon;
  final List<LiveCall> calls;

  @override
  State<_CallsTable> createState() => _CallsTableState();
}

class _CallsTableState extends State<_CallsTable> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  String _elapsed(LiveCall x) {
    final d = DateTime.now().difference(x.answered ?? x.seen);
    final h = d.inHours;
    final mm = '${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';
    return h > 0 ? '$h:$mm' : mm;
  }

  String _who(String number) {
    final name = widget.phone.nameFor(number);
    return name.isEmpty ? number : '$name ($number)';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final q = _filter.text.trim().toLowerCase();
    final rows = [
      for (final x in widget.calls)
        if (q.isEmpty ||
            '${_who(x.caller)} ${_who(x.callee)}'.toLowerCase().contains(q))
          x,
    ];
    Widget head(String t, int flex) => Expanded(
      flex: flex,
      child: Text(
        t,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c.muted,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
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
              Icon(widget.icon, size: 18, color: c.accent),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
              ),
              const SizedBox(width: 10),
              CountBadge(rows.length),
              const Spacer(),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    hintText: tr('Chiamante o chiamato'),
                    hintStyle: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                head(tr('Chiamante'), 3),
                head(tr('Chiamato'), 3),
                head(tr('Stato'), 2),
                head(tr('Durata'), 1),
                head(tr('Dettagli'), 2),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.phone_disabled_outlined,
                          size: 32,
                          color: c.border,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr('Nessuna chiamata in corso'),
                          style: TextStyle(color: c.muted),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: c.border, height: 1),
                    itemBuilder: (_, i) {
                      final x = rows[i];
                      final (icon, color, label) = x.ringing
                          ? (
                              Icons.ring_volume_rounded,
                              c.ringing,
                              tr('Squilla'),
                            )
                          : x.onHold
                          ? (
                              Icons.pause_circle_outline,
                              c.muted,
                              tr('In attesa'),
                            )
                          : (Icons.call_rounded, c.ok, tr('In conversazione'));
                      final details = [
                        if (x.trunk.isNotEmpty) x.trunk,
                        if (x.path.isNotEmpty) x.path,
                      ].join(' · ');
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                _who(x.caller),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.text),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                _who(x.callee),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.text),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Tooltip(
                                  message: label,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Icon(icon, size: 16, color: color),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(_elapsed(x), style: mono(c.text)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                details.isEmpty ? '—' : details,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: c.muted),
                              ),
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

/// Colonna BLF generale: Preferiti, poi un gruppo per reparto (attivi/totali).
class _BlfColumn extends StatefulWidget {
  const _BlfColumn({required this.phone, required this.conn});
  final PhoneController phone;
  final PbxConnection conn;

  @override
  State<_BlfColumn> createState() => _BlfColumnState();
}

class _BlfColumnState extends State<_BlfColumn> {
  final _filter = TextEditingController();
  final _closed = <String>{};

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final p = widget.phone;
    final conn = widget.conn;
    final q = _filter.text.trim().toLowerCase();
    final exts = {
      for (final x in conn.directory)
        x.id: Extension(
          x.name.isEmpty ? x.number : x.name,
          x.number,
          source: conn.id,
        ),
    };
    bool shown(Extension e) =>
        q.isEmpty || e.number.contains(q) || e.name.toLowerCase().contains(q);
    final groups = <(String, List<Extension>, bool)>[
      (
        tr('Preferiti'),
        [
          for (final e in exts.values)
            if (p.isFavorite(e) && shown(e)) e,
        ],
        true,
      ),
      for (final o in conn.orgs)
        (
          o.name,
          [
            for (final id in o.extIds)
              if (exts[id] != null && shown(exts[id]!)) exts[id]!,
          ],
          false,
        ),
      if (conn.orgs.isEmpty)
        (tr('Tutti gli interni'), exts.values.where(shown).toList(), false),
    ];
    bool active(Extension e) {
      final s = p.blfOf(e);
      return s != null && s != BlfStatus.offline && s != BlfStatus.unknown;
    }

    return Container(
      padding: const EdgeInsets.all(12),
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
              Icon(Icons.people_alt_outlined, size: 18, color: c.accent),
              const SizedBox(width: 8),
              Text(
                tr('Interni'),
                style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: tr('Cerca interno'),
              hintStyle: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (final (name, list, fav) in groups)
                  if (list.isNotEmpty || (fav && q.isEmpty)) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(
                        () => _closed.contains(name)
                            ? _closed.remove(name)
                            : _closed.add(name),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            if (fav)
                              Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: c.ringing,
                              ),
                            if (fav) const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$name (${list.where(active).length}/${list.length})',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: c.text,
                                ),
                              ),
                            ),
                            AnimatedRotation(
                              turns: _closed.contains(name) ? -0.25 : 0,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              child: Icon(
                                Icons.expand_more_rounded,
                                size: 18,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _closed.contains(name)
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final e in list)
                                  _BlfRow(phone: p, ext: e),
                              ],
                            ),
                    ),
                    Divider(color: c.border, height: 8),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlfRow extends StatelessWidget {
  const _BlfRow({required this.phone, required this.ext});
  final PhoneController phone;
  final Extension ext;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final s = phone.blfOf(ext);
    final stale = phone.blfStale(ext);
    final dot = switch (s) {
      BlfStatus.idle => c.ok,
      BlfStatus.busy => c.busy,
      BlfStatus.ringing => c.ringing,
      _ => c.border,
    }.withValues(alpha: stale ? 0.35 : 1);
    final pr = presenceOf(c, phone.presenceOf(ext));
    final callable = phone.isCallable(ext) && phone.canDial;
    return Tooltip(
      message: [
        blfLabel(s),
        if (stale) tr('da confermare'),
        if (pr != null) pr.$3,
      ].join(' · '),
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: callable ? () => phone.dial(ext.number, via: ext) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(ext.number, style: mono(c.muted, size: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ext.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.text),
                ),
              ),
              if (pr != null) Icon(pr.$1, size: 14, color: pr.$2),
            ],
          ),
        ),
      ),
    );
  }
}
