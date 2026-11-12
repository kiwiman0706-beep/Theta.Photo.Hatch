import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:theta_photo_hatch/core/camera_hatch.dart';
import 'package:theta_photo_hatch/core/pano.dart';
import 'package:theta_photo_hatch/core/uploader.dart';
import 'package:theta_photo_hatch/core/xmp.dart';

List<int> box(String type, List<int> body) {
  final n = body.length + 8;
  return [n >> 24, (n >> 16) & 255, (n >> 8) & 255, n & 255, ...latin1.encode(type), ...body];
}

List<int> u32(int v) => [v >> 24, (v >> 16) & 255, (v >> 8) & 255, v & 255];

void main() {
  group('clap（Theta Camera Hatch の表示範囲）', () {
    test('display_crop を読む', () {
      final c = CropInfo.parse('3000x3000 / 4000x3000')!;
      expect(c.fullW, 4000);
      expect(c.cropW, 3000);
      expect(c.isFull, isFalse);
    });

    test('OS が全体を返したら切る。縦に回っていたら割合も入れ替える', () {
      final c = CropInfo.parse('4000x1718 / 4000x2252')!; // フル（横長の全体、上下を切る）
      final land = c.fractionFor(2000, 1126)!;
      expect(land.w, closeTo(1, 1e-9));
      expect(land.h, closeTo(1718 / 2252, 1e-9));
      final port = c.fractionFor(1126, 2000)!; // irot 270°：縦に表示
      expect(port.w, closeTo(1718 / 2252, 1e-9));
      expect(port.h, closeTo(1, 1e-9));
    });

    test('OS がすでに切っていたら切らない', () {
      final c = CropInfo.parse('3000x3000 / 4000x3000')!;
      expect(c.fractionFor(1500, 1500), isNull);
    });

    test('HEIF の ispe（一番大きい物）と clap を読む', () {
      final head = [
        ...box('ftyp', latin1.encode('heic')),
        ...box('ispe', [0, 0, 0, 0, ...u32(512), ...u32(512)]), // タイル
        ...box('ispe', [0, 0, 0, 0, ...u32(4000), ...u32(3000)]),
        ...box('clap', [...u32(3000), ...u32(1), ...u32(3000), ...u32(1), ...u32(0), ...u32(1), ...u32(0), ...u32(1)]),
      ];
      final c = heifClap(head)!;
      expect((c.fullW, c.fullH, c.cropW, c.cropH), (4000.0, 3000.0, 3000.0, 3000.0));
    });

    test('Camera のサイドカー（theta.capture/1）を読む', () async {
      final dir = await Directory.systemTemp.createTemp('cam');
      final j = File('${dir.path}/20261109_1423_003.theta.json');
      await j.writeAsString(jsonEncode({
        'schema': 'theta.capture/1',
        'media': '20261109_1423_003.heic',
        'event': {'id': 'e1', 'name': 'レゴランド', 'start': '2026-11-09', 'end': '2026-11-10'},
        'favorite': true,
        'tags': ['長女', '初めて'],
        'comment': '初めてのジェットコースター',
        'display_crop': {'type': 'clap-center', 'size': '3000x3000 / 4000x3000'},
      }));
      final r = (await readCameraSidecar(j.path, '${dir.path}/none.xmp'))!;
      expect(r.meta.event, 'レゴランド');
      expect(r.meta.favorite, isTrue);
      expect(r.meta.tags, ['長女', '初めて']);
      expect(r.meta.comment, '初めてのジェットコースター');
      expect(r.meta.crop!.cropW, 3000);
      expect(r.rawJson!['schema'], 'theta.capture/1');
      await dir.delete(recursive: true);
    });

    test('サイドカーの場所（DCIM → Documents）', () {
      final s = cameraSidecars('/storage/emulated/0', 'DCIM/ThetaCamera/家族写真/', '20261109_1423_003.heic');
      expect(s.json, '/storage/emulated/0/Documents/ThetaCamera/家族写真/20261109_1423_003.theta.json');
      expect(s.xmp, '/storage/emulated/0/Documents/ThetaCamera/家族写真/20261109_1423_003.xmp');
    });
  });

  test('360° 写真（GPano の equirectangular）を見分ける', () {
    expect(isEquirectangularHead(latin1.encode('<x GPano:ProjectionType="equirectangular"/>')), isTrue);
    expect(isEquirectangularHead(latin1.encode('<GPano:ProjectionType>equirectangular</GPano:ProjectionType>')), isTrue);
    expect(isEquirectangularHead(latin1.encode('<x GPano:ProjectionType="cylindrical"/>')), isFalse);
  });

  group('NAS の置き場所（ライブラリ規則 §5）', () {
    test('<年>/<YYYY-MM-DD> <イベント>/', () {
      final t = DateTime(2026, 10, 29, 10, 35);
      expect(nasDirFor('/photo', t, '布引ハーブ園'), '/photo/2026/2026-10-29 布引ハーブ園');
      expect(nasDirFor('/home/Photos/Memo/', t, null), '/home/Photos/Memo/2026/2026-10-29');
    });

    test('使えない文字は全角に', () {
      expect(nasSafe('A/B: c?'), 'A／B： c？');
      expect(nasSafe('.隠し.'), '隠し');
    });
  });

  test('XMP のイベントとコメント、読み戻し', () async {
    final dir = await Directory.systemTemp.createTemp('xmp');
    final f = File('${dir.path}/a.heic');
    await f.writeAsBytes(Uint8List.fromList([0, 0, 0, 0]));
    final m = HatchMeta(
      categoryId: 'family',
      categoryLabel: '家族',
      processedAt: DateTime.utc(2026, 11, 12),
      event: 'A & B',
      comment: 'はじめて！',
    );
    final sidecar = await writeMetadata(f.path, m);
    final x = await File(sidecar!).readAsString();
    expect(x, contains(hatchNs));
    expect(x, contains('<dc:description><rdf:Alt><rdf:li xml:lang="x-default">はじめて！</rdf:li>'));
    expect(await readEvent(f.path), 'A & B');
    await dir.delete(recursive: true);
  });
}
