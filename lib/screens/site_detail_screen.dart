import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/site.dart';
import '../services/site_client.dart';
import '../services/site_store.dart';
import 'chat_list_screen.dart';
import 'site_edit_screen.dart';
import 'web_login_screen.dart';

/// 站点详情：概览 / 模型 / 签到 三个页签。
class SiteDetailScreen extends StatefulWidget {
  final String siteId;
  const SiteDetailScreen({super.key, required this.siteId});

  @override
  State<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends State<SiteDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _client = SiteClient();

  bool _busy = false;
  BalanceInfo? _balance;
  String? _balanceErr;
  List<String> _models = [];
  String? _modelsErr;
  String _modelFilter = '';
  CheckinInfo? _checkin;
  String? _checkinErr;
  String _notice = '';
  List<UsageLog> _usageLogs = [];
  String? _usageErr;
  String? _loginState;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _refreshBalance(silent: true);
    _fetchNotice(silent: true);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _client.close();
    super.dispose();
  }

  Site get _site => context.read<SiteStore>().byId(widget.siteId)!;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _refreshBalance({bool silent = false}) async {
    final store = context.read<SiteStore>();
    final site = store.byId(widget.siteId);
    if (site == null) return;
    if (!silent) setState(() => _busy = true);
    try {
      final b = await _client.fetchBalance(
        site,
        cookie: store.cookieOf(site.id),
        apiKey: store.apiKeyOf(site.id),
      );
      if (!mounted) return;
      setState(() {
        _balance = b;
        _balanceErr = null;
      });
    } on NeedWebLoginException catch (e) {
      if (!mounted) return;
      setState(() {
        _balance = null;
        _balanceErr = e.message;
      });
      if (!silent) _askWebLogin(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _balance = null;
        _balanceErr = '查询失败：$e';
      });
    } finally {
      if (!silent && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshModels() async {
    final store = context.read<SiteStore>();
    final site = store.byId(widget.siteId);
    if (site == null) return;
    final key = store.apiKeyOf(site.id);
    if (key.isEmpty) {
      _snack('请先在编辑页填写 API Key');
      return;
    }
    setState(() => _busy = true);
    try {
      final list = await _client.fetchModels(site, key);
      if (!mounted) return;
      setState(() {
        _models = list;
        _modelsErr = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelsErr = '拉取失败：$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshCheckin() async {
    final store = context.read<SiteStore>();
    final site = store.byId(widget.siteId);
    if (site == null) return;
    setState(() => _busy = true);
    try {
      final s = await _client.checkinStatus(site, store.cookieOf(site.id));
      if (!mounted) return;
      setState(() {
        _checkin = s;
        _checkinErr = null;
      });
    } on NeedWebLoginException catch (e) {
      if (!mounted) return;
      setState(() {
        _checkin = null;
        _checkinErr = e.message;
      });
      _askWebLogin(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkin = null;
        _checkinErr = '查询失败：$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doCheckin() async {
    final store = context.read<SiteStore>();
    final site = store.byId(widget.siteId);
    if (site == null) return;
    setState(() => _busy = true);
    try {
      final r = await _client.doCheckin(site, store.cookieOf(site.id));
      if (!mounted) return;
      setState(() {
        _checkin = r;
        _checkinErr = null;
      });
      await store.recordCheckin(site.id, r.message);
      _snack(r.message);
      if (r.ok) _refreshBalance(silent: true);
    } on NeedWebLoginException catch (e) {
      if (!mounted) return;
      _askWebLogin(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkinErr = '签到失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 拉取站点公告（公开接口，失败时静默）。
  Future<void> _fetchNotice({bool silent = false}) async {
    final store = context.read<SiteStore>();
    final site = store.byId(widget.siteId);
    if (site == null || !site.type.hasUserPanel) return;
    try {
      final n = await _client.fetchNotice(site);
      if (!mounted) return;
      setState(() => _notice = n);
    } catch (_) {
      if (!silent && mounted) _snack('公告获取失败');
    }
  }

  /// 用量明细（NewAPI 系）。
  Future<void> _refreshUsage({bool silent = false}) async {
    final store = context.read<SiteStore>();
    final site = store.byId(widget.siteId);
    if (site == null || !site.type.hasUserPanel) return;
    if (!silent) setState(() => _busy = true);
    try {
      final logs = await _client.fetchUserLogs(
        site,
        cookie: store.cookieOf(site.id),
        apiKey: store.apiKeyOf(site.id),
      );
      if (!mounted) return;
      setState(() {
        _usageLogs = logs;
        _usageErr = null;
      });
    } on NeedWebLoginException catch (e) {
      if (!mounted) return;
      setState(() {
        _usageLogs = [];
        _usageErr = e.message;
      });
      if (!silent) _askWebLogin(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _usageLogs = [];
        _usageErr = '查询失败：$e';
      });
    } finally {
      if (!silent && mounted) setState(() => _busy = false);
    }
  }

  /// 登录状态检查：有用户面板的验 cookie，其余验 API Key。
  Future<void> _checkLogin() async {
    final store = context.read<SiteStore>();
    final site = store.byId(widget.siteId);
    if (site == null) return;
    setState(() => _busy = true);
    try {
      if (site.type.hasUserPanel) {
        await _client.fetchBalance(site,
            cookie: store.cookieOf(site.id), apiKey: '');
      } else {
        final key = store.apiKeyOf(site.id);
        if (key.isEmpty) throw Exception('未填写 API Key');
        await _client.fetchModels(site, key);
      }
      if (!mounted) return;
      setState(() => _loginState = '有效');
      _snack('登录态有效');
    } on NeedWebLoginException catch (e) {
      if (!mounted) return;
      setState(() => _loginState = '已失效');
      _askWebLogin(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loginState = '异常');
      _snack('检查失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _askWebLogin(String reason) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('需要网页登录'),
        content: Text('$reason\n\n将在内置浏览器打开站点登录页，登录成功后自动保存登录态（只存本机）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('稍后')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('去登录')),
        ],
      ),
    );
    if (go == true && mounted) _openWebLogin();
  }

  Future<void> _openWebLogin() async {
    final site = _site;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WebLoginScreen(site: site)),
    );
    if (ok == true && mounted) {
      _snack('已保存网页登录态');
      _refreshBalance(silent: true);
      _refreshCheckin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SiteStore>();
    final site = store.byId(widget.siteId);
    if (site == null) {
      return const Scaffold(body: Center(child: Text('站点已删除')));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(site.name),
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SiteEditScreen(site: site)),
            ),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: '概览', icon: Icon(Icons.dashboard_outlined)),
            Tab(text: '模型', icon: Icon(Icons.smart_toy_outlined)),
            Tab(text: '用量', icon: Icon(Icons.receipt_long_outlined)),
            Tab(text: '签到', icon: Icon(Icons.event_available_outlined)),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: [
              _overviewTab(site),
              _modelsTab(),
              _usageTab(),
              _checkinTab(),
            ],
          ),
          if (_busy)
            const Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _overviewTab(Site site) {
    final store = context.read<SiteStore>();
    return RefreshIndicator(
      onRefresh: () => _refreshBalance(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_notice.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.campaign_outlined, size: 18),
                        const SizedBox(width: 6),
                        const Text('站点公告',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        InkWell(
                          onTap: () => _fetchNotice(),
                          child: const Icon(Icons.refresh, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_notice),
                  ],
                ),
              ),
            ),
          if (_notice.isNotEmpty) const SizedBox(height: 12),
          if (site.type.hasUserPanel)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined),
                        const SizedBox(width: 8),
                        const Text('余额',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        TextButton(
                          onPressed: _busy ? null : () => _refreshBalance(),
                          child: const Text('刷新'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_balance != null) ...[
                      _kv('用户名', _balance!.username),
                      _kv('剩余额度', '${_balance!.quota - _balance!.usedQuota}'),
                      _kv('已用额度', '${_balance!.usedQuota}'),
                      _kv('约合美元',
                          '\$${_balance!.dollarsLeft.toStringAsFixed(2)}（估算）'),
                    ] else
                      Text(_balanceErr ?? '下拉刷新查看余额',
                          style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '该站点类型不提供余额接口（仅 NewAPI / OneAPI 有 /api/user/self）。模型列表与连通性不受影响。',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('站点信息',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _kv('类型', site.type.label),
                  _kv('地址', site.normalizedBaseUrl),
                  _kv('API Key',
                      store.apiKeyOf(site.id).isEmpty ? '未填写' : '已填写（安全存储）'),
                  _kv('网页登录',
                      store.cookieOf(site.id).isEmpty ? '未登录' : '已登录（安全存储）'),
                  if (_loginState != null) _kv('登录态', _loginState!),
                  if (site.note.isNotEmpty) _kv('备注', site.note),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _openWebLogin,
                icon: const Icon(Icons.web),
                label: const Text('网页登录'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatListScreen(siteId: site.id),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('聊天'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _checkLogin,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('检查登录态'),
              ),
              if (store.cookieOf(site.id).isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () async {
                    await store.clearCookie(site.id);
                    _snack('已清除网页登录态');
                    setState(() {
                      _balance = null;
                      _checkin = null;
                    });
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('退出网页登录'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modelsTab() {
    final filtered = _modelFilter.isEmpty
        ? _models
        : _models
            .where((m) =>
                m.toLowerCase().contains(_modelFilter.toLowerCase()))
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '搜索模型',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _modelFilter = v),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _busy ? null : _refreshModels,
                child: const Text('拉取'),
              ),
            ],
          ),
        ),
        if (_modelsErr != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_modelsErr!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: _models.isEmpty && _modelsErr == null
              ? const Center(child: Text('点"拉取"获取模型列表'))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.smart_toy_outlined, size: 20),
                    title: Text(filtered[i],
                        style: const TextStyle(fontFamily: 'monospace')),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _usageTab() {
    final site = _site;
    if (!site.type.hasUserPanel) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '用量明细为 NewAPI / OneAPI 站点功能，\n当前站点类型不支持。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _refreshUsage(),
      child: _usageLogs.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(32),
              children: [
                Center(
                  child: Text(
                      _usageErr ?? '下拉加载最近 20 条用量记录',
                      style: TextStyle(
                          color: _usageErr == null
                              ? Colors.grey
                              : Colors.red)),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _usageLogs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final l = _usageLogs[i];
                final dt = l.dateTime;
                final time =
                    '${dt.month}-${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: l.type == 2
                        ? Colors.orange.shade100
                        : Colors.green.shade100,
                    child: Text(l.typeLabel[0],
                        style: const TextStyle(fontSize: 12)),
                  ),
                  title: Text(
                    l.modelName.isEmpty ? l.typeLabel : l.modelName,
                    style: const TextStyle(
                        fontSize: 13, fontFamily: 'monospace'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${l.typeLabel} · $time${l.content.isNotEmpty ? ' · ${l.content}' : ''}',
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    '\$${l.dollars.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              },
            ),
    );
  }

  Widget _checkinTab() {
    final site = _site;
    if (!site.type.hasCheckin) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '签到为 NewAPI 系站点功能，\n当前站点类型不支持。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshCheckin,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('每日签到',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_checkin != null) ...[
                    Row(
                      children: [
                        Icon(
                          _checkin!.checkedIn
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: _checkin!.checkedIn
                              ? Colors.green
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_checkin!.message)),
                      ],
                    ),
                  ] else
                    Text(_checkinErr ?? '下拉查询今日签到状态',
                        style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (_busy || (_checkin?.checkedIn == true))
                        ? null
                        : _doCheckin,
                    icon: const Icon(Icons.event_available),
                    label: const Text('签到'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '说明：通过站点官方签到接口执行；若站点开启了人机验证，'
                    '会自动提示你去网页手动完成。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 80,
                child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
