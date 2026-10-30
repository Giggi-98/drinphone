import 'dart:io';

import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/update/release_notes.dart';
import 'package:drinphone/core/update/updater.dart';
import 'package:drinphone/features/update/release_notes_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formato: sezioni, voci, righe di continuazione', () {
    final n = ReleaseNotes.parse('1.2.3', '''
# Titolo ignorato
Testo libero prima delle sezioni

## Novità
- Prima voce
  che continua qui
* Seconda voce

## Vuota

## Sicurezza
- Una sola
''');
    expect(n.sections.map((s) => s.title), ['', 'Novità', 'Sicurezza']);
    expect(n.sections[0].items, ['Testo libero prima delle sezioni']);
    expect(n.sections[1].items, [
      'Prima voce che continua qui',
      'Seconda voce',
    ]);
    expect(n.sections[2].items, ['Una sola']);
    expect(ReleaseNotes.parse('1.2.3', '\n## Solo titolo\n').isEmpty, isTrue);
  });

  test('ogni versione di pubspec.yaml ha le sue note di rilascio', () {
    final m = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    final f = File('release-notes/${m[1]}.md');
    expect(f.existsSync(), isTrue, reason: 'manca ${f.path}');
    expect(ReleaseNotes.parse(m[1]!, f.readAsStringSync()).isEmpty, isFalse);
  });

  testWidgets('novità mostrate una volta per versione', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('drin_notes');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final seen = '${tmp.path}${Platform.pathSeparator}notes-seen';
    final version = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())![1]!;
    final u = Updater(
      current: version,
      downloadDir: tmp.path,
      notesSeenFile: seen,
    );
    await tester.runAsync(() async {
      expect((await u.unseenNotes())?.version, version);
      await u.markNotesSeen();
      expect(await u.unseenNotes(), isNull);
      // Build di sviluppo: mai.
      final dev = Updater(
        current: 'dev',
        downloadDir: tmp.path,
        notesSeenFile: '$seen-dev',
      );
      expect(await dev.unseenNotes(), isNull);
    });
  });

  for (final b in Brightness.values) {
    testWidgets('popup novità: sezioni leggibili a 360 px, tema ${b.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final notes = ReleaseNotes.parse('9.9.9', '''
## Novità
- ${'Voce molto lunga che deve andare a capo senza tagli. ' * 3}
## Correzioni
- Una correzione
## Sicurezza
- Una nota di sicurezza
## Da fare dopo l'aggiornamento, con un titolo di sezione molto lungo
- Un passo
''');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(b),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showReleaseNotes(context, notes),
                  child: const Text('apri'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
      expect(find.text('Novità'), findsOneWidget);
      expect(find.text('Correzioni'), findsOneWidget);
      expect(find.text('Sicurezza'), findsOneWidget);
      expect(find.text('Una correzione'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      expect(find.text('Novità'), findsNothing);
    });
  }
}
