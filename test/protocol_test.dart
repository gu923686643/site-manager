import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_manager/services/gateway_service.dart';
import 'package:site_manager/services/model_store.dart';
import 'package:site_manager/services/protocol_translate.dart';
import 'package:site_manager/services/site_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  group('Claude -> OpenAI', () {
    test('system 字符串与消息块', () {
      final o = claudeToOpenAI({
        'model': 'gpt-4o',
        'system': '你是助手',
        'max_tokens': 100,
        'temperature': 0.5,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '你好'},
              {'type': 'image', 'source': {}}, // 非文本块忽略
            ]
          },
          {
            'role': 'assistant',
            'content': '您好'
          },
        ],
      });
      expect(o['model'], 'gpt-4o');
      expect(o['max_tokens'], 100);
      expect(o['temperature'], 0.5);
      final msgs = o['messages'] as List;
      expect(msgs.length, 3);
      expect(msgs[0], {'role': 'system', 'content': '你是助手'});
      expect(msgs[1]['content'], '你好');
      expect(msgs[2]['role'], 'assistant');
    });

    test('stream 透传', () {
      final o = claudeToOpenAI({
        'model': 'm',
        'messages': [],
        'stream': true,
      });
      expect(o['stream'], true);
    });
  });

  group('OpenAI -> Claude 响应', () {
    test('标准映射', () {
      final c = openAIToClaudeResponse({
        'id': 'chatcmpl-1',
        'model': 'gpt-4o',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'hi'},
            'finish_reason': 'stop',
          }
        ],
        'usage': {'prompt_tokens': 5, 'completion_tokens': 3},
      }, 'msg_1');
      expect(c['id'], 'msg_1');
      expect(c['type'], 'message');
      expect((c['content'] as List).first['text'], 'hi');
      expect(c['stop_reason'], 'end_turn');
      expect((c['usage'] as Map)['input_tokens'], 5);
      expect((c['usage'] as Map)['output_tokens'], 3);
    });

    test('length 映射为 max_tokens', () {
      final c = openAIToClaudeResponse({
        'choices': [
          {
            'message': {'content': 'x'},
            'finish_reason': 'length'
          }
        ],
      }, 'msg_2');
      expect(c['stop_reason'], 'max_tokens');
    });
  });

  group('ClaudeStreamTranslator', () {
    test('事件序列：start -> delta -> stop', () {
      final t = ClaudeStreamTranslator(model: 'gpt-4o', msgId: 'msg_9');
      final lines = <String>[];
      lines.addAll(t.translateData(jsonEncode({
        'choices': [
          {
            'delta': {'content': '你'},
            'finish_reason': null
          }
        ]
      })));
      lines.addAll(t.translateData(jsonEncode({
        'choices': [
          {
            'delta': {'content': '好'},
            'finish_reason': 'stop'
          }
        ]
      })));
      lines.addAll(t.translateData('[DONE]'));

      final text = lines.join('\n');
      expect(text.contains('event: message_start'), true);
      expect(text.contains('event: content_block_start'), true);
      expect(text.contains('event: content_block_delta'), true);
      expect(text.contains('event: content_block_stop'), true);
      expect(text.contains('event: message_delta'), true);
      expect(text.contains('event: message_stop'), true);
      // delta 内容在事件里
      expect(text.contains('你'), true);
      expect(text.contains('好'), true);
      // message_start 只出现一次
      expect('event: message_start'.allMatches(text).length, 1);
    });

    test('usage 嗅探进 message_delta', () {
      final t = ClaudeStreamTranslator(model: 'm', msgId: 'msg_u');
      final lines = t.translateData(jsonEncode({
        'choices': [],
        'usage': {'prompt_tokens': 7, 'completion_tokens': 9},
      }));
      lines.addAll(t.translateData('[DONE]'));
      final text = lines.join('\n');
      expect(text.contains('"input_tokens":7'), true);
      expect(text.contains('"output_tokens":9'), true);
    });
  });

  group('Responses -> OpenAI', () {
    test('字符串 input 与 instructions', () {
      final o = responsesToOpenAI({
        'model': 'gpt-4o',
        'instructions': '简洁回答',
        'input': '今天天气？',
        'max_output_tokens': 50,
      });
      final msgs = o['messages'] as List;
      expect(msgs[0], {'role': 'system', 'content': '简洁回答'});
      expect(msgs[1], {'role': 'user', 'content': '今天天气？'});
      expect(o['max_tokens'], 50);
    });

    test('input 消息数组', () {
      final o = responsesToOpenAI({
        'model': 'm',
        'input': [
          {
            'type': 'message',
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': 'hi'}
            ]
          },
        ],
      });
      final msgs = o['messages'] as List;
      expect(msgs.length, 1);
      expect(msgs[0]['content'], 'hi');
    });
  });

  group('OpenAI -> Responses', () {
    test('响应结构', () {
      final r = openAIToResponsesResponse({
        'model': 'gpt-4o',
        'choices': [
          {
            'message': {'content': 'done'},
            'finish_reason': 'stop'
          }
        ],
        'usage': {'prompt_tokens': 4, 'completion_tokens': 2},
      }, 'resp_1');
      expect(r['object'], 'response');
      expect(r['status'], 'completed');
      final out = (r['output'] as List).first as Map;
      expect(out['type'], 'message');
      final content = (out['content'] as List).first as Map;
      expect(content['type'], 'output_text');
      expect(content['text'], 'done');
      expect((r['usage'] as Map)['total_tokens'], 6);
    });

    test('流式事件序列', () {
      final t =
          ResponsesStreamTranslator(model: 'm', respId: 'resp_9');
      final lines = <String>[];
      lines.addAll(t.translateData(jsonEncode({
        'choices': [
          {
            'delta': {'content': 'ok'},
            'finish_reason': null
          }
        ]
      })));
      lines.addAll(t.translateData('[DONE]'));
      final text = lines.join('\n');
      expect(text.contains('event: response.created'), true);
      expect(
          text.contains('event: response.output_text.delta'), true);
      expect(text.contains('event: response.completed'), true);
      expect(text.contains('ok'), true);
    });
  });

  group('ModelStore', () {
    test('sync 新增与排序', () async {
      final s = ModelStore();
      await s.load();
      final added = await s.sync('ms_sync', ['b', 'a', 'c']);
      expect(added, 3);
      final list = s.list('ms_sync');
      expect(list.map((m) => m.id).toList(), ['b', 'a', 'c']);
      // 再次同步不重复
      final added2 = await s.sync('ms_sync', ['a', 'b', 'c', 'd']);
      expect(added2, 1);
      expect(s.list('ms_sync').length, 4);
    });

    test('别名/启停/分组', () async {
      final s = ModelStore();
      await s.load();
      await s.sync('ms_meta', ['m1']);
      await s.setAlias('ms_meta', 'm1', '主力');
      await s.setGroup('ms_meta', 'm1', '常用');
      await s.setEnabled('ms_meta', 'm1', false);
      final m = s.list('ms_meta').first;
      expect(m.displayName, '主力');
      expect(m.group, '常用');
      expect(m.enabled, false);
      expect(s.isEnabled('ms_meta', 'm1'), false);
      expect(s.isEnabled('ms_meta', 'unknown'), true); // 无记录默认可用
      expect(s.displayName('ms_meta', 'm1'), '主力');
    });

    test('reorder 与 cleanup', () async {
      final s = ModelStore();
      await s.load();
      await s.sync('ms_reorder', ['a', 'b', 'c']);
      await s.reorder('ms_reorder', ['c', 'a', 'b']);
      expect(s.list('ms_reorder').map((m) => m.id).toList(), ['c', 'a', 'b']);
      final removed = await s.cleanup('ms_reorder', ['a', 'c']);
      expect(removed, 1);
      expect(s.list('ms_reorder').map((m) => m.id).toList(), ['c', 'a']);
    });
  });

  group('网关多协议路由', () {
    test('/v1/messages 未知模型返回 Claude 错误格式', () async {
      final gw = GatewayService();
      await gw.load();
      await gw.regenerateKey();
      // 用正确 key 重建 handler（regenerateKey 后 key 已变，这里直接用新 key）
      final key = gw.apiKey;
      final r = await gw.buildHandler(SiteStore())(Request(
        'POST',
        Uri.parse('http://localhost/v1/messages'),
        headers: {'Authorization': 'Bearer $key'},
        body: jsonEncode({
          'model': 'nope',
          'max_tokens': 10,
          'messages': [
            {'role': 'user', 'content': 'hi'}
          ],
        }),
      ));
      expect(r.statusCode, 404);
      final body = jsonDecode(await r.readAsString());
      expect(body['type'], 'error');
      expect(body['error']['type'], 'not_found_error');
      expect(gw.logs.any((l) => l.status == 404), true);
    });

    test('/v1/responses 未知模型返回 404', () async {
      final gw = GatewayService();
      await gw.load();
      final key = await gw.regenerateKey();
      final r = await gw.buildHandler(SiteStore())(Request(
        'POST',
        Uri.parse('http://localhost/v1/responses'),
        headers: {'Authorization': 'Bearer $key'},
        body: jsonEncode({'model': 'nope', 'input': 'hi'}),
      ));
      expect(r.statusCode, 404);
    });

    test('/v1/messages 缺 model 返回 400', () async {
      final gw = GatewayService();
      await gw.load();
      final key = await gw.regenerateKey();
      final r = await gw.buildHandler(SiteStore())(Request(
        'POST',
        Uri.parse('http://localhost/v1/messages'),
        headers: {'Authorization': 'Bearer $key'},
        body: jsonEncode({'messages': []}),
      ));
      expect(r.statusCode, 400);
      final body = jsonDecode(await r.readAsString());
      expect(body['type'], 'error');
    });
  });
}
