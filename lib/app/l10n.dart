// Lingua dell'interfaccia. Il testo italiano è la chiave: tr('Interni') rende
// 'Extensions' in inglese. Segnaposto con {nome}: tr('{n} interni', {'n': 3}).
// Cambio immediato (ValueNotifier) e persistente (settings.json, campo `lang`).
import 'package:flutter/foundation.dart';

import 'l10n_en.dart';

enum AppLang {
  it('Italiano'),
  en('English');

  const AppLang(this.label);
  final String label;

  static AppLang fromCode(String? code) =>
      AppLang.values.where((l) => l.name == code).firstOrNull ?? AppLang.it;
}

final appLang = ValueNotifier<AppLang>(AppLang.it);

String tr(String it, [Map<String, Object> args = const {}]) {
  var s = appLang.value == AppLang.en ? (en[it] ?? it) : it;
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}
