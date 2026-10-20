import 'package:flutter_test/flutter_test.dart';
import 'package:site_manager/screens/web_login_screen.dart';

void main() {
  group('webLoginLooksLoggedIn', () {
    const site = 'https://api.example.com';

    test('本站 console 页判定为已登录', () {
      expect(
        webLoginLooksLoggedIn(
            Uri.parse('https://api.example.com/console'), site),
        true,
      );
      expect(
        webLoginLooksLoggedIn(
            Uri.parse('https://api.example.com/console/token'), site),
        true,
      );
    });

    test('本站首页判定为已登录', () {
      expect(
        webLoginLooksLoggedIn(Uri.parse('https://api.example.com/'), site),
        true,
      );
    });

    test('本站登录页不判定', () {
      expect(
        webLoginLooksLoggedIn(
            Uri.parse('https://api.example.com/login'), site),
        false,
      );
    });

    test('L站 OAuth 中转页不判定（关键：防误抓 L站 Cookie）', () {
      // OAuth 授权页
      expect(
        webLoginLooksLoggedIn(
            Uri.parse('https://linux.do/oauth/authorize'), site),
        false,
      );
      // L站首页（路径为 /，但域名不对）
      expect(
        webLoginLooksLoggedIn(Uri.parse('https://linux.do/'), site),
        false,
      );
      // connect.linux.do 回调
      expect(
        webLoginLooksLoggedIn(
            Uri.parse('https://connect.linux.do/callback'), site),
        false,
      );
    });

    test('空 URL 不判定', () {
      expect(webLoginLooksLoggedIn(null, site), false);
    });
  });

  group('isOAuthHost', () {
    test('OAuth 中转域名识别', () {
      expect(isOAuthHost('linux.do'), true);
      expect(isOAuthHost('connect.linux.do'), true);
      expect(isOAuthHost('github.com'), true);
      expect(isOAuthHost('accounts.google.com'), true);
      expect(isOAuthHost('discord.com'), true);
      expect(isOAuthHost('appleid.apple.com'), true);
    });

    test('普通站点域名不误判', () {
      expect(isOAuthHost('api.example.com'), false);
      expect(isOAuthHost('my-linux.do.evil.com'), false);
      expect(isOAuthHost('notgithub.com'), false);
    });

    test('大小写不敏感', () {
      expect(isOAuthHost('Linux.DO'), true);
    });
  });
}
