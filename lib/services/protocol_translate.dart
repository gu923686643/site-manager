import 'dart:convert';

/// 协议转换：Claude Messages / OpenAI Responses  <->  OpenAI Chat Completions。
/// 网关的上游站点都是 OpenAI 兼容的，这里做双向翻译，让 Claude/Responses
/// 协议的客户端也能经网关调用。

String _textOf(dynamic content) {
  if (content is String) return content;
  if (content is List) {
    return content.whereType<Map>().where((b) {
      final t = '${b['type'] ?? 'text'}';
      return t == 'text' || t.endsWith('_text'); // input_text / output_text
    }).map((b) => '${b['text'] ?? ''}').where((t) => t.isNotEmpty).join('\n');
  }
  return '';
}

/// 取 choices 首个 Map 项，兼容各种泛型推断。
Map<String, dynamic> _firstChoice(Map<String, dynamic> resp) {
  final choices = resp['choices'];
  if (choices is List) {
    for (final c in choices) {
      if (c is Map) return Map<String, dynamic>.from(c);
    }
  }
  return {};
}

// ---------------------------------------------------------------------------
// Claude Messages
// ---------------------------------------------------------------------------

/// Claude 请求 -> OpenAI 请求。
Map<String, dynamic> claudeToOpenAI(Map<String, dynamic> req) {
  final messages = <Map<String, dynamic>>[];
  final system = req['system'];
  if (system is String && system.isNotEmpty) {
    messages.add({'role': 'system', 'content': system});
  } else if (system is List) {
    final text = _textOf(system);
    if (text.isNotEmpty) {
      messages.add({'role': 'system', 'content': text});
    }
  }
  for (final m in (req['messages'] as List? ?? [])) {
    if (m is! Map) continue;
    final role = '${m['role'] ?? 'user'}';
    messages.add({
      'role': role == 'assistant' ? 'assistant' : 'user',
      'content': _textOf(m['content']),
    });
  }
  return {
    'model': req['model'],
    'messages': messages,
    if (req['max_tokens'] != null) 'max_tokens': req['max_tokens'],
    if (req['temperature'] != null) 'temperature': req['temperature'],
    if (req['top_p'] != null) 'top_p': req['top_p'],
    if (req['stream'] == true) 'stream': true,
  };
}

/// OpenAI 非流式响应 -> Claude message 响应。
Map<String, dynamic> openAIToClaudeResponse(
    Map<String, dynamic> resp, String msgId) {
  final choice = _firstChoice(resp);
  final text = '${(choice['message'] as Map?)?['content'] ?? ''}';
  final finish = '${choice['finish_reason'] ?? 'stop'}';
  final usage = (resp['usage'] as Map?) ?? {};
  return {
    'id': msgId,
    'type': 'message',
    'role': 'assistant',
    'model': '${resp['model'] ?? ''}',
    'content': [
      {'type': 'text', 'text': text}
    ],
    'stop_reason': finish == 'length' ? 'max_tokens' : 'end_turn',
    'stop_sequence': null,
    'usage': {
      'input_tokens': (usage['prompt_tokens'] as int?) ?? 0,
      'output_tokens': (usage['completion_tokens'] as int?) ?? 0,
    },
  };
}

/// OpenAI SSE -> Claude SSE 的有状态转换器。
class ClaudeStreamTranslator {
  final String model;
  final String msgId;
  bool _started = false;
  int _inputTokens = 0;
  int _outputTokens = 0;
  String _stopReason = 'end_turn';

  ClaudeStreamTranslator({required this.model, required this.msgId});

  /// 输入上游 data 负载，返回下游 SSE 行（不含换行，空串表示空行）。
  List<String> translateData(String data) {
    if (data == '[DONE]') return _finish();
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return [];
    }
    final out = <String>[];
    final usage = json['usage'] as Map?;
    if (usage != null) {
      _inputTokens = (usage['prompt_tokens'] as int?) ?? _inputTokens;
      _outputTokens =
          (usage['completion_tokens'] as int?) ?? _outputTokens;
    }
    final choices = (json['choices'] as List?) ?? [];
    if (choices.isNotEmpty) {
      final choice = choices.first as Map;
      final delta = (choice['delta'] as Map?)?['content'];
      if (delta is String && delta.isNotEmpty) {
        out.addAll(_ensureStarted());
        out.add('event: content_block_delta');
        out.add('data: ${jsonEncode({
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': delta},
            })}');
        out.add('');
      }
      final finish = choice['finish_reason'];
      if (finish is String && finish.isNotEmpty) {
        _stopReason = finish == 'length' ? 'max_tokens' : 'end_turn';
      }
    }
    return out;
  }

  List<String> _ensureStarted() {
    if (_started) return [];
    _started = true;
    return [
      'event: message_start',
      'data: ${jsonEncode({
            'type': 'message_start',
            'message': {
              'id': msgId,
              'type': 'message',
              'role': 'assistant',
              'model': model,
              'content': [],
              'stop_reason': null,
              'stop_sequence': null,
              'usage': {'input_tokens': 0, 'output_tokens': 0},
            },
          })}',
      '',
      'event: content_block_start',
      'data: ${jsonEncode({
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': ''},
          })}',
      '',
      'event: ping',
      'data: ${jsonEncode({'type': 'ping'})}',
      '',
    ];
  }

  List<String> _finish() {
    final out = <String>[];
    out.addAll(_ensureStarted());
    out.addAll([
      'event: content_block_stop',
      'data: ${jsonEncode({'type': 'content_block_stop', 'index': 0})}',
      '',
      'event: message_delta',
      'data: ${jsonEncode({
            'type': 'message_delta',
            'delta': {'stop_reason': _stopReason, 'stop_sequence': null},
            'usage': {
              'input_tokens': _inputTokens,
              'output_tokens': _outputTokens
            },
          })}',
      '',
      'event: message_stop',
      'data: ${jsonEncode({'type': 'message_stop'})}',
      '',
    ]);
    return out;
  }
}

/// 上游 OpenAI 错误 -> Claude 错误格式。
Map<String, dynamic> openAIErrorToClaude(int status, String message) => {
      'type': 'error',
      'error': {
        'type': status == 401
            ? 'authentication_error'
            : status == 404
                ? 'not_found_error'
                : status == 429
                    ? 'rate_limit_error'
                    : 'api_error',
        'message': message,
      },
    };

// ---------------------------------------------------------------------------
// OpenAI Responses API
// ---------------------------------------------------------------------------

/// Responses 请求 -> OpenAI 请求。
Map<String, dynamic> responsesToOpenAI(Map<String, dynamic> req) {
  final messages = <Map<String, dynamic>>[];
  final instructions = req['instructions'];
  if (instructions is String && instructions.isNotEmpty) {
    messages.add({'role': 'system', 'content': instructions});
  }
  final input = req['input'];
  if (input is String && input.isNotEmpty) {
    messages.add({'role': 'user', 'content': input});
  } else if (input is List) {
    for (final item in input) {
      if (item is! Map) continue;
      final type = '${item['type'] ?? 'message'}';
      if (type != 'message') continue;
      messages.add({
        'role': '${item['role'] ?? 'user'}',
        'content': _textOf(item['content']),
      });
    }
  }
  return {
    'model': req['model'],
    'messages': messages,
    if (req['max_output_tokens'] != null)
      'max_tokens': req['max_output_tokens'],
    if (req['temperature'] != null) 'temperature': req['temperature'],
    if (req['stream'] == true) 'stream': true,
  };
}

/// OpenAI 非流式响应 -> Responses 对象。
Map<String, dynamic> openAIToResponsesResponse(
    Map<String, dynamic> resp, String respId) {
  final choice = _firstChoice(resp);
  final text = '${(choice['message'] as Map?)?['content'] ?? ''}';
  final usage = (resp['usage'] as Map?) ?? {};
  final pt = (usage['prompt_tokens'] as int?) ?? 0;
  final ct = (usage['completion_tokens'] as int?) ?? 0;
  return {
    'id': respId,
    'object': 'response',
    'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'model': '${resp['model'] ?? ''}',
    'status': 'completed',
    'output': [
      {
        'type': 'message',
        'id': '${respId}_msg',
        'status': 'completed',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': text, 'annotations': []},
        ],
      }
    ],
    'usage': {
      'input_tokens': pt,
      'output_tokens': ct,
      'total_tokens': pt + ct,
    },
  };
}

/// OpenAI SSE -> Responses SSE 的有状态转换器。
class ResponsesStreamTranslator {
  final String model;
  final String respId;
  final String itemId;
  bool _started = false;
  int _inputTokens = 0;
  int _outputTokens = 0;

  ResponsesStreamTranslator({required this.model, required this.respId})
      : itemId = '${respId}_msg';

  List<String> translateData(String data) {
    if (data == '[DONE]') return _finish();
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return [];
    }
    final out = <String>[];
    final usage = json['usage'] as Map?;
    if (usage != null) {
      _inputTokens = (usage['prompt_tokens'] as int?) ?? _inputTokens;
      _outputTokens =
          (usage['completion_tokens'] as int?) ?? _outputTokens;
    }
    final choices = (json['choices'] as List?) ?? [];
    if (choices.isNotEmpty) {
      final delta =
          (choices.first as Map)['delta'] as Map?;
      final text = delta?['content'];
      if (text is String && text.isNotEmpty) {
        out.addAll(_ensureStarted());
        out.add('event: response.output_text.delta');
        out.add('data: ${jsonEncode({
              'type': 'response.output_text.delta',
              'item_id': itemId,
              'output_index': 0,
              'content_index': 0,
              'delta': text,
            })}');
        out.add('');
      }
    }
    return out;
  }

  List<String> _ensureStarted() {
    if (_started) return [];
    _started = true;
    final base = {
      'id': respId,
      'object': 'response',
      'model': model,
      'status': 'in_progress',
    };
    return [
      'event: response.created',
      'data: ${jsonEncode({'type': 'response.created', 'response': base})}',
      '',
      'event: response.in_progress',
      'data: ${jsonEncode({'type': 'response.in_progress', 'response': base})}',
      '',
      'event: response.output_item.added',
      'data: ${jsonEncode({
            'type': 'response.output_item.added',
            'output_index': 0,
            'item': {
              'type': 'message',
              'id': itemId,
              'status': 'in_progress',
              'role': 'assistant',
              'content': [],
            },
          })}',
      '',
      'event: response.content_part.added',
      'data: ${jsonEncode({
            'type': 'response.content_part.added',
            'item_id': itemId,
            'output_index': 0,
            'content_index': 0,
            'part': {'type': 'output_text', 'text': '', 'annotations': []},
          })}',
      '',
    ];
  }

  List<String> _finish() {
    final out = <String>[];
    out.addAll(_ensureStarted());
    out.addAll([
      'event: response.output_text.done',
      'data: ${jsonEncode({
            'type': 'response.output_text.done',
            'item_id': itemId,
            'output_index': 0,
            'content_index': 0,
            'text': '',
          })}',
      '',
      'event: response.content_part.done',
      'data: ${jsonEncode({
            'type': 'response.content_part.done',
            'item_id': itemId,
            'output_index': 0,
            'content_index': 0,
            'part': {'type': 'output_text', 'text': '', 'annotations': []},
          })}',
      '',
      'event: response.output_item.done',
      'data: ${jsonEncode({
            'type': 'response.output_item.done',
            'output_index': 0,
            'item': {
              'type': 'message',
              'id': itemId,
              'status': 'completed',
              'role': 'assistant',
              'content': [],
            },
          })}',
      '',
      'event: response.completed',
      'data: ${jsonEncode({
            'type': 'response.completed',
            'response': {
              'id': respId,
              'object': 'response',
              'model': model,
              'status': 'completed',
              'usage': {
                'input_tokens': _inputTokens,
                'output_tokens': _outputTokens,
                'total_tokens': _inputTokens + _outputTokens,
              },
            },
          })}',
      '',
    ]);
    return out;
  }
}
