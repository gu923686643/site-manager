import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/site.dart';
import 'cookie_sync.dart';

/// 连通性测试结果。
class ConnResult {
  final bool ok;
  final String message;
  final int modelCount;
  const ConnResult({required this.ok, required this.message, this.modelCount = 0});
}

/// 余额信息。NewAPI 系额度单位：500000 = 1 美元（估算展示）。
class BalanceInfo {
  final String username;
  final int quota; // 剩余额度（原始单位）
  final int usedQuota; // 已用额度（原始单位）
  const BalanceInfo({
    required this.username,
    required this.quota,
    required this.usedQuota,
  });

  double get dollarsLeft => (quota - usedQuota) / 500000.0;

  static BalanceInfo? tryParse(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map) return null;
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    return BalanceInfo(
      username: '${data['username'] ?? ''}',
      quota: asInt(data['quota']),
      usedQuota: asInt(data['used_quota']),
    );
  }
}

/// 签到状态 / 结果。
class CheckinInfo {
  final bool ok;
  final bool checkedIn;
  final String message;
  const CheckinInfo({required this.ok, required this.checkedIn, required this.message});
}

/// 内存缓存的 access_token（新版 NewAPI 登录体系）。
class _CachedToken {
  final String token;
  final String refreshToken; // 发行它时所用的刷新令牌
  final DateTime expiresAt;
  const _CachedToken(this.token, this.refreshToken, this.expiresAt);
}

/// 与用户自建站点直接通信的 HTTP 客户端。
///
/// 所有请求只发往 [Site.baseUrl]，不经过任何中转服务。
/// `/api/user/*` 系列接口需要网页登录态：
/// - 旧版 NewAPI：网页会话 Cookie；
/// - 新版 NewAPI（refresh-token 体系）：用 `new_api_refresh` 换取
///   access_token 后走 `Authorization: Bearer`（见 [_newApiAccessToken]）。
/// `/v1/*` 只需要 apiKey。
class SiteClient {
  static const timeout = Duration(seconds: 15);
  final http.Client _http;
  final Map<String, _CachedToken> _accessTokens = {};

  SiteClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  void close() => _http.close();

  Map<String, String> _headers({String? apiKey, String? cookie, String? bearer}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'SiteManager/0.1',
    };
    if (bearer != null && bearer.isNotEmpty) {
      h['Authorization'] = 'Bearer $bearer';
    } else if (apiKey != null && apiKey.isNotEmpty) {
      h['Authorization'] = 'Bearer $apiKey';
    }
    if (cookie != null && cookie.isNotEmpty) {
      h['Cookie'] = cookie;
    }
    return h;
  }

  /// 新版 NewAPI 登录：用刷新 Cookie 换 access_token（15 分钟有效，内存缓存）。
  ///
  /// 对应前端逻辑：POST /api/user/auth/refresh（Cookie: new_api_refresh=…，
  /// 单 Origin 头过 SessionCookieOriginGuard）-> data.access_token。
  /// 刷新令牌每次使用都会轮换：把响应 Set-Cookie 里新的回写 WebView，
  /// 保持 App 与 WebView 一致，否则旧值超出重放窗口再用会触发
  /// "令牌复用"导致整个会话被吊销。
  Future<String> _newApiAccessToken(
    Site site, {
    required String refreshToken,
    required Future<void> Function(String rotated) onRotated,
  }) async {
    final cached = _accessTokens[site.id];
    if (cached != null &&
        cached.refreshToken == refreshToken &&
        DateTime.now().isBefore(cached.expiresAt)) {
      return cached.token;
    }
    final base = site.normalizedBaseUrl;
    final resp = await _http
        .post(
          Uri.parse('$base/api/user/auth/refresh'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'SiteManager/0.1',
            'Cookie': '${CookieSync.refreshCookieName}=$refreshToken',
            'Origin': base,
            'Referer': '$base/',
          },
        )
        .timeout(timeout);
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      _accessTokens.remove(site.id);
      throw NeedWebLoginException('登录态失效，请重新在内置浏览器登录');
    }
    if (resp.statusCode != 200) {
      throw Exception('刷新登录态失败：HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>? ?? {};
    final token = '${data['access_token'] ?? ''}';
    if (token.isEmpty) throw Exception('刷新登录态失败：未返回 access_token');
    // 轮换后的新刷新令牌：持久化 + 回写 WebView
    final rotated =
        CookieSync.extractRefreshToken(resp.headers['set-cookie'] ?? '');
    if (rotated != null && rotated.isNotEmpty && rotated != refreshToken) {
      await onRotated(rotated);
      final host = Uri.tryParse(base)?.host ?? '';
      if (host.isNotEmpty) {
        await CookieSync.writeBackRefreshCookie(
          host,
          rotated,
          secure: base.startsWith('https://'),
        );
      }
    }
    final exp = data['access_expires_at'];
    final expiresAt = exp is int
        ? DateTime.fromMillisecondsSinceEpoch(exp * 1000)
        : DateTime.now().add(const Duration(minutes: 14));
    _accessTokens[site.id] = _CachedToken(
      token,
      refreshToken,
      expiresAt.subtract(const Duration(minutes: 1)),
    );
    return token;
  }

  /// 若传入 refreshToken（新版登录体系），先换取 access_token 走 Bearer；
  /// 否则沿用旧逻辑（cookie / apiKey）。
  Future<String> _bearerFor(
    Site site, {
    String refreshToken = '',
    Future<void> Function(String)? onRefreshToken,
  }) async {
    if (refreshToken.isNotEmpty && onRefreshToken != null) {
      return _newApiAccessToken(
        site,
        refreshToken: refreshToken,
        onRotated: onRefreshToken,
      );
    }
    return '';
  }

  /// 测连通：GET /v1/models，顺带拿到模型数量。
  Future<ConnResult> testConnection(Site site, String apiKey) async {
    if (apiKey.isEmpty) {
      return const ConnResult(ok: false, message: '请先填写 API Key');
    }
    try {
      final resp = await _http
          .get(
            Uri.parse('${site.normalizedBaseUrl}/v1/models'),
            headers: _headers(apiKey: apiKey),
          )
          .timeout(timeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final data = body['data'];
        final count = data is List ? data.length : 0;
        return ConnResult(ok: true, message: '连接正常', modelCount: count);
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return const ConnResult(ok: false, message: 'API Key 无效（401/403）');
      }
      return ConnResult(ok: false, message: 'HTTP ${resp.statusCode}');
    } on TimeoutException {
      return const ConnResult(ok: false, message: '连接超时，请检查地址与网络');
    } catch (e) {
      return ConnResult(ok: false, message: '连接失败：$e');
    }
  }

  /// 拉模型列表：GET /v1/models。
  Future<List<String>> fetchModels(Site site, String apiKey) async {
    final resp = await _http
        .get(
          Uri.parse('${site.normalizedBaseUrl}/v1/models'),
          headers: _headers(apiKey: apiKey),
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = body['data'];
    if (data is! List) return [];
    final ids = <String>[];
    for (final e in data) {
      if (e is Map && e['id'] != null) ids.add('${e['id']}');
    }
    ids.sort();
    return ids;
  }

  /// 查余额：GET /api/user/self。
  /// 新版登录体系用 refreshToken 换 Bearer；旧版优先网页登录态 cookie，缺失时尝试 apiKey。
  ///
  /// 注意：部分站点要求必须网页登录；此时会抛出 [NeedWebLoginException]，
  /// 调用方应引导用户去内置浏览器完成登录。
  Future<BalanceInfo> fetchBalance(Site site,
      {String cookie = '',
      String apiKey = '',
      String refreshToken = '',
      Future<void> Function(String)? onRefreshToken}) async {
    final bearer = await _bearerFor(site,
        refreshToken: refreshToken, onRefreshToken: onRefreshToken);
    final resp = await _http
        .get(
          Uri.parse('${site.normalizedBaseUrl}/api/user/self'),
          headers: _headers(apiKey: apiKey, cookie: cookie, bearer: bearer),
        )
        .timeout(timeout);
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw NeedWebLoginException('该接口需要网页登录态，请先在内置浏览器登录站点');
    }
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body['success'] == false) {
      throw Exception('${body['message'] ?? '查询失败'}');
    }
    final info = BalanceInfo.tryParse(body);
    if (info == null) throw Exception('余额数据解析失败（站点可能不是 NewAPI 系）');
    return info;
  }

  /// 签到状态：GET /api/user/checkin。需要网页登录态。
  Future<CheckinInfo> checkinStatus(Site site, String cookie,
      {String refreshToken = '',
      Future<void> Function(String)? onRefreshToken}) async {
    if (cookie.isEmpty && refreshToken.isEmpty) {
      throw NeedWebLoginException('签到需要网页登录态，请先在内置浏览器登录站点');
    }
    final bearer = await _bearerFor(site,
        refreshToken: refreshToken, onRefreshToken: onRefreshToken);
    final resp = await _http
        .get(
          Uri.parse('${site.normalizedBaseUrl}/api/user/checkin'),
          headers: _headers(cookie: cookie, bearer: bearer),
        )
        .timeout(timeout);
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw NeedWebLoginException('登录态失效，请重新在内置浏览器登录');
    }
    if (resp.statusCode != 200) {
      // 接口不存在 -> 该站点不支持 API 签到
      if (resp.statusCode == 404) {
        return const CheckinInfo(
            ok: false, checkedIn: false, message: '该站点不支持 API 签到，可去网页手动签到');
      }
      throw Exception('HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = body['data'];
    final checkedIn = data == true ||
        (data is Map && (data['checked_in'] == true || data['has_checkin'] == true));
    return CheckinInfo(
      ok: true,
      checkedIn: checkedIn,
      message: checkedIn ? '今日已签到' : '今日未签到',
    );
  }

  /// 执行签到：POST /api/user/checkin。需要网页登录态。
  ///
  /// 部分站点开启了 Turnstile 人机验证，自动签到会被拦下，
  /// 此时返回 ok=false 并提示去网页手动完成。
  Future<CheckinInfo> doCheckin(Site site, String cookie,
      {String refreshToken = '',
      Future<void> Function(String)? onRefreshToken}) async {
    if (cookie.isEmpty && refreshToken.isEmpty) {
      throw NeedWebLoginException('签到需要网页登录态，请先在内置浏览器登录站点');
    }
    final bearer = await _bearerFor(site,
        refreshToken: refreshToken, onRefreshToken: onRefreshToken);
    final resp = await _http
        .post(
          Uri.parse('${site.normalizedBaseUrl}/api/user/checkin'),
          headers: _headers(cookie: cookie, bearer: bearer),
        )
        .timeout(timeout);
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw NeedWebLoginException('登录态失效，请重新在内置浏览器登录');
    }
    if (resp.statusCode == 404) {
      return const CheckinInfo(
          ok: false, checkedIn: false, message: '该站点不支持 API 签到，可去网页手动签到');
    }
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final success = body['success'] == true;
    final msg = '${body['message'] ?? ''}';
    final needsHuman =
        msg.contains('Turnstile') || msg.contains('验证') || msg.contains('captcha');
    if (success) {
      return CheckinInfo(ok: true, checkedIn: true, message: msg.isEmpty ? '签到成功' : msg);
    }
    return CheckinInfo(
      ok: false,
      checkedIn: false,
      message: needsHuman ? '需要人机验证，请去网页手动签到' : (msg.isEmpty ? '签到失败' : msg),
    );
  }

  /// 站点公告：GET /api/notice（公开接口，无需认证）。
  /// 返回空字符串表示站点未设置公告。
  Future<String> fetchNotice(Site site) async {
    final resp = await _http
        .get(
          Uri.parse('${site.normalizedBaseUrl}/api/notice'),
          headers: _headers(),
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final body = resp.body.trim();
    if (body.isEmpty || body == 'null' || body == '""') return '';
    // serveRevalidatedJSON 直接写字符串时 body 是带引号的 JSON 字符串
    try {
      final decoded = jsonDecode(body);
      if (decoded is String) return decoded.trim();
    } catch (_) {}
    return body;
  }

  /// 我的用量明细：GET /api/log/self（NewAPI 系，需用户登录态）。
  Future<List<UsageLog>> fetchUserLogs(
    Site site, {
    required String cookie,
    required String apiKey,
    String refreshToken = '',
    Future<void> Function(String)? onRefreshToken,
    int pageSize = 20,
  }) async {
    final bearer = await _bearerFor(site,
        refreshToken: refreshToken, onRefreshToken: onRefreshToken);
    final uri = Uri.parse(
        '${site.normalizedBaseUrl}/api/log/self?p=0&page_size=$pageSize');
    final resp = await _http
        .get(uri,
            headers: _headers(apiKey: apiKey, cookie: cookie, bearer: bearer))
        .timeout(timeout);
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw NeedWebLoginException('登录态失效，请重新在内置浏览器登录');
    }
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw Exception('${body['message'] ?? '查询失败'}');
    }
    final data = body['data'];
    final items = data is Map ? data['items'] as List? : null;
    if (items == null) return [];
    return items
        .map(UsageLog.tryParse)
        .whereType<UsageLog>()
        .toList();
  }
}

/// 用量日志条目。NewAPI 系 GET /api/log/self 返回。
class UsageLog {
  final int createdAt; // unix 秒
  final String modelName;
  final int quota; // 原始额度单位
  final int type;
  final String content;

  const UsageLog({
    required this.createdAt,
    required this.modelName,
    required this.quota,
    required this.type,
    required this.content,
  });

  double get dollars => quota / 500000.0;

  String get typeLabel {
    switch (type) {
      case 1:
        return '充值';
      case 2:
        return '消费';
      case 3:
        return '管理';
      case 4:
        return '系统';
      case 5:
        return '异常';
      case 6:
        return '退款';
      case 7:
        return '登录';
      default:
        return '其他';
    }
  }

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

  static UsageLog? tryParse(dynamic json) {
    if (json is! Map) return null;
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    return UsageLog(
      createdAt: asInt(json['created_at']),
      modelName: '${json['model_name'] ?? ''}',
      quota: asInt(json['quota']),
      type: asInt(json['type']),
      content: '${json['content'] ?? ''}',
    );
  }
}

/// 需要网页登录才能继续的信号异常，UI 层捕获后引导用户去内置浏览器登录。
class NeedWebLoginException implements Exception {
  final String message;
  NeedWebLoginException(this.message);
  @override
  String toString() => message;
}
