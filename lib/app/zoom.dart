import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Ultimo punto premuto nella finestra (coordinate globali) e quando: la
/// finestra di chiamata che si apre subito dopo cresce da lì.
final lastPress = ValueNotifier<(Offset, DateTime)?>(null);

/// Zoom dell'interfaccia (desktop): `Ctrl` + `+` o rotella in su ingrandisce,
/// `Ctrl` + `−` o rotella in giù riduce, `Ctrl` + `0` torna al 100 %. Vale con
/// la finestra a fuoco, anche dentro un campo di testo. Mostra per un attimo
/// la percentuale.
class ZoomKeys extends StatefulWidget {
  const ZoomKeys({super.key, required this.onZoom, required this.child});

  /// Salva il nuovo zoom (già nei limiti di [DrinScale]).
  final ValueChanged<double> onZoom;
  final Widget child;

  @override
  State<ZoomKeys> createState() => _ZoomKeysState();
}

class _ZoomKeysState extends State<ZoomKeys> {
  bool _shown = false;
  Timer? _hide;
  DateTime _lastWheel = DateTime(0);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _hide?.cancel();
    super.dispose();
  }

  static bool get _ctrlOnly {
    final kb = HardwareKeyboard.instance;
    // AltGr su Windows arriva come Ctrl+Alt: non è una scorciatoia di zoom.
    return kb.isControlPressed && !kb.isAltPressed && !kb.isMetaPressed;
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    if (!_ctrlOnly) return false;
    final k = e.logicalKey;
    final label = k.keyLabel;
    final double? next;
    if (k == LogicalKeyboardKey.numpadAdd || label == '+' || label == '=') {
      next = appZoom.value + DrinScale.zoomStep;
    } else if (k == LogicalKeyboardKey.numpadSubtract || label == '-') {
      next = appZoom.value - DrinScale.zoomStep;
    } else if (k == LogicalKeyboardKey.numpad0 || label == '0') {
      next = 1.0;
    } else {
      return false;
    }
    _apply(next);
    return true;
  }

  // Con Ctrl premuto le liste rifiutano la rotella (_ZoomScrollBehavior),
  // quindi l'evento arriva qui senza far scorrere niente.
  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_ctrlOnly || e.scrollDelta.dy == 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      // Un passo per scatto: il touchpad manda raffiche di eventi piccoli.
      final now = DateTime.now();
      if (now.difference(_lastWheel) < const Duration(milliseconds: 80)) {
        return;
      }
      _lastWheel = now;
      final step = e.scrollDelta.dy < 0
          ? DrinScale.zoomStep
          : -DrinScale.zoomStep;
      _apply(appZoom.value + step);
    });
  }

  void _apply(double next) {
    widget.onZoom(DrinScale.clampZoom(next));
    _hide?.cancel();
    setState(() => _shown = true);
    _hide = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _shown = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Stack(
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: _onSignal,
          onPointerDown: (e) => lastPress.value = (e.position, DateTime.now()),
          child: ScrollConfiguration(
            behavior: const _ZoomScrollBehavior(),
            child: widget.child,
          ),
        ),
        Positioned(
          top: DrinSpace.s5,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: _shown ? 1 : 0,
                duration: DrinMotion.of(context, DrinMotion.base),
                curve: DrinMotion.curve,
                child: AnimatedSlide(
                  offset: _shown ? Offset.zero : const Offset(0, -0.25),
                  duration: DrinMotion.of(context, DrinMotion.base),
                  curve: DrinMotion.curve,
                  child: _Badge(colors: c),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.colors});
  final DrinColors colors;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: appZoom,
      builder: (_, z, _) => Material(
        // Sta sopra a tutto: ombra (DESIGN §3), bordo `line`, pillola.
        elevation: 6,
        color: colors.surface,
        shape: StadiumBorder(side: BorderSide(color: colors.line)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DrinSpace.s4,
            vertical: DrinSpace.s2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.zoom_in_rounded, size: 18, color: colors.muted),
              const SizedBox(width: DrinSpace.s2),
              Text(
                '${(z * 100).round()} %',
                style: DrinText.number.copyWith(color: colors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Come lo scorrimento Material, ma con Ctrl premuto le liste non accettano
/// la rotella: `Ctrl` + rotella è lo zoom, non deve anche scorrere.
class _ZoomScrollBehavior extends MaterialScrollBehavior {
  const _ZoomScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      _NoScrollWhileCtrl(parent: super.getScrollPhysics(context));
}

class _NoScrollWhileCtrl extends ScrollPhysics {
  const _NoScrollWhileCtrl({super.parent});

  @override
  _NoScrollWhileCtrl applyTo(ScrollPhysics? ancestor) =>
      _NoScrollWhileCtrl(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !_ZoomKeysState._ctrlOnly && super.shouldAcceptUserOffset(position);
}
