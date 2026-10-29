import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 未処理として扱う端末内フォルダ（MediaStore の RELATIVE_PATH）
const defaultSources = ['DCIM/Camera/', 'Pictures/Screenshots/', 'DCIM/Screenshots/'];

class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;
  List<HatchCategory> categories = defaultCategories();
  List<String> sources = [...defaultSources];
  List<String> recentKeywords = [];
  List<String> recentEvents = [];

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final c = _p.getString('categories');
    if (c != null) categories = HatchCategory.decodeList(c);
    sources = _p.getStringList('sources') ?? [...defaultSources];
    recentKeywords = _p.getStringList('recentKeywords') ?? [];
    recentEvents = _p.getStringList('recentEvents') ?? [];
  }

  Future<void> saveCategories() async {
    await _p.setString('categories', HatchCategory.encodeList(categories));
    notifyListeners();
  }

  void changed() => notifyListeners();

  Future<void> saveSources(List<String> s) async {
    sources = s.map((e) => e.endsWith('/') ? e : '$e/').toList();
    await _p.setStringList('sources', sources);
    notifyListeners();
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
}
