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
  Future<void> hold(int id) async => log.add('hold $id');
  @override
  Future<void> resume(int id) async => log.add('resume $id');
  @override
  Future<void> transfer(int id, String number) async =>
      log.add('transfer $id $number');
  @override
  Future<void> transferAttended(int id, int toId) async =>
      log.add('attended $id $toId');

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

  List<SipAccount> accounts = [];
  @override
  Future<void> setAccounts(List<SipAccount> list) async {
    accounts = list;
    registered = list.firstOrNull;
    log.add(
      'accounts ${[for (final a in list) '${a.username}@${a.domain}'].join(',')}',
    );
  }

  var _nextId = 100;
  @override
  Future<int?> dial(String number, {String? accountId}) async {
    log.add(accountId == null ? 'dial $number' : 'dial $number via $accountId');
    return _nextId++;
  }

  @override
  Future<void> answer(int id) async => log.add('answer $id');
  @override
  Future<void> hangup(int id) async => log.add('hangup $id');
  @override
  Future<void> setMicMuted(bool muted) async => log.add('mute $muted');
  @override
  Future<void> sendDtmf(int id, String digit) async =>
      log.add('dtmf $id $digit');
  @override
  Future<void> stop() async => log.add('stop');
}
