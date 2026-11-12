import 'dart:convert';

import 'package:flutter/material.dart';

class MediaItem {
  MediaItem({
    required this.id,
    required this.path,
    required this.name,
    required this.mime,
    required this.size,
    required this.isVideo,
    required this.relativePath,
    required this.takenAt,
    this.width = 0,
    this.height = 0,
  });

  factory MediaItem.fromMap(Map<dynamic, dynamic> m) => MediaItem(
    id: (m['id'] as num).toInt(),
    path: m['path'] as String,
    name: m['name'] as String,
    mime: (m['mime'] as String?) ?? '',
    size: (m['size'] as num?)?.toInt() ?? 0,
    isVideo: m['isVideo'] as bool? ?? false,
    relativePath: (m['relativePath'] as String?) ?? '',
    takenAt: DateTime.fromMillisecondsSinceEpoch((m['takenMs'] as num).toInt()),
  );

  final int id;
  final String path;
  final String name;
  final String mime;
  final int size;
  final bool isVideo;
  final String relativePath;
  final DateTime takenAt;
  final int width, height;

  /// 360° 写真の候補（縦横 2:1）。本当にそうかは XMP（GPano）で確かめる（pano.dart）
  bool get maybePanorama => !isVideo && width > 0 && width == height * 2;

  DateTime get day => DateTime(takenAt.year, takenAt.month, takenAt.day);
}

/// 仕分け先。端末上では `Pictures/<folder>/` という「固定の」フォルダになる。
/// フォルダを固定にしておくことで、Amazon フォトや Synology Photos の
/// 「バックアップするフォルダ」設定が一度で済む。
class HatchCategory {
  HatchCategory({
    required this.id,
    required this.label,
    required this.folder,
    required this.hint,
    required this.color,
    this.nasRoot = '',
  });

  factory HatchCategory.fromJson(Map<String, dynamic> j) => HatchCategory(
    id: j['id'] as String,
    label: j['label'] as String,
    folder: j['folder'] as String,
    hint: (j['hint'] as String?) ?? '',
    color: Color((j['color'] as num).toInt()),
    nasRoot: (j['nasRoot'] as String?) ?? defaultNasRoot(j['id'] as String),
  );

  final String id;
  String label;
  String folder;
  String hint;
  Color color;

  /// NAS（File Station）のアップ先。この下に `<年>/<YYYY-MM-DD> <イベント>/` を作る（ライブラリ規則 §5）。空ならアップしない
  String nasRoot;

  String get relativePath => 'Pictures/$folder/';

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'folder': folder,
    'hint': hint,
    'color': color.toARGB32(),
  };

  static String encodeList(List<HatchCategory> l) => jsonEncode(l.map((c) => c.toJson()).toList());
  static List<HatchCategory> decodeList(String s) =>
      (jsonDecode(s) as List).map((e) => HatchCategory.fromJson(e as Map<String, dynamic>)).toList();
}

const trashFolder = 'Hatch_Trash';

/// USB から取り込んだ物の置き場所（未処理として表示する）
const usbInboxFolder = 'Hatch_Inbox';

/// 共有スペース（photo）は家族で見る物、個人スペース（home/Photos）は自分だけの物
String defaultNasRoot(String id) => switch (id) {
  'family_share' || 'family' => '/photo',
  'memo' => '/home/Photos/Memo',
  'private' => '/home/Photos/Private',
  _ => '',
};

List<HatchCategory> defaultCategories() => [
  HatchCategory(
    id: 'family_share',
    nasRoot: defaultNasRoot('family_share'),
    label: '家族・共有',
    folder: 'Hatch_FamilyShare',
    hint: 'Amazonフォト（Echo表示）＋ みてね ＋ Synology',
    color: const Color(0xFFE57373),
  ),
  HatchCategory(
    id: 'family',
    nasRoot: defaultNasRoot('family'),
    label: '家族',
    folder: 'Hatch_Family',
    hint: 'Synologyのみ',
    color: const Color(0xFFFFB74D),
  ),
  HatchCategory(
    id: 'memo',
    nasRoot: defaultNasRoot('memo'),
    label: 'メモ',
    folder: 'Hatch_Memo',
    hint: 'Synologyのみ',
    color: const Color(0xFF64B5F6),
  ),
  HatchCategory(
    id: 'private',
    nasRoot: defaultNasRoot('private'),
    label: '記録（非公開）',
    folder: 'Hatch_Private',
    hint: 'Synologyの個人スペースのみ。どこにも共有しない',
    color: const Color(0xFF90A4AE),
  ),
];
