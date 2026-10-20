import 'package:flutter_test/flutter_test.dart';

import 'package:site_manager/services/cookie_sync.dart';

void main() {
  group('CookieSync.relatedHosts', () {
    test('子域名展开自身、www 变体、父域', () {
      final hosts = CookieSync.relatedHosts('api.example.com');
      expect(hosts, contains('api.example.com'));
      expect(hosts, contains('www.api.example.com'));
      expect(hosts, contains('example.com'));
      expect(hosts, contains('www.example.com'));
    });

    test('www 域名展开裸域', () {
      final hosts = CookieSync.relatedHosts('www.example.com');
      expect(hosts, contains('www.example.com'));
      expect(hosts, contains('example.com'));
    });

    test('裸域只展开 www 变体', () {
      final hosts = CookieSync.relatedHosts('example.com');
      expect(hosts, containsAll(['example.com', 'www.example.com']));
      expect(hosts.length, 2);
    });

    test('空 host 返回空', () {
      expect(CookieSync.relatedHosts(''), isEmpty);
    });

    test('大小写归一', () {
      expect(CookieSync.relatedHosts('API.Example.COM'),
          contains('api.example.com'));
    });
  });

  group('CookieSync.isSessionCookieName', () {
    test('常见会话 Cookie 名', () {
      expect(CookieSync.isSessionCookieName('session'), true);
      expect(CookieSync.isSessionCookieName('auth.session-token'), true);
      expect(CookieSync.isSessionCookieName('_forum_session'), true);
      expect(CookieSync.isSessionCookieName('PHPSESSID'), true);
      expect(CookieSync.isSessionCookieName('connect.sid'), true);
      expect(CookieSync.isSessionCookieName('access_token'), true);
    });

    test('普通 Cookie 不误判', () {
      expect(CookieSync.isSessionCookieName('cf_clearance'), false);
      expect(CookieSync.isSessionCookieName('theme'), false);
      expect(CookieSync.isSessionCookieName('locale'), false);
    });
  });

  group('CookieSync.hasSessionCookie / toHeader', () {
    test('有会话 Cookie 才算已登录', () {
      expect(CookieSync.hasSessionCookie({'theme': 'dark'}), false);
      expect(CookieSync.hasSessionCookie({'session': 'abc'}), true);
    });

    test('拼 header', () {
      expect(CookieSync.toHeader({'a': '1', 'b': '2'}), 'a=1; b=2');
      expect(CookieSync.toHeader({}), '');
    });
  });
}
