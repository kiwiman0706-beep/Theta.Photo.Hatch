import 'package:flutter/material.dart';

import '../core/nas.dart';
import '../core/native.dart';
import '../core/settings.dart';
import '../core/uploader.dart';

/// 仕分け済みの写真を NAS（Synology、Tailscale 経由）へ上げる。
/// 置き場所は分類ごとのアップ先の下の `<年>/<YYYY-MM-DD> <イベント>/`。上げたら NAS の大きさを確かめる。
/// 端末からは消さない（消す役は保留中）。
class UploadPage extends StatefulWidget {
  const UploadPage({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  late final Uploader _up = Uploader(widget.settings);
  List<UploadItem>? _items;
  UploadProgress? _progress;
  bool _running = false;
  bool? _wifi;
  final _log = <String>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await _up.pending();
    final wifi = await NativeBridge.isWifi();
    if (mounted) {
      setState(() {
        _items = items;
        _wifi = wifi;
      });
    }
  }

  Future<String?> _askOtp(String message) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('2 段階認証'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('ログイン')),
        ],
      ),
    );
  }

  Future<void> _start() async {
    final items = _items;
    if (items == null || items.isEmpty) return;
    if (widget.settings.uploadWifiOnly && !await NativeBridge.isWifi()) {
      setState(() => _log.insert(0, 'Wi-Fi につないでから上げてください（設定で変えられます）'));
      return;
    }
    setState(() => _running = true);
    try {
      for (;;) {
        try {
          await _up.nas.ensureLogin();
          break;
        } on NasOtpException catch (e) {
          final code = await _askOtp(e.message);
          if (code == null || code.isEmpty) rethrow;
          _up.nas.setOtp(code);
        }
      }
      final r = await _up.run(items, (p) {
        if (mounted) setState(() => _progress = p);
      });
      _log.insert(0, '${r.ok}件を上げました');
      _log.insertAll(0, r.errors);
    } catch (e) {
      _log.insert(0, '$e');
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _progress = null;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final t = Theme.of(context).textTheme;
    final p = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('NAS へ上げる')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.settings.nasUrl.isEmpty)
                  const Text('設定 → NAS で接続先を入れてください（Theta Home Hatch があれば、そこから受け取れます）'),
                Text('まだ上げていない物：${items.length}件', style: t.titleMedium),
                Text(
                  '回線：${_wifi == null
                      ? '…'
                      : _wifi!
                      ? 'Wi-Fi'
                      : 'モバイル回線'}'
                  '${widget.settings.uploadWifiOnly ? '（Wi-Fi のときだけ上げる）' : ''}',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 12),
                if (p != null) ...[
                  LinearProgressIndicator(value: p.total == 0 ? null : p.done / p.total),
                  Text('${p.done}/${p.total}  ${p.current}', style: t.bodySmall),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _running || items.isEmpty || widget.settings.nasUrl.isEmpty ? null : _start,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('上げる'),
                    ),
                    const SizedBox(width: 12),
                    if (_running) OutlinedButton(onPressed: _up.stop, child: const Text('止める')),
                  ],
                ),
                const SizedBox(height: 16),
                for (final l in _log) Text(l, style: t.bodySmall),
                const Divider(),
                for (final it in items.take(200))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(it.media.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text('→ ${it.dir}${it.files.length > 1 ? '（＋サイドカー ${it.files.length - 1}）' : ''}'),
                  ),
                if (items.length > 200) Text('ほか ${items.length - 200}件', style: t.bodySmall),
              ],
            ),
    );
  }
}
