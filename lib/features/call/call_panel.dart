import 'dart:async';

import 'package:flutter/material.dart';

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
        return 'Chiamata in arrivo';
      case CallPhase.outgoing:
        return 'Chiamata in corso…';
      case CallPhase.paused:
        return 'In attesa';
      default:
        if (since == null) return 'In linea';
        final d = DateTime.now().difference(since);
        String two(int n) => n.toString().padLeft(2, '0');
        return 'In linea · ${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
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
            title.isEmpty ? 'Sconosciuto' : title,
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
                  child: _bigButton('Rispondi', DrinColors.callGreen, p.answer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _bigButton('Rifiuta', DrinColors.hangupRed, p.hangup),
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
                      p.muted ? 'Riattiva' : 'Muto',
                      p.muted,
                      Icons.mic_off_outlined,
                      p.toggleMute,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _toggle(
                      context,
                      'Tastiera',
                      _dtmfOpen,
                      Icons.dialpad,
                      () => setState(() => _dtmfOpen = !_dtmfOpen),
                    ),
                  ),
                ],
              ),
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
            _bigButton('Riaggancia', DrinColors.hangupRed, p.hangup),
          ],
        ],
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
