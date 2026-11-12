import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Theta Camera Hatch との連携。
/// Camera は写真を `DCIM/ThetaCamera/<フォルダ>/` に、メタデータを `Documents/ThetaCamera/<フォルダ>/` の
/// `<名前>.theta.json`（theta.capture/1）と `<名前>.xmp` に置く（Camera の PORTABLE_METADATA.md）。
const cameraDcim = 'DCIM/ThetaCamera/';
const cameraDocs = 'Documents/ThetaCamera/';

bool isCameraHatch(String relativePath) => relativePath.startsWith(cameraDcim);

/// Camera が撮影時に付けたもの
class CameraMeta {
  CameraMeta({this.event, this.favorite = false, this.tags = const [], this.comment = '', this.crop});

  final String? event;
  final bool favorite;
  final List<String> tags;
  final String comment;

  /// 表示範囲（clap）
  final CropInfo? crop;
}

/// 表示範囲（clap）。全体と、見せる範囲の幅・高さ（どちらも回転前＝ファイルに入っている向き）。範囲は中央
class CropInfo {
  const CropInfo(this.fullW, this.fullH, this.cropW, this.cropH);
  final double fullW, fullH, cropW, cropH;

  bool get isFull => cropW >= fullW * 0.995 && cropH >= fullH * 0.995;

  /// "3000x3000 / 4000x3000"（Camera の display_crop.size：見せる範囲 / 全体）
  static CropInfo? parse(String? s) {
    final m = RegExp(r'(\d+)\s*x\s*(\d+)\s*/\s*(\d+)\s*x\s*(\d+)').firstMatch(s ?? '');
    if (m == null) return null;
    final v = [for (var i = 1; i <= 4; i++) double.parse(m.group(i)!)];
    if (v[2] == 0 || v[3] == 0) return null;
    return CropInfo(v[2], v[3], v[0], v[1]);
  }

  /// OS が読んだ画像（shownW×shownH）に対して、どれだけ切って見せるか（幅・高さの割合）。
  /// OS がすでに切っている（＝縦横が範囲と同じ）なら null。回転で縦横が入れ替わっていたら割合も入れ替える
  ({double w, double h})? fractionFor(int shownW, int shownH) {
    if (isFull || shownW <= 0 || shownH <= 0) return null;
    final a = shownW / shownH;
    final full = fullW / fullH;
    bool near(double x, double y) => (x - y).abs() / y < 0.02;
    final fw = cropW / fullW, fh = cropH / fullH;
    if (near(a, full)) return (w: fw, h: fh);
    if (near(a, 1 / full)) return (w: fh, h: fw);
    return null;
  }
}

/// 写真に対応するサイドカー（無ければ存在しないパス）
({String json, String xmp}) cameraSidecars(String storageRoot, String relativePath, String fileName) {
  final rest = relativePath.substring(cameraDcim.length);
  final dir = p.join(storageRoot, cameraDocs, rest);
  final base = p.basenameWithoutExtension(fileName);
  return (json: p.join(dir, '$base.theta.json'), xmp: p.join(dir, '$base.xmp'));
}

class CameraSidecar {
  CameraSidecar(this.meta, this.rawJson, this.cropText);
  final CameraMeta meta;
  final Map<String, dynamic>? rawJson;
  final String? cropText;
}

/// .theta.json を読む（無い・壊れているときは .xmp だけ、どちらも無ければ null）
Future<CameraSidecar?> readCameraSidecar(String jsonPath, String xmpPath) async {
  final jf = File(jsonPath);
  if (jf.existsSync()) {
    try {
      final j = jsonDecode(await jf.readAsString()) as Map<String, dynamic>;
      final ev = j['event'];
      final crop = (j['display_crop'] is Map) ? (j['display_crop'] as Map)['size'] as String? : null;
      return CameraSidecar(
        CameraMeta(
          event: ev is Map ? ev['name'] as String? : null,
          favorite: j['favorite'] == true || ((j['rating'] as num?) ?? 0) > 0,
          tags: ((j['tags'] as List?) ?? []).map((e) => '$e').toList(),
          comment: (j['comment'] as String?) ?? '',
          crop: CropInfo.parse(crop),
        ),
        j,
        crop,
      );
    } catch (_) {
      // 壊れた JSON は読まない（上書きもしない）
    }
  }
  final xf = File(xmpPath);
  if (!xf.existsSync()) return null;
  final x = await xf.readAsString();
  final rating = int.tryParse(RegExp(r'xmp:Rating="(-?\d+)"').firstMatch(x)?.group(1) ?? '') ?? 0;
  final subj = RegExp(r'<dc:subject>([\s\S]*?)</dc:subject>').firstMatch(x)?.group(1) ?? '';
  final tags = RegExp(r'<rdf:li>([^<]*)</rdf:li>').allMatches(subj).map((m) => _unesc(m.group(1)!)).toList();
  final desc = RegExp(r'<dc:description>[\s\S]*?<rdf:li[^>]*>([^<]*)</rdf:li>').firstMatch(x)?.group(1);
  return CameraSidecar(CameraMeta(favorite: rating > 0, tags: tags, comment: _unesc(desc ?? '')), null, null);
}

String _unesc(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// HEIF の clap（表示範囲）を読む（Camera のサイドカーが無いとき用）。
/// 全体は一番大きい ispe（主画像。タイルやサムネイルは小さい）、範囲は clap の幅・高さ。無ければ null
CropInfo? heifClap(List<int> head) {
  int u32(int i) => (head[i] << 24) | (head[i + 1] << 16) | (head[i + 2] << 8) | head[i + 3];
  bool at(int i, String t) =>
      head[i] == t.codeUnitAt(0) &&
      head[i + 1] == t.codeUnitAt(1) &&
      head[i + 2] == t.codeUnitAt(2) &&
      head[i + 3] == t.codeUnitAt(3);
  var iw = 0, ih = 0;
  int? clap;
  for (var i = 0; i + 16 <= head.length; i++) {
    if (at(i, 'ispe')) {
      final w = u32(i + 8), h = u32(i + 12); // 'ispe' の後に version/flags（4）、幅、高さ
      if (w * h > iw * ih) {
        iw = w;
        ih = h;
      }
    } else if (clap == null && at(i, 'clap')) {
      clap = i;
    }
  }
  if (clap == null || iw == 0 || clap + 4 + 16 > head.length) return null;
  final wn = u32(clap + 4), wd = u32(clap + 8), hn = u32(clap + 12), hd = u32(clap + 16);
  if (wd == 0 || hd == 0) return null;
  return CropInfo(iw.toDouble(), ih.toDouble(), wn / wd, hn / hd);
}

/// 写真の表示範囲：Camera のサイドカー（写真の隣か Documents/ThetaCamera）→ HEIF の clap の順に探す
Future<CropInfo?> findCrop(String path, {String? storageRoot, String? relativePath}) async {
  final stem = path.substring(0, path.lastIndexOf('.') < 0 ? path.length : path.lastIndexOf('.'));
  final candidates = <String>['$stem.theta.json'];
  if (storageRoot != null && relativePath != null && isCameraHatch(relativePath)) {
    candidates.add(cameraSidecars(storageRoot, relativePath, path.split('/').last).json);
  }
  for (final c in candidates) {
    final f = File(c);
    if (!f.existsSync()) continue;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final dc = j['display_crop'];
      final info = dc is Map ? CropInfo.parse(dc['size'] as String?) : null;
      if (info != null) return info;
    } catch (_) {}
  }
  final lower = path.toLowerCase();
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    try {
      final r = await File(path).open();
      try {
        return heifClap(await r.read(512 * 1024));
      } finally {
        await r.close();
      }
    } catch (_) {}
  }
  return null;
}
