import 'dart:io';

import 'package:flutter/material.dart';

import 'app/l10n.dart';
import 'app/phone_controller.dart';
import 'app/theme.dart';
import 'core/app_paths.dart';
import 'core/call_history.dart';
import 'core/contacts/personal_contacts.dart';
import 'core/pbx/pbx_cache.dart';
import 'core/platform/window_attention.dart';
import 'core/security/api_credential_store.dart';
import 'core/security/settings_store.dart';
import 'core/sip/linphone_ffi_engine.dart';
import 'features/shell/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = AppPaths.forPlatform();
  final phone = PhoneController(
    LinphoneFfiEngine(),
    SettingsStore(paths.settingsFile),
    engineDataDir: paths.engineData,
    logDir: paths.logs,
    // DPAPI esiste solo su Windows: altrove niente integrazione API per ora.
    historyStoreFor: (id) => CallHistoryStore(paths.historyFileFor(id)),
    personalStoreFor: (id) => PersonalContactsStore(paths.contactsFileFor(id)),
    onIncomingCall: WindowAttention.instance.request,
    apiStoreFor: Platform.isWindows
        ? (id) => ApiCredentialStore(paths.apiCredentialsFileFor(id))
        : null,
    cacheFor: Platform.isWindows
        ? (id) => PbxCache(paths.pbxCacheFileFor(id))
        : null,
  );
  await phone.init();
  runApp(DrinPhoneApp(phone: phone));
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
