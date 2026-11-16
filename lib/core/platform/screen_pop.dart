import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Costruisce un URI HTTP/HTTPS valido sostituendo `{number}` e `{name}` nel
/// modello configurato dall'utente. Schemi diversi o modelli non validi
/// restituiscono `null` (niente `javascript:`, `file:`, esecuzione locale).
Uri? buildScreenPopUri(
  String template, {
  required String number,
  String name = '',
}) {
  final raw = template.trim();
  if (raw.isEmpty || number.trim().isEmpty) return null;
  final resolved = raw
      .replaceAll('{number}', Uri.encodeQueryComponent(number.trim()))
      .replaceAll('{name}', Uri.encodeQueryComponent(name.trim()));
  final uri = Uri.tryParse(resolved);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return uri;
}

/// Apre un URI `http`/`https` nel browser predefinito di Windows via
/// `ShellExecuteW`, senza invocare la shell di sistema.
Future<bool> openScreenPopUrl(
  Uri uri, {
  bool Function(Uri)? opener,
}) async {
  if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    return false;
  }
  if (opener != null) return opener(uri);
  if (!Platform.isWindows) return false;
  return _WindowsShellOpen.open(uri.toString());
}

class _WindowsShellOpen {
  static final _shell32 = DynamicLibrary.open('shell32.dll');
  static final _shellExecute = _shell32.lookupFunction<
    IntPtr Function(
      Pointer<Void>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Int32,
    ),
    int Function(
      Pointer<Void>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      int,
    )
  >('ShellExecuteW');

  static bool open(String url) => using((a) {
    final op = 'open'.toNativeUtf16(allocator: a);
    final target = url.toNativeUtf16(allocator: a);
    // Win32 ShellExecuteW restituisce > 32 in caso di successo.
    return _shellExecute(nullptr, op, target, nullptr, nullptr, 1) > 32;
  });
}

