/// 聊天消息。
class ChatMessage {
  final String role; // user / assistant / system
  String content;
  final DateTime createdAt;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: (json['role'] ?? 'user') as String,
        content: (json['content'] ?? '') as String,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String),
      );

  /// 发给 /v1/chat/completions 的格式。
  Map<String, String> toApiJson() => {'role': role, 'content': content};
}

/// 一次会话：归属某个站点，绑定模型，含消息列表。
class Conversation {
  final String id;
  final String siteId;
  String model;
  String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  DateTime updatedAt;

  Conversation({
    required this.id,
    required this.siteId,
    required this.model,
    this.title = '新会话',
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static String newId() =>
      'c${DateTime.now().microsecondsSinceEpoch}';

  /// 用首条用户消息生成标题（截断）。
  void refreshTitle() {
    final first = messages.firstWhere(
      (m) => m.role == 'user' && m.content.trim().isNotEmpty,
      orElse: () => ChatMessage(role: 'user', content: ''),
    );
    final t = first.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isNotEmpty) {
      title = t.length > 24 ? '${t.substring(0, 24)}…' : t;
    }
  }

  void touch() => updatedAt = DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'siteId': siteId,
        'model': model,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        siteId: (json['siteId'] ?? '') as String,
        model: (json['model'] ?? '') as String,
        title: (json['title'] ?? '新会话') as String,
        messages: ((json['messages'] as List?) ?? [])
            .whereType<Map>()
            .map((m) => ChatMessage.fromJson(
                Map<String, dynamic>.from(m)))
            .toList(),
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String),
        updatedAt: DateTime.tryParse((json['updatedAt'] ?? '') as String),
      );
}
