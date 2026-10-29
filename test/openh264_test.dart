import 'dart:io';

import 'package:drinphone/core/video/openh264.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OpenH264: accettato solo con l\'impronta verificata', () async {
    final tmp = await Directory.systemTemp.createTemp('drinphone_h264');
    final h = OpenH264(tmp.path);
    expect(await h.verified(), isFalse);
    // Archivio qualsiasi: rifiutato, niente installato.
    await expectLater(
      h.installFrom([1, 2, 3]),
      throwsA(isA<FormatException>()),
    );
    expect(File(h.dllPath).existsSync(), isFalse);
    // DLL sostituita o manomessa: non verificata, il core non la carica.
    await File(h.dllPath).writeAsBytes([0x4D, 0x5A, 0, 0]);
    expect(await h.verified(), isFalse);
    await h.remove();
    expect(File(h.dllPath).existsSync(), isFalse);
    await tmp.delete(recursive: true);
  });
}
