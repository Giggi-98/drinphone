// Finestre Win32 dove liblinphone disegna il video (contesto MSOGL).
//
// Popup *di proprietà* della finestra dell'app, senza attivazione né icona:
// il compositore di Windows le tiene sopra l'app e le nasconde con essa (da
// figlie, sorelle della superficie Flutter, venivano ridisegnate sopra: tremolio).
//
// Le finestre appartengono a un **thread dedicato** (isolate con il suo ciclo
// di messaggi), non al thread dell'interfaccia: il thread di disegno di MSOGL
// crea la superficie EGL sulla finestra e per farlo aspetta il thread che la
// possiede; se fosse quello dell'interfaccia, mentre questo aspetta liblinphone
// (es. impostando la finestra video) i due si bloccherebbero a vicenda (visto
// con la videochiamata in uscita). Dall'interfaccia partono solo messaggi non
// bloccanti: crea, sposta (SWP_ASYNCWINDOWPOS), distruggi.
//
// Le due finestre (video remoto, anteprima) si creano una volta all'avvio e
// restano consegnate al core per sempre: MSOGL ha sempre una finestra vera
// (anche nell'early media della chiamata in uscita) e non si cambia mai
// finestra a stream avviato. L'interfaccia le mostra, sposta e nasconde.
//
// Limite: le finestre stanno sopra a menu e dialoghi Flutter aperti lì.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

final class _Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

/// MSG di Win32 (x64).
final class _Msg extends Struct {
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int message;
  @IntPtr()
  external int wParam;
  @IntPtr()
  external int lParam;
  @Uint32()
  external int time;
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Uint32()
  external int private;
}

const _wmCreate = 0x8000 + 1; // WM_APP + 1: wParam = richiesta, lParam = owner
const _wmDestroy = 0x8000 + 2; // WM_APP + 2: wParam = hwnd

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _findWindow = _user32
    .lookupFunction<
      IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)
    >('FindWindowW');
final _create = _user32
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
final _setPos = _user32
    .lookupFunction<
      Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
      int Function(int, int, int, int, int, int, int)
    >('SetWindowPos');
final _clientToScreen = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<_Point>),
      int Function(int, Pointer<_Point>)
    >('ClientToScreen');
final _showAsync = _user32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
      'ShowWindowAsync',
    );
final _destroyWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyWindow');
final _getMessage = _user32
    .lookupFunction<
      Int32 Function(Pointer<_Msg>, IntPtr, Uint32, Uint32),
      int Function(Pointer<_Msg>, int, int, int)
    >('GetMessageW');
final _peekMessage = _user32
    .lookupFunction<
      Int32 Function(Pointer<_Msg>, IntPtr, Uint32, Uint32, Uint32),
      int Function(Pointer<_Msg>, int, int, int, int)
    >('PeekMessageW');
final _translate = _user32
    .lookupFunction<Int32 Function(Pointer<_Msg>), int Function(Pointer<_Msg>)>(
      'TranslateMessage',
    );
final _dispatch = _user32
    .lookupFunction<
      IntPtr Function(Pointer<_Msg>),
      int Function(Pointer<_Msg>)
    >('DispatchMessageW');
final _postThreadMessage = _user32
    .lookupFunction<
      Int32 Function(Uint32, Uint32, IntPtr, IntPtr),
      int Function(int, int, int, int)
    >('PostThreadMessageW');
final _currentThreadId = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentThreadId');

/// Corpo del thread delle finestre video: ciclo di messaggi che non torna mai
/// all'event loop Dart (così l'isolate resta sullo stesso thread di sistema).
void _videoThread(SendPort out) {
  const wsPopup = 0x80000000, wsClipSiblings = 0x04000000, ssBlackRect = 0x4;
  const wsExNoActivate = 0x08000000, wsExToolWindow = 0x00000080;
  final msg = calloc<_Msg>();
  final cls = 'STATIC'.toNativeUtf16();
  final title = ''.toNativeUtf16();
  // Crea la coda dei messaggi prima di annunciare il thread.
  _peekMessage(msg, 0, 0, 0, 0);
  out.send(_currentThreadId());
  while (_getMessage(msg, 0, 0, 0) > 0) {
    final m = msg.ref;
    if (m.hwnd == 0 && m.message == _wmCreate) {
      final hwnd = _create(
        wsExNoActivate | wsExToolWindow,
        cls,
        title,
        wsPopup | wsClipSiblings | ssBlackRect,
        0,
        0,
        1,
        1,
        m.lParam,
        0,
        0,
        nullptr,
      );
      out.send((m.wParam, hwnd));
    } else if (m.hwnd == 0 && m.message == _wmDestroy) {
      _destroyWindow(m.wParam);
    } else {
      _translate(msg);
      _dispatch(msg);
    }
  }
}

class _VideoThread {
  _VideoThread._();
  static final instance = _VideoThread._();

  Future<int>? _tid;
  final _pending = <int, Completer<int>>{};
  int _next = 1;

  Future<int> _start() => _tid ??= () async {
    final port = ReceivePort();
    final tid = Completer<int>();
    port.listen((m) {
      if (m is int && !tid.isCompleted) {
        tid.complete(m);
      } else if (m is (int, int)) {
        _pending.remove(m.$1)?.complete(m.$2);
      }
    });
    await Isolate.spawn(_videoThread, port.sendPort, debugName: 'video-win');
    return tid.future;
  }();

  Future<int> create(int owner) async {
    final tid = await _start();
    final id = _next++;
    final done = Completer<int>();
    _pending[id] = done;
    _postThreadMessage(tid, _wmCreate, id, owner);
    return done.future;
  }

  Future<void> destroy(int hwnd) async =>
      _postThreadMessage(await _start(), _wmDestroy, hwnd, 0);
}

class VideoSurface {
  VideoSurface._(this.handle, this._owner);

  /// HWND come intero (0 = nessuna).
  final int handle;
  final int _owner;
  (int, int, int, int)? _last;

  // Classe della finestra del runner Flutter (windows/runner/win32_window.cpp).
  static const _ownerClass = 'FLUTTER_RUNNER_WIN32_WINDOW';
  static const _swpNoActivate = 0x10;
  static const _swpShow = 0x40;
  static const _swpNoOwnerZOrder = 0x200;
  static const _swpAsync = 0x4000;

  /// Null fuori da Windows o se la finestra dell'app non si trova.
  /// [owner] = finestra proprietaria (0 = quella dell'app).
  static Future<VideoSurface?> create({int owner = 0}) async {
    if (!Platform.isWindows) return null;
    if (owner == 0) {
      owner = using(
        (a) => _findWindow(_ownerClass.toNativeUtf16(allocator: a), nullptr),
      );
    }
    if (owner == 0) return null;
    final hwnd = await _VideoThread.instance.create(owner);
    return hwnd == 0 ? null : VideoSurface._(hwnd, owner);
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
    // Asincrono: la finestra è di un altro thread, mai aspettarlo da qui.
    _setPos(
      handle,
      0,
      sx,
      sy,
      w,
      h,
      _swpNoActivate | _swpShow | _swpNoOwnerZOrder | _swpAsync,
    );
  }

  /// Nascosta (asincrono: la finestra è del thread video).
  void hide() {
    _last = null;
    _showAsync(handle, 0);
  }

  void destroy() => _VideoThread.instance.destroy(handle);
}
