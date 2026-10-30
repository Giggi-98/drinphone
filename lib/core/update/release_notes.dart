import 'package:flutter/services.dart' show rootBundle;

/// Una sezione delle note di rilascio ("Novità", "Correzioni", "Sicurezza").
class NotesSection {
  const NotesSection(this.title, this.items);
  final String title;
  final List<String> items;
}

/// Note di rilascio di una versione: `release-notes/<versione>.md` nel repo,
/// incluse nell'app (asset) e firmate nel manifest degli aggiornamenti.
/// Formato: `## Titolo sezione` e voci `- testo`; una riga rientrata continua
/// la voce precedente. Solo testo, niente HTML né link.
class ReleaseNotes {
  const ReleaseNotes(this.version, this.sections);
  final String version;
  final List<NotesSection> sections;

  bool get isEmpty => sections.every((s) => s.items.isEmpty);

  static ReleaseNotes parse(String version, String text) {
    final sections = <NotesSection>[];
    var title = '';
    var items = <String>[];
    void close() {
      if (items.isNotEmpty) sections.add(NotesSection(title, items));
    }

    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trimRight();
      final t = line.trimLeft();
      if (t.startsWith('## ')) {
        close();
        title = t.substring(3).trim();
        items = [];
      } else if (t.startsWith('- ') || t.startsWith('* ')) {
        items.add(t.substring(2).trim());
      } else if (t.isEmpty || t.startsWith('#')) {
        continue;
      } else if (line.startsWith(' ') && items.isNotEmpty) {
        items[items.length - 1] = '${items.last} $t';
      } else {
        items.add(t);
      }
    }
    close();
    return ReleaseNotes(version, sections);
  }

  /// Note incluse nell'app per [version]; null se mancano.
  static Future<ReleaseNotes?> bundled(String version) async {
    try {
      final text = await rootBundle.loadString('release-notes/$version.md');
      final notes = parse(version, text);
      return notes.isEmpty ? null : notes;
    } catch (_) {
      return null;
    }
  }
}
