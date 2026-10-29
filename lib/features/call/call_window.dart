import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/sip/sip_engine.dart';
import '../shell/widgets.dart';
import 'keypad.dart';
import 'native_video_view.dart';

/// Finestra di chiamata (struttura ispirata a Linkus Desktop): scheda compatta
/// per la chiamata in arrivo; in conversazione una finestra grande con
/// intestazione, video o avatar, pannelli laterali e barra dei comandi,
/// riducibile a barra o a schermo intero. I pannelli sono nella finestra e non
/// in dialoghi: il video è una finestra nativa e coprirebbe i dialoghi.
class CallWindow extends StatefulWidget {
  const CallWindow({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<CallWindow> createState() => _CallWindowState();
}

enum _Mode { normal, full, mini }

enum _Panel { none, keypad, transfer, newCall, participant, note }

class _CallWindowState extends State<CallWindow> {
  Timer? _tick;
  _Mode _mode = _Mode.normal;
  _Panel _panel = _Panel.none;
  String _dtmf = '';
  int? _callId;

  PhoneController get p => widget.phone;

  @override
  void initState() {
    super.initState();
    // Durata e qualità del segnale.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && p.call != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _duration() {
    final since = p.callConnectedAt;
    if (since == null) return '';
    final d = DateTime.now().difference(since);
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  String _nameOf(CallEvent c) =>
      c.remoteName.isNotEmpty ? c.remoteName : p.nameFor(c.remoteNumber);

  void _toggle(_Panel panel) =>
      setState(() => _panel = _panel == panel ? _Panel.none : panel);

  @override
  Widget build(BuildContext context) {
    final call = p.call;
    if (call == null) return const SizedBox.shrink();
    // Chiamata nuova: si riparte dalla finestra normale, senza pannelli.
    if (_callId != call.id) {
      _callId = call.id;
      _panel = _Panel.none;
      _dtmf = '';
      if (_mode == _Mode.full) _mode = _Mode.normal;
    }
    if (call.phase == CallPhase.incoming) {
      return Positioned(right: 24, bottom: 24, child: _incoming(call));
    }
    if (_mode == _Mode.mini) {
      return Positioned(right: 24, bottom: 24, child: _mini(call));
    }
    final full = _mode == _Mode.full;
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.all(full ? 0 : 28),
        child: Center(
          child: ConstrainedBox(
            constraints: full
                ? const BoxConstraints.expand()
                : const BoxConstraints(maxWidth: 1080, maxHeight: 720),
            child: _window(call, full),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- in arrivo

  Widget _incoming(CallEvent call) {
    final c = context.drin;
    final name = _nameOf(call);
    return Material(
      color: c.surface,
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.ringing),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              call.remoteVideo
                  ? tr('Videochiamata in arrivo')
                  : tr('Chiamata in arrivo'),
              style: TextStyle(color: c.ringing, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            _Avatar(name: name.isNotEmpty ? name : call.remoteNumber, size: 72),
            const SizedBox(height: 12),
            Text(
              name.isNotEmpty ? name : call.remoteNumber,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
            if (name.isNotEmpty)
              Text(call.remoteNumber, style: mono(c.muted, size: 13)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundButton(
                  icon: Icons.call_end_rounded,
                  label: tr('Rifiuta'),
                  color: DrinColors.hangupRed,
                  onTap: () => p.hangup(call.id),
                ),
                if (call.remoteVideo && p.videoEnabled)
                  _RoundButton(
                    icon: Icons.videocam_rounded,
                    label: tr('Rispondi in video'),
                    color: DrinColors.callGreen,
                    onTap: () => p.answer(call.id, true),
                  ),
                _RoundButton(
                  icon: Icons.call_rounded,
                  label: tr('Rispondi'),
                  color: DrinColors.callGreen,
                  onTap: () => p.answer(call.id),
                ),
              ],
            ),
            for (final other in p.otherCalls) ...[
              const SizedBox(height: 12),
              _OtherCall(phone: p, call: other),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- ridotta

  Widget _mini(CallEvent call) {
    final c = context.drin;
    final name = _nameOf(call);
    return Material(
      color: c.surface,
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Avatar(name: name.isNotEmpty ? name : call.remoteNumber, size: 34),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isNotEmpty ? name : call.remoteNumber,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                  Text(
                    call.phase == CallPhase.paused
                        ? tr('In attesa')
                        : _duration(),
                    style: mono(c.muted, size: 12),
                  ),
                ],
              ),
            ),
            if (p.isRecording(call.id)) ...[
              const SizedBox(width: 8),
              Icon(Icons.fiber_manual_record, size: 12, color: c.busy),
            ],
            const SizedBox(width: 8),
            IconButton(
              tooltip: p.muted ? tr('Riattiva') : tr('Muto'),
              onPressed: p.toggleMute,
              icon: Icon(
                p.muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                color: p.muted ? c.busy : c.text,
              ),
            ),
            IconButton(
              tooltip: tr('Espandi'),
              onPressed: () => setState(() => _mode = _Mode.normal),
              icon: Icon(Icons.open_in_full_rounded, color: c.text, size: 20),
            ),
            IconButton.filled(
              tooltip: tr('Riaggancia'),
              style: IconButton.styleFrom(
                backgroundColor: DrinColors.hangupRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => p.hangup(call.id),
              icon: const Icon(Icons.call_end_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- in conversazione

  Widget _window(CallEvent call, bool full) {
    final c = context.drin;
    final name = _nameOf(call);
    final outgoing = call.phase == CallPhase.outgoing;
    final showVideo =
        call.video &&
        (call.phase == CallPhase.active || call.phase == CallPhase.paused);
    return Material(
      color: c.surface,
      elevation: full ? 0 : 16,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(full ? 0 : 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(call, name, full),
          if (p.otherCalls.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              color: c.card,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final other in p.otherCalls)
                    _OtherCall(phone: p, call: other),
                ],
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: showVideo ? _video() : _identity(call, name, outgoing),
                ),
                if (_panel != _Panel.none)
                  Container(
                    width: 340,
                    decoration: BoxDecoration(
                      color: c.card,
                      border: Border(left: BorderSide(color: c.border)),
                    ),
                    child: _sidePanel(call),
                  ),
              ],
            ),
          ),
          _toolbar(call, outgoing),
        ],
      ),
    );
  }

  Widget _header(CallEvent call, String name, bool full) {
    final c = context.drin;
    final quality = p.callQuality(call.id);
    final status = switch (call.phase) {
      CallPhase.outgoing => tr('Chiamata in corso…'),
      CallPhase.paused => tr('In attesa'),
      _ => _duration(),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.side,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              name.isNotEmpty ? name : call.remoteNumber,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
          ),
          if (name.isNotEmpty) ...[
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: c.border,
            ),
            Text(call.remoteNumber, style: mono(c.text, size: 14)),
          ],
          const SizedBox(width: 12),
          Text(status, style: mono(c.muted, size: 13)),
          if (quality >= 0) ...[
            const SizedBox(width: 12),
            _SignalBars(quality: quality),
          ],
          if (call.inConference) ...[
            const SizedBox(width: 12),
            _Tag(text: tr('Conferenza'), color: c.accent),
          ],
          if (p.isRecording(call.id)) ...[
            const SizedBox(width: 8),
            _Tag(text: 'REC', color: c.busy),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: () => _toggle(_Panel.note),
            icon: Icon(
              p.noteOf(call.id).isEmpty
                  ? Icons.sticky_note_2_outlined
                  : Icons.sticky_note_2_rounded,
              size: 18,
            ),
            label: Text(tr('Note')),
          ),
          IconButton(
            tooltip: tr('Riduci'),
            onPressed: () => setState(() => _mode = _Mode.mini),
            icon: Icon(Icons.picture_in_picture_alt_outlined, color: c.text),
          ),
          IconButton(
            tooltip: full ? tr('Esci da schermo intero') : tr('Schermo intero'),
            onPressed: () =>
                setState(() => _mode = full ? _Mode.normal : _Mode.full),
            icon: Icon(
              full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              color: c.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _identity(CallEvent call, String name, bool outgoing) {
    final c = context.drin;
    return Container(
      color: c.ground,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Avatar(name: name.isNotEmpty ? name : call.remoteNumber, size: 104),
          const SizedBox(height: 18),
          Text(
            name.isNotEmpty ? name : call.remoteNumber,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(call.remoteNumber, style: mono(c.muted, size: 16)),
          ],
          const SizedBox(height: 8),
          Text(
            outgoing
                ? tr('Chiamata in corso…')
                : (call.phase == CallPhase.paused
                      ? tr('In attesa')
                      : _duration()),
            style: mono(c.muted, size: 14),
          ),
        ],
      ),
    );
  }

  /// Video remoto e, se attiva, l'anteprima della webcam in un angolo.
  Widget _video() => Stack(
    children: [
      Positioned.fill(
        child: NativeVideoView(
          label: tr('Video non disponibile su questa piattaforma'),
          onHandle: (h) => p.setVideoWindow(remote: h),
        ),
      ),
      if (p.settings.video.preview)
        Positioned(
          right: 12,
          bottom: 12,
          child: SizedBox(
            width: 200,
            height: 112,
            child: NativeVideoView(
              onHandle: (h) => p.setVideoWindow(preview: h),
            ),
          ),
        ),
    ],
  );

  Widget _toolbar(CallEvent call, bool outgoing) {
    final c = context.drin;
    final established = !outgoing;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      color: c.side,
      child: Row(
        children: [
          if (established) ...[
            _ToolButton(
              icon: Icons.add_call,
              label: tr('Nuova chiamata'),
              on: _panel == _Panel.newCall,
              onTap: () => _toggle(_Panel.newCall),
            ),
            _ToolButton(
              icon: Icons.group_add_outlined,
              label: tr('Aggiungi partecipante'),
              on: _panel == _Panel.participant,
              onTap: () => _toggle(_Panel.participant),
            ),
            if (p.canMergeConference)
              _ToolButton(
                icon: Icons.call_merge_rounded,
                label: tr('Unisci in conferenza'),
                on: true,
                onTap: p.mergeConference,
              ),
          ],
          const Spacer(),
          if (established && p.videoEnabled)
            _ToolButton(
              icon: call.video
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_outlined,
              label: tr('Video'),
              on: call.video,
              onTap: p.toggleCallVideo,
            ),
          _ToolButton(
            icon: p.muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
            label: p.muted ? tr('Riattiva') : tr('Muto'),
            on: p.muted,
            onTap: p.toggleMute,
          ),
          if (established) ...[
            _ToolButton(
              icon: Icons.pause_rounded,
              label: p.onHold ? tr('Riprendi') : tr('Attesa'),
              on: p.onHold,
              onTap: p.toggleHold,
            ),
            _ToolButton(
              icon: Icons.dialpad_rounded,
              label: tr('Tastiera'),
              on: _panel == _Panel.keypad,
              onTap: () => _toggle(_Panel.keypad),
            ),
            if (p.canRecord(call))
              _ToolButton(
                icon: Icons.fiber_manual_record_outlined,
                label: p.isRecording(call.id)
                    ? tr('Ferma registrazione')
                    : tr('Registra'),
                on: p.isRecording(call.id),
                onColor: c.busy,
                onTap: p.toggleRecording,
              ),
            _ToolButton(
              icon: Icons.phone_forwarded_rounded,
              label: tr('Trasferisci'),
              on: _panel == _Panel.transfer,
              onTap: () => _toggle(_Panel.transfer),
            ),
            if (p.canCompleteTransfer)
              _ToolButton(
                icon: Icons.call_split_rounded,
                label: tr('Completa trasferimento'),
                on: true,
                onTap: p.completeTransfer,
              ),
          ],
          const SizedBox(width: 12),
          _ToolButton(
            icon: Icons.call_end_rounded,
            label: tr('Termina'),
            on: true,
            onColor: DrinColors.hangupRed,
            onTap: () => p.hangup(call.id),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- pannelli laterali

  Widget _sidePanel(CallEvent call) {
    final c = context.drin;
    Widget title(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t,
              style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
            ),
          ),
          IconButton(
            tooltip: tr('Chiudi'),
            onPressed: () => setState(() => _panel = _Panel.none),
            icon: Icon(Icons.close_rounded, color: c.muted, size: 18),
          ),
        ],
      ),
    );
    return switch (_panel) {
      _Panel.keypad => Column(
        children: [
          title(tr('Tastiera')),
          Text(_dtmf.isEmpty ? ' ' : _dtmf, style: mono(c.text, size: 20)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Keypad(
              onKey: (d) {
                setState(() => _dtmf += d);
                p.sendDtmf(d);
              },
            ),
          ),
        ],
      ),
      _Panel.note => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title(tr('Note della chiamata')),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextFormField(
                key: ValueKey(('note', call.id)),
                initialValue: p.noteOf(call.id),
                autofocus: true,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (v) => p.setNote(call.id, v),
                decoration: InputDecoration(
                  hintText: tr('Salvate nel registro chiamate'),
                ),
              ),
            ),
          ),
        ],
      ),
      _Panel.transfer => _NumberPanel(
        key: const ValueKey('transfer'),
        phone: p,
        title: title(tr('Trasferisci chiamata')),
        actions: (number) => [
          // Assistito: prima si parla con il destinatario, poi si completa.
          OutlinedButton.icon(
            onPressed: () {
              p.consult(number);
              setState(() => _panel = _Panel.none);
            },
            icon: const Icon(Icons.record_voice_over_outlined, size: 18),
            label: Text(tr('Consulta prima')),
          ),
          FilledButton.icon(
            onPressed: () {
              p.transfer(number);
              setState(() => _panel = _Panel.none);
            },
            icon: const Icon(Icons.phone_forwarded_rounded, size: 18),
            label: Text(tr('Trasferisci subito')),
          ),
        ],
      ),
      _Panel.newCall || _Panel.participant => _NumberPanel(
        key: ValueKey(_panel),
        phone: p,
        title: title(
          _panel == _Panel.newCall
              ? tr('Nuova chiamata')
              : tr('Aggiungi partecipante'),
        ),
        hint: _panel == _Panel.participant
            ? tr(
                'La chiamata attuale va in attesa; quando l’altro risponde premi '
                '"Unisci in conferenza".',
              )
            : tr('La chiamata attuale va in attesa.'),
        actions: (number) => [
          FilledButton.icon(
            onPressed: () {
              p.newCall(number);
              setState(() => _panel = _Panel.none);
            },
            icon: const Icon(Icons.call_rounded, size: 18),
            label: Text(tr('Chiama')),
          ),
        ],
      ),
      _Panel.none => const SizedBox.shrink(),
    };
  }
}

/// Numero o ricerca (interni e rubrica) con le azioni in fondo.
class _NumberPanel extends StatefulWidget {
  const _NumberPanel({
    super.key,
    required this.phone,
    required this.title,
    required this.actions,
    this.hint = '',
  });
  final PhoneController phone;
  final Widget title;
  final List<Widget> Function(String number) actions;
  final String hint;

  @override
  State<_NumberPanel> createState() => _NumberPanelState();
}

class _NumberPanelState extends State<_NumberPanel> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final hits = widget.phone.search(_text.text, limit: 6);
    final number = _text.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.title,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _text,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: mono(c.text, size: 15),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: tr('Numero, interno o nome'),
            ),
          ),
        ),
        if (widget.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              widget.hint,
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final h in hits)
                ListTile(
                  dense: true,
                  title: Text(h.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(h.number, style: mono(c.muted, size: 12)),
                  onTap: () => setState(() => _text.text = h.number),
                ),
            ],
          ),
        ),
        if (number.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: widget.actions(number),
            ),
          ),
      ],
    );
  }
}

/// Un'altra chiamata (in attesa o in arrivo durante la conversazione).
class _OtherCall extends StatelessWidget {
  const _OtherCall({required this.phone, required this.call});
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
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: incoming ? c.ringing : c.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            incoming ? Icons.ring_volume_rounded : Icons.pause_circle_outline,
            size: 16,
            color: incoming ? c.ringing : c.muted,
          ),
          const SizedBox(width: 8),
          Text(
            name.isNotEmpty ? name : call.remoteNumber,
            style: TextStyle(color: c.text),
          ),
          const SizedBox(width: 6),
          Text(
            incoming ? tr('In arrivo') : tr('In attesa'),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          if (incoming)
            IconButton(
              tooltip: tr('Rispondi (la chiamata attuale va in attesa)'),
              onPressed: () => phone.answer(call.id),
              icon: const Icon(
                Icons.call_rounded,
                color: DrinColors.callGreen,
                size: 18,
              ),
            )
          else
            IconButton(
              tooltip: tr('Riprendi (scambia)'),
              onPressed: () => phone.resumeCall(call.id),
              icon: Icon(Icons.swap_calls_rounded, color: c.accent, size: 18),
            ),
          IconButton(
            tooltip: incoming ? tr('Rifiuta') : tr('Riaggancia'),
            onPressed: () => phone.hangup(call.id),
            icon: const Icon(
              Icons.call_end_rounded,
              color: DrinColors.hangupRed,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.avatar,
        border: Border.all(color: c.border, width: size > 60 ? 6 : 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w600,
          color: c.text,
        ),
      ),
    );
  }
}

/// Pulsante della barra comandi: icona tonda ed etichetta sotto.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.on = false,
    this.onColor,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool on;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final bg = on ? (onColor ?? c.accent) : c.keyBtn;
    final fg = on ? Colors.white : c.text;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 86,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, color: fg, size: 22),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.text, height: 1.15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    // Tutto il pulsante (cerchio ed etichetta) è cliccabile.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: c.text)),
          ],
        ),
      ),
    );
  }
}

/// Qualità della chiamata (0–5 da liblinphone) come tacche del segnale.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.quality});
  final double quality;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final bars = quality >= 4
        ? 4
        : quality >= 3
        ? 3
        : quality >= 2
        ? 2
        : quality >= 1
        ? 1
        : 0;
    final color = bars >= 3 ? c.ok : (bars == 2 ? c.ringing : c.busy);
    return Tooltip(
      message: tr('Qualità {q}/5', {'q': quality.toStringAsFixed(1)}),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 4,
              height: 6.0 + i * 4,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i < bars ? color : c.border,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
  );
}
