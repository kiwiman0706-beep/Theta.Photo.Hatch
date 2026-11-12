import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/settings.dart';
import 'core/usb.dart';
import 'ui/home.dart';
import 'ui/hud/hud_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja');
  UsbImporter.init();
  final settings = AppSettings();
  await settings.load();
  runApp(HatchApp(settings: settings));
}

class HatchApp extends StatelessWidget {
  const HatchApp({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    // スキン（ui.skin、Theta.Hatch.Series design/skins/skins.json）。system は端末の明暗
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final p = paletteFor(settings.skin, MediaQuery.platformBrightnessOf(context));
        return HudScope(
          palette: p,
          child: MaterialApp(
            title: 'Theta Photo Hatch',
            debugShowCheckedModeBanner: false,
            theme: _theme(p),
            home: HomeShell(settings: settings),
          ),
        );
      },
    );
  }

  ThemeData _theme(Palette p) {
    final base = hudMaterialTheme(p);
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.fg,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontFamily: p.display, fontSize: 20, color: p.fg, letterSpacing: 0.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.panel,
        indicatorColor: p.accent.withValues(alpha: 0.25),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: p.shape(side: p.line),
      ),
      chipTheme: ChipThemeData(selectedColor: p.accent.withValues(alpha: 0.3)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        shape: p.shape(),
      ),
      dividerColor: p.line,
    );
  }
}
