import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/pbx/pbx_connection.dart';
import '../../core/pbx/yeastar_api.dart';
import '../../core/security/settings_store.dart';
import '../../core/sip/sip_engine.dart';
import '../shell/widgets.dart';

/// Sezione Live (pannello operatore): chiamate entranti/interne e uscenti con
/// trascinamento (trasferimento cieco), menu contestuale tasto destro
/// (trasferisci, riaggancia, registra, parcheggia e — solo se il proprio
/// interno ha il monitoraggio attivo — intromettiti, ascolta, suggerisci),
/// riquadri destinazioni in basso (gruppi di squillo, code, parcheggio,
/// casella vocale di gruppo) e colonna Interni BLF a destra.
class LiveCallsView extends StatefulWidget {
  const LiveCallsView({
    super.key,
    required this.phone,
    required this.onOpenPreferences,
    this.focus,
  });
  final PhoneController phone;

  /// Interno la cui chiamata va evidenziata (arrivando dal suo segnalino).
  final String? focus;

  /// Apre Preferenze > Integrazione PBX (per attivare gli eventi).
  final VoidCallback onOpenPreferences;

  @override
  State<LiveCallsView> createState() => _LiveCallsViewState();
}

class _LiveCallsViewState extends State<LiveCallsView> {
  String? _connId;
  late final Timer _tick;
  String? _attendedChannel;
  String? _attendedTargetLabel;

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

  bool _hasOperatorTargets(PbxConnection conn) =>
      conn.ringGroups.isNotEmpty ||
      conn.queues.isNotEmpty ||
      conn.parkingSlots.isNotEmpty ||
      conn.vmGroups.isNotEmpty;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _doBlindTransfer(
    PbxConnection conn,
    LiveCall call,
    String destination, {
    String? label,
  }) async {
    final target = destination.trim();
    if (target.isEmpty) return;
    try {
      await conn.blindTransferCall(call, target);
      _snack(tr('Chiamata trasferita a {n}', {'n': label ?? target}));
    } catch (e) {
      _snack(e is YeastarApiException ? '$e' : tr('Operazione non riuscita'));
    }
  }

  Future<void> _doHangup(PbxConnection conn, LiveCall call) async {
    try {
      await conn.hangupLiveCall(call);
      _snack(tr('Chiamata terminata'));
    } catch (e) {
      _snack(e is YeastarApiException ? '$e' : tr('Operazione non riuscita'));
    }
  }

  Future<void> _doRecord(PbxConnection conn, LiveCall call) async {
    try {
      await conn.recordLiveCall(call);
      _snack(tr('Registrazione avviata'));
    } catch (e) {
      _snack(e is YeastarApiException ? '$e' : tr('Operazione non riuscita'));
    }
  }

  Future<void> _doMonitor(
    PbxConnection conn,
    LiveCall call,
    String mode, {
    String? targetChannelId,
  }) async {
    if (!conn.canMonitor || !conn.allowedMonitorModes.contains(mode)) return;
    var ch = targetChannelId;
    if (ch == null) {
      final exts = conn.monitorableExtensionsOf(call);
      if (exts.isEmpty) return;
      if (exts.length == 1) {
        ch = exts.first.channel;
      } else {
        if (!mounted) return;
        ch = await _pickMonitorTarget(exts);
        if (ch == null) return;
      }
    }
    try {
      await conn.monitorLiveCall(call, mode, targetChannelId: ch);
      _snack(tr('Monitoraggio avviato sul tuo interno'));
    } catch (e) {
      _snack(e is YeastarApiException ? '$e' : tr('Operazione non riuscita'));
    }
  }

  Future<String?> _pickMonitorTarget(List<LiveMember> exts) =>
      showDialog<String>(
        context: context,
        builder: (ctx) {
          final c = ctx.drin;
          return AlertDialog(
            title: Text(
              tr('Scegli interno da monitorare'),
              style: DrinText.title.copyWith(color: c.ink),
            ),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in exts)
                    ListTile(
                      leading: Icon(
                        Icons.person_outline_rounded,
                        color: c.primary,
                      ),
                      title: Text(
                        p.nameFor(m.number).isEmpty
                            ? m.number
                            : '${p.nameFor(m.number)} (${m.number})',
                        style: DrinText.body.copyWith(color: c.ink),
                      ),
                      onTap: () => Navigator.pop(ctx, m.channel),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Annulla')),
              ),
            ],
          );
        },
      );

  Future<void> _openTransferPicker(
    PbxConnection conn,
    LiveCall call, {
    bool attended = false,
  }) async {
    final dest = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => _TransferPickerDialog(
        phone: p,
        conn: conn,
        attended: attended,
      ),
    );
    if (dest == null) return;
    if (!attended) {
      await _doBlindTransfer(conn, call, dest.$1, label: dest.$2);
      return;
    }
    try {
      final ch = await conn.attendedTransferCall(call, dest.$1);
      if (mounted) {
        setState(() {
          _attendedChannel = ch;
          _attendedTargetLabel = dest.$2;
        });
      }
      _snack(tr('Consultazione avviata verso {n}', {'n': dest.$2}));
    } catch (e) {
      _snack(e is YeastarApiException ? '$e' : tr('Operazione non riuscita'));
    }
  }

  Future<void> _operateAttended(PbxConnection conn, String op) async {
    final ch = _attendedChannel;
    if (ch == null || ch.isEmpty) return;
    try {
      await conn.operateAttendedTransfer(channelId: ch, operate: op);
      if (!mounted) return;
      if (op == 'complete' || op == 'abort' || op == 'threeway') {
        setState(() {
          _attendedChannel = null;
          _attendedTargetLabel = null;
        });
      }
      _snack(switch (op) {
        'complete' => tr('Trasferimento completato'),
        'abort' => tr('Trasferimento annullato'),
        'swap' => tr('Chiamate scambiate'),
        'threeway' => tr('Conferenza a 3 avviata'),
        _ => tr('Operazione completata'),
      });
    } catch (e) {
      _snack(e is YeastarApiException ? '$e' : tr('Operazione non riuscita'));
    }
  }

  Future<void> _toggleQueuePause(
    PbxConnection conn, {
    required bool pause,
    PbxQueue? queue,
  }) async {
    try {
      await conn.setOwnQueuePause(pause: pause, queue: queue);
      if (mounted) setState(() {});
      _snack(
        pause
            ? (queue == null
                  ? tr('In pausa su tutte le code')
                  : tr('In pausa su {q}', {'q': queue.name}))
            : (queue == null
                  ? tr('Attivo su tutte le code')
                  : tr('Attivo su {q}', {'q': queue.name})),
      );
    } catch (e) {
      _snack(e is YeastarApiException ? '$e' : tr('Operazione non riuscita'));
    }
  }

  void _pickupExtension(PbxConnection conn, String extNumber) {
    final code = conn.extPickupCode;
    if (code == null || code.isEmpty || !p.canDial || extNumber.isEmpty) return;
    p.dial('$code$extNumber');
  }

  Future<void> _openParkPicker(PbxConnection conn, LiveCall call) async {
    final busySlots = {for (final x in conn.parkedCalls) x.slot};
    final freeSlots = [
      for (final s in conn.parkingSlots)
        if (!busySlots.contains(s)) s,
    ];
    if (freeSlots.isEmpty && (conn.parkCode ?? '').isNotEmpty) {
      await _doBlindTransfer(conn, call, conn.parkCode!);
      return;
    }
    if (freeSlots.length == 1) {
      await _doBlindTransfer(conn, call, freeSlots.single);
      return;
    }
    if (!mounted || freeSlots.isEmpty) return;
    final slot = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.drin;
        return AlertDialog(
          title: Text(
            tr('Parcheggia'),
            style: DrinText.title.copyWith(color: c.ink),
          ),
          content: SizedBox(
            width: 320,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in freeSlots)
                  ListTile(
                    leading: Icon(Icons.local_parking_rounded, color: c.ok),
                    title: Text(
                      '$s · ${tr('Libero')}',
                      style: DrinText.body.copyWith(color: c.ink),
                    ),
                    onTap: () => Navigator.pop(ctx, s),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Annulla')),
            ),
          ],
        );
      },
    );
    if (slot != null) await _doBlindTransfer(conn, call, slot);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final c = context.drin;
    final conn = _conn;
    if (conn == null) {
      return Center(
        child: Text(
          tr('Collega un PBX in Preferenze > Integrazione PBX.'),
          style: DrinText.body.copyWith(color: c.muted),
        ),
      );
    }
    final calls = conn.visibleCalls;
    final hasTargets = _hasOperatorTargets(conn);
    return Padding(
      padding: const EdgeInsets.all(DrinSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(c, conn),
                if (!conn.eventsConnected) _eventsBanner(c, conn),
                if (_attendedChannel != null) _attendedBanner(c, conn),
                const SizedBox(height: DrinSpace.s3),
                if (calls.isEmpty && !hasTargets)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.phone_disabled_rounded,
                            size: 40,
                            color: c.muted,
                          ),
                          const SizedBox(height: DrinSpace.s3),
                          Text(
                            tr('Nessuna chiamata in corso'),
                            style: DrinText.title.copyWith(color: c.ink),
                          ),
                          const SizedBox(height: DrinSpace.s1),
                          Text(
                            tr(
                              'Le chiamate del PBX compaiono qui appena '
                              'iniziano, divise tra entranti e uscenti.',
                            ),
                            style: DrinText.detail.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Expanded(
                    child: _CallsTable(
                      phone: p,
                      conn: conn,
                      focus: widget.focus,
                      deptOf: p.viewFlag('live.byDept') && conn.orgs.isNotEmpty
                          ? conn.deptOfCall
                          : null,
                      title: tr('Entranti e interne'),
                      icon: Icons.call_received_rounded,
                      calls: [
                        for (final x in calls)
                          if (!x.outbound) x,
                      ],
                      onTransfer: (call) => _openTransferPicker(conn, call),
                      onAttendedTransfer: (call) =>
                          _openTransferPicker(conn, call, attended: true),
                      onPickup: (ext) => _pickupExtension(conn, ext),
                      onHangup: (call) => _doHangup(conn, call),
                      onRecord: (call) => _doRecord(conn, call),
                      onPark: (call) => _openParkPicker(conn, call),
                      onMonitor: (call, mode) => _doMonitor(conn, call, mode),
                    ),
                  ),
                  const SizedBox(height: DrinSpace.s3),
                  Expanded(
                    child: _CallsTable(
                      phone: p,
                      conn: conn,
                      focus: widget.focus,
                      deptOf: p.viewFlag('live.byDept') && conn.orgs.isNotEmpty
                          ? conn.deptOfCall
                          : null,
                      title: tr('Uscenti'),
                      icon: Icons.call_made_rounded,
                      calls: [
                        for (final x in calls)
                          if (x.outbound) x,
                      ],
                      onTransfer: (call) => _openTransferPicker(conn, call),
                      onAttendedTransfer: (call) =>
                          _openTransferPicker(conn, call, attended: true),
                      onPickup: (ext) => _pickupExtension(conn, ext),
                      onHangup: (call) => _doHangup(conn, call),
                      onRecord: (call) => _doRecord(conn, call),
                      onPark: (call) => _openParkPicker(conn, call),
                      onMonitor: (call, mode) => _doMonitor(conn, call, mode),
                    ),
                  ),
                ],
                if (hasTargets) ...[
                  const SizedBox(height: DrinSpace.s3),
                  SizedBox(
                    height: 184,
                    child: _OperatorTargetsRow(
                      phone: p,
                      conn: conn,
                      onBlindTransfer: (call, dest, {label}) =>
                          _doBlindTransfer(conn, call, dest, label: label),
                      onParkCall: (call) => _openParkPicker(conn, call),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DrinSpace.s4),
          SizedBox(
            width: 320,
            child: _BlfColumn(
              phone: p,
              conn: conn,
              onBlindTransfer: (call, dest, {label}) =>
                  _doBlindTransfer(conn, call, dest, label: label),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(DrinColors c, PbxConnection conn) {
    final agentQueues = conn.ownAgentQueues;
    final pausedAny = conn.pausedQueueIds.isNotEmpty;
    return Row(
      children: [
        Text(
          tr('Live'),
          style: DrinText.title.copyWith(color: c.ink),
        ),
        const SizedBox(width: DrinSpace.s3),
        CountBadge(conn.visibleCalls.length),
        const Spacer(),
        if (agentQueues.isNotEmpty) ...[
          PopupMenuButton<String>(
            tooltip: pausedAny
                ? tr('Agente coda in pausa')
                : tr('Stato agente nelle code'),
            onSelected: (v) {
              if (v == 'pause_all') {
                _toggleQueuePause(conn, pause: true);
              } else if (v == 'unpause_all') {
                _toggleQueuePause(conn, pause: false);
              } else if (v.startsWith('q:')) {
                final qid = int.tryParse(v.substring(2));
                final q = agentQueues.where((x) => x.id == qid).firstOrNull;
                if (q != null) {
                  _toggleQueuePause(
                    conn,
                    pause: !conn.pausedQueueIds.contains(q.id),
                    queue: q,
                  );
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: pausedAny ? 'unpause_all' : 'pause_all',
                child: Row(
                  children: [
                    Icon(
                      pausedAny
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 17,
                      color: pausedAny ? c.ok : c.squilloLine,
                    ),
                    const SizedBox(width: DrinSpace.s2),
                    Expanded(
                      child: Text(
                        pausedAny
                            ? tr('Riprendi tutte le code')
                            : tr('Pausa su tutte le code'),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 8),
              for (final q in agentQueues)
                () {
                  final paused = conn.pausedQueueIds.contains(q.id);
                  return PopupMenuItem(
                    value: 'q:${q.id}',
                    child: Row(
                      children: [
                        Icon(
                          paused
                              ? Icons.pause_circle_filled_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 16,
                          color: paused ? c.squilloLine : c.ok,
                        ),
                        const SizedBox(width: DrinSpace.s2),
                        Expanded(
                          child: Text('${q.number} ${q.name}'),
                        ),
                      ],
                    ),
                  );
                }(),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DrinSpace.s3,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: (pausedAny ? c.squillo : c.ok).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(DrinRadius.pill),
                border: Border.all(
                  color: (pausedAny ? c.squilloLine : c.ok).withValues(
                    alpha: 0.45,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pausedAny
                        ? Icons.pause_circle_rounded
                        : Icons.support_agent_rounded,
                    size: 15,
                    color: pausedAny ? c.squilloLine : c.okText,
                  ),
                  const SizedBox(width: DrinSpace.s1),
                  Text(
                    pausedAny ? tr('In pausa coda') : tr('Code attive'),
                    style: DrinText.label.copyWith(
                      color: pausedAny ? c.squilloLine : c.okText,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 16,
                    color: pausedAny ? c.squilloLine : c.okText,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: DrinSpace.s2),
        ],
        if (conn.orgs.isNotEmpty)
          IconButton(
            tooltip: p.viewFlag('live.byDept')
                ? tr('Tutte insieme')
                : tr('Raggruppa per reparto'),
            isSelected: p.viewFlag('live.byDept'),
            onPressed: () =>
                p.setViewFlag('live.byDept', !p.viewFlag('live.byDept')),
            icon: Icon(Icons.groups_outlined, color: c.muted),
            selectedIcon: Icon(Icons.groups_rounded, color: c.primary),
          ),
        Tooltip(
          message: conn.eventsStatus,
          child: Icon(
            Icons.bolt_rounded,
            color: conn.eventsConnected ? c.ok : c.muted,
          ),
        ),
        const SizedBox(width: DrinSpace.s2),
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
          Text(conn.label, style: DrinText.detail.copyWith(color: c.muted)),
      ],
    );
  }

  Widget _attendedBanner(DrinColors c, PbxConnection conn) => Container(
    margin: const EdgeInsets.only(top: DrinSpace.s3),
    padding: const EdgeInsets.symmetric(
      horizontal: DrinSpace.s4,
      vertical: DrinSpace.s2,
    ),
    decoration: BoxDecoration(
      color: c.primary.withValues(alpha: 0.1),
      border: Border.all(color: c.primary.withValues(alpha: 0.45)),
      borderRadius: BorderRadius.circular(DrinRadius.row),
    ),
    child: Row(
      children: [
        Icon(Icons.phone_forwarded_rounded, size: 18, color: c.primary),
        const SizedBox(width: DrinSpace.s3),
        Expanded(
          child: Text(
            tr('Consultazione verso {n}', {'n': _attendedTargetLabel ?? ''}),
            style: DrinText.heading.copyWith(color: c.ink),
          ),
        ),
        TextButton.icon(
          onPressed: () => _operateAttended(conn, 'swap'),
          icon: const Icon(Icons.swap_calls_rounded, size: 16),
          label: Text(tr('Scambia')),
        ),
        const SizedBox(width: DrinSpace.s1),
        TextButton.icon(
          onPressed: () => _operateAttended(conn, 'threeway'),
          icon: const Icon(Icons.group_add_rounded, size: 16),
          label: Text(tr('Conferenza a 3')),
        ),
        const SizedBox(width: DrinSpace.s1),
        FilledButton.icon(
          onPressed: () => _operateAttended(conn, 'complete'),
          icon: const Icon(Icons.check_rounded, size: 16),
          label: Text(tr('Completa')),
        ),
        const SizedBox(width: DrinSpace.s1),
        TextButton(
          onPressed: () => _operateAttended(conn, 'abort'),
          child: Text(tr('Annulla'), style: TextStyle(color: c.busy)),
        ),
      ],
    ),
  );

  Widget _eventsBanner(DrinColors c, PbxConnection conn) => Container(
    margin: const EdgeInsets.only(top: DrinSpace.s3),
    padding: const EdgeInsets.symmetric(
      horizontal: DrinSpace.s4,
      vertical: DrinSpace.s2,
    ),
    decoration: BoxDecoration(
      border: Border.all(color: c.line),
      borderRadius: BorderRadius.circular(DrinRadius.row),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: c.primary),
        const SizedBox(width: DrinSpace.s3),
        Expanded(
          child: Text(
            conn.realtime
                ? conn.eventsStatus
                : tr(
                    'Le chiamate in corso arrivano dagli eventi in tempo reale '
                    'del PBX: attivali per questa connessione.',
                  ),
            style: DrinText.body.copyWith(color: c.ink),
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
    required this.conn,
    required this.title,
    required this.icon,
    required this.calls,
    required this.onTransfer,
    required this.onAttendedTransfer,
    required this.onPickup,
    required this.onHangup,
    required this.onRecord,
    required this.onPark,
    required this.onMonitor,
    this.focus,
    this.deptOf,
  });

  /// Se dato, chiamate divise per reparto con un'intestazione per gruppo.
  final String Function(LiveCall)? deptOf;
  final PhoneController phone;
  final PbxConnection conn;
  final String title;
  final IconData icon;
  final List<LiveCall> calls;
  final ValueChanged<LiveCall> onTransfer;
  final ValueChanged<LiveCall> onAttendedTransfer;
  final ValueChanged<String> onPickup;
  final ValueChanged<LiveCall> onHangup;
  final ValueChanged<LiveCall> onRecord;
  final ValueChanged<LiveCall> onPark;
  final void Function(LiveCall call, String mode) onMonitor;

  /// Interno da evidenziare (le sue chiamate).
  final String? focus;

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

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    LiveCall call,
  ) async {
    final c = context.drin;
    final conn = widget.conn;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final hasPark =
        conn.parkingSlots.isNotEmpty || (conn.parkCode ?? '').isNotEmpty;
    final canMon =
        conn.canMonitor && conn.monitorableExtensionsOf(call).isNotEmpty;
    final modes = conn.allowedMonitorModes;

    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String text, {
      bool trailingArrow = false,
      Color? iconColor,
    }) => PopupMenuItem<String>(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 17, color: iconColor ?? c.primary),
          const SizedBox(width: DrinSpace.s3),
          Expanded(
            child: Text(
              text,
              style: DrinText.body.copyWith(color: c.ink),
            ),
          ),
          if (trailingArrow)
            Icon(Icons.chevron_right_rounded, size: 16, color: c.muted),
        ],
      ),
    );

    final canAttended = conn.attendedTransferChannelOf(call) != null;
    final pickupExt = call.ringing &&
            (conn.extPickupCode ?? '').isNotEmpty &&
            widget.phone.canDial
        ? call.members
              .where((m) => m.kind == 'extension' && m.status == 'RING')
              .firstOrNull
              ?.number
        : null;

    final entries = <PopupMenuEntry<String>>[
      if (pickupExt != null && pickupExt.isNotEmpty)
        item(
          'pickup',
          Icons.phone_in_talk_rounded,
          tr('Rispondi per {n}', {'n': pickupExt}),
          iconColor: c.ok,
        ),
      item(
        'transfer',
        Icons.swap_horiz_rounded,
        tr('Trasferisci'),
        trailingArrow: true,
      ),
      if (canAttended)
        item(
          'transfer_attended',
          Icons.phone_forwarded_rounded,
          tr('Trasferisci con consultazione'),
          trailingArrow: true,
        ),
      item(
        'hangup',
        Icons.call_end_rounded,
        tr('Riaggancia'),
        iconColor: c.busy,
      ),
      item(
        'record',
        Icons.fiber_manual_record_rounded,
        tr('Registra'),
      ),
      if (hasPark)
        item(
          'park',
          Icons.local_parking_rounded,
          tr('Parcheggia'),
          trailingArrow: true,
        ),
      if (canMon) ...[
        const PopupMenuDivider(height: 8),
        if (modes.contains('barge'))
          item(
            'barge',
            Icons.record_voice_over_rounded,
            tr('Intromettiti'),
          ),
        if (modes.contains('listen'))
          item(
            'listen',
            Icons.headset_rounded,
            tr('Ascolta'),
          ),
        if (modes.contains('whisper'))
          item(
            'whisper',
            Icons.hearing_rounded,
            tr('Suggerisci'),
            trailingArrow: conn.monitorableExtensionsOf(call).length > 1,
          ),
      ],
    ];

    final chosen = await showMenu<String>(
      context: context,
      color: c.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DrinRadius.row),
        side: BorderSide(color: c.line),
      ),
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: entries,
    );
    if (!mounted || chosen == null) return;
    switch (chosen) {
      case 'pickup':
        if (pickupExt != null) widget.onPickup(pickupExt);
      case 'transfer':
        widget.onTransfer(call);
      case 'transfer_attended':
        widget.onAttendedTransfer(call);
      case 'hangup':
        widget.onHangup(call);
      case 'record':
        widget.onRecord(call);
      case 'park':
        widget.onPark(call);
      case 'barge' || 'listen' || 'whisper':
        widget.onMonitor(call, chosen);
    }
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
    final deptOf = widget.deptOf;
    final List<Object> items;
    if (deptOf == null) {
      items = rows;
    } else {
      final sorted = [...rows]
        ..sort((a, b) {
          final da = deptOf(a), db = deptOf(b);
          if (da.isEmpty != db.isEmpty) return da.isEmpty ? 1 : -1;
          return da.compareTo(db);
        });
      items = [];
      String? last;
      for (final x in sorted) {
        final d = deptOf(x);
        if (d != last) {
          last = d;
          items.add(d.isEmpty ? tr('Senza reparto') : d);
        }
        items.add(x);
      }
    }
    Widget head(String t, int flex) => Expanded(
      flex: flex,
      child: Text(
        t,
        style: DrinText.label.copyWith(color: c.muted),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(DrinSpace.s3),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(DrinRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 18, color: c.primary),
              const SizedBox(width: DrinSpace.s2),
              Text(
                widget.title,
                style: DrinText.heading.copyWith(color: c.ink),
              ),
              const SizedBox(width: DrinSpace.s2),
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
                    hintStyle: DrinText.detail.copyWith(color: c.muted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DrinSpace.s2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DrinSpace.s3,
              vertical: DrinSpace.s2,
            ),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(DrinRadius.control),
            ),
            child: Row(
              children: [
                head(tr('Chiamante'), 3),
                head(tr('Chiamato'), 3),
                head(tr('Stato'), 2),
                head(tr('Durata'), 1),
                head(tr('Dettagli'), 2),
                const SizedBox(width: 28),
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
                          Icons.inbox_outlined,
                          size: 32,
                          color: c.line,
                        ),
                        const SizedBox(height: DrinSpace.s1),
                        Text(
                          tr('Nessuna chiamata in corso'),
                          style: DrinText.detail.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: c.line, height: 1),
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      if (item is String) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.groups_outlined,
                                size: 16,
                                color: c.primary,
                              ),
                              const SizedBox(width: DrinSpace.s2),
                              Text(
                                item,
                                style: DrinText.heading.copyWith(color: c.ink),
                              ),
                            ],
                          ),
                        );
                      }
                      final x = item as LiveCall;
                      final (icon, color, label) = liveLook(
                        c,
                        x.ringing
                            ? LiveState.ringing
                            : x.onHold
                            ? LiveState.hold
                            : LiveState.talking,
                      );
                      final details = [
                        if (x.trunk.isNotEmpty) x.trunk,
                        if (x.path.isNotEmpty) x.path,
                      ].join(' · ');
                      final hl =
                          widget.focus != null &&
                          x.members.any(
                            (m) =>
                                m.kind == 'extension' &&
                                m.number == widget.focus,
                          );
                      final callerText = _who(x.caller);
                      final calleeText = _who(x.callee);
                      final elapsedText = _elapsed(x);
                      final detailsText = details.isEmpty ? '—' : details;

                      final rowContent = GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapDown: (d) =>
                            _showContextMenu(ctx, d.globalPosition, x),
                        child: Container(
                          decoration: hl
                              ? BoxDecoration(
                                  color: c.primary.withValues(alpha: 0.14),
                                  border: Border(
                                    left: BorderSide(
                                      color: c.primary,
                                      width: 3,
                                    ),
                                  ),
                                )
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: DrinSpace.s3,
                            vertical: DrinSpace.s2,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.drag_indicator_rounded,
                                      size: 15,
                                      color: c.muted,
                                    ),
                                    const SizedBox(width: DrinSpace.s1),
                                    Expanded(
                                      child: Text(
                                        callerText,
                                        overflow: TextOverflow.ellipsis,
                                        style: DrinText.body.copyWith(
                                          color: c.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  calleeText,
                                  overflow: TextOverflow.ellipsis,
                                  style: DrinText.body.copyWith(color: c.ink),
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
                                        horizontal: DrinSpace.s2,
                                        vertical: DrinSpace.s1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(
                                          DrinRadius.pill,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(icon, size: 14, color: color),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              label,
                                              overflow: TextOverflow.ellipsis,
                                              style: DrinText.label.copyWith(
                                                color: c.ink,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  elapsedText,
                                  style: DrinText.number.copyWith(color: c.ink),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  detailsText,
                                  overflow: TextOverflow.ellipsis,
                                  style: DrinText.detail.copyWith(
                                    color: c.muted,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 28,
                                child: Builder(
                                  builder: (btnCtx) => IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 26,
                                      minHeight: 26,
                                    ),
                                    iconSize: 16,
                                    tooltip: tr('Azioni chiamata'),
                                    icon: Icon(
                                      Icons.more_horiz_rounded,
                                      color: c.muted,
                                    ),
                                    onPressed: () {
                                      final box =
                                          btnCtx.findRenderObject()
                                              as RenderBox?;
                                      final pos =
                                          box?.localToGlobal(Offset.zero) ??
                                          Offset.zero;
                                      _showContextMenu(btnCtx, pos, x);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );

                      return FadeIn(
                        key: ValueKey(x.id),
                        child: Draggable<LiveCall>(
                          data: x,
                          dragAnchorStrategy: pointerDragAnchorStrategy,
                          feedback: Material(
                            color: Colors.transparent,
                            child: Container(
                              width: 520,
                              padding: const EdgeInsets.symmetric(
                                horizontal: DrinSpace.s4,
                                vertical: DrinSpace.s2,
                              ),
                              decoration: BoxDecoration(
                                color: c.raised.withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(
                                  DrinRadius.row,
                                ),
                                border: Border.all(
                                  color: c.primary,
                                  width: 1.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x55000000),
                                    blurRadius: 16,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.swap_horiz_rounded,
                                    size: 16,
                                    color: c.primary,
                                  ),
                                  const SizedBox(width: DrinSpace.s2),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      callerText,
                                      overflow: TextOverflow.ellipsis,
                                      style: DrinText.heading.copyWith(
                                        color: c.ink,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      calleeText,
                                      overflow: TextOverflow.ellipsis,
                                      style: DrinText.body.copyWith(
                                        color: c.ink,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: DrinSpace.s2,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(
                                        DrinRadius.pill,
                                      ),
                                    ),
                                    child: Text(
                                      label,
                                      style: DrinText.label.copyWith(
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: DrinSpace.s3),
                                  Text(
                                    elapsedText,
                                    style: DrinText.number.copyWith(
                                      color: c.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.4,
                            child: rowContent,
                          ),
                          child: rowContent,
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

/// Riga inferiore del pannello operatore: Gruppi di squillo, Code, Parcheggio
/// e Casella vocale di gruppo. Ogni elemento accetta il trascinamento di una
/// [LiveCall] per eseguire un trasferimento cieco verso quella destinazione.
class _OperatorTargetsRow extends StatelessWidget {
  const _OperatorTargetsRow({
    required this.phone,
    required this.conn,
    required this.onBlindTransfer,
    required this.onParkCall,
  });

  final PhoneController phone;
  final PbxConnection conn;
  final void Function(LiveCall call, String destination, {String? label})
  onBlindTransfer;
  final ValueChanged<LiveCall> onParkCall;

  int _onlineCount(List<String> members) {
    final byId = {for (final e in conn.directory) '${e.id}': e.number};
    final byNum = {for (final e in conn.directory) e.number};
    final nums = <String>{
      for (final m in members)
        if (byNum.contains(m)) m else ?byId[m],
    };
    var count = 0;
    for (final n in nums) {
      final s = phone.blfOf(Extension(n, n, source: conn.id));
      if (s != null && s != BlfStatus.offline && s != BlfStatus.unknown) {
        count++;
      }
    }
    return count;
  }

  int _totalCount(int memberCount, List<String> members) =>
      memberCount > 0 ? memberCount : members.length;

  @override
  Widget build(BuildContext context) {
    final busyBySlot = {for (final x in conn.parkedCalls) x.slot: x};
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _OperatorTargetCard(
            title: tr('Gruppi di squillo'),
            icon: Icons.phone_callback_rounded,
            entries: [
              for (final g in conn.ringGroups)
                _TargetItem(
                  number: g.number,
                  title:
                      '${g.number} ${g.name} '
                      '(${_onlineCount(g.memberNumbers)}/${_totalCount(g.memberCount, g.memberNumbers)})',
                  searchKey: '${g.number} ${g.name}',
                  onTap: phone.canDial ? () => phone.dial(g.number) : null,
                ),
            ],
            onDrop: onBlindTransfer,
          ),
        ),
        const SizedBox(width: DrinSpace.s3),
        Expanded(
          child: _OperatorTargetCard(
            title: tr('Code'),
            icon: Icons.support_agent_rounded,
            entries: [
              for (final q in conn.queues)
                _TargetItem(
                  number: q.number,
                  title:
                      '${q.number} ${q.name} '
                      '(${_onlineCount(q.agentNumbers)}/${_totalCount(q.memberCount, q.agentNumbers)})',
                  searchKey: '${q.number} ${q.name}',
                  onTap: phone.canDial ? () => phone.dial(q.number) : null,
                ),
            ],
            onDrop: onBlindTransfer,
          ),
        ),
        const SizedBox(width: DrinSpace.s3),
        Expanded(
          child: _OperatorTargetCard(
            title: tr('Parcheggio'),
            icon: Icons.local_parking_rounded,
            entries: [
              for (final slot in conn.parkingSlots)
                if (busyBySlot[slot] case final parked?)
                  _TargetItem(
                    number: slot,
                    title: '$slot ${parked.parkedParty}',
                    searchKey: '$slot ${parked.parkedParty}',
                    busy: true,
                    actionLabel: phone.canDial ? tr('Riprendi') : null,
                    onTap: phone.canDial ? () => phone.dial(slot) : null,
                  )
                else
                  _TargetItem(
                    number: slot,
                    title: '$slot ${tr('Libero')}',
                    searchKey: slot,
                    busy: false,
                  ),
            ],
            onDrop: onBlindTransfer,
            onCardDrop: onParkCall,
          ),
        ),
        const SizedBox(width: DrinSpace.s3),
        Expanded(
          child: _OperatorTargetCard(
            title: tr('Casella vocale di gruppo'),
            icon: Icons.voicemail_rounded,
            entries: [
              for (final v in conn.vmGroups)
                _TargetItem(
                  number: v.number,
                  title: '${v.number} ${v.name}',
                  searchKey: '${v.number} ${v.name}',
                  onTap: phone.canDial ? () => phone.dial(v.number) : null,
                ),
            ],
            onDrop: onBlindTransfer,
          ),
        ),
      ],
    );
  }
}

class _TargetItem {
  const _TargetItem({
    required this.number,
    required this.title,
    required this.searchKey,
    this.busy,
    this.actionLabel,
    this.onTap,
  });
  final String number;
  final String title;
  final String searchKey;
  final bool? busy;
  final String? actionLabel;
  final VoidCallback? onTap;
}

class _OperatorTargetCard extends StatefulWidget {
  const _OperatorTargetCard({
    required this.title,
    required this.icon,
    required this.entries,
    required this.onDrop,
    this.onCardDrop,
  });

  final String title;
  final IconData icon;
  final List<_TargetItem> entries;
  final void Function(LiveCall call, String destination, {String? label})
  onDrop;
  final ValueChanged<LiveCall>? onCardDrop;

  @override
  State<_OperatorTargetCard> createState() => _OperatorTargetCardState();
}

class _OperatorTargetCardState extends State<_OperatorTargetCard> {
  bool _searching = false;
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final q = _filter.text.trim().toLowerCase();
    final filtered = [
      for (final e in widget.entries)
        if (q.isEmpty || e.searchKey.toLowerCase().contains(q)) e,
    ];
    return DragTarget<LiveCall>(
      onWillAcceptWithDetails: (_) => widget.onCardDrop != null,
      onAcceptWithDetails: (d) => widget.onCardDrop?.call(d.data),
      builder: (_, cardCandidates, _) {
        final cardOver = widget.onCardDrop != null && cardCandidates.isNotEmpty;
        return Container(
          padding: const EdgeInsets.all(DrinSpace.s3),
          decoration: BoxDecoration(
            color: cardOver
                ? c.primary.withValues(alpha: 0.08)
                : c.surface,
            border: Border.all(
              color: cardOver ? c.primary : c.line,
              width: cardOver ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(DrinRadius.panel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(widget.icon, size: 16, color: c.primary),
                  const SizedBox(width: DrinSpace.s2),
                  Expanded(
                    child: _searching
                        ? SizedBox(
                            height: 28,
                            child: TextField(
                              controller: _filter,
                              autofocus: true,
                              onChanged: (_) => setState(() {}),
                              style: DrinText.detail.copyWith(color: c.ink),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: DrinSpace.s2,
                                  vertical: 4,
                                ),
                                hintText: widget.title,
                                hintStyle: DrinText.detail.copyWith(
                                  color: c.muted,
                                ),
                              ),
                            ),
                          )
                        : Text(
                            widget.title,
                            overflow: TextOverflow.ellipsis,
                            style: DrinText.heading.copyWith(color: c.ink),
                          ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    iconSize: 16,
                    icon: Icon(
                      _searching ? Icons.close_rounded : Icons.search_rounded,
                      color: c.muted,
                    ),
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) _filter.clear();
                    }),
                  ),
                ],
              ),
              Divider(color: c.line, height: DrinSpace.s3),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          '—',
                          style: DrinText.detail.copyWith(color: c.muted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => Divider(
                          color: c.line.withValues(alpha: 0.5),
                          height: 1,
                        ),
                        itemBuilder: (_, i) {
                          final item = filtered[i];
                          return DragTarget<LiveCall>(
                            onWillAcceptWithDetails: (_) => true,
                            onAcceptWithDetails: (d) => widget.onDrop(
                              d.data,
                              item.number,
                              label: item.title,
                            ),
                            builder: (_, candidates, _) {
                              final over = candidates.isNotEmpty;
                              return AnimatedContainer(
                                duration: DrinMotion.fast,
                                decoration: BoxDecoration(
                                  color: over
                                      ? c.primary.withValues(alpha: 0.16)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                    DrinRadius.control,
                                  ),
                                  border: over
                                      ? Border.all(
                                          color: c.primary,
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    DrinRadius.control,
                                  ),
                                  onTap: item.onTap,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: DrinSpace.s2,
                                    ),
                                    child: Row(
                                      children: [
                                        if (item.busy != null) ...[
                                          Container(
                                            width: 9,
                                            height: 9,
                                            decoration: BoxDecoration(
                                              color: item.busy! ? c.busy : c.ok,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: DrinSpace.s2),
                                        ],
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            overflow: TextOverflow.ellipsis,
                                            style: DrinText.detail.copyWith(
                                              color: c.ink,
                                            ),
                                          ),
                                        ),
                                        if (item.actionLabel != null && !over)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: DrinSpace.s2,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.primary.withValues(
                                                alpha: 0.14,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    DrinRadius.pill,
                                                  ),
                                            ),
                                            child: Text(
                                              item.actionLabel!,
                                              style: DrinText.detail.copyWith(
                                                color: c.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        if (over)
                                          Icon(
                                            Icons.phone_forwarded_rounded,
                                            size: 14,
                                            color: c.primary,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Dialogo per il comando "Trasferisci" dal menu contestuale di una chiamata.
class _TransferPickerDialog extends StatefulWidget {
  const _TransferPickerDialog({
    required this.phone,
    required this.conn,
    this.attended = false,
  });
  final PhoneController phone;
  final PbxConnection conn;
  final bool attended;

  @override
  State<_TransferPickerDialog> createState() => _TransferPickerDialogState();
}

class _TransferPickerDialogState extends State<_TransferPickerDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final q = _ctl.text.trim().toLowerCase();
    final conn = widget.conn;
    final items = <(IconData, String, String)>[
      for (final e in conn.directory)
        if (e.number != conn.voicemailOf)
          (
            Icons.person_outline_rounded,
            e.number,
            e.name.isEmpty ? e.number : '${e.name} (${e.number})',
          ),
      for (final g in conn.ringGroups)
        (Icons.phone_callback_rounded, g.number, '${g.name} (${g.number})'),
      for (final qu in conn.queues)
        (Icons.support_agent_rounded, qu.number, '${qu.name} (${qu.number})'),
      for (final v in conn.vmGroups)
        (Icons.voicemail_rounded, v.number, '${v.name} (${v.number})'),
    ].where((x) => q.isEmpty || x.$3.toLowerCase().contains(q)).toList();

    return AlertDialog(
      title: Text(
        widget.attended ? tr('Trasferisci con consultazione…') : tr('Trasferisci a…'),
        style: DrinText.title.copyWith(color: c.ink),
      ),
      content: SizedBox(
        width: 380,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  Navigator.pop(context, (v.trim(), v.trim()));
                }
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: tr('Numero, interno o nome'),
              ),
            ),
            const SizedBox(height: DrinSpace.s2),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final (icon, num, label) = items[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(icon, size: 18, color: c.primary),
                    title: Text(
                      label,
                      style: DrinText.body.copyWith(color: c.ink),
                    ),
                    onTap: () => Navigator.pop(context, (num, label)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Annulla')),
        ),
        FilledButton(
          onPressed: _ctl.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  (_ctl.text.trim(), _ctl.text.trim()),
                ),
          child: Text(widget.attended ? tr('Consulta') : tr('Trasferisci')),
        ),
      ],
    );
  }
}

/// Colonna BLF generale: Preferiti, poi un gruppo per reparto (attivi/totali).
/// Ogni riga accetta il trascinamento di una [LiveCall] per trasferimento cieco.
class _BlfColumn extends StatefulWidget {
  const _BlfColumn({
    required this.phone,
    required this.conn,
    required this.onBlindTransfer,
  });
  final PhoneController phone;
  final PbxConnection conn;
  final void Function(LiveCall call, String destination, {String? label})
  onBlindTransfer;

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
      padding: const EdgeInsets.all(DrinSpace.s3),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(DrinRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.people_alt_outlined, size: 18, color: c.primary),
              const SizedBox(width: DrinSpace.s2),
              Text(
                tr('Interni'),
                style: DrinText.heading.copyWith(color: c.ink),
              ),
            ],
          ),
          const SizedBox(height: DrinSpace.s2),
          TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: tr('Cerca interno'),
              hintStyle: DrinText.detail.copyWith(color: c.muted),
            ),
          ),
          const SizedBox(height: DrinSpace.s2),
          Expanded(
            child: ListView(
              children: [
                for (final (name, list, fav) in groups)
                  if (list.isNotEmpty || (fav && q.isEmpty)) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(DrinRadius.control),
                      onTap: () => setState(
                        () => _closed.contains(name)
                            ? _closed.remove(name)
                            : _closed.add(name),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: DrinSpace.s2,
                          horizontal: DrinSpace.s1,
                        ),
                        child: Row(
                          children: [
                            if (fav)
                              Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: c.brand,
                              ),
                            if (fav) const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$name (${list.where(active).length}/${list.length})',
                                overflow: TextOverflow.ellipsis,
                                style: DrinText.heading.copyWith(color: c.ink),
                              ),
                            ),
                            AnimatedRotation(
                              turns: _closed.contains(name) ? -0.25 : 0,
                              duration: DrinMotion.base,
                              curve: DrinMotion.curve,
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
                      duration: DrinMotion.base,
                      curve: DrinMotion.curve,
                      alignment: Alignment.topCenter,
                      child: _closed.contains(name)
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final e in list)
                                  _BlfRow(
                                    phone: p,
                                    ext: e,
                                    conn: widget.conn,
                                    onBlindTransfer: widget.onBlindTransfer,
                                  ),
                              ],
                            ),
                    ),
                    Divider(color: c.line, height: DrinSpace.s2),
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
  const _BlfRow({
    required this.phone,
    required this.ext,
    required this.conn,
    required this.onBlindTransfer,
  });
  final PhoneController phone;
  final Extension ext;
  final PbxConnection conn;
  final void Function(LiveCall call, String destination, {String? label})
  onBlindTransfer;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final s = phone.blfOf(ext);
    final stale = phone.blfStale(ext);
    final dot = switch (s) {
      BlfStatus.idle => c.ok,
      BlfStatus.busy => c.busy,
      BlfStatus.ringing => c.ringing,
      _ => c.line,
    }.withValues(alpha: stale ? 0.35 : 1);
    final pr = presenceOf(c, phone.presenceOf(ext));
    final live = conn.extensionCalls[ext.number];
    final callable = phone.isCallable(ext) && phone.canDial;
    final displayLabel = nameIsNumber(ext.name, ext.number)
        ? ext.number
        : '${ext.name} (${ext.number})';

    return DragTarget<LiveCall>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) =>
          onBlindTransfer(d.data, ext.number, label: displayLabel),
      builder: (_, candidates, _) {
        final over = candidates.isNotEmpty;
        return Tooltip(
          message: [
            blfLabel(s),
            if (stale) tr('da confermare'),
            if (pr != null) pr.$3,
          ].join(' · '),
          waitDuration: const Duration(milliseconds: 600),
          child: AnimatedContainer(
            duration: DrinMotion.fast,
            decoration: BoxDecoration(
              color: over
                  ? c.primary.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(DrinRadius.control),
              border: over ? Border.all(color: c.primary, width: 1.5) : null,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(DrinRadius.control),
              onTap: callable ? () => phone.dial(ext.number, via: ext) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: DrinMotion.base,
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      ext.number,
                      style: DrinText.number.copyWith(color: c.muted),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nameIsNumber(ext.name, ext.number) ? '' : ext.name,
                        overflow: TextOverflow.ellipsis,
                        style: DrinText.body.copyWith(color: c.ink),
                      ),
                    ),
                    if (over)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.phone_forwarded_rounded,
                          size: 14,
                          color: c.primary,
                        ),
                      ),
                    if (live != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: LiveChip(live, dense: true),
                      ),
                    if (s == BlfStatus.ringing &&
                        (conn.extPickupCode ?? '').isNotEmpty &&
                        phone.canDial)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: IconButton(
                          tooltip: tr('Rispondi per {n}', {'n': ext.number}),
                          onPressed: () =>
                              phone.dial('${conn.extPickupCode}${ext.number}'),
                          style: IconButton.styleFrom(
                            backgroundColor: c.ok.withValues(alpha: 0.16),
                            foregroundColor: c.okText,
                            minimumSize: const Size(24, 24),
                            fixedSize: const Size(24, 24),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(
                            Icons.phone_in_talk_rounded,
                            size: 14,
                          ),
                        ),
                      ),
                    if (pr != null) Icon(pr.$1, size: 14, color: pr.$2),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
