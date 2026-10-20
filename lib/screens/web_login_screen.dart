import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../models/site.dart';
import '../services/cookie_sync.dart';
import '../services/site_store.dart';
import '../widgets/oauth_popup.dart';

/// OAuth 中转域名：这些站点的 Cookie 绝不能存为目标站点的登录态。
bool isOAuthHost(String host) {
  final h = host.toLowerCase();
  return h == 'linux.do' ||
      h.endsWith('.linux.do') ||
      h == 'github.com' ||
      h.endsWith('.github.com') ||
      h == 'accounts.google.com' ||
      h == 'discord.com' ||
      h.endsWith('.discord.com') ||
      h == 'appleid.apple.com';
}

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

  /// 捕获登录态。以 WebView 的 Cookie 存储为事实来源，扫描站点配置域名、
  /// 历史登录域名、当前页面域名的相关域名（自身/www 变体/父域），
  /// 同名 Cookie 按会话特征打分去重。静默模式下要求存在会话类 Cookie
  /// 才认定登录成功，避免登录前页面已有的普通 Cookie 造成误判。
  Future<void> _capture({bool silent = false}) async {
    if (_done) return;
    final c = _controller;
    if (c == null) return;
    void toast(String m) {
      if (!silent) _toast(m);
    }

    final store = context.read<SiteStore>();
    try {
      final currentUrl = await c.getUrl();
      final curHost = currentUrl?.host ?? '';
      if (curHost.isNotEmpty && isOAuthHost(curHost)) {
        toast('当前在第三方授权页，请回到站点页面后再捕获');
        return;
      }
      final siteHost =
          Uri.tryParse(widget.site.normalizedBaseUrl)?.host ?? '';
      final hosts = <String>{
        ...CookieSync.relatedHosts(siteHost),
        ...CookieSync.relatedHosts(store.webHostOf(widget.site.id)),
        ...CookieSync.relatedHosts(curHost),
      }..removeWhere((h) => h.isEmpty || isOAuthHost(h));
      final cookies = await CookieSync.collectCookies(hosts);
      // 新版登录体系：刷新 Cookie（Path 受限，要单独按路径读）
      final refreshByHost = await CookieSync.collectRefreshCookies(hosts);
      final refreshToken =
          refreshByHost.values.isNotEmpty ? refreshByHost.values.first : '';
      if (refreshToken.isNotEmpty) {
        await store.setRefreshToken(widget.site.id, refreshToken);
      }
      if (cookies.isEmpty && refreshToken.isEmpty) {
        toast('未读取到 Cookie，请确认已在页面内完成登录');
        return;
      }
      if (silent &&
          refreshToken.isEmpty &&
          !CookieSync.hasSessionCookie(cookies)) {
        return;
      }
      final header = CookieSync.toHeader(cookies);
      if (!mounted) return;
      await store.setCookie(widget.site.id, header);
      // 记录实际登录域名，后续签到/查余额前静默重同步时一并扫描
      if (curHost.isNotEmpty && curHost != siteHost) {
        await store.setWebHost(widget.site.id, curHost);
      }
      setState(() => _done = true);
      if (refreshToken.isNotEmpty) {
        _toast('已捕获登录态（新版登录体系，将使用令牌鉴权）');
      } else {
        final sessionNames =
            cookies.keys.where(CookieSync.isSessionCookieName).join('、');
        _toast('已捕获登录态（$sessionNames）');
      }
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      toast('捕获失败：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 接管 window.open 弹窗（站点"使用 Linux.do 登录"等 OAuth 流程），
  /// 用全屏对话框承载，避免弹窗被丢弃导致黑屏/卡死。
  Future<bool> _onCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction action,
  ) {
    if (!mounted) return Future.value(false);
    return showOAuthPopup(
      context,
      windowId: action.windowId,
      // 弹窗内回到本站登录后页面 → 自动关闭，父页面随即捕获
      isLoginComplete: (url) async =>
          webLoginLooksLoggedIn(url, widget.site.normalizedBaseUrl),
      onFinished: () async {
        // 弹窗关闭后刷新主窗口，触发登录态捕获
        await _controller?.reload();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('站点网页登录'),
        actions: [
          TextButton(
            onPressed: () => _capture(),
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
                // 允许 window.open 弹窗（"使用 Linux.do 登录"等 OAuth 流程）
                supportMultipleWindows: true,
              ),
              onWebViewCreated: (c) => _controller = c,
              onProgressChanged: (_, p) =>
                  setState(() => _progress = p),
              onLoadStop: (_, url) {
                if (_done) return;
                // WebUri 实现了 Uri 接口，可直接传入
                if (webLoginLooksLoggedIn(
                    url, widget.site.normalizedBaseUrl)) {
                  _capture();
                  return;
                }
                // 兜底：非常规登录后路径（同域名或异域名）——只要不在登录页
                // 且非 OAuth 中转，就静默尝试捕获（内部以会话 Cookie 为门槛）
                final u = url;
                if (u != null) {
                  final p = u.path;
                  if (u.host.isNotEmpty &&
                      !isOAuthHost(u.host) &&
                      p != '/login' &&
                      !p.startsWith('/login') &&
                      p != '/register' &&
                      !p.startsWith('/register')) {
                    _capture(silent: true);
                  }
                }
              },
              onCreateWindow: _onCreateWindow,
              // 渲染进程意外崩溃时重载，避免长期黑屏
              onRenderProcessGone: (c, _) => c.reload(),
            ),
          ),
        ],
      ),
    );
  }
}
