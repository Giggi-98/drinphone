// Credenziali OpenAPI Yeastar (Client ID/Secret) su Windows.
//
// ─── PERCHÉ NON BASTA flutter_secure_storage ───
// flutter_secure_storage tiene la chiave AES nel Gestore credenziali: qualunque
// processo dello stesso utente la legge con CredRead. Qui il blob è cifrato con
// DPAPI (legato a utente Windows + PC) e con un'entropia aggiuntiva = segreto
// compilato nell'app + sale casuale per installazione: senza l'eseguibile di
// DrinPhone il file non si apre, e copiato altrove è inutile. NON protegge da
// codice eseguito con lo stesso utente che estragga il segreto dall'exe, né da
// un amministratore del PC (DECISIONS 2026-10-28 · credenziali API nel client).
//
// Sola scrittura per la UI: l'unico lettore è [load], usato dal client API.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class ApiCredentials {
  const ApiCredentials({
    required this.baseUrl,
    required this.clientId,
    required this.clientSecret,
  });

  /// Es. `https://drin.ras.yeastar.com` o `https://192.168.1.10:8088`.
  final String baseUrl;
  final String clientId;
  final String clientSecret;

  // Mai stampare ID o Secret.
  @override
  String toString() => 'ApiCredentials($baseUrl)';
}

final class _Blob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _ProtectC = Int32 Function(
  Pointer<_Blob>,
  Pointer<Utf16>,
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_Blob>,
);
typedef _ProtectDart = int Function(
  Pointer<_Blob>,
  Pointer<Utf16>,
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_Blob>,
);
typedef _UnprotectC = Int32 Function(
  Pointer<_Blob>,
  Pointer<Pointer<Utf16>>,
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_Blob>,
);
typedef _UnprotectDart = int Function(
  Pointer<_Blob>,
  Pointer<Pointer<Utf16>>,
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_Blob>,
);

class ApiCredentialStore {
  ApiCredentialStore(this.path);

  final String path;
  static const _magic = 'DPAPI1';
  static const _cryptprotectUiForbidden = 0x1;
  // Segreto applicativo: offusca, non è una barriera contro chi analizza l'exe.
  static final _pepper = utf8.encode('DrinPhone/Econnet/yeastar-openapi/v1');

  late final _crypt32 = DynamicLibrary.open('crypt32.dll');
  late final _kernel32 = DynamicLibrary.open('kernel32.dll');
  late final _protect = _crypt32.lookupFunction<_ProtectC, _ProtectDart>(
    'CryptProtectData',
  );
  late final _unprotect = _crypt32.lookupFunction<_UnprotectC, _UnprotectDart>(
    'CryptUnprotectData',
  );
  late final _localFree = _kernel32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');

  bool get isSet => File(path).existsSync();

  Future<void> save(ApiCredentials c) async {
    final salt = Uint8List.fromList(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final plain = utf8.encode(
      jsonEncode({
        'baseUrl': c.baseUrl,
        'clientId': c.clientId,
        'clientSecret': c.clientSecret,
      }),
    );
    final sealed = _dpapi(plain, salt, protect: true);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'format': _magic,
        'salt': base64Encode(salt),
        'blob': base64Encode(sealed),
      }),
      flush: true,
    );
  }

  /// Unico punto di lettura: il client API all'avvio. Null se assenti o se il
  /// file non è decifrabile da questo utente/PC/app.
  Future<ApiCredentials?> load() async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (j['format'] != _magic) return null;
      final plain = _dpapi(
        base64Decode(j['blob'] as String),
        base64Decode(j['salt'] as String),
        protect: false,
      );
      final m = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      return ApiCredentials(
        baseUrl: m['baseUrl'] as String,
        clientId: m['clientId'] as String,
        clientSecret: m['clientSecret'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Uint8List _dpapi(List<int> input, List<int> salt, {required bool protect}) {
    return using((a) {
      Pointer<_Blob> blobOf(List<int> bytes) {
        final b = a<_Blob>();
        final data = a<Uint8>(bytes.length);
        data.asTypedList(bytes.length).setAll(0, bytes);
        b.ref
          ..cbData = bytes.length
          ..pbData = data;
        return b;
      }

      final inBlob = blobOf(input);
      final entropy = blobOf([..._pepper, ...salt]);
      final out = a<_Blob>();
      final ok = protect
          ? _protect(
              inBlob,
              'DrinPhone'.toNativeUtf16(allocator: a),
              entropy,
              nullptr,
              nullptr,
              _cryptprotectUiForbidden,
              out,
            )
          : _unprotect(
              inBlob,
              nullptr,
              entropy,
              nullptr,
              nullptr,
              _cryptprotectUiForbidden,
              out,
            );
      if (ok == 0) throw StateError('DPAPI non riuscita');
      final result = Uint8List.fromList(
        out.ref.pbData.asTypedList(out.ref.cbData),
      );
      // Il buffer di output è allocato da DPAPI: azzerarlo e liberarlo con LocalFree.
      out.ref.pbData
          .asTypedList(out.ref.cbData)
          .fillRange(0, out.ref.cbData, 0);
      _localFree(out.ref.pbData.cast());
      return result;
    });
  }
}
