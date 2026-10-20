import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:site_manager/models/site.dart';
import 'package:site_manager/services/site_client.dart';

Site _site() => Site(
      id: 't1',
      name: '测试站',
      baseUrl: 'https://api.example.com/',
    );

/// http.Response 默认按 Latin1 编码 body，中文会炸；统一用 bytes 构造。
http.Response _jsonResp(Map<String, dynamic> obj, int code) =>
    http.Response.bytes(utf8.encode(jsonEncode(obj)), code,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('testConnection', () {
    test('200 返回模型数量', () async {
      final client = SiteClient(
        httpClient: MockClient((req) async {
          expect(req.url.path, '/v1/models');
          expect(req.headers['Authorization'], 'Bearer sk-test');
          return http.Response(
              jsonEncode({
                'data': [
                  {'id': 'gpt-4'},
                  {'id': 'gpt-3.5-turbo'}
                ]
              }),
              200);
        }),
      );
      final r = await client.testConnection(_site(), 'sk-test');
      expect(r.ok, true);
      expect(r.modelCount, 2);
      client.close();
    });

    test('401 提示 Key 无效', () async {
      final client = SiteClient(
        httpClient: MockClient((_) async => http.Response('{}', 401)),
      );
      final r = await client.testConnection(_site(), 'sk-bad');
      expect(r.ok, false);
      expect(r.message, contains('401'));
      client.close();
    });

    test('空 Key 直接拒绝', () async {
      final client = SiteClient(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final r = await client.testConnection(_site(), '');
      expect(r.ok, false);
      client.close();
    });
  });

  group('fetchModels', () {
    test('解析并排序模型 id', () async {
      final client = SiteClient(
        httpClient: MockClient((_) async => http.Response(
            jsonEncode({
              'data': [
                {'id': 'b-model'},
                {'id': 'a-model'}
              ]
            }),
            200)),
      );
      final list = await client.fetchModels(_site(), 'sk-test');
      expect(list, ['a-model', 'b-model']);
      client.close();
    });
  });

  group('fetchBalance', () {
    test('解析 NewAPI 用户信息', () async {
      final client = SiteClient(
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/user/self');
          return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'username': 'demo',
                  'quota': 1000000,
                  'used_quota': 250000,
                }
              }),
              200);
        }),
      );
      final b = await client.fetchBalance(_site(), cookie: 'session=abc');
      expect(b.username, 'demo');
      expect(b.quota, 1000000);
      expect(b.usedQuota, 250000);
      // (1000000-250000)/500000 = 1.5 美元
      expect(b.dollarsLeft, closeTo(1.5, 1e-9));
      client.close();
    });

    test('401 抛 NeedWebLoginException', () async {
      final client = SiteClient(
        httpClient: MockClient((_) async => http.Response('{}', 401)),
      );
      expect(
        () => client.fetchBalance(_site(), cookie: 'expired=1'),
        throwsA(isA<NeedWebLoginException>()),
      );
      client.close();
    });
  });

  group('checkin', () {
    test('状态接口解析', () async {
      final client = SiteClient(
        httpClient: MockClient((req) async {
          expect(req.method, 'GET');
          expect(req.url.path, '/api/user/checkin');
          return http.Response(
              jsonEncode({'success': true, 'data': true}), 200);
        }),
      );
      final s = await client.checkinStatus(_site(), 'session=abc');
      expect(s.ok, true);
      expect(s.checkedIn, true);
      client.close();
    });

    test('404 表示不支持 API 签到', () async {
      final client = SiteClient(
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
      final s = await client.checkinStatus(_site(), 'session=abc');
      expect(s.ok, false);
      expect(s.message, contains('不支持'));
      client.close();
    });

    test('签到成功', () async {
      final client = SiteClient(
        httpClient: MockClient((req) async {
          expect(req.method, 'POST');
          return _jsonResp({'success': true, 'message': '签到成功，+100 额度'}, 200);
        }),
      );
      final r = await client.doCheckin(_site(), 'session=abc');
      expect(r.ok, true);
      expect(r.checkedIn, true);
      client.close();
    });

    test('Turnstile 拦截给出手动指引', () async {
      final client = SiteClient(
        httpClient:
            MockClient((_) async => _jsonResp({'success': false, 'message': 'Turnstile 验证失败'}, 200)),
      );
      final r = await client.doCheckin(_site(), 'session=abc');
      expect(r.ok, false);
      expect(r.message, contains('手动'));
      client.close();
    });
  });
}
