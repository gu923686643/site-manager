/// 站点模型的本地管理信息：别名 / 启停 / 分组 / 排序。
class ManagedModel {
  final String id; // 服务器上的模型 id
  String alias; // 显示别名，空则显示 id
  bool enabled;
  String group; // 分组名，空为未分组
  int sort; // 越小越靠前
  DateTime lastSeen; // 上次在服务器上见到

  ManagedModel({
    required this.id,
    this.alias = '',
    this.enabled = true,
    this.group = '',
    this.sort = 0,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get displayName => alias.isEmpty ? id : alias;

  Map<String, dynamic> toJson() => {
        'id': id,
        'alias': alias,
        'enabled': enabled,
        'group': group,
        'sort': sort,
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory ManagedModel.fromJson(Map<String, dynamic> json) => ManagedModel(
        id: '${json['id'] ?? ''}',
        alias: '${json['alias'] ?? ''}',
        enabled: json['enabled'] != false,
        group: '${json['group'] ?? ''}',
        sort: (json['sort'] as int?) ?? 0,
        lastSeen: DateTime.tryParse('${json['lastSeen'] ?? ''}'),
      );
}
