import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/conversation.dart';
import '../models/site.dart';

/// 聊天流事件。
class ChatStreamEvent {
  final String delta; // 本次增量文本（空表示结束）
  final bool done;
  const ChatStreamEvent(this.delta, {this.done = false});
}

/// OpenAI 兼容的流式聊天客户端：POST /v1/chat/completions（stream=true），解析 SSE。
///
/// 只与 [Site.baseUrl] 通信。调用方负责 cancel 订阅以中断流。
class ChatClient {
  static const timeout = Duration(seconds: 30);
  final http.Client _http;

  ChatClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  void close() => _http.close();

  /// 流式发送消息。message 插入历史末尾。
  Stream<ChatStreamEvent> streamChat({
    required Site site,
    required String apiKey,
    required String model,
    required List<ChatMessage> history,
    ChatMessage? systemPrompt,
    double temperature = 0.7,
  }) async* {
    final messages = <Map<String, String>>[
      if (systemPrompt != null) systemPrompt.toApiJson(),
      ...history.map((m) => m.toApiJson()),
    ];
    final req = http.Request(
      'POST',
      Uri.parse('${site.normalizedBaseUrl}/v1/chat/completions'),
    );
    req.headers.addAll({
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Authorization': 'Bearer $apiKey',
      'User-Agent': 'SiteManager/0.2',
    });
    req.body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'stream': true,
    });

    http.StreamedResponse resp;
    try {
      resp = await _http.send(req).timeout(timeout);
    } on TimeoutException {
      throw Exception('连接超时');
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw Exception('API Key 无效或无权限（HTTP ${resp.statusCode}）');
    }
    if (resp.statusCode == 404) {
      throw Exception('站点不支持 /v1/chat/completions（HTTP 404）');
    }
    if (resp.statusCode != 200) {
      final body = await resp.stream.bytesToString();
      throw Exception('HTTP ${resp.statusCode}：${_shortBody(body)}');
    }

    yield* _parseSse(resp.stream);
  }

  /// 非流式发送（用于模型连通性测试）。
  Future<String> testModel({
    required Site site,
    required String apiKey,
    required String model,
  }) async {
    final resp = await _http
        .post(
          Uri.parse('${site.normalizedBaseUrl}/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
            'User-Agent': 'SiteManager/0.2',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ],
            'max_tokens': 8,
            'stream': false,
          }),
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}：${_shortBody(resp.body)}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = body['choices'] as List?;
    final content =
        (choices?.isNotEmpty == true) ? choices![0]['message']['content'] : null;
    return '${content ?? ''}'.trim().isEmpty ? '连通正常（无返回文本）' : '连通正常';
  }

  /// 解析 SSE 流，产出增量文本。
  Stream<ChatStreamEvent> _parseSse(Stream<List<int>> bytes) async* {
    await for (final chunk
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      final line = chunk.trim();
      if (line.isEmpty) continue;
      // SSE 注释行（以 : 开头）忽略
      if (line.startsWith(':')) continue;
      final data = line.startsWith('data:')
          ? line.substring(5).trim()
          : line;
      if (data == '[DONE]') break;
      if (data.isEmpty) continue;
      Map<String, dynamic>? json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final delta = parseDelta(json);
      if (delta.isNotEmpty) {
        yield ChatStreamEvent(delta);
      }
      // 有些实现用 finish_reason 标记结束
      final choices = json['choices'] as List?;
      if (choices?.isNotEmpty == true) {
        final fr = choices![0]['finish_reason'];
        if (fr != null && fr != 'null' && '$fr'.isNotEmpty) {
          // 继续读完剩余缓冲后由 [DONE] 或流结束收尾
        }
      }
    }
    yield const ChatStreamEvent('', done: true);
  }

  /// 从单个 SSE data JSON 提取增量文本（兼容多种实现）。
  static String parseDelta(Map<String, dynamic> json) {
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) return '';
    final first = choices[0];
    if (first is! Map) return '';
    // 标准 OpenAI：choices[0].delta.content
    final delta = first['delta'];
    if (delta is Map && delta['content'] is String) {
      return delta['content'] as String;
    }
    // 兼容：choices[0].message.content / choices[0].text
    final message = first['message'];
    if (message is Map && message['content'] is String) {
      return message['content'] as String;
    }
    if (first['text'] is String) return first['text'] as String;
    return '';
  }

  String _shortBody(String body) {
    final b = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    return b.length > 160 ? '${b.substring(0, 160)}…' : b;
  }
}
