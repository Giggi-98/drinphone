import 'package:drinphone/core/pbx/pbx_connection.dart';
import 'package:drinphone/core/pbx/yeastar_api.dart';
import 'package:flutter_test/flutter_test.dart';

LiveMember ext(String n, String status) =>
    LiveMember(kind: 'extension', channel: 'c$n', status: status, number: n);

void main() {
  // Bug 0.1.9: 302→303 in conversazione da minuti mostrata come "squilla"
  // perché un capo era rimasto in ALERT.
  test('una conversazione con un capo rimasto in ALERT non squilla', () {
    final c = LiveCall('1', [ext('302', 'ALERT'), ext('303', 'ANSWER')]);
    expect(c.talking, isTrue);
    expect(c.ringing, isFalse);
    expect(c.stateOf('302'), LiveState.talking);
    expect(c.stateOf('303'), LiveState.talking);
  });

  test('prima della risposta: chi chiama "chiama", al chiamato squilla', () {
    final c = LiveCall('1', [ext('302', 'ALERT'), ext('303', 'RING')]);
    expect(c.ringing, isTrue);
    expect(c.stateOf('302'), LiveState.calling);
    expect(c.stateOf('303'), LiveState.ringing);
    expect(c.otherOf('302'), '303');
    expect(c.otherOf('303'), '302');
    expect(c.stateOf('999'), isNull);
  });

  test('attesa', () {
    final c = LiveCall('1', [ext('302', 'HOLD'), ext('303', 'ANSWER')]);
    expect(c.onHold, isTrue);
    expect(c.stateOf('302'), LiveState.hold);
  });
}
