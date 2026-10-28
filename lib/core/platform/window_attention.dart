// Chiamata in arrivo con l'app in secondo piano (Windows): ripristina la
// finestra se ridotta a icona, prova a portarla davanti e fa lampeggiare il
// pulsante sulla barra delle applicazioni finché l'utente non la attiva.
// Windows può negare il primo piano a un processo non attivo (foreground
// lock): il lampeggio resta comunque.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _FlashInfo extends Struct {
  @Uint32()
  external int cbSize;
  external Pointer<Void> hwnd;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int uCount;
  @Uint32()
  external int dwTimeout;
}

class WindowAttention {
  WindowAttention._();
  static final instance = WindowAttention._();

  // Classe della finestra del runner Flutter (windows/runner/win32_window.cpp).
  static const _className = 'FLUTTER_RUNNER_WIN32_WINDOW';
  static const _swRestore = 9;
  static const _flashwAll = 0x3;
  static const _flashwTimerNoFg = 0xC;

  late final _user32 = DynamicLibrary.open('user32.dll');
  late final _findWindow = _user32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf16>),
        Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf16>)
      >('FindWindowW');
  late final _isIconic = _user32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('IsIconic');
  late final _showWindow = _user32
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('ShowWindow');
  late final _setForeground = _user32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('SetForegroundWindow');
  late final _flash = _user32
      .lookupFunction<
        Int32 Function(Pointer<_FlashInfo>),
        int Function(Pointer<_FlashInfo>)
      >('FlashWindowEx');

  void request() {
    if (!Platform.isWindows) return;
    using((a) {
      final hwnd = _findWindow(_className.toNativeUtf16(allocator: a), nullptr);
      if (hwnd == nullptr) return;
      if (_isIconic(hwnd) != 0) _showWindow(hwnd, _swRestore);
      _setForeground(hwnd);
      final info = a<_FlashInfo>();
      info.ref
        ..cbSize = sizeOf<_FlashInfo>()
        ..hwnd = hwnd
        ..dwFlags = _flashwAll | _flashwTimerNoFg
        ..uCount = 0
        ..dwTimeout = 0;
      _flash(info);
    });
  }
}
