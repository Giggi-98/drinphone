// Porta astratta verso il motore SIP. La UI e i controller vedono solo questi
// tipi; un solo adattatore (linphone_ffi_engine.dart) conosce liblinphone.

enum SipTransport { udp, tcp, tls }

class SipAccount {
  const SipAccount({
    this.id = 'main',
    this.pbxId = '',
    required this.username,
    required this.password,
    required this.domain,
    this.transport = SipTransport.udp,
    this.displayName = '',
  });

  /// Identificativo locale dell'account (il primo è `main`).
  final String id;

  /// Connessione API del PBX su cui è registrato ('' = nessuna).
  final String pbxId;
  final String username;
  final String password;

  String get host => domain.split(':').first;

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
  const RegistrationEvent(
    this.status, [
    this.message = '',
    this.accountId = 'main',
  ]);
  final RegistrationStatus status;
  final String message;
  final String accountId;
}

enum CallDirection { incoming, outgoing }

enum CallPhase { incoming, outgoing, active, paused, ended, error }

class CallEvent {
  const CallEvent({
    this.id = 0,
    required this.phase,
    required this.direction,
    required this.remoteNumber,
    this.remoteName = '',
    this.message = '',
  });

  /// Identifica la chiamata finché esiste (più chiamate contemporanee).
  final int id;
  final CallPhase phase;
  final CallDirection direction;
  final String remoteNumber;
  final String remoteName;
  final String message;
}

/// Stato linea di un interno via SIP BLF (dialog event package, RFC 4235).
/// `unknown` finché la subscription non è attiva o se il PBX la rifiuta:
/// mai verde per deduzione (docs/sip-e-blf.md).
/// `offline`: interno non registrato (Yeastar invia `<state>unregister</state>`).
enum BlfStatus { unknown, offline, idle, ringing, busy }

class BlfEvent {
  const BlfEvent(this.number, this.status, [this.reason = '']);
  final String number;
  final BlfStatus status;
  final String reason;
}

/// Casella vocale (SIP MWI, message-summary): messaggi nuovi e già ascoltati.
class VoicemailEvent {
  const VoicemailEvent(this.newMessages, this.oldMessages);
  final int newMessages;
  final int oldMessages;
}

abstract class SipEngine {
  Stream<RegistrationEvent> get registrations;
  Stream<VoicemailEvent> get voicemail;

  /// Esito di un trasferimento: true = accettato dal destinatario.
  Stream<bool> get transfers;
  Stream<CallEvent> get calls;
  Stream<BlfEvent> get dialogs;

  /// Avvia il motore. [dataDir] è privata dell'app; [debug] abilita il log
  /// completo del motore (SIP incluso) su file in `logDir`.
  Future<String> start({
    required String dataDir,
    required String logDir,
    required bool debug,
  });

  /// Registra esattamente questi account (gli altri vengono rimossi). Il primo
  /// è quello predefinito.
  Future<void> setAccounts(List<SipAccount> accounts);

  /// Avvia una chiamata tramite l'account [accountId] (null = predefinito);
  /// restituisce il suo id (null se non partita).
  Future<int?> dial(String number, {String? accountId});
  Future<void> answer(int id);
  Future<void> hangup(int id);
  Future<void> setMicMuted(bool muted);
  Future<void> sendDtmf(int id, String digit);

  /// Attesa / ripresa (re-INVITE sendonly/sendrecv).
  Future<void> hold(int id);
  Future<void> resume(int id);

  /// Trasferimento cieco (REFER, RFC 3515) a [number].
  Future<void> transfer(int id, String number);

  /// Trasferimento assistito: collega [id] (in attesa) con [toId] (consultazione),
  /// REFER con Replaces (RFC 3891).
  Future<void> transferAttended(int id, int toId);

  /// Sostituisce l'insieme degli interni osservati via SUBSCRIBE `dialog`.
  /// Ogni voce è `interno@host`: il core la instrada sull'account di quel host.
  /// Le subscription non più presenti vengono chiuse.
  Future<void> watchDialogs(Set<String> targets);

  Future<void> stop();
}
