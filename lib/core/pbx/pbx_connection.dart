// Una connessione OpenAPI verso un PBX Yeastar: credenziali proprie (file DPAPI
// dedicato), token, elenco interni e reparti, ciclo di sincronizzazione.
// Più connessioni convivono senza condividere nulla (multi-PBX).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../app/l10n.dart';
import '../security/api_credential_store.dart';
import '../security/cdr_db_store.dart';
import '../sip/sip_engine.dart' show BlfStatus;
import 'pbx_cache.dart';
import 'pbx_cdr.dart';
import 'pbx_sync.dart';
import 'yeastar_api.dart';

/// Chiamata in corso sul PBX (Live Calls).
class LiveCall {
  LiveCall(this.id, this.members) : seen = DateTime.now();
  final String id;
  List<LiveMember> members;

  /// Prima volta vista (inizio approssimato) e prima risposta.
  final DateTime seen;
  DateTime? answered;

  bool get ringing =>
      members.any((m) => m.status == 'RING' || m.status == 'ALERT');
  bool get onHold => members.any((m) => m.status == 'HOLD');
  bool get talking =>
      members.any((m) => m.status == 'ANSWER' || m.status == 'ANSWERED');

  /// Tipo da `call/query` (`inbound`, `outbound`, `internal`); vuoto finché
  /// la chiamata è nota solo dagli eventi.
  String type = '';

  /// Direzione stimata dagli interni noti quando mancano le tratte trunk:
  /// true = da interno verso esterno; null = nessun capo esterno riconosciuto.
  bool? viaExternal;

  /// Chiamata verso l'esterno (Linkus: "Outbound Calls"): prima le tratte
  /// trunk, poi la stima dagli interni, infine il tipo di `call/query`.
  bool get outbound {
    if (members.any((m) => m.kind == 'outbound')) return true;
    if (members.any((m) => m.kind == 'inbound')) return false;
    return viaExternal ?? type == 'outbound';
  }

  LiveMember? _of(String kind) =>
      members.where((m) => m.kind == kind).firstOrNull;

  /// Chiamante: da inbound/outbound/internal, altrimenti il primo interno.
  String get caller {
    for (final k in ['inbound', 'outbound', 'internal']) {
      final m = _of(k);
      if (m != null && m.from.isNotEmpty) return m.from;
    }
    return members.where((m) => m.kind == 'extension').firstOrNull?.number ??
        '';
  }

  /// Chiamato: interni coinvolti diversi dal chiamante, o il numero esterno.
  String get callee {
    final out = _of('outbound');
    if (out != null && out.to.isNotEmpty) return out.to;
    final exts = [
      for (final m in members)
        if (m.kind == 'extension' && m.number != caller) m.number,
    ];
    if (exts.isNotEmpty) return exts.join(', ');
    return (_of('inbound') ?? _of('internal'))?.to ?? '';
  }

  String get trunk =>
      members.map((m) => m.trunk).where((t) => t.isNotEmpty).firstOrNull ?? '';
  String get path =>
      members.map((m) => m.path).where((t) => t.isNotEmpty).firstOrNull ?? '';
}

class PbxConnection {
  PbxConnection({
    required this.id,
    required this.label,
    required this.store,
    required this.apiFactory,
    required this.onUpdate,
    this.cache,
    this.cdrStore,
    this.cdrOpener,
  });

  final String id;

  /// Credenziali Database Grant per il CDR (null = funzione assente).
  final CdrDbStore? cdrStore;
  final CdrSourceOpener? cdrOpener;

  /// CDR configurato (credenziali salvate) e concesso per tutto il PBX.
  bool get cdrConfigured => cdrStore?.isSet ?? false;
  bool cdrWholePbx = false;

  /// Righe del CDR: del proprio interno ([voicemailOf], legato all'interno
  /// scelto dall'amministratore) o di tutto il PBX se concesso.
  /// Una lettura del CDR alla volta: filtri nuovi o "Riprova" non aprono
  /// connessioni in parallelo al database del PBX.
  Future<void> _cdrQueue = Future.value();

  Future<CdrPage> readCdr(CdrQuery q) {
    final next = _cdrQueue.then((_) => _readCdr(q));
    _cdrQueue = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<CdrPage> _readCdr(CdrQuery q) async {
    final creds = await cdrStore?.load();
    if (creds == null) throw StateError('CDR non configurato');
    cdrWholePbx = creds.wholePbx;
    return PbxCdr(creds, open: cdrOpener).read(ownExtension: voicemailOf, q: q);
  }

  /// Salva (o sostituisce) le credenziali del database CDR.
  Future<void> saveCdr(CdrDbCredentials creds) async {
    await cdrStore?.save(creds);
    cdrWholePbx = creds.wholePbx;
    onUpdate(this, false);
  }

  Future<void> forgetCdr() async {
    await cdrStore?.clear();
    cdrWholePbx = false;
    onUpdate(this, false);
  }

  /// Ultimi dati letti, cifrati su disco: mostrati subito all'avvio.
  final PbxCache? cache;
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

  /// Eventi in tempo reale via WebSocket (interruttore della connessione).
  bool realtime = false;

  /// Stato di chiamata per interno dall'evento 30008 (BLF senza SIP).
  final callStatus = <String, BlfStatus>{};

  /// Chiamate in corso sul PBX (evento 30011 + fotografia call/query).
  final liveCalls = <String, LiveCall>{};

  /// Chiamate da mostrare, dalla più vecchia. Il PBX dà id diversi alla tratta
  /// trunk e a quella dell'interno della stessa conversazione: una riga per
  /// coppia di capi, preferendo quella con il trunk.
  List<LiveCall> get visibleCalls {
    final exts = {for (final e in directory) e.number};
    final byPair = <String, LiveCall>{};
    final sorted = liveCalls.values.toList()
      ..sort((a, b) => a.seen.compareTo(b.seen));
    for (final c in sorted) {
      final callerExt = exts.contains(c.caller);
      final calleeExt = exts.contains(c.callee);
      c.viaExternal =
          c.caller.isEmpty || c.callee.isEmpty || callerExt == calleeExt
          ? null
          : callerExt;
      final pair = c.caller.isEmpty || c.callee.isEmpty
          ? c.id
          : ([c.caller, c.callee]..sort()).join('|');
      final prev = byPair[pair];
      if (prev == null || (prev.trunk.isEmpty && c.trunk.isNotEmpty)) {
        byPair[pair] = c;
      }
    }
    return byPair.values.toList()..sort((a, b) => a.seen.compareTo(b.seen));
  }

  /// Stato leggibile del canale eventi; vuoto se spento.
  String eventsStatus = '';
  bool get eventsConnected => _ws != null;

  WebSocket? _ws;
  Timer? _heartbeat;
  Timer? _wsRetry;
  Timer? _resyncSoon;
  int _wsFailures = 0;

  /// Eventi sottoscritti: registrazione (30007), stato chiamata (30008),
  /// presenza (30009), anagrafica interno cambiata (30022).
  static const eventTopics = [30007, 30008, 30009, 30011, 30022];

  /// Tipi di `call/query` (documentati per le tre edition).
  static const _callTypes = ['inbound', 'outbound', 'internal'];

  /// Con chiamate in corso, riallineamento periodico via `call/query`: un BYE
  /// perso o non inviato non lascia chiamate fantasma.
  static const callsCheckEvery = Duration(seconds: 15);
  Timer? _callsTimer;
  bool _snapshotting = false;

  /// Interno di cui leggere la casella vocale (l'account SIP); null = nessuno.
  /// Vale solo se coincide con [ownExtension]: lo username SIP lo modifica
  /// l'utente, l'interno della chiave lo sceglie l'amministratore.
  String? get voicemailOf {
    final v = _voicemailOf;
    return v != null && v.isNotEmpty && v == ownExtension ? v : null;
  }

  set voicemailOf(String? v) => _voicemailOf = v;
  String? _voicemailOf;

  /// Interno dell'utente fissato con le credenziali ([ApiCredentials]).
  String ownExtension = '';

  /// Messaggi in casella; null = non letti dall'API (non disponibile o errore).
  List<PbxVoicemail>? voicemail;

  /// Codice di registrazione del PBX (`feature_code/get`), se abilitato.
  String? recordCode;

  /// Dettaglio del proprio interno ([voicemailOf]): presenze e inoltri.
  PbxExtensionDetail? ownDetail;
  bool _detailStale = true;
  String status = tr('Non connessa');
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

  /// Ultima lettura riuscita (o tentata, per le facoltative) di ogni voce; la
  /// rubrica viene dalla cache, così vale anche fra un accesso e l'altro.
  final _readAt = <PbxSync, DateTime>{};
  String _fingerprint = '';
  bool _stopped = false;

  /// Cosa leggere e ogni quanto, scelto dall'utente ([PbxSync]; nome →
  /// secondi, 0 = spenta). Errori con attesa crescente fino a 15 minuti
  /// (limite 8 token e blocco IP).
  Map<String, int> syncSettings = {};
  static const maxBackoff = Duration(minutes: 15);
  static const minGap = Duration(seconds: 10);

  /// Con gli eventi attivi la presenza arriva in tempo reale: interni al più
  /// ogni 5 minuti.
  static const eventsExtensionsEvery = Duration(minutes: 5);

  Duration every(PbxSync s) {
    final d = s.of(syncSettings);
    if (s == PbxSync.extensions && _ws != null && d < eventsExtensionsEvery) {
      return eventsExtensionsEvery;
    }
    return d;
  }

  void setSyncEvery(PbxSync s, Duration d) {
    final wasOff = s.of(syncSettings) == Duration.zero;
    syncSettings = {...syncSettings, s.name: d.inSeconds};
    if (_api == null || _stopped) return;
    if (wasOff && d != Duration.zero) {
      _readAt.remove(s);
      sync(force: true);
    } else if (!syncing) {
      // Nuova cadenza: il prossimo giro si ricalcola.
      _timer?.cancel();
      _timer = Timer(_nextDelay(), sync);
    }
  }

  /// Ultima lettura di una voce in questa sessione (rubrica: anche dalla cache).
  DateTime? lastRead(PbxSync s) => _readAt[s];

  /// Voce da rileggere a questo giro: accesa e scaduta (o [now] richiesto).
  bool _due(PbxSync s, {bool now = false}) {
    final d = every(s);
    if (d == Duration.zero) return false;
    final at = _readAt[s];
    // Margine: il timer scatta a ridosso della scadenza.
    return now ||
        at == null ||
        DateTime.now().difference(at) >= d - const Duration(seconds: 2);
  }

  Future<void> start() async {
    await stop();
    // Un avvio superato da uno più recente (o da credenziali nuove) si ferma
    // dopo ogni attesa senza toccare dati né client.
    final gen = _gen;
    _stopped = false;
    final creds = await store.load();
    if (gen != _gen) return;
    cdrWholePbx = (await cdrStore?.load())?.wholePbx ?? false;
    if (gen != _gen) return;
    if (creds == null) {
      ok = false;
      status = store.isSet
          ? tr('Credenziali non leggibili su questo PC')
          : tr('Credenziali mancanti');
      onUpdate(this, false);
      return;
    }
    baseUrl = creds.baseUrl;
    ownExtension = creds.ownExtension;
    final api = apiFactory(creds);
    // Token rinnovato: il WebSocket si ricollega con quello nuovo.
    api.onTokens = () {
      if (identical(api, _api) && _ws != null) _ws!.close();
    };
    _api = api;
    // Dati della volta scorsa subito a schermo; la sync li aggiorna.
    final cached = directory.isEmpty ? await cache?.load() : null;
    // Staccato nel frattempo: chi l'ha staccato chiude anche questo client.
    if (gen != _gen) return;
    _readAt.clear();
    if (cached != null) {
      if (cached.contactsAt case final at?) _readAt[PbxSync.contacts] = at;
      directory = cached.directory;
      orgs = cached.orgs;
      contacts = cached.contacts;
      // Casella e presenze solo se sono del proprio interno (stesso account).
      if (voicemailOf != null) {
        voicemail = cached.voicemail;
        ownDetail = cached.detail;
      }
      recordCode = cached.recordCode;
      status = tr('Dati salvati · aggiornamento in corso');
      onUpdate(this, true);
    }
    await sync(force: true);
  }

  /// Rilettura dal PBX. Senza [force] viene saltata se l'ultima è troppo
  /// recente; [full] rilegge anche la rubrica aziendale ("Sincronizza ora").
  Future<void> sync({bool force = false, bool full = false}) async {
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
      // Interni sempre al primo giro: provano le credenziali e servono a tutto.
      final readExt = _due(PbxSync.extensions, now: force) || directory.isEmpty;
      final ext = readExt ? await api.listExtensions() : directory;
      if (readExt) _readAt[PbxSync.extensions] = DateTime.now();
      final idsChanged =
          ext
              .map((e) => e.id)
              .toSet()
              .difference(directory.map((e) => e.id).toSet())
              .isNotEmpty ||
          ext.length != directory.length;
      var newOrgs = orgs;
      var newContacts = contacts;
      if (_due(PbxSync.orgs, now: force || idsChanged)) {
        try {
          newOrgs = await api.listOrganizations();
        } catch (e) {
          // Reparti facoltativi: si tengono gli ultimi letti; non bloccano gli interni.
          optionalErrors.add('reparti: ${_short(e)}');
        }
        _readAt[PbxSync.orgs] = DateTime.now();
      }
      var newRecordCode = recordCode;
      if (_due(PbxSync.featureCodes, now: force)) {
        try {
          newRecordCode = await api.recordFeatureCode();
        } catch (e) {
          optionalErrors.add('codici funzione: ${_short(e)}');
        }
        _readAt[PbxSync.featureCodes] = DateTime.now();
      }
      final readContacts = _due(PbxSync.contacts, now: full);
      if (readContacts) {
        try {
          newContacts = await api.listCompanyContacts();
          _readAt[PbxSync.contacts] = DateTime.now();
        } catch (e) {
          // Rubrica facoltativa (permessi, formato diverso dalla documentazione).
          optionalErrors.add('rubrica: ${_short(e)}');
        }
      }
      final vmOf = voicemailOf;
      if (vmOf == null && (_voicemailOf ?? '').isNotEmpty) {
        // Credenziali senza interno (prima versione) o username cambiato.
        optionalErrors.add(
          'proprio interno: ${ownExtension.isEmpty ? 'non indicato nelle credenziali API' : 'diverso da quello delle credenziali API'}',
        );
      }
      var newVm = voicemail;
      if (vmOf == null ||
          vmOf.isEmpty ||
          every(PbxSync.voicemail) == Duration.zero) {
        // Spenta: la vista usa l'avviso SIP (MWI).
        newVm = null;
      } else if (_due(PbxSync.voicemail, now: force)) {
        try {
          newVm = await api.listVoicemail(vmOf);
        } catch (e) {
          newVm = null;
          optionalErrors.add('casella vocale: ${_short(e)}');
        }
        _readAt[PbxSync.voicemail] = DateTime.now();
      }
      // Dettaglio del proprio interno: anche su 30022 o su richiesta.
      final own = vmOf == null
          ? null
          : ext.where((e) => e.number == vmOf).firstOrNull;
      // Senza proprio interno non resta quello di prima (username cambiato).
      var newDetail = own == null ? null : ownDetail;
      if (own != null &&
          _due(PbxSync.ownDetail, now: _detailStale || force || idsChanged)) {
        try {
          newDetail = await api.getExtension(own.id);
          _detailStale = false;
        } catch (e) {
          optionalErrors.add('dettaglio interno: ${_short(e)}');
        }
        _readAt[PbxSync.ownDetail] = DateTime.now();
      }
      // Credenziali cambiate durante le letture (stop + clearData): sono dati
      // del PBX di prima, non vanno né in memoria né in cache.
      if (!identical(api, _api)) {
        _readAt.clear();
        return;
      }
      final detailChanged = !identical(newDetail, ownDetail);
      ownDetail = newDetail;
      recordCode = newRecordCode;
      final fp =
          '${_fingerprintOf(ext, newOrgs, newContacts)}\n'
          '${newVm?.map((m) => '${m.id}|${m.read}').join(',')}';
      changed = fp != _fingerprint;
      _fingerprint = fp;
      directory = ext;
      orgs = newOrgs;
      contacts = newContacts;
      // Cache aggiornata solo se i dati sono cambiati (non a ogni giro) o se la
      // rubrica è stata riletta (la sua data decide la prossima lettura).
      if (changed || detailChanged || readContacts) {
        unawaited(
          cache?.save(
            ext,
            newOrgs,
            newContacts,
            voicemail: newVm,
            detail: newDetail,
            recordCode: newRecordCode,
            contactsAt: _readAt[PbxSync.contacts],
          ),
        );
      }
      voicemail = newVm;
      lastSync = DateTime.now();
      _failures = 0;
      ok = true;
      status = tr('Sincronizzata · {e} interni, {o} reparti, {c} contatti', {
        'e': ext.length,
        'o': newOrgs.length,
        'c': newContacts.length,
      });
    } catch (e) {
      // Errore di un giro del PBX di prima (client chiuso): non conta.
      if (!identical(api, _api)) return;
      // e non contiene URL né token (YeastarApiException), solo operazione e codice.
      _failures++;
      ok = false;
      status = tr('Errore: {e} · nuovo tentativo tra {m} min', {
        'e': e,
        'm': _nextDelay().inMinutes,
      });
    } finally {
      syncing = false;
      // Un giro del PBX di prima ha tenuto occupata la prima sync del nuovo:
      // si rifà subito.
      if (!_stopped) {
        _timer = Timer(
          identical(api, _api) ? _nextDelay() : Duration.zero,
          sync,
        );
      }
      onUpdate(this, changed);
    }
    if (ok && realtime && _ws == null && _wsRetry == null) _connectEvents();
  }

  /// Salva sul PBX le modifiche di [edited] rispetto al dettaglio letto, solo
  /// sul proprio interno (id dall'elenco, per numero) e solo i campi ammessi;
  /// poi rilegge il dettaglio. Lancia se il PBX rifiuta.
  Future<void> updateOwnExtension(PbxExtensionDetail edited) async {
    final api = _api;
    final current = ownDetail;
    final own = directory.where((e) => e.number == voicemailOf).firstOrNull;
    if (api == null || current == null || own == null) {
      throw StateError('proprio interno non disponibile');
    }
    // Il dettaglio modificato e quello letto devono essere di quell'interno.
    if (edited.id != own.id || current.id != own.id) {
      throw StateError('non è il proprio interno');
    }
    final changes = edited.changesFrom(current);
    if (changes.isEmpty) return;
    if (!api.connected) await api.connect();
    await api.updateOwnExtension(own.id, changes);
    debugPrint('pbx $id: interno aggiornato (${changes.keys.join(', ')})');
    await refreshDetail();
  }

  /// Rilegge subito il dettaglio del proprio interno.
  Future<void> refreshDetail() async {
    _detailStale = true;
    await sync(force: true);
  }

  /// Accende o spegne il canale eventi senza riavviare la connessione.
  void setRealtime(bool on) {
    realtime = on;
    if (on) {
      _connectEvents();
    } else {
      _closeEvents();
      eventsStatus = '';
      callStatus.clear();
      liveCalls.clear();
      onUpdate(this, false);
    }
  }

  Future<void> _connectEvents() async {
    _wsRetry = null;
    final api = _api;
    if (!realtime || _stopped || api == null || !api.connected || _ws != null) {
      return;
    }
    try {
      final ws = await WebSocket.connect(
        api.eventsUri().toString(),
        headers: {HttpHeaders.userAgentHeader: YeastarApi.userAgent},
      ).timeout(const Duration(seconds: 15));
      // Client cambiato durante la connessione: socket del PBX di prima.
      if (!identical(api, _api) || _stopped) {
        unawaited(ws.close());
        return;
      }
      _ws = ws;
      ws.add(jsonEncode({'topic_list': eventTopics}));
      // Senza traffico il PBX chiude dopo 60 s.
      _heartbeat = Timer.periodic(
        const Duration(seconds: 30),
        (_) => ws.add('heartbeat'),
      );
      eventsStatus = tr('Eventi in tempo reale: collegamento…');
      // Solo il socket corrente: uno chiuso (credenziali cambiate, eventi
      // spenti) non scrive più stato né tocca quello nuovo.
      ws.listen(
        (data) {
          if (identical(ws, _ws)) _onEvent(data);
        },
        onDone: () {
          if (identical(ws, _ws)) _onEventsClosed();
        },
        onError: (_) {
          if (identical(ws, _ws)) _onEventsClosed();
        },
        cancelOnError: true,
      );
    } catch (e) {
      // Il messaggio di WebSocketException può contenere l'URL col token.
      _wsFailures++;
      eventsStatus = tr('Eventi non disponibili ({e}), nuovo tentativo', {
        'e': e.runtimeType,
      });
      _scheduleEvents();
    }
    onUpdate(this, false);
  }

  void _onEventsClosed() {
    _heartbeat?.cancel();
    _ws = null;
    if (!_stopped && realtime) {
      eventsStatus = tr('Eventi in tempo reale: riconnessione…');
      _scheduleEvents();
    }
    onUpdate(this, false);
  }

  void _scheduleEvents() {
    _wsRetry?.cancel();
    final secs = min(5 * pow(2, min(_wsFailures, 6)).toInt(), 300);
    _wsRetry = Timer(Duration(seconds: secs), _connectEvents);
  }

  void _closeEvents() {
    _wsRetry?.cancel();
    _wsRetry = null;
    _callsTimer?.cancel();
    _callsTimer = null;
    _heartbeat?.cancel();
    _ws?.close();
    _ws = null;
  }

  /// Fotografia via `call/query`: chi non c'è più è terminata, e dà il tipo
  /// (entrante / uscente / interna). Si applica solo se riescono tutte e tre.
  Future<void> _snapshotCalls() async {
    final api = _api;
    if (api == null || _snapshotting) return;
    _snapshotting = true;
    final started = DateTime.now();
    try {
      final fresh = <String, (String, List<LiveMember>)>{};
      for (final type in _callTypes) {
        try {
          for (final e in (await api.queryCalls(type)).entries) {
            fresh[e.key] = (type, e.value);
          }
        } catch (e) {
          debugPrint('[drinphone] call/query $type: ${_short(e)}');
          return;
        }
      }
      // Lettura del PBX di prima (credenziali cambiate nel frattempo).
      if (!identical(api, _api)) return;
      // Le chiamate nate durante la lettura restano: le vedrà il giro dopo.
      liveCalls.removeWhere(
        (id, c) => !fresh.containsKey(id) && c.seen.isBefore(started),
      );
      for (final e in fresh.entries) {
        final members = [
          for (final m in e.value.$2)
            if (m.status != 'BYE') m,
        ];
        if (members.isEmpty) {
          liveCalls.remove(e.key);
          continue;
        }
        final c = liveCalls.putIfAbsent(e.key, () => LiveCall(e.key, members))
          ..members = members
          ..type = e.value.$1;
        if (c.talking) c.answered ??= DateTime.now();
      }
      onUpdate(this, false);
    } finally {
      _snapshotting = false;
      _scheduleCallsCheck(callsCheckEvery);
    }
  }

  void _scheduleCallsCheck(Duration after) {
    _callsTimer?.cancel();
    _callsTimer = null;
    if (_stopped || _ws == null || liveCalls.isEmpty) return;
    _callsTimer = Timer(after, _snapshotCalls);
  }

  /// Evento 30011: membri per identità; chi è in BYE esce. Una chiamata finisce
  /// quando non resta nessuno o, dopo un BYE, resta al più un capo.
  void _applyCall(Map<String, dynamic> msg) {
    final id = '${msg['call_id'] ?? ''}';
    if (id.isEmpty) return;
    final incoming = LiveMember.parse(msg['members'] as List? ?? const []);
    final isNew = !liveCalls.containsKey(id);
    final call = liveCalls.putIfAbsent(id, () => LiveCall(id, const []));
    final byKey = {for (final m in call.members) m.key: m};
    var hungUp = false;
    for (final m in incoming) {
      if (m.status == 'BYE') {
        byKey.remove(m.key);
        hungUp = true;
      } else {
        byKey[m.key] = m;
      }
    }
    call.members = byKey.values.toList();
    if (call.talking) call.answered ??= DateTime.now();
    // `internal` descrive la tratta, non è un capo della chiamata.
    final parties = call.members.where((m) => m.kind != 'internal').length;
    if (call.members.isEmpty || (hungUp && parties <= 1)) {
      liveCalls.remove(id);
    }
    // Chiamata nuova: tipo da call/query a breve; poi controllo periodico.
    if (isNew && liveCalls.containsKey(id)) {
      _scheduleCallsCheck(const Duration(seconds: 2));
    } else if (_callsTimer == null) {
      _scheduleCallsCheck(callsCheckEvery);
    }
  }

  static BlfStatus? _callState(String s) => switch (s.toLowerCase()) {
    'idle' => BlfStatus.idle,
    'ringing' => BlfStatus.ringing,
    'busy' => BlfStatus.busy,
    _ => null,
  };

  void _onEvent(dynamic data) {
    if (data is! String || data.startsWith('heartbeat')) return;
    Map<String, dynamic> j;
    try {
      j = jsonDecode(data) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    // Risposta alla sottoscrizione.
    if (j.containsKey('errcode') && !j.containsKey('type')) {
      final code = j['errcode'];
      eventsStatus = code == 0
          ? tr('Eventi in tempo reale attivi')
          : tr('Eventi rifiutati dal PBX (errcode {c})', {'c': code});
      if (code == 0) {
        _wsFailures = 0;
        _snapshotCalls();
      }
      onUpdate(this, false);
      return;
    }
    final type = (j['type'] as num?)?.toInt();
    var msg = j['msg'];
    if (msg is String) {
      try {
        msg = jsonDecode(msg);
      } on FormatException {
        return;
      }
    }
    if (msg is! Map<String, dynamic>) return;
    // Solo tipo e nomi dei campi nel log (i valori sono dati personali);
    // per 30011 anche tipo e stato dei membri, senza numeri.
    final shape = type == 30011
        ? LiveMember.parse(msg['members'] as List? ?? const [])
              .map((m) => '${m.kind}:${m.status}')
              .toList()
        : msg.keys.toList();
    debugPrint('[drinphone] evento pbx $type $shape');
    final ext = '${msg['extension'] ?? msg['number'] ?? ''}';
    switch (type) {
      case 30008:
        final st = _callState('${msg['status'] ?? ''}');
        if (ext.isNotEmpty && st != null) callStatus[ext] = st;
        onUpdate(this, false);
      case 30009:
        final presence = '${msg['presence_status'] ?? msg['status'] ?? ''}';
        if (ext.isNotEmpty && presence.isNotEmpty) {
          if (ext == voicemailOf) ownDetail = ownDetail?.withPresence(presence);
          directory = [
            for (final e in directory)
              e.number == ext
                  ? PbxExtension(
                      id: e.id,
                      number: e.number,
                      name: e.name,
                      email: e.email,
                      mobile: e.mobile,
                      presence: presence,
                    )
                  : e,
          ];
          onUpdate(this, false);
        }
      case 30011:
        _applyCall(msg);
        onUpdate(this, false);
      case 30022:
        // Anagrafica cambiata: rilettura a breve (più eventi ravvicinati = una).
        if (ext.isEmpty || ext == voicemailOf) _detailStale = true;
        _resyncSoon?.cancel();
        _resyncSoon = Timer(
          const Duration(seconds: 3),
          () => sync(force: true),
        );
      default:
        break;
    }
  }

  /// Prossimo giro: la prima voce accesa che scade; con errori, attesa
  /// crescente a partire dalla cadenza degli interni.
  Duration _nextDelay() {
    if (_failures > 0) {
      final s = every(PbxSync.extensions).inSeconds * pow(2, min(_failures, 4));
      return Duration(seconds: min(s.toInt(), maxBackoff.inSeconds));
    }
    final now = DateTime.now();
    var next = every(PbxSync.extensions);
    for (final item in PbxSync.values) {
      final d = every(item);
      if (d == Duration.zero) continue;
      final at = _readAt[item];
      final left = at == null ? Duration.zero : d - now.difference(at);
      if (left < next) next = left;
    }
    return next < minGap ? minGap : next;
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

  Future<void> stop() async => _detach()?.close();

  /// Generazione dell'avvio: cambia a ogni [_detach].
  int _gen = 0;

  /// Ferma subito, senza rete: il client lasciato va chiuso (revoca token).
  YeastarApi? _detach() {
    _gen++;
    _stopped = true;
    _timer?.cancel();
    _resyncSoon?.cancel();
    _closeEvents();
    final api = _api;
    _api = null;
    return api;
  }

  /// Credenziali nuove (forse un altro PBX). Subito e in locale: fermo, dati e
  /// cache buttati, poi credenziali salvate (in quest'ordine: un'uscita a metà
  /// non lascia credenziali nuove con la cache vecchia). Revoca del token
  /// vecchio e prima lettura in sottofondo: chi salva non aspetta la rete.
  /// Se il salvataggio fallisce, il client vecchio si chiude comunque e la
  /// connessione riparte con le credenziali rimaste; l'errore torna a chi salva.
  Future<void> replaceCredentials(ApiCredentials creds) async {
    final old = _detach();
    try {
      await clearData();
      // Altro PBX: il database CDR (e il suo permesso) era di quello di prima.
      if (creds.baseUrl != baseUrl) {
        await cdrStore?.clear();
        cdrWholePbx = false;
      }
      await store.save(creds);
    } finally {
      unawaited(old?.close());
      unawaited(start());
    }
  }

  /// Ferma e cancella le credenziali di questa connessione.
  Future<void> forget() async {
    await stop();
    await store.clear();
    await cdrStore?.clear();
    await clearData();
  }

  /// Butta i dati letti dal PBX, in memoria e in cache: con credenziali nuove
  /// il PBX può essere un altro, e i suoi id di interno non sono questi.
  Future<void> clearData() async {
    await cache?.clear();
    directory = const [];
    orgs = const [];
    contacts = const [];
    ownDetail = null;
    voicemail = null;
    recordCode = null;
    callStatus.clear();
    liveCalls.clear();
    lastSync = null;
    _fingerprint = '';
    _readAt.clear();
    _detailStale = true;
  }
}
