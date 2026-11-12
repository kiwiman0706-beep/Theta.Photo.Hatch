import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/usb.dart';

/// 出先で USB から取り込む。デジカメ・GoPro・THETA（MTP／PTP）とカードリーダー・USB メモリ。
/// 取り込んだ物は「未処理」に出るので、いつもどおり仕分ける。元の機器からは消さない。
class UsbPage extends StatefulWidget {
  const UsbPage({super.key});

  @override
  State<UsbPage> createState() => _UsbPageState();
}

class _UsbPageState extends State<UsbPage> {
  List<UsbSource>? _sources;
  UsbSource? _source;
  List<UsbFile>? _files;
  Set<String> _imported = {};
  String? _status;
  (int, int)? _progress;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await UsbImporter.sources();
    if (mounted) setState(() => _sources = s);
  }

  Future<void> _open(UsbSource s) async {
    setState(() {
      _source = s;
      _files = null;
      _status = '読み込み中…';
    });
    try {
      if (!await UsbImporter.requestPermission(s)) {
        setState(() => _status = 'USB の許可がありません');
        return;
      }
      final files = await UsbImporter.scan(s);
      files.sort((a, b) => b.date.compareTo(a.date));
      final done = await UsbImporter.imported();
      if (mounted) {
        setState(() {
          _files = files;
          _imported = done;
          _status = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    }
  }

  Future<void> _import(List<UsbFile> files) async {
    final s = _source!;
    setState(() => _progress = (0, files.length));
    final r = await UsbImporter.import(s, files, (d, t) {
      if (mounted) setState(() => _progress = (d, t));
    });
    final done = await UsbImporter.imported();
    if (!mounted) return;
    setState(() {
      _progress = null;
      _imported = done;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.errors.isEmpty
              ? '${r.ok}件を取り込みました。「未処理」で仕分けてください'
              : '${r.ok}件取り込み / ${r.errors.length}件失敗（${r.errors.first}）',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _source;
    return Scaffold(
      appBar: AppBar(
        title: Text(s == null ? 'USB から取り込む' : s.label),
        leading: s == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _source = null)),
        actions: [IconButton(onPressed: s == null ? _refresh : () => _open(s), icon: const Icon(Icons.refresh))],
      ),
      body: s == null ? _sourceList() : _fileList(s),
    );
  }

  Widget _sourceList() {
    final list = _sources;
    if (list == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      children: [
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'USB の機器が見つかりません。\n\n'
              '・カメラ／GoPro／THETA：USB-C でつなぎ、カメラ側の USB 設定を「MTP」か「PTP」に\n'
              '・SD カード：カードリーダーでつなぐ\n\n'
              'つないだら右上の更新を押してください。',
            ),
          ),
        for (final x in list)
          ListTile(
            leading: Icon(x.kind == 'mtp' ? Icons.photo_camera : Icons.sd_card),
            title: Text(x.label),
            subtitle: Text(x.kind == 'mtp' ? 'カメラ（MTP／PTP）' : 'カードリーダー・USB メモリ（${x.path}）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(x),
          ),
      ],
    );
  }

  Widget _fileList(UsbSource s) {
    final files = _files;
    if (_status != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_status!)),
      );
    }
    if (files == null) return const Center(child: CircularProgressIndicator());
    final fresh = files.where((f) => !_imported.contains(f.key(s))).toList();
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    final prog = _progress;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: Text('${files.length}件（まだ取り込んでいない物 ${fresh.length}件）')),
              FilledButton.icon(
                onPressed: fresh.isEmpty || prog != null ? null : () => _import(fresh),
                icon: const Icon(Icons.download),
                label: const Text('新しい物を取り込む'),
              ),
            ],
          ),
        ),
        if (prog != null) LinearProgressIndicator(value: prog.$2 == 0 ? null : prog.$1 / prog.$2),
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (_, i) {
              final f = files[i];
              final done = _imported.contains(f.key(s));
              return ListTile(
                dense: true,
                leading: Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: done ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(f.name),
                subtitle: Text('${fmt.format(f.date)}  ${(f.size / 1e6).toStringAsFixed(1)} MB  ${f.folder}'),
              );
            },
          ),
        ),
      ],
    );
  }
}
