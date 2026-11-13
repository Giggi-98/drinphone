import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:drinphone/features/preferences/preferences_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(PhoneController, FakeSipEngine, Directory)> makePhone({
    Settings initial = const Settings(),
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('drin_s3_');
    final store = SettingsStore('${dir.path}${Platform.pathSeparator}settings.json');
    await store.save(initial);
    final engine = FakeSipEngine();
    final phone = PhoneController(
      engine,
      store,
      engineDataDir: dir.path,
      logDir: dir.path,
    );
    await phone.init();
    return (phone, engine, dir);
  }

  test('Hot-swap audio ripristina i dispositivi preferiti e aggiorna AudioSettings', () async {
    const usbMic = SoundDevice('WASAPI: Cuffia USB Mic', capture: true, playback: false);
    const usbSpk = SoundDevice('WASAPI: Cuffia USB Audio', capture: false, playback: true);
    final (phone, engine, dir) = await makePhone(
      initial: const Settings(
        audio: ('WASAPI: Cuffia USB Mic', 'WASAPI: Cuffia USB Audio', ''),
      ),
    );
    addTearDown(() async {
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });

    // All'avvio la cuffia USB è collegata, poi viene scollegata e ricollegata.
    engine.current = ('WASAPI: Microfono', 'WASAPI: Altoparlanti', '');
    engine.devices = [...engine.devices, usbMic, usbSpk];
    engine.reloadSoundCount = 0;
    engine.devicesChangedCtl.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(engine.reloadSoundCount, 0);
    expect(engine.audioDevices().$1, 'WASAPI: Cuffia USB Mic');
    expect(engine.audioDevices().$2, 'WASAPI: Cuffia USB Audio');
    expect(phone.audioDeviceRevision, 1);
  });

  test('Codec audio e risposta automatica persistono in SettingsStore', () async {
    final (phone, engine, dir) = await makePhone();
    addTearDown(() async {
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });

    await phone.setAudioCodecs(const [
      AudioCodecPref('PCMA/8000/1', enabled: true),
      AudioCodecPref('opus/48000/2', enabled: false),
    ]);
    await phone.setCallOptions(
      const CallOptions(autoAnswer: true, autoAnswerDelaySeconds: 2),
    );

    final store = SettingsStore('${dir.path}${Platform.pathSeparator}settings.json');
    final reloaded = await store.load();
    expect(reloaded.audioCodecs.length, 2);
    expect(reloaded.audioCodecs[0].id, 'PCMA/8000/1');
    expect(reloaded.audioCodecs[1].enabled, isFalse);
    expect(reloaded.callOptions.autoAnswer, isTrue);
    expect(reloaded.callOptions.autoAnswerDelaySeconds, 2);

    // Verifica riapplicazione codec a un nuovo avvio
    final engine2 = FakeSipEngine();
    final phone2 = PhoneController(
      engine2,
      store,
      engineDataDir: dir.path,
      logDir: dir.path,
    );
    await phone2.init();
    expect(engine2.audioCodecs().first.id, 'PCMA/8000/1');
    expect(
      engine2.audioCodecs().firstWhere((c) => c.id == 'opus/48000/2').enabled,
      isFalse,
    );
    await phone2.shutdown();
    phone2.dispose();
  });

  test('Risposta automatica risponde solo se non c’è già una chiamata attiva', () async {
    final (phone, engine, dir) = await makePhone(
      initial: const Settings(
        callOptions: CallOptions(autoAnswer: true, autoAnswerDelaySeconds: 0),
      ),
    );
    addTearDown(() async {
      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });

    // Prima chiamata in arrivo -> auto-risponde
    engine.callsCtl.add(
      const CallEvent(
        id: 101,
        phase: CallPhase.incoming,
        direction: CallDirection.incoming,
        remoteNumber: '302',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(engine.log, contains('answer 101'));

    // Segniamo la 101 come attiva, poi arriva la 102 -> NON deve interromperla
    engine.callsCtl.add(
      const CallEvent(
        id: 101,
        phase: CallPhase.active,
        direction: CallDirection.incoming,
        remoteNumber: '302',
      ),
    );
    engine.log.clear();
    engine.callsCtl.add(
      const CallEvent(
        id: 102,
        phase: CallPhase.incoming,
        direction: CallDirection.incoming,
        remoteNumber: '303',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(engine.log.any((x) => x.startsWith('answer 102')), isFalse);
  });

  testWidgets('PreferencesView: schede Codec audio e Risposta automatica', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final (phone, engine, dir) = await makePhone();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: PreferencesView(phone: phone, initialTab: 3),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Codec audio'), findsOneWidget);
      expect(find.textContaining('opus · 48000 Hz'), findsOneWidget);
      expect(find.text('Risposta automatica'), findsOneWidget);

      // Attiva risposta automatica dalla UI
      await tester.ensureVisible(
        find.text('Rispondi automaticamente alle chiamate'),
      );
      await tester.tap(find.text('Rispondi automaticamente alle chiamate'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      expect(phone.settings.callOptions.autoAnswer, isTrue);

      // Sposta su PCMA (secondo codec -> primo)
      final upButtons = find.byIcon(Icons.arrow_upward_rounded);
      expect(upButtons, findsNWidgets(4));
      await tester.ensureVisible(upButtons.at(1));
      await tester.tap(upButtons.at(1));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(engine.audioCodecs().first.id, 'PCMA/8000/1');

      await phone.shutdown();
      phone.dispose();
      await dir.delete(recursive: true);
    });
  });
}
