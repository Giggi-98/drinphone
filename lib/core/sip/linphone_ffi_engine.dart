// Adattatore SipEngine -> liblinphone (API C) via dart:ffi. Windows: SDK
// ufficiale linphone-sdk-win64, DLL installate accanto all'exe dal CMake del
// runner (windows/CMakeLists.txt). Il core gira senza linphonerc (config NULL):
// nessuna impostazione, e quindi nessuna password, viene scritta su disco dal
// motore; l'account viene ripassato a ogni avvio dallo storage sicuro.
// Prove e trappole del binding: docs/spikes/F0-A.md.
import 'dart:async';
import 'dart:convert';
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
typedef _PPP = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _PPPP = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
);

/// mediastreamer2/msogl.h: contesto per il filtro di visualizzazione MSOGL.
final class _OglContextInfo extends Struct {
  external Pointer<Void> window;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  external Pointer<Void> getProcAddress;
}

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
  // Account registrati: id -> LinphoneAccount (ref tenuta finché registrati).
  final _accounts = <String, Pointer<Void>>{};
  final _accountHosts = <String, String>{};
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

  late final _createCallParams = _lib.lookupFunction<_PPP, _PPP>(
    'linphone_core_create_call_params',
  );
  late final _callParamsSetAccount = _lib.lookupFunction<_VoidPP, _VoidPPDart>(
    'linphone_call_params_set_account',
  );
  late final _callParamsUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_call_params_unref',
  );
  late final _inviteWithParams = _lib.lookupFunction<_PPPP, _PPPP>(
    'linphone_core_invite_address_with_params',
  );

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

  late final _callGetParams = _lib.lookupFunction<_PP, _PP>(
    'linphone_call_get_params',
  );
  late final _callParamsGetAccount = _lib.lookupFunction<_PP, _PP>(
    'linphone_call_params_get_account',
  );

  /// Host dell'account su cui viaggia la chiamata (multi-account), o del
  /// predefinito.
  String _hostOfCall(Pointer<Void> call) {
    final params = _callGetParams(call);
    final acc = params == nullptr ? nullptr : _callParamsGetAccount(params);
    for (final e in _accounts.entries) {
      if (e.value == acc) return _accountHosts[e.key] ?? '';
    }
    return _accountHosts.values.firstOrNull ?? '';
  }

  late final _soundDevices = _lib
      .lookupFunction<
        Pointer<Pointer<Utf8>> Function(Pointer<Void>),
        Pointer<Pointer<Utf8>> Function(Pointer<Void>)
      >('linphone_core_get_sound_devices');
  late final _canCapture = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('linphone_core_sound_device_can_capture');
  late final _canPlayback = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('linphone_core_sound_device_can_playback');
  late final _reloadSound = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_core_reload_sound_devices',
  );
  late final _getCapture = _lib.lookupFunction<_PS, _PS>(
    'linphone_core_get_capture_device',
  );
  late final _getPlayback = _lib.lookupFunction<_PS, _PS>(
    'linphone_core_get_playback_device',
  );
  late final _getRinger = _lib.lookupFunction<_PS, _PS>(
    'linphone_core_get_ringer_device',
  );
  late final _setCapture = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('linphone_core_set_capture_device');
  late final _setPlayback = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('linphone_core_set_playback_device');
  late final _setRinger = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('linphone_core_set_ringer_device');

  @override
  List<SoundDevice> soundDevices() {
    if (_core == nullptr) return const [];
    _reloadSound(_core);
    _devicesListed = true;
    final list = _soundDevices(_core); // array di char* terminato da NULL
    final out = <SoundDevice>[];
    for (var i = 0; list != nullptr && list[i] != nullptr; i++) {
      final id = list[i];
      out.add(
        SoundDevice(
          _deviceName(id),
          capture: _canCapture(_core, id) != 0,
          playback: _canPlayback(_core, id) != 0,
        ),
      );
    }
    return out;
  }

  @override
  (String, String, String) audioDevices() => _core == nullptr
      ? ('', '', '')
      : (
          _deviceName(_getCapture(_core)),
          _deviceName(_getPlayback(_core)),
          _deviceName(_getRinger(_core)),
        );

  /// Nomi letti in ANSI anziché UTF-8 (sotto): si ripassano al core con gli
  /// stessi byte, o il dispositivo non verrebbe trovato.
  final _ansiNames = <String>{};
  var _devicesListed = false;

  /// Nome di scheda audio o webcam. Su alcuni PC Windows arriva nella code
  /// page ANSI (es. "Microfono (Realtek® Audio)" con ® = 0xAE): `toDartString`
  /// lancia FormatException e la scheda Audio delle Preferenze restava grigia.
  /// Latin-1 conserva i byte, così il nome torna identico al core.
  String _deviceName(Pointer<Utf8> p) {
    if (p == nullptr) return '';
    final bytes = p.cast<Uint8>().asTypedList(p.length);
    try {
      return utf8.decode(bytes);
    } on FormatException {
      final name = latin1.decode(bytes);
      _ansiNames.add(name);
      return name;
    }
  }

  Pointer<Utf8> _deviceNative(String name, Allocator a) {
    if (!_ansiNames.contains(name)) return name.toNativeUtf8(allocator: a);
    final bytes = latin1.encode(name);
    final p = a<Uint8>(bytes.length + 1);
    p.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    return p.cast();
  }

  @override
  Future<void> setAudioDevices({
    String? capture,
    String? playback,
    String? ringer,
  }) async {
    if (_core == nullptr) return;
    // All'avvio (dispositivi salvati) i nomi ANSI non sono ancora noti.
    if (!_devicesListed) soundDevices();
    using((a) {
      if (capture != null && capture.isNotEmpty) {
        _setCapture(_core, _deviceNative(capture, a));
      }
      if (playback != null && playback.isNotEmpty) {
        _setPlayback(_core, _deviceNative(playback, a));
      }
      if (ringer != null && ringer.isNotEmpty) {
        _setRinger(_core, _deviceNative(ringer, a));
      }
    });
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
        'sip:$number@${_hostOfCall(call)}'.toNativeUtf8(allocator: a),
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
  // --- account avanzato: route, scadenza, privacy, realm, NAT.
  late final _bctbx = DynamicLibrary.open(
    Platform.isWindows
        ? '${File(Platform.resolvedExecutable).parent.path}'
              '${Platform.pathSeparator}bctoolbox.dll'
        : 'libbctoolbox.so',
  );
  late final _listNew = _bctbx.lookupFunction<_PP, _PP>('bctbx_list_new');
  late final _listFree = _bctbx.lookupFunction<_PP, _PP>('bctbx_list_free');
  late final _setRoutes = _lib.lookupFunction<_IntPP, _IntPPDart>(
    'linphone_account_params_set_routes_addresses',
  );
  late final _setExpires = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('linphone_account_params_set_expires');
  late final _setPrivacy = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint32),
        void Function(Pointer<Void>, int)
      >('linphone_account_params_set_privacy');
  late final _setNatPolicy = _lib.lookupFunction<_VoidPP, _VoidPPDart>(
    'linphone_account_params_set_nat_policy',
  );
  late final _createNatPolicy = _lib.lookupFunction<_PP, _PP>(
    'linphone_core_create_nat_policy',
  );
  late final _natPolicyUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_nat_policy_unref',
  );
  late final _natSetServer = _lib.lookupFunction<_VoidPS, _VoidPSDart>(
    'linphone_nat_policy_set_stun_server',
  );
  late final _natSetUser = _lib.lookupFunction<_VoidPS, _VoidPSDart>(
    'linphone_nat_policy_set_stun_server_username',
  );
  late final _natStun = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_nat_policy_enable_stun');
  late final _natIce = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_nat_policy_enable_ice');
  late final _natTurn = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_nat_policy_enable_turn');

  // --- video.
  late final _setNativeVideoWindow = _lib.lookupFunction<_VoidPP, _VoidPPDart>(
    'linphone_core_set_native_video_window_id',
  );
  late final _setNativePreviewWindow = _lib
      .lookupFunction<_VoidPP, _VoidPPDart>(
        'linphone_core_set_native_preview_window_id',
      );
  late final _getVideoDevices = _lib
      .lookupFunction<
        Pointer<Pointer<Utf8>> Function(Pointer<Void>),
        Pointer<Pointer<Utf8>> Function(Pointer<Void>)
      >('linphone_core_get_video_devices');
  late final _setVideoDevice = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('linphone_core_set_video_device');
  late final _paramsEnableVideo = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_call_params_enable_video');
  late final _paramsVideoEnabled = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('linphone_call_params_video_enabled');
  late final _callCurrentParams = _lib.lookupFunction<_PP, _PP>(
    'linphone_call_get_current_params',
  );
  late final _callRemoteParams = _lib.lookupFunction<_PP, _PP>(
    'linphone_call_get_remote_params',
  );
  late final _acceptWithParams = _lib.lookupFunction<_IntPP, _IntPPDart>(
    'linphone_call_accept_with_params',
  );
  late final _callUpdate = _lib.lookupFunction<_IntPP, _IntPPDart>(
    'linphone_call_update',
  );
  late final _interpretUrl = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
      >('linphone_core_interpret_url');
  late final _videoPayloads = _lib.lookupFunction<_PP, _PP>(
    'linphone_core_get_video_payload_types',
  );
  late final _ptMime = _lib.lookupFunction<_PS, _PS>(
    'linphone_payload_type_get_mime_type',
  );
  late final _ptUsable = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('linphone_payload_type_is_usable');
  late final _ptEnabled = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('linphone_payload_type_enabled');
  late final _ptUnref = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_payload_type_unref',
  );

  late final _enableVideoPreview = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_core_enable_video_preview');
  late final _setVideoDefinition = _lib.lookupFunction<_VoidPS, _VoidPSDart>(
    'linphone_core_set_preferred_video_definition_by_name',
  );
  late final _setFramerate = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Float),
        void Function(Pointer<Void>, double)
      >('linphone_core_set_preferred_framerate');
  late final _setUploadBandwidth = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('linphone_core_set_upload_bandwidth');

  // --- registrazione, qualità, conferenza.
  late final _paramsSetRecordFile = _lib.lookupFunction<_VoidPS, _VoidPSDart>(
    'linphone_call_params_set_record_file',
  );
  late final _startRecording = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_call_start_recording',
  );
  late final _stopRecording = _lib.lookupFunction<_VoidP, _VoidPDart>(
    'linphone_call_stop_recording',
  );
  late final _currentQuality = _lib
      .lookupFunction<
        Float Function(Pointer<Void>),
        double Function(Pointer<Void>)
      >('linphone_call_get_current_quality');
  late final _callConference = _lib.lookupFunction<_PP, _PP>(
    'linphone_call_get_conference',
  );
  late final _addAllToConference = _lib.lookupFunction<_IntP, _IntPDart>(
    'linphone_core_add_all_to_conference',
  );

  // --- opzioni globali delle chiamate.
  late final _setMediaEncryption = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('linphone_core_set_media_encryption');
  late final _setEncryptionMandatory = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_core_set_media_encryption_mandatory');
  late final _enableKeepAlive = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_core_enable_keep_alive');
  late final _useInfoDtmf = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_core_set_use_info_for_dtmf');
  late final _useRfc2833Dtmf = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('linphone_core_set_use_rfc2833_for_dtmf');

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
    String? codecDir,
  }) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    // OpenH264 (verificato dal chiamante): il plugin libmsopenh264 importa
    // `openh264.dll`, cercata anche nella cartella impostata qui.
    if (codecDir != null && Platform.isWindows) {
      using((a) {
        DynamicLibrary.open('kernel32.dll').lookupFunction<
          Int32 Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)
        >('SetDllDirectoryW')(codecDir.toNativeUtf16(allocator: a));
      });
    }
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
    // Video spento finché il controller non applica Preferenze > Video.
    _enableVideoCapture(_core, 0);
    _enableVideoDisplay(_core, 0);
    _setNativeVideoWindow(_core, nullptr);
    _setNativePreviewWindow(_core, nullptr);

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
  Future<void> setAccounts(List<SipAccount> accounts) async {
    _dropSubscriptions();
    _clearAccounts(_core);
    _clearAuthInfo(_core);
    for (final acc in _accounts.values) {
      _accountUnref(acc);
    }
    _accounts.clear();
    _accountHosts.clear();
    for (final account in accounts) {
      final acc = _addSipAccount(account);
      _accounts[account.id] = acc;
      _accountHosts[account.id] = account.host;
      if (account == accounts.first) _setDefault(_core, acc);
    }
  }

  Pointer<Void> _addSipAccount(SipAccount account) => using((a) {
    final host = account.host;
    Pointer<Utf8> opt(String s) =>
        s.isEmpty ? nullptr : s.toNativeUtf8(allocator: a);
    final auth = _createAuthInfo(
      _factory,
      account.username.toNativeUtf8(allocator: a),
      opt(account.authUser),
      account.password.toNativeUtf8(allocator: a),
      nullptr,
      opt(account.realm),
      host.toNativeUtf8(allocator: a),
    );
    _addAuthInfo(_core, auth);
    _authInfoUnref(auth);
    // Credenziali TURN: auth info con l'utente della NAT policy.
    if (account.turn && account.turnUser.isNotEmpty) {
      final t = _createAuthInfo(
        _factory,
        account.turnUser.toNativeUtf8(allocator: a),
        nullptr,
        account.turnPassword.toNativeUtf8(allocator: a),
        nullptr,
        nullptr,
        nullptr,
      );
      _addAuthInfo(_core, t);
      _authInfoUnref(t);
    }

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
    // Destinazione del REGISTER: in liblinphone va sempre al server
    // dell'account (le route valgono solo per le chiamate). Quindi: registrar
    // esplicito, altrimenti il proxy in uscita, altrimenti il dominio.
    // L'identità resta utente@dominio (serve ai PBX multi-tenant).
    final server = _createAddress(
      _factory,
      'sip:${account.registrar.isNotEmpty ? account.registrar : (account.proxy.isNotEmpty ? account.proxy : account.domain)}'
          .toNativeUtf8(allocator: a),
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
    _enableRegister(params, account.registerEnabled ? 1 : 0);
    if (account.expires > 0) _setExpires(params, account.expires);
    // LinphonePrivacyId = 0x8 (types.h).
    if (account.hideCallerId) _setPrivacy(params, 0x8);
    // Proxy in uscita come route: REGISTER e chiamate passano di lì, la
    // Request-URI resta il registrar/dominio.
    if (account.proxy.isNotEmpty) {
      final t = account.transport == SipTransport.udp
          ? ''
          : ';transport=${account.transport.name}';
      final route = _createAddress(
        _factory,
        'sip:${account.proxy}$t;lr'.toNativeUtf8(allocator: a),
      );
      if (route == nullptr) {
        _paramsUnref(params);
        _addressUnref(server);
        _addressUnref(identity);
        throw ArgumentError('Proxy in uscita non valido');
      }
      final list = _listNew(route);
      _setRoutes(params, list);
      _listFree(list);
      _addressUnref(route);
    }
    // NAT: STUN/TURN e ICE per account (contro l'audio a senso unico).
    if (account.stunServer.isNotEmpty || account.ice || account.turn) {
      final nat = _createNatPolicy(_core);
      if (account.stunServer.isNotEmpty) {
        _natSetServer(nat, account.stunServer.toNativeUtf8(allocator: a));
        _natStun(nat, 1);
      }
      if (account.turn) {
        _natTurn(nat, 1);
        if (account.turnUser.isNotEmpty) {
          _natSetUser(nat, account.turnUser.toNativeUtf8(allocator: a));
        }
      }
      if (account.ice) _natIce(nat, 1);
      _setNatPolicy(params, nat);
      _natPolicyUnref(nat);
    }
    final acc = _createAccount(_core, params);
    // Casella vocale: il PBX invia NOTIFY message-summary sull'account.
    _mwiCb ??= NativeCallable<_MwiCb>.isolateLocal(_onMwi);
    final accCbs = _createAccountCbs(_factory);
    _setMwiCb(accCbs, _mwiCb!.nativeFunction);
    _accountAddCbs(acc, accCbs);
    _accountCbsUnref(accCbs);
    _addAccount(_core, acc);
    _paramsUnref(params);
    _addressUnref(server);
    _addressUnref(identity);
    return acc; // ref di createAccount: rilasciata alla prossima setAccounts
  });

  @override
  Future<void> setCallOptions(CallOptions o) async {
    _setMediaEncryption(_core, o.encryption.index);
    _setEncryptionMandatory(_core, o.encryptionMandatory ? 1 : 0);
    _enableKeepAlive(_core, o.keepAlive ? 1 : 0);
    _useRfc2833Dtmf(_core, o.dtmfInfo ? 0 : 1);
    _useInfoDtmf(_core, o.dtmfInfo ? 1 : 0);
  }

  @override
  Future<int?> dial(
    String number, {
    String? accountId,
    bool video = false,
  }) async {
    final acc = accountId == null ? null : _accounts[accountId];
    final call = acc == null
        ? using((a) {
            // Account predefinito: il core completa il numero con il suo dominio.
            final to = _interpretUrl(_core, number.toNativeUtf8(allocator: a));
            if (to == nullptr) return nullptr;
            final params = _createCallParams(_core, nullptr);
            _paramsEnableVideo(params, video ? 1 : 0);
            _setRecordFile(params, number, a);
            final c = _inviteWithParams(_core, to, params);
            _callParamsUnref(params);
            _addressUnref(to);
            return c;
          })
        : using((a) {
            // Account esplicito (multi-PBX): indirizzo sul suo host e parametri
            // di chiamata legati a quell'account.
            final uri = number.contains('@')
                ? 'sip:$number'
                : 'sip:$number@${_accountHosts[accountId]}';
            final to = _createAddress(_factory, uri.toNativeUtf8(allocator: a));
            if (to == nullptr) return nullptr;
            final params = _createCallParams(_core, nullptr);
            _callParamsSetAccount(params, acc);
            _paramsEnableVideo(params, video ? 1 : 0);
            _setRecordFile(params, number, a);
            final c = _inviteWithParams(_core, to, params);
            _callParamsUnref(params);
            _addressUnref(to);
            return c;
          });
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
  Future<void> answer(int id, {bool video = false}) async {
    final call = _ptr(id);
    if (call == nullptr) return;
    // Video solo se scelto ("Rispondi in video"), anche se il chiamante lo offre.
    final params = _createCallParams(_core, call);
    if (params == nullptr) {
      _accept(call);
      return;
    }
    _paramsEnableVideo(params, video ? 1 : 0);
    using((a) {
      final remote = _remoteAddress(call);
      _setRecordFile(
        params,
        remote == nullptr ? 'sconosciuto' : _str(_addressUsername(remote)),
        a,
      );
    });
    _acceptWithParams(call, params);
    _callParamsUnref(params);
  }

  String _recordingDir = '';

  @override
  void setRecordingDir(String dir) => _recordingDir = dir;

  /// File della registrazione locale (scritto solo se la si avvia): mkv per
  /// audio e video, `AAAAMMGG-hhmmss-numero.mkv`.
  void _setRecordFile(Pointer<Void> params, String number, Allocator a) {
    if (_recordingDir.isEmpty) return;
    Directory(_recordingDir).createSync(recursive: true);
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final safe = number.replaceAll(RegExp(r'[^0-9A-Za-z+_-]'), '_');
    final name =
        '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}-$safe.mkv';
    _paramsSetRecordFile(
      params,
      '$_recordingDir${Platform.pathSeparator}$name'.toNativeUtf8(allocator: a),
    );
  }

  @override
  Future<void> startRecording(int id) async {
    if (_ptr(id) != nullptr) _startRecording(_ptr(id));
  }

  @override
  Future<void> stopRecording(int id) async {
    if (_ptr(id) != nullptr) _stopRecording(_ptr(id));
  }

  @override
  double callQuality(int id) =>
      _ptr(id) == nullptr ? -1 : _currentQuality(_ptr(id));

  @override
  Future<void> conferenceAll() async => _addAllToConference(_core);

  @override
  Future<void> setCallVideo(int id, bool on) async {
    final call = _ptr(id);
    if (call == nullptr) return;
    final params = _createCallParams(_core, call);
    if (params == nullptr) return;
    _paramsEnableVideo(params, on ? 1 : 0);
    _callUpdate(call, params);
    _callParamsUnref(params);
  }

  @override
  Future<void> setVideo(VideoOptions o) async {
    _enableVideoCapture(_core, o.enabled ? 1 : 0);
    _enableVideoDisplay(_core, o.enabled ? 1 : 0);
    // Default del core: 640x480 a ~400 kbit/s (immagine sgranata). Risoluzione,
    // 25 fps e banda in uscita secondo la qualità scelta.
    final (name, kbps) = switch (o.quality) {
      VideoQuality.low => ('vga', 800),
      VideoQuality.medium => ('720p', 1800),
      VideoQuality.high => ('1080p', 3500),
    };
    using((a) => _setVideoDefinition(_core, name.toNativeUtf8(allocator: a)));
    _setFramerate(_core, 25);
    _setUploadBandwidth(_core, kbps);
    if (o.camera.isNotEmpty) {
      using((a) => _setVideoDevice(_core, _deviceNative(o.camera, a)));
    }
  }

  @override
  Future<void> setCameraPreview(bool on) async =>
      _enableVideoPreview(_core, on ? 1 : 0);

  @override
  List<String> videoDevices() {
    final list = _getVideoDevices(_core);
    if (list == nullptr) return const [];
    return [for (var i = 0; list[i] != nullptr; i++) _deviceName(list[i])];
  }

  @override
  List<String> videoCodecs() {
    final list = _videoPayloads(_core);
    final out = <String>[];
    // bctbx_list_t: { next, prev, data }.
    var node = list.cast<IntPtr>();
    while (node != nullptr) {
      final pt = Pointer<Void>.fromAddress(node[2]);
      if (_ptUsable(pt) != 0 && _ptEnabled(pt) != 0) {
        out.add(_ptMime(pt).toDartString());
      }
      _ptUnref(pt);
      node = Pointer<IntPtr>.fromAddress(node[0]);
    }
    if (list != nullptr) _listFree(list);
    return out;
  }

  @override
  Future<void> setVideoWindows({
    required int remote,
    required int preview,
  }) async {
    _setNativeVideoWindow(_core, _oglContext(remote));
    _setNativePreviewWindow(_core, _oglContext(preview));
  }

  /// Il filtro MSOGL (Windows) vuole un `MSOglContextInfo*`, non l'HWND:
  /// `{ void* window; unsigned width; unsigned height; getProcAddress }`
  /// (mediastreamer2/msogl.h). La memoria resta valida finché il core la può
  /// usare: si libera solo in [stop]. 0 = nessuna finestra.
  final _oglContexts = <int, Pointer<_OglContextInfo>>{};

  Pointer<Void> _oglContext(int hwnd) {
    if (hwnd == 0) return nullptr;
    return _oglContexts.putIfAbsent(hwnd, () {
      final info = calloc<_OglContextInfo>();
      info.ref
        ..window = Pointer.fromAddress(hwnd)
        // Dimensioni di ripiego: MSOGL le legge dalla superficie EGL.
        ..width = 1280
        ..height = 720
        ..getProcAddress = nullptr;
      return info;
    }).cast();
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

  /// SUBSCRIBE a gruppi: decine insieme (più account) possono far scattare
  /// i limiti del PBX e bloccano l'interfaccia di eventi.
  static const _subBatch = 10;
  static const _subGap = Duration(milliseconds: 200);
  final _subQueue = <String>[];
  Timer? _subTimer;

  @override
  Future<void> watchDialogs(Set<String> targets) async {
    for (final n in _subs.keys.where((n) => !targets.contains(n)).toList()) {
      _dropSubscription(n);
    }
    _subQueue.removeWhere((n) => !targets.contains(n));
    for (final n in targets) {
      if (!_subs.containsKey(n) && !_subQueue.contains(n)) _subQueue.add(n);
    }
    if (_subTimer == null && _subQueue.isNotEmpty) {
      _subscribeBatch();
      if (_subQueue.isNotEmpty) {
        _subTimer = Timer.periodic(_subGap, (_) => _subscribeBatch());
      }
    }
  }

  void _subscribeBatch() {
    for (var i = 0; i < _subBatch && _subQueue.isNotEmpty; i++) {
      _subscribe(_subQueue.removeAt(0));
    }
    if (_subQueue.isEmpty) {
      _subTimer?.cancel();
      _subTimer = null;
    }
  }

  void _subscribe(String n) {
    final ev = using((a) {
      final addr = _createAddress(
        _factory,
        'sip:$n'.toNativeUtf8(allocator: a),
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
      return;
    }
    _subs[n] = ev;
    _subTrackers[n] = DialogInfoTracker();
    _eventSendSubscribe(ev, nullptr);
    _dialogs.add(BlfEvent(n, BlfStatus.unknown));
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
    _subQueue.clear();
    _subTimer?.cancel();
    _subTimer = null;
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
      for (final acc in _accounts.values) {
        _accountUnref(acc);
      }
      _accounts.clear();
      _stop(_core);
      _coreUnref(_core);
      _core = nullptr;
    }
    // Contesti video: liberi solo a core distrutto.
    for (final info in _oglContexts.values) {
      calloc.free(info);
    }
    _oglContexts.clear();
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
    final id = _accounts.entries
        .where((e) => e.value == account)
        .map((e) => e.key)
        .firstOrNull;
    if (id == null) return; // account già rimosso (es. un-REGISTER del vecchio)
    _registrations.add(
      RegistrationEvent(map[state] ?? RegistrationStatus.none, _str(msg), id),
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
        video: _videoOf(_callCurrentParams(call)),
        remoteVideo: _videoOf(_callRemoteParams(call)),
        accountId: _accountIdOf(call),
        inConference: _callConference(call) != nullptr,
      ),
    );
  }

  String _accountIdOf(Pointer<Void> call) {
    final params = _callGetParams(call);
    final acc = params == nullptr ? nullptr : _callParamsGetAccount(params);
    for (final e in _accounts.entries) {
      if (e.value == acc) return e.key;
    }
    return '';
  }

  bool _videoOf(Pointer<Void> params) =>
      params != nullptr && _paramsVideoEnabled(params) != 0;

  static String _str(Pointer<Utf8> p) => p == nullptr ? '' : p.toDartString();
}
