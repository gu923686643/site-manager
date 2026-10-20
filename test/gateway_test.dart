import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_manager/services/gateway_service.dart';
import 'package:site_manager/services/site_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    // mock flutter_secure_storage 的 MethodChannel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  group('GatewayService', () {
    test('鉴权中间件：无/错 key 401，对 key 放行', () async {
      final gw = GatewayService();
      await gw.load();
      final key = await gw.regenerateKey();
      final handler = gw.buildHandler(SiteStore());

      Future<Response> get(String? auth) async => await handler(Request(
            'GET',
            Uri.parse('http://localhost/v1/models'),
            headers: {
              if (auth != null) 'Authorization': auth,
            },
          ));

      expect((await get(null)).statusCode, 401);
      expect((await get('Bearer wrong')).statusCode, 401);

      final ok = await get('Bearer $key');
      expect(ok.statusCode, 200);
      final body = jsonDecode(await ok.readAsString());
      expect(body['object'], 'list');
      expect(body['data'], isEmpty); // 空站点
    });

    test('未知模型返回 404 OpenAI 错误格式并记日志', () async {
      final gw = GatewayService();
      await gw.load();
      final key = await gw.regenerateKey();
      final handler = gw.buildHandler(SiteStore());

      final r = await handler(Request(
        'POST',
        Uri.parse('http://localhost/v1/chat/completions'),
        headers: {'Authorization': 'Bearer $key'},
        body: jsonEncode({
          'model': 'nope',
          'messages': [
            {'role': 'user', 'content': 'hi'}
          ]
        }),
      ));
      expect(r.statusCode, 404);
      final body = jsonDecode(await r.readAsString());
      expect(body['error']['message'], contains('Model not found'));
      expect(
          gw.logs.any((l) => l.status == 404 && l.model == 'nope'), true);
    });

    test('缺 model 参数返回 400', () async {
      final gw = GatewayService();
      await gw.load();
      final key = await gw.regenerateKey();
      final handler = gw.buildHandler(SiteStore());

      final r = await handler(Request(
        'POST',
        Uri.parse('http://localhost/v1/chat/completions'),
        headers: {'Authorization': 'Bearer $key'},
        body: jsonEncode({
          'messages': []
        }),
      ));
      expect(r.statusCode, 400);
    });
  });
}
