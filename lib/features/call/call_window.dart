import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../app/zoom.dart' show lastPress;
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

enum _Panel { none, keypad, transfer, newCall, participant, note, stats }

class _CallWindowState extends State<CallWindow> {
  Timer? _tick;
  _Mode _mode = _Mode.normal;
  _Panel _panel = _Panel.none;
  String _dtmf = '';
  int? _callId;
  bool _wasVideo = false;

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
    // Chiamata nuova: si riparte dalla finestra normale, senza pannelli
    // (prima della chiave della forma, che dipende da _mode).
    if (call != null && _callId != call.id) {
      _callId = call.id;
      _panel = _Panel.none;
      _dtmf = '';
      if (_mode == _Mode.full) _mode = _Mode.normal;
    }
    final isVideo =
        call != null &&
        call.video &&
        (call.phase == CallPhase.active ||
            call.phase == CallPhase.paused ||
            (call.phase == CallPhase.incoming &&
                call.earlyMedia &&
                p.videoEnabled));
    if (isVideo && !_wasVideo) {
      // Le finestre native MSOGL coprono i popup Flutter: chiudi eventuali menu.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.maybeOf(context)?.popUntil((r) => r is! PopupRoute);
      });
    }
    _wasVideo = isVideo;
    // Comparsa, cambio di forma (normale, ridotta, schermo intero) e chiusura
    // animati: la finestra uscente si dissolve mentre entra la nuova.
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: DrinMotion.of(context, DrinMotion.wide),
        switchInCurve: DrinMotion.emphasized,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(anim),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) =>
            Stack(children: [...previous, ?current]),
        child: call == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : Stack(
                key: ValueKey(
                  call.phase == CallPhase.incoming ? 'incoming' : _mode,
                ),
                children: [_content(call)],
              ),
      ),
    );
  }

  /// Punto da cui far crescere la finestra: il clic che ha avviato la
  /// chiamata, se recente; altrimenti il centro.
  Alignment _origin() {
    final press = lastPress.value;
    final box = context.findRenderObject() as RenderBox?;
    if (press == null ||
        box == null ||
        !box.hasSize ||
        DateTime.now().difference(press.$2) > const Duration(seconds: 2)) {
      return Alignment.center;
    }
    final at = box.globalToLocal(press.$1);
    final s = box.size;
    return Alignment(
      (at.dx / s.width * 2 - 1).clamp(-1.0, 1.0),
      (at.dy / s.height * 2 - 1).clamp(-1.0, 1.0),
    );
  }

  Widget _content(CallEvent call) {
    if (call.phase == CallPhase.incoming) {
      return Positioned(right: 24, bottom: 24, child: _incoming(call));
    }
    if (_mode == _Mode.mini) {
      return Positioned(right: 24, bottom: 24, child: _mini(call));
    }
    final full = _mode == _Mode.full;
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: full ? 0.88 : 0.54),
        ),
        child: _Grow(
          // Una volta per chiamata: dal punto premuto alla finestra intera.
          key: ValueKey(('grow', call.id)),
          from: _origin(),
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
        ),
      ),
    );
  }

  // ------------------------------------------------------------- in arrivo

  Widget _incoming(CallEvent call) {
    final c = context.drin;
    final name = _nameOf(call);
    final showPreview = call.earlyMedia && call.video && p.videoEnabled;
    // Il momento del marchio (DESIGN.md §6): avatar che oscilla come un
    // campanello, onde e "!" del logo in squilloLine. Con Auto Preview
    // (videocitofono in early media) compare subito il riquadro video live.
    return _Entrance(
      child: Material(
        color: c.surface,
        elevation: 12,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(DrinRadius.sheet),
        child: Container(
          width: showPreview ? 420 : 380,
          padding: const EdgeInsets.fromLTRB(
            DrinSpace.s5,
            DrinSpace.s4,
            DrinSpace.s5,
            DrinSpace.s5,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DrinRadius.sheet),
            border: Border.all(color: c.squilloLine, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      call.remoteVideo
                          ? tr('Videochiamata in arrivo')
                          : tr('Chiamata in arrivo'),
                      style: DrinText.label.copyWith(color: c.muted),
                    ),
                  ),
                  if (showPreview) ...[
                    _Tag(text: tr('Auto Preview'), color: c.primary),
                    const SizedBox(width: DrinSpace.s2),
                  ],
                  _Bang(color: c.squilloLine),
                ],
              ),
              const SizedBox(height: DrinSpace.s3),
              if (showPreview)
                ClipRRect(
                  borderRadius: BorderRadius.circular(DrinRadius.panel),
                  child: SizedBox(
                    height: 210,
                    width: double.infinity,
                    child: VideoSlot(
                      surface: p.remoteSurface,
                      label: tr('Anteprima video in arrivo'),
                    ),
                  ),
                )
              else
                // Niente anteprima webcam locale durante lo squillo:
                // la webcam si avvia solo dopo la risposta.
                _RingingAvatar(
                  name: name.isNotEmpty ? name : call.remoteNumber,
                ),
              const SizedBox(height: DrinSpace.s3),
              Text(
                name.isNotEmpty ? name : call.remoteNumber,
                overflow: TextOverflow.ellipsis,
                style: (showPreview ? DrinText.title : DrinText.displayStyle)
                    .copyWith(color: c.ink),
              ),
              if (name.isNotEmpty)
                Text(
                  call.remoteNumber,
                  style: DrinText.numberLarge.copyWith(color: c.muted),
                ),
              _CallerContextStrip(phone: p, call: call, name: name, compact: true),
              const SizedBox(height: DrinSpace.s5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundButton(
                    icon: Icons.call_end_rounded,
                    label: tr('Rifiuta'),
                    color: context.drin.busy,
                    onTap: () => p.hangup(call.id),
                  ),
                  if (call.remoteVideo && p.videoEnabled)
                    _RoundButton(
                      icon: Icons.videocam_rounded,
                      label: tr('Rispondi in video'),
                      color: context.drin.free,
                      onTap: () => p.answer(call.id, true),
                    ),
                  _RoundButton(
                    icon: Icons.call_rounded,
                    label: tr('Rispondi'),
                    color: context.drin.free,
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
                backgroundColor: context.drin.busy,
                foregroundColor: context.drin.onBusy,
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
      elevation: full ? 0 : 20,
      shadowColor: Colors.black87,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(full ? 0 : DrinRadius.sheet),
        side: full ? BorderSide.none : BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(call, name, full),
          _CallerContextStrip(phone: p, call: call, name: name),
          if (p.otherCalls.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              color: c.raised,
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
                      color: c.raised,
                      border: Border(left: BorderSide(color: c.line)),
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
    final metrics = p.callAudioMetrics(call.id);
    final quality = metrics != null && metrics.quality >= 0
        ? metrics.quality
        : p.callQuality(call.id);
    final status = switch (call.phase) {
      CallPhase.outgoing => tr('Chiamata in corso…'),
      CallPhase.paused => tr('In attesa'),
      _ => _duration(),
    };
    final statusColor = call.phase == CallPhase.paused
        ? c.away
        : call.phase == CallPhase.outgoing
        ? c.primary
        : c.free;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        DrinSpace.s5,
        DrinSpace.s3,
        DrinSpace.s3,
        DrinSpace.s3,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              name.isNotEmpty ? name : call.remoteNumber,
              overflow: TextOverflow.ellipsis,
              style: DrinText.heading.copyWith(color: c.ink),
            ),
          ),
          if (name.isNotEmpty) ...[
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: DrinSpace.s3),
              color: c.line,
            ),
            Text(call.remoteNumber, style: DrinText.number.copyWith(color: c.muted)),
          ],
          const SizedBox(width: DrinSpace.s3),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DrinSpace.s3,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(DrinRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  status,
                  style: DrinText.number.copyWith(color: c.ink),
                ),
              ],
            ),
          ),
          if (quality >= 0) ...[
            const SizedBox(width: DrinSpace.s3),
            InkWell(
              borderRadius: BorderRadius.circular(DrinRadius.control),
              onTap: () => _toggle(_Panel.stats),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: _SignalBars(quality: quality, metrics: metrics),
              ),
            ),
          ],
          if (metrics != null &&
              ((metrics.lossPct ?? 0) > 2.0 || (metrics.jitterMs ?? 0) > 40.0)) ...[
            const SizedBox(width: DrinSpace.s2),
            Tooltip(
              message: tr('Qualità audio degradata · clicca sulle tacche per i dettagli'),
              child: InkWell(
                borderRadius: BorderRadius.circular(DrinRadius.pill),
                onTap: () => _toggle(_Panel.stats),
                child: _Tag(text: tr('Rete instabile'), color: c.squilloLine),
              ),
            ),
          ],
          if (metrics != null && metrics.codec.isNotEmpty) ...[
            const SizedBox(width: DrinSpace.s2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: c.raised,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(DrinRadius.pill),
              ),
              child: Text(
                metrics.codec,
                style: DrinText.label.copyWith(color: c.ink),
              ),
            ),
          ],
          if (call.inConference) ...[
            const SizedBox(width: DrinSpace.s2),
            _Tag(text: tr('Conferenza'), color: c.primary),
          ],
          if (p.isRecording(call.id)) ...[
            const SizedBox(width: DrinSpace.s2),
            _Tag(text: 'REC', color: c.busy),
          ],
          const Spacer(),
          if (p.screenPopUriFor(call.remoteNumber, name: name) != null)
            Padding(
              padding: const EdgeInsets.only(right: DrinSpace.s2),
              child: OutlinedButton.icon(
                onPressed: () => p.openScreenPop(call.remoteNumber, name: name),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(tr('Apri CRM')),
              ),
            ),
          OutlinedButton.icon(
            style: _panel == _Panel.note || p.noteOf(call.id).isNotEmpty
                ? OutlinedButton.styleFrom(
                    backgroundColor: c.primary.withValues(alpha: 0.14),
                    side: BorderSide(color: c.primary),
                  )
                : null,
            onPressed: () => _toggle(_Panel.note),
            icon: Icon(
              p.noteOf(call.id).isEmpty
                  ? Icons.sticky_note_2_outlined
                  : Icons.sticky_note_2_rounded,
              size: 16,
            ),
            label: Text(tr('Note')),
          ),
          const SizedBox(width: DrinSpace.s2),
          IconButton(
            tooltip: tr('Riduci'),
            onPressed: () => setState(() => _mode = _Mode.mini),
            icon: Icon(Icons.picture_in_picture_alt_outlined, color: c.ink),
          ),
          IconButton(
            tooltip: full ? tr('Esci da schermo intero') : tr('Schermo intero'),
            onPressed: () =>
                setState(() => _mode = full ? _Mode.normal : _Mode.full),
            icon: Icon(
              full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _identity(CallEvent call, String name, bool outgoing) {
    final c = context.drin;
    final paused = call.phase == CallPhase.paused;
    final stateColor = outgoing
        ? c.primary
        : paused
        ? c.away
        : c.free;
    final stateText = outgoing
        ? tr('Chiamata in corso…')
        : paused
        ? tr('In attesa')
        : _duration();
    return Container(
      color: c.ground,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(DrinSpace.s5),
      child: Container(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 460),
        padding: const EdgeInsets.symmetric(
          horizontal: DrinSpace.s6,
          vertical: DrinSpace.s5,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(DrinRadius.sheet),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: stateColor.withValues(alpha: 0.14),
                border: Border.all(
                  color: stateColor.withValues(alpha: 0.45),
                  width: 2,
                ),
              ),
              child: _Avatar(
                name: name.isNotEmpty ? name : call.remoteNumber,
                size: 104,
              ),
            ),
            const SizedBox(height: DrinSpace.s4),
            Text(
              name.isNotEmpty ? name : call.remoteNumber,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DrinText.displayStyle.copyWith(color: c.ink),
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(height: DrinSpace.s1),
              Text(
                call.remoteNumber,
                style: DrinText.numberLarge.copyWith(color: c.muted),
              ),
            ],
            const SizedBox(height: DrinSpace.s4),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DrinSpace.s4,
                vertical: DrinSpace.s2,
              ),
              decoration: BoxDecoration(
                color: stateColor.withValues(alpha: 0.14),
                border: Border.all(color: stateColor.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(DrinRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    paused
                        ? Icons.pause_rounded
                        : outgoing
                        ? Icons.ring_volume_rounded
                        : Icons.call_rounded,
                    size: 16,
                    color: paused
                        ? c.ink
                        : outgoing
                        ? c.primary
                        : c.freeText,
                  ),
                  const SizedBox(width: DrinSpace.s2),
                  Text(
                    stateText,
                    style: (outgoing || paused ? DrinText.label : DrinText.numberLarge)
                        .copyWith(
                          color: paused
                              ? c.ink
                              : outgoing
                              ? c.primary
                              : c.freeText,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Video remoto e, se attiva, l'anteprima della webcam in un angolo.
  Widget _video() => Stack(
    children: [
      Positioned.fill(
        child: VideoSlot(
          surface: p.remoteSurface,
          label: tr('Video non disponibile su questa piattaforma'),
        ),
      ),
      if (p.settings.video.preview)
        Positioned(
          right: 12,
          bottom: 12,
          child: SizedBox(
            width: 200,
            height: 112,
            child: VideoSlot(surface: p.previewSurface),
          ),
        ),
    ],
  );

  Widget _toolbar(CallEvent call, bool outgoing) {
    final c = context.drin;
    final established = !outgoing;
    final divider = Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: DrinSpace.s2),
      color: c.line,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(
        DrinSpace.s3,
        DrinSpace.s3,
        DrinSpace.s3,
        DrinSpace.s3,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
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
          divider,
          _ToolButton(
            icon: Icons.call_end_rounded,
            label: tr('Termina'),
            on: true,
            onColor: c.busy,
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
      _Panel.stats => _statsPanel(call, title(tr('Qualità rete (QoS)'))),
      _Panel.none => const SizedBox.shrink(),
    };
  }

  Widget _statsPanel(CallEvent call, Widget header) {
    final c = context.drin;
    final m = p.callAudioMetrics(call.id);
    final hist = p.callAudioHistory(call.id);
    Widget statRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: DrinSpace.s1),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: DrinText.detail.copyWith(color: c.muted)),
          ),
          Text(value, style: DrinText.number.copyWith(color: c.ink)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              DrinSpace.s4,
              0,
              DrinSpace.s4,
              DrinSpace.s4,
            ),
            children: [
              Container(
                padding: const EdgeInsets.all(DrinSpace.s3),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(DrinRadius.row),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    statRow(
                      tr('Qualità'),
                      m != null && m.quality >= 0
                          ? '${m.quality.toStringAsFixed(1)} / 5'
                          : '—',
                    ),
                    statRow(
                      'Codec',
                      m != null && m.codec.isNotEmpty ? m.codec : '—',
                    ),
                    statRow(
                      tr('Banda RX / TX'),
                      m == null
                          ? '—'
                          : '↓ ${m.downloadKbps?.toStringAsFixed(0) ?? '-'} · ↑ ${m.uploadKbps?.toStringAsFixed(0) ?? '-'} kbps',
                    ),
                    statRow(
                      'Jitter',
                      m?.jitterMs != null
                          ? '${m!.jitterMs!.toStringAsFixed(1)} ms'
                          : '—',
                    ),
                    statRow(
                      tr('Perdita pacchetti'),
                      m?.lossPct != null
                          ? '${m!.lossPct!.toStringAsFixed(1)} %'
                          : '—',
                    ),
                    statRow(
                      'RTT',
                      m?.rttMs != null ? '${m!.rttMs!.toStringAsFixed(0)} ms' : '—',
                    ),
                  ],
                ),
              ),
              if (hist.isNotEmpty) ...[
                const SizedBox(height: DrinSpace.s4),
                Text(
                  tr('Andamento qualità (ultimi {n} s)', {'n': hist.length}),
                  style: DrinText.label.copyWith(color: c.muted),
                ),
                const SizedBox(height: DrinSpace.s2),
                Container(
                  height: 64,
                  padding: const EdgeInsets.all(DrinSpace.s2),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(DrinRadius.row),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final sample in hist)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            height: ((sample.quality.clamp(0.5, 5.0)) / 5.0) * 44,
                            decoration: BoxDecoration(
                              color: sample.quality >= 3.5
                                  ? c.free
                                  : sample.quality >= 2.2
                                  ? c.squillo
                                  : c.busy,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
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
              icon: Icon(
                Icons.call_rounded,
                color: context.drin.free,
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
            icon: Icon(
              Icons.call_end_rounded,
              color: context.drin.busy,
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
        color: c.panel,
        border: Border.all(color: c.line, width: size > 60 ? 3 : 2),
      ),
      alignment: Alignment.center,
      child: initialsOrIcon(
        name,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w600,
          color: c.ink,
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
    final bg = on ? (onColor ?? c.primary) : c.panel;
    final fg = on ? (onColor == c.busy ? c.onBusy : c.onPrimary) : c.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DrinSpace.s1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DrinRadius.row),
        child: SizedBox(
          width: 86,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DrinSpace.s1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: on ? null : Border.all(color: c.line),
                  ),
                  child: Icon(icon, color: fg, size: 22),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: DrinText.label.copyWith(
                    color: on ? c.ink : c.muted,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatefulWidget {
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
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    // Icona col suo "on" (DESIGN.md §1): nel tema scuro scura su verde/rosso.
    final fg = widget.color == c.busy
        ? c.onBusy
        : widget.color == c.free
        ? c.onFree
        : c.onPrimary;
    // Tutto il pulsante (cerchio ed etichetta) è cliccabile; alla pressione
    // il cerchio si stringe e torna con una piccola molla.
    return InkWell(
      onTap: widget.onTap,
      onHighlightChanged: (v) => setState(() => _down = v),
      borderRadius: BorderRadius.circular(DrinRadius.panel),
      child: Padding(
        padding: const EdgeInsets.all(DrinSpace.s1 + 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _down ? 0.9 : 1,
              duration: DrinMotion.of(context, DrinMotion.fast),
              curve: _down ? DrinMotion.curve : Curves.elasticOut,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: fg, size: 26),
              ),
            ),
            const SizedBox(height: DrinSpace.s1 + 2),
            Text(widget.label, style: DrinText.label.copyWith(color: c.ink)),
          ],
        ),
      ),
    );
  }
}

/// La finestra di chiamata cresce dal punto [from] (scala 0,2 → 1 e
/// dissolvenza, [DrinMotion.wide]); niente con "riduci movimento".
class _Grow extends StatelessWidget {
  const _Grow({super.key, required this.from, required this.child});
  final Alignment from;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: DrinMotion.of(context, DrinMotion.wide),
    curve: DrinMotion.emphasized,
    builder: (context, t, child) => Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.2 + 0.8 * t,
        alignment: from,
        child: child,
      ),
    ),
    child: child,
  );
}

/// Comparsa della scheda in arrivo: dissolvenza e 4 px di salita ([DrinMotion.wide]).
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: DrinMotion.of(context, DrinMotion.wide),
    curve: DrinMotion.emphasized,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 4 * (1 - t)), child: child),
    ),
    child: child,
  );
}

/// Avatar che squilla: oscillazione da campanello e due onde (DESIGN.md §5).
class _RingingAvatar extends StatefulWidget {
  const _RingingAvatar({required this.name});
  final String name;

  @override
  State<_RingingAvatar> createState() => _RingingAvatarState();
}

class _RingingAvatarState extends State<_RingingAvatar>
    with TickerProviderStateMixin {
  late final _bell = AnimationController(
    vsync: this,
    duration: DrinMotion.ring,
  );
  late final _wave = AnimationController(
    vsync: this,
    duration: DrinMotion.wave,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (DrinMotion.reduced(context)) {
      _bell.stop();
      _wave.stop();
    } else {
      if (!_bell.isAnimating) _bell.repeat();
      if (!_wave.isAnimating) _wave.repeat();
    }
  }

  @override
  void dispose() {
    _bell.dispose();
    _wave.dispose();
    super.dispose();
  }

  /// Colpi del campanello nella prima metà del ciclo, smorzati; poi fermo.
  static double _angle(double t) {
    if (t >= 0.5) return 0;
    const peaks = [-9.0, 8.0, -6.0, 4.0, 0.0];
    final x = t / 0.1;
    final i = x.floor().clamp(0, 4);
    final from = i == 0 ? 0.0 : peaks[i - 1];
    final k = Curves.easeInOut.transform(x - i);
    return (from + (peaks[i] - from) * k) * 3.14159265 / 180;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    const size = 80.0;
    return SizedBox(
      width: size * 1.9,
      height: size * 1.9,
      child: AnimatedBuilder(
        animation: Listenable.merge([_bell, _wave]),
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            for (final shift in const [0.0, 0.5])
              if (_wave.isAnimating)
                Builder(
                  builder: (context) {
                    final t = (_wave.value + shift) % 1;
                    final k = Curves.easeOut.transform(t);
                    return Container(
                      width: size * (1 + 0.9 * k),
                      height: size * (1 + 0.9 * k),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c.squilloLine.withValues(alpha: 0.9 * (1 - k)),
                          width: 3,
                        ),
                      ),
                    );
                  },
                ),
            Transform.rotate(angle: _angle(_bell.value), child: child),
          ],
        ),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
          child: initialsOrIcon(
            widget.name,
            style: DrinText.displayStyle.copyWith(
              fontSize: 26,
              color: c.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Il "!" del logo che compare a ritmo di squillo.
class _Bang extends StatefulWidget {
  const _Bang({required this.color});
  final Color color;

  @override
  State<_Bang> createState() => _BangState();
}

class _BangState extends State<_Bang> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: DrinMotion.ring);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (DrinMotion.reduced(context)) {
      _c.value = 0.45;
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      final t = _c.value;
      // Su 0.3-0.6, giù altrove.
      final v = t < 0.3
          ? Curves.easeOut.transform(t / 0.3)
          : t < 0.6
          ? 1.0
          : 1 - Curves.easeIn.transform((t - 0.6) / 0.4);
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 4 * (1 - v)),
          child: Transform.scale(scale: 0.8 + 0.2 * v, child: child),
        ),
      );
    },
    child: Text(
      '!',
      style: DrinText.displayStyle.copyWith(fontSize: 30, color: widget.color),
    ),
  );
}

/// Qualità della chiamata (0–5 da liblinphone) come tacche del segnale + QoS.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.quality, this.metrics});
  final double quality;
  final CallAudioMetrics? metrics;

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
    final color = bars >= 3 ? c.ok : (bars == 2 ? c.away : c.busy);
    final parts = <String>[
      tr('Qualità {q}/5', {'q': quality.toStringAsFixed(1)}),
      if (metrics != null) ...[
        if (metrics!.codec.isNotEmpty) 'Codec: ${metrics!.codec}',
        if (metrics!.downloadKbps != null || metrics!.uploadKbps != null)
          '↓ ${metrics!.downloadKbps?.toStringAsFixed(0) ?? '-'} ↑ ${metrics!.uploadKbps?.toStringAsFixed(0) ?? '-'} kbps',
        if (metrics!.jitterMs != null)
          'Jitter: ${metrics!.jitterMs!.toStringAsFixed(0)} ms',
        if (metrics!.lossPct != null)
          '${tr('Perdita')}: ${metrics!.lossPct!.toStringAsFixed(1)}%',
        if (metrics!.rttMs != null)
          'RTT: ${metrics!.rttMs!.toStringAsFixed(0)} ms',
      ],
    ];
    return Tooltip(
      message: parts.join(' · '),
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

class _CallerContextStrip extends StatelessWidget {
  const _CallerContextStrip({
    required this.phone,
    required this.call,
    required this.name,
    this.compact = false,
  });

  final PhoneController phone;
  final CallEvent call;
  final String name;
  final bool compact;

  static String _when(DateTime dt) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(dt.hour)}:${two(dt.minute)}';
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${tr('Oggi')} $hm';
    }
    return '${two(dt.day)}/${two(dt.month)} $hm';
  }

  static String _dur(int s) =>
      s >= 60 ? '${s ~/ 60}m ${s % 60}s' : '${s}s';

  @override
  Widget build(BuildContext context) {
    final ctx = phone.callerContext(call.remoteNumber);
    final hasCrm = phone.screenPopUriFor(call.remoteNumber, name: name) != null;
    if (!ctx.hasInfo && !(compact && hasCrm)) return const SizedBox.shrink();
    final c = context.drin;
    final last = ctx.lastCall;
    final lastLabel = last == null
        ? ''
        : last.answered
        ? '${tr('Ultima chiamata')}: ${_when(last.start)} (${_dur(last.seconds)})'
        : last.missed
        ? '${tr('Ultima chiamata')}: ${_when(last.start)} · ${tr('Persa')}'
        : '${tr('Ultima chiamata')}: ${_when(last.start)} · ${tr('Non risposta')}';

    final pills = <Widget>[
      if (ctx.todayCalls > 0)
        _Tag(
          text: ctx.todayCalls == 1
              ? tr('Già 1 chiamata oggi')
              : tr('{n} chiamate oggi', {'n': ctx.todayCalls}),
          color: c.primary,
        ),
      if (lastLabel.isNotEmpty)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 14, color: c.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                lastLabel,
                overflow: TextOverflow.ellipsis,
                style: DrinText.detail.copyWith(color: c.ink),
              ),
            ),
          ],
        ),
      if (ctx.lastNote.isNotEmpty)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sticky_note_2_outlined, size: 14, color: c.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                ctx.lastNote,
                overflow: TextOverflow.ellipsis,
                maxLines: compact ? 2 : 1,
                style: DrinText.detail.copyWith(color: c.ink),
              ),
            ),
          ],
        ),
      if (ctx.activeReminder != null)
        _Tag(text: tr('Promemoria attivo'), color: c.away),
      if (compact && hasCrm)
        OutlinedButton.icon(
          onPressed: () => phone.openScreenPop(call.remoteNumber, name: name),
          icon: const Icon(Icons.open_in_new_rounded, size: 15),
          label: Text(tr('Apri CRM')),
        ),
    ];

    if (compact) {
      return Container(
        margin: const EdgeInsets.only(top: DrinSpace.s3),
        width: double.infinity,
        padding: const EdgeInsets.all(DrinSpace.s3),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(DrinRadius.row),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < pills.length; i++) ...[
              if (i > 0) const SizedBox(height: DrinSpace.s1),
              pills[i],
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DrinSpace.s5,
        vertical: DrinSpace.s2,
      ),
      decoration: BoxDecoration(
        color: c.raised,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Wrap(
        spacing: DrinSpace.s3,
        runSpacing: DrinSpace.s1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: pills,
      ),
    );
  }
}
