import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'settings.dart';

class NasException implements Exception {
  NasException(this.message, [this.code = 0]);
  final String message;
  final int code;
  @override
  String toString() => message;
}

/// 2 段階認証（Secure SignIn の確認コード）が要る・違う
class NasOtpException extends NasException {
  NasOtpException(super.message, [super.code]);
}

/// Synology DSM の File Station（Tailscale 経由）。
/// 手順は Theta Music Hatch・Home Hatch と同じ：SYNO.API.Info → SYNO.API.Auth（初回だけ確認コード、以後はデバイストークン）。
class NasClient {
  NasClient(this.settings);

  final AppSettings settings;
  final http.Client _c = http.Client();
  Map<String, dynamic>? _apis;
  String? _sid;
  String? _otp;

  /// 「100.1.2.3」のように方式を省いたときは DSM の既定（http, 5000）を補う
  static String normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      final slash = u.indexOf('/');
      final host = slash < 0 ? u : u.substring(0, slash);
      final rest = slash < 0 ? '' : u.substring(slash);
      u = 'http://$host${host.contains(':') ? '' : ':5000'}$rest';
    }
    return u;
  }

  String get base => normalize(settings.nasUrl);

  /// 次のログインで 1 回だけ使う確認コード
  void setOtp(String? code) {
    _otp = (code == null || code.trim().isEmpty) ? null : code.trim();
    if (_otp != null) _sid = null;
  }

  void reset() {
    _sid = null;
    _apis = null;
  }

  Future<Map<String, dynamic>> _postJson(String url, Map<String, String> form, {Duration? timeout}) async {
    final res = await _c.post(Uri.parse(url), body: form).timeout(timeout ?? const Duration(seconds: 20));
    if (res.statusCode != 200) throw NasException('DSM HTTP ${res.statusCode}');
    try {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw NasException('DSM の応答ではありません');
    }
  }

  Map<String, dynamic> _api(String name) {
    final a = _apis?[name];
    if (a is! Map<String, dynamic>) throw NasException('$name が使えません');
    return a;
  }

  int _ver(String name, int want) {
    final a = _api(name);
    final max = a['maxVersion'] as int? ?? want;
    final min = a['minVersion'] as int? ?? 1;
    return want.clamp(min, max);
  }

  String _url(String name) => '$base/webapi/${_api(name)['path'] ?? 'entry.cgi'}';

  Future<void> ensureLogin() async {
    if (_sid != null) return;
    if (base.isEmpty) throw NasException('NAS の URL が未設定です');
    const q = {'api': 'SYNO.API.Info', 'version': '1', 'method': 'query', 'query': 'all'};
    Map<String, dynamic> info;
    try {
      info = await _postJson('$base/webapi/query.cgi', q, timeout: const Duration(seconds: 8));
    } on NasException {
      info = await _postJson('$base/webapi/entry.cgi', q, timeout: const Duration(seconds: 8));
    } on SocketException {
      throw NasException('NAS につながりません（Tailscale はつながっていますか？）');
    } on TimeoutException {
      throw NasException('NAS につながりません（Tailscale はつながっていますか？）');
    }
    _apis = info['data'] as Map<String, dynamic>?;
    if (_apis == null || !_apis!.containsKey('SYNO.API.Auth')) throw NasException('DSM の応答ではありません');
    if (settings.nasPassword.isEmpty) throw NasException('パスワード未設定');
    final did = settings.nasDeviceToken;
    final twoStep = _otp != null || did.isNotEmpty;
    final p = <String, String>{
      'api': 'SYNO.API.Auth',
      'version': '${_ver('SYNO.API.Auth', twoStep ? 6 : 3)}',
      'method': 'login',
      'account': settings.nasUser,
      'passwd': settings.nasPassword,
      'session': 'FileStation',
      'format': 'sid',
    };
    if (_otp != null) {
      p['otp_code'] = _otp!;
      p['enable_device_token'] = 'yes';
      p['device_name'] = 'ThetaPhotoHatch';
    } else if (did.isNotEmpty) {
      p['device_id'] = did;
      p['device_name'] = 'ThetaPhotoHatch';
    }
    _otp = null;
    final r = await _postJson(_url('SYNO.API.Auth'), p);
    if (r['success'] != true) {
      final code = (r['error'] as Map?)?['code'] as int? ?? 0;
      if (code == 403 || code == 406) {
        settings.nasDeviceToken = '';
        await settings.saveSecrets();
        throw NasOtpException('2 段階認証の確認コードを入れてください（1 回入れれば、この端末は次から要りません）', code);
      }
      if (code == 404) throw NasOtpException('確認コードが違います', code);
      throw NasException(switch (code) {
        400 => 'アカウントかパスワードが違います',
        401 => 'アカウントが無効です',
        402 => 'File Station を使う権限がありません',
        407 => 'ログインの失敗が続いたため、NAS が一時的に拒否しています',
        _ => 'ログインエラー $code',
      }, code);
    }
    final data = r['data'] as Map<String, dynamic>;
    _sid = data['sid'] as String;
    final newDid = (data['did'] ?? data['device_id'] ?? '') as String;
    if (newDid.isNotEmpty && newDid != settings.nasDeviceToken) {
      settings.nasDeviceToken = newDid;
      await settings.saveSecrets();
    }
  }

  /// API を呼ぶ。セッション切れ（105〜107・119）なら 1 回だけログインし直す
  Future<Map<String, dynamic>> call(String api, String method, Map<String, String> params, {int version = 2}) async {
    for (var attempt = 0; ; attempt++) {
      await ensureLogin();
      final p = {...params, 'api': api, 'version': '${_ver(api, version)}', 'method': method, '_sid': _sid!};
      final r = await _postJson(_url(api), p, timeout: const Duration(seconds: 60));
      if (r['success'] == true) return (r['data'] as Map<String, dynamic>?) ?? {};
      final code = (r['error'] as Map?)?['code'] as int? ?? 0;
      if (attempt == 0 && (code == 105 || code == 106 || code == 107 || code == 119)) {
        _sid = null;
        continue;
      }
      throw NasException('DSM エラー $code ($api.$method)', code);
    }
  }

  /// NAS 上のファイルの大きさ（無ければ null）
  Future<int?> size(String path) async {
    try {
      final d = await call('SYNO.FileStation.List', 'getinfo', {
        'path': jsonEncode([path]),
        'additional': jsonEncode(['size']),
      });
      final files = (d['files'] as List?) ?? [];
      if (files.isEmpty) return null;
      final f = files.first as Map<String, dynamic>;
      if (f['code'] != null) return null; // 408：無い
      return ((f['additional'] as Map?)?['size'] as num?)?.toInt();
    } on NasException catch (e) {
      if (e.code == 408) return null;
      rethrow;
    }
  }

  /// dir（`/photo/2026/2026-10-29 布引ハーブ園`）へ file を上げる。フォルダは作る。同じ名前は上書き
  Future<void> upload(String dir, File file, {String? name}) async {
    for (var attempt = 0; ; attempt++) {
      await ensureLogin();
      final api = 'SYNO.FileStation.Upload';
      final uri = Uri.parse(_url(api))
          .replace(queryParameters: {'api': api, 'version': '${_ver(api, 2)}', 'method': 'upload', '_sid': _sid!});
      final req = http.MultipartRequest('POST', uri)
        ..fields['path'] = dir
        ..fields['create_parents'] = 'true'
        ..fields['overwrite'] = 'true'
        ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: name ?? file.uri.pathSegments.last));
      final res = await _c.send(req).timeout(const Duration(minutes: 30));
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200) throw NasException('アップロード HTTP ${res.statusCode}');
      final r = jsonDecode(body) as Map<String, dynamic>;
      if (r['success'] == true) return;
      final code = (r['error'] as Map?)?['code'] as int? ?? 0;
      if (attempt == 0 && (code == 105 || code == 106 || code == 107 || code == 119)) {
        _sid = null;
        continue;
      }
      throw NasException(switch (code) {
        1800 || 1801 || 1802 => 'アップロードが途中で切れました',
        1803 || 1804 => 'NAS の空きが足りません（または上限を超えました）',
        407 || 105 => 'このフォルダに書き込む権限がありません（$dir）',
        _ => 'アップロードのエラー $code',
      }, code);
    }
  }
}
