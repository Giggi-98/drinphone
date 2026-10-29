// Finestra Win32 dove liblinphone disegna il video (contesto MSOGL).
// Popup *di proprietà* della finestra dell'app, senza attivazione né icona:
// il compositore di Windows la tiene sopra l'app e la nasconde con essa.
// Non è una figlia: da sorella della superficie Flutter veniva ridisegnata
// sopra a ogni frame (tremolio). Il widget che la ospita la posiziona sopra il
// suo riquadro. Limite: sta sopra a menu e dialoghi Flutter aperti lì.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

class VideoSurface {
  VideoSurface._(this.handle, this._owner);

  /// HWND come intero (0 = nessuna).
  final int handle;
  final int _owner;
  (int, int, int, int)? _last;

  // Classe della finestra del runner Flutter (windows/runner/win32_window.cpp).
  static const _ownerClass = 'FLUTTER_RUNNER_WIN32_WINDOW';
  static const _wsPopup = 0x80000000;
  static const _wsClipSiblings = 0x04000000;
  static const _ssBlackRect = 0x4;
  static const _wsExNoActivate = 0x08000000;
  static const _wsExToolWindow = 0x00000080;
  static const _swpNoActivate = 0x10;
  static const _swpShow = 0x40;
  static const _swpNoOwnerZOrder = 0x200;
  static const _swHide = 0;

  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _findWindow = _user32
      .lookupFunction<
        IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)
      >('FindWindowW');
  static final _create = _user32
      .lookupFunction<
        IntPtr Function(
          Uint32,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Uint32,
          Int32,
          Int32,
          Int32,
          Int32,
          IntPtr,
          IntPtr,
          IntPtr,
          Pointer<Void>,
        ),
        int Function(
          int,
          Pointer<Utf16>,
          Pointer<Utf16>,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          Pointer<Void>,
        )
      >('CreateWindowExW');
  static final _setPos = _user32
      .lookupFunction<
        Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
        int Function(int, int, int, int, int, int, int)
      >('SetWindowPos');
  static final _clientToScreen = _user32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<_Point>),
        int Function(int, Pointer<_Point>)
      >('ClientToScreen');
  static final _show = _user32
      .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
        'ShowWindow',
      );
  static final _destroy = _user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'DestroyWindow',
      );

  /// Null fuori da Windows o se la finestra dell'app non si trova.
  static VideoSurface? create() {
    if (!Platform.isWindows) return null;
    return using((a) {
      final owner = _findWindow(
        _ownerClass.toNativeUtf16(allocator: a),
        nullptr,
      );
      if (owner == 0) return null;
      final hwnd = _create(
        _wsExNoActivate | _wsExToolWindow,
        'STATIC'.toNativeUtf16(allocator: a),
        ''.toNativeUtf16(allocator: a),
        _wsPopup | _wsClipSiblings | _ssBlackRect,
        0,
        0,
        1,
        1,
        owner,
        0,
        0,
        nullptr,
      );
      return hwnd == 0 ? null : VideoSurface._(hwnd, owner);
    });
  }

  /// Posizione in pixel fisici relativa all'area client della finestra
  /// dell'app; convertita in coordinate di schermo (segue gli spostamenti).
  void place(int x, int y, int w, int h) {
    final (sx, sy) = using((a) {
      final p = a<_Point>()
        ..ref.x = x
        ..ref.y = y;
      _clientToScreen(_owner, p);
      return (p.ref.x, p.ref.y);
    });
    final r = (sx, sy, w, h);
    if (r == _last) return;
    _last = r;
    // HWND_TOP = 0: sopra la finestra proprietaria.
    _setPos(
      handle,
      0,
      sx,
      sy,
      w,
      h,
      _swpNoActivate | _swpShow | _swpNoOwnerZOrder,
    );
  }

  void hide() {
    _last = null;
    _show(handle, _swHide);
  }

  void destroy() => _destroy(handle);
}
