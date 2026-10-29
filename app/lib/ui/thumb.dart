import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/native.dart';

final _cache = <int, Uint8List>{};
const _cacheMax = 600;

Future<Uint8List?> _load(MediaItem item) async {
  final hit = _cache.remove(item.id);
  if (hit != null) return _cache[item.id] = hit;
  final data = await NativeBridge.thumbnail(item);
  if (data != null) {
    _cache[item.id] = data;
    if (_cache.length > _cacheMax) _cache.remove(_cache.keys.first);
  }
  return data;
}

class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, required this.item, required this.selected, this.onTap, this.onLongPress});
  final MediaItem item;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cached = _cache[item.id];
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedPadding(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.all(selected ? 8 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(selected ? 8 : 0),
              child: cached != null
                  ? Image.memory(cached, fit: BoxFit.cover, gaplessPlayback: true)
                  : FutureBuilder<Uint8List?>(
                      future: _load(item),
                      builder: (_, s) => s.data == null
                          ? ColoredBox(color: scheme.surfaceContainerHighest)
                          : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
                    ),
            ),
          ),
          if (item.isVideo)
            const Positioned(
              left: 4,
              bottom: 4,
              child: Icon(Icons.play_circle_fill, color: Colors.white, size: 20, shadows: [Shadow(blurRadius: 4)]),
            ),
          if (selected) Positioned(right: 4, top: 4, child: Icon(Icons.check_circle, color: scheme.primary, size: 24)),
        ],
      ),
    );
  }
}
