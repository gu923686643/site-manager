import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation.dart';

/// 会话历史：本机 SharedPreferences 持久化，按更新时间倒序。
class ChatStore extends ChangeNotifier {
  static const _prefsKey = 'chat_conversations_v1';

  final List<Conversation> _convs = [];
  bool _loaded = false;

  bool get loaded => _loaded;
  List<Conversation> get conversations => List.unmodifiable(_convs);

  List<Conversation> forSite(String siteId) =>
      _convs.where((c) => c.siteId == siteId).toList();

  Conversation? byId(String id) {
    for (final c in _convs) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _convs.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          if (e is Map) {
            _convs.add(Conversation.fromJson(
                Map<String, dynamic>.from(e)));
          }
        }
      } catch (_) {}
    }
    _sort();
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(Conversation conv) async {
    _convs.add(conv);
    _sort();
    await _persist();
  }

  Future<void> remove(String id) async {
    _convs.removeWhere((c) => c.id == id);
    await _persist();
  }

  /// 消息变化后调用：更新排序并持久化。
  Future<void> touch(Conversation conv) async {
    conv.touch();
    _sort();
    await _persist();
  }

  /// 删除某站点的全部会话（站点删除时连带清理）。
  Future<void> removeForSite(String siteId) async {
    _convs.removeWhere((c) => c.siteId == siteId);
    await _persist();
  }

  /// 某站点上次使用的模型。
  Future<String> lastModelFor(String siteId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('chat_last_model_$siteId') ?? '';
  }

  Future<void> setLastModel(String siteId, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_last_model_$siteId', model);
  }

  void _sort() =>
      _convs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_convs.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }
}
