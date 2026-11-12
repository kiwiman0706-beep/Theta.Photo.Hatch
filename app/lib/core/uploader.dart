import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'nas.dart';
import 'native.dart';
import 'settings.dart';
import 'xmp.dart';

/// NAS のフォルダ名に使えない文字は全角に（Theta.Hatch.Series spec/THETA_LIBRARY_SPEC.md §2）
String nasSafe(String s) {
  const map = {':': '：', '?': '？', '/': '／', '*': '＊', '"': '”', '<': '＜', '>': '＞', '|': '｜', '\\': '＼'};
  var out = s.split('').map((c) => map[c] ?? c).join().trim();
  while (out.endsWith('.')) {
    out = out.substring(0, out.length - 1);
  }
  while (out.startsWith('.')) {
    out = out.substring(1);
  }
  return out;
}

/// 写真の置き場所：`<アップ先>/<年>/<YYYY-MM-DD> <イベント>/`（イベントが無ければ日付だけ）。ライブラリ規則 §5
String nasDirFor(String root, DateTime takenAt, String? event) {
  final day = DateFormat('yyyy-MM-dd').format(takenAt);
  final ev = (event == null || event.trim().isEmpty) ? '' : ' ${nasSafe(event)}';
  final r = root.endsWith('/') ? root.substring(0, root.length - 1) : root;
  return '$r/${takenAt.year}/$day$ev';
}

class UploadItem {
  UploadItem(this.media, this.category, this.dir, this.files);
  final MediaItem media;
  final HatchCategory category;
  final String dir;

  /// 写真と、隣のサイドカー（.xmp・.theta.json）
  final List<File> files;
}

class UploadProgress {
  UploadProgress(this.done, this.total, this.current);
  final int done, total;
  final String current;
}

/// 仕分け済みフォルダの写真を NAS へ上げる。上げた物は端末内の記録（uploaded.json）に残す。
/// 端末からは消さない（消す役はまだ決めていない：Synology Photos の「空き容量を確保」か、このアプリか）。
class Uploader {
  Uploader(this.settings) : nas = NasClient(settings);

  final AppSettings settings;
  final NasClient nas;
  bool _stop = false;

  static Future<File> _ledgerFile() async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'uploaded.json'));

  /// key（パス|大きさ）→ NAS のパス
  static Future<Map<String, String>> ledger() async {
    final f = await _ledgerFile();
    if (!f.existsSync()) return {};
    try {
      return (jsonDecode(await f.readAsString()) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  static String keyOf(MediaItem m) => '${m.path}|${m.size}';

  /// まだ上げていない物
  Future<List<UploadItem>> pending() async {
    final done = await ledger();
    final cats = settings.categories.where((c) => c.nasRoot.trim().isNotEmpty).toList();
    if (cats.isEmpty) return [];
    final items = await NativeBridge.listMedia(cats.map((c) => c.relativePath).toList());
    final out = <UploadItem>[];
    for (final m in items) {
      if (done.containsKey(keyOf(m))) continue;
      final cat = cats.firstWhere((c) => c.relativePath == m.relativePath);
      final event = await readEvent(m.path);
      final stem = p.withoutExtension(m.path);
      final files = [
        File(m.path),
        for (final ext in ['.xmp', '.theta.json'])
          if (File('$stem$ext').existsSync()) File('$stem$ext'),
      ];
      out.add(UploadItem(m, cat, nasDirFor(cat.nasRoot.trim(), m.takenAt, event), files));
    }
    out.sort((a, b) => a.media.takenAt.compareTo(b.media.takenAt));
    return out;
  }

  void stop() => _stop = true;

  /// 1 つずつ上げて、NAS 側の大きさが同じか確かめる。Wi-Fi だけの設定なら、回線が変わったら止める
  Future<({int ok, List<String> errors})> run(List<UploadItem> items, void Function(UploadProgress) onProgress) async {
    _stop = false;
    final done = await ledger();
    final errors = <String>[];
    var ok = 0;
    for (var i = 0; i < items.length && !_stop; i++) {
      final it = items[i];
      onProgress(UploadProgress(i, items.length, it.media.name));
      if (settings.uploadWifiOnly && !await NativeBridge.isWifi()) {
        errors.add('Wi-Fi ではなくなったので止めました');
        break;
      }
      try {
        for (final f in it.files) {
          await nas.upload(it.dir, f);
          final remote = await nas.size('${it.dir}/${p.basename(f.path)}');
          final local = await f.length();
          if (remote != local) throw NasException('${p.basename(f.path)}：NAS の大きさが合いません（$remote / $local）');
        }
        done[keyOf(it.media)] = '${it.dir}/${it.media.name}';
        await (await _ledgerFile()).writeAsString(jsonEncode(done), flush: true);
        ok++;
      } on NasOtpException {
        rethrow;
      } catch (e) {
        errors.add('${it.media.name}：$e');
        if (e is NasException && e.code == 400) break; // ログインできないなら続けない
      }
    }
    onProgress(UploadProgress(items.length, items.length, ''));
    return (ok: ok, errors: errors);
  }
}
