// Porta astratta verso il motore SIP. La UI e i controller vedono solo questi
// tipi; un solo adattatore (linphone_ffi_engine.dart) conosce liblinphone.

enum SipTransport { udp, tcp, tls }

class SipAccount {
  const SipAccount({
    required this.username,
    required this.password,
    required this.domain,
    this.transport = SipTransport.udp,
    this.displayName = '',
  });

  final String username;
  final String password;

  /// Host del PBX, opzionalmente con porta: `pbx.example.it` o `10.0.0.5:5060`.
  final String domain;
  final SipTransport transport;
  final String displayName;

  // Mai includere la password: questa stringa finisce nei log.
  @override
  String toString() => 'SipAccount($username@$domain, ${transport.name})';
}

enum RegistrationStatus { none, progress, ok, cleared, failed }

class RegistrationEvent {
  const RegistrationEvent(this.status, [this.message = '']);
  final RegistrationStatus status;
  final String message;
}

enum CallDirection { incoming, outgoing }

enum CallPhase { incoming, outgoing, active, paused, ended, error }

class CallEvent {
  const CallEvent({
    required this.phase,
    required this.direction,
    required this.remoteNumber,
    this.remoteName = '',
    this.message = '',
  });

  final CallPhase phase;
  final CallDirection direction;
  final String remoteNumber;
  final String remoteName;
  final String message;
}

abstract class SipEngine {
  Stream<RegistrationEvent> get registrations;
  Stream<CallEvent> get calls;

  /// Avvia il motore. [dataDir] è privata dell'app; [debug] abilita il log
  /// completo del motore (SIP incluso) su file in `logDir`.
  Future<String> start({
    required String dataDir,
    required String logDir,
    required bool debug,
  });
  Future<void> register(SipAccount account);
  Future<void> unregister();

  Future<void> dial(String number);
  Future<void> answer();
  Future<void> hangup();
  Future<void> setMicMuted(bool muted);
  Future<void> sendDtmf(String digit);

  Future<void> stop();
}
