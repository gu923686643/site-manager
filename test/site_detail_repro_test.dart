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

  testWidgets('复现：无 Key 站点进详情页不红屏', (tester) async {
    final store = SiteStore();
    await store.load();
    // 只填 URL，不填 Key（127.0.0.1:9 连接直接被拒，网络失败走得快）
    await store.add(
      Site(
        id: 'repro1',
        name: '无Key站',
        baseUrl: 'http://127.0.0.1:9/',
        type: SiteType.newApi,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: store,
          child: const SiteDetailScreen(siteId: 'repro1'),
        ),
      ),
    );
    // 等 initState 里的异步网络失败、setState 落定
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('无Key站'), findsOneWidget);
  });
}
