import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/call_history.dart';
import 'package:drinphone/core/platform/screen_pop.dart';
import 'package:drinphone/core/recall_reminders.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/call/call_window.dart';
import 'package:drinphone/features/history/history_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(PhoneController, FakeSipEngine, Directory)> makePhone({
    Settings initial = const Settings(),
    List<CallRecord> history = const [],
    DateTime Function()? clock,
    bool Function(Uri)? screenPopOpener,
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('drin_s4_');
    final store = SettingsStore(
      '${dir.path}${Platform.pathSeparator}settings.json',
    );
    await store.save(initial);
    final histStore = CallHistoryStore(
      '${dir.path}${Platform.pathSeparator}history.json',
    );
    if (history.isNotEmpty) await histStore.save(history);
    final remStore = RecallReminderStore(
      '${dir.path}${Platform.pathSeparator}reminders.json',
    );
    final engine = FakeSipEngine();
    final phone = PhoneController(
      engine,
      store,
      engineDataDir: dir.path,
      logDir: dir.path,
      historyStoreFor: (_) => histStore,
      reminderStore: remStore,
      clock: clock,
      screenPopOpener: screenPopOpener,
    );
    await phone.init();
    addTearDown(() async {
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
    return (phone, engine, dir);
  }

  test('Perse da richiamare esclude chiamate già risposte o richiamate', () async {
    final t0 = DateTime(2026, 11, 16, 9, 0);
    final (phone, _, _) = await makePhone(
      clock: () => DateTime(2026, 11, 16, 12, 0),
      history: [
        // 081111111: prima persa alle 09:00, poi richiamata alle 10:00 -> risolta.
        CallRecord(
          number: '+39 081111111',
          name: 'Mario',
          direction: CallDirection.outgoing,
          start: t0.add(const Duration(hours: 1)),
          seconds: 25,
          answered: true,
        ),
        CallRecord(
          number: '081111111',
          name: 'Mario',
          direction: CallDirection.incoming,
          start: t0,
          seconds: 0,
          answered: false,
        ),
        // 333222222: due perse, nessuna chiamata successiva -> conta 1 interlocutore da richiamare.
        CallRecord(
          number: '333222222',
          name: 'Anna',
          direction: CallDirection.incoming,
          start: t0.add(const Duration(minutes: 40)),
          seconds: 0,
          answered: false,
          note: 'Richiede preventivo',
        ),
        CallRecord(
          number: '333222222',
          name: 'Anna',
          direction: CallDirection.incoming,
          start: t0.add(const Duration(minutes: 10)),
          seconds: 0,
          answered: false,
        ),
      ],
    );

    expect(phone.unreturnedMissedCount, 1);
    final ctx = phone.callerContext('+39333222222');
    expect(ctx.todayCalls, 2);
    expect(ctx.lastNote, 'Richiede preventivo');
    expect(ctx.lastCall?.missed, isTrue);
  });

  test('updateHistoryNote aggiorna e persiste la nota post-chiamata', () async {
    final rec = CallRecord(
      number: '305',
      name: 'Assistenza',
      direction: CallDirection.incoming,
      start: DateTime(2026, 11, 16, 10, 0),
      seconds: 40,
      answered: true,
    );
    final (phone, _, dir) = await makePhone(history: [rec]);
    await phone.updateHistoryNote(rec, 'Inviare offerta entro venerdì');
    expect(phone.history.first.note, 'Inviare offerta entro venerdì');

    final reloaded = await CallHistoryStore(
      '${dir.path}${Platform.pathSeparator}history.json',
    ).load();
    expect(reloaded.first.note, 'Inviare offerta entro venerdì');
  });

  test('Promemoria di richiamata: pianifica, scade, rimanda e chiude su disco', () async {
    var now = DateTime(2026, 11, 16, 14, 0);
    final (phone, _, dir) = await makePhone(clock: () => now);
    await phone.scheduleReminder(
      number: '339123456',
      name: 'Luca',
      note: 'Contratto',
      delay: const Duration(minutes: 15),
    );
    expect(phone.reminders.length, 1);
    expect(phone.dueReminders, isEmpty);

    now = now.add(const Duration(minutes: 16));
    phone.checkReminders();
    expect(phone.dueReminders.length, 1);

    final id = phone.dueReminders.first.id;
    await phone.postponeReminder(id, const Duration(minutes: 15));
    expect(phone.dueReminders, isEmpty);

    now = now.add(const Duration(minutes: 15));
    expect(phone.dueReminders.length, 1);

    await phone.dismissReminder(id);
    expect(phone.reminders, isEmpty);

    final stored = await RecallReminderStore(
      '${dir.path}${Platform.pathSeparator}reminders.json',
    ).load();
    expect(stored, isEmpty);
  });

  test('buildScreenPopUri accetta solo HTTP/HTTPS e apre auto su entrante se attivo', () async {
    expect(
      buildScreenPopUri('javascript:alert(1)', number: '100'),
      isNull,
    );
    expect(
      buildScreenPopUri('file:///C:/Windows/win.ini?n={number}', number: '100'),
      isNull,
    );
    final ok = buildScreenPopUri(
      'https://crm.example.com/find?tel={number}&name={name}',
      number: '+39 081 555',
      name: 'Mario Rossi',
    );
    expect(
      ok.toString(),
      'https://crm.example.com/find?tel=%2B39+081+555&name=Mario+Rossi',
    );

    final opened = <Uri>[];
    final (phone, engine, _) = await makePhone(
      initial: const Settings(
        crmUrlTemplate: 'https://crm.example.com/find?tel={number}',
        crmAutoOpen: true,
      ),
      screenPopOpener: (u) {
        opened.add(u);
        return true;
      },
    );

    engine.callsCtl.add(
      const CallEvent(
        id: 77,
        phase: CallPhase.incoming,
        direction: CallDirection.incoming,
        remoteNumber: '335999000',
        remoteName: 'Cliente VIP',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(opened.length, 1);
    expect(opened.first.queryParameters['tel'], '335999000');
  });

  testWidgets('HistoryView mostra da richiamare e CallWindow mostra contesto e Apri CRM', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final now = DateTime.now();
      final (phone, engine, _) = await makePhone(
        initial: const Settings(
          crmUrlTemplate: 'https://crm.example.com/find?tel={number}',
        ),
        history: [
          CallRecord(
            number: '340111222',
            name: 'Studio Bianchi',
            direction: CallDirection.incoming,
            start: now.subtract(const Duration(minutes: 20)),
            seconds: 0,
            answered: false,
            note: 'Chiede stato pratica',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              height: 700,
              child: HistoryView(phone: phone, onCall: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('da richiamare'), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      engine.callsCtl.add(
        const CallEvent(
          id: 88,
          phase: CallPhase.incoming,
          direction: CallDirection.incoming,
          remoteNumber: '340111222',
          remoteName: 'Studio Bianchi',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              height: 700,
              child: Stack(children: [CallWindow(phone: phone)]),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Chiede stato pratica'), findsOneWidget);
      expect(find.text('Già 1 chiamata oggi'), findsOneWidget);
      expect(find.text('Apri CRM'), findsOneWidget);
    });
  });
}

