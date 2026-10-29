import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'naming.dart';
import 'native.dart';
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

  static Future<SortResult> run(List<MediaItem> items, SortRequest req) async {
    final root = await NativeBridge.storageRoot();
    final cat = req.category;
    final targetDir = cat == null ? await trashDir() : p.join(root, 'Pictures', cat.folder);
    await Directory(targetDir).create(recursive: true);

    final batch = DateTime.now();
    final scan = <String>[];
    final log = <Map<String, dynamic>>[];
    final errors = <String>[];

    for (final item in items) {
      try {
        final name = cat == null ? item.name : hatchFileName(item.takenAt, item.name, event: req.event);
        final dest = uniquePath(targetDir, name, (s) => File(s).existsSync());
        await _move(item.path, dest);
        String? sidecar;
        if (cat != null) {
          sidecar = await writeMetadata(
            dest,
            HatchMeta(
              categoryId: cat.id,
              categoryLabel: cat.label,
              processedAt: batch,
              event: req.event,
              starred: req.starred,
              keywords: req.keywords,
              originalName: item.name,
            ),
          );
        }
        scan
          ..add(item.path)
          ..add(dest);
        log.add({
          'batch': batch.toIso8601String(),
          'from': item.path,
          'to': dest,
          'sidecar': sidecar,
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
    for (final e in undo) {
      final to = e['to'] as String, from = e['from'] as String;
      if (File(to).existsSync() && !File(from).existsSync()) {
        await _move(to, from);
        scan
          ..add(to)
          ..add(from);
      }
      final sc = e['sidecar'] as String?;
      if (sc != null && File(sc).existsSync()) await File(sc).delete();
    }
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
