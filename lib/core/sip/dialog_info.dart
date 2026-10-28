// Parser minimo di application/dialog-info+xml (RFC 4235) per il BLF.
// Niente parser XML generico: si estraggono solo dialog/state/direction e i
// documenti con DOCTYPE/ENTITY vengono scartati (nessuna espansione di entità).
import 'sip_engine.dart';

class DialogInfoTracker {
  final _dialogs = <String, (String state, String direction)>{};
  bool _hasDocument = false;

  static final _root = RegExp(r'<(?:\w+:)?dialog-info\b([^>]*)>');
  static final _dialog = RegExp(
    r'<(?:\w+:)?dialog\b([^>]*?)(?:/>|>(.*?)</(?:\w+:)?dialog>)',
    dotAll: true,
  );
  static final _state = RegExp(
    r'<(?:\w+:)?state\b[^>]*>\s*([A-Za-z-]+)\s*</(?:\w+:)?state>',
  );

  static String? _attr(String attrs, String name) =>
      RegExp('\\b$name\\s*=\\s*"([^"]*)"').firstMatch(attrs)?.group(1);

  /// Applica un NOTIFY e restituisce lo stato risultante dell'interno.
  BlfStatus apply(String xml) {
    if (xml.contains('<!DOCTYPE') || xml.contains('<!ENTITY')) {
      return BlfStatus.unknown;
    }
    final root = _root.firstMatch(xml);
    if (root == null) {
      // NOTIFY senza corpo: stato invariato se ne avevamo uno, altrimenti ignoto.
      return _hasDocument ? status : BlfStatus.unknown;
    }
    if ((_attr(root.group(1)!, 'state') ?? 'full') == 'full') _dialogs.clear();
    _hasDocument = true;
    for (final m in _dialog.allMatches(xml)) {
      final attrs = m.group(1)!;
      final id = _attr(attrs, 'id') ?? '';
      final state = _state.firstMatch(m.group(2) ?? '')?.group(1) ?? '';
      if (state == 'terminated' || state.isEmpty) {
        _dialogs.remove(id);
      } else {
        _dialogs[id] = (state, _attr(attrs, 'direction') ?? '');
      }
    }
    return status;
  }

  BlfStatus get status {
    if (!_hasDocument) return BlfStatus.unknown;
    if (_dialogs.isEmpty) return BlfStatus.idle;
    final values = _dialogs.values;
    if (values.any((d) => d.$1 == 'confirmed')) return BlfStatus.busy;
    // early/proceeding/trying: squilla se la chiamata è verso l'interno.
    if (values.any((d) => d.$2 != 'initiator')) return BlfStatus.ringing;
    return BlfStatus.busy;
  }
}
