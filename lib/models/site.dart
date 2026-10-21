/// 站点类型：NewAPI / OneAPI / SUB2API / 通用 OpenAI 兼容。
enum SiteType { newApi, oneApi, sub2Api, openAi }

extension SiteTypeX on SiteType {
  String get label {
    switch (this) {
      case SiteType.newApi:
        return 'NewAPI';
      case SiteType.oneApi:
        return 'OneAPI';
      case SiteType.sub2Api:
        return 'SUB2API';
      case SiteType.openAi:
        return 'OpenAI 兼容';
    }
  }

  /// 是否有 NewAPI 风格的用户面板（GET /api/user/self 余额接口）。
  /// 已核实：One API 是 NewAPI 的上游，同样提供 /api/user/self；
  /// SUB2API 是订阅转接网关、通用 OpenAI 兼容端点没有该接口。
  bool get hasUserPanel =>
      this == SiteType.newApi || this == SiteType.oneApi;

  /// 是否支持签到（NewAPI 系功能；One API 源码中无签到接口）。
  bool get hasCheckin => this == SiteType.newApi;

  static SiteType fromName(String? name) => SiteType.values.firstWhere(
        (e) => e.name == name,
        orElse: () => SiteType.newApi,
      );
}

/// 一个 API 站点。
///
/// 普通字段存 SharedPreferences；apiKey 与 cookie 属于敏感信息，
/// 由 [SiteStore] 存入 flutter_secure_storage，不会出现在本对象的 JSON 里。
class Site {
  final String id;
  String name;
  String baseUrl;
  SiteType type;
  String note;

  /// 是否启用：停用的站点不参与批量操作。
  bool enabled;

  /// 收藏：置顶显示。
  bool favorite;

  /// 隐藏：默认不在列表显示。
  bool hidden;

  /// 标签：用于筛选。
  List<String> tags;

  /// 最近一次签到时间与结果摘要。
  DateTime? lastCheckinAt;
  String lastCheckinResult;

  final DateTime createdAt;

  Site({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.type = SiteType.newApi,
    this.note = '',
    this.enabled = true,
    this.favorite = false,
    this.hidden = false,
    List<String>? tags,
    this.lastCheckinAt,
    this.lastCheckinResult = '',
    DateTime? createdAt,
  })  : tags = tags ?? [],
        createdAt = createdAt ?? DateTime.now();

  /// 去掉末尾斜杠，统一拼接路径。
  String get normalizedBaseUrl {
    var u = baseUrl.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'type': type.name,
        'note': note,
        'enabled': enabled,
        'favorite': favorite,
        'hidden': hidden,
        'tags': tags,
        'lastCheckinAt': lastCheckinAt?.toIso8601String(),
        'lastCheckinResult': lastCheckinResult,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Site.fromJson(Map<String, dynamic> json) => Site(
        id: json['id'] as String,
        name: (json['name'] ?? '') as String,
        baseUrl: (json['baseUrl'] ?? '') as String,
        type: SiteTypeX.fromName(json['type'] as String?),
        note: (json['note'] ?? '') as String,
        enabled: (json['enabled'] as bool?) ?? true,
        favorite: (json['favorite'] as bool?) ?? false,
        hidden: (json['hidden'] as bool?) ?? false,
        tags: ((json['tags'] as List?) ?? [])
            .map((e) => '$e')
            .where((e) => e.isNotEmpty)
            .toList(),
        lastCheckinAt:
            DateTime.tryParse((json['lastCheckinAt'] ?? '') as String),
        lastCheckinResult: (json['lastCheckinResult'] ?? '') as String,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String),
      );

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}${(1000 + (DateTime.now().microsecond % 9000))}';

  /// 解析用户输入的标签：逗号/空格/顿号分隔，去重。
  static List<String> parseTags(String input) {
    final parts = input
        .split(RegExp(r'[,，、\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    final seen = <String>{};
    return parts.where((e) => seen.add(e)).toList();
  }
}

/// 列表页签到徽标状态。
enum CheckinBadge {
  /// 不显示徽标。
  none,

  /// 今天已签到。
  checkedToday,

  /// 今天签到异常（失败/登录态失效等）。
  anomalyToday,

  /// 以往某天签到成功过（只提示上次日期，不代表今日已签）。
  lastChecked,
}

extension SiteCheckinX on Site {
  /// 依据「最近一次签到」的时间与结果计算列表页徽标：
  /// 只有当天的结果才能显示「已签到/签到异常」；跨天后昨天的成功记录
  /// 降级为「上次 MM-DD」，避免用户误以为今天已经签过。
  CheckinBadge checkinBadge(DateTime now) {
    if (lastCheckinResult.isEmpty || lastCheckinAt == null) {
      return CheckinBadge.none;
    }
    final ok =
        lastCheckinResult.contains('成功') || lastCheckinResult.contains('已签到');
    final at = lastCheckinAt!.toLocal();
    final today = now.toLocal();
    final sameDay =
        at.year == today.year && at.month == today.month && at.day == today.day;
    if (sameDay) {
      return ok ? CheckinBadge.checkedToday : CheckinBadge.anomalyToday;
    }
    return ok ? CheckinBadge.lastChecked : CheckinBadge.none;
  }

  /// 「上次签到」徽标文案，如 `上次 10-20`。
  String get lastCheckinLabel {
    final at = lastCheckinAt!.toLocal();
    final m = at.month.toString().padLeft(2, '0');
    final d = at.day.toString().padLeft(2, '0');
    return '上次 $m-$d';
  }
}
