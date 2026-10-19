import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/site.dart';
import 'site_store.dart';

/// 网关日志条目。
class GatewayLog {
  final DateTime time;
  final String model;
  final String siteName;
  final bool stream;
  final int status;
  final int ms;
  final int promptTokens;
  final int completionTokens;
  final String? error;

  GatewayLog({
    required this.time,
    required this.model,
    required this.siteName,
    required this.stream,
    required this.status,
    required this.ms,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'model': model,
        'siteName': siteName,
        'stream': stream,
        'status': status,
        'ms': ms,
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'error': error,
      };

  factory GatewayLog.fromJson(Map<String, dynamic> json) => GatewayLog(
        time: DateTime.tryParse((json['time'] ?? '') as String) ??
            DateTime.now(),
        model: '${json['model'] ?? ''}',
        siteName: '${json['siteName'] ?? ''}',
        stream: json['stream'] == true,
        status: (json['status'] as int?) ?? 0,
        ms: (json['ms'] as int?) ?? 0,
        promptTokens: (json['promptTokens'] as int?) ?? 0,
        completionTokens: (json['completionTokens'] as int?) ?? 0,
        error: json['error'] as String?,
      );
}

/// 本地 API 网关：在本机（可含局域网）提供 OpenAI 兼容入口，
/// 按模型名路由到用户自己的站点。所有上游请求直连用户站点。
class GatewayService extends ChangeNotifier {
  static const _secure = FlutterSecureStorage();
  static const _kPort = 'gateway_port';
  static const _kBindLan = 'gateway_bind_lan';
  static const _kKey = 'gateway_api_key';
  static const _kLogs = 'gateway_logs_v1';
  static const _maxLogs = 200;

  final http.Client _http = http.Client();

  bool _running = false;
  HttpServer? _server;
  int _port = 8080;
  bool _bindLan = false;
  String _apiKey = '';

  final List<GatewayLog> _logs = [];
  // 模型 -> 可用站点（启用且有 Key），/v1/models 聚合时刷新
  final Map<String, List<Site>> _modelMap = {};

  bool get running => _running;
  int get port => _port;
  bool get bindLan => _bindLan;
  String get apiKey => _apiKey;
  int get actualPort => _server?.port ?? _port;
  String get listenAddress =>
      _bindLan ? '0.0.0.0' : '127.0.0.1';
  List<GatewayLog> get logs => List.unmodifiable(_logs);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _port = prefs.getInt(_kPort) ?? 8080;
    _bindLan = prefs.getBool(_kBindLan) ?? false;
    _apiKey = await _secure.read(key: _kKey) ?? '';
    final raw = prefs.getString(_kLogs);
    _logs.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list.reversed) {
          if (e is Map) {
            _logs.add(GatewayLog.fromJson(
                Map<String, dynamic>.from(e)));
          }
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> saveConfig({int? port, bool? bindLan}) async {
    final prefs = await SharedPreferences.getInstance();
    if (port != null) {
      _port = port.clamp(1024, 65535);
      await prefs.setInt(_kPort, _port);
    }
    if (bindLan != null) {
      _bindLan = bindLan;
      await prefs.setBool(_kBindLan, _bindLan);
    }
    notifyListeners();
  }

  /// 生成新的网关密钥（Bearer <key>）。
  Future<String> regenerateKey() async {
    final rnd = Random.secure();
    final bytes = List<int>.generate(24, (_) => rnd.nextInt(256));
    _apiKey =
        'sm-${base64UrlEncode(bytes).replaceAll('=', '')}';
    await _secure.write(key: _kKey, value: _apiKey);
    notifyListeners();
    return _apiKey;
  }

  /// 构建请求处理器（供测试直接调用，无需绑定端口）。
  Handler buildHandler(SiteStore siteStore) {
    final router = Router()
      ..get('/v1/models', (Request req) => _handleModels(req, siteStore))
      ..post('/v1/chat/completions',
          (Request req) => _handleChat(req, siteStore));

    return const Pipeline()
        .addMiddleware(_authMiddleware)
        .addMiddleware(logRequests())
        .addHandler(router.call);
  }

  Future<void> start(SiteStore siteStore) async {
    if (_running) return;
    if (_apiKey.isEmpty) {
      await regenerateKey(); // 默认始终开启鉴权
    }
    final handler = buildHandler(siteStore);

    try {
      _server = await shelf_io.serve(
        handler,
        _bindLan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
        _port,
      );
    } on SocketException catch (e) {
      throw Exception('端口 $_port 启动失败：${e.message}');
    }
    _running = true;
    // 启动时预聚合一次模型
    unawaited(_refreshModelMap(siteStore));
    notifyListeners();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _running = false;
    notifyListeners();
  }

  Future<void> clearLogs() async {
    _logs.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLogs);
    notifyListeners();
  }

  // ---------- 内部 ----------

  Middleware get _authMiddleware => (Handler inner) {
        return (Request req) async {
          final auth = req.headers['authorization'] ?? '';
          if (auth != 'Bearer $_apiKey') {
            return Response(
              401,
              body: jsonEncode({
                'error': {
                  'message': 'Invalid API key',
                  'type': 'invalid_request_error'
                }
              }),
              headers: {'Content-Type': 'application/json'},
            );
          }
          return inner(req);
        };
      };

  /// 聚合启用站点的模型列表，同时刷新路由表。
  Future<void> _refreshModelMap(SiteStore siteStore) async {
    _modelMap.clear();
    final sites =
        siteStore.sites.where((s) => s.enabled).toList();
    final futures = <Future>[];
    for (final s in sites) {
      final key = siteStore.apiKeyOf(s.id);
      if (key.isEmpty) continue;
      futures.add(_fetchSiteModels(s, key).then((models) {
        for (final m in models) {
          _modelMap.putIfAbsent(m, () => []).add(s);
        }
      }).catchError((_) {}));
    }
    await Future.wait(futures);
  }

  Future<List<String>> _fetchSiteModels(Site site, String key) async {
    final resp = await _http
        .get(
          Uri.parse('${site.normalizedBaseUrl}/v1/models'),
          headers: {'Authorization': 'Bearer $key'},
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return [];
    final body = jsonDecode(resp.body);
    final data = body is Map ? body['data'] as List? : null;
    if (data == null) return [];
    return data
        .whereType<Map>()
        .map((e) => '${e['id'] ?? ''}')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<Response> _handleModels(
      Request req, SiteStore siteStore) async {
    await _refreshModelMap(siteStore);
    final data = <Map<String, dynamic>>[];
    _modelMap.forEach((model, sites) {
      data.add({
        'id': model,
        'object': 'model',
        'created': 0,
        'owned_by': sites.map((s) => s.name).join(','),
      });
    });
    data.sort((a, b) =>
        (a['id'] as String).compareTo(b['id'] as String));
    return Response.ok(
      jsonEncode({'object': 'list', 'data': data}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _handleChat(
      Request req, SiteStore siteStore) async {
    final stopwatch = Stopwatch()..start();
    Map<String, dynamic> body;
    try {
      body =
          jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _err(400, 'Invalid JSON body', stopwatch, '', false);
    }
    final model = '${body['model'] ?? ''}';
    final stream = body['stream'] == true;
    if (model.isEmpty) {
      return _err(400, 'model is required', stopwatch, '', stream);
    }
    if (_modelMap.isEmpty) {
      await _refreshModelMap(siteStore);
    }
    final sites = _modelMap[model];
    if (sites == null || sites.isEmpty) {
      return _err(404, 'Model not found: $model', stopwatch, model,
          stream);
    }
    // 路由策略：首个可用站点
    final site = sites.first;
    final key = siteStore.apiKeyOf(site.id);

    if (stream) {
      return _forwardStream(req, site, key, body, model, stopwatch);
    }
    return _forwardOnce(site, key, body, model, stopwatch);
  }

  Future<Response> _forwardOnce(Site site, String key,
      Map<String, dynamic> body, String model, Stopwatch sw) async {
    http.Response upstream;
    try {
      upstream = await _http
          .post(
            Uri.parse(
                '${site.normalizedBaseUrl}/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $key',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      return _err(502, 'Upstream error: $e', sw, model, false,
          siteName: site.name);
    }
    final ms = sw.elapsedMilliseconds;
    int pt = 0, ct = 0;
    try {
      final j = jsonDecode(upstream.body) as Map<String, dynamic>;
      final u = j['usage'] as Map?;
      pt = (u?['prompt_tokens'] as int?) ?? 0;
      ct = (u?['completion_tokens'] as int?) ?? 0;
    } catch (_) {}
    _addLog(GatewayLog(
      time: DateTime.now(),
      model: model,
      siteName: site.name,
      stream: false,
      status: upstream.statusCode,
      ms: ms,
      promptTokens: pt,
      completionTokens: ct,
      error: upstream.statusCode == 200
          ? null
          : _short(upstream.body),
    ));
    return Response(
      upstream.statusCode,
      body: upstream.body,
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _forwardStream(Request req, Site site, String key,
      Map<String, dynamic> body, String model, Stopwatch sw) async {
    // 请求上游附带 usage，便于日志统计
    final upstreamBody = Map<String, dynamic>.from(body);
    upstreamBody['stream_options'] = {'include_usage': true};

    final clientReq = http.Request(
      'POST',
      Uri.parse('${site.normalizedBaseUrl}/v1/chat/completions'),
    );
    clientReq.headers['Content-Type'] = 'application/json';
    clientReq.headers['Authorization'] = 'Bearer $key';
    clientReq.headers['Accept'] = 'text/event-stream';
    clientReq.body = jsonEncode(upstreamBody);

    http.StreamedResponse upstream;
    try {
      upstream = await _http.send(clientReq);
    } catch (e) {
      return _err(502, 'Upstream error: $e', sw, model, true,
          siteName: site.name);
    }
    if (upstream.statusCode != 200) {
      final b = await upstream.stream.bytesToString();
      return _err(upstream.statusCode, _short(b), sw, model, true,
          siteName: site.name);
    }

    // 透传 SSE，同时嗅探 usage 做日志
    var pt = 0, ct = 0;
    StreamSubscription<String>? sub;
    final controller = StreamController<List<int>>(
      onCancel: () => sub?.cancel(),
    );
    sub = upstream.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.startsWith('data:')) {
          final d = line.substring(5).trim();
          if (d.startsWith('{') && d.contains('"usage"')) {
            try {
              final u =
                  (jsonDecode(d) as Map)['usage'] as Map?;
              pt = (u?['prompt_tokens'] as int?) ?? pt;
              ct = (u?['completion_tokens'] as int?) ?? ct;
            } catch (_) {}
          }
        }
        if (!controller.isClosed) {
          controller.add(utf8.encode('$line\n'));
        }
      },
      onError: (Object e) {
        if (!controller.isClosed) controller.addError(e);
      },
      onDone: () {
        _addLog(GatewayLog(
          time: DateTime.now(),
          model: model,
          siteName: site.name,
          stream: true,
          status: 200,
          ms: sw.elapsedMilliseconds,
          promptTokens: pt,
          completionTokens: ct,
        ));
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: true,
    );
    return Response.ok(
      controller.stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'X-Accel-Buffering': 'no',
      },
    );
  }

  Response _err(int status, String message, Stopwatch sw, String model,
      bool stream,
      {String siteName = ''}) {
    _addLog(GatewayLog(
      time: DateTime.now(),
      model: model,
      siteName: siteName,
      stream: stream,
      status: status,
      ms: sw.elapsedMilliseconds,
      error: message,
    ));
    return Response(
      status,
      body: jsonEncode({
        'error': {'message': message, 'type': 'invalid_request_error'}
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  void _addLog(GatewayLog log) {
    _logs.insert(0, log);
    if (_logs.length > _maxLogs) {
      _logs.removeRange(_maxLogs, _logs.length);
    }
    notifyListeners();
    unawaited(_persistLogs());
  }

  Future<void> _persistLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kLogs, jsonEncode(_logs.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  String _short(String s) {
    final b = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return b.length > 200 ? '${b.substring(0, 200)}…' : b;
  }
}
