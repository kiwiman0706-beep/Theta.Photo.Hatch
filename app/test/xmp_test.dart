import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:theta_photo_hatch/core/naming.dart';
import 'package:theta_photo_hatch/core/xmp.dart';

Uint8List seg(int marker, List<int> payload) =>
    Uint8List.fromList([0xFF, marker, (payload.length + 2) >> 8, (payload.length + 2) & 0xFF, ...payload]);

Uint8List jpeg(List<Uint8List> appSegments) => Uint8List.fromList([
      0xFF, 0xD8,
      for (final s in appSegments) ...s,
      ...seg(0xDB, List.filled(10, 1)), // DQT
      0xFF, 0xDA, 0x00, 0x02, 1, 2, 3, // SOS + data
      0xFF, 0xD9,
    ]);

String xmpOf(Uint8List b) {
  final s = latin1.decode(b);
  final start = s.indexOf('http://ns.adobe.com/xap/1.0/');
  return utf8.decode(b.sublist(start, s.indexOf('<?xpacket end', start) + 20), allowMalformed: true);
}

final meta = HatchMeta(
  categoryId: 'family',
  categoryLabel: '家族',
  processedAt: DateTime.utc(2026, 10, 29),
  event: '布引ハーブ園',
  starred: true,
  keywords: ['長男', 'ハーブ & 花'],
  originalName: 'PXL_1.jpg',
);

void main() {
  test('inserts XMP after Exif APP1 and keeps image data', () {
    final exif = seg(0xE1, [...latin1.encode('Exif\u0000\u0000'), 9, 9]);
    final src = jpeg([seg(0xE0, latin1.encode('JFIF\u0000')), exif]);
    final out = embedXmpInJpegBytes(src, meta)!;
    final x = xmpOf(out);
    expect(x, contains('xmp:Rating="5"'));
    expect(x, contains('<rdf:li>長男</rdf:li>'));
    expect(x, contains('ハーブ &amp; 花'));
    expect(x, contains('布引ハーブ園'));
    // 画像データ（末尾）はそのまま
    expect(out.sublist(out.length - 21), src.sublist(src.length - 21));
    // Exif の直後に挿入されている
    final exifEnd = 2 + 9 + exif.length;
    expect(out[exifEnd], 0xFF);
    expect(out[exifEnd + 1], 0xE1);
  });

  test('merges into existing XMP without dropping other descriptions, and re-run replaces', () {
    const existing = '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta xmlns:x="adobe:ns:meta/">'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description rdf:about="" xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" GCamera:MotionPhoto="1"/>'
        '</rdf:RDF></x:xmpmeta><?xpacket end="w"?>';
    final src = jpeg([seg(0xE1, [...latin1.encode('http://ns.adobe.com/xap/1.0/\u0000'), ...utf8.encode(existing)])]);
    final once = embedXmpInJpegBytes(src, meta)!;
    final twice = embedXmpInJpegBytes(once, meta)!;
    final x = xmpOf(twice);
    expect(x, contains('GCamera:MotionPhoto="1"'));
    expect('hatch:Version'.allMatches(x).length, 1);
    expect(twice.length, once.length);
  });

  test('refuses non-JPEG', () {
    expect(embedXmpInJpegBytes(Uint8List.fromList([1, 2, 3, 4]), meta), isNull);
  });

  test('file naming', () {
    final t = DateTime(2026, 10, 29, 10, 35, 12);
    expect(hatchFileName(t, 'PXL_1.jpg', event: '布引ハーブ園'), '20261029_103512_布引ハーブ園_PXL_1.jpg');
    expect(hatchFileName(t, 'IMG.heic'), '20261029_103512_IMG.heic');
    expect(hatchFileName(t, 'a.jpg', event: ' A/B: c '), '20261029_103512_A_B_-c_a.jpg');
    expect(eventLabel(t, '布引ハーブ園'), '20261029｜布引ハーブ園');
  });
}
