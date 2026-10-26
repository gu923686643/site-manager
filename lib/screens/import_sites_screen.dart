import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/site.dart';
import '../services/site_import.dart';
import '../services/site_store.dart';

/// 导入站点：粘贴文本批量添加，每行只需「名称」与「地址」两个字段。
class ImportSitesScreen extends StatefulWidget {
  const ImportSitesScreen({super.key});

  @override
  State<ImportSitesScreen> createState() => _ImportSitesScreenState();
}

class _ImportSitesScreenState extends State<ImportSitesScreen> {
  final _ctrl = TextEditingController();
  String? _summary;
  List<String> _invalid = [];
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _doImport() async {
    final store = context.read<SiteStore>();
    setState(() {
      _busy = true;
      _summary = null;
      _invalid = [];
    });
    try {
      final parsed = parseImportText(_ctrl.text);
      final toAdd = <Site>[];
      final seen = <String>{};
      var dup = 0;
      for (final e in parsed.entries) {
        // 地址归一化后判重：与已有站点比 + 本批内比
        final key =
            e.baseUrl.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
        if (seen.contains(key) || store.findDuplicate(e.baseUrl) != null) {
          dup++;
          continue;
        }
        seen.add(key);
        toAdd.add(Site(
          id: Site.newId(),
          name: e.name,
          baseUrl: e.baseUrl,
        ));
      }
      if (toAdd.isNotEmpty) await store.addAll(toAdd);
      if (!mounted) return;
      setState(() {
        _summary =
            '成功导入 ${toAdd.length} 个，重复跳过 $dup 个，无效 ${parsed.invalidLines.length} 行';
        _invalid = parsed.invalidLines;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入站点')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '每行一个站点，只需名称与地址两个字段：',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Future Hub,https://api.futureppo.top\n'
            '华为云 https://115.175.46.250\n'
            'https://api.example.com（只有地址时，名称自动取域名）\n'
            '空行与 # 开头的注释行会被跳过；缺 https:// 的地址自动补全。',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 12,
            minLines: 8,
            decoration: const InputDecoration(
              hintText: '在此粘贴站点列表…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _doImport,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('导入'),
          ),
          if (_summary != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_summary!,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    if (_invalid.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('无效行（请修正后重新导入，重复的会自动跳过）：',
                          style: TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      ..._invalid.take(10).map((l) => Text('· $l',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.red))),
                      if (_invalid.length > 10)
                        Text('……等 ${_invalid.length} 行',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.red)),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('完成并返回列表'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            '导入的站点类型默认为 NewAPI，可在编辑页修改；'
            'API Key 需之后单独填写或从账号导入。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
