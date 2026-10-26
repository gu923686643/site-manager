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

    test('新版前端登录后落地 dashboard 判定为已登录', () {
      expect(
        webLoginLooksLoggedIn(
            Uri.parse('https://api.example.com/dashboard'), site),
        true,
      );
      expect(
        webLoginLooksLoggedIn(
            Uri.parse('https://api.example.com/dashboard/overview'), site),
        true,
      );
    });

    test('本站 sign-in 页不判定', () {
      expect(
        webLoginLooksLoggedIn(
            Uri.parse('https://api.example.com/sign-in'), site),
        false,
      );
    });
  });

  group('loginPathCandidates', () {
    test('无记忆时默认 /sign-in 优先', () {
      expect(loginPathCandidates(''), ['/sign-in', '/login']);
    });

    test('记住 /login 时 /login 优先', () {
      expect(loginPathCandidates('/login'), ['/login', '/sign-in']);
    });

    test('记住 /sign-in 时保持 /sign-in 优先', () {
      expect(loginPathCandidates('/sign-in'), ['/sign-in', '/login']);
    });

    test('未知记忆值回落到默认顺序', () {
      expect(loginPathCandidates('/whatever'), ['/sign-in', '/login']);
    });
  });

  group('isAuthPagePath', () {
    test('登录/注册路径识别', () {
      expect(isAuthPagePath('/login'), true);
      expect(isAuthPagePath('/login/'), true);
      expect(isAuthPagePath('/sign-in'), true);
      expect(isAuthPagePath('/register'), true);
      expect(isAuthPagePath('/sign-up'), true);
    });

    test('登录后路径不误判', () {
      expect(isAuthPagePath('/console'), false);
      expect(isAuthPagePath('/dashboard'), false);
      expect(isAuthPagePath('/'), false);
      expect(isAuthPagePath('/login-history'), false);
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
