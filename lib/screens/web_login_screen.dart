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
/// 且进入 console / dashboard / 首页等登录后页面。
bool webLoginLooksLoggedIn(Uri? url, String siteBaseUrl) {
  if (url == null) return false;
  final siteHost = Uri.tryParse(siteBaseUrl)?.host ?? '';
  if (siteHost.isEmpty || url.host != siteHost) return false;
  final p = url.path;
  return p.startsWith('/console') ||
      p.startsWith('/dashboard') ||
      p == '/' ||
      p.isEmpty;
}

/// 已知的登录页路径：新版 NewAPI 前端用 /sign-in，经典前端用 /login。
/// 写错路径在部分站点上不是 404，而是连接直接被关（ERR_CONNECTION_CLOSED）。
const List<String> kLoginPaths = ['/sign-in', '/login'];

/// 登录页候选顺序：记住的可用路径排第一，其余按默认顺序补齐。
List<String> loginPathCandidates(String remembered) {
  return <String>[
    if (kLoginPaths.contains(remembered)) remembered,
    ...kLoginPaths.where((p) => p != remembered),
  ];
}

/// 是否是登录/注册类页面（在这些页面上不做静默捕获，避免误判）。
bool isAuthPagePath(String path) {
  for (final p in const ['/login', '/sign-in', '/register', '/sign-up']) {
    if (path == p || path.startsWith('$p/')) return true;
  }
  return false;
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

  /// 登录页候选（记住的可用路径排第一）与当前下标。
  List<String> _candidates = List.of(kLoginPaths);
  int _candIdx = 0;

  /// 两个候选都加载失败时的错误说明（显示兜底横幅）。
  String? _loadError;

  /// 加载序号：页面探测等异步动作靠它丢弃过期结果。
  int _loadSeq = 0;

  String get _currentPath => _candidates[_candIdx];
  String get _initialUrl =>
      '${widget.site.normalizedBaseUrl}${_candidates.first}';

  @override
  void initState() {
    super.initState();
    try {
      final store = context.read<SiteStore>();
      _candidates = loginPathCandidates(store.loginPathOf(widget.site.id));
    } catch (_) {
      _candidates = List.of(kLoginPaths);
    }
  }

  /// 加载第 [idx] 个候选登录页。
  void _loadPath(int idx) {
    if (idx < 0 || idx >= _candidates.length) return;
    setState(() {
      _candIdx = idx;
      _loadError = null;
      _loadSeq++;
    });
    _controller?.loadUrl(
      urlRequest: URLRequest(
          url: WebUri('${widget.site.normalizedBaseUrl}${_candidates[idx]}')),
    );
  }

  /// 失败事件是否针对当前候选登录页：同域名的旧页面迟到事件、
  /// 以及用户手动打开的首页等非登录页，都不应触发自动切换。
  bool _isCurrentCandidateFailure(WebUri url) {
    final siteHost =
        Uri.tryParse(widget.site.normalizedBaseUrl)?.host ?? '';
    if (url.host.isNotEmpty && siteHost.isNotEmpty && url.host != siteHost) {
      return false;
    }
    var p = url.path;
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p == _currentPath || p.isEmpty;
  }

  /// 主框架加载失败（连接被关/HTTP 错误）：自动换下一个候选登录页；
  /// 候选都试完则显示错误横幅，让用户手动切换或重试。
  void _onMainFrameFailure(String desc) {
    if (_done || !mounted) return;
    if (_candIdx + 1 < _candidates.length) {
      _toast('登录页 $_currentPath 打不开，自动切换到 ${_candidates[_candIdx + 1]}');
      _loadPath(_candIdx + 1);
    } else {
      setState(() => _loadError = desc);
    }
  }

  /// 页面加载完后探测是否为真正的登录页：SPA 在错误路径上也返回 200，
  /// 但渲染的是 404 页（没有密码框）。探到密码框 → 记住该路径下次直达；
  /// 明确是 404 且还有候选 → 自动切换。
  Future<void> _probeLoginForm() async {
    final seq = _loadSeq;
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted || _done || seq != _loadSeq) return;
    final c = _controller;
    if (c == null) return;
    try {
      final r = await c.evaluateJavascript(source: '''
(function(){try{
  var pw=document.querySelector('input[type="password"]');
  var t=document.body?document.body.innerText||'':'';
  var nf=/404|not found|页面不存在|找不到页面/i.test(t.slice(0,1500));
  return (pw?'pw':'nopw')+','+(nf?'nf':'ok');
}catch(e){return 'err';}})()
''');
      if (!mounted || _done || seq != _loadSeq) return;
      final s = '$r';
      if (s.contains('pw')) {
        await context
            .read<SiteStore>()
            .setLoginPath(widget.site.id, _currentPath);
      } else if (s.contains('nf') && _candIdx + 1 < _candidates.length) {
        _toast('$_currentPath 不是本站登录页，自动切换到 ${_candidates[_candIdx + 1]}');
        _loadPath(_candIdx + 1);
      }
    } catch (_) {
      // JS 探测失败不影响手动登录
    }
  }

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
              'Cookie 只保存在本机安全存储。'
              '登录页地址有 /sign-in 与 /login 两种，打不开会自动切换，也可在下方手动切换。',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _candidates.length; i++)
                  ActionChip(
                    avatar: _candIdx == i
                        ? const Icon(Icons.check, size: 14)
                        : null,
                    label: Text('登录页 ${_candidates[i]}',
                        style: const TextStyle(fontSize: 11)),
                    onPressed: () => _loadPath(i),
                  ),
                ActionChip(
                  label:
                      const Text('站点首页', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    setState(() {
                      _loadError = null;
                      _loadSeq++;
                    });
                    _controller?.loadUrl(
                        urlRequest: URLRequest(
                            url: WebUri(
                                '${widget.site.normalizedBaseUrl}/')));
                  },
                ),
                ActionChip(
                  label: const Text('刷新', style: TextStyle(fontSize: 11)),
                  onPressed: () => _controller?.reload(),
                ),
              ],
            ),
          ),
          if (_loadError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '页面加载失败：$_loadError\n'
                      '可点上方按钮换一个登录页地址，或检查网络后重试。',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _loadPath(_candIdx),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_initialUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                // 允许 window.open 弹窗（"使用 Linux.do 登录"等 OAuth 流程）
                supportMultipleWindows: true,
              ),
              onWebViewCreated: (c) {
                _controller = c;
                // 控制器就绪前用户已手动切换过候选 → 补加载
                if (_candIdx != 0) _loadPath(_candIdx);
              },
              onProgressChanged: (_, p) =>
                  setState(() => _progress = p),
              onLoadStart: (_, url) {
                _loadSeq++;
                if (_loadError != null && mounted) {
                  setState(() => _loadError = null);
                }
              },
              // 主框架网络失败（如 ERR_CONNECTION_CLOSED）：自动换候选登录页
              onReceivedError: (_, request, error) {
                if (request.isForMainFrame == false) return;
                if (!_isCurrentCandidateFailure(request.url)) return;
                _onMainFrameFailure(error.description);
              },
              // 主框架 HTTP 错误（如写错登录路径返回 404）：同样自动换候选
              onReceivedHttpError: (_, request, errorResponse) {
                if (request.isForMainFrame == false) return;
                final code = errorResponse.statusCode ?? 0;
                if (code < 400) return;
                if (!_isCurrentCandidateFailure(request.url)) return;
                _onMainFrameFailure('HTTP $code');
              },
              onLoadStop: (_, url) {
                if (_done) return;
                // WebUri 实现了 Uri 接口，可直接传入
                if (webLoginLooksLoggedIn(
                    url, widget.site.normalizedBaseUrl)) {
                  _capture();
                  return;
                }
                final u = url;
                if (u != null) {
                  // 停在某个候选登录页上 → 探测它是不是真正的登录页
                  if (_candidates.contains(u.path)) {
                    _probeLoginForm();
                  }
                  // 兜底：非常规登录后路径（同域名或异域名）——只要不在登录页
                  // 且非 OAuth 中转，就静默尝试捕获（内部以会话 Cookie 为门槛）
                  if (u.host.isNotEmpty &&
                      !isOAuthHost(u.host) &&
                      !isAuthPagePath(u.path)) {
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
