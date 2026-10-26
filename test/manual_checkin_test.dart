import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_manager/models/site.dart';
import 'package:site_manager/screens/site_detail_screen.dart';
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

  testWidgets('手动确认按钮：网页签到后同步今日已签到状态与列表记录',
      (tester) async {
    final store = SiteStore();
    await store.load();
    await store.add(
      Site(
        id: 'manual1',
        name: '手动签到站',
        baseUrl: 'http://127.0.0.1:9/',
        type: SiteType.newApi,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: store,
          child: const SiteDetailScreen(siteId: 'manual1'),
        ),
      ),
    );
    // 等初始化里的静默网络失败落定
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // 切到签到页签
    await tester.tap(find
        .byWidgetPredicate((w) => w is Tab && w.text == '签到'));
    await tester.pumpAndSettle();

    // 初始未签到，手动确认按钮可见
    expect(find.text('我已在网页签到'), findsOneWidget);
    await tester.tap(find.text('我已在网页签到'));
    await tester.pump();

    // 详情页签状态变为已签到
    expect(find.text('今日已签到（手动确认）'), findsOneWidget);
    // 签到记录写回，列表徽标用同一记录 → 今日已签到
    final site = store.byId('manual1')!;
    expect(site.lastCheckinResult, '今日已签到');
    expect(site.checkinBadge(DateTime.now()), CheckinBadge.checkedToday);
    // 已签到后手动按钮不再需要
    expect(find.text('我已在网页签到'), findsNothing);
  });

  testWidgets('手动签到站点：签到页签隐藏接口签到按钮，只留手动确认',
      (tester) async {
    final store = SiteStore();
    await store.load();
    await store.add(
      Site(
        id: 'manual2',
        name: '手动站',
        baseUrl: 'http://127.0.0.1:9/',
        type: SiteType.newApi,
        manualCheckin: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: store,
          child: const SiteDetailScreen(siteId: 'manual2'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find
        .byWidgetPredicate((w) => w is Tab && w.text == '签到'));
    await tester.pumpAndSettle();

    // 接口签到按钮不在，手动确认按钮在
    expect(find.widgetWithText(FilledButton, '签到'), findsNothing);
    expect(find.text('我已在网页签到'), findsOneWidget);
    await tester.tap(find.text('我已在网页签到'));
    await tester.pump();

    expect(find.text('今日已签到（手动确认）'), findsOneWidget);
    expect(store.byId('manual2')!.lastCheckinResult, '今日已签到');
  });
}
