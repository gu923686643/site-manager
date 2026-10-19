import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../services/chat_client.dart';
import '../services/chat_store.dart';
import '../services/site_client.dart';
import '../services/site_store.dart';

/// 聊天界面：流式输出、模型选择、多 Key 切换。
class ChatScreen extends StatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatClient = ChatClient();
  final _siteClient = SiteClient();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  StreamSubscription<ChatStreamEvent>? _sub;
  bool _streaming = false;
  bool _autoScroll = true;
  String? _error;

  List<String> _models = [];
  bool _modelsLoading = false;
  List<String> _keys = [];
  int _keyIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      final cur = _scrollCtrl.position.pixels;
      _autoScroll = (max - cur) < 120;
    });
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _chatClient.close();
    _siteClient.close();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Conversation get _conv =>
      context.read<ChatStore>().byId(widget.conversationId)!;

  Future<void> _init() async {
    final siteStore = context.read<SiteStore>();
    final chatStore = context.read<ChatStore>();
    final conv = chatStore.byId(widget.conversationId);
    if (conv == null) return;
    final keys = await siteStore.loadApiKeys(conv.siteId);
    if (!mounted) return;
    setState(() => _keys = keys);
    if (conv.model.isEmpty) {
      final last = await chatStore.lastModelFor(conv.siteId);
      if (!mounted) return;
      if (last.isNotEmpty) {
        setState(() => _conv.model = last);
      }
    }
    _fetchModels(silent: true);
  }

  Future<void> _fetchModels({bool silent = false}) async {
    final siteStore = context.read<SiteStore>();
    final conv = _conv;
    final site = siteStore.byId(conv.siteId);
    if (site == null) return;
    final key = _keys.isEmpty ? '' : _keys[_keyIndex.clamp(0, _keys.length - 1)];
    if (key.isEmpty) {
      if (!silent) _snack('请先添加 API Key（右上角钥匙图标）');
      return;
    }
    if (!silent) setState(() => _modelsLoading = true);
    try {
      final list = await _siteClient.fetchModels(site, key);
      if (!mounted) return;
      setState(() {
        _models = list;
        _modelsLoading = false;
        if (conv.model.isEmpty && list.isNotEmpty) {
          conv.model = list.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _modelsLoading = false);
      if (!silent) _snack('拉取模型失败：$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _streaming) return;
    final chatStore = context.read<ChatStore>();
    final siteStore = context.read<SiteStore>();
    final conv = _conv;
    final site = siteStore.byId(conv.siteId);
    if (site == null) return;
    if (_keys.isEmpty) {
      _snack('请先添加 API Key（右上角钥匙图标）');
      return;
    }
    if (conv.model.isEmpty) {
      _snack('请先选择模型（顶部模型按钮）');
      await _pickModel();
      return;
    }
    final key = _keys[_keyIndex.clamp(0, _keys.length - 1)];

    setState(() {
      _error = null;
      _streaming = true;
      _autoScroll = true;
    });
    conv.messages.add(ChatMessage(role: 'user', content: text));
    final reply = ChatMessage(role: 'assistant', content: '');
    conv.messages.add(reply);
    _inputCtrl.clear();
    await chatStore.touch(conv);
    _scrollToBottom();

    _sub = _chatClient
        .streamChat(
      site: site,
      apiKey: key,
      model: conv.model,
      history: conv.messages.sublist(0, conv.messages.length - 1),
    )
        .listen(
      (e) {
        if (e.done) return;
        if (!mounted) return;
        setState(() => reply.content += e.delta);
        _scrollToBottom();
      },
      onError: (Object err) async {
        if (!mounted) return;
        // 出错时移除空回复，保留用户消息
        if (reply.content.isEmpty) conv.messages.remove(reply);
        setState(() {
          _streaming = false;
          _error = '$err';
        });
        await chatStore.touch(conv);
      },
      onDone: () async {
        if (!mounted) return;
        conv.refreshTitle();
        setState(() => _streaming = false);
        await chatStore.touch(conv);
        await chatStore.setLastModel(conv.siteId, conv.model);
      },
      cancelOnError: true,
    );
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    final chatStore = context.read<ChatStore>();
    final conv = _conv;
    conv.refreshTitle();
    setState(() => _streaming = false);
    await chatStore.touch(conv);
  }

  void _scrollToBottom() {
    if (!_autoScroll || !_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _pickModel() async {
    if (_models.isEmpty) await _fetchModels();
    if (!mounted) return;
    final conv = _conv;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('选择模型',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    tooltip: '刷新模型列表',
                    icon: _modelsLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    onPressed: () async {
                      Navigator.pop(c);
                      await _fetchModels();
                      if (mounted) _pickModel();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _models.isEmpty
                  ? const Center(
                      child: Text('暂无模型，请先拉取',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: _models.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final m = _models[i];
                        return ListTile(
                          dense: true,
                          title: Text(m,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 13)),
                          trailing: conv.model == m
                              ? const Icon(Icons.check,
                                  color: Colors.teal)
                              : IconButton(
                                  tooltip: '测试连通',
                                  icon: const Icon(Icons.bolt_outlined,
                                      size: 20),
                                  onPressed: () =>
                                      _testModel(c, m),
                                ),
                          onTap: () => Navigator.pop(c, m),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && picked != conv.model) {
      if (!mounted) return;
      final chatStore = context.read<ChatStore>();
      setState(() => conv.model = picked);
      await chatStore.touch(conv);
      await chatStore.setLastModel(conv.siteId, picked);
    }
  }

  Future<void> _testModel(BuildContext sheetCtx, String model) async {
    final siteStore = context.read<SiteStore>();
    final conv = _conv;
    final site = siteStore.byId(conv.siteId);
    if (site == null) return;
    final key = _keys.isEmpty ? '' : _keys[_keyIndex.clamp(0, _keys.length - 1)];
    _snack('正在测试 $model …');
    try {
      final r = await _chatClient.testModel(
          site: site, apiKey: key, model: model);
      _snack('$model：$r');
    } catch (e) {
      _snack('$model 测试失败：$e');
    }
  }

  Future<void> _manageKeys() async {
    final siteStore = context.read<SiteStore>();
    final conv = _conv;
    await showDialog(
      context: context,
      builder: (c) => _KeyDialog(
        siteId: conv.siteId,
        onChanged: () async {
          final keys = await siteStore.loadApiKeys(conv.siteId);
          if (mounted) {
            setState(() {
              _keys = keys;
              _keyIndex = _keyIndex.clamp(0, keys.length - 1);
            });
          }
        },
      ),
    );
    // 对话框关闭后同步默认 Key 下标
    final keys = await siteStore.loadApiKeys(conv.siteId);
    if (mounted) {
      setState(() {
        _keys = keys;
        _keyIndex = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conv = context.watch<ChatStore>().byId(widget.conversationId);
    if (conv == null) {
      return const Scaffold(body: Center(child: Text('会话已删除')));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(conv.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            onPressed: _streaming ? null : _pickModel,
            icon: const Icon(Icons.smart_toy_outlined, size: 18),
            label: Text(
              conv.model.isEmpty
                  ? '选模型'
                  : (conv.model.length > 14
                      ? '${conv.model.substring(0, 14)}…'
                      : conv.model),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: '管理 Key（${_keys.length} 个）',
            icon: const Icon(Icons.key_outlined),
            onPressed: _manageKeys,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: conv.messages.isEmpty
                ? const Center(
                    child: Text('输入消息开始聊天',
                        style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: conv.messages.length,
                    itemBuilder: (_, i) =>
                        _msgBubble(conv.messages[i]),
                  ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              child: Text(_error!,
                  style: TextStyle(
                      color: Colors.red.shade800, fontSize: 12)),
            ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _msgBubble(ChatMessage m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          m.content.isEmpty && !_streaming ? '…' : m.content,
          style: const TextStyle(fontSize: 14, height: 1.45),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                decoration: const InputDecoration(
                  hintText: '输入消息…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                enabled: !_streaming,
              ),
            ),
            const SizedBox(width: 8),
            _streaming
                ? IconButton.filled(
                    tooltip: '停止',
                    icon: const Icon(Icons.stop),
                    onPressed: _stop,
                  )
                : IconButton.filled(
                    tooltip: '发送',
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
          ],
        ),
      ),
    );
  }
}

/// Key 管理对话框：列表 / 添加 / 删除 / 设为默认。
class _KeyDialog extends StatefulWidget {
  final String siteId;
  final Future<void> Function() onChanged;
  const _KeyDialog({required this.siteId, required this.onChanged});

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  final _keyCtrl = TextEditingController();
  List<String> _keys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final store = context.read<SiteStore>();
    final keys = await store.loadApiKeys(widget.siteId);
    if (!mounted) return;
    setState(() {
      _keys = keys;
      _loading = false;
    });
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<SiteStore>();
    return AlertDialog(
      title: const Text('管理 API Key'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else if (_keys.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('暂无 Key，请添加',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _keys.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final k = _keys[i];
                    return ListTile(
                      dense: true,
                      title: Text(_mask(k),
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12)),
                      subtitle: i == 0
                          ? const Text('默认',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.teal))
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i != 0)
                            IconButton(
                              tooltip: '设为默认',
                              icon: const Icon(
                                  Icons.push_pin_outlined,
                                  size: 20),
                              onPressed: () async {
                                await store.setDefaultApiKey(
                                    widget.siteId, i);
                                _reload();
                              },
                            ),
                          IconButton(
                            tooltip: '删除',
                            icon: const Icon(
                                Icons.delete_outline,
                                size: 20),
                            onPressed: () async {
                              await store.removeApiKey(
                                  widget.siteId, i);
                              _reload();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keyCtrl,
                    decoration: const InputDecoration(
                      hintText: '粘贴新的 API Key',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: '添加',
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    final v = _keyCtrl.text.trim();
                    if (v.isEmpty) return;
                    await store.addApiKey(widget.siteId, v);
                    _keyCtrl.clear();
                    _reload();
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Key 存入系统安全存储，仅本机使用',
                style:
                    TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }

  String _mask(String k) {
    if (k.length <= 12) return '***';
    return '${k.substring(0, 7)}…${k.substring(k.length - 4)}';
  }
}
