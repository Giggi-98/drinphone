// Firma degli aggiornamenti (Ed25519), vedi lib/core/update/updater.dart.
//   dart run tool/sign_update.dart keygen <file-chiave>
//     crea la chiave privata (FUORI dal repo) e stampa la pubblica da mettere
//     in Updater.publicKey.
//   dart run tool/sign_update.dart sign <file-chiave> <installer.exe> <versione> <note.md> <update.json>
//     lo usa tool/build_installer.ps1.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String s) => [
  for (var i = 0; i + 1 < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];

Future<void> main(List<String> args) async {
  final algo = Ed25519();
  if (args.length == 2 && args[0] == 'keygen') {
    final f = File(args[1]);
    if (f.existsSync()) {
      stderr.writeln('${f.path} esiste già: non la sovrascrivo.');
      exit(1);
    }
    final rnd = Random.secure();
    final seed = [for (var i = 0; i < 32; i++) rnd.nextInt(256)];
    final pair = await algo.newKeyPairFromSeed(seed);
    final pub = await pair.extractPublicKey();
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(_hex(seed));
    stdout.writeln('Chiave privata: ${f.path} (non versionarla)');
    stdout.writeln('Chiave pubblica: ${_hex(pub.bytes)}');
    return;
  }
  if (args.length == 6 && args[0] == 'sign') {
    final seed = _unhex(File(args[1]).readAsStringSync().trim());
    final installer = File(args[2]);
    final payload = jsonEncode({
      'version': args[3],
      'file': installer.uri.pathSegments.last,
      'sha256': sha256.convert(installer.readAsBytesSync()).toString(),
      // release-notes/<versione>.md: sezioni e voci, firmate col resto.
      'notes': File(args[4]).readAsStringSync().trim(),
    });
    final pair = await algo.newKeyPairFromSeed(seed);
    final sig = await algo.sign(utf8.encode(payload), keyPair: pair);
    File(args[5]).writeAsStringSync(
      jsonEncode({'payload': payload, 'sig': base64.encode(sig.bytes)}),
    );
    stdout.writeln('Firmato: ${args[5]}');
    return;
  }
  stderr.writeln(
    'uso: keygen <file-chiave> | '
    'sign <file-chiave> <installer.exe> <versione> <note.md> <update.json>',
  );
  exit(64);
}
