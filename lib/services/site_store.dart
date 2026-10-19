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
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(Site site, {String apiKey = '', String cookie = ''}) async {
    _sites.add(site);
    _apiKeys[site.id] = apiKey;
    _cookies[site.id] = cookie;
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
    _cookies.remove(id);
    await _secure.delete(key: _kApiKey(id));
    await _secure.delete(key: _kCookie(id));
    await _persist();
  }

  Future<void> setCookie(String id, String cookie) async {
    _cookies[id] = cookie;
    await _secure.write(key: _kCookie(id), value: cookie);
    notifyListeners();
  }

  Future<void> clearCookie(String id) => setCookie(id, '');

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
  static String _kCookie(String id) => 'site_cookie_$id';
}
