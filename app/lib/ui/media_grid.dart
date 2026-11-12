import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models.dart';
import 'thumb.dart';
import 'viewer.dart';

/// 日付ごとに区切ったグリッド。サムネタップで選択、日付タップでその日を全選択/解除。
class MediaGrid extends StatelessWidget {
  const MediaGrid({super.key, required this.items, required this.selected, required this.onChanged, this.header});

  final List<MediaItem> items; // 新しい順
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final groups = <DateTime, List<MediaItem>>{};
    for (final it in items) {
      groups.putIfAbsent(it.day, () => []).add(it);
    }
    final fmt = DateFormat('yyyy/MM/dd (E)', 'ja');
    final scheme = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        if (header != null) SliverToBoxAdapter(child: header),
        for (final e in groups.entries) ...[
          SliverToBoxAdapter(
            child: InkWell(
              onTap: () {
                final ids = e.value.map((i) => i.id).toSet();
                final all = selected.containsAll(ids);
                final next = {...selected};
                all ? next.removeAll(ids) : next.addAll(ids);
                onChanged(next);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                child: Row(
                  children: [
                    Icon(
                      e.value.every((i) => selected.contains(i.id))
                          ? Icons.check_circle
                          : e.value.any((i) => selected.contains(i.id))
                          ? Icons.remove_circle_outline
                          : Icons.radio_button_unchecked,
                      color: scheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(fmt.format(e.key), style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(width: 8),
                    Text('${e.value.length}', style: TextStyle(color: scheme.outline)),
                  ],
                ),
              ),
            ),
          ),
          SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: e.value.length,
            itemBuilder: (context, i) {
              final it = e.value[i];
              return MediaThumb(
                key: ValueKey(it.id),
                item: it,
                selected: selected.contains(it.id),
                onTap: () {
                  final next = {...selected};
                  next.contains(it.id) ? next.remove(it.id) : next.add(it.id);
                  onChanged(next);
                },
                onLongPress: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ViewerPage(path: it.path, item: it),
                  ),
                ),
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}
