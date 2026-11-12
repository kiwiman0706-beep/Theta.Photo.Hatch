import 'package:flutter/material.dart';

import 'skins.g.dart';

/// Theta Hatch シリーズのスキン（正本は Theta.Hatch.Series の `design/skins/skins.json`。
/// 値は `skins.g.dart` に生成：`python tool/gen_skins.py <skins.json>`）。
/// 基本は計器盤（HUD）風：黒地にオレンジ 1 色、細い線、四角い角。
@immutable
class Palette {
  final Color bg, panel, raised, fg, muted, faint, line, accent, onAccent, widget, launch, zebra;

  /// POP 系（pop・braun・soft・window）：角を丸め、見出しを色の帯に、ボタンに影、書体はゴシック
  final bool pop;
  final Color accent2, accent3;

  /// 背景の模様：'' / scan（走査線） / grid（方眼） / rain（流れる文字） / lines（白い方眼） / pixel（液晶の横線）
  final String backdrop;

  /// 見出しの上の警告の帯の太さ
  final double hazard;

  /// 作り（hud・pop・term・braun・soft・window・lcd）、角丸、書体（hud・sans・mono）、影（none・hard・soft）
  final String style;
  final double radius;
  final String font;
  final String shadow;

  const Palette({
    required this.bg,
    required this.panel,
    required this.raised,
    required this.fg,
    required this.muted,
    required this.faint,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.widget,
    required this.launch,
    required this.zebra,
    this.pop = false,
    Color? accent2,
    Color? accent3,
    this.backdrop = '',
    this.hazard = 4,
    this.style = 'hud',
    this.radius = 0,
    this.font = 'hud',
    this.shadow = 'none',
  }) : accent2 = accent2 ?? accent,
       accent3 = accent3 ?? accent;

  /// タブの群：0 再生（accent）/ 1 ライブラリ（widget）/ 2 管理（launch）
  Color group(int g) => switch (g) {
    0 => accent,
    1 => widget,
    _ => launch,
  };

  bool get isDark => bg.computeLuminance() < 0.5;

  /// 見出し・数字：hud は Oswald、mono は Share Tech Mono、sans は端末のゴシック。日本語は端末の書体
  String? get display => switch (font) {
    'hud' => 'Oswald',
    'mono' => 'ShareTechMono',
    _ => null,
  };

  /// ラベル・ボタン：hud・mono は Share Tech Mono、sans は端末のゴシック
  String? get mono => font == 'sans' ? null : 'ShareTechMono';
  double get lineWidth => shadow == 'hard' ? 1.5 : 1;

  /// 角丸（POP 系・term・lcd）か、左上を落とした角（HUD）か
  bool get rounded => radius > 0;

  /// ボタン・入力欄の形：HUD は左上を落とした角、ほかは角丸
  ShapeBorder shape({Color? side}) {
    final bs = side == null ? BorderSide.none : BorderSide(color: side, width: lineWidth);
    return rounded
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius > 10 ? radius * 0.7 : 8), side: bs)
        : BeveledRectangleBorder(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)),
            side: bs,
          );
  }
}

const darkPalette = Palette(
  bg: Color(0xFF0A0A0B),
  panel: Color(0xFF111113),
  raised: Color(0xFF19191C),
  fg: Color(0xFFEDEDED),
  muted: Color(0xFFA3A3A3),
  faint: Color(0xFF858585),
  line: Color(0xFF333336),
  accent: Color(0xFFFF6B1A),
  onAccent: Color(0xFF0A0A0B),
  widget: Color(0xFFEDEDED),
  launch: Color(0xFF7A7A7E),
  zebra: Color(0x0FFFFFFF),
);

/// 設定で選べるスキン（ui.skin）
const hudThemes = skinNames;

/// スキン名から配色を決める。'system' と知らない名前は端末のダーク・ライトに合わせる
Palette paletteFor(String mode, Brightness system) =>
    skinPalettes[mode] ?? skinPalettes[system == Brightness.dark ? 'dark' : 'light'] ?? darkPalette;

class HudScope extends InheritedWidget {
  final Palette palette;
  const HudScope({super.key, required this.palette, required super.child});

  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HudScope>()?.palette ?? darkPalette;

  @override
  bool updateShouldNotify(HudScope old) => old.palette != palette;
}

/// ダイアログなど Material 部品の配色
ThemeData hudMaterialTheme(Palette p) {
  final scheme = ColorScheme(
    brightness: p.isDark ? Brightness.dark : Brightness.light,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.widget,
    onSecondary: p.bg,
    error: const Color(0xFFFF4D4D),
    onError: Colors.black,
    surface: p.panel,
    onSurface: p.fg,
    surfaceContainerHighest: p.raised,
    onSurfaceVariant: p.muted,
    outline: p.line,
  );
  final r = p.radius;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: p.bg,
    fontFamily: p.mono,
    dialogTheme: DialogThemeData(
      backgroundColor: p.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r),
        side: BorderSide(color: p.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: p.shape() as OutlinedBorder)),
  );
}
