import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as ed;
import 'package:flutter/foundation.dart';

import 'release_notes.dart';

/// Una versione pubblicata, letta dal manifest firmato.
class UpdateInfo {
  const UpdateInfo(this.version, this.file, this.sha256, this.notes);
  final String version;

  /// Nome dell'installer fra gli asset della release `v<version>`.
  final String file;
  final String sha256;

  /// Note di rilascio (`release-notes/<versione>.md`), firmate col payload.
  final String notes;

  ReleaseNotes get releaseNotes => ReleaseNotes.parse(version, notes);

  Uri get url => Uri.parse(
    'https://github.com/${Updater.repo}/releases/download/v$version/$file',
  );
}

/// Aggiornamenti dalle GitHub Releases (DECISIONS "Aggiornamenti dalle GitHub
/// Releases"). Il client legge `update.json` dell'ultima release:
/// `{"payload": "<json>", "sig": "<base64>"}`, payload =
/// `{"version", "file", "sha256", "notes"}` firmato Ed25519 con la chiave di
/// `tool/sign_update.dart`. Si accetta solo con firma valida, versione più
/// recente di quella installata (niente rollback) e installer con l'impronta
/// del payload. HTTPS da solo non basta: chi controlla il repo non può
/// distribuire un installer senza la chiave privata, che non sta nel repo.
class Updater extends ChangeNotifier {
  Updater({
    required this.current,
    required this.downloadDir,
    this.notesSeenFile,
  });

  /// Versione installata (`DRIN_VERSION`); `dev` = build locale, niente
  /// controlli periodici.
  final String current;
  final String downloadDir;

  /// Ultima versione di cui si sono mostrate le novità.
  final String? notesSeenFile;

  static const repo = 'Giggi-98/drinphone';
  static final manifestUrl = Uri.parse(
    'https://github.com/$repo/releases/latest/download/update.json',
  );

  /// Chiave pubblica Ed25519 (hex) della firma degli aggiornamenti.
  /// Privata in `%USERPROFILE%\.drinphone\update-signing.key` di chi pubblica.
  static const publicKey =
      '9d88fa95b589922ffcf27ab0b774ca193effa75022201788d41f61d68b99aacd';

  static const checkEvery = Duration(hours: 6);

  UpdateInfo? available;
  bool checking = false;
  String? error;
  DateTime? lastCheck;

  /// Avanzamento del download (0..1), null se non in corso.
  double? progress;

  Timer? _timer;

  bool get isDevBuild => _parse(current) == null;

  /// Primo controllo dopo l'avvio (senza rallentarlo), poi ogni 6 ore.
  void startPeriodic() {
    if (isDevBuild) return;
    _timer = Timer(const Duration(seconds: 30), () async {
      // Installer di un aggiornamento già fatto.
      try {
        await Directory(downloadDir).delete(recursive: true);
      } catch (_) {}
      check();
      _timer = Timer.periodic(checkEvery, (_) => check());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Novità della versione installata, se non ancora mostrate (primo avvio
  /// dopo un aggiornamento o dopo l'installazione).
  Future<ReleaseNotes?> unseenNotes() async {
    final f = notesSeenFile;
    if (isDevBuild || f == null) return null;
    try {
      if (File(f).existsSync() &&
          File(f).readAsStringSync().trim() == current) {
        return null;
      }
    } catch (_) {}
    return ReleaseNotes.bundled(current);
  }

  Future<void> markNotesSeen() async {
    final f = notesSeenFile;
    if (f == null) return;
    try {
      await File(f).parent.create(recursive: true);
      await File(f).writeAsString(current);
    } catch (_) {}
  }

  Future<void> check() async {
    if (checking || progress != null) return;
    checking = true;
    error = null;
    notifyListeners();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final res = await (await client.getUrl(manifestUrl)).close();
      // 404 = nessuna release pubblicata ancora.
      if (res.statusCode == 404) {
        available = null;
      } else if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      } else {
        final body = await res.transform(utf8.decoder).join();
        final info = await verifyManifest(body, publicKey);
        available = isNewer(info.version, current) ? info : null;
      }
      lastCheck = DateTime.now();
    } catch (e) {
      error = '$e';
    } finally {
      client.close();
      checking = false;
      notifyListeners();
    }
  }

  /// Scarica l'installer, ne verifica l'impronta e lo avvia in modalità
  /// silenziosa; poi [beforeExit] (un-REGISTER, token) e uscita: l'installer
  /// sostituisce i file e riapre l'app.
  Future<void> install(Future<void> Function() beforeExit) async {
    final info = available;
    if (info == null || progress != null) return;
    progress = 0;
    error = null;
    notifyListeners();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    File? file;
    try {
      await Directory(downloadDir).create(recursive: true);
      file = File('$downloadDir${Platform.pathSeparator}${info.file}');
      final res = await (await client.getUrl(info.url)).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      final sink = file.openWrite();
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      var got = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          hasher.add(chunk);
          got += chunk.length;
          if (got > 500 * 1024 * 1024) {
            throw const FormatException('installer troppo grande');
          }
          if (total > 0) {
            progress = got / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      hasher.close();
      if (digest.value.toString() != info.sha256) {
        throw const FormatException('impronta dell\'installer non valida');
      }
      await Process.start(file.path, [
        '/SILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
      ], mode: ProcessStartMode.detached);
      await beforeExit();
      exit(0);
    } catch (e) {
      error = '$e';
      progress = null;
      if (file != null && await file.exists()) await file.delete();
      notifyListeners();
    } finally {
      client.close();
    }
  }

  /// Verifica firma e contenuto del manifest; lancia se non valido.
  static Future<UpdateInfo> verifyManifest(String body, String keyHex) async {
    final outer = jsonDecode(body) as Map<String, dynamic>;
    final payload = outer['payload'] as String;
    final ok = await ed.Ed25519().verify(
      utf8.encode(payload),
      signature: ed.Signature(
        base64.decode(outer['sig'] as String),
        publicKey: ed.SimplePublicKey(
          _hex(keyHex),
          type: ed.KeyPairType.ed25519,
        ),
      ),
    );
    if (!ok) {
      throw const FormatException('firma dell\'aggiornamento non valida');
    }
    final j = jsonDecode(payload) as Map<String, dynamic>;
    final info = UpdateInfo(
      j['version'] as String,
      j['file'] as String,
      (j['sha256'] as String).toLowerCase(),
      j['notes'] as String? ?? '',
    );
    // Il nome finisce in un URL e in un percorso locale.
    if (_parse(info.version) == null ||
        !RegExp(r'^[A-Za-z0-9._-]+\.exe$').hasMatch(info.file) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(info.sha256)) {
      throw const FormatException('manifest di aggiornamento non valido');
    }
    return info;
  }

  /// `a` più recente di `b` (x.y.z numerici); una build `dev` non si aggiorna.
  static bool isNewer(String a, String b) {
    final x = _parse(a), y = _parse(b);
    if (x == null || y == null) return false;
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] > y[i];
    }
    return false;
  }

  static List<int>? _parse(String v) {
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(v);
    return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m[i]!)];
  }

  static List<int> _hex(String s) => [
    for (var i = 0; i + 1 < s.length; i += 2)
      int.parse(s.substring(i, i + 2), radix: 16),
  ];
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
