import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/site.dart';
import '../services/chat_store.dart';
import '../services/cookie_sync.dart';
import '../services/model_store.dart';
import '../services/site_client.dart';
import 'gateway_screen.dart';
import 'import_sites_screen.dart';
import 'linux_do_login_screen.dart';
import 'site_detail_screen.dart';
import 'site_edit_screen.dart';
import '../services/site_store.dart';

/// 站点列表：搜索 / 筛选 / 增删改 / 批量操作入口。
class SiteListScreen extends StatefulWidget {
  const SiteListScreen({super.key});

  @override
  State<SiteListScreen> createState() => _SiteListScreenState();
}

class _SiteListScreenState extends State<SiteListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _tagFilter; // null = 全部标签
  bool _onlyFavorite = false;
  bool _showDisabled = true;
  bool _showHidden = false;
  bool _batchRunning = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Site> _filtered(List<Site> sites) {
    final q = _query.trim().toLowerCase();
    var list = sites.where((s) {
      if (q.isNotEmpty &&
          !s.name.toLowerCase().contains(q) &&
          !s.baseUrl.toLowerCase().contains(q) &&
          !s.note.toLowerCase().contains(q)) {
        return false;
      }
      if (_tagFilter != null && !s.tags.contains(_tagFilter)) return false;
      if (_onlyFavorite && !s.favorite) return false;
      if (!_showDisabled && !s.enabled) return false;
      if (!_showHidden && s.hidden) return false;
      return true;
    }).toList();
    // 按存储顺序显示：新站点追加在末尾即添加顺序；
    // 用户拖拽调整后按调整后的顺序（收藏只做星标，不再置顶）。
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SiteStore>();
    final sites = _filtered(store.sites);
    final tags = store.allTags();
    return Scaffold(
      appBar: AppBar(
        title: const Text('站点管家'),
        actions: [
          IconButton(
            tooltip: 'L站登录（各站点"使用 Linux.do 登录"免重复验证）',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const LinuxDoLoginScreen()),
            ),
          ),
          IconButton(
            tooltip: '本地 API 网关',
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const GatewayScreen()),
            ),
          ),
          IconButton(
            tooltip: '批量操作',
            icon: const Icon(Icons.bolt_outlined),
            onPressed: _batchRunning ? null : () => _batchMenu(context),
          ),
          IconButton(
            tooltip: '导入站点（名称 + 地址）',
            icon: const Icon(Icons.playlist_add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ImportSitesScreen()),
            ),
          ),
          IconButton(
            tooltip: '关于与隐私',
            icon: const Icon(Icons.shield_outlined),
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: '搜索名称 / 地址 / 备注',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                if (tags.isNotEmpty || true)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('收藏'),
                          selected: _onlyFavorite,
                          onSelected: (v) =>
                              setState(() => _onlyFavorite = v),
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: const Text('含停用'),
                          selected: _showDisabled,
                          onSelected: (v) =>
                              setState(() => _showDisabled = v),
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: const Text('含隐藏'),
                          selected: _showHidden,
                          onSelected: (v) =>
                              setState(() => _showHidden = v),
                        ),
                        for (final t in tags) ...[
                          const SizedBox(width: 6),
                          FilterChip(
                            label: Text(t),
                            selected: _tagFilter == t,
                            onSelected: (v) => setState(
                                () => _tagFilter = v ? t : null),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Expanded(
                  child: store.sites.isEmpty
                      ? _emptyHint()
                      : sites.isEmpty
                          ? const Center(child: Text('没有符合筛选的站点'))
                          : RefreshIndicator(
                              onRefresh: () => store.load(),
                              child: ReorderableListView.builder(
                                buildDefaultDragHandles: false,
                                itemCount: sites.length,
                                onReorderItem: (oldIndex, newIndex) {
                                  // onReorderItem 的 newIndex 已是移除拖动项后的下标
                                  final moved = sites[oldIndex];
                                  // 在展示列表里找到拖动后的邻居，映射回全量列表
                                  // （筛选只做减法不改顺序，映射恒成立）
                                  final rest = sites
                                      .where((s) => s.id != moved.id)
                                      .toList();
                                  final beforeId = newIndex < rest.length
                                      ? rest[newIndex].id
                                      : null;
                                  store.moveSite(moved.id, beforeId);
                                },
                                itemBuilder: (context, i) => _siteTile(
                                    context, store, sites[i], i),
                              ),
                            ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SiteEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('添加站点'),
      ),
    );
  }

  Widget _siteTile(
      BuildContext context, SiteStore store, Site site, int index) {
    final hasKey = store.hasApiKey(site.id);
    final hasCookie = store.hasLogin(site.id);
    return Dismissible(
      key: ValueKey(site.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context, site),
      onDismissed: (_) {
        store.remove(site.id);
        // 连带清理该站点的聊天记录与模型管理记录
        context.read<ChatStore>().removeForSite(site.id);
        context.read<ModelStore>().removeSite(site.id);
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SiteDetailScreen(siteId: site.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _siteAvatar(context, site),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              site.name.isEmpty ? '(未命名)' : site.name,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (site.favorite)
                            const Icon(Icons.star,
                                size: 16, color: Colors.amber),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${site.type.label} · ${_shortUrl(site.baseUrl)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _statusChip(
                              context,
                              hasKey ? 'Key' : '无 Key',
                              hasKey),
                          _statusChip(
                              context,
                              hasCookie ? '已登录' : '未登录',
                              hasCookie),
                          _checkinChip(context, site),
                          if (site.manualCheckin)
                            _statusChip(context, '手动签到', false,
                                grey: true),
                          if (!site.enabled)
                            _statusChip(context, '停用', false,
                                grey: true),
                          if (site.hidden)
                            _statusChip(context, '隐藏', false,
                                grey: true),
                          ...site.tags.map((t) => Chip(
                                label: Text(t,
                                    style: const TextStyle(
                                        fontSize: 10)),
                                visualDensity:
                                    VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
                // 拖拽手柄：按住可调整顺序；空点击拦截，避免点手柄误进详情
                GestureDetector(
                  onTap: () {},
                  child: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Icon(Icons.drag_handle,
                          size: 20, color: Colors.grey),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  iconSize: 20,
                  onSelected: (v) =>
                      _tileAction(context, store, site, v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'toggle',
                        child: Text('启用 / 停用')),
                    const PopupMenuItem(
                        value: 'fav',
                        child: Text('收藏 / 取消收藏')),
                    PopupMenuItem(
                        value: 'hide',
                        child:
                            Text(site.hidden ? '取消隐藏' : '隐藏')),
                    const PopupMenuItem(
                        value: 'edit', child: Text('编辑')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 站点头像：按类型配色 + 首字 + 启用状态点。
  Widget _siteAvatar(BuildContext context, Site site) {
    final colors = {
      'newApi': Colors.teal,
      'oneApi': Colors.indigo,
      'sub2Api': Colors.deepOrange,
      'openAi': Colors.green,
    };
    final color =
        colors[site.type.name] ?? Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            site.name.isEmpty ? '?' : site.name[0],
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 18),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: site.enabled ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  /// 小状态徽标。
  Widget _statusChip(
      BuildContext context, String label, bool ok,
      {bool grey = false}) {
    final cs = Theme.of(context).colorScheme;
    final bg = grey
        ? cs.surfaceContainerHighest
        : ok
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.orange.withValues(alpha: 0.12);
    final fg = grey
        ? cs.onSurfaceVariant
        : ok
            ? Colors.green.shade700
            : Colors.orange.shade800;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: fg)),
    );
  }

  /// 签到徽标：只有当天的签到结果才显示「已签到/签到异常」；
  /// 过去的成功记录降级为灰色「上次 MM-DD」，避免跨天后误读为今日已签。
  Widget _checkinChip(BuildContext context, Site site) {
    switch (site.checkinBadge(DateTime.now())) {
      case CheckinBadge.checkedToday:
        return _statusChip(context, '已签到', true);
      case CheckinBadge.anomalyToday:
        return _statusChip(context, '签到异常', false);
      case CheckinBadge.lastChecked:
        return _statusChip(context, site.lastCheckinLabel, false, grey: true);
      case CheckinBadge.none:
        return const SizedBox.shrink();
    }
  }

  void _tileAction(
      BuildContext context, SiteStore store, Site site, String v) {
    switch (v) {
      case 'toggle':
        store.toggleEnabled(site.id);
        break;
      case 'fav':
        store.toggleFavorite(site.id);
        break;
      case 'hide':
        store.toggleHidden(site.id);
        break;
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SiteEditScreen(site: site)),
        );
        break;
    }
  }

  /// 批量操作菜单。
  Future<void> _batchMenu(BuildContext context) async {
    final store = context.read<SiteStore>();
    final enabled = store.sites.where((s) => s.enabled).toList();
    if (enabled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有启用的站点')),
      );
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('批量操作（${enabled.length} 个启用站点）'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'balance'),
            child: const ListTile(
              leading: Icon(Icons.account_balance_wallet_outlined),
              title: Text('批量刷新余额'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'checkin'),
            child: const ListTile(
              leading: Icon(Icons.event_available_outlined),
              title: Text('批量签到'),
              subtitle: Text('已签到的自动跳过'),
            ),
          ),
        ],
      ),
    );
    if (choice == 'balance' && mounted) {
      _batchBalance(enabled);
    } else if (choice == 'checkin' && mounted) {
      _batchCheckin(enabled);
    }
  }

  /// 批量操作前静默重同步该站的 WebView 会话 Cookie（防轮换过期）。
  /// 新版登录体系下同时同步刷新令牌。
  Future<void> _resyncSiteCookie(SiteStore store, Site s) async {
    try {
      if (!s.type.hasUserPanel) return;
      final siteHost = Uri.tryParse(s.normalizedBaseUrl)?.host ?? '';
      final hosts = <String>{
        ...CookieSync.relatedHosts(siteHost),
        ...CookieSync.relatedHosts(store.webHostOf(s.id)),
      }..removeWhere((h) => h.isEmpty);
      final refreshByHost = await CookieSync.collectRefreshCookies(hosts);
      final jarRefresh = refreshByHost.values.isNotEmpty
          ? refreshByHost.values.first
          : '';
      final oldRefresh = store.refreshTokenOf(s.id);
      if (jarRefresh.isNotEmpty && jarRefresh != oldRefresh) {
        await store.setRefreshToken(s.id, jarRefresh);
      }
      final old = store.cookieOf(s.id);
      if (old.isEmpty && oldRefresh.isEmpty && jarRefresh.isEmpty) return;
      final cookies = await CookieSync.collectCookies(hosts);
      if (!CookieSync.hasSessionCookie(cookies)) return;
      final header = CookieSync.toHeader(cookies);
      if (header != old) await store.setCookie(s.id, header);
    } catch (_) {}
  }

  Future<void> _persistRefreshToken(SiteStore store, String id, String v) async {
    try {
      await store.setRefreshToken(id, v);
    } catch (_) {}
  }

  /// 批量刷新余额：逐站执行并汇总结果；无余额接口的类型直接跳过。
  Future<void> _batchBalance(List<Site> sites) async {
    final store = context.read<SiteStore>();
    final client = SiteClient();
    final results = <_Row>[];
    setState(() => _batchRunning = true);
    try {
      for (final s in sites) {
        if (!s.type.hasUserPanel) {
          results.add(_Row(s.name, false, '已跳过：${s.type.label} 无余额接口',
              skipped: true));
          continue;
        }
        await _resyncSiteCookie(store, s);
        try {
          final b = await client.fetchBalance(
            s,
            cookie: store.cookieOf(s.id),
            apiKey: store.apiKeyOf(s.id),
            refreshToken: store.refreshTokenOf(s.id),
            onRefreshToken: (v) => _persistRefreshToken(store, s.id, v),
          );
          results.add(_Row(
              s.name, true, '剩余 \$${b.dollarsLeft.toStringAsFixed(2)}'));
        } on NeedWebLoginException {
          results.add(_Row(s.name, false, '待登录'));
        } catch (e) {
          results.add(_Row(s.name, false, '失败：$e'));
        }
        if (mounted) setState(() {});
      }
    } finally {
      client.close();
      if (mounted) setState(() => _batchRunning = false);
    }
    if (mounted) _showBatchResult('批量刷新余额', results);
  }

  /// 批量签到：逐站查询状态，未签到则执行，结果逐站记录。
  Future<void> _batchCheckin(List<Site> sites) async {
    final store = context.read<SiteStore>();
    final client = SiteClient();
    final results = <_Row>[];
    setState(() => _batchRunning = true);
    try {
      for (final s in sites) {
        if (!s.type.hasCheckin) {
          results.add(_Row(s.name, false, '已跳过：签到为 NewAPI 系功能',
              skipped: true));
          continue;
        }
        // 手动签到站点：批量不自动签，留给用户网页签完后手动确认。
        // 跳过不写签到记录，避免覆盖已有的签到状态（上次日期）。
        if (s.manualCheckin) {
          results.add(_Row(s.name, false, '需手动签到，已跳过',
              skipped: true));
          continue;
        }
        await _resyncSiteCookie(store, s);
        final cookie = store.cookieOf(s.id);
        if (cookie.isEmpty && store.refreshTokenOf(s.id).isEmpty) {
          results.add(_Row(s.name, false, '待登录，已跳过',
              skipped: true));
          continue;
        }
        try {
          final st = await client.checkinStatus(
            s,
            cookie,
            refreshToken: store.refreshTokenOf(s.id),
            onRefreshToken: (v) => _persistRefreshToken(store, s.id, v),
          );
          if (st.checkedIn) {
            results.add(_Row(s.name, true, '今日已签到'));
            await store.recordCheckin(s.id, '今日已签到');
            continue;
          }
          final r = await client.doCheckin(
            s,
            cookie,
            refreshToken: store.refreshTokenOf(s.id),
            onRefreshToken: (v) => _persistRefreshToken(store, s.id, v),
          );
          results.add(_Row(s.name, r.ok, r.message));
          // 记录文案统一：签到成功固定记「今日已签到」（与详情页一致），
          // 避免服务器原始消息不含「成功/已签到」时列表徽标误判为异常
          await store.recordCheckin(
              s.id, r.checkedIn ? '今日已签到' : r.message);
        } on NeedWebLoginException {
          results.add(_Row(s.name, false, '登录态失效'));
          await store.recordCheckin(s.id, '登录态失效');
        } catch (e) {
          results.add(_Row(s.name, false, '失败：$e'));
          await store.recordCheckin(s.id, '失败');
        }
        if (mounted) setState(() {});
      }
    } finally {
      client.close();
      if (mounted) setState(() => _batchRunning = false);
    }
    if (mounted) _showBatchResult('批量签到', results);
  }

  void _showBatchResult(String title, List<_Row> rows) {
    final done = rows.where((r) => !r.skipped).toList();
    final okCount = done.where((r) => r.ok).length;
    final skipCount = rows.length - done.length;
    final titleText = skipCount > 0
        ? '$title（$okCount/${done.length} 成功，$skipCount 个跳过）'
        : '$title（$okCount/${rows.length} 成功）';
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titleText),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              return ListTile(
                dense: true,
                leading: Icon(
                  r.skipped
                      ? Icons.remove_circle_outline
                      : (r.ok ? Icons.check_circle : Icons.error_outline),
                  color: r.skipped
                      ? Colors.grey
                      : (r.ok ? Colors.green : Colors.orange),
                  size: 20,
                ),
                title: Text(r.name,
                    style: const TextStyle(fontSize: 14)),
                subtitle:
                    Text(r.message, style: const TextStyle(fontSize: 12)),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              const Text('还没有站点', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              const Text(
                '添加你自己的 NewAPI / OneAPI / OpenAI 兼容站点。\n所有数据只保存在本机，只与你填写的站点通信。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Future<bool> _confirmDelete(BuildContext context, Site site) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除站点'),
        content:
            Text('确定删除「${site.name}」吗？本地保存的 Key 与登录态会一并清除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除')),
        ],
      ),
    );
    return r == true;
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('关于与隐私'),
        content: const SingleChildScrollView(
          child: Text(
            '站点管家 v0.2\n\n'
            '· 无账号体系，无激活，无服务端\n'
            '· 站点信息保存在本机；API Key 与网页登录 Cookie 存入系统安全存储\n'
            '· 所有网络请求只发往你填写的站点地址\n'
            '· 余额单位换算（500000 额度 = 1 美元）为估算值，仅供参考',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  String _shortUrl(String url) {
    var u = url.trim();
    u = u.replaceFirst(RegExp(r'^https?://'), '');
    if (u.length > 32) u = '${u.substring(0, 32)}…';
    return u;
  }
}

class _Row {
  final String name;
  final bool ok;
  final String message;
  final bool skipped;
  _Row(this.name, this.ok, this.message, {this.skipped = false});
}
