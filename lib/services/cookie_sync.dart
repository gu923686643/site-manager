import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 登录态同步：以系统 WebView 的 Cookie 存储为事实来源。
///
/// 对标原版思路：
/// - 不只读配置的那一个 host，而是扫描"相关域名"（自身、www 变体、父域）；
/// - 同名 Cookie 去重时打分，优先会话类（session/auth/token），再看值长度；
/// - Cookie 会轮换，所以每次签到/查余额前都静默重同步一次来自愈。
class CookieSync {
  /// 会话类 Cookie 名特征。
  static bool isSessionCookieName(String name) {
    final n = name.toLowerCase();
    return n.contains('session') ||
        n.contains('auth') ||
        n.contains('token') ||
        n.contains('refresh') ||
        n == 'sid' ||
        n.endsWith('_sid') ||
        n.endsWith('.sid') ||
        n == 'sessionid' ||
        n == 'phpsessid' ||
        n == 'jsessionid';
  }

  /// 新版 NewAPI 的刷新 Cookie 名与路径（见 [collectRefreshCookies]）。
  static const refreshCookieName = 'new_api_refresh';
  static const refreshCookiePath = '/api/user/auth';

  /// 由 host 生成相关 host：自身、www 前缀变体、父域及父域 www 变体。
  /// 如 api.example.com -> [api.example.com, www.api.example.com,
  /// example.com, www.example.com]
  static List<String> relatedHosts(String host) {
    final h = host.toLowerCase().trim();
    final out = <String>{};
    if (h.isEmpty) return const [];
    out.add(h);
    if (h.startsWith('www.')) {
      out.add(h.substring(4));
    } else {
      out.add('www.$h');
    }
    final parts = h.split('.');
    if (parts.length > 2) {
      final parent = parts.sublist(1).join('.');
      out.add(parent);
      if (parent.startsWith('www.')) {
        out.add(parent.substring(4));
      } else {
        out.add('www.$parent');
      }
    }
    return out.toList();
  }

  /// 从 WebView Cookie 存储收集 [hosts] 的全部 Cookie，按名去重，
  /// 同名时保留打分更高的（会话类优先，其次值更长、其次带过期时间）。
  static Future<Map<String, String>> collectCookies(
      Iterable<String> hosts) async {
    final best = <String, Cookie>{};
    for (final host in hosts) {
      List<Cookie> cs;
      try {
        cs =
            await CookieManager.instance().getCookies(url: WebUri('https://$host'));
      } catch (_) {
        continue;
      }
      for (final c in cs) {
        final cur = best[c.name];
        if (cur == null || _score(c) > _score(cur)) best[c.name] = c;
      }
    }
    final out = <String, String>{};
    for (final e in best.entries) {
      final v = e.value.value;
      out[e.key] = v == null ? '' : v.toString();
    }
    return out;
  }

  static int _score(Cookie c) {
    var s = 0;
    if (isSessionCookieName(c.name)) s += 100;
    final v = c.value;
    final len = v == null ? 0 : v.toString().length;
    s += len.clamp(0, 50);
    if (c.expiresDate != null) s += 10;
    return s;
  }

  /// 是否存在会话类 Cookie（判定"看起来已登录"）。
  static bool hasSessionCookie(Map<String, String> cookies) =>
      cookies.keys.any(isSessionCookieName);

  /// 收集新版 NewAPI 的刷新 Cookie（`new_api_refresh`）。
  ///
  /// 它被服务器限定 Path=/api/user/auth 且 HttpOnly：用根路径查询会被
  /// 路径匹配挡掉，所以必须用该路径下的 URL 去读。返回 host -> 值。
  static Future<Map<String, String>> collectRefreshCookies(
      Iterable<String> hosts) async {
    final out = <String, String>{};
    for (final host in hosts) {
      List<Cookie> cs;
      try {
        cs = await CookieManager.instance().getCookies(
            url: WebUri('https://$host$refreshCookiePath/refresh'));
      } catch (_) {
        continue;
      }
      for (final c in cs) {
        final v = c.value;
        if (c.name == refreshCookieName && v != null && '$v'.isNotEmpty) {
          out[host] = '$v';
        }
      }
    }
    return out;
  }

  /// 从 Set-Cookie 响应头中提取轮换后的刷新 Cookie 值。
  static String? extractRefreshToken(String setCookieHeader) {
    final m = RegExp('$refreshCookieName=([^;,\\s]+)')
        .firstMatch(setCookieHeader);
    if (m == null) return null;
    final v = m.group(1)!;
    return v.isEmpty ? null : v;
  }

  /// 把刷新 Cookie 回写到 WebView 存储，保持 App 与 WebView 两边一致。
  ///
  /// 刷新令牌每次使用都会轮换，任意一边用旧值再去刷新，超出重放窗口后
  /// 服务器会按"令牌复用"把整个会话吊销，所以轮换后必须回写。
  static Future<void> writeBackRefreshCookie(
    String host,
    String value, {
    bool secure = true,
  }) async {
    try {
      await CookieManager.instance().setCookie(
        url: WebUri('https://$host$refreshCookiePath/refresh'),
        name: refreshCookieName,
        value: value,
        path: refreshCookiePath,
        isHttpOnly: true,
        isSecure: secure,
      );
    } catch (_) {
      // 回写失败不阻塞主流程
    }
  }

  static String toHeader(Map<String, String> cookies) =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
}
