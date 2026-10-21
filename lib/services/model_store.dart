import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/managed_model.dart';

/// 模型管理：每个站点的模型别名 / 启停 / 分组 / 排序，本机持久化。
class ModelStore extends ChangeNotifier {
  static const _prefsKey = 'managed_models_v1';

  // siteId -> models（已按 sort 排好）
  final Map<String, List<ManagedModel>> _models = {};
  bool _loaded = false;

  bool get loaded => _loaded;

  List<ManagedModel> list(String siteId) =>
      List.unmodifiable(_models[siteId] ?? const []);

  /// 启用的模型 id 集合（无记录时视为全部启用）。
  Set<String> enabledIds(String siteId) {
    final list = _models[siteId];
    if (list == null || list.isEmpty) return const {};
    return list.where((m) => m.enabled).map((m) => m.id).toSet();
  }

  /// 该模型是否可用（无管理记录时默认可用）。
  bool isEnabled(String siteId, String modelId) {
    final list = _models[siteId];
    if (list == null) return true;
    for (final m in list) {
      if (m.id == modelId) return m.enabled;
    }
    return true;
  }

  String displayName(String siteId, String modelId) {
    final list = _models[siteId];
    if (list == null) return modelId;
    for (final m in list) {
      if (m.id == modelId) return m.displayName;
    }
    return modelId;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _models.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((siteId, list) {
          if (list is List) {
            _models[siteId] = list
                .whereType<Map>()
                .map((e) =>
                    ManagedModel.fromJson(Map<String, dynamic>.from(e)))
                .where((m) => m.id.isNotEmpty)
                .toList();
            _sort(siteId);
          }
        });
      } catch (_) {}
    }
    _loaded = true;
    notifyListeners();
  }

  /// 用刚拉取到的 id 列表同步：新增补入，存活更新 lastSeen。
  /// 返回新增数量。
  Future<int> sync(String siteId, List<String> ids) async {
    final list = _models.putIfAbsent(siteId, () => []);
    final existing = {for (final m in list) m.id: m};
    var added = 0;
    var maxSort = list.isEmpty
        ? 0
        : list.map((m) => m.sort).reduce((a, b) => a > b ? a : b);
    final now = DateTime.now();
    for (final id in ids) {
      final m = existing[id];
      if (m == null) {
        maxSort += 1;
        list.add(ManagedModel(id: id, sort: maxSort, lastSeen: now));
        added++;
      } else {
        m.lastSeen = now;
      }
    }
    _sort(siteId);
    await _persist();
    return added;
  }

  /// 清理：删除不在 ids 中的模型（如下线模型）。返回删除数量。
  Future<int> cleanup(String siteId, List<String> ids) async {
    final list = _models[siteId];
    if (list == null) return 0;
    final keep = ids.toSet();
    final before = list.length;
    list.removeWhere((m) => !keep.contains(m.id));
    await _persist();
    return before - list.length;
  }

  Future<void> setAlias(String siteId, String id, String alias) async {
    _find(siteId, id)?.alias = alias.trim();
    await _persist();
  }

  Future<void> setEnabled(String siteId, String id, bool enabled) async {
    _find(siteId, id)?.enabled = enabled;
    await _persist();
  }

  Future<void> setGroup(String siteId, String id, String group) async {
    _find(siteId, id)?.group = group.trim();
    await _persist();
  }

  /// 拖拽排序后按新顺序重写 sort。
  Future<void> reorder(String siteId, List<String> orderedIds) async {
    final list = _models[siteId];
    if (list == null) return;
    final byId = {for (final m in list) m.id: m};
    var i = 0;
    for (final id in orderedIds) {
      final m = byId[id];
      if (m != null) m.sort = ++i;
    }
    _sort(siteId);
    await _persist();
  }

  Future<void> removeSite(String siteId) async {
    _models.remove(siteId);
    await _persist();
  }

  ManagedModel? _find(String siteId, String id) {
    final list = _models[siteId];
    if (list == null) return null;
    for (final m in list) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _sort(String siteId) {
    _models[siteId]?.sort((a, b) {
      final c = a.sort.compareTo(b.sort);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_models.map(
          (k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()))),
    );
    notifyListeners();
  }
}
