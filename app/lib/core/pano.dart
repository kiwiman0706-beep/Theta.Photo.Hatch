import 'dart:convert';
import 'dart:io';

/// 360° 写真（RICOH THETA など、正距円筒図法）か。
/// XMP の GPano:ProjectionType="equirectangular"（Google Photo Sphere）を見る。
bool isEquirectangularHead(List<int> head) {
  final s = latin1.decode(head, allowInvalid: true);
  return RegExp(r'ProjectionType\s*(=\s*"|>)\s*equirectangular', caseSensitive: false).hasMatch(s);
}

final _cache = <String, bool>{};

/// 先頭 256KB だけ読んで判定する（結果は覚えておく）
Future<bool> isPanorama(String path) async {
  final hit = _cache[path];
  if (hit != null) return hit;
  final lower = path.toLowerCase();
  var r = false;
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    try {
      final f = await File(path).open();
      try {
        r = isEquirectangularHead(await f.read(256 * 1024));
      } finally {
        await f.close();
      }
    } catch (_) {}
  }
  return _cache[path] = r;
}
