import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'app/l10n.dart';
import 'app/phone_controller.dart';
import 'app/theme.dart';
import 'core/app_paths.dart';
import 'core/call_history.dart';
import 'core/install_id.dart';
import 'core/contacts/personal_contacts.dart';
import 'core/pbx/pbx_cache.dart';
import 'core/video/openh264.dart';
import 'core/platform/window_attention.dart';
import 'core/security/api_credential_store.dart';
import 'core/security/settings_store.dart';
import 'core/sip/linphone_ffi_engine.dart';
import 'core/update/updater.dart';
import 'app/brand.dart';
import 'features/shell/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Font inclusi nell'app (OFL): licenze nella pagina delle licenze.
  LicenseRegistry.addLicense(() async* {
    for (final (pkg, file) in const [
      ('Bricolage Grotesque', 'Bricolage-OFL.txt'),
      ('Onest', 'Onest-OFL.txt'),
      ('Red Hat Mono', 'RedHatMono-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        pkg,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
  final paths = AppPaths.forPlatform();
  final installId = loadInstallId(paths.installIdFile);
  _logErrors(paths.logs, installId);
  final phone = PhoneController(
    LinphoneFfiEngine(),
    SettingsStore(paths.settingsFile),
    engineDataDir: paths.engineData,
    logDir: paths.logs,
    installId: installId,
    // DPAPI esiste solo su Windows: altrove niente integrazione API per ora.
    historyStoreFor: (id) => CallHistoryStore(paths.historyFileFor(id)),
    personalStoreFor: (id) => PersonalContactsStore(paths.contactsFileFor(id)),
    onIncomingCall: WindowAttention.instance.request,
    apiStoreFor: Platform.isWindows
        ? (id) => ApiCredentialStore(paths.apiCredentialsFileFor(id))
        : null,
    openH264: Platform.isWindows ? OpenH264(paths.codecs) : null,
    updater: Platform.isWindows
        ? (Updater(
            current: buildVersion,
            downloadDir: paths.updates,
            notesSeenFile: paths.notesSeenFile,
          )..startPeriodic())
        : null,
    recordingsDir: paths.recordings,
    cacheFor: Platform.isWindows
        ? (id) => PbxCache(paths.pbxCacheFileFor(id))
        : null,
  );
  await phone.init();
  runApp(DrinPhoneApp(phone: phone));
}

/// Errori non gestiti in `logs/flutter-errors.log`: in release un errore di
/// costruzione lascia solo un riquadro grigio (es. scheda Audio su un PC
/// esterno) e senza questo file non c'è modo di sapere perché. Token e
/// password eventualmente presenti negli URL sono oscurati.
void _logErrors(String logDir, String installId) {
  final secret = RegExp(
    r'((?:access_|refresh_)?token|password|secret)=[^&\s]+',
    caseSensitive: false,
  );
  void write(Object error, StackTrace? stack) {
    try {
      Directory(logDir).createSync(recursive: true);
      final text =
          '${DateTime.now().toIso8601String()} $buildVersion $installId\n'
          '$error\n$stack\n\n';
      File('$logDir${Platform.pathSeparator}flutter-errors.log')
          .writeAsStringSync(
            text.replaceAllMapped(secret, (m) => '${m[1]}=***'),
            mode: FileMode.append,
            flush: true,
          );
    } catch (_) {}
  }

  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    write(d.exception, d.stack);
  };
  PlatformDispatcher.instance.onError = (e, s) {
    write(e, s);
    return true;
  };
  // Al posto del riquadro grigio: un messaggio con il nome dell'errore.
  ErrorWidget.builder = (d) => Material(
    color: Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Errore in questa sezione: ${d.exceptionAsString().split('\n').first}\n'
        'Dettagli in $logDir${Platform.pathSeparator}flutter-errors.log',
        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
      ),
    ),
  );
}

class DrinPhoneApp extends StatelessWidget {
  const DrinPhoneApp({super.key, required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    // Cambio lingua o tema dalle Impostazioni: si ricostruisce l'interfaccia.
    return ListenableBuilder(
      listenable: Listenable.merge([appLang, appThemeMode]),
      builder: (_, _) {
        final lang = appLang.value;
        return MaterialApp(
          title: 'DrinPhone',
          debugShowCheckedModeBanner: false,
          locale: Locale(lang.name),
          themeMode: appThemeMode.value,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: HomeScreen(key: ValueKey(lang), phone: phone),
        );
      },
    );
  }
}
