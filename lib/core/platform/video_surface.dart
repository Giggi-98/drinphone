// Finestra Win32 figlia della finestra dell'app, dove liblinphone disegna il
// video (finestra nativa per `linphone_core_set_native_video_window_id`).
// Il widget Flutter che la ospita la tiene posizionata sopra il suo riquadro.
// Limite: essendo una finestra nativa sta sopra a tutto il contenuto Flutter
// (anche menu e dialoghi aperti sopra il pannello di chiamata).
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class VideoSurface {
  VideoSurface._(this.handle);

  /// HWND come intero (0 = nessuna).
  final int handle;

  // Classe della finestra del runner Flutter (windows/runner/win32_window.cpp).
  static const _parentClass = 'FLUTTER_RUNNER_WIN32_WINDOW';
  static const _wsChild = 0x40000000;
  static const _wsClipSiblings = 0x04000000;
  static const _ssBlackRect = 0x4;
  static const _swpNoActivate = 0x10;
  static const _swpShow = 0x40;
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
      final parent = _findWindow(
        _parentClass.toNativeUtf16(allocator: a),
        nullptr,
      );
      if (parent == 0) return null;
      final hwnd = _create(
        0,
        'STATIC'.toNativeUtf16(allocator: a),
        ''.toNativeUtf16(allocator: a),
        _wsChild | _wsClipSiblings | _ssBlackRect,
        0,
        0,
        1,
        1,
        parent,
        0,
        0,
        nullptr,
      );
      return hwnd == 0 ? null : VideoSurface._(hwnd);
    });
  }

  /// Posizione in pixel fisici, relativa all'area client della finestra.
  void place(int x, int y, int w, int h) =>
      // HWND_TOP = 0: sopra la vista Flutter (finestra sorella).
      _setPos(handle, 0, x, y, w, h, _swpNoActivate | _swpShow);

  void hide() => _show(handle, _swHide);

  void destroy() => _destroy(handle);
}
