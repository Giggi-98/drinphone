import 'dart:io';

import 'package:drinphone/app/l10n.dart';
import 'package:drinphone/app/l10n_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ogni testo tr() del codice ha la traduzione inglese', () {
    final call = RegExp(r"tr\(\s*((?:'(?:[^'\\]|\\.)*'\s*)+)");
    final part = RegExp(r"'((?:[^'\\]|\\.)*)'");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in call.allMatches(f.readAsStringSync())) {
        final key = part
            .allMatches(m.group(1)!)
            .map((p) => p.group(1)!)
            .join()
            .replaceAll(r"\'", "'");
        if (!en.containsKey(key)) missing.add(key);
      }
    }
    expect(missing, isEmpty);
  });

  test('tr: segnaposto e cambio lingua', () {
    appLang.value = AppLang.en;
    expect(tr('Chiama {n}', {'n': '201'}), 'Call 201');
    appLang.value = AppLang.it;
    expect(tr('Chiama {n}', {'n': '201'}), 'Chiama 201');
    expect(AppLang.fromCode('xx'), AppLang.it);
  });
}
