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
    FunctionKeyKind.blf => tr('BLF (interno, linea/trunk o codice *8XX/*9XX)'),
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
                        'Aggiungi tasti BLF (interni, trunk VoIP/FXO/ISDN o codici *8XX/*9XX), chiamate rapide, DTMF o parcheggio.',
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
                          : tr('Clic = chiama, impegna o rispondi'),
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

  Future<void> _dialViaTrunk(BuildContext context) async {
    final number = await showDialog<String>(
      context: context,
      builder: (_) => _SeizeTrunkDialog(item: item),
    );
    if (number != null) {
      await phone.seizeTrunk(item, number: number);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final target = item.target.trim();
    final isBlfWatch = item.kind == FunctionKeyKind.blf;
    final isTrunk = phone.isTrunkLikeKey(item);
    final blf = isBlfWatch ? phone.blfOfNumber(target) : null;
    final blfReason = isBlfWatch ? phone.blfReasonOfNumber(target) : '';
    final live =
        isBlfWatch && !isTrunk
            ? phone.liveOfNumber(target)
            : null;
    final trunkCalls = isTrunk ? phone.trunkLiveCalls(target) : const [];
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
        isBlfWatch &&
        (blf == BlfStatus.ringing || live?.state == LiveState.ringing);
    final resolvedName = item.label.isNotEmpty
        ? item.label
        : (target.isNotEmpty && item.kind == FunctionKeyKind.blf
              ? (phone.nameFor(target).isNotEmpty
                    ? phone.nameFor(target)
                    : target)
              : target.isNotEmpty
              ? target
              : FunctionKeysPanel.kindLabel(item.kind));

    final unknownWithReason =
        blf == BlfStatus.unknown && blfReason.isNotEmpty
            ? '$target · ${tr('Stato sconosciuto')} ($blfReason)'
            : null;

    final trunkStateText = trunkCalls.isNotEmpty
        ? (trunkCalls.length > 1
              ? '$target · ${tr('{n} chiamate', {'n': trunkCalls.length})}'
              : '$target · ${trunkCalls.first.caller} → ${trunkCalls.first.callee}')
        : (unknownWithReason ??
              (blf != null ? '$target · ${blfLabel(blf)}' : target));

    final subtitle = switch (item.kind) {
      FunctionKeyKind.blf =>
        isTrunk
            ? trunkStateText
            : ringing
            ? '$target · ${tr('Squilla')}'
            : unknownWithReason ??
                  (blf != null ? '$target · ${blfLabel(blf)}' : target),
      FunctionKeyKind.dnd => dndOn ? tr('Attivo') : tr('Disattivo'),
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
        ((item.kind == FunctionKeyKind.blf &&
                !isTrunk &&
                !target.startsWith('*')) ||
            item.kind == FunctionKeyKind.speedDial) &&
        target.isNotEmpty;

    final tile = Material(
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
                    Row(
                      children: [
                        if (isTrunk) ...[
                          Icon(
                            Icons.cable_rounded,
                            size: 13,
                            color: c.muted,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            resolvedName,
                            overflow: TextOverflow.ellipsis,
                            style: DrinText.heading.copyWith(color: c.ink),
                          ),
                        ),
                      ],
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
                  'seize' => _dialViaTrunk(context),
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
                  if (isTrunk && phone.canDial)
                    PopupMenuItem(
                      value: 'seize',
                      child: Text(tr('Chiama tramite questa linea…')),
                    ),
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

    if (blfReason.isNotEmpty && blf == BlfStatus.unknown) {
      return Tooltip(message: blfReason, child: tile);
    }
    return tile;
  }
}

class _SeizeTrunkDialog extends StatefulWidget {
  const _SeizeTrunkDialog({required this.item});

  final FunctionKey item;

  @override
  State<_SeizeTrunkDialog> createState() => _SeizeTrunkDialogState();
}

class _SeizeTrunkDialogState extends State<_SeizeTrunkDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final prefix = item.dialCode.trim();
    return AlertDialog(
      title: Text(
        tr('Impegna linea {n}', {
          'n': item.label.isNotEmpty ? item.label : item.target,
        }),
      ),
      content: SizedBox(
        width: 340,
        child: TextField(
          controller: _ctl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('Numero da chiamare (opzionale)'),
            helperText: prefix.isNotEmpty
                ? tr('Prefisso linea: {p}', {'p': prefix})
                : null,
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Annulla')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _ctl.text.trim()),
          icon: const Icon(Icons.call_rounded, size: 17),
          label: Text(tr('Chiama')),
        ),
      ],
    );
  }
}

/// Dialogo per creare o modificare un tasto funzione / BLF.
Future<void> showFunctionKeyDialog(
  BuildContext context,
  PhoneController phone, {
  FunctionKey? initial,
}) async {
  final saved = await showDialog<FunctionKey>(
    context: context,
    builder: (_) => _FunctionKeyDialog(phone: phone, initial: initial),
  );
  if (saved != null) await phone.saveFunctionKey(saved);
}

class _FunctionKeyDialog extends StatefulWidget {
  const _FunctionKeyDialog({required this.phone, this.initial});

  final PhoneController phone;
  final FunctionKey? initial;

  @override
  State<_FunctionKeyDialog> createState() => _FunctionKeyDialogState();
}

class _FunctionKeyDialogState extends State<_FunctionKeyDialog> {
  late FunctionKeyKind _kind = widget.initial?.kind ?? FunctionKeyKind.blf;
  late final _labelCtl = TextEditingController(
    text: widget.initial?.label ?? '',
  );
  late final _targetCtl = TextEditingController(
    text: widget.initial?.target ?? '',
  );
  late final _dialCodeCtl = TextEditingController(
    text: widget.initial?.dialCode ?? '',
  );

  @override
  void dispose() {
    _labelCtl.dispose();
    _targetCtl.dispose();
    _dialCodeCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone;
    final initial = widget.initial;
    final needsTarget =
        _kind != FunctionKeyKind.dnd && _kind != FunctionKeyKind.queuePause;
    final targetLabel = switch (_kind) {
      FunctionKeyKind.blf => tr(
        'Valore BLF (interno, *8XX/*9XX o nome linea/trunk)',
      ),
      FunctionKeyKind.speedDial => tr('Numero da chiamare'),
      FunctionKeyKind.dtmf => tr('Sequenza DTMF (es. # o 1234#)'),
      FunctionKeyKind.park => tr('Slot o codice parcheggio'),
      FunctionKeyKind.pickup => tr('Interno o codice pickup (es. *4)'),
      _ => tr('Destinazione'),
    };
    final targetHint = _kind == FunctionKeyKind.blf
        ? tr('Es. 301, *801, TG100-Acc oppure 306_TG100-Acc (SLA)')
        : null;
    final suggestions =
        _kind == FunctionKeyKind.blf || _kind == FunctionKeyKind.pickup
        ? phone.allExtensions.take(8).toList()
        : const <Extension>[];
    final trunks = _kind == FunctionKeyKind.blf
        ? phone.knownTrunkNames.take(8).toList()
        : const <String>[];
    final slots = _kind == FunctionKeyKind.park
        ? (phone.primaryConnection?.parkingSlots ?? const <String>[])
        : const <String>[];

    return AlertDialog(
      title: Text(
        initial == null
            ? tr('Nuovo tasto funzione')
            : tr('Modifica tasto funzione'),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<FunctionKeyKind>(
                initialValue: _kind,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Tipo di tasto')),
                items: [
                  for (final k in FunctionKeyKind.values)
                    DropdownMenuItem(
                      value: k,
                      child: Row(
                        children: [
                          Icon(FunctionKeysPanel.kindIcon(k), size: 18),
                          const SizedBox(width: DrinSpace.s2),
                          Flexible(
                            child: Text(
                              FunctionKeysPanel.kindLabel(k),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _kind = v);
                },
              ),
              const SizedBox(height: DrinSpace.s3),
              TextField(
                controller: _labelCtl,
                decoration: InputDecoration(
                  labelText: tr('Etichetta (opzionale)'),
                ),
              ),
              if (needsTarget) ...[
                const SizedBox(height: DrinSpace.s3),
                TextField(
                  controller: _targetCtl,
                  autofocus: initial == null,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: targetLabel,
                    helperText: targetHint,
                  ),
                ),
              ],
              if (_kind == FunctionKeyKind.blf) ...[
                const SizedBox(height: DrinSpace.s3),
                TextField(
                  controller: _dialCodeCtl,
                  decoration: InputDecoration(
                    labelText: tr('Prefisso automatico impegno linea (opzionale)'),
                    helperText: tr(
                      'Vuoto = al clic impegna direttamente il valore BLF (es. 9 o *91 opzionale)',
                    ),
                  ),
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
                          _targetCtl.text = ext.number;
                          if (_labelCtl.text.trim().isEmpty &&
                              ext.name.isNotEmpty) {
                            _labelCtl.text = ext.name;
                          }
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ],
              if (trunks.isNotEmpty) ...[
                const SizedBox(height: DrinSpace.s2),
                Wrap(
                  spacing: DrinSpace.s1,
                  runSpacing: DrinSpace.s1,
                  children: [
                    for (final t in trunks)
                      ActionChip(
                        avatar: const Icon(Icons.cable_rounded, size: 14),
                        label: Text(t),
                        onPressed: () {
                          _targetCtl.text = t;
                          if (_labelCtl.text.trim().isEmpty) {
                            _labelCtl.text = t;
                          }
                          setState(() {});
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
                          _targetCtl.text = slot;
                          if (_labelCtl.text.trim().isEmpty) {
                            _labelCtl.text = '${tr('Parcheggio')} $slot';
                          }
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Annulla')),
        ),
        FilledButton(
          onPressed: () {
            if (needsTarget &&
                _kind != FunctionKeyKind.pickup &&
                _kind != FunctionKeyKind.park &&
                _targetCtl.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(
              context,
              FunctionKey(
                id: initial?.id ?? '',
                kind: _kind,
                label: _labelCtl.text.trim(),
                target: needsTarget ? _targetCtl.text.trim() : '',
                dialCode:
                    _kind == FunctionKeyKind.blf ? _dialCodeCtl.text.trim() : '',
              ),
            );
          },
          child: Text(tr('Salva')),
        ),
      ],
    );
  }
}
