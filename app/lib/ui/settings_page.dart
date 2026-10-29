import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/settings.dart';
import '../core/sorter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _palette = [
    Color(0xFFE57373),
    Color(0xFFFFB74D),
    Color(0xFFFFF176),
    Color(0xFF81C784),
    Color(0xFF64B5F6),
    Color(0xFFBA68C8),
    Color(0xFF90A4AE),
    Color(0xFFA1887F),
  ];

  Future<void> _editCategory(HatchCategory? c) async {
    final label = TextEditingController(text: c?.label);
    final folder = TextEditingController(text: c?.folder ?? 'Hatch_');
    final hint = TextEditingController(text: c?.hint);
    var color = c?.color ?? _palette[3];
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c == null ? '分類を追加' : '分類を編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: '表示名'),
                ),
                TextField(
                  controller: folder,
                  decoration: const InputDecoration(
                    labelText: 'フォルダ名（Pictures/直下）',
                    helperText: '英数字推奨。変更しても既存の写真は移動しません',
                  ),
                ),
                TextField(
                  controller: hint,
                  decoration: const InputDecoration(labelText: 'メモ（アップロード先など）'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in _palette)
                      GestureDetector(
                        onTap: () => set(() => color = p),
                        child: CircleAvatar(
                          backgroundColor: p,
                          radius: 14,
                          child: p == color ? const Icon(Icons.check, size: 16) : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (c != null)
              TextButton(
                onPressed: () {
                  widget.settings.categories.remove(c);
                  Navigator.pop(ctx, true);
                },
                child: const Text('削除'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
            FilledButton(
              onPressed: () {
                final f = folder.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
                if (label.text.trim().isEmpty || f.isEmpty) return;
                if (c == null) {
                  widget.settings.categories.add(
                    HatchCategory(
                      id: 'c${DateTime.now().millisecondsSinceEpoch}',
                      label: label.text.trim(),
                      folder: f,
                      hint: hint.text.trim(),
                      color: color,
                    ),
                  );
                } else {
                  c
                    ..label = label.text.trim()
                    ..folder = f
                    ..hint = hint.text.trim()
                    ..color = color;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await widget.settings.saveCategories();
      setState(() {});
    }
  }

  Future<void> _editSources() async {
    final ctl = TextEditingController(text: widget.settings.sources.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未処理として表示するフォルダ'),
        content: TextField(
          controller: ctl,
          maxLines: 6,
          decoration: const InputDecoration(helperText: '1行に1フォルダ（例: DCIM/Camera/）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      final list = ctl.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      await widget.settings.saveSources(list);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          const ListTile(title: Text('分類（仕分け先フォルダ）')),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (a, b) async {
              s.categories.insert(b, s.categories.removeAt(a));
              await s.saveCategories();
              setState(() {});
            },
            children: [
              for (final c in s.categories)
                ListTile(
                  key: ValueKey(c.id),
                  leading: CircleAvatar(backgroundColor: c.color, radius: 10),
                  title: Text(c.label),
                  subtitle: Text('Pictures/${c.folder}  ${c.hint}'),
                  onTap: () => _editCategory(c),
                ),
            ],
          ),
          ListTile(leading: const Icon(Icons.add), title: const Text('分類を追加'), onTap: () => _editCategory(null)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('未処理として表示するフォルダ'),
            subtitle: Text(s.sources.join(', ')),
            onTap: _editSources,
          ),
          ListTile(
            leading: const Icon(Icons.undo),
            title: const Text('直前の仕分けを元に戻す'),
            onTap: () async {
              final n = await Sorter.undoLast();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n件を元に戻しました')));
              }
              s.changed();
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('分類を初期設定に戻す'),
            onTap: () async {
              s.categories = defaultCategories();
              await s.saveCategories();
              setState(() {});
            },
          ),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Photo Hatch',
            applicationVersion: '0.1.0',
            aboutBoxChildren: [
              Text(
                'タグ・☆・イベント名は XMP（業界標準）で写真に書き込みます。'
                'JPEG は埋め込み、それ以外は同名の .xmp ファイルに保存します。',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
