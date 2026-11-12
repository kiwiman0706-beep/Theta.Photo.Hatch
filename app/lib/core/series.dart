import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// シリーズのハブ（Theta Home Hatch、無ければ KidsHome）とのやり取り（Android 側は Series.kt）。
/// Theta.Hatch.Series spec/THETA_SHARED_SETTINGS.md §4.0・§4.1、spec/THETA_HATCH_SPEC.md §6.1
class Series {
  static const _ch = MethodChannel('hatch/series');
  static const repo = 'kiwiman0706-beep/Theta.Photo.Hatch';

  /// 入っているハブのパッケージ名（無ければ ''）
  static Future<String> hub() async {
    try {
      return await _ch.invokeMethod<String>('hub') ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> version() async {
    try {
      return await _ch.invokeMethod<String>('version') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// key → 値（ui.skin・nas.url・nas.user・nas.shareRoot…）。ハブが無い・読めないときは空
  static Future<Map<String, String>> info() async {
    try {
      final m = await _ch.invokeMapMethod<String, List<Object?>>('info') ?? {};
      return {for (final e in m.entries) e.key: '${e.value.isEmpty ? '' : e.value.first ?? ''}'};
    } catch (e) {
      debugPrint('series info: $e');
      return {};
    }
  }

  /// 利用者が「Home Hatch の設定を使う」を選んだときだけ呼ぶ（nas.password・nas.deviceToken）
  static Future<String> secret(String key) async => await _ch.invokeMethod<String>('secret', {'key': key}) ?? '';

  /// 「シリーズに合わせる」項目を変えたら、ハブにも書く
  static Future<void> tell(String key, String value) async {
    try {
      await _ch.invokeMethod<void>('tell', {'key': key, 'value': value});
    } catch (_) {}
  }

  /// 「更新する」：ハブに頼む（無ければ Releases ページ）。'hub' か 'browser'
  static Future<String> requestUpdate() async => await _ch.invokeMethod<String>('requestUpdate') ?? '';

  static Future<void> openReleases() => _ch.invokeMethod<void>('open');

  /// Releases の最新の版（`v1.2.0` → `1.2.0`）。調べられなければ null
  static Future<String?> latest() async {
    try {
      final r = await http
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final tag = (jsonDecode(r.body) as Map)['tag_name'] as String? ?? '';
      return tag.startsWith('v') ? tag.substring(1) : tag;
    } catch (_) {
      return null;
    }
  }

  /// a が b より新しいか（1.2.10 > 1.2.9）
  static bool newer(String a, String b) {
    List<int> p(String v) => [for (final x in v.split('-').first.split('.')) int.tryParse(x) ?? 0];
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d > 0;
    }
    return false;
  }
}
