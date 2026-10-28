import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../call/keypad.dart';
import 'widgets.dart';

/// Campo "numero, interno o nome" con popup di risultati mentre si digita e
/// tastierino a comparsa, entrambi agganciati sotto il campo.
class SearchBox extends StatefulWidget {
  const SearchBox({super.key, required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  final _results = OverlayPortalController();
  final _keypad = OverlayPortalController();
  List<SearchHit> _hits = const [];
  int _selected = 0;

  static const _width = 420.0;
  static final _dialable = RegExp(r'^[0-9*#+]+$');

  PhoneController get p => widget.phone;
  String get _typed => _text.text.trim();
  bool get _offerNumber =>
      _dialable.hasMatch(_typed) && !_hits.any((h) => h.number == _typed);
  int get _rows => _hits.length + (_offerNumber ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _results.hide();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String v) {
    setState(() {
      _hits = p.search(v);
      _selected = 0;
    });
    _typed.isEmpty ? _results.hide() : _results.show();
  }

  void _call(String number) {
    widget.onCall(number);
    _text.clear();
    _changed('');
    _keypad.hide();
  }

  void _activate(int i) {
    if (_offerNumber) {
      if (i == 0) return _call(_typed);
      i--;
    }
    if (i < _hits.length) {
      final h = _hits[i];
      if (h.extension == null || p.isCallable(h.extension!)) _call(h.number);
    }
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _results.hide();
      _keypad.hide();
      return KeyEventResult.handled;
    }
    if (_rows == 0) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1) % _rows);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1 + _rows) % _rows);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _popup(DrinColors c, Widget child) => Positioned(
    width: _width,
    child: CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.bottomLeft,
      offset: const Offset(0, 8),
      child: Material(
        color: c.surface,
        elevation: 12,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(8),
          child: child,
        ),
      ),
    ),
  );

  Widget _row(
    DrinColors c,
    int index,
    Widget leading,
    String title,
    String sub, {
    bool enabled = true,
  }) {
    final on = index == _selected;
    return Material(
      color: on ? c.keyBtn : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? () => _activate(index) : null,
        onHover: (h) {
          if (h) setState(() => _selected = index);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: enabled ? c.text : c.muted,
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.call_rounded,
                size: 18,
                color: enabled ? c.accent : c.border,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultsList(DrinColors c) {
    final rows = <Widget>[];
    var i = 0;
    if (_offerNumber) {
      rows.add(
        _row(
          c,
          i++,
          CircleAvatar(
            radius: 20,
            backgroundColor: c.keyBtn,
            child: Icon(Icons.dialpad_rounded, size: 18, color: c.accent),
          ),
          tr('Chiama {n}', {'n': _typed}),
          tr('Numero digitato'),
        ),
      );
    }
    for (final h in _hits) {
      final e = h.extension;
      rows.add(
        e != null
            ? _row(
                c,
                i++,
                StatusAvatar(
                  name: e.name,
                  blf: p.isCallable(e) ? p.blf[e.number]?.status : null,
                  presence: p.presenceOf(e),
                ),
                e.name,
                '${tr('Interno')} ${e.number}',
                enabled: p.isCallable(e),
              )
            : _row(
                c,
                i++,
                StatusAvatar(name: h.name),
                h.name,
                '${h.label} · ${h.number}',
              ),
      );
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(tr('Nessun risultato'), style: TextStyle(color: c.muted)),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return OverlayPortal(
      controller: _keypad,
      overlayChildBuilder: (_) => _popup(
        c,
        SizedBox(
          width: 300,
          child: Keypad(
            onKey: (d) {
              _text.text += d;
              _changed(_text.text);
              _focus.requestFocus();
            },
          ),
        ),
      ),
      child: OverlayPortal(
        controller: _results,
        overlayChildBuilder: (_) => _popup(c, _resultsList(c)),
        child: CompositedTransformTarget(
          link: _link,
          child: Container(
            width: _width,
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: c.field,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 18, color: c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Focus(
                    onKeyEvent: _key,
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      onChanged: _changed,
                      onTap: () {
                        if (_typed.isNotEmpty) _results.show();
                      },
                      onSubmitted: (_) {
                        _activate(_selected);
                        _focus.requestFocus();
                      },
                      style: mono(c.text, size: 15),
                      decoration: InputDecoration(
                        hintText: tr('Numero, interno o nome'),
                        // Il segnaposto non eredita il monospazio del testo digitato.
                        hintStyle: TextStyle(
                          fontFamily: 'Segoe UI Variable Text',
                          fontFamilyFallback: const ['Segoe UI'],
                          fontSize: 14,
                          color: c.muted,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr('Tastierino'),
                  style: IconButton.styleFrom(
                    backgroundColor: c.keyBtn,
                    foregroundColor: c.accent,
                  ),
                  onPressed: _keypad.toggle,
                  icon: const Icon(Icons.dialpad_rounded, size: 18),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: tr('Chiama'),
                  style: IconButton.styleFrom(
                    backgroundColor: DrinColors.callGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: c.keyBtn,
                  ),
                  onPressed: p.canDial && _rows > 0
                      ? () => _activate(_selected)
                      : null,
                  icon: const Icon(Icons.call_rounded, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
