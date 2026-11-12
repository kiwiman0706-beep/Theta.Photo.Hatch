import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:path/path.dart' as p;

import '../core/camera_hatch.dart';
import '../core/models.dart';
import '../core/native.dart';
import '../core/pano.dart';
import 'thumb.dart';

/// 1 枚を見る画面。
/// - HEIF の clap（Theta Camera Hatch の「全体を残して表示範囲を記録」）：範囲どおりに切って見せる。「全体」で切らずに見る
/// - 360° 写真（THETA など、GPano の equirectangular）：ぐるっと見回す。端末の向きでも動かせる
class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.path, this.item});
  final String path;
  final MediaItem? item;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  bool? _pano;
  bool _gyro = false;
  bool _showFull = false;
  ({Uint8List bytes, int width, int height})? _img;
  CropInfo? _crop;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final item = widget.item;
    if (item?.isVideo ?? false) return;
    final pano = await isPanorama(widget.path);
    if (!mounted) return;
    setState(() => _pano = pano);
    if (pano) return;
    try {
      final root = await NativeBridge.storageRoot();
      final crop = await findCrop(widget.path, storageRoot: root, relativePath: item?.relativePath);
      final img = await NativeBridge.decode(widget.path);
      if (mounted) {
        setState(() {
          _crop = crop;
          _img = img;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    final frac = (img == null || _showFull) ? null : _crop?.fractionFor(img.width, img.height);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(p.basename(widget.path), style: const TextStyle(fontSize: 14)),
        actions: [
          if (_pano == true)
            IconButton(
              tooltip: _gyro ? '指で動かす' : '端末の向きで動かす',
              icon: Icon(_gyro ? Icons.screen_rotation : Icons.touch_app),
              onPressed: () => setState(() => _gyro = !_gyro),
            ),
          if (_crop != null && !_crop!.isFull)
            TextButton(
              onPressed: () => setState(() => _showFull = !_showFull),
              child: Text(_showFull ? '表示範囲' : '全体', style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Center(child: _body(img, frac)),
    );
  }

  Widget _body(({Uint8List bytes, int width, int height})? img, ({double w, double h})? frac) {
    final item = widget.item;
    if (item?.isVideo ?? false) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 240, height: 240, child: MediaThumb(item: item!, selected: false)),
          const SizedBox(height: 12),
          const Text('動画（プレビューはサムネイルのみ）', style: TextStyle(color: Colors.white70)),
        ],
      );
    }
    if (_error != null) return Text('読めませんでした：$_error', style: const TextStyle(color: Colors.white70));
    if (_pano == true) {
      return PanoramaViewer(
        sensorControl: _gyro ? SensorControl.orientation : SensorControl.none,
        child: Image.file(File(widget.path)),
      );
    }
    if (img == null) return const CircularProgressIndicator();
    Widget pic = Image.memory(img.bytes, gaplessPlayback: true);
    if (frac != null) {
      pic = AspectRatio(
        aspectRatio: (img.width * frac.w) / (img.height * frac.h),
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(width: img.width.toDouble(), height: img.height.toDouble(), child: pic),
          ),
        ),
      );
    }
    return InteractiveViewer(maxScale: 8, child: pic);
  }
}
