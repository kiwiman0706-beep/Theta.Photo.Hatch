import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'camera_hatch.dart';
import 'models.dart';
import 'naming.dart';
import 'native.dart';
import 'settings.dart';
import 'xmp.dart';

class SortRequest {
  SortRequest({required this.category, this.event, this.starred = false, this.keywords = const []});

  /// null ならゴミ箱
  final HatchCategory? category;
  final String? event;
  final bool starred;
  final List<String> keywords;
}

class SortResult {
  SortResult(this.moved, this.errors);
  final int moved;
  final List<String> errors;
}

/// 「移動 + リネーム + XMP」を行い、元に戻せるようジャーナルに記録する。
class Sorter {
  static Future<File> _journal() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'journal.jsonl'));
  }

  static Future<String> trashDir() async {
    final dir = p.join(await NativeBridge.storageRoot(), 'Pictures', trashFolder);
    await Directory(dir).create(recursive: true);
    final nomedia = File(p.join(dir, '.nomedia'));
    if (!nomedia.existsSync()) await nomedia.create();
    return dir;
  }

  static Future<File> _processedFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'processed.json'));
  }

  /// Camera の写真を「コピー」で仕分けた物（元は Camera のフォルダに残る）。未処理の一覧から外す
  static Future<Set<String>> processed() async {
    final f = await _processedFile();
    if (!f.existsSync()) return {};
    try {
      return (jsonDecode(await f.readAsString()) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveProcessed(Set<String> s) async =>
      (await _processedFile()).writeAsString(jsonEncode(s.toList()), flush: true);

  static Future<SortResult> run(
    List<MediaItem> items,
    SortRequest req, {
    CameraMode cameraMode = CameraMode.move,
  }) async {
    final root = await NativeBridge.storageRoot();
    final cat = req.category;
    final targetDir = cat == null ? await trashDir() : p.join(root, 'Pictures', cat.folder);
    await Directory(targetDir).create(recursive: true);

    final batch = DateTime.now();
    final scan = <String>[];
    final log = <Map<String, dynamic>>[];
    final errors = <String>[];

    final processedSet = await processed();
    for (final item in items) {
      try {
        // Theta Camera Hatch の写真：撮影時のイベント・☆・タグ・コメントを引き継ぐ
        final camera = isCameraHatch(item.relativePath);
        final cs = camera ? cameraSidecars(root, item.relativePath, item.name) : null;
        final cam = cs == null ? null : await readCameraSidecar(cs.json, cs.xmp);
        final event = req.event ?? cam?.meta.event;
        final copy = camera && cat != null && cameraMode == CameraMode.copy;

        final name = cat == null ? item.name : hatchFileName(item.takenAt, item.name, event: event);
        final dest = uniquePath(targetDir, name, (s) => File(s).existsSync());
        if (copy) {
          await File(item.path).copy(dest);
        } else {
          await _move(item.path, dest);
        }
        String? sidecar, cameraJson;
        if (cat != null) {
          sidecar = await writeMetadata(
            dest,
            HatchMeta(
              categoryId: cat.id,
              categoryLabel: cat.label,
              processedAt: batch,
              event: event,
              starred: req.starred || (cam?.meta.favorite ?? false),
              keywords: {...req.keywords, ...?cam?.meta.tags}.toList(),
              originalName: item.name,
              comment: cam?.meta.comment ?? '',
            ),
          );
          // Camera の theta.capture/1 も写真の隣へ（名前を合わせ、知らない項目は残す）。
          // Camera 側の元のサイドカーは消さない（元に戻すとき・Camera の索引のため）
          if (cam?.rawJson != null) {
            final j = Map<String, dynamic>.from(cam!.rawJson!)..['media'] = p.basename(dest);
            cameraJson = '${p.withoutExtension(dest)}.theta.json';
            await File(cameraJson).writeAsString(const JsonEncoder.withIndent('  ').convert(j), flush: true);
          }
        }
        if (copy) {
          processedSet.add(item.path);
        } else {
          scan.add(item.path);
        }
        scan.add(dest);
        log.add({
          'batch': batch.toIso8601String(),
          'from': item.path,
          'to': dest,
          'copied': copy,
          'sidecar': sidecar,
          'cameraJson': cameraJson,
          'category': cat?.id ?? 'trash',
          'event': req.event,
          'starred': req.starred,
          'keywords': req.keywords,
        });
      } catch (e) {
        errors.add('${item.name}: $e');
      }
    }

    final j = await _journal();
    await j.writeAsString(log.map((e) => '${jsonEncode(e)}\n').join(), mode: FileMode.append, flush: true);
    await _saveProcessed(processedSet);
    await NativeBridge.scanFiles(scan);
    return SortResult(log.length, errors);
  }

  static Future<void> _move(String from, String to) async {
    try {
      await File(from).rename(to);
    } on FileSystemException {
      await File(from).copy(to);
      await File(from).delete();
    }
  }

  /// 直前の仕分けを取り消す（ファイルを元の場所・元の名前に戻す）。
  static Future<int> undoLast() async {
    final j = await _journal();
    if (!j.existsSync()) return 0;
    final lines = (await j.readAsLines()).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return 0;
    final entries = lines.map((l) => jsonDecode(l) as Map<String, dynamic>).toList();
    final last = entries.last['batch'];
    final undo = entries.where((e) => e['batch'] == last).toList();
    final scan = <String>[];
    final processedSet = await processed();
    for (final e in undo) {
      final to = e['to'] as String, from = e['from'] as String;
      if (e['copied'] == true) {
        // コピーで仕分けた物：コピーを消し、元を未処理に戻す
        if (File(to).existsSync() && File(from).existsSync()) await File(to).delete();
        processedSet.remove(from);
        scan.add(to);
      } else if (File(to).existsSync() && !File(from).existsSync()) {
        await _move(to, from);
        scan
          ..add(to)
          ..add(from);
      }
      for (final k in ['sidecar', 'cameraJson']) {
        final sc = e[k] as String?;
        if (sc != null && File(sc).existsSync()) await File(sc).delete();
      }
    }
    await _saveProcessed(processedSet);
    final keep = entries.where((e) => e['batch'] != last).map((e) => '${jsonEncode(e)}\n').join();
    await j.writeAsString(keep, flush: true);
    await NativeBridge.scanFiles(scan);
    return undo.length;
  }

  static Future<List<File>> trashFiles() async {
    final dir = Directory(await trashDir());
    return dir.listSync().whereType<File>().where((f) => !p.basename(f.path).startsWith('.')).toList();
  }

  static Future<int> emptyTrash() async {
    final files = await trashFiles();
    for (final f in files) {
      await f.delete();
    }
    return files.length;
  }
}
