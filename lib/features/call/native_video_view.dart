import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/video_surface.dart';

/// Riquadro dove compare una finestra video permanente ([surface], creata dal
/// controller): la sposta sopra di sé a ogni frame e ogni 100 ms (gli
/// spostamenti della finestra dell'app non producono frame) e la nasconde
/// quando sparisce. Null = video non disponibile (si mostra [label]).
class VideoSlot extends StatefulWidget {
  const VideoSlot({super.key, required this.surface, this.label = ''});
  final VideoSurface? surface;
  final String label;

  @override
  State<VideoSlot> createState() => _VideoSlotState();
}

class _VideoSlotState extends State<VideoSlot> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _follow();
    _poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) _place();
    });
  }

  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _place();
      _follow();
    });
  }

  void _place() {
    final s = widget.surface;
    final box = context.findRenderObject() as RenderBox?;
    if (s == null || box == null || !box.hasSize) return;
    final dpr = View.of(context).devicePixelRatio;
    final r = box.localToGlobal(Offset.zero) & box.size;
    s.place(
      (r.left * dpr).round(),
      (r.top * dpr).round(),
      (r.width * dpr).round(),
      (r.height * dpr).round(),
    );
  }

  @override
  void didUpdateWidget(covariant VideoSlot old) {
    super.didUpdateWidget(old);
    if (old.surface != widget.surface) old.surface?.hide();
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.surface?.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: widget.surface == null && widget.label.isNotEmpty
        ? Center(
            child: Text(
              widget.label,
              style: const TextStyle(color: Colors.white70),
            ),
          )
        : const SizedBox.expand(),
  );
}
