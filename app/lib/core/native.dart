import 'package:flutter/services.dart';

import 'models.dart';

class NativeBridge {
  static const _ch = MethodChannel('hatch/native');

  static Future<bool> hasAllFilesAccess() async => (await _ch.invokeMethod<bool>('hasAllFilesAccess')) ?? false;

  static Future<void> requestAllFilesAccess() => _ch.invokeMethod('requestAllFilesAccess');

  static Future<String> storageRoot() async => (await _ch.invokeMethod<String>('storageRoot')) ?? '/storage/emulated/0';

  /// prefix が true なら、下のフォルダ（DCIM/ThetaCamera/<フォルダ>/ など）も含める
  static Future<List<MediaItem>> listMedia(List<String> relativePaths, {bool prefix = false}) async {
    final raw = await _ch.invokeListMethod<Map<dynamic, dynamic>>('listMedia', {
      'relativePaths': relativePaths,
      'prefix': prefix,
    });
    return (raw ?? []).map(MediaItem.fromMap).toList();
  }

  static Future<Uint8List?> thumbnail(MediaItem item, {int size = 256}) =>
      _ch.invokeMethod<Uint8List>('thumbnail', {'id': item.id, 'isVideo': item.isVideo, 'size': size});

  static Future<void> scanFiles(List<String> paths) =>
      _ch.invokeMethod('scanFiles', {'paths': paths}).timeout(const Duration(seconds: 30), onTimeout: () => null);

  /// ビューア用に読む（HEIF・回転は OS に任せる）。bytes（JPEG）・width・height
  static Future<({Uint8List bytes, int width, int height})?> decode(String path, {int max = 2560}) async {
    final m = await _ch.invokeMapMethod<String, dynamic>('decode', {'path': path, 'max': max});
    if (m == null) return null;
    return (bytes: m['bytes'] as Uint8List, width: m['width'] as int, height: m['height'] as int);
  }

  /// Wi-Fi（か有線）で、従量制でない回線か
  static Future<bool> isWifi() async => (await _ch.invokeMethod<bool>('isWifi')) ?? false;

  /// ビューアとして開かれたときの写真のパス（無ければ null）
  static Future<String?> viewIntent() => _ch.invokeMethod<String>('viewIntent');
}
