// Chiamata in arrivo con l'app in secondo piano (Windows): ripristina la
// finestra se ridotta a icona, prova a portarla davanti e fa lampeggiare il
// pulsante sulla barra delle applicazioni finché l'utente non la attiva.
// Windows può negare il primo piano a un processo non attivo (foreground
// lock): il lampeggio resta comunque.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

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

  late final _isVisible = _user32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('IsWindowVisible');
  late final _getForeground = _user32
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetForegroundWindow',
      );
  late final _getWindowRect = _user32
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<_Rect>),
        int Function(Pointer<Void>, Pointer<_Rect>)
      >('GetWindowRect');
  late final _setWindowPos = _user32
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Void>,
          Int32,
          Int32,
          Int32,
          Int32,
          Uint32,
        ),
        int Function(Pointer<Void>, Pointer<Void>, int, int, int, int, int)
      >('SetWindowPos');
  late final _getSystemMetrics = _user32
      .lookupFunction<Int32 Function(Int32), int Function(int)>(
        'GetSystemMetrics',
      );

  ({int left, int top, int width, int height})? _savedBounds;
  bool isMiniHud = false;

  /// Attiva/disattiva la modalità compatta Always-on-top su Windows salvando e
  /// ripristinando posizione/dimensioni originali della finestra.
  void setMiniHud(bool on) {
    isMiniHud = on;
    if (!Platform.isWindows) return;
    final hwnd = _hwnd();
    if (hwnd == nullptr) return;
    using((a) {
      const swpShowWindow = 0x0040;
      const swpNoActivate = 0x0010;
      final hwndTopMost = Pointer<Void>.fromAddress(-1);
      final hwndNoTopMost = Pointer<Void>.fromAddress(-2);
      if (on) {
        final rect = a<_Rect>();
        if (_getWindowRect(hwnd, rect) != 0) {
          final w = rect.ref.right - rect.ref.left;
          final h = rect.ref.bottom - rect.ref.top;
          if (w > 460 && h > 280) {
            _savedBounds = (
              left: rect.ref.left,
              top: rect.ref.top,
              width: w,
              height: h,
            );
          }
        }
        if (_isIconic(hwnd) != 0) _showWindow(hwnd, _swRestore);
        final screenW = _getSystemMetrics(0); // SM_CXSCREEN
        const hudW = 420;
        const hudH = 264;
        final x = (screenW > hudW + 24) ? screenW - hudW - 24 : 24;
        const y = 24;
        _setWindowPos(
          hwnd,
          hwndTopMost,
          x,
          y,
          hudW,
          hudH,
          swpShowWindow | swpNoActivate,
        );
      } else {
        final b = _savedBounds;
        _savedBounds = null;
        if (b != null) {
          _setWindowPos(
            hwnd,
            hwndNoTopMost,
            b.left,
            b.top,
            b.width,
            b.height,
            swpShowWindow,
          );
        } else {
          // Fallback SWP_NOMOVE | SWP_NOSIZE
          _setWindowPos(hwnd, hwndNoTopMost, 0, 0, 0, 0, 0x0001 | 0x0002);
        }
      }
    });
  }

  Pointer<Void> _hwnd() => using(
    (a) => _findWindow(_className.toNativeUtf16(allocator: a), nullptr),
  );

  /// Finestra nascosta nella barra di sistema (chiusura con "resta attivo").
  void hide() {
    if (!Platform.isWindows) return;
    final hwnd = _hwnd();
    if (hwnd != nullptr) _showWindow(hwnd, 0); // SW_HIDE
  }

  /// Di nuovo visibile e in primo piano (icona o notifica nella barra).
  void show() {
    if (!Platform.isWindows) return;
    final hwnd = _hwnd();
    if (hwnd == nullptr) return;
    _showWindow(hwnd, _isIconic(hwnd) != 0 ? _swRestore : 5); // SW_SHOW
    _setForeground(hwnd);
  }

  /// L'utente sta guardando l'app: visibile e in primo piano.
  bool get inFront {
    if (!Platform.isWindows) return true;
    final hwnd = _hwnd();
    return hwnd != nullptr &&
        _isVisible(hwnd) != 0 &&
        _isIconic(hwnd) == 0 &&
        _getForeground() == hwnd;
  }

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
