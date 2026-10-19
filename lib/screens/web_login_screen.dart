import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../models/site.dart';
import '../services/site_store.dart';

/// 登录成功的启发式判断：必须是本站域名（排除 L站 OAuth 中转页），
/// 且进入 console / 首页等登录后页面。
bool webLoginLooksLoggedIn(Uri? url, String siteBaseUrl) {
  if (url == null) return false;
  final siteHost = Uri.tryParse(siteBaseUrl)?.host ?? '';
  if (siteHost.isEmpty || url.host != siteHost) return false;
  final p = url.path;
  return p.startsWith('/console') || p == '/' || p.isEmpty;
}

/// 内置浏览器：在站点官网完成登录后，自动捕获登录态（Cookie）并只存本机。
class WebLoginScreen extends StatefulWidget {
  final Site site;
  const WebLoginScreen({super.key, required this.site});

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  InAppWebViewController? _controller;
  bool _done = false;
  int _progress = 0;

  String get _loginUrl => '${widget.site.normalizedBaseUrl}/login';

  Future<void> _capture() async {
    if (_done) return;
    final c = _controller;
    if (c == null) return;
    try {
      // 始终读取本站点的 Cookie（而不是当前页面的，避免 OAuth 中转到
      // linux.do 时误抓 L站的 Cookie 存成站点的）
      final siteUri = WebUri(widget.site.normalizedBaseUrl);
      final cookies =
          await CookieManager.instance().getCookies(url: siteUri);
      if (cookies.isEmpty) {
        _toast('未读取到该站点的 Cookie，请确认已在页面内完成登录');
        return;
      }
      final header =
          cookies.map((e) => '${e.name}=${e.value}').join('; ');
      if (!mounted) return;
      await context.read<SiteStore>().setCookie(widget.site.id, header);
      setState(() => _done = true);
      _toast('已捕获登录态，共 ${cookies.length} 个 Cookie');
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _toast('捕获失败：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('站点网页登录'),
        actions: [
          TextButton(
            onPressed: _capture,
            child: const Text('已登录，捕获', style: TextStyle(color: Colors.white)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _progress < 100
              ? LinearProgressIndicator(value: _progress / 100)
              : const SizedBox.shrink(),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Text(
              '请在下方页面完成该站点的登录（支持"使用 Linux.do 登录"；'
              '建议先在站点列表右上角完成 L站登录，避免重复验证）'
              '检测到进入登录后页面会自动捕获 Cookie，也可点右上角"已登录，捕获"手动捕获。'
              'Cookie 只保存在本机安全存储。',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
              ),
              onWebViewCreated: (c) => _controller = c,
              onProgressChanged: (_, p) =>
                  setState(() => _progress = p),
              onLoadStop: (_, url) {
                // WebUri 实现了 Uri 接口，可直接传入
                if (webLoginLooksLoggedIn(
                    url, widget.site.normalizedBaseUrl)) {
                  _capture();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
