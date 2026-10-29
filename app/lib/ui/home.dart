import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/native.dart';
import '../core/settings.dart';
import '../core/sorter.dart';
import 'media_grid.dart';
import 'settings_page.dart';
import 'sort_sheet.dart';
import 'sorted_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  bool? _granted;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final g = await NativeBridge.hasAllFilesAccess();
    if (mounted && g != _granted) setState(() => _granted = g);
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_granted == false) return const _PermissionPage();
    final pages = [
      InboxPage(settings: widget.settings),
      SortedPage(settings: widget.settings),
      SettingsPage(settings: widget.settings),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox), label: '未処理'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: '仕分け済み'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }
}

class _PermissionPage extends StatelessWidget {
  const _PermissionPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.egg_outlined, size: 72),
              const SizedBox(height: 16),
              Text('Photo Hatch', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              const Text(
                '写真をフォルダへ移動・リネームするために「すべてのファイルへのアクセス」が必要です。\n'
                '次の画面で Photo Hatch をオンにしてから戻ってきてください。',
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: NativeBridge.requestAllFilesAccess,
                icon: const Icon(Icons.lock_open),
                label: const Text('アクセスを許可する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InboxPage extends StatefulWidget {
  const InboxPage({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> with WidgetsBindingObserver {
  List<MediaItem>? _items;
  Set<int> _selected = {};
  bool _busy = false;

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
    final items = await NativeBridge.listMedia(widget.settings.sources);
    items.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    if (!mounted) return;
    setState(() {
      _items = items;
      final ids = items.map((e) => e.id).toSet();
      _selected = _selected.intersection(ids);
    });
  }

  Future<void> _sort() async {
    final items = _items!.where((i) => _selected.contains(i.id)).toList();
    final req = await showModalBottomSheet<SortRequest>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SortSheet(settings: widget.settings, items: items),
    );
    if (req == null || !mounted) return;
    setState(() => _busy = true);
    final res = await Sorter.run(items, req);
    await widget.settings.remember(keywords: req.keywords, event: req.event);
    _selected = {};
    await _reload();
    if (!mounted) return;
    setState(() => _busy = false);
    final where = req.category?.label ?? 'ゴミ箱';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.errors.isEmpty
              ? '${res.moved}件を「$where」に仕分けました'
              : '${res.moved}件成功 / ${res.errors.length}件失敗\n${res.errors.first}',
        ),
        action: SnackBarAction(
          label: '元に戻す',
          onPressed: () async {
            await Sorter.undoLast();
            await _reload();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final n = _selected.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(n > 0 ? '$n件選択中' : '未処理 ${items?.length ?? ''}'),
        leading: n > 0
            ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selected = {}))
            : null,
        actions: [
          if (items != null && items.isNotEmpty)
            IconButton(
              tooltip: 'すべて選択',
              icon: const Icon(Icons.select_all),
              onPressed: () => setState(() => _selected = items.map((e) => e.id).toSet()),
            ),
        ],
      ),
      body: items == null || _busy
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                children: [
                  const SizedBox(height: 160),
                  const Center(child: Text('🐣', style: TextStyle(fontSize: 64))),
                  const SizedBox(height: 12),
                  Center(child: Text('未処理の写真はありません', style: Theme.of(context).textTheme.titleMedium)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: MediaGrid(items: items, selected: _selected, onChanged: (s) => setState(() => _selected = s)),
            ),
      floatingActionButton: n == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: _sort,
              icon: const Icon(Icons.drive_file_move_outline),
              label: Text('$n件を仕分ける'),
            ),
    );
  }
}
