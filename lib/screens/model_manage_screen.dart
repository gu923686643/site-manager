import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/managed_model.dart';
import '../models/site.dart';
import '../services/model_store.dart';
import '../services/site_client.dart';
import '../services/site_store.dart';

/// 模型管理：别名 / 启停 / 分组 / 排序 / 清理下线模型。
class ModelManageScreen extends StatefulWidget {
  final String siteId;
  const ModelManageScreen({super.key, required this.siteId});

  @override
  State<ModelManageScreen> createState() => _ModelManageScreenState();
}

class _ModelManageScreenState extends State<ModelManageScreen> {
  final _siteClient = SiteClient();
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _groupFilter = ''; // 空 = 全部
  bool _busy = false;

  @override
  void dispose() {
    _siteClient.close();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 从站点重新拉取并同步。
  Future<void> _sync() async {
    final siteStore = context.read<SiteStore>();
    final modelStore = context.read<ModelStore>();
    final site = siteStore.byId(widget.siteId);
    if (site == null) return;
    final key = siteStore.apiKeyOf(site.id);
    if (key.isEmpty) {
      _snack('该站点没有 API Key');
      return;
    }
    setState(() => _busy = true);
    try {
      final ids = await _siteClient.fetchModels(site, key);
      final added = await modelStore.sync(site.id, ids);
      _snack('同步完成，共 ${ids.length} 个模型，新增 $added 个');
    } catch (e) {
      _snack('同步失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 清理下线模型：先拉取最新列表，删除不在其中的。
  Future<void> _cleanup() async {
    final siteStore = context.read<SiteStore>();
    final modelStore = context.read<ModelStore>();
    final site = siteStore.byId(widget.siteId);
    if (site == null) return;
    final key = siteStore.apiKeyOf(site.id);
    if (key.isEmpty) {
      _snack('该站点没有 API Key');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清理下线模型'),
        content: const Text('将删除服务器上已不存在的模型记录（含其别名/分组设置），继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('清理')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final ids = await _siteClient.fetchModels(site, key);
      final removed = await modelStore.cleanup(site.id, ids);
      _snack('清理完成，删除 $removed 个下线模型');
    } catch (e) {
      _snack('清理失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(ManagedModel m) async {
    final modelStore = context.read<ModelStore>();
    final aliasCtrl = TextEditingController(text: m.alias);
    final groupCtrl = TextEditingController(text: m.group);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(m.id,
            style:
                const TextStyle(fontFamily: 'monospace', fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: aliasCtrl,
              decoration: const InputDecoration(
                labelText: '别名（空则显示原名）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: groupCtrl,
              decoration: const InputDecoration(
                labelText: '分组（空为未分组）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('保存')),
        ],
      ),
    );
    aliasCtrl.dispose();
    groupCtrl.dispose();
    if (ok == true) {
      await modelStore.setAlias(widget.siteId, m.id, aliasCtrl.text);
      await modelStore.setGroup(widget.siteId, m.id, groupCtrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = context.watch<SiteStore>().byId(widget.siteId);
    final modelStore = context.watch<ModelStore>();
    if (site == null) {
      return const Scaffold(body: Center(child: Text('站点已删除')));
    }
    final all = modelStore.list(site.id);
    final groups =
        all.map((m) => m.group).where((g) => g.isNotEmpty).toSet().toList()
          ..sort();
    final q = _query.toLowerCase();
    final filtered = all.where((m) {
      if (_groupFilter.isNotEmpty && m.group != _groupFilter) return false;
      if (q.isEmpty) return true;
      return m.id.toLowerCase().contains(q) ||
          m.displayName.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${site.name} · 模型管理'),
        actions: [
          IconButton(
            tooltip: '从站点同步',
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            onPressed: _busy ? null : _sync,
          ),
          IconButton(
            tooltip: '清理下线模型',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: _busy ? null : _cleanup,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: '搜索模型 id / 别名',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (groups.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _groupChip('', '全部'),
                  ...groups.map((g) => _groupChip(g, g)),
                ],
              ),
            ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text(
                  '共 ${all.length} 个，启用 ${all.where((m) => m.enabled).length} 个',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),
                const Text('长按拖拽排序',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Expanded(
            child: all.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('还没有模型记录',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _busy ? null : _sync,
                          icon: const Icon(Icons.sync),
                          label: const Text('从站点同步'),
                        ),
                      ],
                    ),
                  )
                : _query.isNotEmpty || _groupFilter.isNotEmpty
                    ? _plainList(site, filtered)
                    : _reorderList(site, filtered),
          ),
        ],
      ),
    );
  }

  Widget _groupChip(String value, String label) {
    final selected = _groupFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) =>
            setState(() => _groupFilter = value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// 搜索/过滤时用普通列表（排序无意义）。
  Widget _plainList(Site site, List<ManagedModel> models) {
    return ListView.separated(
      itemCount: models.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _row(site, models[i]),
    );
  }

  /// 默认用可拖拽排序列表。
  Widget _reorderList(Site site, List<ManagedModel> models) {
    return ReorderableListView.builder(
      itemCount: models.length,
      onReorderItem: (oldI, newI) async {
        final ids = models.map((m) => m.id).toList();
        final id = ids.removeAt(oldI);
        ids.insert(newI, id);
        await context
            .read<ModelStore>()
            .reorder(site.id, ids);
      },
      itemBuilder: (_, i) {
        final m = models[i];
        return _row(site, m, key: ValueKey(m.id));
      },
    );
  }

  Widget _row(Site site, ManagedModel m, {Key? key}) {
    final modelStore = context.read<ModelStore>();
    return ListTile(
      key: key,
      dense: true,
      title: Text(
        m.displayName,
        style: TextStyle(
          fontSize: 14,
          color: m.enabled ? null : Colors.grey,
          decoration:
              m.enabled ? null : TextDecoration.lineThrough,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.alias.isNotEmpty)
            Text(m.id,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 11)),
          if (m.group.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(m.group,
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.teal.shade800)),
            ),
        ],
      ),
      trailing: Switch(
        value: m.enabled,
        onChanged: (v) =>
            modelStore.setEnabled(site.id, m.id, v),
      ),
      onTap: () => _edit(m),
    );
  }
}
