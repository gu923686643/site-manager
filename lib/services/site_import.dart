/// 导入站点：一行一个，只需「名称」与「地址」两个字段。
///
/// 支持的写法（地址一定在最后）：
/// - `名称,地址` / `名称，地址` / `名称\t地址`
/// - `名称 地址`（名称可含空格，如 `Future Hub https://api.example.com`）
/// - 只有地址（名称自动取域名）
/// 空行与 `#` 注释行跳过；缺 scheme 的地址自动补 `https://`。
class ImportSiteEntry {
  final String name;
  final String baseUrl;
  const ImportSiteEntry(this.name, this.baseUrl);
}

class ImportParseResult {
  final List<ImportSiteEntry> entries;
  final List<String> invalidLines;
  const ImportParseResult(this.entries, this.invalidLines);
}

ImportParseResult parseImportText(String text) {
  final entries = <ImportSiteEntry>[];
  final invalid = <String>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final entry = parseImportLine(line);
    if (entry == null) {
      invalid.add(line);
    } else {
      entries.add(entry);
    }
  }
  return ImportParseResult(entries, invalid);
}

/// 解析单行；非法返回 null。
ImportSiteEntry? parseImportLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  String? name;
  String? url;
  // 逗号/中文逗号/制表符：按第一个分隔符切（地址里可能还有逗号）
  final sep = RegExp(r'[,，\t]').firstMatch(trimmed);
  if (sep != null) {
    name = trimmed.substring(0, sep.start).trim();
    url = trimmed.substring(sep.end).trim();
  } else {
    // 空白分隔：地址在最后，名称可含空格
    final parts = trimmed
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length == 1) {
      url = parts.first;
    } else {
      name = parts.sublist(0, parts.length - 1).join(' ');
      url = parts.last;
    }
  }
  if (url.isEmpty) return null;
  final normalized = normalizeImportUrl(url);
  if (normalized == null) return null;
  name = (name ?? '').trim();
  if (name.isEmpty) {
    name = Uri.parse(normalized).host;
  }
  return ImportSiteEntry(name, normalized);
}

/// 地址规范化：缺 scheme 补 https；非法返回 null。
/// host 须含点号（域名/IP）或是 localhost，避免把误打的单个词当成地址。
String? normalizeImportUrl(String url) {
  var u = url.trim();
  if (u.isEmpty) return null;
  if (!u.contains('://')) u = 'https://$u';
  final uri = Uri.tryParse(u);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  if (uri.host != 'localhost' && !uri.host.contains('.')) return null;
  return u;
}
