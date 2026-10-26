import 'package:flutter_test/flutter_test.dart';
import 'package:site_manager/models/conversation.dart';
import 'package:site_manager/services/chat_client.dart';

void main() {
  group('ChatClient.parseDelta', () {
    test('标准 OpenAI delta', () {
      expect(
        ChatClient.parseDelta({
          'choices': [
            {
              'delta': {'content': '你好'},
              'finish_reason': null,
            }
          ]
        }),
        '你好',
      );
    });

    test('空 delta 返回空串', () {
      expect(
        ChatClient.parseDelta({
          'choices': [
            {'delta': {}, 'finish_reason': 'stop'}
          ]
        }),
        '',
      );
      expect(ChatClient.parseDelta({'choices': []}), '');
      expect(ChatClient.parseDelta({}), '');
    });

    test('兼容 message.content 格式', () {
      expect(
        ChatClient.parseDelta({
          'choices': [
            {
              'message': {'content': 'hi there'}
            }
          ]
        }),
        'hi there',
      );
    });
  });

  group('Conversation', () {
    test('JSON 往返', () {
      final c = Conversation(
        id: 'c1',
        siteId: 's1',
        model: 'gpt-4o',
        messages: [
          ChatMessage(role: 'user', content: '你好'),
          ChatMessage(role: 'assistant', content: '您好！'),
        ],
      );
      c.refreshTitle();
      final r = Conversation.fromJson(c.toJson());
      expect(r.id, 'c1');
      expect(r.model, 'gpt-4o');
      expect(r.title, '你好');
      expect(r.messages.length, 2);
      expect(r.messages[1].role, 'assistant');
    });

    test('标题截断与空白折叠', () {
      final c = Conversation(id: 'c2', siteId: 's', model: 'm');
      c.messages.add(ChatMessage(
          role: 'user',
          content: '  这是\n一个很长的\n问题内容超过二十四个字  '));
      c.refreshTitle();
      expect(c.title.length <= 25, true);
      expect(c.title.contains('\n'), false);
    });

    test('无用户消息时标题不变', () {
      final c = Conversation(id: 'c3', siteId: 's', model: 'm');
      c.refreshTitle();
      expect(c.title, '新会话');
    });

    test('toApiJson 只含 role/content', () {
      final m = ChatMessage(role: 'user', content: 'hi');
      expect(m.toApiJson(), {'role': 'user', 'content': 'hi'});
    });
  });

}
