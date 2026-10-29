import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../security/api_credential_store.dart';
import 'yeastar_api.dart';

/// Ultimi dati letti da un PBX (interni, reparti, rubrica aziendale, casella
/// vocale e dettaglio del proprio interno, codice di registrazione), cifrati
/// con DPAPI: all'avvio e all'accesso l'interfaccia si riempie subito, poi la
/// sincronizzazione li aggiorna. Rubrica e casella sono dati personali di
/// terzi: mai in chiaro su disco (DECISIONS "Cache dati PBX").
/// Codifica, DPAPI e decodifica (migliaia di contatti) in un isolate a parte:
/// l'interfaccia non si blocca all'accesso.
typedef PbxCached = ({
  List<PbxExtension> directory,
  List<PbxOrg> orgs,
  List<PbxContact> contacts,
  List<PbxVoicemail>? voicemail,
  PbxExtensionDetail? detail,
  String? recordCode,
  DateTime? contactsAt,
});

class PbxCache {
  PbxCache(String path) : _box = DpapiBox(path);
  final DpapiBox _box;

  // Un salvataggio alla volta per file (anche fra la connessione lasciata al
  // logout e quella nuova): due scritture parallele userebbero lo stesso file
  // temporaneo. Cache facoltativa: un errore di scrittura non ferma la sync.
  static final _saving = <String, Future<void>>{};

  /// Fine dei salvataggi in corso su questo file.
  @visibleForTesting
  Future<void> get saved => _saving[_box.path] ?? Future.value();

  Future<void> save(
    List<PbxExtension> directory,
    List<PbxOrg> orgs,
    List<PbxContact> contacts, {
    List<PbxVoicemail>? voicemail,
    PbxExtensionDetail? detail,
    String? recordCode,
    DateTime? contactsAt,
  }) {
    final path = _box.path;
    return _saving[path] = (_saving[path] ?? Future.value()).then(
      (_) => Isolate.run(
        () => DpapiBox(path).write(
          _encode(
            directory,
            orgs,
            contacts,
            voicemail,
            detail,
            recordCode,
            contactsAt,
          ),
        ),
      ).catchError((Object _) {}),
    );
  }

  static String _encode(
    List<PbxExtension> directory,
    List<PbxOrg> orgs,
    List<PbxContact> contacts,
    List<PbxVoicemail>? voicemail,
    PbxExtensionDetail? detail,
    String? recordCode,
    DateTime? contactsAt,
  ) => jsonEncode({
    'v': 2,
    'contactsAt': contactsAt?.millisecondsSinceEpoch,
    'voicemail': voicemail == null
        ? null
        : [
            for (final m in voicemail)
              [m.id, m.callerName, m.callerNumber, m.time, m.seconds, m.read],
          ],
    'detail': detail?.toJson(),
    'recordCode': recordCode,
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
  });

  /// Null se assente, illeggibile o di un formato diverso.
  Future<PbxCached?> load() {
    final path = _box.path;
    return Isolate.run(() async => _decode(await DpapiBox(path).read()));
  }

  static PbxCached? _decode(String? plain) {
    if (plain == null) return null;
    try {
      final j = jsonDecode(plain) as Map<String, dynamic>;
      if (j['v'] != 1 && j['v'] != 2) return null;
      final vm = j['voicemail'] as List?;
      final detail = j['detail'] as Map<String, dynamic>?;
      final contactsAt = j['contactsAt'] as int?;
      return (
        directory: [
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
        orgs: [
          for (final o in j['orgs'] as List)
            PbxOrg(
              id: o[0] as int,
              parentId: o[1] as int,
              name: o[2] as String,
              depth: o[3] as int,
              extIds: {for (final x in o[4] as List) x as int},
            ),
        ],
        contacts: [
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
        voicemail: vm == null
            ? null
            : [
                for (final m in vm)
                  PbxVoicemail(
                    id: m[0] as String,
                    callerName: m[1] as String,
                    callerNumber: m[2] as String,
                    time: m[3] as String,
                    seconds: m[4] as int,
                    read: m[5] as bool,
                  ),
              ],
        detail: detail == null ? null : PbxExtensionDetail.parse(detail),
        recordCode: j['recordCode'] as String?,
        contactsAt: contactsAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(contactsAt),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _box.clear();
}
