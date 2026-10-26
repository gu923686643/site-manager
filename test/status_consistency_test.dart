import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_manager/models/site.dart';
import 'package:site_manager/services/site_store.dart';

/// 列表页徽标与详情页「站点信息」共用 SiteStore.hasApiKey / hasLogin，
/// 这里验证这两个口径在各种凭证组合下的结果，避免两处再次漂移。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = <String, String>{};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        final args = (call.arguments as Map?) ?? {};
        final key = '${args['key']}';
        switch (call.method) {
          case 'read':
            return storage[key];
          case 'write':
            storage[key] = '${args['value']}';
            return null;
          case 'delete':
            storage.remove(key);
            return null;
          case 'readAll':
            return Map<String, String>.from(storage);
          case 'deleteAll':
            storage.clear();
            return null;
          case 'containsKey':
            return storage.containsKey(key);
        }
        return null;
      },
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage.clear();
  });

  Site mk(String id) =>
      Site(id: id, name: id, baseUrl: 'https://$id.example.com');

  Future<SiteStore> loaded() async {
    final store = SiteStore();
    await store.load();
    return store;
  }

  group('hasLogin（Cookie 或新版刷新令牌任一存在即已登录）', () {
    test('无任何凭证 → 未登录', () async {
      final store = await loaded();
      await store.add(mk('a'));
      expect(store.hasLogin('a'), false);
    });

    test('只有 Cookie → 已登录', () async {
      final store = await loaded();
      await store.add(mk('a'));
      await store.setCookie('a', 'session=abc');
      expect(store.hasLogin('a'), true);
    });

    test('只有新版刷新令牌 → 已登录（回归：列表旧口径只看 Cookie）', () async {
      final store = await loaded();
      await store.add(mk('a'));
      await store.setRefreshToken('a', 'sid.secret');
      expect(store.cookieOf('a'), isEmpty);
      expect(store.hasLogin('a'), true);
    });

    test('退出登录清双凭证 → 未登录', () async {
      final store = await loaded();
      await store.add(mk('a'));
      await store.setCookie('a', 'session=abc');
      await store.setRefreshToken('a', 'sid.secret');
      await store.clearCookie('a');
      await store.clearRefreshToken('a');
      expect(store.hasLogin('a'), false);
    });
  });

  group('hasApiKey（与多 Key 列表同步）', () {
    test('建站时带 Key → 有；不带 → 无', () async {
      final store = await loaded();
      await store.add(mk('a'), apiKey: 'sk-1');
      await store.add(mk('b'));
      expect(store.hasApiKey('a'), true);
      expect(store.hasApiKey('b'), false);
    });

    test('从账号导入 Key（addApiKey）后 → 有；删光后 → 无', () async {
      final store = await loaded();
      await store.add(mk('a'));
      await store.addApiKey('a', 'sk-imported');
      expect(store.hasApiKey('a'), true);
      await store.removeApiKey('a', 0);
      expect(store.hasApiKey('a'), false);
    });
  });
}
