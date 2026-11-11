import 'package:drinphone/core/pbx/pbx_connection.dart';
import 'package:drinphone/core/pbx/yeastar_api.dart';
import 'package:drinphone/core/security/api_credential_store.dart';
import 'package:drinphone/app/theme.dart';
import 'package:drinphone/features/shell/widgets.dart';
import 'package:flutter/material.dart';
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

  testWidgets('segnalino del menu: conversazioni, squilli, quiete', (
    tester,
  ) async {
    Future<void> show(int talking, int ringing) => tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: LiveBadge(talking: talking, ringing: ringing),
          ),
        ),
      ),
    );
    await show(0, 0);
    expect(find.byType(Tooltip), findsNothing);
    await show(3, 1);
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.ring_volume_rounded), findsOneWidget);
    expect(
      find.byTooltip('3 conversazioni in corso · 1 chiamata squilla'),
      findsOneWidget,
    );
    await show(0, 2);
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.byTooltip('2 chiamate squillano'), findsOneWidget);
  });

  test('reparto di una chiamata: il più specifico del primo interno', () {
    final conn = PbxConnection(
      id: 'a',
      label: 'PBX',
      store: ApiCredentialStore('nessun-file.dpapi'),
      apiFactory: YeastarApi.new,
      onUpdate: (_, _) {},
    );
    conn.directory = const [
      PbxExtension(id: 1, number: '302', name: 'Patrizia'),
      PbxExtension(id: 2, number: '303', name: 'Sandro'),
    ];
    conn.orgs = [
      PbxOrg(id: 10, name: 'Skillworks Holding', depth: 0, extIds: {1, 2}),
      PbxOrg(id: 11, parentId: 10, name: 'Econnet', depth: 1, extIds: {1}),
    ];
    expect(conn.deptOf('302'), 'Econnet');
    expect(conn.deptOf('303'), 'Skillworks Holding');
    expect(conn.deptOf('999'), '');
    expect(
      conn.deptOfCall(
        LiveCall('1', [ext('302', 'ANSWER'), ext('303', 'ANSWER')]),
      ),
      'Econnet',
    );
  });
}
