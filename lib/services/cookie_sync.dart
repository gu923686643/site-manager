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
        n == 'sid' ||
        n.endsWith('_sid') ||
        n.endsWith('.sid') ||
        n == 'sessionid' ||
        n == 'phpsessid' ||
        n == 'jsessionid';
  }

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

  static String toHeader(Map<String, String> cookies) =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
}
