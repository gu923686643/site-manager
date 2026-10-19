import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/gateway_service.dart';
import '../services/site_store.dart';

/// 本地 API 网关：启停、配置、日志。
class GatewayScreen extends StatefulWidget {
  const GatewayScreen({super.key});

  @override
  State<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends State<GatewayScreen> {
  final _portCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _portCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggle(GatewayService gw) async {
    final siteStore = context.read<SiteStore>();
    setState(() => _busy = true);
    try {
      if (gw.running) {
        await gw.stop();
      } else {
        final port = int.tryParse(_portCtrl.text.trim());
        if (port != null) await gw.saveConfig(port: port);
        await gw.start(siteStore);
        _snack('网关已启动');
      }
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gw = context.watch<GatewayService>();
    if (_portCtrl.text.isEmpty) {
      _portCtrl.text = '${gw.port}';
    }
    final enabledCount =
        context.watch<SiteStore>().sites.where((s) => s.enabled).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地 API 网关'),
        actions: [
          IconButton(
            tooltip: '清空日志',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => gw.clearLogs(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: gw.running
                ? Colors.green.shade50
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        gw.running
                            ? Icons.cloud_done
                            : Icons.cloud_off_outlined,
                        color: gw.running ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        gw.running ? '运行中' : '已停止',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _toggle(gw),
                        icon: Icon(
                            gw.running ? Icons.stop : Icons.play_arrow),
                        label:
                            Text(gw.running ? '停止' : '启动'),
                      ),
                    ],
                  ),
                  if (gw.running) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      'http://${gw.listenAddress == '0.0.0.0' ? '<本机局域网IP>' : '127.0.0.1'}:${gw.actualPort}',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'OpenAI 兼容：GET /v1/models，POST /v1/chat/completions（支持流式）',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text('可用站点 $enabledCount 个（仅启用的站点参与路由）',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ],
                ],
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
                  const Text('配置',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _portCtrl,
                          enabled: !gw.running,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '端口',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SwitchListTile(
                          title: const Text('局域网监听',
                              style: TextStyle(fontSize: 13)),
                          subtitle: const Text('关闭则仅本机可连',
                              style: TextStyle(fontSize: 11)),
                          value: gw.bindLan,
                          onChanged: gw.running
                              ? null
                              : (v) => gw.saveConfig(bindLan: v),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          gw.apiKey.isEmpty
                              ? '未生成密钥'
                              : _mask(gw.apiKey),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13),
                        ),
                      ),
                      IconButton(
                        tooltip: '复制密钥',
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: gw.apiKey.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(
                                    text: gw.apiKey));
                                _snack('密钥已复制');
                              },
                      ),
                      IconButton(
                        tooltip: '重新生成密钥',
                        icon:
                            const Icon(Icons.refresh, size: 20),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title:
                                  const Text('重新生成密钥'),
                              content: const Text(
                                  '旧密钥立即失效，已配置的客户端需更新。继续吗？'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(c, false),
                                    child:
                                        const Text('取消')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(c, true),
                                    child:
                                        const Text('重新生成')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await gw.regenerateKey();
                            _snack('新密钥已生成');
                          }
                        },
                      ),
                    ],
                  ),
                  const Text('调用时 Header：Authorization: Bearer <密钥>',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('请求日志',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${gw.logs.length} 条',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          if (gw.logs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text('暂无请求',
                        style: TextStyle(color: Colors.grey))),
              ),
            )
          else
            ...gw.logs.map(_logTile),
        ],
      ),
    );
  }

  Widget _logTile(GatewayLog l) {
    final ok = l.status >= 200 && l.status < 300;
    final dt = l.time;
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    final tokens = (l.promptTokens + l.completionTokens) > 0
        ? ' · ${(l.promptTokens + l.completionTokens)} tokens'
        : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(
          ok ? Icons.check_circle : Icons.error,
          color: ok ? Colors.green : Colors.red,
          size: 20,
        ),
        title: Text(
          '${l.model.isEmpty ? '?' : l.model} → ${l.siteName}',
          style:
              const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$time · ${l.stream ? '流式' : '非流式'} · ${l.status} · ${l.ms}ms$tokens${l.error != null ? '\n${l.error}' : ''}',
          style: const TextStyle(fontSize: 11),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _mask(String k) {
    if (k.length <= 12) return '***';
    return '${k.substring(0, 10)}…${k.substring(k.length - 4)}';
  }
}
