import 'package:flutter_test/flutter_test.dart';
import 'package:site_manager/models/site.dart';
import 'package:site_manager/services/site_client.dart';

void main() {
  group('Site.parseTags', () {
    test('逗号/空格/顿号分隔并去重', () {
      expect(
        Site.parseTags('主力, 便宜 主力、备用,, '),
        ['主力', '便宜', '备用'],
      );
    });

    test('空输入返回空列表', () {
      expect(Site.parseTags(''), isEmpty);
      expect(Site.parseTags(' , '), isEmpty);
    });
  });

  group('Site JSON', () {
    test('新字段往返无损', () {
      final s = Site(
        id: 'x1',
        name: '站',
        baseUrl: 'https://a.example.com/',
        enabled: false,
        favorite: true,
        tags: ['主力', '便宜'],
        lastCheckinResult: '签到成功',
        lastCheckinAt: DateTime.utc(2026, 10, 19, 12),
      );
      final r = Site.fromJson(s.toJson());
      expect(r.enabled, false);
      expect(r.favorite, true);
      expect(r.tags, ['主力', '便宜']);
      expect(r.lastCheckinResult, '签到成功');
      expect(r.lastCheckinAt?.toUtc(), DateTime.utc(2026, 10, 19, 12));
    });

    test('老数据缺字段时给默认值', () {
      final r = Site.fromJson({
        'id': 'old',
        'name': '老站',
        'baseUrl': 'https://o.example.com',
      });
      expect(r.enabled, true);
      expect(r.favorite, false);
      expect(r.tags, isEmpty);
      expect(r.lastCheckinAt, isNull);
    });

    test('normalizedBaseUrl 去掉末尾斜杠', () {
      final s = Site(id: 'u', name: 'n', baseUrl: 'https://a.b///');
      expect(s.normalizedBaseUrl, 'https://a.b');
    });
  });

  group('SiteType 能力', () {
    test('NewAPI 全功能', () {
      expect(SiteType.newApi.hasUserPanel, true);
      expect(SiteType.newApi.hasCheckin, true);
    });

    test('OneAPI 有余额无签到（已核源码）', () {
      expect(SiteType.oneApi.hasUserPanel, true);
      expect(SiteType.oneApi.hasCheckin, false);
    });

    test('SUB2API 与通用兼容只有模型', () {
      expect(SiteType.sub2Api.hasUserPanel, false);
      expect(SiteType.sub2Api.hasCheckin, false);
      expect(SiteType.openAi.hasUserPanel, false);
      expect(SiteType.openAi.hasCheckin, false);
    });

    test('fromName 未知类型回退 NewAPI', () {
      expect(SiteTypeX.fromName('nope'), SiteType.newApi);
      expect(SiteTypeX.fromName('sub2Api'), SiteType.sub2Api);
    });

    test('hidden 字段往返', () {
      final s = Site(id: 'h', name: 'n', baseUrl: 'https://x', hidden: true);
      expect(Site.fromJson(s.toJson()).hidden, true);
      expect(
          Site.fromJson({'id': 'o', 'name': 'n', 'baseUrl': 'https://x'})
              .hidden,
          false);
    });
  });

  group('UsageLog', () {
    test('解析与换算', () {
      final l = UsageLog.tryParse({
        'created_at': 1760900000,
        'model_name': 'gpt-4o',
        'quota': 500000,
        'type': 2,
        'content': 'ok',
      })!;
      expect(l.modelName, 'gpt-4o');
      expect(l.dollars, 1.0);
      expect(l.typeLabel, '消费');
      expect(l.dateTime.year, 2025);
    });

    test('类型标签', () {
      expect(
          UsageLog.tryParse(
              {'created_at': 1, 'type': 1})!
              .typeLabel,
          '充值');
      expect(
          UsageLog.tryParse(
              {'created_at': 1, 'type': 99})!
              .typeLabel,
          '其他');
      expect(UsageLog.tryParse('nope'), isNull);
    });
  });
}
