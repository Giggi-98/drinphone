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

  late final DynamicLibrary _lib;
  Pointer<Void> _factory = nullptr;
  Pointer<Void> _core = nullptr;
  Pointer<Void> _call = nullptr;
  CallDirection _direction = CallDirection.outgoing;
  Timer? _iterate;
  NativeCallable<_RegStateCb>? _regCb;
  NativeCallable<_CallStateCb>? _callCb;

  @override
  Stream<RegistrationEvent> get registrations => _registrations.stream;
  @override
  Stream<CallEvent> get calls => _calls.stream;

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
    final cbs = _createCbs(_factory);
    _setRegCb(cbs, _regCb!.nativeFunction);
    _setCallCb(cbs, _callCb!.nativeFunction);
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
    _clearAccounts(_core);
    _clearAuthInfo(_core);
    using((a) {
      final host = account.domain.split(':').first;
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
    _clearAccounts(_core);
    _clearAuthInfo(_core);
  }

  @override
  Future<void> dial(String number) async {
    if (_call != nullptr) return;
    // Un numero nudo viene completato dal core con il dominio dell'account predefinito.
    final call = using(
      (a) => _invite(_core, number.toNativeUtf8(allocator: a)),
    );
    if (call == nullptr) {
      _calls.add(
        CallEvent(
          phase: CallPhase.error,
          direction: CallDirection.outgoing,
          remoteNumber: number,
          message: 'Chiamata non avviata',
        ),
      );
    }
  }

  @override
  Future<void> answer() async {
    if (_call != nullptr) _accept(_call);
  }

  @override
  Future<void> hangup() async {
    if (_call != nullptr) _terminate(_call);
  }

  @override
  Future<void> setMicMuted(bool muted) async =>
      _enableMic(_core, muted ? 0 : 1);

  @override
  Future<void> sendDtmf(String digit) async {
    if (_call != nullptr && digit.isNotEmpty) {
      _sendDtmf(_call, digit.codeUnitAt(0));
    }
  }

  @override
  Future<void> stop() async {
    _iterate?.cancel();
    if (_core != nullptr) {
      _stop(_core);
      _coreUnref(_core);
      _core = nullptr;
    }
    _regCb?.close();
    _callCb?.close();
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
    if (_call == nullptr && (state == 1 || state == 3)) {
      _call = call;
      _direction = state == 1 ? CallDirection.incoming : CallDirection.outgoing;
    } else if (call != _call) {
      // Una sola chiamata alla volta per ora: una seconda in arrivo viene chiusa.
      if (state == 1) _terminate(call);
      return;
    }
    if (state == 19) {
      // Released: il core libera l'oggetto, il puntatore non è più valido.
      _call = nullptr;
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
        phase: phase,
        direction: _direction,
        remoteNumber: remote == nullptr ? '' : _str(_addressUsername(remote)),
        remoteName: remote == nullptr ? '' : _str(_addressDisplayName(remote)),
        message: _str(msg),
      ),
    );
  }

  static String _str(Pointer<Utf8> p) => p == nullptr ? '' : p.toDartString();
}
