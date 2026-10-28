import 'dart:async';

import 'package:drinphone/core/sip/sip_engine.dart';

/// Motore finto per i test: registra le chiamate ricevute ed emette eventi a comando.
class FakeSipEngine implements SipEngine {
  final registrationsCtl = StreamController<RegistrationEvent>.broadcast(
    sync: true,
  );
  final callsCtl = StreamController<CallEvent>.broadcast(sync: true);
  final dialogsCtl = StreamController<BlfEvent>.broadcast(sync: true);
  final voicemailCtl = StreamController<VoicemailEvent>.broadcast(sync: true);
  final transfersCtl = StreamController<bool>.broadcast(sync: true);
  Set<String> watched = {};
  final log = <String>[];
  SipAccount? registered;

  @override
  Stream<RegistrationEvent> get registrations => registrationsCtl.stream;
  @override
  Stream<CallEvent> get calls => callsCtl.stream;
  @override
  Stream<BlfEvent> get dialogs => dialogsCtl.stream;
  @override
  Stream<VoicemailEvent> get voicemail => voicemailCtl.stream;
  @override
  Stream<bool> get transfers => transfersCtl.stream;
  @override
  Future<void> hold() async => log.add('hold');
  @override
  Future<void> resume() async => log.add('resume');
  @override
  Future<void> transfer(String number) async => log.add('transfer $number');

  @override
  Future<void> watchDialogs(Set<String> numbers) async =>
      watched = {...numbers};

  @override
  Future<String> start({
    required String dataDir,
    required String logDir,
    required bool debug,
  }) async {
    log.add('start debug=$debug');
    return 'fake';
  }

  @override
  Future<void> register(SipAccount account) async {
    registered = account;
    log.add('register ${account.username}@${account.domain}');
  }

  @override
  Future<void> unregister() async => log.add('unregister');
  @override
  Future<void> dial(String number) async => log.add('dial $number');
  @override
  Future<void> answer() async => log.add('answer');
  @override
  Future<void> hangup() async => log.add('hangup');
  @override
  Future<void> setMicMuted(bool muted) async => log.add('mute $muted');
  @override
  Future<void> sendDtmf(String digit) async => log.add('dtmf $digit');
  @override
  Future<void> stop() async => log.add('stop');
}
