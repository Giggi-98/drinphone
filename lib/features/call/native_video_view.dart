import 'package:flutter/material.dart';

import '../../core/platform/video_surface.dart';

/// Riquadro dove liblinphone disegna il video: una finestra nativa tenuta
/// sopra questo widget a ogni frame. [onHandle] riceve l'HWND (0 alla chiusura).
class NativeVideoView extends StatefulWidget {
  const NativeVideoView({super.key, required this.onHandle, this.label = ''});
  final void Function(int handle) onHandle;

  /// Testo mostrato dove la finestra nativa non c'è (fuori da Windows).
  final String label;

  @override
  State<NativeVideoView> createState() => _NativeVideoViewState();
}

class _NativeVideoViewState extends State<NativeVideoView> {
  VideoSurface? _surface;
  Rect? _placed;

  @override
  void initState() {
    super.initState();
    _surface = VideoSurface.create();
    final s = _surface;
    if (s != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onHandle(s.handle);
      });
    }
    _follow();
  }

  /// Dopo ogni frame: la finestra nativa segue posizione e dimensioni.
  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _place();
      _follow();
    });
  }

  void _place() {
    final s = _surface;
    final box = context.findRenderObject() as RenderBox?;
    if (s == null || box == null || !box.hasSize) return;
    final dpr = View.of(context).devicePixelRatio;
    final r = (box.localToGlobal(Offset.zero) & box.size);
    final px = Rect.fromLTRB(
      (r.left * dpr).roundToDouble(),
      (r.top * dpr).roundToDouble(),
      (r.right * dpr).roundToDouble(),
      (r.bottom * dpr).roundToDouble(),
    );
    if (px == _placed) return;
    _placed = px;
    s.place(
      px.left.toInt(),
      px.top.toInt(),
      px.width.toInt(),
      px.height.toInt(),
    );
  }

  @override
  void dispose() {
    final s = _surface;
    if (s != null) {
      widget.onHandle(0);
      s.destroy();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: _surface == null && widget.label.isNotEmpty
        ? Center(
            child: Text(
              widget.label,
              style: const TextStyle(color: Colors.white70),
            ),
          )
        : const SizedBox.expand(),
  );
}
