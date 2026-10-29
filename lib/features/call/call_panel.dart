import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/sip/sip_engine.dart';
import 'keypad.dart';

/// Pannello della chiamata corrente: in arrivo, in uscita, in linea.
class CallPanel extends StatefulWidget {
  const CallPanel({super.key, required this.phone, required this.call});
  final PhoneController phone;
  final CallEvent call;

  @override
  State<CallPanel> createState() => _CallPanelState();
}

class _CallPanelState extends State<CallPanel> {
  Timer? _tick;
  bool _dtmfOpen = false;
  String _dtmf = '';

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _status {
    final since = widget.phone.callConnectedAt;
    switch (widget.call.phase) {
      case CallPhase.incoming:
        return tr('Chiamata in arrivo');
      case CallPhase.outgoing:
        return tr('Chiamata in corso…');
      case CallPhase.paused:
        return tr('In attesa');
      default:
        if (since == null) return tr('In linea');
        final d = DateTime.now().difference(since);
        String two(int n) => n.toString().padLeft(2, '0');
        return '${tr('In linea')} · ${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final p = widget.phone;
    final call = widget.call;
    // Nome dal SIP, altrimenti da interni o rubrica aziendale.
    final name = call.remoteName.isNotEmpty
        ? call.remoteName
        : p.nameFor(call.remoteNumber);
    final title = name.isNotEmpty ? name : call.remoteNumber;
    final incoming = call.phase == CallPhase.incoming;

    return Container(
      width: 340,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: incoming ? c.ringing : c.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x47000000),
            blurRadius: 32,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _status,
              style: TextStyle(
                color: incoming ? c.ringing : c.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title.isEmpty ? tr('Sconosciuto') : title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (name.isNotEmpty)
              Text(
                call.remoteNumber,
                style: TextStyle(fontFamily: monoFont, color: c.muted),
              ),
            const SizedBox(height: 20),
            if (incoming)
              Row(
                children: [
                  Expanded(
                    child: _bigButton(
                      tr('Rispondi'),
                      DrinColors.callGreen,
                      p.answer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _bigButton(
                      tr('Rifiuta'),
                      DrinColors.hangupRed,
                      p.hangup,
                    ),
                  ),
                ],
              )
            else ...[
              if (call.phase != CallPhase.outgoing)
                Row(
                  children: [
                    Expanded(
                      child: _toggle(
                        context,
                        p.muted ? tr('Riattiva') : tr('Muto'),
                        p.muted,
                        Icons.mic_off_outlined,
                        p.toggleMute,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _toggle(
                        context,
                        p.onHold ? tr('Riprendi') : tr('Attesa'),
                        p.onHold,
                        Icons.pause_rounded,
                        p.toggleHold,
                      ),
                    ),
                  ],
                ),
              if (call.phase != CallPhase.outgoing) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _toggle(
                        context,
                        tr('Tastiera'),
                        _dtmfOpen,
                        Icons.dialpad,
                        () => setState(() => _dtmfOpen = !_dtmfOpen),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _toggle(
                        context,
                        tr('Trasferisci'),
                        false,
                        Icons.phone_forwarded_rounded,
                        () => showDialog<void>(
                          context: context,
                          builder: (_) => _TransferDialog(phone: p),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_dtmfOpen) ...[
                const SizedBox(height: 12),
                Text(
                  _dtmf,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: monoFont,
                    fontSize: 18,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 8),
                Keypad(
                  onKey: (d) {
                    setState(() => _dtmf += d);
                    p.sendDtmf(d);
                  },
                ),
              ],
              const SizedBox(height: 16),
              if (p.canCompleteTransfer) ...[
                const SizedBox(height: 10),
                _bigButton(
                  tr('Completa trasferimento'),
                  c.accent,
                  p.completeTransfer,
                ),
              ],
              const SizedBox(height: 10),
              _bigButton(tr('Riaggancia'), DrinColors.hangupRed, p.hangup),
            ],
            // Altre chiamate: in attesa (scambio) o in arrivo (avviso di chiamata).
            for (final other in p.otherCalls) ...[
              const SizedBox(height: 12),
              _OtherCallRow(phone: p, call: other),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bigButton(String label, Color color, VoidCallback onTap) =>
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  Widget _toggle(
    BuildContext context,
    String label,
    bool on,
    IconData icon,
    VoidCallback onTap,
  ) {
    final c = context.drin;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        backgroundColor: on ? c.accent : Colors.transparent,
        foregroundColor: on ? c.surface : c.text,
        side: BorderSide(color: on ? c.accent : c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// Trasferimento cieco: numero libero o scelta tra interni e rubrica.
class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.phone});
  final PhoneController phone;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _go(String number, {required bool consult}) {
    if (number.trim().isEmpty) return;
    consult ? widget.phone.consult(number) : widget.phone.transfer(number);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final hits = widget.phone.search(_text.text, limit: 6);
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(tr('Trasferisci chiamata')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) => _go(v, consult: false),
              style: mono(c.text, size: 15),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: tr('Numero, interno o nome'),
              ),
            ),
            const SizedBox(height: 8),
            for (final h in hits)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(h.name),
                subtitle: Text(h.number, style: mono(c.muted, size: 12)),
                trailing: Icon(Icons.phone_forwarded_rounded, color: c.accent),
                onTap: () => setState(() => _text.text = h.number),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Annulla')),
        ),
        // Assistito: prima si parla con il destinatario, poi si completa.
        OutlinedButton.icon(
          onPressed: () => _go(_text.text, consult: true),
          icon: const Icon(Icons.record_voice_over_outlined, size: 18),
          label: Text(tr('Consulta prima')),
        ),
        FilledButton.icon(
          onPressed: () => _go(_text.text, consult: false),
          icon: const Icon(Icons.phone_forwarded_rounded, size: 18),
          label: Text(tr('Trasferisci subito')),
        ),
      ],
    );
  }
}

/// Riga compatta per una chiamata non in primo piano.
class _OtherCallRow extends StatelessWidget {
  const _OtherCallRow({required this.phone, required this.call});
  final PhoneController phone;
  final CallEvent call;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final incoming = call.phase == CallPhase.incoming;
    final name = call.remoteName.isNotEmpty
        ? call.remoteName
        : phone.nameFor(call.remoteNumber);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: incoming ? c.ringing : c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Tooltip(
            message: incoming ? tr('In arrivo') : tr('In attesa'),
            child: Icon(
              incoming ? Icons.ring_volume_rounded : Icons.pause_circle_outline,
              size: 20,
              color: incoming ? c.ringing : c.muted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : call.remoteNumber,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
                ),
                if (name.isNotEmpty)
                  Text(call.remoteNumber, style: mono(c.muted, size: 12)),
              ],
            ),
          ),
          if (incoming) ...[
            IconButton(
              tooltip: tr('Rispondi (la chiamata attuale va in attesa)'),
              color: DrinColors.callGreen,
              onPressed: () => phone.answer(call.id),
              icon: const Icon(Icons.call_rounded),
            ),
            IconButton(
              tooltip: tr('Rifiuta'),
              color: DrinColors.hangupRed,
              onPressed: () => phone.hangup(call.id),
              icon: const Icon(Icons.call_end_rounded),
            ),
          ] else ...[
            IconButton(
              tooltip: tr('Riprendi (scambia)'),
              color: c.accent,
              onPressed: () => phone.resumeCall(call.id),
              icon: const Icon(Icons.swap_calls_rounded),
            ),
            IconButton(
              tooltip: tr('Riaggancia'),
              color: DrinColors.hangupRed,
              onPressed: () => phone.hangup(call.id),
              icon: const Icon(Icons.call_end_rounded),
            ),
          ],
        ],
      ),
    );
  }
}
