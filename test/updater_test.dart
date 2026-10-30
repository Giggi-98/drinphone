import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drinphone/core/update/updater.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('Updater: solo versioni più recenti, mai una build dev', () {
    expect(Updater.isNewer('0.1.1', '0.1.0'), isTrue);
    expect(Updater.isNewer('0.10.0', '0.9.9'), isTrue);
    expect(Updater.isNewer('0.1.0', '0.1.0'), isFalse);
    expect(Updater.isNewer('0.0.9', '0.1.0'), isFalse);
    expect(Updater.isNewer('1.0.0', 'dev'), isFalse);
  });

  test('Updater: manifest accettato solo con la firma della chiave', () async {
    final algo = Ed25519();
    final pair = await algo.newKeyPairFromSeed(List.filled(32, 7));
    final pub = _hex((await pair.extractPublicKey()).bytes);
    Future<String> signed(Map<String, String> p) async {
      final payload = jsonEncode(p);
      final sig = await algo.sign(utf8.encode(payload), keyPair: pair);
      return jsonEncode({'payload': payload, 'sig': base64.encode(sig.bytes)});
    }

    final good = {
      'version': '0.2.0',
      'file': 'DrinPhone-Alpha-0.2.0-setup.exe',
      'sha256': 'a' * 64,
      'notes': 'fix audio',
    };
    final info = await Updater.verifyManifest(await signed(good), pub);
    expect(info.version, '0.2.0');
    expect(
      info.url.toString(),
      'https://github.com/${Updater.repo}/releases/download/v0.2.0/'
      'DrinPhone-Alpha-0.2.0-setup.exe',
    );

    // Payload alterato dopo la firma.
    final j = jsonDecode(await signed(good)) as Map<String, dynamic>;
    j['payload'] = (j['payload'] as String).replaceAll('0.2.0', '9.9.9');
    await expectLater(
      Updater.verifyManifest(jsonEncode(j), pub),
      throwsA(isA<FormatException>()),
    );

    // Firmato ma con un nome di file che uscirebbe dalla cartella.
    await expectLater(
      Updater.verifyManifest(
        await signed({...good, 'file': r'..\evil.exe'}),
        pub,
      ),
      throwsA(isA<FormatException>()),
    );

    // Chiave pubblica di produzione: un manifest di prova non passa.
    await expectLater(
      Updater.verifyManifest(await signed(good), Updater.publicKey),
      throwsA(isA<FormatException>()),
    );
  });
}
