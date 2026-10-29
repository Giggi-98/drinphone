import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/core/call_history.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

void main() {
  late Directory tmp;
  late FakeSipEngine engine;
  late PhoneController phone;
  late CallHistoryStore history;
  var attention = 0;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('drinphone_hist');
    final sep = Platform.pathSeparator;
    engine = FakeSipEngine();
    history = CallHistoryStore('${tmp.path}${sep}history.json');
    final settings = SettingsStore('${tmp.path}${sep}s.json');
    await settings.save(
      const Settings(
        extensions: [
          Extension('Paolo Guerra', '301'),
          Extension('Sala Riunioni', '210'),
        ],
      ),
    );
    attention = 0;
    phone = PhoneController(
      engine,
      settings,
      engineDataDir: tmp.path,
      logDir: tmp.path,
      historyStoreFor: (_) => history,
      onIncomingCall: () => attention++,
    );
    await phone.init();
  });

  tearDown(() async {
    await phone.historySaved;
    await tmp.delete(recursive: true);
  });

  void ev(CallPhase phase, CallDirection dir, String n, [String name = '']) =>
      engine.callsCtl.add(
        CallEvent(
          phase: phase,
          direction: dir,
          remoteNumber: n,
          remoteName: name,
        ),
      );

  test(
    'ricerca: popup con interni per nome o numero, prima a inizio parola',
    () {
      expect(phone.search('paolo').map((h) => h.number), ['301']);
      expect(phone.search('21').map((h) => h.number), ['210']);
      expect(phone.search('rIUn').single.name, 'Sala Riunioni');
      expect(phone.search(''), isEmpty);
    },
  );

  test(
    'entrante non risposta = persa; richiamo attenzione una volta',
    () async {
      ev(CallPhase.incoming, CallDirection.incoming, '350', 'Jack');
      ev(CallPhase.incoming, CallDirection.incoming, '350', 'Jack');
      ev(CallPhase.ended, CallDirection.incoming, '350');
      expect(attention, 1);
      final r = phone.history.single;
      expect((r.number, r.name, r.missed, r.seconds), ('350', 'Jack', true, 0));
      // Persistita su file e riletta.
      await phone.historySaved;
      expect((await history.load()).single.missed, isTrue);
    },
  );

  test('uscente risposta: non persa, più recenti in cima', () {
    ev(CallPhase.outgoing, CallDirection.outgoing, '301');
    ev(CallPhase.active, CallDirection.outgoing, '301');
    ev(CallPhase.ended, CallDirection.outgoing, '301');
    ev(CallPhase.outgoing, CallDirection.outgoing, '210');
    ev(CallPhase.error, CallDirection.outgoing, '210');
    expect(phone.history.map((r) => (r.number, r.answered)), [
      ('210', false),
      ('301', true),
    ]);
    expect(phone.history.any((r) => r.missed), isFalse);
    expect(attention, 0);
  });

  test('sameNumber: prefissi e simboli sì, interni brevi mai per suffisso', () {
    expect(
      PhoneController.sameNumber('+39 02 5550 1234', '0255501234'),
      isTrue,
    );
    expect(
      PhoneController.sameNumber('0039 333 1234567', '3331234567'),
      isTrue,
    );
    expect(PhoneController.sameNumber('234', '0255501234'), isFalse);
    expect(PhoneController.sameNumber('201', '201'), isTrue);
    expect(PhoneController.sameNumber('', '201'), isFalse);
  });

  CallEvent ce(int id, CallPhase ph, CallDirection d, String n) =>
      CallEvent(id: id, phase: ph, direction: d, remoteNumber: n);

  test('attesa/riprendi e trasferimento cieco con esito', () async {
    engine.registrationsCtl.add(const RegistrationEvent(RegistrationStatus.ok));
    engine.callsCtl.add(ce(1, CallPhase.active, CallDirection.outgoing, '301'));
    await phone.toggleHold();
    expect(engine.log.last, 'hold 1');
    engine.callsCtl.add(ce(1, CallPhase.paused, CallDirection.outgoing, '301'));
    expect(phone.onHold, isTrue);
    await phone.toggleHold();
    expect(engine.log.last, 'resume 1');
    engine.callsCtl.add(ce(1, CallPhase.active, CallDirection.outgoing, '301'));
    await phone.transfer(' 210 ');
    expect(engine.log.last, 'transfer 1 210');
    engine.transfersCtl.add(true);
    expect(phone.notice, 'Chiamata trasferita');
    engine.callsCtl.add(ce(1, CallPhase.ended, CallDirection.outgoing, '301'));
    expect((phone.call, phone.calls.isEmpty), (null, true));
  });

  test(
    'avviso di chiamata: rispondere mette in attesa la conversazione',
    () async {
      engine.callsCtl.add(
        ce(1, CallPhase.active, CallDirection.outgoing, '301'),
      );
      engine.callsCtl.add(
        ce(2, CallPhase.incoming, CallDirection.incoming, '350'),
      );
      expect(phone.call!.id, 1); // la conversazione resta in primo piano
      expect(phone.otherCalls.single.id, 2);
      expect(attention, 1);
      await phone.answer(2);
      expect(engine.log.sublist(engine.log.length - 2), ['hold 1', 'answer 2']);
      engine.callsCtl.add(
        ce(1, CallPhase.paused, CallDirection.outgoing, '301'),
      );
      engine.callsCtl.add(
        ce(2, CallPhase.active, CallDirection.incoming, '350'),
      );
      expect(phone.call!.id, 2);
      await phone.resumeCall(1); // scambio
      expect(engine.log.sublist(engine.log.length - 2), ['hold 2', 'resume 1']);
      expect(phone.history, isEmpty); // nessuna chiamata ancora chiusa
    },
  );

  test('trasferimento assistito: consulta, poi completa', () async {
    engine.registrationsCtl.add(const RegistrationEvent(RegistrationStatus.ok));
    engine.callsCtl.add(ce(1, CallPhase.active, CallDirection.incoming, '350'));
    expect(phone.canDial, isFalse); // c'è già una chiamata
    await phone.consult('210');
    expect(engine.log.sublist(engine.log.length - 2), ['hold 1', 'dial 210']);
    const to = 100; // primo id restituito da FakeSipEngine.dial
    engine.callsCtl.add(ce(1, CallPhase.paused, CallDirection.incoming, '350'));
    engine.callsCtl.add(
      ce(to, CallPhase.outgoing, CallDirection.outgoing, '210'),
    );
    expect(
      phone.canCompleteTransfer,
      isFalse,
    ); // il destinatario non ha risposto
    engine.callsCtl.add(
      ce(to, CallPhase.active, CallDirection.outgoing, '210'),
    );
    expect(phone.canCompleteTransfer, isTrue);
    await phone.completeTransfer();
    expect(engine.log.last, 'attended 1 $to');
    engine.callsCtl.add(ce(1, CallPhase.ended, CallDirection.incoming, '350'));
    engine.callsCtl.add(ce(to, CallPhase.ended, CallDirection.outgoing, '210'));
    expect(phone.calls, isEmpty);
    expect(phone.history.length, 2);
  });

  test('preferiti: stella, filtro e salvataggio', () async {
    final sala = phone.allExtensions.firstWhere((e) => e.number == '210');
    expect(phone.isFavorite(sala), isFalse);
    await phone.toggleFavorite(sala);
    expect(phone.isFavorite(sala), isTrue);
    phone.selectGroup(PhoneController.favoritesGroup);
    expect(phone.visibleExtensions.map((e) => e.number), ['210']);
    final saved = await SettingsStore(
      '${tmp.path}${Platform.pathSeparator}s.json',
    ).load();
    expect(saved.favorites, [':210']);
    await phone.toggleFavorite(sala);
    expect(phone.visibleExtensions, isEmpty);
  });

  test(
    'badge: si spengono entrando nella sezione, solo le novità li riaccendono',
    () async {
      ev(CallPhase.incoming, CallDirection.incoming, '350');
      ev(CallPhase.ended, CallDirection.incoming, '350');
      expect(phone.missedUnseen, 1);
      await phone.markHistorySeen();
      expect(phone.missedUnseen, 0);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      ev(CallPhase.incoming, CallDirection.incoming, '301');
      ev(CallPhase.ended, CallDirection.incoming, '301');
      expect(phone.missedUnseen, 1);

      // Casella vocale senza API: conteggio MWI.
      engine.voicemailCtl.add(const VoicemailEvent(2, 0));
      expect(phone.voicemailUnseen, 2);
      await phone.markVoicemailSeen();
      expect(phone.voicemailUnseen, 0);
      engine.voicemailCtl.add(const VoicemailEvent(3, 0));
      expect(phone.voicemailUnseen, 1);
    },
  );

  test(
    'video: videochiamata, rispondi in video, spento = solo audio, anteprima',
    () async {
      await phone.saveAccount(
        const SipAccount(username: '305', password: 'p', domain: 'pbx.test'),
      );
      engine.registrationsCtl.add(
        const RegistrationEvent(RegistrationStatus.ok),
      );
      await phone.dial('301', video: true);
      expect(engine.log.last, 'dial 301 video');
      engine.callsCtl.add(
        const CallEvent(
          id: 7,
          phase: CallPhase.incoming,
          direction: CallDirection.incoming,
          remoteNumber: '350',
          remoteVideo: true,
        ),
      );
      await phone.answer(7, true);
      expect(engine.log.last, 'answer 7 video');

      // Anteprima: la finestra arriva al motore solo se attiva in Preferenze.
      await phone.setVideoWindow(remote: 11, preview: 22);
      expect(engine.windows, (11, 0));
      await phone.setVideoOptions(const VideoOptions(preview: true));
      expect(engine.windows, (11, 22));
      expect(engine.video.preview, isTrue);

      await phone.setVideoOptions(const VideoOptions(enabled: false));
      expect(phone.videoEnabled, isFalse);
      engine.callsCtl.add(
        const CallEvent(
          id: 7,
          phase: CallPhase.ended,
          direction: CallDirection.incoming,
          remoteNumber: '350',
        ),
      );
      await phone.dial('301', video: true);
      expect(engine.log.last, 'dial 301');
    },
  );

  test('finestra di chiamata: registra (codice/locale/no), note nel registro, conferenza', () async {
    CallEvent ev2(
      int id,
      CallPhase ph, {
      String name = '',
      bool video = false,
    }) => CallEvent(
      id: id,
      phase: ph,
      direction: CallDirection.outgoing,
      remoteNumber: '301',
      remoteName: name,
      video: video,
      accountId: 'main',
    );
    await phone.saveAccount(
      const SipAccount(
        username: '305',
        password: 'p',
        domain: 'pbx.test',
        recording: RecordingMode.pbxCode,
        recordCode: '*1',
      ),
    );
    engine.callsCtl.add(ev2(1, CallPhase.active, name: 'Paolo', video: true));
    // Evento successivo senza nome: il video non si perde.
    engine.callsCtl.add(ev2(1, CallPhase.active, video: true));
    expect(phone.call!.video, isTrue);
    expect(phone.call!.remoteName, 'Paolo');

    expect(phone.canRecord(phone.call!), isTrue);
    await phone.toggleRecording();
    expect(engine.log.where((l) => l.startsWith('dtmf')), isNotEmpty);
    expect(phone.isRecording(1), isTrue);

    phone.setNote(1, '  Richiamare per il preventivo  ');
    engine.callsCtl.add(ev2(1, CallPhase.ended));
    expect(phone.history.first.note, 'Richiamare per il preventivo');

    // Locale: avvio e stop del file; disattivata: niente pulsante.
    await phone.saveAccount(
      const SipAccount(
        username: '305',
        password: 'p',
        domain: 'pbx.test',
        recording: RecordingMode.local,
      ),
    );
    engine.callsCtl.add(ev2(2, CallPhase.active));
    expect(phone.canRecord(phone.call!), phone.recordingsDir.isNotEmpty);
    await phone.saveAccount(
      const SipAccount(
        username: '305',
        password: 'p',
        domain: 'pbx.test',
        recording: RecordingMode.off,
      ),
    );
    expect(phone.canRecord(phone.call!), isFalse);

    // Conferenza: due chiamate stabilite si uniscono.
    engine.callsCtl.add(ev2(3, CallPhase.paused));
    expect(phone.canMergeConference, isTrue);
    await phone.mergeConference();
    expect(engine.log.last, 'conference');
  });
}
