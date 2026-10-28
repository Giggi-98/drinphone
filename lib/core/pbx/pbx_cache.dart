import 'dart:convert';

import '../security/api_credential_store.dart';
import 'yeastar_api.dart';

/// Ultimi dati letti da un PBX (interni, reparti, rubrica aziendale), cifrati
/// con DPAPI: all'avvio e al cambio profilo l'interfaccia si riempie subito,
/// poi la sincronizzazione li aggiorna. La rubrica è dato personale di terzi:
/// mai in chiaro su disco (DECISIONS "Cache dati PBX").
class PbxCache {
  PbxCache(String path) : _box = DpapiBox(path);
  final DpapiBox _box;

  Future<void> save(
    List<PbxExtension> directory,
    List<PbxOrg> orgs,
    List<PbxContact> contacts,
  ) => _box.write(
    jsonEncode({
      'v': 1,
      'directory': [
        for (final e in directory)
          [e.id, e.number, e.name, e.email, e.mobile, e.presence],
      ],
      'orgs': [
        for (final o in orgs)
          [o.id, o.parentId, o.name, o.depth, o.extIds.toList()],
      ],
      'contacts': [
        for (final c in contacts)
          [
            c.id,
            c.name,
            c.company,
            c.jobTitle,
            c.email,
            [
              for (final (l, n) in c.numbers) [l, n],
            ],
            c.phonebooks,
          ],
      ],
    }),
  );

  /// Null se assente, illeggibile o di un formato diverso.
  Future<(List<PbxExtension>, List<PbxOrg>, List<PbxContact>)?> load() async {
    final plain = await _box.read();
    if (plain == null) return null;
    try {
      final j = jsonDecode(plain) as Map<String, dynamic>;
      if (j['v'] != 1) return null;
      return (
        [
          for (final e in j['directory'] as List)
            PbxExtension(
              id: e[0] as int,
              number: e[1] as String,
              name: e[2] as String,
              email: e[3] as String,
              mobile: e[4] as String,
              presence: e[5] as String,
            ),
        ],
        [
          for (final o in j['orgs'] as List)
            PbxOrg(
              id: o[0] as int,
              parentId: o[1] as int,
              name: o[2] as String,
              depth: o[3] as int,
              extIds: {for (final x in o[4] as List) x as int},
            ),
        ],
        [
          for (final c in j['contacts'] as List)
            PbxContact(
              id: c[0] as int,
              name: c[1] as String,
              company: c[2] as String,
              jobTitle: c[3] as String,
              email: c[4] as String,
              numbers: [
                for (final n in c[5] as List) (n[0] as String, n[1] as String),
              ],
              phonebooks: [for (final b in c[6] as List) b as String],
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _box.clear();
}
