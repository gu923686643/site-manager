import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/site.dart';

/// 站点仓库：CRUD + 持久化。
///
/// 普通字段 -> SharedPreferences；apiKey / cookie -> flutter_secure_storage。
/// 内存里同时缓存一份，避免每次读盘。
class SiteStore extends ChangeNotifier {
  static const _prefsKey = 'sites_v1';
  static const _secure = FlutterSecureStorage();

  final List<Site> _sites = [];
  final Map<String, String> _apiKeys = {};
  final Map<String, List<String>> _apiKeyLists = {};
  final Map<String, String> _cookies = {};
  bool _loaded = false;

  List<Site> get sites => List.unmodifiable(_sites);
  bool get loaded => _loaded;

  Site? byId(String id) {
    for (final s in _sites) {
      if (s.id == id) return s;
    }
    return null;
  }

  String apiKeyOf(String id) => _apiKeys[id] ?? '';
  String cookieOf(String id) => _cookies[id] ?? '';

  /// 该站点的全部 Key（首个为默认）。兼容老版本单 Key 数据：自动迁移。
  /// 首次调用前请先 await [loadApiKeys] 完成迁移。
  List<String> apiKeysOf(String id) =>
      List.unmodifiable(_apiKeyLists[id] ?? const []);

  Future<List<String>> loadApiKeys(String id) async {
    await _ensureKeyList(id);
    return apiKeysOf(id);
  }

  Future<void> _ensureKeyList(String id) async {
    if (_apiKeyLists.containsKey(id)) return;
    final raw = await _secure.read(key: _kApiKeys(id));
    List<String> list = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        list = (jsonDecode(raw) as List).map((e) => '$e').toList();
      } catch (_) {}
    }
    // 老版本单 Key 迁移
    final legacy = _apiKeys[id] ?? '';
    if (list.isEmpty && legacy.isNotEmpty) list = [legacy];
    _apiKeyLists[id] = list;
    if (list.isNotEmpty) {
      _apiKeys[id] = list.first;
      await _secure.write(key: _kApiKey(id), value: list.first);
    }
  }

  Future<void> _saveKeyList(String id) async {
    final list = _apiKeyLists[id] ?? [];
    await _secure.write(key: _kApiKeys(id), value: jsonEncode(list));
    final def = list.isEmpty ? '' : list.first;
    _apiKeys[id] = def;
    await _secure.write(key: _kApiKey(id), value: def);
    notifyListeners();
  }

  Future<void> addApiKey(String id, String key) async {
    key = key.trim();
    if (key.isEmpty) return;
    await _ensureKeyList(id);
    final list = _apiKeyLists[id]!;
    if (list.contains(key)) return;
    list.add(key);
    await _saveKeyList(id);
  }

  Future<void> removeApiKey(String id, int index) async {
    await _ensureKeyList(id);
    final list = _apiKeyLists[id]!;
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _saveKeyList(id);
  }

  /// 把第 index 个 Key 设为默认。
  Future<void> setDefaultApiKey(String id, int index) async {
    await _ensureKeyList(id);
    final list = _apiKeyLists[id]!;
    if (index <= 0 || index >= list.length) return;
    final k = list.removeAt(index);
    list.insert(0, k);
    await _saveKeyList(id);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _sites.clear();
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List;
      for (final e in list) {
        try {
          _sites.add(Site.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {
          // 单条损坏不影响整体
        }
      }
    }
    for (final s in _sites) {
      _apiKeys[s.id] = await _secure.read(key: _kApiKey(s.id)) ?? '';
      _cookies[s.id] = await _secure.read(key: _kCookie(s.id)) ?? '';
      _refreshTokens[s.id] =
          await _secure.read(key: _kRefresh(s.id)) ?? '';
      _webHosts[s.id] = prefs.getString(_kWebHost(s.id)) ?? '';
      _loginPaths[s.id] = prefs.getString(_kLoginPath(s.id)) ?? '';
      _apiKeyLists.remove(s.id); // 懒加载，首次访问时迁移
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(Site site, {String apiKey = '', String cookie = ''}) async {
    _sites.add(site);
    _apiKeys[site.id] = apiKey;
    _cookies[site.id] = cookie;
    _refreshTokens[site.id] = '';
    _webHosts[site.id] = '';
    _loginPaths[site.id] = '';
    await _secure.write(key: _kApiKey(site.id), value: apiKey);
    await _secure.write(key: _kCookie(site.id), value: cookie);
    await _persist();
  }

  Future<void> update(Site site, {String? apiKey, String? cookie}) async {
    final i = _sites.indexWhere((e) => e.id == site.id);
    if (i < 0) return;
    _sites[i] = site;
    if (apiKey != null) {
      _apiKeys[site.id] = apiKey;
      await _secure.write(key: _kApiKey(site.id), value: apiKey);
    }
    if (cookie != null) {
      _cookies[site.id] = cookie;
      await _secure.write(key: _kCookie(site.id), value: cookie);
    }
    await _persist();
  }

  Future<void> remove(String id) async {
    _sites.removeWhere((e) => e.id == id);
    _apiKeys.remove(id);
    _apiKeyLists.remove(id);
    _cookies.remove(id);
    _refreshTokens.remove(id);
    _webHosts.remove(id);
    _loginPaths.remove(id);
    await _secure.delete(key: _kApiKey(id));
    await _secure.delete(key: _kApiKeys(id));
    await _secure.delete(key: _kCookie(id));
    await _secure.delete(key: _kRefresh(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWebHost(id));
    await prefs.remove(_kLoginPath(id));
    await _persist();
  }

  Future<void> setCookie(String id, String cookie) async {
    _cookies[id] = cookie;
    await _secure.write(key: _kCookie(id), value: cookie);
    notifyListeners();
  }

  Future<void> clearCookie(String id) => setCookie(id, '');

  /// 新版 NewAPI 的刷新令牌（new_api_refresh，Path=/api/user/auth 的 HttpOnly
  /// Cookie，用它换 access_token 走 Bearer 鉴权）。同样敏感，进安全存储。
  final Map<String, String> _refreshTokens = {};
  String refreshTokenOf(String id) => _refreshTokens[id] ?? '';

  Future<void> setRefreshToken(String id, String token) async {
    _refreshTokens[id] = token;
    await _secure.write(key: _kRefresh(id), value: token);
    notifyListeners();
  }

  Future<void> clearRefreshToken(String id) => setRefreshToken(id, '');

  /// 记录用户实际完成网页登录的 host（可能与站点配置域名不一致，
  /// 如网页控制台独立域名）。后续静默同步时一并扫描该 host。
  final Map<String, String> _webHosts = {};
  String webHostOf(String id) => _webHosts[id] ?? '';

  Future<void> loadWebHosts() async {
    final prefs = await SharedPreferences.getInstance();
    for (final s in _sites) {
      _webHosts[s.id] = prefs.getString(_kWebHost(s.id)) ?? '';
    }
  }

  Future<void> setWebHost(String id, String host) async {
    _webHosts[id] = host;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWebHost(id), host);
  }

  /// 记住本站真正可用的登录页路径：新版 NewAPI 前端是 /sign-in、
  /// 经典前端是 /login，写错路径轻则 404、重则连接被关（ERR_CONNECTION_CLOSED）。
  /// 网页登录时探明后存下来，下次直接打开对的那个。
  final Map<String, String> _loginPaths = {};
  String loginPathOf(String id) => _loginPaths[id] ?? '';

  Future<void> setLoginPath(String id, String path) async {
    if (_loginPaths[id] == path) return;
    _loginPaths[id] = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLoginPath(id), path);
  }

  /// 启停 / 收藏切换。
  Future<void> toggleEnabled(String id) async {
    final s = byId(id);
    if (s == null) return;
    s.enabled = !s.enabled;
    await _persist();
  }

  Future<void> toggleFavorite(String id) async {
    final s = byId(id);
    if (s == null) return;
    s.favorite = !s.favorite;
    await _persist();
  }

  Future<void> toggleHidden(String id) async {
    final s = byId(id);
    if (s == null) return;
    s.hidden = !s.hidden;
    await _persist();
  }

  /// 按规范化地址查找重复站点（排除自身）。
  Site? findDuplicate(String baseUrl, {String? excludeId}) {
    final norm = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    for (final s in _sites) {
      if (s.id == excludeId) continue;
      if (s.normalizedBaseUrl.toLowerCase() == norm.toLowerCase()) {
        return s;
      }
    }
    return null;
  }

  /// 记录一次签到结果。
  Future<void> recordCheckin(String id, String result) async {
    final s = byId(id);
    if (s == null) return;
    s.lastCheckinAt = DateTime.now();
    s.lastCheckinResult = result;
    await _persist();
  }

  /// 所有标签（去重排序），用于筛选器。
  List<String> allTags() {
    final set = <String>{};
    for (final s in _sites) {
      set.addAll(s.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_sites.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  static String _kApiKey(String id) => 'site_apikey_$id';
  static String _kApiKeys(String id) => 'site_apikeys_$id';
  static String _kCookie(String id) => 'site_cookie_$id';
  static String _kRefresh(String id) => 'site_refresh_$id';
  static String _kWebHost(String id) => 'site_webhost_$id';
  static String _kLoginPath(String id) => 'site_loginpath_$id';
}
