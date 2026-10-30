import 'dart:io';
import 'dart:math';

/// Codice univoco di questa installazione (DECISIONS "ID di installazione"):
/// 16 byte casuali creati al primo avvio e salvati nella cartella dati, quindi
/// stabile fra aggiornamenti e reinstallazioni dello stesso utente. Serve solo
/// a riconoscere il PC nel supporto (Diagnostica, log errori): non lascia il
/// PC e non autentica nulla.
String loadInstallId(String file) {
  final f = File(file);
  try {
    final id = f.readAsStringSync().trim();
    if (RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return id;
  } catch (_) {}
  final rnd = Random.secure();
  final id = [
    for (var i = 0; i < 16; i++)
      rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
  try {
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(id);
  } catch (_) {}
  return id;
}
