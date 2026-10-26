import 'package:flutter_test/flutter_test.dart';
import 'package:site_manager/models/site.dart';

Site _site({DateTime? at, String result = ''}) => Site(
      id: 's1',
      name: '测试站',
      baseUrl: 'https://example.com',
      lastCheckinAt: at,
      lastCheckinResult: result,
    );

void main() {
  group('Site.checkinBadge', () {
    final now = DateTime(2026, 10, 21, 1, 8);

    test('无记录不显示', () {
      expect(_site().checkinBadge(now), CheckinBadge.none);
    });

    test('有结果但无时间不显示', () {
      expect(_site(result: '签到成功').checkinBadge(now), CheckinBadge.none);
    });

    test('今天签到成功 → checkedToday', () {
      final s = _site(at: DateTime(2026, 10, 21, 0, 30), result: '签到成功，获得额度');
      expect(s.checkinBadge(now), CheckinBadge.checkedToday);
    });

    test('今天查询到已签到 → checkedToday', () {
      final s = _site(at: DateTime(2026, 10, 21, 1, 0), result: '今日已签到');
      expect(s.checkinBadge(now), CheckinBadge.checkedToday);
    });

    test('昨天签到成功，今天凌晨看 → lastChecked（回归：跨天误显示已签到）', () {
      final s = _site(at: DateTime(2026, 10, 20, 15, 26), result: '今日已签到');
      expect(s.checkinBadge(now), CheckinBadge.lastChecked);
      expect(s.lastCheckinLabel, '上次 10-20');
    });

    test('昨晚 23:59 签到，今天 00:01 看 → lastChecked', () {
      final s = _site(at: DateTime(2026, 10, 20, 23, 59), result: '签到成功');
      expect(
        s.checkinBadge(DateTime(2026, 10, 21, 0, 1)),
        CheckinBadge.lastChecked,
      );
    });

    test('今天签到失败 → anomalyToday', () {
      final s = _site(at: DateTime(2026, 10, 21, 0, 5), result: '登录态失效');
      expect(s.checkinBadge(now), CheckinBadge.anomalyToday);
    });

    test('昨天的失败记录今天不显示', () {
      final s = _site(at: DateTime(2026, 10, 20, 12, 0), result: '失败');
      expect(s.checkinBadge(now), CheckinBadge.none);
    });

    test('今天状态查询回写「今日未签到」→ 不显示（中性结论，不是异常）', () {
      final s = _site(at: DateTime(2026, 10, 21, 0, 40), result: '今日未签到');
      expect(s.checkinBadge(now), CheckinBadge.none);
    });

    test('批量跳过记录 → 不显示（不是异常）', () {
      final s = _site(at: DateTime(2026, 10, 21, 0, 40), result: '需手动签到，已跳过');
      expect(s.checkinBadge(now), CheckinBadge.none);
      final s2 = _site(at: DateTime(2026, 10, 21, 0, 40), result: '待登录，已跳过');
      expect(s2.checkinBadge(now), CheckinBadge.none);
    });
  });
}
