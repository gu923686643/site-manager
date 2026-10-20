import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/site.dart';
import '../services/site_client.dart';
import '../services/site_store.dart';

/// 新增 / 编辑站点。
class SiteEditScreen extends StatefulWidget {
  final Site? site;
  const SiteEditScreen({super.key, this.site});

  @override
  State<SiteEditScreen> createState() => _SiteEditScreenState();
}

class _SiteEditScreenState extends State<SiteEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _note;
  late final TextEditingController _tags;
  late SiteType _type;
  late bool _enabled;
  late bool _favorite;
  late bool _hidden;
  bool _obscureKey = true;
  bool _testing = false;
  String? _testMsg;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final s = widget.site;
    final store = context.read<SiteStore>();
    _name = TextEditingController(text: s?.name ?? '');
    _url = TextEditingController(text: s?.baseUrl ?? '');
    _key = TextEditingController(
        text: s == null ? '' : store.apiKeyOf(s.id));
    _note = TextEditingController(text: s?.note ?? '');
    _tags = TextEditingController(text: (s?.tags ?? []).join(', '));
    _type = s?.type ?? SiteType.newApi;
    _enabled = s?.enabled ?? true;
    _favorite = s?.favorite ?? false;
    _hidden = s?.hidden ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _key.dispose();
    _note.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.site != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? '编辑站点' : '添加站点')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：我的主站',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请填写名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: '站点地址',
                hintText: 'https://api.example.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return '请填写站点地址';
                final uri = Uri.tryParse(t);
                if (uri == null ||
                    !(uri.scheme == 'http' || uri.scheme == 'https') ||
                    uri.host.isEmpty) {
                  return '地址格式不正确';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SiteType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: '站点类型',
                border: OutlineInputBorder(),
              ),
              items: SiteType.values
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? SiteType.newApi),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _key,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API Key（sk- 开头）',
                hintText: '用于测连通、拉模型；只存本机',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureKey ? Icons.visibility : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: '标签（可选，逗号/空格分隔）',
                hintText: '如：主力, 便宜',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              title: const Text('启用站点'),
              subtitle: const Text('停用的站点不参与批量操作'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            SwitchListTile(
              title: const Text('收藏'),
              subtitle: const Text('收藏的站点在列表置顶'),
              value: _favorite,
              onChanged: (v) => setState(() => _favorite = v),
            ),
            SwitchListTile(
              title: const Text('隐藏'),
              subtitle: const Text('隐藏后默认不在列表显示'),
              value: _hidden,
              onChanged: (v) => setState(() => _hidden = v),
            ),
            const SizedBox(height: 16),
            if (_testMsg != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: (_testOk ? Colors.green : Colors.red)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_testMsg!),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _doTest,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find),
                    label: const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: Text(isEdit ? '保存' : '添加'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '查余额、签到需要网页登录态：保存后在详情页点"网页登录"，'
              '在内置浏览器登录站点即可，Cookie 只存本机。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doTest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_key.text.trim().isEmpty) {
      setState(() {
        _testOk = false;
        _testMsg = '请先填写 API Key 再测试';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testMsg = null;
    });
    final probe = Site(
      id: 'probe',
      name: _name.text.trim(),
      baseUrl: _url.text.trim(),
      type: _type,
    );
    final r = await SiteClient()
        .testConnection(probe, _key.text.trim());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = r.ok;
      _testMsg = r.ok ? '${r.message}（${r.modelCount} 个模型）' : r.message;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final store = context.read<SiteStore>();
    final existing = widget.site;
    // 重复站点识别：同地址（去末尾斜杠、忽略大小写）已存在则提醒
    final dup = store.findDuplicate(_url.text.trim(),
        excludeId: existing?.id);
    if (dup != null && mounted) {
      final goOn = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('检测到重复站点'),
          content: Text(
              '「${dup.name}」已使用相同地址：\n${dup.normalizedBaseUrl}\n\n仍要继续保存吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('仍要保存')),
          ],
        ),
      );
      if (goOn != true) return;
    }
    if (existing == null) {
      final site = Site(
        id: Site.newId(),
        name: _name.text.trim(),
        baseUrl: _url.text.trim(),
        type: _type,
        note: _note.text.trim(),
        enabled: _enabled,
        favorite: _favorite,
        hidden: _hidden,
        tags: Site.parseTags(_tags.text),
      );
      await store.add(site, apiKey: _key.text.trim());
    } else {
      existing.name = _name.text.trim();
      existing.baseUrl = _url.text.trim();
      existing.type = _type;
      existing.note = _note.text.trim();
      existing.enabled = _enabled;
      existing.favorite = _favorite;
      existing.hidden = _hidden;
      existing.tags = Site.parseTags(_tags.text);
      await store.update(existing, apiKey: _key.text.trim());
    }
    if (mounted) Navigator.of(context).pop();
  }
}
