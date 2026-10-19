import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// L站（linux.do）登录：一次登录后，WebView 的 Cookie 全应用共享，
/// 各第三方站点的"使用 Linux.do 登录"即可免重复验证。
/// 登录态只存在于本机 WebView，不上传任何服务器。
class LinuxDoLoginScreen extends StatefulWidget {
  const LinuxDoLoginScreen({super.key});

  @override
  State<LinuxDoLoginScreen> createState() => _LinuxDoLoginScreenState();
}

class _LinuxDoLoginScreenState extends State<LinuxDoLoginScreen> {
  static final WebUri _linuxDo = WebUri('https://linux.do');
  static const _sessionCookie = '_forum_session';

  bool? _loggedIn;
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
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('L站已登录')));
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop(true);
    }
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
                    '在下方完成 linux.do 登录一次即可，之后各站点'
                    '的"使用 Linux.do 登录"不再重复验证。登录态仅存本机。',
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
              ),
              onProgressChanged: (_, p) =>
                  setState(() => _progress = p),
              onLoadStop: (_, __) => _checkStatus(),
            ),
          ),
        ],
      ),
    );
  }
}
