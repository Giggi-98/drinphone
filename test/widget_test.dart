import 'dart:io';

import 'package:drinphone/app/l10n.dart';
import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/platform/call_links.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/history/history_view.dart';
import 'package:drinphone/features/contacts/contacts_view.dart';
import 'package:drinphone/features/shell/search_box.dart';
import 'package:drinphone/core/contacts/personal_contacts.dart';
import 'package:drinphone/core/call_history.dart';
import 'package:drinphone/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

const _account = SipAccount(
  username: '201',
  password: 's3greta!',
  domain: 'pbx.test',
  displayName: 'Prova',
);

void main() {
  late Directory tmp;
  late FakeSipEngine engine;
  late SettingsStore store;
  late PhoneController phone;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('drinphone_test');
    engine = FakeSipEngine();
    store = SettingsStore('${tmp.path}${Platform.pathSeparator}settings.json');
    phone = PhoneController(
      engine,
      store,
      engineDataDir: tmp.path,
      logDir: tmp.path,
    );
    await phone.init();
  });

  tearDown(() => tmp.delete(recursive: true));

  test('preferenze di vista salvate; salvataggi ravvicinati in coda', () async {
    await phone.setViewPref('ext.sort', 'name');
    // Due scritture insieme: una dopo l'altra, vince l'ultima.
    await Future.wait([
      phone.setViewFlag('ext.byState', true),
      phone.setViewFlag('ext.rows', true),
    ]);
    final saved = await store.load();
    expect(saved.view['ext.sort'], 'name');
    expect(saved.view['ext.byState'], '1');
    expect(saved.view['ext.rows'], '1');
  });

  test(
    'la password va nello storage sicuro, non nel file impostazioni',
    () async {
      await phone.saveAccount(_account);
      await phone.setDebugLog(true);
      final json = await File(store.path).readAsString();
      expect(json, isNot(contains(_account.password)));
      expect(json, contains('pbx.test'));
      final reloaded = await store.load();
      expect(reloaded.account!.password, _account.password);
      expect(reloaded.debugLog, isTrue);
      expect(engine.registered!.username, '201');
    },
  );

  test('SipAccount.toString non espone la password', () {
    expect('$_account', isNot(contains(_account.password)));
  });

  test('si compone solo da registrato e senza chiamate in corso', () async {
    await phone.saveAccount(_account);
    await phone.dial('202');
    expect(engine.log, isNot(contains('dial 202')));

    engine.registrationsCtl.add(const RegistrationEvent(RegistrationStatus.ok));
    await phone.dial('202');
    expect(engine.log, contains('dial 202'));

    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.outgoing,
        direction: CallDirection.outgoing,
        remoteNumber: '202',
      ),
    );
    expect(phone.canDial, isFalse);
    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.active,
        direction: CallDirection.outgoing,
        remoteNumber: '202',
      ),
    );
    expect(phone.callConnectedAt, isNotNull);
    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.ended,
        direction: CallDirection.outgoing,
        remoteNumber: '202',
      ),
    );
    expect(phone.call, isNull);
    expect(phone.canDial, isTrue);
  });

  test('errore di chiamata produce un avviso e resetta il muto', () async {
    await phone.saveAccount(_account);
    engine.registrationsCtl.add(const RegistrationEvent(RegistrationStatus.ok));
    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.active,
        direction: CallDirection.incoming,
        remoteNumber: '300',
      ),
    );
    await phone.toggleMute();
    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.error,
        direction: CallDirection.incoming,
        remoteNumber: '300',
        message: 'Busy',
      ),
    );
    expect(phone.notice, contains('Busy'));
    expect(phone.muted, isFalse);
    expect(engine.log, contains('mute false'));
  });

  test(
    'BLF: sottoscrive gli interni da registrato, sconosciuto se cade',
    () async {
      await phone.saveAccount(_account);
      await phone.addExtension(const Extension('Paolo', '301'));
      expect(engine.watched, isEmpty); // account non ancora registrato
      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      expect(engine.watched, {'301@pbx.test'});

      engine.dialogsCtl.add(const BlfEvent('301@pbx.test', BlfStatus.busy));
      expect(phone.blfOf(phone.settings.extensions.first), BlfStatus.busy);

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.failed),
      );
      expect(phone.blf, isEmpty);

      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      await phone.addExtension(const Extension('Sala', '300'));
      expect(engine.watched, {'301@pbx.test', '300@pbx.test'});
      await phone.removeExtension(phone.settings.extensions.first);
      expect(engine.watched, {'300@pbx.test'});
    },
  );

  testWidgets('più account: scelta all’avvio, accesso, logout', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final two = await tester.runAsync(() async {
      await store.save(
        const Settings(
          profileName: 'Uno',
          accounts: [_account],
          others: [
            Profile(
              id: 'p2',
              name: 'Due',
              kind: ProfileKind.sip,
              accounts: [
                SipAccount(
                  id: 'b2',
                  username: '902',
                  password: 'q',
                  domain: 'b.test',
                ),
              ],
            ),
          ],
        ),
      );
      final c = PhoneController(
        FakeSipEngine(),
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await c.init();
      return c;
    });
    await tester.pumpWidget(DrinPhoneApp(phone: two!));
    await tester.pump();
    expect(find.text('Scegli l’account'), findsOneWidget);
    expect(find.text('Uno'), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);
    expect(find.text('Chiama con'), findsNothing);

    await tester.runAsync(() => two.login('p2'));
    await tester.pumpAndSettle();
    expect(find.text('Scegli l’account'), findsNothing);
    expect(find.text('902'), findsWidgets);
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Esci (logout)'), findsOneWidget);
    await tester.tap(find.text('Esci (logout)'));
    await tester.pumpAndSettle();
    // Conferma prima di scollegare l'interno.
    expect(find.text('Uscire dall’account?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Esci (logout)'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(two.loggedIn, isFalse);
    expect(find.text('Scegli l’account'), findsOneWidget);
    await tester.runAsync(two.shutdown);
  });

  testWidgets('link tel: chiama solo dopo conferma', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => pendingCallLink.value = null);
    await tester.runAsync(() => phone.saveAccount(_account));
    await tester.pumpWidget(DrinPhoneApp(phone: phone));
    engine.registrationsCtl.add(const RegistrationEvent(RegistrationStatus.ok));
    await tester.pumpAndSettle();
    expect(phone.canDial, isTrue);

    pendingCallLink.value = numberFromLink('tel:+39%2002%205550');
    await tester.pumpAndSettle();
    expect(find.text('Chiamare +39025550?'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(engine.log.where((l) => l.startsWith('dial')), isEmpty);
    expect(pendingCallLink.value, isNull);

    // Chiama si attiva dopo un attimo, e di nuovo a ogni numero cambiato
    // col dialogo aperto: il click "in corsa" non chiama.
    final chiama = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Chiama'),
    );
    pendingCallLink.value = '301';
    await tester.pumpAndSettle();
    await tester.tap(chiama);
    await tester.pump();
    expect(engine.log.where((l) => l.startsWith('dial')), isEmpty);
    await tester.pump(const Duration(milliseconds: 1300));
    pendingCallLink.value = '302';
    await tester.pump();
    expect(find.text('Chiamare 302?'), findsOneWidget);
    await tester.tap(chiama);
    await tester.pump();
    expect(engine.log.where((l) => l.startsWith('dial')), isEmpty);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.tap(chiama);
    await tester.pumpAndSettle();
    expect(
      engine.log.where((l) => l.startsWith('dial')).single,
      contains('302'),
    );
  });

  testWidgets('chiamata in arrivo mostra Rispondi e Rifiuta', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(DrinPhoneApp(phone: phone));
    // Installazione vuota: procedura guidata, rimandabile.
    expect(find.text('Benvenuto in DrinPhone'), findsOneWidget);
    await tester.tap(find.text('Configura più tardi'));
    await tester.pumpAndSettle();
    expect(find.text('Nessun account SIP configurato.'), findsOneWidget);

    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.incoming,
        direction: CallDirection.incoming,
        remoteNumber: '205',
        remoteName: 'Magazzino',
      ),
    );
    await tester.pump();
    expect(find.text('Chiamata in arrivo'), findsOneWidget);
    await tester.tap(find.text('Rispondi'));
    expect(engine.log, contains('answer 0'));

    // In conversazione: finestra grande con la barra dei comandi.
    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.active,
        direction: CallDirection.incoming,
        remoteNumber: '205',
        remoteName: 'Magazzino',
      ),
    );
    await tester.pump();
    for (final label in [
      'Muto',
      'Attesa',
      'Tastiera',
      'Trasferisci',
      'Termina',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Riduci: resta una barra con riaggancia ed espandi.
    await tester.tap(find.byTooltip('Riduci'));
    await tester.pump();
    expect(find.text('Termina'), findsNothing);
    expect(find.byTooltip('Espandi'), findsOneWidget);
    await tester.tap(find.byTooltip('Espandi'));
    await tester.pump();
    expect(find.text('Termina'), findsOneWidget);

    // Fine chiamata: la finestra si dissolve e sparisce.
    engine.callsCtl.add(
      const CallEvent(
        phase: CallPhase.ended,
        direction: CallDirection.incoming,
        remoteNumber: '205',
        remoteName: 'Magazzino',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Termina'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('una registrazione per account: salvarne una sostituisce', () async {
    const other = SipAccount(
      id: 'main',
      username: '401',
      password: 'altra!',
      domain: 'pbx2.test',
    );
    await phone.saveAccount(_account);
    await phone.saveAccount(other);
    expect(engine.accounts.map((a) => a.username), ['401']);
    final reloaded = await store.load();
    expect(reloaded.accounts.single.password, 'altra!');
    expect(await File(store.path).readAsString(), isNot(contains('altra!')));
  });

  // Bug 0.1.2: cambiare lingua o tema riportava all elenco interni.
  testWidgets('lingua e tema cambiano restando nella sezione aperta', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() {
      appLang.value = AppLang.it;
      appThemeMode.value = ThemeMode.system;
    });
    late PhoneController p;
    await tester.runAsync(() async {
      await store.save(const Settings(accounts: [_account]));
      p = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await p.init();
    });
    await tester.pumpWidget(DrinPhoneApp(phone: p));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Preferenze').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Diagnostica'), findsWidgets);

    await tester.runAsync(() => p.setLanguage(AppLang.en));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Diagnostics'), findsWidgets);
    expect(find.text('Diagnostica'), findsNothing);

    await tester.runAsync(() => p.setThemeMode(ThemeMode.dark));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Diagnostics'), findsWidgets);
    expect((await tester.runAsync(store.load))!.theme, 'dark');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ctrl +/−/0 cambiano lo zoom dell interfaccia e lo salvano', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => appZoom.value = 1.0);
    late PhoneController p;
    await tester.runAsync(() async {
      await store.save(const Settings(accounts: [_account]));
      p = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await p.init();
    });
    await tester.pumpWidget(DrinPhoneApp(phone: p));
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> ctrl(LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // Meno del ritardo di salvataggio: il file si scrive solo alla fine.
      await tester.pump(const Duration(milliseconds: 100));
    }

    await ctrl(LogicalKeyboardKey.equal);
    expect(appZoom.value, 1.1);
    expect(find.text('110 %'), findsOneWidget);
    await ctrl(LogicalKeyboardKey.minus);
    await ctrl(LogicalKeyboardKey.numpadSubtract);
    expect(appZoom.value, 0.9);
    for (var i = 0; i < 3; i++) {
      await ctrl(LogicalKeyboardKey.minus);
    }
    expect(appZoom.value, DrinScale.zoomMin);
    await ctrl(LogicalKeyboardKey.digit0);
    expect(appZoom.value, 1.0);
    // Senza Ctrl il tasto resta al campo di testo.
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    expect(appZoom.value, 1.0);

    // Ctrl + rotella: su ingrandisce, giù riduce; senza Ctrl niente zoom.
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(700, 400)));
    Future<void> wheel(double dy, {bool ctrl = true}) async {
      if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
      if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
    }

    await wheel(-100);
    expect(appZoom.value, 1.1);
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 100)),
    );
    await wheel(100);
    expect(appZoom.value, 1.0);
    await wheel(-100, ctrl: false);
    expect(appZoom.value, 1.0);

    // Salvato una volta sola, dopo l'ultima pressione.
    await tester.runAsync(() async {
      p.setZoom(1.3);
      await Future.delayed(const Duration(milliseconds: 900));
    });
    expect((await tester.runAsync(store.load))!.zoom, 1.3);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scorciatoie: Ctrl+numero cambia sezione, F1 le elenca', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late PhoneController p;
    await tester.runAsync(() async {
      await store.save(const Settings(accounts: [_account]));
      p = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await p.init();
    });
    await tester.pumpWidget(DrinPhoneApp(phone: p));
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> ctrl(LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Senza Live Calls: 1 Interni, 2 Rubrica, 3 Registro, 4 Casella vocale.
    await ctrl(LogicalKeyboardKey.digit3);
    expect(find.byType(HistoryView), findsOneWidget);
    await ctrl(LogicalKeyboardKey.digit2);
    expect(find.byType(ContactsView), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Scorciatoie da tastiera'), findsOneWidget);
    await tester.tap(find.text('Chiudi'));
    await tester.pump(const Duration(milliseconds: 400));

    await ctrl(LogicalKeyboardKey.keyK);
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(SearchBox),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.focusNode.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Interni: vista a righe e legenda senza overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late PhoneController p;
    await tester.runAsync(() async {
      await store.save(
        const Settings(
          accounts: [_account],
          extensions: [
            Extension('Margherita Talenti', '200'),
            Extension('208', '208'),
            Extension('211 211', '211'),
          ],
        ),
      );
      p = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await p.init();
    });
    await tester.pumpWidget(DrinPhoneApp(phone: p));
    await tester.pump(const Duration(milliseconds: 300));
    // Nome uguale al numero: il numero una volta sola.
    expect(find.text('211 211'), findsNothing);

    await tester.tap(find.byTooltip('Vista a righe'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('Margherita Talenti'), findsWidgets);

    await tester.tap(find.byTooltip('Legenda degli stati'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Anello: stato della linea'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Rubrica: lista continua con indice A–Z', (tester) async {
    tester.view.physicalSize = const Size(1366, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late PhoneController p;
    await tester.runAsync(() async {
      await store.save(const Settings(accounts: [_account]));
      p = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await p.init();
      for (final (i, n) in const [
        'Anna Rossi',
        'Bruno Verdi',
        'Carlo Neri',
      ].indexed) {
        await p.savePersonal(
          PersonalContact(
            id: 'c$i',
            name: n,
            numbers: [('Cellulare', '33300000$i')],
          ),
        );
      }
    });
    await tester.pumpWidget(DrinPhoneApp(phone: p));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('3 contatti'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    await tester.tap(find.text('C'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('header: ricerca e account contro il bordo destro', (
    tester,
  ) async {
    for (final w in [1100.0, 1920.0]) {
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1;
      late PhoneController p;
      await tester.runAsync(() async {
        await store.save(const Settings(accounts: [_account]));
        p = PhoneController(
          engine,
          store,
          engineDataDir: tmp.path,
          logDir: tmp.path,
        );
        await p.init();
      });
      await tester.pumpWidget(DrinPhoneApp(phone: p));
      await tester.pump(const Duration(milliseconds: 300));
      final chevron = tester.getRect(
        find.descendant(
          of: find.byTooltip('Account'),
          matching: find.byIcon(Icons.expand_more_rounded),
        ),
      );
      final right = tester.getRect(find.byType(Scaffold).first).right;
      // Solo il margine dell'header e del pulsante (meno di 40) a destra.
      expect(right - chevron.right, lessThan(40), reason: 'larghezza $w');
      await tester.pumpWidget(const SizedBox());
    }
    tester.view.reset();
  });

  testWidgets('Interni: ordina per nome e raggruppa per stato, salvati', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late PhoneController p;
    await tester.runAsync(() async {
      await store.save(
        const Settings(
          accounts: [_account],
          extensions: [
            Extension('Zeno', '200'),
            Extension('Anna', '210'),
            Extension('305', '305'),
          ],
        ),
      );
      p = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await p.init();
    });
    await tester.pumpWidget(DrinPhoneApp(phone: p));
    await tester.pump(const Duration(milliseconds: 300));
    double x(String t) => tester.getTopLeft(find.text(t).last).dx;
    double y(String t) => tester.getTopLeft(find.text(t).last).dy;
    // Predefinito per numero: Zeno (200) prima di Anna (210).
    expect(x('Zeno') < x('Anna') || y('Zeno') < y('Anna'), isTrue);

    await tester.tap(find.byTooltip('Ordina e raggruppa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina per nome'));
    await tester.pumpAndSettle();
    expect(x('Anna') < x('Zeno') || y('Anna') < y('Zeno'), isTrue);

    await tester.tap(find.byTooltip('Ordina e raggruppa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Raggruppa per stato'));
    await tester.pumpAndSettle();
    // Senza BLF né eventi: tutti in "Stato sconosciuto".
    expect(find.text('Stato sconosciuto'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Lascia finire le scritture partite dai tocchi, poi rilegge il file.
    // Scelte applicate e tenute dal controller (il file: test a parte).
    expect(p.settings.view['ext.sort'], 'name');
    expect(p.settings.view['ext.byState'], '1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Registro: ripetute ×3 apribili, giorni e riepilogo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late PhoneController p;
    await tester.runAsync(() async {
      await store.save(
        const Settings(
          accounts: [_account],
          view: {'hist.repeat': '1', 'hist.byDay': '1'},
        ),
      );
      p = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await p.init();
    });
    final now = DateTime.now();
    CallRecord missed(int min) => CallRecord(
      number: '250',
      name: 'Max Sartini',
      direction: CallDirection.incoming,
      start: now.subtract(Duration(minutes: min)),
      seconds: 0,
      answered: false,
    );
    p.history = [
      missed(1),
      missed(2),
      missed(3),
      CallRecord(
        number: '301',
        name: 'Paolo',
        direction: CallDirection.outgoing,
        start: now.subtract(const Duration(minutes: 10)),
        seconds: 95,
        answered: true,
      ),
    ];
    await tester.pumpWidget(DrinPhoneApp(phone: p));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 400));

    // Tre perse di fila dallo stesso numero: una riga "×3".
    expect(find.text('×3 · mostra tutte'), findsOneWidget);
    expect(find.text('Max Sartini'), findsOneWidget);
    // Intestazione del giorno con il totale e riepilogo di oggi.
    expect(find.text('4 chiamate'), findsOneWidget);
    expect(find.text('perse'), findsOneWidget);
    expect(find.text('1:35'), findsWidgets);

    await tester.tap(find.text('×3 · mostra tutte'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Max Sartini'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Rubrica: raggruppa per azienda, scelta salvata', (tester) async {
    tester.view.physicalSize = const Size(1366, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late PhoneController p;
    await tester.runAsync(() async {
      await store.save(const Settings(accounts: [_account]));
      p = PhoneController(
        engine,
        store,
        engineDataDir: tmp.path,
        logDir: tmp.path,
      );
      await p.init();
      for (final (i, (n, co)) in const [
        ('Anna Rossi', 'Fonica Srl'),
        ('Bruno Verdi', 'Econnet'),
        ('Carlo Neri', 'Fonica Srl'),
        ('Dario', ''),
      ].indexed) {
        await p.savePersonal(
          PersonalContact(
            id: 'c$i',
            name: n,
            company: co,
            numbers: [('Cellulare', '33300000$i')],
          ),
        );
      }
    });
    await tester.pumpWidget(DrinPhoneApp(phone: p));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('Raggruppa per azienda'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(p.settings.view['contacts.byCompany'], '1');
    expect(find.text('Senza azienda'), findsOneWidget);
    // Intestazione "Fonica Srl" sopra i suoi due referenti.
    final head = tester.getTopLeft(find.text('Fonica Srl').first).dy;
    expect(tester.getTopLeft(find.text('Anna Rossi')).dy, greaterThan(head));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
