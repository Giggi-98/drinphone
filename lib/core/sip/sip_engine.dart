// Porta astratta verso il motore SIP. La UI e i controller vedono solo questi
// tipi; un solo adattatore (linphone_ffi_engine.dart) conosce liblinphone.

enum SipTransport { udp, tcp, tls }

/// Pulsante Registra: `auto` = codice del PBX letto dalle API (Yeastar
/// `feature_code/get`), `pbxCode` = codice impostato a mano, `local` = file sul
/// PC (liblinphone), `off` = nessuna registrazione.
enum RecordingMode { auto, pbxCode, local, off }

class SipAccount {
  const SipAccount({
    this.id = 'main',
    this.pbxId = '',
    required this.username,
    required this.password,
    required this.domain,
    this.transport = SipTransport.udp,
    this.displayName = '',
    this.proxy = '',
    this.registrar = '',
    this.authUser = '',
    this.realm = '',
    this.expires = 0,
    this.registerEnabled = true,
    this.hideCallerId = false,
    this.voicemailCode = '',
    this.stunServer = '',
    this.ice = false,
    this.turn = false,
    this.turnUser = '',
    this.turnPassword = '',
    this.recording = RecordingMode.auto,
    this.recordCode = '',
  });

  final RecordingMode recording;

  /// Codice funzione di registrazione per `pbxCode` (es. `*1`).
  final String recordCode;

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

  // --- Avanzate (finestra account, come i softphone SIP classici).

  /// Proxy in uscita (route): `host[:porta]`; '' = diretto al registrar.
  final String proxy;

  /// Registrar se diverso dal dominio: `host[:porta]`; '' = [domain].
  final String registrar;

  /// Utente di autenticazione ("login") se diverso da [username].
  final String authUser;
  final String realm;

  /// Secondi tra le registrazioni; 0 = default del motore.
  final int expires;

  /// Account configurato ma non registrato (solo per chiamare via proxy, o sospeso).
  final bool registerEnabled;

  /// Header `Privacy: id` sulle chiamate (rispettato se PBX/trunk lo supportano).
  final bool hideCallerId;

  /// Codice casella vocale di questo account; '' = quello del profilo.
  final String voicemailCode;

  /// NAT: server STUN/TURN `host[:porta]`, ICE, TURN con credenziali.
  final String stunServer;
  final bool ice;
  final bool turn;
  final String turnUser;

  /// Segreto: solo nello storage sicuro, mai nel JSON né nei log.
  final String turnPassword;

  SipAccount copyWith({String? id, String? password, String? turnPassword}) =>
      SipAccount(
        id: id ?? this.id,
        pbxId: pbxId,
        username: username,
        password: password ?? this.password,
        domain: domain,
        transport: transport,
        displayName: displayName,
        proxy: proxy,
        registrar: registrar,
        authUser: authUser,
        realm: realm,
        expires: expires,
        registerEnabled: registerEnabled,
        hideCallerId: hideCallerId,
        voicemailCode: voicemailCode,
        stunServer: stunServer,
        ice: ice,
        turn: turn,
        turnUser: turnUser,
        turnPassword: turnPassword ?? this.turnPassword,
        recording: recording,
        recordCode: recordCode,
      );

  // Mai includere la password: questa stringa finisce nei log.
  @override
  String toString() => 'SipAccount($username@$domain, ${transport.name})';
}

/// Cifratura dei media: in liblinphone 5.5 vale per tutta l'app (non per
/// account). Valori nell'ordine di `LinphoneMediaEncryption`.
enum MediaEncryption { none, srtp, zrtp, dtls }

/// Video (Preferenze > Video): webcam e anteprima sono globali nel core.
/// Risoluzione inviata (la banda segue: più pixel, più kbit/s).
enum VideoQuality { low, medium, high }

class VideoOptions {
  const VideoOptions({
    this.enabled = true,
    this.camera = '',
    this.preview = false,
    this.quality = VideoQuality.medium,
  });

  /// 480p / 720p / 1080p.
  final VideoQuality quality;

  /// Videochiamate possibili (webcam e visualizzazione nel core).
  final bool enabled;

  /// Id della webcam ('' = predefinita).
  final String camera;

  /// Anteprima della propria webcam durante le videochiamate.
  final bool preview;
}

/// Opzioni globali delle chiamate (Preferenze > Avanzate).
class CallOptions {
  const CallOptions({
    this.encryption = MediaEncryption.none,
    this.encryptionMandatory = false,
    this.keepAlive = true,
    this.dtmfInfo = false,
    this.autoAnswer = false,
    this.autoAnswerDelaySeconds = 0,
  });
  final MediaEncryption encryption;

  /// Rifiuta le chiamate senza la cifratura scelta.
  final bool encryptionMandatory;

  /// Pacchetti periodici sulla segnalazione per tenere aperto il NAT.
  final bool keepAlive;

  /// DTMF via SIP INFO invece di RFC 2833 (nel flusso RTP).
  final bool dtmfInfo;

  /// Risposta automatica alle chiamate entranti (quando non c'è un'altra chiamata
  /// attiva o in uscita).
  final bool autoAnswer;

  /// Ritardo prima della risposta automatica, in secondi (0 = subito).
  final int autoAnswerDelaySeconds;
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
    this.video = false,
    this.remoteVideo = false,
    this.accountId = '',
    this.inConference = false,
  });

  /// Account SIP della chiamata ('' = non determinato).
  final String accountId;

  /// Fa parte della conferenza locale.
  final bool inConference;

  /// Video attivo nella chiamata (parametri correnti).
  final bool video;

  /// L'altro capo offre il video (entrante: si può rispondere in video).
  final bool remoteVideo;

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

/// Codec audio esposto dal core (ordine di preferenza e stato).
class AudioCodecInfo {
  const AudioCodecInfo({
    required this.id,
    required this.mime,
    required this.clockRate,
    required this.channels,
    required this.enabled,
  });

  /// Identificatore univoco `<mime>/<clockRate>/<channels>` (es. `opus/48000/2`).
  final String id;
  final String mime;
  final int clockRate;
  final int channels;
  final bool enabled;
}

/// Preferenza salvata su disco per un codec audio (ordine + abilitazione).
class AudioCodecPref {
  const AudioCodecPref(this.id, {this.enabled = true});
  final String id;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is AudioCodecPref && id == other.id && enabled == other.enabled;

  @override
  int get hashCode => Object.hash(id, enabled);
}

/// Dispositivo audio del sistema (id del core, es. `WASAPI: Microfono (…)`).
class SoundDevice {
  const SoundDevice(this.id, {required this.capture, required this.playback});
  final String id;
  final bool capture;
  final bool playback;

  /// Nome leggibile: senza il prefisso del driver.
  String get name => id.replaceFirst(RegExp(r'^[A-Za-z]+:\s*'), '');
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
    String? codecDir,
  });

  /// Webcam, visualizzazione e anteprima.
  Future<void> setVideo(VideoOptions options);

  /// Webcam disponibili (id del core).
  List<String> videoDevices();

  /// Codec video utilizzabili (es. VP8, H264 se OpenH264 è installato).
  List<String> videoCodecs();

  /// Finestre native (HWND) dove il core disegna il video remoto e
  /// l'anteprima; 0 = nessuna.
  Future<void> setVideoWindows({required int remote, required int preview});

  /// Anteprima della webcam fuori dalle chiamate (Preferenze > Video > Prova).
  Future<void> setCameraPreview(bool on);

  /// Accende o spegne il video in una chiamata in corso (re-INVITE).
  Future<void> setCallVideo(int id, bool on);

  /// Cartella dei file di registrazione locale ('' = nessuna).
  void setRecordingDir(String dir);

  /// Registrazione locale della chiamata (file nella cartella sopra).
  Future<void> startRecording(int id);
  Future<void> stopRecording(int id);

  /// Qualità corrente da 0 (pessima) a 5 (ottima); -1 se non disponibile.
  double callQuality(int id);

  /// Unisce tutte le chiamate in una conferenza locale (mixer di DrinPhone).
  Future<void> conferenceAll();

  /// Registra esattamente questi account (gli altri vengono rimossi). Il primo
  /// è quello predefinito.
  Future<void> setAccounts(List<SipAccount> accounts);

  /// Avvia una chiamata tramite l'account [accountId] (null = predefinito);
  /// restituisce il suo id (null se non partita).
  Future<int?> dial(String number, {String? accountId, bool video = false});
  Future<void> answer(int id, {bool video = false});
  Future<void> hangup(int id);
  Future<void> setMicMuted(bool muted);
  Future<void> sendDtmf(int id, String digit);

  /// Audio RTP ricevuto adesso nella chiamata [id], in kbit/s (null se non
  /// noto): serve a riconoscere le chiamate rimaste aperte senza l'altro capo.
  Future<double?> inboundAudioKbps(int id);

  /// Notifica quando il sistema aggiunge o rimuove un dispositivo audio.
  Stream<bool> get audioDevicesChanged => const Stream.empty();

  /// Dispositivi audio disponibili ([reload] = true rilegge il sistema).
  List<SoundDevice> soundDevices({bool reload = true});

  /// Dispositivi in uso: (microfono, altoparlante, suoneria).
  (String, String, String) audioDevices();

  /// Imposta i dispositivi; null = lascia com'è.
  Future<void> setAudioDevices({
    String? capture,
    String? playback,
    String? ringer,
  });

  /// Codec audio utilizzabili dal core, in ordine di priorità.
  List<AudioCodecInfo> audioCodecs();

  /// Imposta abilitazione e priorità dei codec audio.
  Future<void> setAudioCodecs(List<AudioCodecPref> codecs);

  /// Opzioni globali: cifratura media, keep-alive, metodo DTMF.
  Future<void> setCallOptions(CallOptions options);

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
