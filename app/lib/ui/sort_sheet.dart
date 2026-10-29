import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/naming.dart';
import '../core/settings.dart';
import '../core/sorter.dart';

class SortSheet extends StatefulWidget {
  const SortSheet({super.key, required this.settings, required this.items});
  final AppSettings settings;
  final List<MediaItem> items;

  @override
  State<SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<SortSheet> {
  HatchCategory? _cat;
  bool _trash = false;
  bool _star = false;
  final _event = TextEditingController();
  final _kwInput = TextEditingController();
  final Set<String> _keywords = {};

  @override
  void initState() {
    super.initState();
    _event.addListener(() => setState(() {}));
  }

  void _addKeyword() {
    final k = _kwInput.text.trim();
    if (k.isEmpty) return;
    setState(() {
      _keywords.add(k);
      _kwInput.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final t = Theme.of(context).textTheme;
    final first = widget.items.first;
    final canRun = _trash || _cat != null;
    final sample = _trash ? null : hatchFileName(first.takenAt, first.name, event: _event.text);
    final kwChoices = {..._keywords, ...s.recentKeywords}.toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.items.length}件を仕分け', style: t.titleLarge),
            const SizedBox(height: 16),
            Text('分類（＝端末内の移動先フォルダ）', style: t.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in s.categories)
                  ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
                    label: Text(c.label),
                    selected: _cat == c && !_trash,
                    onSelected: (_) => setState(() {
                      _cat = c;
                      _trash = false;
                    }),
                  ),
                ChoiceChip(
                  avatar: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('ゴミ箱'),
                  selected: _trash,
                  onSelected: (_) => setState(() {
                    _trash = true;
                    _cat = null;
                  }),
                ),
              ],
            ),
            if (_cat != null && !_trash) ...[
              const SizedBox(height: 6),
              Text('→ Pictures/${_cat!.folder}/  ${_cat!.hint}', style: t.bodySmall),
            ],
            if (!_trash) ...[
              const SizedBox(height: 20),
              TextField(
                controller: _event,
                decoration: const InputDecoration(
                  labelText: 'イベント名（任意）',
                  hintText: '例: 布引ハーブ園',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.event),
                ),
              ),
              if (s.recentEvents.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final e in s.recentEvents.take(6))
                      ActionChip(label: Text(e), onPressed: () => _event.text = e),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(_star ? Icons.star : Icons.star_border, color: _star ? Colors.amber : null),
                title: const Text('☆ 特に大事'),
                value: _star,
                onChanged: (v) => setState(() => _star = v),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _kwInput,
                      decoration: const InputDecoration(
                        labelText: 'キーワード',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.sell_outlined),
                      ),
                      onSubmitted: (_) => _addKeyword(),
                    ),
                  ),
                  IconButton(onPressed: _addKeyword, icon: const Icon(Icons.add)),
                ],
              ),
              if (kwChoices.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final k in kwChoices)
                      FilterChip(
                        label: Text(k),
                        selected: _keywords.contains(k),
                        onSelected: (v) => setState(() => v ? _keywords.add(k) : _keywords.remove(k)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Text('ファイル名の例', style: t.labelMedium),
              Text(sample!, style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !canRun
                    ? null
                    : () => Navigator.pop(
                        context,
                        SortRequest(
                          category: _trash ? null : _cat,
                          event: _event.text.trim().isEmpty ? null : _event.text.trim(),
                          starred: _star,
                          keywords: _keywords.toList(),
                        ),
                      ),
                icon: Icon(_trash ? Icons.delete_outline : Icons.check),
                label: Text(_trash ? 'ゴミ箱へ移動' : '仕分ける'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
