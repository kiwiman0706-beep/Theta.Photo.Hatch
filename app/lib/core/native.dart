import 'package:flutter/services.dart';

import 'models.dart';

class NativeBridge {
  static const _ch = MethodChannel('hatch/native');

  static Future<bool> hasAllFilesAccess() async => (await _ch.invokeMethod<bool>('hasAllFilesAccess')) ?? false;

  static Future<void> requestAllFilesAccess() => _ch.invokeMethod('requestAllFilesAccess');

  static Future<String> storageRoot() async => (await _ch.invokeMethod<String>('storageRoot')) ?? '/storage/emulated/0';

  static Future<List<MediaItem>> listMedia(List<String> relativePaths) async {
    final raw = await _ch.invokeListMethod<Map<dynamic, dynamic>>('listMedia', {'relativePaths': relativePaths});
    return (raw ?? []).map(MediaItem.fromMap).toList();
  }

  static Future<Uint8List?> thumbnail(MediaItem item, {int size = 256}) =>
      _ch.invokeMethod<Uint8List>('thumbnail', {'id': item.id, 'isVideo': item.isVideo, 'size': size});

  static Future<void> scanFiles(List<String> paths) =>
      _ch.invokeMethod('scanFiles', {'paths': paths}).timeout(const Duration(seconds: 30), onTimeout: () => null);
}
