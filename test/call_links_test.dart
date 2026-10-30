import 'package:drinphone/core/platform/call_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('link telefonici: il numero, senza separatori', () {
    expect(numberFromLink('tel:+39%2002%205550%201234'), '+390255501234');
    expect(numberFromLink('"TEL:+39-02-5550.1234"'), '+390255501234');
    expect(numberFromLink('callto://3471234567'), '3471234567');
    expect(numberFromLink('sip:301@pbx.econnet.it;transport=tls'), '301');
    expect(numberFromLink('--autostart tel:(02) 5550'), '02');
  });

  test('niente link o niente numero chiamabile: null', () {
    expect(numberFromLink('--autostart'), isNull);
    expect(numberFromLink(''), isNull);
    expect(numberFromLink('https://example.com/tel:123'), '123');
    expect(numberFromLink('sip:mario@pbx'), isNull);
    // Codici di servizio del PBX (inoltro, casella vocale): non da un link.
    expect(numberFromLink('sips:*2@pbx'), isNull);
    expect(numberFromLink('tel:*723912345678'), isNull);
    expect(numberFromLink('tel:123%23'), isNull);
    expect(numberFromLink('tel:12%ZZ'), isNull);
    expect(numberFromLink('tel:${'1' * 40}'), isNull);
    expect(numberFromLink('tel:123;ext=4"&calc.exe'), '123');
  });
}
