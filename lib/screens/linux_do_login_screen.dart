import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../widgets/oauth_popup.dart';

/// 是否已回到 linux.do 域名下（排除 GitHub 等 OAuth 中转页）。
/// 只有回到本站后才允许自动返回，避免跳转过程中误触。
bool linuxDoSettled(Uri? url) {
  if (url == null) return false;
  final h = url.host.toLowerCase();
  return h == 'linux.do' || h.endsWith('.linux.do');
}

/// L站（linux.do）登录：一次登录后，WebView 的 Cookie 全应用共享，
/// 各第三方站点的"使用 Linux.do 登录"即可免重复验证。
/// 登录态只存在于本机 WebView，不上传任何服务器。
///
/// 第三方授权（GitHub 等）可能以 window.open 弹窗形式打开，
/// 通过 [OAuthPopupDialog] 承载（与原版 App 一致的处理方式），
/// 避免弹窗被丢弃导致黑屏/卡死。
class LinuxDoLoginScreen extends StatefulWidget {
  const LinuxDoLoginScreen({super.key});

  @override
  State<LinuxDoLoginScreen> createState() => _LinuxDoLoginScreenState();
}

class _LinuxDoLoginScreenState extends State<LinuxDoLoginScreen> {
  static final WebUri _linuxDo = WebUri('https://linux.do');
  static const _sessionCookie = '_forum_session';

  InAppWebViewController? _controller;
  bool? _loggedIn;
  bool _announced = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  /// 是否已登录：检查 linux.do 的会话 Cookie。
  static Future<bool> isLoggedIn() async {
    try {
      final cookies =
          await CookieManager.instance().getCookies(url: _linuxDo);
      return cookies.any((c) => c.name == _sessionCookie);
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkStatus() async {
    final ok = await isLoggedIn();
    if (!mounted) return;
    setState(() => _loggedIn = ok);
    if (!ok || _announced) return;
    // 主窗口明确处于 GitHub 等第三方 OAuth 页时不提示，
    // 避免跳转过程中误报；回到 linux.do 本站后再提示。
    final url = await _controller?.getUrl();
    if (url != null && !linuxDoSettled(url)) return;
    _announced = true;
    if (!mounted) return;
    // 登录成功后不再自动关闭页面：用户可能还要在站内手动操作，
    // 完成后按返回键退出即可。
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          const SnackBar(content: Text('L站已登录，可继续浏览，完成后按返回退出')));
  }

  /// 接管 window.open 弹窗（GitHub 等第三方授权），用全屏对话框承载。
  Future<bool> _onCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction action,
  ) {
    if (!mounted) return Future.value(false);
    return showOAuthPopup(
      context,
      windowId: action.windowId,
      // 弹窗内回到 linux.do 且会话已建立 → 自动关闭弹窗
      isLoginComplete: (url) async =>
          linuxDoSettled(url) && await isLoggedIn(),
      onFinished: () async {
        // 弹窗关闭后刷新主窗口，重新检查登录态
        await _controller?.reload();
        _checkStatus();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('L站登录'),
        actions: [
          TextButton(
            onPressed: _checkStatus,
            child: const Text('检查状态',
                style: TextStyle(color: Colors.white)),
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
            color:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  _loggedIn == true
                      ? Icons.check_circle
                      : Icons.info_outline,
                  size: 16,
                  color: _loggedIn == true
                      ? Colors.green
                      : Colors.grey,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '在下方完成 linux.do 登录一次即可（支持 GitHub 等第三方登录，'
                    '授权页会以弹窗打开），之后各站点的"使用 Linux.do 登录"'
                    '不再重复验证。登录态仅存本机。登录成功后不会自动退出，'
                    '可继续浏览，完成后按返回退出。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: _linuxDo),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                // 允许 window.open 弹窗（GitHub 等 OAuth 授权页）
                supportMultipleWindows: true,
              ),
              onWebViewCreated: (c) => _controller = c,
              onProgressChanged: (_, p) =>
                  setState(() => _progress = p),
              onLoadStop: (_, __) => _checkStatus(),
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
