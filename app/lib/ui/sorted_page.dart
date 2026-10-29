import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models.dart';
import '../core/native.dart';
import '../core/settings.dart';
import '../core/sorter.dart';
import 'media_grid.dart';

class SortedPage extends StatefulWidget {
  const SortedPage({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<SortedPage> createState() => _SortedPageState();
}

class _SortedPageState extends State<SortedPage> with WidgetsBindingObserver {
  Map<String, int> _counts = {};
  int _trash = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_reload);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final cats = widget.settings.categories;
    final items = await NativeBridge.listMedia(cats.map((c) => c.relativePath).toList());
    final counts = <String, int>{};
    for (final i in items) {
      counts[i.relativePath] = (counts[i.relativePath] ?? 0) + 1;
    }
    final trash = (await Sorter.trashFiles()).length;
    if (mounted) {
      setState(() {
        _counts = counts;
        _trash = trash;
      });
    }
  }

  Future<void> _emptyTrash() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ゴミ箱を空にする'),
        content: Text('$_trash件を端末から完全に削除します。元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    await Sorter.emptyTrash();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.settings.categories;
    return Scaffold(
      appBar: AppBar(title: const Text('仕分け済み')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: [
            const _UploadGuide(),
            for (final c in cats)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: c.color,
                  child: const Icon(Icons.folder, color: Colors.white),
                ),
                title: Text(c.label),
                subtitle: Text('Pictures/${c.folder}\n${c.hint}'),
                isThreeLine: true,
                trailing: Text('${_counts[c.relativePath] ?? 0}', style: Theme.of(context).textTheme.titleMedium),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FolderPage(category: c)));
                  _reload();
                },
              ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.delete_outline)),
              title: const Text('ゴミ箱'),
              subtitle: const Text('Pictures/$trashFolder（どこにもアップロードされません）'),
              trailing: TextButton(onPressed: _trash == 0 ? null : _emptyTrash, child: Text('$_trash件 空にする')),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadGuide extends StatelessWidget {
  const _UploadGuide();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: ExpansionTile(
        leading: const Icon(Icons.cloud_upload_outlined),
        title: const Text('アップロード設定のしかた'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '仕分け先フォルダは固定なので、各アプリの設定は最初の1回だけです。\n\n'
            '① Amazonフォト：自動保存の対象フォルダを「Hatch_FamilyShare」だけにする'
            '（カメラフォルダはオフ）\n'
            '② Synology Photos：バックアップ対象に「Hatch_」で始まるフォルダをすべて追加'
            '（カメラフォルダはオフ）\n'
            '③ みてね：下の各フォルダを開いて写真を選び、共有ボタン → みてね\n'
            '④ アップロードが終わったら Synology Photos の「空き容量を確保」で端末から削除',
          ),
        ],
      ),
    );
  }
}

class FolderPage extends StatefulWidget {
  const FolderPage({super.key, required this.category});
  final HatchCategory category;

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  List<MediaItem>? _items;
  Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await NativeBridge.listMedia([widget.category.relativePath]);
    items.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    if (mounted) setState(() => _items = items);
  }

  Future<void> _share() async {
    final files = _items!.where((i) => _selected.contains(i.id)).map((i) => XFile(i.path, mimeType: i.mime)).toList();
    await SharePlus.instance.share(ShareParams(files: files));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final n = _selected.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(n > 0 ? '$n件選択中' : widget.category.label),
        actions: [
          if (items != null && items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: () => setState(() => _selected = items.map((e) => e.id).toSet()),
            ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(child: Text('このフォルダは空です'))
          : MediaGrid(items: items, selected: _selected, onChanged: (s) => setState(() => _selected = s)),
      floatingActionButton: n == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: Text('$n件を共有（みてね等）'),
            ),
    );
  }
}
