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
  final devicesChangedCtl = StreamController<bool>.broadcast(sync: true);
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
  Stream<bool> get audioDevicesChanged => devicesChangedCtl.stream;
  List<AudioCodecInfo> audioCodecList = const [
    AudioCodecInfo(
      id: 'opus/48000/2',
      mime: 'opus',
      clockRate: 48000,
      channels: 2,
      enabled: true,
    ),
    AudioCodecInfo(
      id: 'PCMA/8000/1',
      mime: 'PCMA',
      clockRate: 8000,
      channels: 1,
      enabled: true,
    ),
    AudioCodecInfo(
      id: 'PCMU/8000/1',
      mime: 'PCMU',
      clockRate: 8000,
      channels: 1,
      enabled: true,
    ),
    AudioCodecInfo(
      id: 'G722/8000/1',
      mime: 'G722',
      clockRate: 8000,
      channels: 1,
      enabled: true,
    ),
  ];
  @override
  List<AudioCodecInfo> audioCodecs() => audioCodecList;
  @override
  Future<void> setAudioCodecs(List<AudioCodecPref> codecs) async {
    final byId = {for (final c in audioCodecList) c.id: c};
    final out = <AudioCodecInfo>[];
    final seen = <String>{};
    for (final p in codecs) {
      final c = byId[p.id];
      if (c == null || !seen.add(c.id)) continue;
      out.add(
        AudioCodecInfo(
          id: c.id,
          mime: c.mime,
          clockRate: c.clockRate,
          channels: c.channels,
          enabled: p.enabled,
        ),
      );
    }
    for (final c in audioCodecList) {
      if (seen.add(c.id)) out.add(c);
    }
    audioCodecList = out;
    log.add('codecs ${codecs.map((c) => '${c.id}:${c.enabled}').join(',')}');
  }
  var devices = const [
    SoundDevice('WASAPI: Microfono', capture: true, playback: false),
    SoundDevice('WASAPI: Altoparlanti', capture: false, playback: true),
  ];
  (String, String, String) current = ('', '', '');
  @override
  List<SoundDevice> soundDevices() => devices;
  @override
  (String, String, String) audioDevices() => current;
  @override
  Future<void> setAudioDevices({
    String? capture,
    String? playback,
    String? ringer,
  }) async {
    current = (
      capture ?? current.$1,
      playback ?? current.$2,
      ringer ?? current.$3,
    );
    log.add('audio ${current.$1}|${current.$2}|${current.$3}');
  }

  CallOptions options = const CallOptions();
  @override
  Future<void> setCallOptions(CallOptions o) async {
    options = o;
    log.add('options ${o.encryption.name}');
  }

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
    String? codecDir,
  }) async {
    log.add('start debug=$debug');
    this.codecDir = codecDir;
    return 'fake';
  }

  String? codecDir;
  VideoOptions video = const VideoOptions();
  List<String> codecs = const ['VP8'];
  (int, int) windows = (0, 0);

  @override
  Future<void> setVideo(VideoOptions o) async => video = o;
  @override
  List<String> videoDevices() => const ['Webcam integrata'];
  @override
  List<String> videoCodecs() => codecs;
  @override
  Future<void> setVideoWindows({
    required int remote,
    required int preview,
  }) async => windows = (remote, preview);
  @override
  Future<void> setCallVideo(int id, bool on) async => log.add('video $id $on');
  String recordingDir = '';
  @override
  void setRecordingDir(String dir) => recordingDir = dir;
  @override
  Future<void> startRecording(int id) async => log.add('record $id on');
  @override
  Future<void> stopRecording(int id) async => log.add('record $id off');
  @override
  double callQuality(int id) => 4.5;
  @override
  Future<void> conferenceAll() async => log.add('conference');
  bool cameraPreview = false;
  @override
  Future<void> setCameraPreview(bool on) async => cameraPreview = on;

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
  Future<int?> dial(
    String number, {
    String? accountId,
    bool video = false,
  }) async {
    log.add(
      '${accountId == null ? 'dial $number' : 'dial $number via $accountId'}'
      '${video ? ' video' : ''}',
    );
    return _nextId++;
  }

  @override
  Future<void> answer(int id, {bool video = false}) async =>
      log.add('answer $id${video ? ' video' : ''}');
  @override
  Future<void> hangup(int id) async => log.add('hangup $id');

  /// Audio in arrivo simulato (kbit/s); null = non noto.
  double? inboundKbps = 80;

  @override
  Future<double?> inboundAudioKbps(int id) async => inboundKbps;
  @override
  Future<void> setMicMuted(bool muted) async => log.add('mute $muted');
  @override
  Future<void> sendDtmf(int id, String digit) async =>
      log.add('dtmf $id $digit');
  @override
  Future<void> stop() async => log.add('stop');
}
