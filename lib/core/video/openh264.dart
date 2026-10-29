import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// Codec H264 di Cisco (OpenH264), scaricato sul PC dell'utente dal sito
/// ufficiale: così la licenza dei brevetti H264 è coperta da Cisco; non si può
/// includere nel nostro pacchetto (DECISIONS "Videochiamate").
///
/// Versione fissata a quella contro cui è compilato il plugin `libmsopenh264`
/// dell'SDK (include/wels/codec_ver.h: 2.2.0). Si accetta solo il file con
/// l'impronta verificata il 2026-10-29: firma Authenticode "Cisco WebEx LLC"
/// valida, importa solo KERNEL32 (nessuna funzione di rete).
class OpenH264 {
  OpenH264(this.dir);

  /// Cartella dei codec nella cartella dati dell'app.
  final String dir;

  static const version = '2.2.0';
  static const url =
      'http://ciscobinary.openh264.org/openh264-2.2.0-win64.dll.bz2';
  static const sha256Archive =
      '799e08c418b6cdeadfbe18d027392158face4a5c901d41f83712a20f0d41ad7d';
  static const sha256Dll =
      '9b392bf05cff1199cc44af236fa672c717f484e79c99d35bf1bed153a423d2d0';

  String get dllPath => '$dir${Platform.pathSeparator}openh264.dll';

  /// Installato e integro: l'impronta si ricontrolla prima di ogni caricamento.
  Future<bool> verified() async {
    final f = File(dllPath);
    if (!await f.exists()) return false;
    return sha256.convert(await f.readAsBytes()).toString() == sha256Dll;
  }

  /// Scarica, verifica entrambe le impronte e installa. L'URL è http come
  /// pubblicato da Cisco: l'integrità è garantita dall'impronta, non dal canale.
  Future<void> install({HttpClient? http}) async {
    final client = http ?? HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('download OpenH264: HTTP ${res.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > 5 * 1024 * 1024) {
          throw const FormatException('download OpenH264 troppo grande');
        }
      }
      await installFrom(bytes);
    } finally {
      if (http == null) client.close();
    }
  }

  /// Installa da un archivio `.bz2` già scaricato (anche per i test).
  Future<void> installFrom(List<int> archive) async {
    if (sha256.convert(archive).toString() != sha256Archive) {
      throw const FormatException('OpenH264: impronta dell\'archivio diversa');
    }
    final dll = BZip2Decoder().decodeBytes(archive);
    if (sha256.convert(dll).toString() != sha256Dll) {
      throw const FormatException('OpenH264: impronta della DLL diversa');
    }
    await Directory(dir).create(recursive: true);
    final tmp = File('$dllPath.tmp');
    await tmp.writeAsBytes(dll, flush: true);
    await tmp.rename(dllPath);
  }

  Future<void> remove() async {
    final f = File(dllPath);
    if (await f.exists()) await f.delete();
  }
}
