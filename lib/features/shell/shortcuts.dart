import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';

/// Scorciatoie da tastiera dell'app (desktop). Tutte con Ctrl, così non
/// rubano tasti a un campo di testo; F1 apre questo elenco.
List<(String, String)> shortcutList() => [
  ('Ctrl + K', tr('Cerca o componi un numero')),
  ('Ctrl + 1…5', tr('Vai alle sezioni del menu')),
  ('Ctrl + ,', tr('Preferenze')),
  ('Ctrl + Invio', tr('Rispondi alla chiamata in arrivo')),
  ('Ctrl + E', tr('Termina o rifiuta la chiamata')),
  ('Ctrl + M', tr('Microfono muto / attivo')),
  ('Ctrl + H', tr('Metti in attesa / riprendi')),
  ('Ctrl + + / −', tr('Ingrandisci / riduci (anche Ctrl + rotella)')),
  ('Ctrl + 0', tr('Zoom al 100 %')),
  ('Ctrl + Alt + A', tr('Rispondi / termina (globale, se attivo)')),
  ('Ctrl + Alt + M', tr('Muto / attivo (globale, se attivo)')),
  ('Ctrl + Alt + D', tr('Chiama numero negli appunti (globale, se attivo)')),
  ('F1', tr('Questo elenco')),
];

/// Ctrl senza Alt (AltGr su Windows è Ctrl+Alt) né Win.
bool get ctrlOnly {
  final kb = HardwareKeyboard.instance;
  return kb.isControlPressed && !kb.isAltPressed && !kb.isMetaPressed;
}

/// Cifra 1–9 del tasto (riga dei numeri o tastierino), altrimenti null.
int? digitOf(LogicalKeyboardKey k) {
  final label = k.keyLabel;
  final n = int.tryParse(label.length == 1 ? label : '');
  if (n != null && n >= 1) return n;
  const pad = [
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];
  final i = pad.indexOf(k);
  return i < 0 ? null : i + 1;
}

/// Foglio delle scorciatoie (F1).
Future<void> showShortcuts(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) {
    final c = ctx.drin;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.keyboard_rounded, color: c.primary),
          const SizedBox(width: DrinSpace.s3),
          Text(tr('Scorciatoie da tastiera')),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (keys, what) in shortcutList())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DrinSpace.s1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        what,
                        style: DrinText.body.copyWith(color: c.ink),
                      ),
                    ),
                    const SizedBox(width: DrinSpace.s4),
                    KeyCap(keys),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('Chiudi')),
        ),
      ],
    );
  },
);

/// Tasto disegnato: pillola `panel` con bordo `line`, testo `number`.
class KeyCap extends StatelessWidget {
  const KeyCap(this.keys, {super.key});
  final String keys;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DrinSpace.s2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(DrinRadius.control),
      ),
      child: Text(keys, style: DrinText.number.copyWith(color: c.ink)),
    );
  }
}
