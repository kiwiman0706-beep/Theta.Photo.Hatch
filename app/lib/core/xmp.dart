import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Hatch が書き込むメタデータ。すべて XMP 標準プロパティに対応させる。
class HatchMeta {
  HatchMeta({
    required this.categoryId,
    required this.categoryLabel,
    required this.processedAt,
    this.event,
    this.starred = false,
    this.keywords = const [],
    this.originalName,
  });

  final String categoryId;
  final String categoryLabel;
  final DateTime processedAt;
  final String? event;
  final bool starred;
  final List<String> keywords;
  final String? originalName;
}

const hatchNs = 'http://ns.theta.photo/hatch/1.0/';
const _xmpHeader = 'http://ns.adobe.com/xap/1.0/\u0000';
const _extXmpHeader = 'http://ns.adobe.com/xmp/extension/\u0000';

String _esc(String s) => const HtmlEscape(HtmlEscapeMode.attribute).convert(s);

/// Hatch 用の rdf:Description 要素。既存の XMP に追記・置換できるよう単独要素にしている。
String buildDescription(HatchMeta m) {
  final attrs = <String>[
    'rdf:about=""',
    'xmlns:xmp="http://ns.adobe.com/xap/1.0/"',
    'xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/"',
    'xmlns:dc="http://purl.org/dc/elements/1.1/"',
    'xmlns:Iptc4xmpExt="http://iptc.org/std/Iptc4xmpExt/2008-02-29/"',
    'xmlns:hatch="$hatchNs"',
    'hatch:Version="1"',
    'hatch:HatchCategory="${_esc(m.categoryId)}"',
    'hatch:ProcessedAt="${m.processedAt.toUtc().toIso8601String()}"',
    'xmp:Label="${_esc(m.categoryLabel)}"',
    if (m.starred) 'xmp:Rating="5"',
    if (m.originalName != null) 'xmpMM:PreservedFileName="${_esc(m.originalName!)}"',
  ];
  final body = StringBuffer();
  if (m.keywords.isNotEmpty) {
    body.write('<dc:subject><rdf:Bag>');
    for (final k in m.keywords) {
      body.write('<rdf:li>${_esc(k)}</rdf:li>');
    }
    body.write('</rdf:Bag></dc:subject>');
  }
  if (m.event != null && m.event!.isNotEmpty) {
    body.write(
      '<Iptc4xmpExt:Event><rdf:Alt>'
      '<rdf:li xml:lang="x-default">${_esc(m.event!)}</rdf:li>'
      '</rdf:Alt></Iptc4xmpExt:Event>',
    );
  }
  return '<rdf:Description ${attrs.join(' ')}>$body</rdf:Description>';
}

String buildPacket(HatchMeta m) =>
    '<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>\n'
    '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
    '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
    '${buildDescription(m)}'
    '</rdf:RDF></x:xmpmeta>\n'
    '<?xpacket end="w"?>';

final _hatchDescription = RegExp(r'<rdf:Description[^>]*xmlns:hatch="[^"]*"[^>]*>[\s\S]*?</rdf:Description>');

/// 既存 XMP パケットに Hatch の Description を差し込む（以前の Hatch 分は置き換え）。
/// 既存の Description（Motion Photo の情報など）は一切触らない。
String? mergeIntoPacket(String existing, HatchMeta m) {
  final cleaned = existing.replaceAll(_hatchDescription, '');
  final idx = cleaned.lastIndexOf('</rdf:RDF>');
  if (idx < 0) return null;
  return cleaned.substring(0, idx) + buildDescription(m) + cleaned.substring(idx);
}

/// JPEG に XMP を埋め込む。成功したら true。
/// 安全のため、少しでも想定外の構造なら何もせず false を返す（呼び出し側はサイドカーに切り替える）。
Uint8List? embedXmpInJpegBytes(Uint8List b, HatchMeta m) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var pos = 2;
  int insertAt = 2;
  int? xmpStart, xmpEnd;
  String? existing;
  while (pos + 4 <= b.length) {
    if (b[pos] != 0xFF) return null;
    final marker = b[pos + 1];
    final isApp = marker >= 0xE0 && marker <= 0xEF;
    if (!isApp && marker != 0xFE) break; // APPn / COM 以外 (DQT, SOF, SOS...) に到達
    final len = (b[pos + 2] << 8) | b[pos + 3];
    final end = pos + 2 + len;
    if (len < 2 || end > b.length) return null;
    final payload = b.sublist(pos + 4, end);
    if (marker == 0xE1) {
      final head = latin1.decode(payload.sublist(0, payload.length.clamp(0, 40)));
      if (head.startsWith(_extXmpHeader)) return null; // 拡張 XMP は扱わない
      if (head.startsWith(_xmpHeader)) {
        xmpStart = pos;
        xmpEnd = end;
        existing = utf8.decode(payload.sublist(_xmpHeader.length), allowMalformed: true);
      }
    }
    if (marker == 0xE0 || marker == 0xE1) insertAt = end;
    pos = end;
  }

  final packet = existing == null ? buildPacket(m) : mergeIntoPacket(existing, m);
  if (packet == null) return null;
  final payload = [...latin1.encode(_xmpHeader), ...utf8.encode(packet)];
  if (payload.length + 2 > 0xFFFF) return null;
  final seg = BytesBuilder()
    ..add([0xFF, 0xE1, (payload.length + 2) >> 8, (payload.length + 2) & 0xFF])
    ..add(payload);
  final segBytes = seg.toBytes();

  final out = BytesBuilder(copy: false);
  if (xmpStart != null) {
    out.add(Uint8List.sublistView(b, 0, xmpStart));
    out.add(segBytes);
    out.add(Uint8List.sublistView(b, xmpEnd!));
  } else {
    out.add(Uint8List.sublistView(b, 0, insertAt));
    out.add(segBytes);
    out.add(Uint8List.sublistView(b, insertAt));
  }
  return out.toBytes();
}

bool isJpeg(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.jpg') || p.endsWith('.jpeg');
}

/// JPEG なら埋め込み、無理ならサイドカー (`<basename>.xmp`) を書く。
/// 戻り値: 作成したサイドカーのパス（埋め込みできた場合は null）
Future<String?> writeMetadata(String path, HatchMeta m) async {
  if (isJpeg(path)) {
    final file = File(path);
    final original = await file.readAsBytes();
    final updated = embedXmpInJpegBytes(original, m);
    if (updated != null) {
      final tmp = File('$path.hatchtmp');
      await tmp.writeAsBytes(updated, flush: true);
      if (await tmp.length() == updated.length) {
        await tmp.rename(path);
        return null;
      }
      await tmp.delete();
    }
  }
  final dot = path.lastIndexOf('.');
  final sidecar = '${dot > 0 ? path.substring(0, dot) : path}.xmp';
  await File(sidecar).writeAsString(buildPacket(m), flush: true);
  return sidecar;
}
