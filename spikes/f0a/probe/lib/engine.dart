// Two candidate bridges evaluated by F0-A:
//  - Android: Platform Channels -> Kotlin -> linphone-sdk-android AAR (Java API
//    needs an Android Context, so FFI alone is not enough there).
//  - Linux/Windows: dart:ffi -> liblinphone C API, iterate() driven from a Dart
//    timer so every callback fires on the isolate's own thread.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

abstract class ProbeEngine {
  factory ProbeEngine.forPlatform() =>
      Platform.isAndroid ? _ChannelEngine() : _FfiEngine();

  Stream<String> get events;
  Future<String> init();
  Future<void> register(String user, String domain);
  Future<void> destroy();
}

// ---------------------------------------------------------------- Android

class _ChannelEngine implements ProbeEngine {
  static const _method = MethodChannel('drinphone/f0a');
  static const _events = EventChannel('drinphone/f0a/events');

  @override
  Stream<String> get events =>
      _events.receiveBroadcastStream().map((e) => e as String);

  @override
  Future<String> init() async => await _method.invokeMethod<String>('init') ?? '';

  @override
  Future<void> register(String user, String domain) =>
      _method.invokeMethod('register', {'user': user, 'domain': domain});

  @override
  Future<void> destroy() => _method.invokeMethod('destroy');
}

// ---------------------------------------------------------------- Linux FFI

typedef _GlobalStateCb = Void Function(Pointer<Void>, Int32, Pointer<Utf8>);
typedef _RegStateCb = Void Function(
    Pointer<Void>, Pointer<Void>, Int32, Pointer<Utf8>);

class _FfiEngine implements ProbeEngine {
  final _controller = StreamController<String>.broadcast();
  late final DynamicLibrary _lib;
  Pointer<Void> _core = nullptr;
  Timer? _iterate;
  NativeCallable<_GlobalStateCb>? _globalCb;
  NativeCallable<_RegStateCb>? _regCb;

  @override
  Stream<String> get events => _controller.stream;

  late final _factoryGet = _lib.lookupFunction<Pointer<Void> Function(),
      Pointer<Void> Function()>('linphone_factory_get');
  late final _setTopResources = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Utf8>),
      void Function(Pointer<Void>,
          Pointer<Utf8>)>('linphone_factory_set_top_resources_dir');
  late final _setMsPlugins = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Utf8>),
      void Function(Pointer<Void>,
          Pointer<Utf8>)>('linphone_factory_set_msplugins_dir');
  late final _createCore = _lib.lookupFunction<
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>,
          Pointer<Void>)>('linphone_factory_create_core_3');
  late final _createCbs = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('linphone_factory_create_core_cbs');
  late final _setGlobalCb = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_GlobalStateCb>>),
      void Function(Pointer<Void>,
          Pointer<NativeFunction<_GlobalStateCb>>)>(
      'linphone_core_cbs_set_global_state_changed');
  late final _setRegCb = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_RegStateCb>>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_RegStateCb>>)>(
      'linphone_core_cbs_set_account_registration_state_changed');
  late final _addCbs = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<Void>)>('linphone_core_add_callbacks');
  late final _version = _lib.lookupFunction<Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('linphone_core_get_version');
  late final _start = _lib.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('linphone_core_start');
  late final _iterateFn = _lib.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('linphone_core_iterate');
  late final _stop = _lib.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('linphone_core_stop');
  late final _unref = _lib.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('linphone_core_unref');
  late final _createAddress = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Utf8>)>('linphone_factory_create_address');
  late final _createParams = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(
          Pointer<Void>)>('linphone_core_create_account_params');
  late final _setIdentity = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>,
          Pointer<Void>)>('linphone_account_params_set_identity_address');
  late final _setServer = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>,
          Pointer<Void>)>('linphone_account_params_set_server_address');
  late final _enableRegister = _lib.lookupFunction<
      Void Function(Pointer<Void>, Uint8),
      void Function(Pointer<Void>, int)>('linphone_account_params_enable_register');
  late final _createAccount = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>)>('linphone_core_create_account');
  late final _addAccount = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)>('linphone_core_add_account');
  late final _setDefault = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>),
      void Function(
          Pointer<Void>, Pointer<Void>)>('linphone_core_set_default_account');

  @override
  Future<String> init() async {
    _lib = DynamicLibrary.open(Platform.environment['F0A_LIBLINPHONE'] ??
        (Platform.isWindows ? 'liblinphone.dll' : 'liblinphone.so'));
    final factory = _factoryGet();
    // Belr grammars & co. live under <top>/belr/grammars; the compiled-in
    // default points at the SDK build prefix, not at our relocated copy.
    final resources = Platform.environment['F0A_RESOURCES'];
    if (resources != null) {
      using((arena) =>
          _setTopResources(factory, resources.toNativeUtf8(allocator: arena)));
    }
    // Windows SDK ships WASAPI (the only sound card backend) as a plugin.
    final msPlugins = Platform.environment['F0A_MSPLUGINS'];
    if (msPlugins != null) {
      using((arena) =>
          _setMsPlugins(factory, msPlugins.toNativeUtf8(allocator: arena)));
    }
    _core = _createCore(factory, nullptr, nullptr, nullptr);
    if (_core == nullptr) throw StateError('create_core_3 returned NULL');

    _globalCb = NativeCallable<_GlobalStateCb>.isolateLocal(
        (Pointer<Void> _, int state, Pointer<Utf8> msg) =>
            _controller.add('global state=$state msg=${_str(msg)}'));
    _regCb = NativeCallable<_RegStateCb>.isolateLocal(
        (Pointer<Void> _, Pointer<Void> __, int state, Pointer<Utf8> msg) =>
            _controller.add('registration state=$state msg=${_str(msg)}'));
    final cbs = _createCbs(factory);
    _setGlobalCb(cbs, _globalCb!.nativeFunction);
    _setRegCb(cbs, _regCb!.nativeFunction);
    _addCbs(_core, cbs);

    final rc = _start(_core);
    if (rc != 0) throw StateError('linphone_core_start rc=$rc');
    _iterate = Timer.periodic(
        const Duration(milliseconds: 20), (_) => _iterateFn(_core));
    return _version().toDartString();
  }

  @override
  Future<void> register(String user, String domain) async {
    final factory = _factoryGet();
    using((arena) {
      final identity = _createAddress(
          factory, 'sip:$user@$domain'.toNativeUtf8(allocator: arena));
      final server = _createAddress(
          factory, 'sip:$domain;transport=tcp'.toNativeUtf8(allocator: arena));
      final params = _createParams(_core);
      _setIdentity(params, identity);
      _setServer(params, server);
      _enableRegister(params, 1);
      final account = _createAccount(_core, params);
      _addAccount(_core, account);
      _setDefault(_core, account);
    });
  }

  @override
  Future<void> destroy() async {
    _iterate?.cancel();
    _stop(_core);
    _unref(_core);
    _core = nullptr;
    _globalCb?.close();
    _regCb?.close();
    await _controller.close();
  }

  static String _str(Pointer<Utf8> p) => p == nullptr ? '' : p.toDartString();
}
