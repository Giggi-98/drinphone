import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/pbx/pbx_connection.dart' show LiveState;
import '../../core/security/settings_store.dart';
import '../../core/sip/sip_engine.dart';
import 'widgets.dart';

/// Pannello laterale o modale dei Tasti funzione / BLF (stile DSS desk-phone).
class FunctionKeysPanel extends StatelessWidget {
  const FunctionKeysPanel({
    super.key,
    required this.phone,
    required this.onClose,
    this.isDialog = false,
  });

  final PhoneController phone;
  final VoidCallback onClose;
  final bool isDialog;

  static String kindLabel(FunctionKeyKind kind) => switch (kind) {
    FunctionKeyKind.blf => tr('BLF (Interno)'),
    FunctionKeyKind.speedDial => tr('Chiamata rapida'),
    FunctionKeyKind.dtmf => tr('DTMF rapido'),
    FunctionKeyKind.park => tr('Parcheggio'),
    FunctionKeyKind.pickup => tr('Pickup / Codice'),
    FunctionKeyKind.dnd => tr('Non disturbare'),
    FunctionKeyKind.queuePause => tr('Pausa code'),
  };

  static IconData kindIcon(FunctionKeyKind kind) => switch (kind) {
    FunctionKeyKind.blf => Icons.person_outline_rounded,
    FunctionKeyKind.speedDial => Icons.call_rounded,
    FunctionKeyKind.dtmf => Icons.dialpad_rounded,
    FunctionKeyKind.park => Icons.local_parking_rounded,
    FunctionKeyKind.pickup => Icons.phone_in_talk_rounded,
    FunctionKeyKind.dnd => Icons.do_not_disturb_on_rounded,
    FunctionKeyKind.queuePause => Icons.pause_circle_outline_rounded,
  };

  bool get _hasUnimportedFavorites {
    final existing = {
      for (final k in phone.settings.functionKeys)
        if (k.kind == FunctionKeyKind.blf) k.target.trim(),
    };
    return phone.favorites.any((e) => !existing.contains(e.number));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final keys = phone.settings.functionKeys;
    final inCall = phone.call?.phase == CallPhase.active;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DrinSpace.s4,
            DrinSpace.s3,
            DrinSpace.s2,
            DrinSpace.s3,
          ),
          child: Row(
            children: [
              Icon(Icons.apps_rounded, size: 18, color: c.primary),
              const SizedBox(width: DrinSpace.s2),
              Expanded(
                child: Text(
                  tr('Tasti funzione'),
                  style: DrinText.heading.copyWith(color: c.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: tr('Aggiungi tasto'),
                onPressed: () => showFunctionKeyDialog(context, phone),
                icon: Icon(Icons.add_rounded, size: 20, color: c.primary),
              ),
              IconButton(
                tooltip: tr('Chiudi'),
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
              ),
            ],
          ),
        ),
        Divider(color: c.line, height: 1),
        if (keys.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(DrinSpace.s5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.apps_rounded, size: 40, color: c.muted),
                    const SizedBox(height: DrinSpace.s3),
                    Text(
                      tr('Nessun tasto funzione'),
                      textAlign: TextAlign.center,
                      style: DrinText.heading.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: DrinSpace.s2),
                    Text(
                      tr(
                        'Aggiungi tasti BLF, chiamate rapide, DTMF o parcheggio accanto alla barra del numero.',
                      ),
                      textAlign: TextAlign.center,
                      style: DrinText.detail.copyWith(color: c.muted),
                    ),
                    const SizedBox(height: DrinSpace.s4),
                    FilledButton.icon(
                      onPressed: () => showFunctionKeyDialog(context, phone),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(tr('Aggiungi tasto')),
                    ),
                    if (_hasUnimportedFavorites) ...[
                      const SizedBox(height: DrinSpace.s2),
                      OutlinedButton.icon(
                        onPressed: phone.importFavoritesAsFunctionKeys,
                        icon: const Icon(Icons.star_outline_rounded, size: 18),
                        label: Text(tr('Importa dai preferiti')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
        else ...[
          if (_hasUnimportedFavorites || inCall)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DrinSpace.s3,
                vertical: DrinSpace.s2,
              ),
              decoration: BoxDecoration(
                color: c.raised,
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      inCall
                          ? tr('In chiamata: clic su BLF = trasferisci')
                          : tr('Clic = chiama o rispondi'),
                      style: DrinText.detail.copyWith(color: c.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_hasUnimportedFavorites)
                    TextButton(
                      onPressed: phone.importFavoritesAsFunctionKeys,
                      child: Text(tr('Dai preferiti')),
                    ),
                ],
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(DrinSpace.s3),
              itemCount: keys.length,
              separatorBuilder: (_, _) => const SizedBox(height: DrinSpace.s2),
              itemBuilder: (context, index) => _FunctionKeyTile(
                phone: phone,
                item: keys[index],
                index: index,
                total: keys.length,
              ),
            ),
          ),
        ],
      ],
    );

    if (isDialog) return body;
    return Container(
      width: 304,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: body,
    );
  }
}

class _FunctionKeyTile extends StatelessWidget {
  const _FunctionKeyTile({
    required this.phone,
    required this.item,
    required this.index,
    required this.total,
  });

  final PhoneController phone;
  final FunctionKey item;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final target = item.target.trim();
    final blf = item.kind == FunctionKeyKind.blf
        ? phone.blfOfNumber(target)
        : null;
    final live = item.kind == FunctionKeyKind.blf
        ? phone.liveOfNumber(target)
        : null;
    final parkBusy =
        item.kind == FunctionKeyKind.park && phone.isParkSlotBusy(target);
    final dndOn =
        item.kind == FunctionKeyKind.dnd &&
        phone.ownPresence == 'do_not_disturb';
    final conn = phone.primaryConnection;
    final queuesPaused =
        item.kind == FunctionKeyKind.queuePause &&
        conn != null &&
        conn.ownAgentQueues.isNotEmpty &&
        conn.ownAgentQueues.every((q) => conn.pausedQueueIds.contains(q.id));

    final Color? ledColor = switch (item.kind) {
      FunctionKeyKind.blf => switch (blf) {
        BlfStatus.idle => c.free,
        BlfStatus.ringing => c.squillo,
        BlfStatus.busy => c.busy,
        _ => live?.state == LiveState.ringing
            ? c.squillo
            : live != null
            ? c.busy
            : c.away,
      },
      FunctionKeyKind.park => parkBusy ? c.squillo : c.free,
      FunctionKeyKind.dnd => dndOn ? c.busy : c.away,
      FunctionKeyKind.queuePause => queuesPaused ? c.squillo : c.free,
      _ => null,
    };

    final ringing =
        item.kind == FunctionKeyKind.blf &&
        (blf == BlfStatus.ringing || live?.state == LiveState.ringing);
    final resolvedName = item.label.isNotEmpty
        ? item.label
        : (target.isNotEmpty && item.kind == FunctionKeyKind.blf
              ? (phone.nameFor(target).isNotEmpty
                    ? phone.nameFor(target)
                    : target)
              : FunctionKeysPanel.kindLabel(item.kind));

    final subtitle = switch (item.kind) {
      FunctionKeyKind.blf =>
        ringing
            ? '$target · ${tr('Squilla')}'
            : blf != null
            ? '$target · ${blfLabel(blf)}'
            : target,
      FunctionKeyKind.dnd =>
        dndOn ? tr('Attivo') : tr('Disattivo'),
      FunctionKeyKind.queuePause =>
        queuesPaused ? tr('In pausa') : tr('Attivo nelle code'),
      FunctionKeyKind.park =>
        parkBusy
            ? '${target.isNotEmpty ? target : (conn?.parkCode ?? '')} · ${tr('Occupato')}'
            : (target.isNotEmpty ? target : (conn?.parkCode ?? '')),
      _ => target.isEmpty ? FunctionKeysPanel.kindLabel(item.kind) : target,
    };

    final inActiveCall = phone.call?.phase == CallPhase.active;
    final supportsConsult =
        inActiveCall &&
        (item.kind == FunctionKeyKind.blf ||
            item.kind == FunctionKeyKind.speedDial) &&
        target.isNotEmpty;

    return Material(
      color: ringing ? c.squillo.withValues(alpha: 0.14) : c.raised,
      borderRadius: BorderRadius.circular(DrinRadius.row),
      child: InkWell(
        borderRadius: BorderRadius.circular(DrinRadius.row),
        onTap: () => phone.triggerFunctionKey(item),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DrinSpace.s3,
            vertical: DrinSpace.s2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DrinRadius.row),
            border: Border.all(color: ringing ? c.squilloLine : c.line),
          ),
          child: Row(
            children: [
              if (ledColor != null)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: DrinSpace.s3),
                  decoration: BoxDecoration(
                    color: ledColor,
                    shape: BoxShape.circle,
                    boxShadow: ledColor == c.away
                        ? null
                        : [
                            BoxShadow(
                              color: ledColor.withValues(alpha: 0.45),
                              blurRadius: 6,
                            ),
                          ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: DrinSpace.s3),
                  child: Icon(
                    FunctionKeysPanel.kindIcon(item.kind),
                    size: 16,
                    color: c.primary,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      resolvedName,
                      overflow: TextOverflow.ellipsis,
                      style: DrinText.heading.copyWith(color: c.ink),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: (item.kind == FunctionKeyKind.dtmf ||
                                    item.kind == FunctionKeyKind.speedDial
                                ? DrinText.number
                                : DrinText.detail)
                            .copyWith(color: c.muted),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Azioni'),
                icon: Icon(Icons.more_vert_rounded, size: 17, color: c.muted),
                padding: EdgeInsets.zero,
                onSelected: (v) => switch (v) {
                  'consult' => phone.triggerFunctionKey(
                    item,
                    consultFirst: true,
                  ),
                  'edit' => showFunctionKeyDialog(
                    context,
                    phone,
                    initial: item,
                  ),
                  'up' => phone.moveFunctionKey(item.id, -1),
                  'down' => phone.moveFunctionKey(item.id, 1),
                  'delete' => phone.deleteFunctionKey(item.id),
                  _ => null,
                },
                itemBuilder: (_) => [
                  if (supportsConsult)
                    PopupMenuItem(
                      value: 'consult',
                      child: Text(tr('Consulta prima')),
                    ),
                  PopupMenuItem(value: 'edit', child: Text(tr('Modifica'))),
                  if (index > 0)
                    PopupMenuItem(value: 'up', child: Text(tr('Sposta su'))),
                  if (index < total - 1)
                    PopupMenuItem(value: 'down', child: Text(tr('Sposta giù'))),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      tr('Elimina'),
                      style: DrinText.body.copyWith(color: c.busyText),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialogo per creare o modificare un tasto funzione / BLF.
Future<void> showFunctionKeyDialog(
  BuildContext context,
  PhoneController phone, {
  FunctionKey? initial,
}) async {
  var kind = initial?.kind ?? FunctionKeyKind.blf;
  final labelCtl = TextEditingController(text: initial?.label ?? '');
  final targetCtl = TextEditingController(text: initial?.target ?? '');
  final saved = await showDialog<FunctionKey>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final needsTarget =
            kind != FunctionKeyKind.dnd && kind != FunctionKeyKind.queuePause;
        final targetLabel = switch (kind) {
          FunctionKeyKind.blf => tr('Numero interno'),
          FunctionKeyKind.speedDial => tr('Numero da chiamare'),
          FunctionKeyKind.dtmf => tr('Sequenza DTMF (es. # o 1234#)'),
          FunctionKeyKind.park => tr('Slot o codice parcheggio'),
          FunctionKeyKind.pickup => tr('Interno o codice pickup (es. *4)'),
          _ => tr('Destinazione'),
        };
        final suggestions = kind == FunctionKeyKind.blf ||
                kind == FunctionKeyKind.pickup
            ? phone.allExtensions.take(8).toList()
            : const <Extension>[];
        final slots = kind == FunctionKeyKind.park
            ? (phone.primaryConnection?.parkingSlots ?? const <String>[])
            : const <String>[];
        return AlertDialog(
          title: Text(
            initial == null
                ? tr('Nuovo tasto funzione')
                : tr('Modifica tasto funzione'),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<FunctionKeyKind>(
                  initialValue: kind,
                  decoration: InputDecoration(labelText: tr('Tipo di tasto')),
                  items: [
                    for (final k in FunctionKeyKind.values)
                      DropdownMenuItem(
                        value: k,
                        child: Row(
                          children: [
                            Icon(FunctionKeysPanel.kindIcon(k), size: 18),
                            const SizedBox(width: DrinSpace.s2),
                            Text(FunctionKeysPanel.kindLabel(k)),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => kind = v);
                  },
                ),
                const SizedBox(height: DrinSpace.s3),
                TextField(
                  controller: labelCtl,
                  decoration: InputDecoration(
                    labelText: tr('Etichetta (opzionale)'),
                  ),
                ),
                if (needsTarget) ...[
                  const SizedBox(height: DrinSpace.s3),
                  TextField(
                    controller: targetCtl,
                    autofocus: initial == null,
                    decoration: InputDecoration(labelText: targetLabel),
                  ),
                ],
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: DrinSpace.s3),
                  Wrap(
                    spacing: DrinSpace.s1,
                    runSpacing: DrinSpace.s1,
                    children: [
                      for (final ext in suggestions)
                        ActionChip(
                          label: Text(
                            ext.name.isNotEmpty && ext.name != ext.number
                                ? '${ext.name} (${ext.number})'
                                : ext.number,
                          ),
                          onPressed: () {
                            targetCtl.text = ext.number;
                            if (labelCtl.text.trim().isEmpty &&
                                ext.name.isNotEmpty) {
                              labelCtl.text = ext.name;
                            }
                          },
                        ),
                    ],
                  ),
                ],
                if (slots.isNotEmpty) ...[
                  const SizedBox(height: DrinSpace.s3),
                  Wrap(
                    spacing: DrinSpace.s1,
                    runSpacing: DrinSpace.s1,
                    children: [
                      for (final slot in slots.take(8))
                        ActionChip(
                          label: Text(slot),
                          onPressed: () {
                            targetCtl.text = slot;
                            if (labelCtl.text.trim().isEmpty) {
                              labelCtl.text = '${tr('Parcheggio')} $slot';
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Annulla')),
            ),
            FilledButton(
              onPressed: () {
                if (needsTarget &&
                    kind != FunctionKeyKind.pickup &&
                    kind != FunctionKeyKind.park &&
                    targetCtl.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(
                  ctx,
                  FunctionKey(
                    id: initial?.id ?? '',
                    kind: kind,
                    label: labelCtl.text.trim(),
                    target: needsTarget ? targetCtl.text.trim() : '',
                  ),
                );
              },
              child: Text(tr('Salva')),
            ),
          ],
        );
      },
    ),
  );
  labelCtl.dispose();
  targetCtl.dispose();
  if (saved != null) await phone.saveFunctionKey(saved);
}
