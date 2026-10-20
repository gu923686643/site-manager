import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../services/chat_store.dart';
import '../services/site_store.dart';
import 'chat_screen.dart';

/// 某站点的会话列表。
class ChatListScreen extends StatelessWidget {
  final String siteId;
  const ChatListScreen({super.key, required this.siteId});

  @override
  Widget build(BuildContext context) {
    final siteStore = context.watch<SiteStore>();
    final chatStore = context.watch<ChatStore>();
    final site = siteStore.byId(siteId);
    if (site == null) {
      return const Scaffold(body: Center(child: Text('站点已删除')));
    }
    final convs = chatStore.forSite(siteId);
    return Scaffold(
      appBar: AppBar(title: Text('${site.name} · 聊天')),
      body: convs.isEmpty
          ? const Center(
              child: Text('还没有会话，点右下角开始新的聊天',
                  style: TextStyle(color: Colors.grey)),
            )
          : ListView.separated(
              itemCount: convs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = convs[i];
                return Dismissible(
                  key: ValueKey(c.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red.shade400,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child:
                        const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async =>
                      await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('删除会话'),
                          content: Text('确定删除「${c.title}」吗？'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(d, false),
                                child: const Text('取消')),
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(d, true),
                                child: const Text('删除')),
                          ],
                        ),
                      ) ==
                      true,
                  onDismissed: (_) => chatStore.remove(c.id),
                  child: ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(c.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${c.model} · ${c.messages.length} 条消息',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      _date(c.updatedAt),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ChatScreen(conversationId: c.id),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newChat(context, chatStore),
        icon: const Icon(Icons.add),
        label: const Text('新会话'),
      ),
    );
  }

  Future<void> _newChat(BuildContext context, ChatStore chatStore) async {
    final model = await chatStore.lastModelFor(siteId);
    if (!context.mounted) return;
    final conv = Conversation(
      id: Conversation.newId(),
      siteId: siteId,
      model: model,
    );
    await chatStore.add(conv);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: conv.id),
      ),
    );
  }

  String _date(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}-${dt.day}';
  }
}
