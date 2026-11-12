import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 未処理として扱う端末内フォルダ（MediaStore の RELATIVE_PATH。下のフォルダも含む）
/// - DCIM/ThetaCamera/：Theta Camera Hatch（DCIM/ThetaCamera/<フォルダ>/）
/// - Pictures/Hatch_Inbox/：USB から取り込んだ物
const defaultSources = [
  'DCIM/Camera/',
  'DCIM/ThetaCamera/',
  'Pictures/Screenshots/',
  'DCIM/Screenshots/',
  'Pictures/$usbInboxFolder/',
];

/// Camera Hatch の写真を仕分けたときの扱い
enum CameraMode {
  /// 仕分け先へ移す（Camera のギャラリーからは見えなくなる）
  move,

  /// Camera のフォルダに残し、仕分け先にはコピー（端末の容量は 2 倍）
  copy,
}

class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;
  static const _secure = FlutterSecureStorage();

  List<HatchCategory> categories = defaultCategories();
  List<String> sources = [...defaultSources];
  List<String> recentKeywords = [];
  List<String> recentEvents = [];

  /// シリーズのスキン（ui.skin）。skinFollow なら Home などで変えた値に合わせる
  String skin = 'system';
  bool skinFollow = true;

  CameraMode cameraMode = CameraMode.move;

  /// NAS（Synology DSM、Tailscale 経由）。nasFollow ならハブ（Home）の nas.url・nas.user に合わせる
  String nasUrl = '';
  String nasUser = '';
  bool nasFollow = true;
  bool uploadWifiOnly = true;

  /// 秘密（端末内で暗号化。書き出し・バックアップには入れない）
  String nasPassword = '';
  String nasDeviceToken = '';

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final c = _p.getString('categories');
    if (c != null) categories = HatchCategory.decodeList(c);
    sources = _p.getStringList('sources') ?? [...defaultSources];
    recentKeywords = _p.getStringList('recentKeywords') ?? [];
    recentEvents = _p.getStringList('recentEvents') ?? [];
    skin = _p.getString('skin') ?? 'system';
    skinFollow = _p.getBool('skinFollow') ?? true;
    cameraMode = CameraMode.values.asNameMap()[_p.getString('cameraMode')] ?? CameraMode.move;
    nasUrl = _p.getString('nasUrl') ?? '';
    nasUser = _p.getString('nasUser') ?? '';
    nasFollow = _p.getBool('nasFollow') ?? true;
    uploadWifiOnly = _p.getBool('uploadWifiOnly') ?? true;
    try {
      nasPassword = await _secure.read(key: 'nas.password') ?? '';
      nasDeviceToken = await _secure.read(key: 'nas.deviceToken') ?? '';
    } catch (e) {
      debugPrint('secure storage: $e');
    }
  }

  void changed() => notifyListeners();

  Future<void> save() async {
    await _p.setString('categories', HatchCategory.encodeList(categories));
    await _p.setStringList('sources', sources);
    await _p.setString('skin', skin);
    await _p.setBool('skinFollow', skinFollow);
    await _p.setString('cameraMode', cameraMode.name);
    await _p.setString('nasUrl', nasUrl);
    await _p.setString('nasUser', nasUser);
    await _p.setBool('nasFollow', nasFollow);
    await _p.setBool('uploadWifiOnly', uploadWifiOnly);
    notifyListeners();
  }

  Future<void> saveSecrets() async {
    await _secure.write(key: 'nas.password', value: nasPassword);
    await _secure.write(key: 'nas.deviceToken', value: nasDeviceToken);
  }

  Future<void> saveCategories() => save();

  Future<void> saveSources(List<String> s) async {
    sources = s.map((e) => e.endsWith('/') ? e : '$e/').toList();
    await save();
  }

  Future<void> remember({List<String> keywords = const [], String? event}) async {
    for (final k in keywords) {
      recentKeywords
        ..remove(k)
        ..insert(0, k);
    }
    if (event != null && event.isNotEmpty) {
      recentEvents
        ..remove(event)
        ..insert(0, event);
    }
    recentKeywords = recentKeywords.take(30).toList();
    recentEvents = recentEvents.take(20).toList();
    await _p.setStringList('recentKeywords', recentKeywords);
    await _p.setStringList('recentEvents', recentEvents);
  }

  /// 設定の書き出し（入れ直し・別の端末へ）。秘密（パスワード・トークン）は入れない
  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'schema': 'thetahatch.photo.settings/1',
    'categories': categories.map((c) => c.toJson()).toList(),
    'sources': sources,
    'recentKeywords': recentKeywords,
    'recentEvents': recentEvents,
    'skin': skin,
    'skinFollow': skinFollow,
    'cameraMode': cameraMode.name,
    'nasUrl': nasUrl,
    'nasUser': nasUser,
    'nasFollow': nasFollow,
    'uploadWifiOnly': uploadWifiOnly,
  });

  Future<void> importJson(String text) async {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['schema'] != 'thetahatch.photo.settings/1') throw const FormatException('Theta Photo Hatch の設定ではありません');
    categories = (j['categories'] as List).map((e) => HatchCategory.fromJson(e as Map<String, dynamic>)).toList();
    sources = (j['sources'] as List).cast<String>();
    recentKeywords = ((j['recentKeywords'] as List?) ?? []).cast<String>();
    recentEvents = ((j['recentEvents'] as List?) ?? []).cast<String>();
    skin = j['skin'] as String? ?? skin;
    skinFollow = j['skinFollow'] as bool? ?? skinFollow;
    cameraMode = CameraMode.values.asNameMap()[j['cameraMode']] ?? cameraMode;
    nasUrl = j['nasUrl'] as String? ?? nasUrl;
    nasUser = j['nasUser'] as String? ?? nasUser;
    nasFollow = j['nasFollow'] as bool? ?? nasFollow;
    uploadWifiOnly = j['uploadWifiOnly'] as bool? ?? uploadWifiOnly;
    await _p.setStringList('recentKeywords', recentKeywords);
    await _p.setStringList('recentEvents', recentEvents);
    await save();
  }

  /// ハブ（Home・KidsHome）の共通設定を取り込む（「シリーズに合わせる」項目だけ）
  bool applyHub(Map<String, String> info) {
    var changed = false;
    final s = info['ui.skin'];
    if (skinFollow && s != null && s.isNotEmpty && s != skin) {
      skin = s;
      changed = true;
    }
    if (nasFollow) {
      final u = info['nas.url'], n = info['nas.user'];
      if (u != null && u.isNotEmpty && u != nasUrl) {
        nasUrl = u;
        changed = true;
      }
      if (n != null && n.isNotEmpty && n != nasUser) {
        nasUser = n;
        changed = true;
      }
    }
    return changed;
  }
}
