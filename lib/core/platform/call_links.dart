// Click-to-call: link tel:, sip:, sips:, callto: aperti da browser, Outlook o
// altre app (Windows li passa a DrinPhone come argomento). Il numero non
// viene chiamato da solo: l'app chiede conferma (una pagina web potrebbe
// lanciare un link verso un numero a pagamento).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Numero da chiamare richiesto da un link, in attesa di conferma.
final pendingCallLink = ValueNotifier<String?>(null);

/// Link nella riga di comando di avvio e in quella delle copie successive
/// (windows/runner: istanza unica, WM_COPYDATA -> "drinphone/instance").
void listenForCallLinks(List<String> args) {
  pendingCallLink.value = numberFromLink(args.join(' '));
  const MethodChannel('drinphone/instance').setMethodCallHandler((call) async {
    final line = call.arguments;
    if (call.method != 'open' || line is! String) return;
    final n = numberFromLink(line);
    if (n != null) pendingCallLink.value = n;
  });
}

final _link = RegExp(
  r'''(?:tel|callto|sips?):(?://)?([^\s"'<>]+)''',
  caseSensitive: false,
);

/// Numero dal primo link nel testo (argomenti della riga di comando); null se
/// non c'è un link o non contiene un numero chiamabile.
String? numberFromLink(String text) {
  final m = _link.firstMatch(text);
  if (m == null) return null;
  var target = m[1]!;
  try {
    target = Uri.decodeComponent(target);
  } catch (_) {
    return null;
  }
  // sip:301@pbx;transport=tls?x=y -> 301 (si chiama dal proprio PBX).
  target = target.split(RegExp('[;?]')).first.split('@').first;
  // Separatori visivi dei numeri (spazi, trattini, punti, parentesi).
  final n = target.replaceAll(RegExp(r'[\s\-.()/]'), '');
  // Solo cifre: * e # sono codici di servizio del PBX (inoltri, casella),
  // non numeri da chiamare da un link.
  if (n.isEmpty || n.length > 32 || !RegExp(r'^\+?[0-9]+$').hasMatch(n)) {
    return null;
  }
  return n;
}
