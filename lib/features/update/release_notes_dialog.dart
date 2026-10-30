import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/update/release_notes.dart';

/// Popup "Novità": note di rilascio divise per sezioni. [action] è un pulsante
/// in più (es. "Installa e riavvia" dal pannello aggiornamenti).
Future<void> showReleaseNotes(
  BuildContext context,
  ReleaseNotes notes, {
  String? title,
  Widget? action,
}) => showDialog<void>(
  context: context,
  builder: (ctx) =>
      ReleaseNotesDialog(notes: notes, title: title, action: action),
);

class ReleaseNotesDialog extends StatelessWidget {
  const ReleaseNotesDialog({
    super.key,
    required this.notes,
    this.title,
    this.action,
  });
  final ReleaseNotes notes;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final height = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: drinBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.celebration_rounded,
                      color: drinBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title ?? tr('Novità di questa versione'),
                          style: TextStyle(
                            color: c.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'DrinPhone $releaseChannel ${notes.version}',
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final s in notes.sections) _Section(s)],
                ),
              ),
            ),
            Divider(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ?action,
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('Chiudi')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.section);
  final NotesSection section;

  /// Icona e colore dal titolo (italiano o inglese); altrimenti neutri.
  (IconData, Color) _style(DrinColors c) {
    final t = section.title.toLowerCase();
    if (t.startsWith('novit') || t.startsWith('new')) {
      return (Icons.auto_awesome_rounded, drinBlue);
    }
    if (t.startsWith('miglior') || t.startsWith('improv')) {
      return (Icons.trending_up_rounded, c.ok);
    }
    if (t.startsWith('corre') || t.startsWith('fix')) {
      return (Icons.build_rounded, c.accent);
    }
    if (t.startsWith('da fare') || t.startsWith('action')) {
      return (Icons.checklist_rounded, c.primary);
    }
    if (t.startsWith('sicur') || t.startsWith('secur')) {
      return (Icons.shield_rounded, c.busy);
    }
    return (Icons.notes_rounded, c.muted);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final (icon, color) = _style(c);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      section.title,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: c.card,
              border: Border(left: BorderSide(color: color, width: 3)),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in section.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 8),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
