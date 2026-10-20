import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:site_manager/models/site.dart';
import 'package:site_manager/services/cookie_sync.dart';
import 'package:site_manager/services/site_client.dart';

void main() {
  group('CookieSync 刷新 Cookie', () {
    test('new_api_refresh 被识别为会话凭证', () {
      expect(CookieSync.isSessionCookieName('new_api_refresh'), true);
      expect(
          CookieSync.hasSessionCookie({'new_api_refresh': 'SID.SECRET'}),
          true);
    });

    test('new_api_has_session 只是提示标记', () {
      expect(CookieSync.isSessionCookieName('new_api_has_session'), true);
      expect(CookieSync.refreshCookieName, isNot('new_api_has_session'));
    });

    test('从 Set-Cookie 提取轮换后的刷新令牌', () {
      expect(
        CookieSync.extractRefreshToken(
            'new_api_refresh=SID.NEWSECRET; Path=/api/user/auth; HttpOnly; Secure; SameSite=Strict'),
        'SID.NEWSECRET',
      );
    });

    test('多 Set-Cookie 合并串中提取', () {
      expect(
        CookieSync.extractRefreshToken(
            'new_api_has_session=1; Path=/, new_api_refresh=SID.S2; Path=/api/user/auth; HttpOnly'),
        'SID.S2',
      );
    });

    test('无刷新 Cookie 返回 null', () {
      expect(CookieSync.extractRefreshToken('session=abc; Path=/'), null);
      expect(CookieSync.extractRefreshToken(''), null);
    });
  });

  group('SiteClient 新版登录体系', () {
    Site site() => Site(
          id: 's1',
          name: 't',
          baseUrl: 'https://example.com',
          createdAt: DateTime(2026),
        );

    test('refresh 换 access_token，走 Bearer，轮换回写回调', () async {
      final seen = <http.Request>[];
      final mock = MockClient((req) async {
        seen.add(req);
        if (req.url.path == '/api/user/auth/refresh') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'access_token': 'AT-123',
                'token_type': 'Bearer',
                'access_expires_at':
                    DateTime.now().millisecondsSinceEpoch ~/ 1000 + 900,
              }
            }),
            200,
            headers: {
              'set-cookie':
                  'new_api_refresh=SID.NEWSECRET; Path=/api/user/auth; HttpOnly'
            },
          );
        }
        if (req.url.path == '/api/user/self') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'username': 'u',
                'quota': 1500000,
                'used_quota': 500000,
              }
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final client = SiteClient(httpClient: mock);
      String? rotated;
      final b = await client.fetchBalance(
        site(),
        refreshToken: 'SID.OLDSECRET',
        onRefreshToken: (v) async => rotated = v,
      );
      expect(b.username, 'u');
      expect(b.dollarsLeft, 2.0);
      // 轮换回调拿到新令牌
      expect(rotated, 'SID.NEWSECRET');
      // refresh 请求带 Cookie + 单 Origin
      final refReq =
          seen.firstWhere((r) => r.url.path == '/api/user/auth/refresh');
      expect(refReq.headers['cookie'],
          contains('new_api_refresh=SID.OLDSECRET'));
      expect(refReq.headers['origin'], 'https://example.com');
      // 业务请求走 Bearer access_token
      final selfReq =
          seen.firstWhere((r) => r.url.path == '/api/user/self');
      expect(selfReq.headers['authorization'], 'Bearer AT-123');
      client.close();
    });

    test('access_token 15 分钟内复用，不重复刷新', () async {
      var refreshCount = 0;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/user/auth/refresh') {
          refreshCount++;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'access_token': 'AT-X',
                'token_type': 'Bearer',
                'access_expires_at':
                    DateTime.now().millisecondsSinceEpoch ~/ 1000 + 900,
              }
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'username': 'u', 'quota': 1, 'used_quota': 0}
          }),
          200,
        );
      });
      final client = SiteClient(httpClient: mock);
      const noop = _noop;
      await client.fetchBalance(site(),
          refreshToken: 'SID.A', onRefreshToken: noop);
      await client.fetchBalance(site(),
          refreshToken: 'SID.A', onRefreshToken: noop);
      expect(refreshCount, 1);
      client.close();
    });

    test('refresh 401 -> NeedWebLoginException', () async {
      final mock = MockClient((req) async {
        if (req.url.path == '/api/user/auth/refresh') {
          return http.Response('{"success":false}', 401);
        }
        return http.Response('not found', 404);
      });
      final client = SiteClient(httpClient: mock);
      expect(
        () => client.fetchBalance(site(),
            refreshToken: 'SID.DEAD', onRefreshToken: _noop),
        throwsA(isA<NeedWebLoginException>()),
      );
      client.close();
    });
  });
}

Future<void> _noop(String _) async {}
