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

  // s1 手动站：手动签到、无登录、无签到记录
  // s2 已登录站：已登录、今日已签到
  // s3 订阅站：无用户面板、无签到功能
  Future<SiteStore> storeWith3() async {
    final store = SiteStore();
    await store.load();
    await store.add(Site(
        id: 's1',
        name: '手动站',
        baseUrl: 'https://s1.example.com',
        manualCheckin: true));
    await store.add(Site(id: 's2', name: '已登录站', baseUrl: 'https://s2.example.com'));
    await store.add(Site(
        id: 's3',
        name: '订阅站',
        baseUrl: 'https://s3.example.com',
        type: SiteType.sub2Api));
    await store.setCookie('s2', 'session=abc');
    await store.recordCheckin('s2', '今日已签到');
    return store;
  }

  Future<void> pumpList(WidgetTester tester, SiteStore store) async {
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
  }

  List<String> visibleNames(WidgetTester tester) {
    const names = ['手动站', '已登录站', '订阅站'];
    return tester
        .widgetList<Text>(find.byWidgetPredicate(
            (w) => w is Text && names.contains(w.data)))
        .map((t) => t.data!)
        .toList();
  }

  Future<void> openFilterMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
  }

  Future<void> pickFilter(WidgetTester tester, String label) async {
    await openFilterMenu(tester);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('只看手动签到', (tester) async {
    final store = await storeWith3();
    await pumpList(tester, store);
    expect(visibleNames(tester), ['手动站', '已登录站', '订阅站']);
    await pickFilter(tester, '只看手动签到');
    expect(visibleNames(tester), ['手动站']);
    // 生效 1 项筛选，筛选按钮右上角应有数量角标
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('只看未签到：已签到的与无签到功能的不计入', (tester) async {
    final store = await storeWith3();
    await pumpList(tester, store);
    await pickFilter(tester, '只看未签到');
    expect(visibleNames(tester), ['手动站']);
  });

  testWidgets('只看未登录：已登录的与无用户面板的不计入', (tester) async {
    final store = await storeWith3();
    await pumpList(tester, store);
    await pickFilter(tester, '只看未登录');
    expect(visibleNames(tester), ['手动站']);
  });

  testWidgets('添加站点按钮可拖动，松手后位置持久化', (tester) async {
    final store = await storeWith3();
    await pumpList(tester, store);
    final fab = find.byType(FloatingActionButton);
    final before = tester.getTopLeft(fab);
    // 分步拖动；Flutter 拖拽会吞掉 slop 阈值前的位移，
    // 所以只断言方向与幅度，不卡精确像素
    final start = tester.getCenter(fab);
    final gesture = await tester.startGesture(start);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(start + Offset(-10.0 * i, -10.0 * i));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(fab);
    expect(before.dx - after.dx, greaterThan(50));
    expect(before.dy - after.dy, greaterThan(50));
    expect(before.dx - after.dx, lessThan(110));
    expect(before.dy - after.dy, lessThan(110));
    // 重建页面后应复原到拖动后的位置（位置已持久化）
    await pumpList(tester, store);
    final restored = tester.getTopLeft(find.byType(FloatingActionButton));
    expect(restored.dx, closeTo(after.dx, 1));
    expect(restored.dy, closeTo(after.dy, 1));
  });
}
