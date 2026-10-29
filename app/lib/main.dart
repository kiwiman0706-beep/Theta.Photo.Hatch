import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/settings.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja');
  final settings = AppSettings();
  await settings.load();
  runApp(HatchApp(settings: settings));
}

class HatchApp extends StatelessWidget {
  const HatchApp({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFF2A65A);
    return MaterialApp(
      title: 'Photo Hatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: HomeShell(settings: settings),
    );
  }
}
