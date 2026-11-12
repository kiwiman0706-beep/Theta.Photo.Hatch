import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/nas.dart';
import '../core/native.dart';
import '../core/series.dart';
import '../core/settings.dart';
import '../core/sorter.dart';
import 'hud/skins.g.dart';

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
    final nasRoot = TextEditingController(text: c?.nasRoot);
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
                TextField(
                  controller: nasRoot,
                  decoration: const InputDecoration(
                    labelText: 'NAS のアップ先（File Station のパス）',
                    helperText: '例 /photo（共有）・/home/Photos（自分だけ）。空なら上げない',
                  ),
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
                      nasRoot: nasRoot.text.trim(),
                      color: color,
                    ),
                  );
                } else {
                  c
                    ..label = label.text.trim()
                    ..folder = f
                    ..hint = hint.text.trim()
                    ..nasRoot = nasRoot.text.trim()
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
          _SeriesSection(settings: s),
          const Divider(),
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
          const Divider(),
          const ListTile(title: Text('Theta Camera Hatch の写真')),
          RadioGroup<CameraMode>(
            groupValue: s.cameraMode,
            onChanged: (v) async {
              s.cameraMode = v ?? CameraMode.move;
              await s.save();
              setState(() {});
            },
            child: const Column(
              children: [
                RadioListTile(
                  value: CameraMode.move,
                  title: Text('仕分け先へ移す'),
                  subtitle: Text('端末の容量はそのまま。Camera のギャラリーからは見えなくなる'),
                ),
                RadioListTile(
                  value: CameraMode.copy,
                  title: Text('Camera のフォルダに残してコピー'),
                  subtitle: Text('Camera でも見られる。容量は 2 倍（Camera 側で消してください）'),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('設定を書き出す'),
            subtitle: const Text('Documents/ThetaPhotoHatch/ に。パスワードは入れません'),
            onTap: () async {
              final f = await _exportFile();
              await f.parent.create(recursive: true);
              await f.writeAsString(s.exportJson());
              await NativeBridge.scanFiles([f.path]);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('書き出しました：${f.path}')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('設定を読み込む'),
            subtitle: const Text('書き出した設定（分類・アップ先・最近のキーワード）を戻す'),
            onTap: () async {
              final f = await _exportFile();
              String msg;
              try {
                await s.importJson(await f.readAsString());
                msg = '読み込みました';
              } catch (e) {
                msg = '読み込めませんでした：$e';
              }
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              setState(() {});
            },
          ),
          const _VersionTile(),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Theta Photo Hatch',
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

Future<File> _exportFile() async =>
    File('${await NativeBridge.storageRoot()}/Documents/ThetaPhotoHatch/ThetaPhotoHatch-settings.json');

/// シリーズの共通設定：スキン（ui.skin）と NAS。ハブ（Home・KidsHome）があれば、そこから受け取れる
class _SeriesSection extends StatefulWidget {
  const _SeriesSection({required this.settings});
  final AppSettings settings;

  @override
  State<_SeriesSection> createState() => _SeriesSectionState();
}

class _SeriesSectionState extends State<_SeriesSection> {
  String _hub = '';

  @override
  void initState() {
    super.initState();
    Series.hub().then((h) {
      if (mounted) setState(() => _hub = h);
    });
  }

  String get _hubName => _hub.endsWith('kidshome') ? 'Theta KidsHome Hatch' : 'Theta Home Hatch';

  Future<void> _editNas() async {
    final s = widget.settings;
    final url = TextEditingController(text: s.nasUrl);
    final user = TextEditingController(text: s.nasUser);
    final pass = TextEditingController(text: s.nasPassword);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('NAS（Synology）'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                decoration: const InputDecoration(
                  labelText: 'DSM の URL',
                  helperText: '例 100.64.1.2:5000（Tailscale の IP か名前）',
                ),
              ),
              TextField(
                controller: user,
                decoration: const InputDecoration(labelText: 'ユーザー'),
              ),
              TextField(
                controller: pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'パスワード'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final changedAccount = url.text.trim() != s.nasUrl || user.text.trim() != s.nasUser;
    s
      ..nasUrl = url.text.trim()
      ..nasUser = user.text.trim()
      ..nasPassword = pass.text;
    if (changedAccount) s.nasDeviceToken = '';
    await s.save();
    await s.saveSecrets();
    if (s.nasFollow) {
      await Series.tell('nas.url', s.nasUrl);
      await Series.tell('nas.user', s.nasUser);
    }
    setState(() {});
  }

  /// 利用者が選んだときだけ、ハブからパスワードとデバイストークンを受け取る
  Future<void> _borrow() async {
    final s = widget.settings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$_hubName の NAS の設定を使う'),
        content: Text(
          '$_hubName から、NAS の接続先・ユーザー・パスワード・2 段階認証のデバイストークンを受け取ります。'
          '受け取った物はこの端末の中で暗号化して保存します。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('受け取る')),
        ],
      ),
    );
    if (ok != true) return;
    String msg;
    try {
      final info = await Series.info();
      s
        ..nasUrl = info['nas.url'] ?? s.nasUrl
        ..nasUser = info['nas.user'] ?? s.nasUser
        ..nasPassword = await Series.secret('nas.password')
        ..nasDeviceToken = await Series.secret('nas.deviceToken');
      await s.save();
      await s.saveSecrets();
      msg = '受け取りました';
    } catch (e) {
      msg = '受け取れませんでした：$e';
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    setState(() {});
  }

  Future<void> _test() async {
    final nas = NasClient(widget.settings);
    String msg;
    for (;;) {
      try {
        await nas.ensureLogin();
        msg = 'ログインできました';
        break;
      } on NasOtpException catch (e) {
        if (!mounted) return;
        final c = TextEditingController();
        final code = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('2 段階認証'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.message),
                TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
              FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('ログイン')),
            ],
          ),
        );
        if (code == null || code.isEmpty) {
          msg = e.message;
          break;
        }
        nas.setOtp(code);
      } catch (e) {
        msg = '$e';
        break;
      }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Column(
      children: [
        ListTile(
          title: const Text('Hatch シリーズの共通設定'),
          subtitle: Text(_hub.isEmpty ? 'ハブ（Theta Home Hatch）が無いので、このアプリで入力します' : '$_hubName から受け取れます'),
        ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('スキン'),
          trailing: DropdownButton<String>(
            value: skinNames.contains(s.skin) ? s.skin : 'system',
            items: [
              for (final n in skinNames)
                DropdownMenuItem(value: n, child: Text(n == 'system' ? '端末に合わせる' : skinLabels[n] ?? n)),
            ],
            onChanged: (v) async {
              s.skin = v ?? 'system';
              await s.save();
              if (s.skinFollow) await Series.tell('ui.skin', s.skin);
              setState(() {});
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.sync),
          title: const Text('スキンと NAS の接続先をシリーズに合わせる'),
          subtitle: const Text('Home などで変えたら、このアプリにも届く'),
          value: s.skinFollow && s.nasFollow,
          onChanged: (v) async {
            s
              ..skinFollow = v
              ..nasFollow = v;
            await s.save();
            setState(() {});
          },
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('NAS（Synology、Tailscale 経由）'),
          subtitle: Text(
            s.nasUrl.isEmpty ? '未設定' : '${s.nasUser}@${s.nasUrl}${s.nasDeviceToken.isEmpty ? '' : '（2 段階認証済み）'}',
          ),
          onTap: _editNas,
        ),
        Wrap(
          spacing: 8,
          children: [
            if (_hub.isNotEmpty) OutlinedButton(onPressed: _borrow, child: Text('$_hubName の設定を使う')),
            OutlinedButton(onPressed: s.nasUrl.isEmpty ? null : _test, child: const Text('ログインを試す')),
          ],
        ),
        SwitchListTile(
          secondary: const Icon(Icons.wifi),
          title: const Text('Wi-Fi のときだけ NAS へ上げる'),
          value: s.uploadWifiOnly,
          onChanged: (v) async {
            s.uploadWifiOnly = v;
            await s.save();
            setState(() {});
          },
        ),
      ],
    );
  }
}

/// 今の版と更新。更新はハブ（Home・KidsHome）に頼む。無ければ Releases ページ（spec §6.1）
class _VersionTile extends StatefulWidget {
  const _VersionTile();

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  String _version = '';
  String? _latest;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    Series.version().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final l = await Series.latest();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _latest = l;
    });
    if (l != null && Series.newer(l, _version)) await Series.requestUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final l = _latest;
    final newer = l != null && Series.newer(l, _version);
    return ListTile(
      leading: const Icon(Icons.system_update_outlined),
      title: Text('今の版 $_version'),
      subtitle: Text(
        _checking
            ? '確かめています…'
            : l == null
            ? '「更新を確認」で Releases を見ます'
            : newer
            ? '新しい版 $l があります'
            : '最新です',
      ),
      trailing: TextButton(onPressed: _checking ? null : _check, child: Text(newer ? '更新する' : '更新を確認')),
    );
  }
}
