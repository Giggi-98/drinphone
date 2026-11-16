// Lettore audio in-app (casella vocale e registrazioni CDR) su Windows tramite
// winmm.dll (`mciSendStringW`), senza dipendenze esterne. Su altre piattaforme o
// nei test si può iniettare un [AudioBackend] finto.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _MciSendNative = Int32 Function(
  Pointer<Utf16> lpszCommand,
  Pointer<Utf16> lpszReturnString,
  Uint32 cchReturn,
  Pointer<Void> hwndCallback,
);
typedef _MciSendDart = int Function(
  Pointer<Utf16> lpszCommand,
  Pointer<Utf16> lpszReturnString,
  int cchReturn,
  Pointer<Void> hwndCallback,
);

/// Interfaccia astratta del motore audio (Win32 MCI in produzione, finta nei test).
abstract class AudioBackend {
  Future<int> open(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(int ms);
  Future<int> positionMs();
  Future<String> mode();
  Future<void> close();
}

/// Implementazione Windows tramite `winmm.dll` (`mciSendStringW`): supporta
/// nativamente `.wav` e `.mp3` restituiti da Yeastar P-Series.
class WindowsMciBackend implements AudioBackend {
  DynamicLibrary? _winmm;
  _MciSendDart? _mci;
  int _seq = 0;
  String? _alias;

  _MciSendDart get _send {
    _winmm ??= DynamicLibrary.open('winmm.dll');
    return _mci ??= _winmm!.lookupFunction<_MciSendNative, _MciSendDart>(
      'mciSendStringW',
    );
  }

  String _exec(String command, {bool ignoreError = false}) {
    if (!Platform.isWindows) {
      if (ignoreError) return '';
      throw UnsupportedError('Riproduzione audio supportata solo su Windows');
    }
    return using((a) {
      const bufChars = 256;
      final cmd = command.toNativeUtf16(allocator: a);
      final out = a<Uint16>(bufChars).cast<Utf16>();
      final err = _send(cmd, out, bufChars, nullptr);
      if (err != 0 && !ignoreError) {
        throw StateError('Errore riproduzione audio (MCI $err)');
      }
      return err == 0 ? out.toDartString().trim() : '';
    });
  }

  @override
  Future<int> open(String path) async {
    await close();
    if (path.contains('"') || path.contains('\n') || path.contains('\r')) {
      throw ArgumentError('Percorso audio non valido');
    }
    final alias = 'drin_audio_${++_seq}';
    _exec('open "$path" alias $alias');
    _alias = alias;
    _exec('set $alias time format milliseconds', ignoreError: true);
    final rawLen = _exec('status $alias length', ignoreError: true);
    return int.tryParse(rawLen) ?? 0;
  }

  @override
  Future<void> play() async {
    final a = _alias;
    if (a != null) _exec('play $a from 0');
  }

  @override
  Future<void> pause() async {
    final a = _alias;
    if (a != null) _exec('pause $a', ignoreError: true);
  }

  @override
  Future<void> resume() async {
    final a = _alias;
    if (a != null) _exec('resume $a', ignoreError: true);
  }

  @override
  Future<void> seek(int ms) async {
    final a = _alias;
    if (a == null) return;
    final currentMode = await mode();
    _exec('seek $a to ${ms < 0 ? 0 : ms}', ignoreError: true);
    if (currentMode == 'playing') {
      _exec('play $a', ignoreError: true);
    }
  }

  @override
  Future<int> positionMs() async {
    final a = _alias;
    if (a == null) return 0;
    final raw = _exec('status $a position', ignoreError: true);
    return int.tryParse(raw) ?? 0;
  }

  @override
  Future<String> mode() async {
    final a = _alias;
    if (a == null) return 'stopped';
    return _exec('status $a mode', ignoreError: true).toLowerCase();
  }

  @override
  Future<void> close() async {
    final a = _alias;
    _alias = null;
    if (a != null) {
      _exec('stop $a', ignoreError: true);
      _exec('close $a', ignoreError: true);
    }
  }
}

enum PlaybackState { idle, loading, playing, paused }

/// Controller condiviso per ascoltare messaggi vocali e registrazioni CDR.
class InAppAudioPlayer extends ChangeNotifier {
  InAppAudioPlayer({AudioBackend? backend})
    : _backend = backend ?? WindowsMciBackend();

  final AudioBackend _backend;
  final Map<String, File> _cachedFiles = {};
  Timer? _poll;

  String? activeKey;
  PlaybackState state = PlaybackState.idle;
  int positionMs = 0;
  int durationMs = 0;
  String? error;

  bool get isLoading => state == PlaybackState.loading;
  bool get isPlaying => state == PlaybackState.playing;
  bool get isPaused => state == PlaybackState.paused;

  bool isActive(String key) => activeKey == key && state != PlaybackState.idle;

  Future<void> togglePlay(
    String key,
    Future<File> Function() resolveFile, {
    bool cacheFile = true,
  }) async {
    if (activeKey == key) {
      if (state == PlaybackState.playing) {
        await _backend.pause();
        state = PlaybackState.paused;
        _poll?.cancel();
        notifyListeners();
        return;
      }
      if (state == PlaybackState.paused) {
        await _backend.resume();
        state = PlaybackState.playing;
        _startPolling();
        notifyListeners();
        return;
      }
      if (state == PlaybackState.loading) return;
    }

    await _stopInternal(notify: false);
    activeKey = key;
    error = null;
    state = PlaybackState.loading;
    positionMs = 0;
    durationMs = 0;
    notifyListeners();

    try {
      var file = cacheFile ? _cachedFiles[key] : null;
      if (file == null || !file.existsSync()) {
        file = await resolveFile();
        if (cacheFile) _cachedFiles[key] = file;
      }
      if (activeKey != key) return;
      final len = await _backend.open(file.path);
      if (activeKey != key) {
        await _backend.close();
        return;
      }
      durationMs = len;
      await _backend.play();
      state = PlaybackState.playing;
      _startPolling();
      notifyListeners();
    } catch (e) {
      error = e is Exception || e is Error ? '$e' : 'Errore audio';
      state = PlaybackState.idle;
      activeKey = null;
      _poll?.cancel();
      notifyListeners();
    }
  }

  Future<void> seek(int ms) async {
    if (activeKey == null ||
        (state != PlaybackState.playing && state != PlaybackState.paused)) {
      return;
    }
    final target = ms.clamp(0, durationMs > 0 ? durationMs : ms);
    await _backend.seek(target);
    positionMs = target;
    notifyListeners();
  }

  Future<void> stop() => _stopInternal(notify: true);

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  Future<void> _tick() async {
    if (state != PlaybackState.playing) return;
    try {
      final m = await _backend.mode();
      final pos = await _backend.positionMs();
      if (state != PlaybackState.playing) return;
      if (m == 'stopped') {
        await _stopInternal(notify: true);
        return;
      }
      if (pos != positionMs) {
        positionMs = pos;
        notifyListeners();
      }
    } catch (_) {
      await _stopInternal(notify: true);
    }
  }

  Future<void> _stopInternal({required bool notify}) async {
    _poll?.cancel();
    _poll = null;
    await _backend.close();
    state = PlaybackState.idle;
    activeKey = null;
    positionMs = 0;
    durationMs = 0;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_backend.close());
    for (final f in _cachedFiles.values) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _cachedFiles.clear();
    super.dispose();
  }
}

/// Backend per cattura breve microfono ("Echo Test" in Preferenze > Audio).
abstract class EchoRecorderBackend {
  Future<void> startRecording();
  Future<void> stopAndSave(String outputPath);
  Future<void> cancel();
}

/// Implementazione Windows tramite `winmm.dll` MCI (`waveaudio`).
class WindowsMciEchoRecorder implements EchoRecorderBackend {
  DynamicLibrary? _winmm;
  _MciSendDart? _mci;
  int _seq = 0;
  String? _alias;

  _MciSendDart get _send {
    _winmm ??= DynamicLibrary.open('winmm.dll');
    return _mci ??= _winmm!.lookupFunction<_MciSendNative, _MciSendDart>(
      'mciSendStringW',
    );
  }

  void _exec(String command, {bool ignoreError = false}) {
    if (!Platform.isWindows) {
      if (ignoreError) return;
      throw UnsupportedError('Prova microfono supportata solo su Windows');
    }
    using((a) {
      const bufChars = 256;
      final cmd = command.toNativeUtf16(allocator: a);
      final out = a<Uint16>(bufChars).cast<Utf16>();
      final err = _send(cmd, out, bufChars, nullptr);
      if (err != 0 && !ignoreError) {
        throw StateError('Errore registrazione microfono (MCI $err)');
      }
    });
  }

  @override
  Future<void> startRecording() async {
    await cancel();
    final alias = 'drin_echo_${++_seq}';
    _exec('open new type waveaudio alias $alias');
    _alias = alias;
    _exec(
      'set $alias time format ms bitspersample 16 channels 1 samplespersec 16000',
      ignoreError: true,
    );
    _exec('record $alias');
  }

  @override
  Future<void> stopAndSave(String outputPath) async {
    final a = _alias;
    _alias = null;
    if (a == null) return;
    if (outputPath.contains('"') ||
        outputPath.contains('\n') ||
        outputPath.contains('\r')) {
      _exec('close $a', ignoreError: true);
      throw ArgumentError('Percorso file audio non valido');
    }
    try {
      _exec('stop $a', ignoreError: true);
      _exec('save $a "$outputPath"');
    } finally {
      _exec('close $a', ignoreError: true);
    }
  }

  @override
  Future<void> cancel() async {
    final a = _alias;
    _alias = null;
    if (a != null) {
      _exec('stop $a', ignoreError: true);
      _exec('close $a', ignoreError: true);
    }
  }
}

enum EchoTestPhase { idle, recording, playing }

/// Registra fino a [maxSeconds] secondi dal microfono e li riproduce subito
/// tramite [InAppAudioPlayer] per verificare microfono e cuffia.
class MicEchoTester extends ChangeNotifier {
  MicEchoTester(
    this.player, {
    EchoRecorderBackend? backend,
    String? tempDir,
    this.maxSeconds = 5,
  }) : _backend = backend ?? WindowsMciEchoRecorder(),
       _tempDir = tempDir ?? Directory.systemTemp.path;

  final InAppAudioPlayer player;
  final EchoRecorderBackend _backend;
  final String _tempDir;
  final int maxSeconds;

  EchoTestPhase phase = EchoTestPhase.idle;
  int secondsLeft = 0;
  String? error;

  Timer? _countdown;
  File? _tempFile;
  VoidCallback? _playerListener;

  Future<void> start() async {
    if (phase != EchoTestPhase.idle) return;
    error = null;
    try {
      await player.stop();
      await _backend.startRecording();
      phase = EchoTestPhase.recording;
      secondsLeft = maxSeconds;
      notifyListeners();
      _countdown?.cancel();
      _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
        if (phase != EchoTestPhase.recording) return;
        secondsLeft--;
        if (secondsLeft <= 0) {
          unawaited(finishRecordingAndPlay());
        } else {
          notifyListeners();
        }
      });
    } catch (e) {
      error = e is Exception || e is Error ? '$e' : 'Errore microfono';
      phase = EchoTestPhase.idle;
      await _backend.cancel();
      notifyListeners();
    }
  }

  Future<void> finishRecordingAndPlay() async {
    if (phase != EchoTestPhase.recording) return;
    _countdown?.cancel();
    _countdown = null;
    try {
      final path =
          '$_tempDir${Platform.pathSeparator}drinphone-echo-${DateTime.now().millisecondsSinceEpoch}.wav';
      final f = File(path);
      _deleteTemp();
      _tempFile = f;
      await _backend.stopAndSave(path);
      phase = EchoTestPhase.playing;
      secondsLeft = 0;
      notifyListeners();
      _detachPlayer();
      _playerListener = () {
        if (phase == EchoTestPhase.playing &&
            player.state == PlaybackState.idle &&
            player.activeKey != 'echo_test') {
          _detachPlayer();
          phase = EchoTestPhase.idle;
          error = player.error;
          _deleteTemp();
          notifyListeners();
        }
      };
      player.addListener(_playerListener!);
      await player.togglePlay('echo_test', () async => f, cacheFile: false);
      if (player.state == PlaybackState.idle && phase == EchoTestPhase.playing) {
        _detachPlayer();
        phase = EchoTestPhase.idle;
        error = player.error;
        _deleteTemp();
        notifyListeners();
      }
    } catch (e) {
      _detachPlayer();
      error = e is Exception || e is Error ? '$e' : 'Errore audio';
      phase = EchoTestPhase.idle;
      _deleteTemp();
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _countdown?.cancel();
    _countdown = null;
    _detachPlayer();
    await _backend.cancel();
    if (player.activeKey == 'echo_test') {
      await player.stop();
    }
    phase = EchoTestPhase.idle;
    secondsLeft = 0;
    _deleteTemp();
    notifyListeners();
  }

  void _detachPlayer() {
    if (_playerListener != null) {
      player.removeListener(_playerListener!);
      _playerListener = null;
    }
  }

  void _deleteTemp() {
    final f = _tempFile;
    _tempFile = null;
    if (f != null) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _detachPlayer();
    unawaited(_backend.cancel());
    _deleteTemp();
    super.dispose();
  }
}
