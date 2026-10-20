import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// OAuth 弹窗：承载网页 `window.open` 打开的第三方授权页（如 GitHub 登录）。
///
/// 用法：父 WebView 设置 `supportMultipleWindows: true` 并在 `onCreateWindow`
/// 里 `showDialog(... OAuthPopupDialog(windowId: action.windowId ...) ...)`
/// 然后返回 true。
///
/// 关闭时机（按优先级）：
/// 1. 授权页自己调用 `window.close()` → [onCloseWindow]；
/// 2. 弹窗内检测到登录已完成（[isLoginComplete] 返回 true）→ 自动关闭；
/// 3. 用户点左上角关闭按钮手动关闭。
/// 关闭后都会回调 [onFinished]，父页面借此刷新主窗口并复查登录态。
class OAuthPopupDialog extends StatefulWidget {
  final int windowId;

  /// 弹窗内每次页面加载完成后调用（参数为弹窗当前 URL），
  /// 返回 true 表示登录已完成、可以关弹窗。
  /// 不需要此行为时传 null（只靠 window.close / 手动关闭）。
  final Future<bool> Function(WebUri? url)? isLoginComplete;

  /// 弹窗关闭后调用（无论何种关闭方式，只调用一次）。
  final Future<void> Function() onFinished;

  const OAuthPopupDialog({
    super.key,
    required this.windowId,
    this.isLoginComplete,
    required this.onFinished,
  });

  @override
  State<OAuthPopupDialog> createState() => _OAuthPopupDialogState();
}

class _OAuthPopupDialogState extends State<OAuthPopupDialog> {
  bool _closed = false;

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    if (mounted) Navigator.of(context).pop();
    await widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('授权登录'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
        ),
        body: InAppWebView(
          windowId: widget.windowId,
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
          ),
          onCloseWindow: (_) => _close(),
          onLoadStop: (_, url) async {
            final check = widget.isLoginComplete;
            if (check != null && await check(url)) _close();
          },
        ),
      ),
    );
  }
}

/// 在父 WebView 的 `onCreateWindow` 里调用：弹出 [OAuthPopupDialog] 承载新窗口。
/// 返回 true 表示已接管（对应原版 App 的行为）。
Future<bool> showOAuthPopup(
  BuildContext context, {
  required int windowId,
  Future<bool> Function(WebUri? url)? isLoginComplete,
  required Future<void> Function() onFinished,
}) async {
  unawaited(showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => OAuthPopupDialog(
      windowId: windowId,
      isLoginComplete: isLoginComplete,
      onFinished: onFinished,
    ),
  ));
  return true;
}
