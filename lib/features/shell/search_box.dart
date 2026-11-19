import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/call_history.dart';
import '../../core/security/settings_store.dart' show Extension;
import '../../core/sip/sip_engine.dart' show CallDirection;
import '../call/keypad.dart';
import 'widgets.dart';

/// Campo "numero, interno o nome" con popup di risultati mentre si digita,
/// comandi rapidi (`>` / `/`) e tastierino a comparsa agganciati sotto il campo.
class SearchBox extends StatefulWidget {
  const SearchBox({
    super.key,
    required this.phone,
    required this.onCall,
    this.onVideoCall,
    this.onOpenMiniHud,
    this.onOpenPreferences,
    this.onSetPresence,
    this.focusNode,
  });
  final PhoneController phone;
  final ValueChanged<String> onCall;
  final ValueChanged<String>? onVideoCall;
  final VoidCallback? onOpenMiniHud;
  final VoidCallback? onOpenPreferences;
  final ValueChanged<String>? onSetPresence;

  /// Fuoco dall'esterno (Ctrl+K); se assente il campo ne crea uno suo.
  final FocusNode? focusNode;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _PaletteCmd {
  const _PaletteCmd(this.icon, this.title, this.subtitle, this.run);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback run;
}

class _SearchBoxState extends State<SearchBox> {
  final _text = TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  final _link = LayerLink();
  final _results = OverlayPortalController();
  final _keypad = OverlayPortalController();
  List<SearchHit> _hits = const [];
  int _selected = 0;

  static const _width = 420.0;
  static final _dialable = RegExp(r'^[0-9*#+]+$');

  PhoneController get p => widget.phone;
  String get _typed => _text.text.trim();
  bool get _isCommand => _typed.startsWith('>') || _typed.startsWith('/');
  bool get _offerNumber =>
      !_isCommand &&
      _dialable.hasMatch(_typed) &&
      !_hits.any((h) => h.number == _typed);

  List<_PaletteCmd> get _commands {
    if (!_isCommand) return const [];
    final raw = _typed.substring(1).trim().toLowerCase();
    final all = <_PaletteCmd>[
      if (p.isYeastar && p.ownDetail != null && widget.onSetPresence != null) ...[
        _PaletteCmd(
          Icons.check_circle_rounded,
          tr('Disponibile'),
          '> disponibile',
          () => widget.onSetPresence!('available'),
        ),
        _PaletteCmd(
          Icons.do_not_disturb_on_rounded,
          tr('Non disturbare'),
          '> dnd',
          () => widget.onSetPresence!('do_not_disturb'),
        ),
        _PaletteCmd(
          Icons.schedule_rounded,
          tr('Assente'),
          '> assente',
          () => widget.onSetPresence!('away'),
        ),
      ],
      if (p.isYeastar && (p.primaryConnection?.ownAgentQueues.isNotEmpty ?? false)) ...[
        _PaletteCmd(
          Icons.pause_circle_outline_rounded,
          tr('Pausa su tutte le code'),
          '> pausa code',
          () => p.primaryConnection?.setOwnQueuePause(pause: true),
        ),
        _PaletteCmd(
          Icons.play_circle_outline_rounded,
          tr('Riprendi tutte le code'),
          '> riprendi code',
          () => p.primaryConnection?.setOwnQueuePause(pause: false),
        ),
      ],
      if (widget.onOpenMiniHud != null)
        _PaletteCmd(
          Icons.picture_in_picture_alt_rounded,
          tr('Mini-HUD compatto'),
          '> mini',
          widget.onOpenMiniHud!,
        ),
      _PaletteCmd(
        Icons.dark_mode_rounded,
        tr('Tema scuro'),
        '> tema scuro',
        () => p.setThemeMode(ThemeMode.dark),
      ),
      _PaletteCmd(
        Icons.light_mode_rounded,
        tr('Tema chiaro'),
        '> tema chiaro',
        () => p.setThemeMode(ThemeMode.light),
      ),
      if (widget.onOpenPreferences != null)
        _PaletteCmd(
          Icons.tune_rounded,
          tr('Preferenze'),
          '> preferenze',
          widget.onOpenPreferences!,
        ),
    ];
    if (raw.startsWith('pickup ')) {
      final num = raw.substring(7).trim();
      final ext = p.allExtensions.where((e) => e.number == num).firstOrNull;
      if (ext != null && p.canPickupExtension(ext)) {
        all.insert(
          0,
          _PaletteCmd(
            Icons.phone_in_talk_rounded,
            tr('Rispondi per {n}', {'n': num}),
            '> pickup $num',
            () => p.pickupExtension(ext),
          ),
        );
      }
    } else if (raw.startsWith('trasf ') && p.call != null) {
      final num = raw.substring(6).trim();
      if (num.isNotEmpty) {
        all.insert(
          0,
          _PaletteCmd(
            Icons.phone_forwarded_rounded,
            tr('Trasferisci a {n}', {'n': num}),
            '> trasf $num',
            () => p.transfer(num),
          ),
        );
      }
    }
    if (raw.isEmpty) return all;
    return [
      for (final cmd in all)
        if (cmd.title.toLowerCase().contains(raw) ||
            cmd.subtitle.toLowerCase().contains(raw))
          cmd,
    ];
  }

  int get _rows => _typed.isEmpty
      ? _quick.length
      : _isCommand
      ? _commands.length
      : _hits.length + (_offerNumber ? 1 : 0);

  /// A campo vuoto: ultimi 5 numeri del registro, poi i preferiti.
  List<(bool, String, String, Extension?, CallRecord?)> get _quick {
    final out = <(bool, String, String, Extension?, CallRecord?)>[];
    final seen = <String>{};
    for (final r in p.history) {
      if (out.length == 5) break;
      if (r.number.isEmpty || !seen.add(r.number)) continue;
      out.add((
        true,
        r.number,
        r.name.isNotEmpty ? r.name : p.nameFor(r.number),
        null,
        r,
      ));
    }
    for (final e in p.favorites.take(8)) {
      out.add((false, e.number, e.name, e, null));
    }
    return out;
  }

  /// Fuoco nel campo vuoto: compaiono recenti e preferiti.
  void _showQuick() {
    if (_typed.isEmpty && _quick.isNotEmpty) {
      setState(() => _selected = 0);
      _results.show();
    }
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _results.hide();
      } else {
        _showQuick();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _text.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _changed(String v) {
    setState(() {
      _hits = p.search(v);
      _selected = 0;
    });
    if (_typed.isNotEmpty) {
      _results.show();
    } else if (_focus.hasFocus && _quick.isNotEmpty) {
      _results.show();
    } else {
      _results.hide();
    }
  }

  void _call(String number) {
    widget.onCall(number);
    _text.clear();
    _changed('');
    _keypad.hide();
  }

  void _activate(int i, {bool video = false}) {
    if (_isCommand) {
      final cmds = _commands;
      if (i < cmds.length) {
        cmds[i].run();
        _text.clear();
        _changed('');
        _results.hide();
      }
      return;
    }
    if (_typed.isEmpty) {
      final q = _quick;
      if (i >= q.length) return;
      final (_, number, _, e, _) = q[i];
      if (e == null) {
        if (video && widget.onVideoCall != null) {
          widget.onVideoCall!(number);
          _text.clear();
          _changed('');
          _keypad.hide();
          return;
        }
        return _call(number);
      }
      if (!p.isCallable(e)) return;
      p.dial(number, via: e, video: video);
      _results.hide();
      return;
    }
    if (_offerNumber) {
      if (i == 0) {
        if (video && widget.onVideoCall != null) {
          widget.onVideoCall!(_typed);
          _text.clear();
          _changed('');
          _keypad.hide();
          return;
        }
        return _call(_typed);
      }
      i--;
    }
    if (i < _hits.length) {
      final h = _hits[i];
      final e = h.extension;
      if (e == null) {
        if (video && widget.onVideoCall != null) {
          widget.onVideoCall!(h.number);
          _text.clear();
          _changed('');
          _keypad.hide();
          return;
        }
        return _call(h.number);
      }
      if (!p.isCallable(e)) return;
      // Interno: tramite l'account SIP del suo PBX.
      p.dial(h.number, via: e, video: video);
      _text.clear();
      _changed('');
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
    if ((e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        HardwareKeyboard.instance.isShiftPressed &&
        p.videoEnabled &&
        !_isCommand) {
      _activate(_selected, video: true);
      return KeyEventResult.handled;
    }
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
      child: AnimatedPopup(
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
    ),
  );

  Widget _row(
    DrinColors c,
    int index,
    Widget leading,
    String title,
    String sub, {
    bool enabled = true,
    Widget? trailing,
    String? copyNumber,
    VoidCallback? onVideo,
    IconData actionIcon = Icons.call_rounded,
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
              if (trailing != null) ...[
                trailing,
                const SizedBox(width: DrinSpace.s2),
              ],
              if (on && copyNumber != null && copyNumber.isNotEmpty)
                IconButton(
                  tooltip: tr('Copia numero'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: () => copyWithToast(context, copyNumber),
                  icon: Icon(
                    Icons.content_copy_rounded,
                    size: 15,
                    color: c.muted,
                  ),
                ),
              if (on && onVideo != null && enabled)
                IconButton(
                  tooltip: tr('Videochiamata'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: onVideo,
                  icon: Icon(
                    Icons.videocam_rounded,
                    size: 16,
                    color: c.primary,
                  ),
                ),
              Icon(
                actionIcon,
                size: 18,
                color: enabled ? c.accent : c.border,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Recenti (con la direzione) e preferiti (con stato e segnalino dal vivo).
  Widget _quickList(DrinColors c) {
    final q = _quick;
    Widget head(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: Text(t, style: DrinText.label.copyWith(color: c.muted)),
    );
    final rows = <Widget>[];
    for (var i = 0; i < q.length; i++) {
      final (recent, number, name, e, r) = q[i];
      if (i == 0 && recent) rows.add(head(tr('Recenti')));
      if (!recent && (i == 0 || q[i - 1].$1)) rows.add(head(tr('Preferiti')));
      final title = name.isEmpty || name == number ? number : name;
      if (recent) {
        final icon = r!.missed
            ? (Icons.call_missed_rounded, c.busyText)
            : r.direction == CallDirection.incoming
            ? (Icons.call_received_rounded, c.freeText)
            : (Icons.call_made_rounded, c.primary);
        rows.add(
          _row(
            c,
            i,
            CircleAvatar(
              radius: 20,
              backgroundColor: c.keyBtn,
              child: Icon(icon.$1, size: 18, color: icon.$2),
            ),
            title,
            title == number ? '' : number,
          ),
        );
      } else {
        final live = p.primaryConnection?.extensionCalls[number];
        rows.add(
          _row(
            c,
            i,
            StatusAvatar(
              name: e!.name,
              blf: p.blfOf(e),
              presence: p.presenceOf(e),
            ),
            title,
            '${tr('Interno')} $number',
            enabled: p.isCallable(e),
            trailing: live == null ? null : LiveChip(live, dense: true),
          ),
        );
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _resultsList(DrinColors c) {
    if (_typed.isEmpty) return _quickList(c);
    if (_isCommand) {
      final cmds = _commands;
      if (cmds.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Text(tr('Nessun comando'), style: TextStyle(color: c.muted)),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Text(
              tr('Comandi rapidi'),
              style: DrinText.label.copyWith(color: c.muted),
            ),
          ),
          for (var i = 0; i < cmds.length; i++)
            _row(
              c,
              i,
              CircleAvatar(
                radius: 18,
                backgroundColor: c.panel,
                child: Icon(cmds[i].icon, size: 17, color: c.primary),
              ),
              cmds[i].title,
              cmds[i].subtitle,
              actionIcon: Icons.keyboard_return_rounded,
            ),
        ],
      );
    }
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
          copyNumber: _typed,
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
                  blf: p.blfOf(e),
                  presence: p.presenceOf(e),
                ),
                e.name,
                '${tr('Interno')} ${e.number}',
                enabled: p.isCallable(e),
                copyNumber: e.number,
                onVideo: p.videoEnabled
                    ? () {
                        p.dial(e.number, via: e, video: true);
                        _text.clear();
                        _changed('');
                      }
                    : null,
              )
            : _row(
                c,
                i++,
                StatusAvatar(name: h.name),
                h.name,
                '${h.label} · ${h.number}',
                copyNumber: h.number,
                onVideo: p.videoEnabled && widget.onVideoCall != null
                    ? () {
                        widget.onVideoCall!(h.number);
                        _text.clear();
                        _changed('');
                      }
                    : null,
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _width),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: c.field,
                border: Border.all(
                  color: _focus.hasFocus ? c.accent : c.border,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showSearchIcon = constraints.maxWidth >= 150;
                  final showKeypad = constraints.maxWidth >= 120;
                  return Row(
                    children: [
                      if (showSearchIcon) ...[
                        Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: _focus.hasFocus ? c.accent : c.muted,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Focus(
                          onKeyEvent: _key,
                          child: TextField(
                            controller: _text,
                            focusNode: _focus,
                            onChanged: _changed,
                            onTap: () {
                              _typed.isNotEmpty
                                  ? _results.show()
                                  : _showQuick();
                            },
                            onSubmitted: (_) {
                              _activate(_selected);
                              _focus.requestFocus();
                            },
                            style: mono(c.text, size: 15),
                            decoration: InputDecoration(
                              hintText: tr('Numero, interno o nome'),
                              // Il segnaposto non eredita il monospazio del testo digitato.
                              hintStyle: DrinText.body.copyWith(color: c.muted),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                            ),
                          ),
                        ),
                      ),
                      if (showKeypad) ...[
                        IconButton(
                          tooltip: tr('Tastierino'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: c.keyBtn,
                            foregroundColor: c.accent,
                          ),
                          onPressed: _keypad.toggle,
                          icon: const Icon(Icons.dialpad_rounded, size: 18),
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        tooltip: tr('Chiama'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: context.drin.free,
                          foregroundColor: context.drin.onFree,
                          disabledBackgroundColor: c.keyBtn,
                        ),
                        onPressed: p.canDial && _rows > 0
                            ? () => _activate(_selected)
                            : null,
                        icon: const Icon(Icons.call_rounded, size: 18),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
