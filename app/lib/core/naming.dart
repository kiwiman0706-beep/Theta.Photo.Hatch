import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

final _bad = RegExp(r'[\\/:*?"<>|\x00-\x1f]');

/// イベント名をファイル名に使える形に整える。
String sanitizeEvent(String s) => s.trim().replaceAll(_bad, '_').replaceAll(RegExp(r'\s+'), '-');

/// 例: 20261029_103512_布引ハーブ園_PXL_20261029_013512345.jpg
/// - 先頭が撮影日時なのでどのツールでも時系列に並ぶ
/// - 元ファイル名を残すので逆引きでき、端末間で名前が衝突しない
String hatchFileName(DateTime takenAt, String originalName, {String? event}) {
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(takenAt);
  final ev = (event == null || event.trim().isEmpty) ? '' : '_${sanitizeEvent(event)}';
  return '$stamp${ev}_$originalName';
}

/// 「20261029｜布引ハーブ園」形式の表示用ラベル。
String eventLabel(DateTime day, String event) => '${DateFormat('yyyyMMdd').format(day)}｜$event';

String uniquePath(String dir, String name, bool Function(String) exists) {
  var candidate = p.join(dir, name);
  final stem = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  var i = 1;
  while (exists(candidate)) {
    candidate = p.join(dir, '${stem}_$i$ext');
    i++;
  }
  return candidate;
}
