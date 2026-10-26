import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_manager/models/site.dart';
import 'package:site_manager/screens/site_list_screen.dart';
import 'package:site_manager/services/chat_store.dart';
import 'package:site_manager/services/model_store.dart';
import 'package:site_manager/services/site_store.dart';

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

  Future<SiteStore> storeWith3() async {
    final store = SiteStore();
    await store.load();
    for (final id in ['a', 'b', 'c']) {
      await store.add(Site(
          id: id, name: '站$id', baseUrl: 'https://$id.example.com'));
    }
    return store;
  }

  group('SiteStore.moveSite', () {
    test('移到某站之前', () async {
      final store = await storeWith3();
      await store.moveSite('c', 'a');
      expect(store.sites.map((s) => s.id), ['c', 'a', 'b']);
    });

    test('移到末尾与不存在的 id 安全处理', () async {
      final store = await storeWith3();
      await store.moveSite('a', null);
      expect(store.sites.map((s) => s.id), ['b', 'c', 'a']);
      await store.moveSite('不存在', 'b');
      expect(store.sites.map((s) => s.id), ['b', 'c', 'a']);
      await store.moveSite('b', '不存在');
      expect(store.sites.map((s) => s.id), ['c', 'a', 'b']);
    });
  });

  testWidgets('列表按添加顺序显示，拖拽手柄可调整顺序', (tester) async {
    final store = await storeWith3();
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: store),
            ChangeNotifierProvider(create: (_) => ChatStore()),
            ChangeNotifierProvider(create: (_) => ModelStore()),
          ],
          child: const SiteListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 添加顺序：a、b、c
    final names = tester
        .widgetList<Text>(find.byWidgetPredicate(
            (w) => w is Text && ['站a', '站b', '站c'].contains(w.data)))
        .map((t) => t.data!)
        .toList();
    expect(names, ['站a', '站b', '站c']);

    // 落点按代理块算：拖动项的尾巴（指针 - 手柄偏移 + 卡片高）
    // 落在最后一张卡片的后半段才算插到末尾；用实测几何算出目标点
    final handles = find.byIcon(Icons.drag_handle);
    final cards = find.byType(Card);
    final firstCard = tester.getRect(cards.first);
    final lastCard = tester.getRect(cards.last);
    final start = tester.getCenter(handles.first);
    final dragOffset = start.dy - firstCard.top;
    final targetY = lastCard.top +
        lastCard.height * 0.75 +
        dragOffset -
        firstCard.height;
    final gesture = await tester.startGesture(start);
    // 分步拖动，让排序逻辑逐步跟进，最后落在目标点
    for (var i = 1; i <= 4; i++) {
      final y = start.dy + (targetY - start.dy) * i / 4;
      await gesture.moveTo(Offset(start.dx, y));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.sites.map((s) => s.id), ['b', 'c', 'a']);
  });
}
