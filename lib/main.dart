import 'package:flutter/material.dart';

import 'app/phone_controller.dart';
import 'app/theme.dart';
import 'core/app_paths.dart';
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
  );
  await phone.init();
  runApp(DrinPhoneApp(phone: phone));
}

class DrinPhoneApp extends StatelessWidget {
  const DrinPhoneApp({super.key, required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DrinPhone',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomeScreen(phone: phone),
    );
  }
}
