import 'package:drinphone/app/theme.dart';
import 'package:drinphone/features/history/range_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<DateTimeRange?> open(
    WidgetTester tester,
    Future<void> Function() act,
  ) async {
    tester.view.physicalSize = const Size(1366, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DateTimeRange? out;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => out = await showRangePicker(ctx),
            child: const Text('apri'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.text('Intervallo di date'), findsOneWidget);
    expect(find.text('Lun'), findsNWidgets(2)); // settimana da lunedì, 2 mesi
    expect(tester.takeException(), isNull);
    await act();
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();
    return out;
  }

  testWidgets('scorciatoia "Ieri"', (tester) async {
    final r = await open(tester, () async {
      await tester.tap(find.text('Ieri'));
      await tester.pump();
    });
    final now = DateTime.now();
    final y = DateTime(now.year, now.month, now.day - 1);
    expect(r, DateTimeRange(start: y, end: y));
  });

  testWidgets('due clic: inizio e fine, anche al contrario', (tester) async {
    final r = await open(tester, () async {
      // Giorni del mese di sinistra (sempre interamente nel passato).
      await tester.tap(find.text('20').first);
      await tester.pump();
      await tester.tap(find.text('10').first);
      await tester.pump();
    });
    expect(r, isNotNull);
    expect(r!.start.day, 10);
    expect(r.end.day, 20);
  });
}
