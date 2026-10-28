import 'package:drinphone/core/sip/dialog_info.dart';
import 'package:drinphone/core/sip/sip_engine.dart';
import 'package:flutter_test/flutter_test.dart';

String doc(String state, String dialogs, {int version = 0}) =>
    '<?xml version="1.0"?>\n'
    '<dialog-info xmlns="urn:ietf:params:xml:ns:dialog-info" version="$version" '
    'state="$state" entity="sip:301@pbx">$dialogs</dialog-info>';

String dialog(String id, String state, {String? direction}) =>
    '<dialog id="$id"${direction == null ? '' : ' direction="$direction"'}>'
    '<state>$state</state></dialog>';

void main() {
  test('senza NOTIFY lo stato è sconosciuto, mai libero', () {
    expect(DialogInfoTracker().status, BlfStatus.unknown);
  });

  test('documento full senza dialog = libero', () {
    expect(DialogInfoTracker().apply(doc('full', '')), BlfStatus.idle);
  });

  test(
    'early in ingresso = squilla, confirmed = occupato, terminated = libero',
    () {
      final t = DialogInfoTracker();
      expect(
        t.apply(doc('full', dialog('a', 'early', direction: 'recipient'))),
        BlfStatus.ringing,
      );
      expect(
        t.apply(doc('full', dialog('a', 'confirmed', direction: 'recipient'))),
        BlfStatus.busy,
      );
      expect(t.apply(doc('full', dialog('a', 'terminated'))), BlfStatus.idle);
    },
  );

  test('early in uscita (initiator) = occupato', () {
    expect(
      DialogInfoTracker().apply(
        doc('full', dialog('a', 'early', direction: 'initiator')),
      ),
      BlfStatus.busy,
    );
  });

  test('aggiornamenti partial mantengono gli altri dialog', () {
    final t = DialogInfoTracker();
    t.apply(
      doc(
        'full',
        dialog('a', 'confirmed') + dialog('b', 'early', direction: 'recipient'),
      ),
    );
    expect(
      t.apply(doc('partial', dialog('a', 'terminated'))),
      BlfStatus.ringing,
    );
    expect(t.apply(doc('partial', dialog('b', 'terminated'))), BlfStatus.idle);
  });

  test('prefisso di namespace accettato', () {
    const xml =
        '<d:dialog-info xmlns:d="urn:ietf:params:xml:ns:dialog-info" state="full">'
        '<d:dialog id="x"><d:state>confirmed</d:state></d:dialog></d:dialog-info>';
    expect(DialogInfoTracker().apply(xml), BlfStatus.busy);
  });

  test('DOCTYPE/ENTITY rifiutati (niente espansione di entità)', () {
    const xml =
        '<!DOCTYPE x [<!ENTITY e SYSTEM "file:///c:/windows/win.ini">]>'
        '<dialog-info state="full"><dialog id="a"><state>&e;</state></dialog></dialog-info>';
    expect(DialogInfoTracker().apply(xml), BlfStatus.unknown);
  });
}
