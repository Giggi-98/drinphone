// Adattatore SipEngine -> liblinphone (API C) via dart:ffi. Windows: SDK
// ufficiale linphone-sdk-win64, DLL installate accanto all'exe dal CMake del
// runner (windows/CMakeLists.txt). Il core gira senza linphonerc (config NULL):
// nessuna impostazione, e quindi nessuna password, viene scritta su disco dal
// motore; l'account viene ripassato a ogni avvio dallo storage sicuro.
// Prove e trappole del binding: docs/spikes/F0-A.md.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'dialog_info.dart';
import 'sip_engine.dart';

typedef _RegStateCb = Void Function(
  Pointer<Void> core,
  Pointer<Void> account,
  Int32 state,
  Pointer<Utf8> msg,
);
typedef _CallStateCb = Void Function(
  Pointer<Void> core,
  Pointer<Void> call,
  Int32 state,
  Pointer<Utf8> msg,
);
typedef _NotifyCb = Void Function(
  Pointer<Void> core,
  Pointer<Void> event,
  Pointer<Utf8> notifiedEvent,
  Pointer<Void> body,
);
typedef _SubStateCb = Void Function(
  Pointer<Void> core,
  Pointer<Void> event,
  Int32 state,
);

typedef _MwiCb = Void Function(Pointer<Void> account, Pointer<Void> mwi);
typedef _TransferCb = Void Function(
  Pointer<Void> core,
  Pointer<Void> call,
  Int32 state,
);

typedef _VoidP = Void Function(Pointer<Void>);
typedef _VoidPDart = void Function(Pointer<Void>);
typedef _VoidPS = Void Function(Pointer<Void>, Pointer<Utf8>);
typedef _VoidPSDart = void Function(Pointer<Void>, Pointer<Utf8>);
typedef _IntP = Int32 Function(Pointer<Void>);
typedef _IntPDart = int Function(Pointer<Void>);
typedef _IntPP = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _IntPPDart = int Function(Pointer<Void>, Pointer<Void>);
typedef _VoidPP = Void Function(Pointer<Void>, Pointer<Void>);
typedef _VoidPPDart = void Function(Pointer<Void>, Pointer<Void>);
typedef _PP = Pointer<Void> Function(Pointer<Void>);
typedef _PS = Pointer<Utf8> Function(Pointer<Void>);

class LinphoneFfiEngine implements SipEngine {
  final _registrations = StreamController<RegistrationEvent>.broadcast();
  final _calls = StreamController<CallEvent>.broadcast();
  final _dialogs = StreamController<BlfEvent>.broadcast();
  final _voicemail = StreamController<VoicemailEvent>.broadcast();
  final _transfers = StreamController<bool>.broadcast();
  NativeCallable<_TransferCb>? _transferCb;
  NativeCallable<_MwiCb>? _mwiCb;

  late final DynamicLibrary _lib;
  Pointer<Void> _factory = nullptr;
  Pointer<Void> _core = nullptr;
  // Chiamate vive per id (= indirizzo dell'oggetto LinphoneCall finché non è Released).
  final _callPtrs = <int, Pointer<Void>>{};
  final _directions = <int, CallDirection>{};
  Pointer<Void> _ptr(int id) => _callPtrs[id] ?? nullptr;
  Timer? _iterate;
  NativeCallable<_RegStateCb>? _regCb;
  NativeCallable<_CallStateCb>? _callCb;
  NativeCallable<_NotifyCb>? _notifyCb;
  NativeCallable<_SubStateCb>? _subStateCb;
  String _host = '';
  // BLF: subscription per interno (LinphoneEvent* posseduto da noi) e stato dialog.
  final _subs = <String, Pointer<Void>>{};
  final _subTrackers = <String, DialogInfoTracker>{};

  @override
  Stream<RegistrationEvent> get registrations => _registrations.stream;
  @override
  Stream<CallEvent> get calls => _calls.stream;
  @override
  Stream<BlfEvent> get dialogs => _dialogs.stream;
  @override
  Stream<VoicemailEvent> get voicemail => _voicemail.stream;
  @override
  Stream<bool> get transfers => _transfers.stream;

  late final _pause = _lib.lookupFunction<_IntP, _IntPDart>(
    'linphone_call_pause',
  );
  late final _resume = _lib.lookupFunction<_IntP, _IntPDart>(
    'linphone_call_resume',
  );
  late final _transferTo = _lib.lookupFunction<_IntPP, _IntPPDart>(
    'linphone_call_transfer_to',
  );
  late final _transferToAnother = _lib.lookupFunction<_IntPP, _IntPPDart>(
    'linphone_call_transfer_to_another',
  );
  late final _setTransferCb = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<NativeFunction<_TransferCb>>),
        void Function(Pointer<Void>, Pointer<NativeFunction<_TransferCb>>)
      >('linphone_core_cbs_set_transfer_state_changed');

  // Stato della chiamata trasferita (LinphoneCallState): Connected 7 /
  // StreamsRunning 8 = trasferimento riuscito, Error 13 = rifiutato.
  void _onTransfer(Pointer<Void> core, Pointer<Void> call, int state) {
    if (state == 7 || state == 8) _transfers.add(true);
    if (state == 13) _transfers.add(false);
  }

  @override
  Future<void> hold(int id) async {
    if (_ptr(id) != nullptr) _pause(_ptr(id));
  }

  @override
  Future<void> resume(int id) async {
    if (_ptr(id) != nullptr) _resume(_ptr(id));
  }

  @override
  Future<void> transferAttended(int id, int toId) async {
    if (_ptr(id) == nullptr || _ptr(toId) == nullptr) return;
    if (_transferToAnother(_ptr(id), _ptr(toId)) != 0) _transfers.add(false);
  }

  @override
  Future<void> transfer(int id, String number) async {
    final call = _ptr(id);
    if (call == nullptr || number.isEmpty) return;
    using((a) {
      final to = _createAddress(
        _factory,
        'sip:$number@$_host'.toNativeUtf8(allocator: a),
      );
      if (to == nullptr) {
        _transfers.add(false);
        return;
      }
      if (_transferTo(call, to) != 0) _transfers.add(false);
      _addressUnref(to);
    });
  }

  late final _createAccountCbs = _lib.lookupFunction<_PP, _PP>(
    'linphone_factory_create_account_cbs',
  );
  late final _setMwiCb = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<NativeFunction<_MwiCb>>),
        void Function(Pointer<Void>, Pointer<NativeFunction<_MwiCb>>)
      >('linphone_account_cbs_set_message_waiting_indication_changed');
  late final _accountAddCbs = _lib.lookupFunction<_VoidPP, _VoidPPDart>(
    'linphone_account_add_callbacks',
  );
  late final _accountCbsUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_account_cbs_unref',
  );
  late final _mwiNew = _lib
      .lookupFunction<
        Uint32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('linphone_message_waiting_indication_get_nb_new');
  late final _mwiOld = _lib
      .lookupFunction<
        Uint32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('linphone_message_waiting_indication_get_nb_old');

  void _onMwi(Pointer<Void> account, Pointer<Void> mwi) {
    if (mwi == nullptr) return;
    _voicemail.add(VoicemailEvent(_mwiNew(mwi), _mwiOld(mwi)));
  }

  late final _factoryGet = _lib
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'linphone_factory_get',
      );
  late final _setTopResources = _lib.lookupFunction<_VoidPS, _VoidPSDart>(
    'linphone_factory_set_top_resources_dir',
  );
  late final _setMsPlugins = _lib.lookupFunction<_VoidPS, _VoidPSDart>(
    'linphone_factory_set_msplugins_dir',
  );
  late final _setDataDir = _lib.lookupFunction<_VoidPS, _VoidPSDart>(
    'linphone_factory_set_data_dir',
  );
  late final _createCore = _lib
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Void>,
        ),
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Void>,
        )
      >('linphone_factory_create_core_3');
  late final _createCbs = _lib.lookupFunction<_PP, _PP>(
    'linphone_factory_create_core_cbs',
  );
  late final _setRegCb = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<NativeFunction<_RegStateCb>>),
        void Function(Pointer<Void>, Pointer<NativeFunction<_RegStateCb>>)
      >('linphone_core_cbs_set_account_registration_state_changed');
  late final _setCallCb = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<NativeFunction<_CallStateCb>>),
        void Function(Pointer<Void>, Pointer<NativeFunction<_CallStateCb>>)
      >('linphone_core_cbs_set_call_state_changed');
  late final _setNotifyCb = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<NativeFunction<_NotifyCb>>),
        void Function(Pointer<Void>, Pointer<NativeFunction<_NotifyCb>>)
      >('linphone_core_cbs_set_notify_received');
  late final _setSubStateCb = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<NativeFunction<_SubStateCb>>),
        void Function(Pointer<Void>, Pointer<NativeFunction<_SubStateCb>>)
      >('linphone_core_cbs_set_subscription_state_changed');
  late final _createSubscribe = _lib
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Utf8>,
          Int32,
        ),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Utf8>, int)
      >('linphone_core_create_subscribe');
  late final _eventAddHeader = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
      >('linphone_event_add_custom_header');
  late final _eventSendSubscribe = _lib.lookupFunction<_IntPP, _IntPPDart>(
    'linphone_event_send_subscribe',
  );
  late final _eventTerminate = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_event_terminate',
  );
  late final _eventUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_event_unref',
  );
  late final _eventReason = _lib.lookupFunction<_IntP, _IntPDart>(
    'linphone_event_get_reason',
  );
  late final _reasonToString = _lib
      .lookupFunction<
        Pointer<Utf8> Function(Int32),
        Pointer<Utf8> Function(int)
      >('linphone_reason_to_string');
  late final _contentText = _lib.lookupFunction<_PS, _PS>(
    'linphone_content_get_utf8_text',
  );
  late final _addCbs = _lib.lookupFunction<_VoidPP, _VoidPPDart>(
    'linphone_core_add_callbacks',
  );
  late final _cbsUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_core_cbs_unref',
  );
  late final _version = _lib
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'linphone_core_get_version',
      );
  late final _setUserAgent = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
      >('linphone_core_set_user_agent');
  late final _createTransports = _lib.lookupFunction<_PP, _PP>(
    'linphone_factory_create_transports',
  );
  late final _setUdpPort = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('linphone_transports_set_udp_port');
  late final _setTcpPort = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('linphone_transports_set_tcp_port');
  late final _setTlsPort = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('linphone_transports_set_tls_port');
  late final _setTransports = _lib.lookupFunction<_IntPP, _IntPPDart>(
    'linphone_core_set_transports',
  );
  late final _transportsUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_transports_unref',
  );
  late final _enableVideoCapture = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_core_enable_video_capture');
  late final _enableVideoDisplay = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_core_enable_video_display');
  late final _start = _lib.lookupFunction<_IntP, _IntPDart>(
    'linphone_core_start',
  );
  late final _iterateFn = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_core_iterate',
  );
  late final _stop = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_core_stop',
  );
  late final _coreUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_core_unref',
  );

  late final _loggingGet = _lib
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'linphone_logging_service_get',
      );
  late final _setLogLevel = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('linphone_logging_service_set_log_level');
  late final _setLogFile = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Size),
        void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int)
      >('linphone_logging_service_set_log_file');

  late final _createAddress = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
      >('linphone_factory_create_address');
  late final _addressUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_address_unref',
  );
  late final _addressSetDisplayName = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('linphone_address_set_display_name');
  late final _addressUsername = _lib.lookupFunction<_PS, _PS>(
    'linphone_address_get_username',
  );
  late final _addressDisplayName = _lib.lookupFunction<_PS, _PS>(
    'linphone_address_get_display_name',
  );

  late final _createAuthInfo = _lib
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
        ),
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
        )
      >('linphone_factory_create_auth_info');
  late final _addAuthInfo = _lib.lookupFunction<_VoidPP, _VoidPPDart>(
    'linphone_core_add_auth_info',
  );
  late final _authInfoUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_auth_info_unref',
  );
  late final _clearAuthInfo = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_core_clear_all_auth_info',
  );

  late final _createParams = _lib.lookupFunction<_PP, _PP>(
    'linphone_core_create_account_params',
  );
  late final _paramsUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_account_params_unref',
  );
  late final _setIdentity = _lib.lookupFunction<_IntPP, _IntPPDart>(
    'linphone_account_params_set_identity_address',
  );
  late final _setServer = _lib.lookupFunction<_IntPP, _IntPPDart>(
    'linphone_account_params_set_server_address',
  );
  late final _setTransport = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('linphone_account_params_set_transport');
  late final _enableRegister = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_account_params_enable_register');
  late final _createAccount = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
      >('linphone_core_create_account');
  late final _addAccount = _lib.lookupFunction<_IntPP, _IntPPDart>(
    'linphone_core_add_account',
  );
  late final _accountUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_account_unref',
  );
  late final _setDefault = _lib.lookupFunction<_VoidPP, _VoidPPDart>(
    'linphone_core_set_default_account',
  );
  late final _clearAccounts = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_core_clear_accounts',
  );

  late final _invite = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
      >('linphone_core_invite');
  late final _accept = _lib.lookupFunction<_IntP, _IntPDart>(
    'linphone_call_accept',
  );
  late final _terminate = _lib.lookupFunction<_IntP, _IntPDart>(
    'linphone_call_terminate',
  );
  late final _remoteAddress = _lib.lookupFunction<_PP, _PP>(
    'linphone_call_get_remote_address',
  );
  late final _enableMic = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_core_enable_mic');
  late final _sendDtmf = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Char),
        int Function(Pointer<Void>, int)
      >('linphone_call_send_dtmf');

  // LinphoneLogLevel (logging.h): bitmask, Debug = 1 << 0, Message = 1 << 2.
  static const _logDebug = 1;
  static const _logMessage = 4;

  @override
  Future<String> start({
    required String dataDir,
    required String logDir,
    required bool debug,
  }) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    _lib = DynamicLibrary.open(
      Platform.isWindows
          ? '$exeDir${Platform.pathSeparator}liblinphone.dll'
          : 'liblinphone.so',
    );
    _factory = _factoryGet();
    final sep = Platform.pathSeparator;
    await Directory(dataDir).create(recursive: true);
    await Directory(logDir).create(recursive: true);

    using((a) {
      final log = _loggingGet();
      _setLogLevel(log, debug ? _logDebug : _logMessage);
      _setLogFile(
        log,
        logDir.toNativeUtf8(allocator: a),
        'linphone.log'.toNativeUtf8(allocator: a),
        10 * 1024 * 1024,
      );
      // Senza queste cartelle il core non trova grammatiche (abort) né WASAPI
      // (nessuna scheda audio): vedi F0-A, punti 2 e 6.
      _setTopResources(
        _factory,
        '$exeDir${sep}linphone${sep}share'.toNativeUtf8(allocator: a),
      );
      _setMsPlugins(
        _factory,
        '$exeDir${sep}linphone${sep}plugins'.toNativeUtf8(allocator: a),
      );
      _setDataDir(_factory, dataDir.toNativeUtf8(allocator: a));
    });

    _core = _createCore(_factory, nullptr, nullptr, nullptr);
    if (_core == nullptr) {
      throw StateError('linphone_factory_create_core_3 ha restituito NULL');
    }

    _regCb = NativeCallable<_RegStateCb>.isolateLocal(_onRegistration);
    _callCb = NativeCallable<_CallStateCb>.isolateLocal(_onCallState);
    _notifyCb = NativeCallable<_NotifyCb>.isolateLocal(_onNotify);
    _subStateCb = NativeCallable<_SubStateCb>.isolateLocal(_onSubState);
    final cbs = _createCbs(_factory);
    _setRegCb(cbs, _regCb!.nativeFunction);
    _setCallCb(cbs, _callCb!.nativeFunction);
    _setNotifyCb(cbs, _notifyCb!.nativeFunction);
    _setSubStateCb(cbs, _subStateCb!.nativeFunction);
    _transferCb = NativeCallable<_TransferCb>.isolateLocal(_onTransfer);
    _setTransferCb(cbs, _transferCb!.nativeFunction);
    _addCbs(_core, cbs);
    _cbsUnref(cbs);

    using(
      (a) => _setUserAgent(
        _core,
        'DrinPhone'.toNativeUtf8(allocator: a),
        '0.1.0'.toNativeUtf8(allocator: a),
      ),
    );

    // Porte locali casuali (LC_SIP_TRANSPORT_RANDOM = -1, misc.h): il default
    // 5060 fisso collide con altri softphone sulla stessa macchina.
    final transports = _createTransports(_factory);
    _setUdpPort(transports, -1);
    _setTcpPort(transports, -1);
    _setTlsPort(transports, -1);
    _setTransports(_core, transports);
    _transportsUnref(transports);
    // Solo audio: niente webcam né offerta video nell'SDP.
    _enableVideoCapture(_core, 0);
    _enableVideoDisplay(_core, 0);

    final rc = _start(_core);
    if (rc != 0) throw StateError('linphone_core_start rc=$rc');
    // Tutti i callback arrivano dentro iterate(), quindi sul thread di questo isolate.
    _iterate = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => _iterateFn(_core),
    );
    return _version().toDartString();
  }

  @override
  Future<void> register(SipAccount account) async {
    _dropSubscriptions();
    _clearAccounts(_core);
    _clearAuthInfo(_core);
    using((a) {
      final host = account.domain.split(':').first;
      _host = host;
      final auth = _createAuthInfo(
        _factory,
        account.username.toNativeUtf8(allocator: a),
        nullptr,
        account.password.toNativeUtf8(allocator: a),
        nullptr,
        nullptr,
        host.toNativeUtf8(allocator: a),
      );
      _addAuthInfo(_core, auth);
      _authInfoUnref(auth);

      final identity = _createAddress(
        _factory,
        'sip:${account.username}@$host'.toNativeUtf8(allocator: a),
      );
      if (identity == nullptr) {
        throw ArgumentError('Utente o dominio SIP non valido');
      }
      if (account.displayName.isNotEmpty) {
        _addressSetDisplayName(
          identity,
          account.displayName.toNativeUtf8(allocator: a),
        );
      }
      final server = _createAddress(
        _factory,
        'sip:${account.domain}'.toNativeUtf8(allocator: a),
      );
      if (server == nullptr) {
        _addressUnref(identity);
        throw ArgumentError('Server SIP non valido');
      }
      final params = _createParams(_core);
      _setIdentity(params, identity);
      _setServer(params, server);
      // LinphoneTransportType: Udp 0, Tcp 1, Tls 2 (types.h).
      _setTransport(params, account.transport.index);
      _enableRegister(params, 1);
      final acc = _createAccount(_core, params);
      // Casella vocale: il PBX invia NOTIFY message-summary sull'account.
      _mwiCb ??= NativeCallable<_MwiCb>.isolateLocal(_onMwi);
      final accCbs = _createAccountCbs(_factory);
      _setMwiCb(accCbs, _mwiCb!.nativeFunction);
      _accountAddCbs(acc, accCbs);
      _accountCbsUnref(accCbs);
      _addAccount(_core, acc);
      _setDefault(_core, acc);
      _accountUnref(acc);
      _paramsUnref(params);
      _addressUnref(server);
      _addressUnref(identity);
    });
  }

  @override
  Future<void> unregister() async {
    _dropSubscriptions();
    _clearAccounts(_core);
    _clearAuthInfo(_core);
  }

  @override
  Future<int?> dial(String number) async {
    // Un numero nudo viene completato dal core con il dominio dell'account predefinito.
    final call = using(
      (a) => _invite(_core, number.toNativeUtf8(allocator: a)),
    );
    if (call != nullptr) {
      _callPtrs.putIfAbsent(call.address, () => call);
      _directions.putIfAbsent(call.address, () => CallDirection.outgoing);
      return call.address;
    } else {
      _calls.add(
        CallEvent(
          phase: CallPhase.error,
          direction: CallDirection.outgoing,
          remoteNumber: number,
          message: 'Chiamata non avviata',
        ),
      );
    }
    return null;
  }

  @override
  Future<void> answer(int id) async {
    if (_ptr(id) != nullptr) _accept(_ptr(id));
  }

  @override
  Future<void> hangup(int id) async {
    if (_ptr(id) != nullptr) _terminate(_ptr(id));
  }

  @override
  Future<void> setMicMuted(bool muted) async =>
      _enableMic(_core, muted ? 0 : 1);

  @override
  Future<void> sendDtmf(int id, String digit) async {
    if (_ptr(id) != nullptr && digit.isNotEmpty) {
      _sendDtmf(_ptr(id), digit.codeUnitAt(0));
    }
  }

  @override
  Future<void> watchDialogs(Set<String> numbers) async {
    for (final n in _subs.keys.where((n) => !numbers.contains(n)).toList()) {
      _dropSubscription(n);
    }
    for (final n in numbers.where((n) => !_subs.containsKey(n))) {
      final ev = using((a) {
        final addr = _createAddress(
          _factory,
          'sip:$n@$_host'.toNativeUtf8(allocator: a),
        );
        if (addr == nullptr) return nullptr;
        // 600 s richiesti; il PBX può accorciarli, il core rinnova da solo.
        final ev = _createSubscribe(
          _core,
          addr,
          'dialog'.toNativeUtf8(allocator: a),
          600,
        );
        _addressUnref(addr);
        if (ev == nullptr) return nullptr;
        _eventAddHeader(
          ev,
          'Accept'.toNativeUtf8(allocator: a),
          'application/dialog-info+xml'.toNativeUtf8(allocator: a),
        );
        return ev;
      });
      if (ev == nullptr) {
        _dialogs.add(BlfEvent(n, BlfStatus.unknown, 'indirizzo non valido'));
        continue;
      }
      _subs[n] = ev;
      _subTrackers[n] = DialogInfoTracker();
      _eventSendSubscribe(ev, nullptr);
      _dialogs.add(BlfEvent(n, BlfStatus.unknown));
    }
  }

  void _dropSubscription(String n) {
    final ev = _subs.remove(n);
    _subTrackers.remove(n);
    if (ev != null) {
      _eventTerminate(ev);
      _eventUnref(ev);
    }
  }

  void _dropSubscriptions() {
    for (final n in _subs.keys.toList()) {
      _dropSubscription(n);
    }
  }

  String? _numberOf(Pointer<Void> ev) {
    for (final e in _subs.entries) {
      if (e.value == ev) return e.key;
    }
    return null;
  }

  void _onNotify(
    Pointer<Void> core,
    Pointer<Void> ev,
    Pointer<Utf8> notifiedEvent,
    Pointer<Void> body,
  ) {
    // Casella vocale: Yeastar manda NOTIFY message-summary fuori dialogo e senza
    // Message-Account (liblinphone non lo abbina all'account, e via RAS la
    // SUBSCRIBE esplicita riceve 500): si legge qui "Voice-Message: n/o" (RFC 3842).
    if (_str(notifiedEvent) == 'message-summary' && body != nullptr) {
      final m = RegExp(r'Voice-Message:\s*(\d+)/(\d+)')
          .firstMatch(_str(_contentText(body)));
      if (m != null) {
        _voicemail.add(
          VoicemailEvent(int.parse(m.group(1)!), int.parse(m.group(2)!)),
        );
      }
      return;
    }
    final n = _numberOf(ev);
    if (n == null || _str(notifiedEvent) != 'dialog') return;
    final xml = body == nullptr ? '' : _str(_contentText(body));
    _dialogs.add(BlfEvent(n, _subTrackers[n]!.apply(xml)));
  }

  // LinphoneSubscriptionState (types.h): Active 4, Terminated 5, Error 6.
  void _onSubState(Pointer<Void> core, Pointer<Void> ev, int state) {
    final n = _numberOf(ev);
    if (n == null || (state != 5 && state != 6)) return;
    final reason = _str(_reasonToString(_eventReason(ev)));
    _dialogs.add(BlfEvent(n, BlfStatus.unknown, reason));
    // Fuori dal callback: si libera l'evento, il prossimo watchDialogs (a ogni
    // rinnovo della registrazione) riprova. Ritmo dei tentativi = refresh REGISTER.
    Future.microtask(() {
      if (_subs[n] == ev) {
        _subs.remove(n);
        _subTrackers.remove(n);
        _eventUnref(ev);
      }
    });
  }

  @override
  Future<void> stop() async {
    _iterate?.cancel();
    if (_core != nullptr) {
      _dropSubscriptions();
      _stop(_core);
      _coreUnref(_core);
      _core = nullptr;
    }
    _regCb?.close();
    _callCb?.close();
    _notifyCb?.close();
    _mwiCb?.close();
    _transferCb?.close();
    _subStateCb?.close();
  }

  // LinphoneRegistrationState (types.h): None 0, Progress 1, Ok 2, Cleared 3,
  // Failed 4, Refreshing 5.
  void _onRegistration(
    Pointer<Void> core,
    Pointer<Void> account,
    int state,
    Pointer<Utf8> msg,
  ) {
    const map = {
      0: RegistrationStatus.none,
      1: RegistrationStatus.progress,
      2: RegistrationStatus.ok,
      3: RegistrationStatus.cleared,
      4: RegistrationStatus.failed,
      5: RegistrationStatus.ok,
    };
    _registrations.add(
      RegistrationEvent(map[state] ?? RegistrationStatus.none, _str(msg)),
    );
  }

  // LinphoneCallState (enums/call-enums.h).
  void _onCallState(
    Pointer<Void> core,
    Pointer<Void> call,
    int state,
    Pointer<Utf8> msg,
  ) {
    final id = call.address;
    if (!_callPtrs.containsKey(id)) {
      if (state == 19) return;
      // Nuova chiamata: in arrivo (anche durante un'altra = avviso di chiamata)
      // o in uscita avviata dal core.
      _callPtrs[id] = call;
      _directions[id] = state == 1 || state == 2
          ? CallDirection.incoming
          : CallDirection.outgoing;
    }
    if (state == 19) {
      // Released: il core libera l'oggetto, il puntatore non è più valido.
      _callPtrs.remove(id);
      _directions.remove(id);
      return;
    }
    final phase = switch (state) {
      1 || 2 || 17 => CallPhase.incoming,
      3 || 4 || 5 || 6 => CallPhase.outgoing,
      10 || 15 => CallPhase.paused,
      13 => CallPhase.error,
      14 => CallPhase.ended,
      _ => CallPhase.active,
    };
    final remote = _remoteAddress(call);
    _calls.add(
      CallEvent(
        id: id,
        phase: phase,
        direction: _directions[id] ?? CallDirection.outgoing,
        remoteNumber: remote == nullptr ? '' : _str(_addressUsername(remote)),
        remoteName: remote == nullptr ? '' : _str(_addressDisplayName(remote)),
        message: _str(msg),
      ),
    );
  }

  static String _str(Pointer<Utf8> p) => p == nullptr ? '' : p.toDartString();
}
