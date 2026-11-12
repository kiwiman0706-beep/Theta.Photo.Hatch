import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'naming.dart';
import 'native.dart';

/// USB の取り込み元：カードリーダー・USB メモリ（volume）か、MTP／PTP のカメラ（mtp）
class UsbSource {
  UsbSource(this.kind, this.key, this.label, {this.path, this.granted = true});
  final String kind, key, label;
  final String? path;
  final bool granted;
}

class UsbFile {
  UsbFile({required this.name, required this.size, required this.date, required this.folder, this.handle, this.path});
  final String name, folder;
  final int size;
  final DateTime date;
  final int? handle;
  final String? path;

  String key(UsbSource s) => '${s.label}|$folder/$name|$size|${date.millisecondsSinceEpoch}';
}

const _media = {
  'jpg', 'jpeg', 'heic', 'heif', 'png', 'dng', 'arw', 'cr2', 'cr3', 'nef', 'orf', 'rw2', 'raf', 'gpr', //
  'mp4', 'mov', 'insv', 'insp', 'avi', 'mts', 'm4v',
};

/// USB からの取り込み。端末の `Pictures/Hatch_Inbox/<機器>/` へコピーし（元は消さない）、未処理として仕分ける。
/// 取り込んだ物は記録（imported.json）に残し、次は飛ばす。
class UsbImporter {
  static const _ch = MethodChannel('hatch/usb');
  static void Function(int done, int total)? _progress;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'importProgress') {
        final a = call.arguments as Map;
        _progress?.call(a['done'] as int, a['total'] as int);
      }
    });
  }

  static Future<List<UsbSource>> sources() async {
    final vols = await _ch.invokeListMethod<Map<dynamic, dynamic>>('volumes') ?? [];
    final mtp = await _ch.invokeListMethod<Map<dynamic, dynamic>>('mtpDevices') ?? [];
    return [
      for (final v in vols) UsbSource('volume', v['key'] as String, v['label'] as String, path: v['path'] as String),
      for (final d in mtp) UsbSource('mtp', d['key'] as String, d['label'] as String, granted: d['granted'] as bool),
    ];
  }

  static Future<bool> requestPermission(UsbSource s) async =>
      s.kind != 'mtp' || ((await _ch.invokeMethod<bool>('mtpPermission', {'key': s.key})) ?? false);

  static Future<List<UsbFile>> scan(UsbSource s) async {
    if (s.kind == 'mtp') {
      final raw = await _ch.invokeListMethod<Map<dynamic, dynamic>>('mtpList', {'key': s.key}) ?? [];
      return [
        for (final r in raw)
          UsbFile(
            name: r['name'] as String,
            size: (r['size'] as num).toInt(),
            date: DateTime.fromMillisecondsSinceEpoch((r['dateMs'] as num).toInt()),
            folder: r['folder'] as String,
            handle: (r['handle'] as num).toInt(),
          ),
      ];
    }
    final root = Directory(s.path!);
    final out = <UsbFile>[];
    await for (final e in root.list(recursive: true, followLinks: false).handleError((_) {})) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: root.path);
      if (rel.split('/').any((part) => part.startsWith('.') || part == 'Android' || part == 'LOST.DIR')) continue;
      if (!_media.contains(p.extension(e.path).replaceFirst('.', '').toLowerCase())) continue;
      final st = await e.stat();
      out.add(
        UsbFile(name: p.basename(e.path), size: st.size, date: st.modified, folder: p.dirname(rel), path: e.path),
      );
    }
    return out;
  }

  static Future<File> _ledgerFile() async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'imported.json'));

  static Future<Set<String>> imported() async {
    final f = await _ledgerFile();
    if (!f.existsSync()) return {};
    try {
      return (jsonDecode(await f.readAsString()) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// 機器ごとの取り込み先（Pictures/Hatch_Inbox/<機器>/）
  static Future<String> inboxDir(UsbSource s) async {
    final label = sanitizeEvent(s.label).isEmpty ? 'USB' : sanitizeEvent(s.label);
    return p.join(await NativeBridge.storageRoot(), 'Pictures', usbInboxFolder, label);
  }

  static Future<({int ok, List<String> errors})> import(
    UsbSource s,
    List<UsbFile> files,
    void Function(int done, int total) onProgress,
  ) async {
    final dir = await inboxDir(s);
    await Directory(dir).create(recursive: true);
    final done = await imported();
    final targets = <(UsbFile, String)>[];
    for (final f in files) {
      targets.add((f, uniquePath(dir, f.name, (x) => File(x).existsSync() || targets.any((t) => t.$2 == x))));
    }
    var ok = 0;
    final errors = <String>[];
    if (s.kind == 'mtp') {
      _progress = onProgress;
      try {
        final r = await _ch.invokeMapMethod<String, dynamic>('mtpImport', {
          'key': s.key,
          'items': [
            for (final t in targets) {'handle': t.$1.handle, 'dest': t.$2},
          ],
        });
        errors.addAll(((r?['errors'] as List?) ?? []).cast<String>());
      } finally {
        _progress = null;
      }
    } else {
      for (var i = 0; i < targets.length; i++) {
        final (f, dest) = targets[i];
        try {
          await File(f.path!).copy('$dest.part');
          await File('$dest.part').rename(dest);
        } catch (e) {
          errors.add('${f.name}: $e');
        }
        onProgress(i + 1, targets.length);
      }
    }
    final scan = <String>[];
    for (final (f, dest) in targets) {
      final file = File(dest);
      if (!file.existsSync()) continue;
      // EXIF の無い物（動画など）も撮影日で並ぶように、更新日時を機器の日時にそろえる
      try {
        await file.setLastModified(f.date);
      } catch (_) {}
      done.add(f.key(s));
      scan.add(dest);
      ok++;
    }
    await (await _ledgerFile()).writeAsString(jsonEncode(done.toList()), flush: true);
    await NativeBridge.scanFiles(scan);
    return (ok: ok, errors: errors);
  }
}
