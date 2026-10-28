// Una connessione OpenAPI verso un PBX Yeastar: credenziali proprie (file DPAPI
// dedicato), token, elenco interni e reparti, ciclo di sincronizzazione.
// Più connessioni convivono senza condividere nulla (multi-PBX).
import 'dart:async';
import 'dart:math';

import '../security/api_credential_store.dart';
import 'yeastar_api.dart';

class PbxConnection {
  PbxConnection({
    required this.id,
    required this.label,
    required this.store,
    required this.apiFactory,
    required this.onUpdate,
  });

  final String id;
  String label;
  final ApiCredentialStore store;
  final YeastarApi Function(ApiCredentials) apiFactory;

  /// `directoryChanged`: interni o reparti diversi dall'ultima lettura.
  final void Function(PbxConnection c, bool directoryChanged) onUpdate;

  YeastarApi? _api;
  List<PbxExtension> directory = const [];
  List<PbxOrg> orgs = const [];

  /// Rubrica aziendale; vuota se l'API non la espone o non è autorizzata.
  List<PbxContact> contacts = const [];
  String status = 'Non connessa';
  bool ok = false;
  bool syncing = false;
  DateTime? lastSync;

  /// Indirizzo API (non segreto), per mostrarlo e per riconoscere il PBX
  /// dell'account SIP.
  String baseUrl = '';
  String get host => Uri.tryParse(baseUrl)?.host ?? '';

  /// Problemi delle letture facoltative dell'ultimo giro (reparti, rubrica).
  final optionalErrors = <String>[];

  // Messaggio breve: tipo ed eventuale codice, mai URL o token.
  static String _short(Object e) =>
      e is YeastarApiException ? '$e' : e.runtimeType.toString();

  Timer? _timer;
  int _failures = 0;
  DateTime? _orgsAt;
  String _fingerprint = '';
  bool _stopped = false;

  /// Presenza ogni minuto; reparti più di rado (cambiano poco); errori con
  /// attesa crescente fino a 15 minuti (limite 8 token e blocco IP).
  static const presenceEvery = Duration(seconds: 60);
  static const orgsEvery = Duration(minutes: 10);
  static const maxBackoff = Duration(minutes: 15);
  static const minGap = Duration(seconds: 10);

  Future<void> start() async {
    await stop();
    _stopped = false;
    final creds = await store.load();
    if (creds == null) {
      ok = false;
      status = store.isSet
          ? 'Credenziali non leggibili su questo PC'
          : 'Credenziali mancanti';
      onUpdate(this, false);
      return;
    }
    baseUrl = creds.baseUrl;
    _api = apiFactory(creds);
    await sync(force: true);
  }

  /// Rilettura dal PBX. Senza [force] viene saltata se l'ultima è troppo recente.
  Future<void> sync({bool force = false}) async {
    final api = _api;
    if (api == null || syncing || _stopped) return;
    final last = lastSync;
    if (!force && last != null && DateTime.now().difference(last) < minGap) {
      return;
    }
    _timer?.cancel();
    syncing = true;
    onUpdate(this, false);
    var changed = false;
    optionalErrors.clear();
    try {
      if (!api.connected) await api.connect();
      final ext = await api.listExtensions();
      final idsChanged =
          ext
              .map((e) => e.id)
              .toSet()
              .difference(directory.map((e) => e.id).toSet())
              .isNotEmpty ||
          ext.length != directory.length;
      var newOrgs = orgs;
      var newContacts = contacts;
      final orgsAt = _orgsAt;
      if (force ||
          idsChanged ||
          orgsAt == null ||
          DateTime.now().difference(orgsAt) > orgsEvery) {
        try {
          newOrgs = await api.listOrganizations();
        } catch (e) {
          // Reparti facoltativi: si tengono gli ultimi letti; non bloccano gli interni.
          optionalErrors.add('reparti: ${_short(e)}');
        }
        // Rubrica: stessa cadenza lenta dei reparti, cambia di rado.
        try {
          newContacts = await api.listCompanyContacts();
        } catch (e) {
          // Rubrica facoltativa (permessi, formato diverso dalla documentazione).
          optionalErrors.add('rubrica: ${_short(e)}');
        }
        _orgsAt = DateTime.now();
      }
      final fp = _fingerprintOf(ext, newOrgs, newContacts);
      changed = fp != _fingerprint;
      _fingerprint = fp;
      directory = ext;
      orgs = newOrgs;
      contacts = newContacts;
      lastSync = DateTime.now();
      _failures = 0;
      ok = true;
      status =
          'Sincronizzata · ${ext.length} interni, ${newOrgs.length} reparti, '
          '${newContacts.length} contatti';
    } catch (e) {
      // e non contiene URL né token (YeastarApiException), solo operazione e codice.
      _failures++;
      ok = false;
      status = 'Errore: $e · nuovo tentativo tra ${_nextDelay().inMinutes} min';
    } finally {
      syncing = false;
      if (!_stopped) _timer = Timer(_nextDelay(), sync);
      onUpdate(this, changed);
    }
  }

  Duration _nextDelay() {
    if (_failures == 0) return presenceEvery;
    final s = presenceEvery.inSeconds * pow(2, min(_failures, 4));
    return Duration(seconds: min(s.toInt(), maxBackoff.inSeconds));
  }

  static String _fingerprintOf(
    List<PbxExtension> ext,
    List<PbxOrg> orgs,
    List<PbxContact> contacts,
  ) => [
    for (final e in ext) '${e.id}|${e.number}|${e.name}|${e.presence}',
    for (final o in orgs) '${o.id}|${o.parentId}|${o.name}|${o.extIds.length}',
    for (final c in contacts) '${c.id}|${c.name}|${c.numbers}',
  ].join('\n');

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    await _api?.close();
    _api = null;
  }

  /// Ferma e cancella le credenziali di questa connessione.
  Future<void> forget() async {
    await stop();
    await store.clear();
    directory = const [];
    orgs = const [];
    contacts = const [];
  }
}
