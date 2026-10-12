import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'home_recent_parser.dart';

/// طلب خفيف يُرسل للـ isolate — بدون نقل JSON ضخم عبر الـ main thread.
@immutable
class HomeRecentIsolateRequest {
  const HomeRecentIsolateRequest({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.action,
    required this.idKey,
    required this.limit,
  });

  final String serverUrl;
  final String username;
  final String password;
  final String action;
  final String idKey;
  final int limit;
}

/// يبني رابط player_api.php بنفس منطق تسجيل الدخول.
Uri buildPlayerApiUri({
  required String serverUrl,
  required String username,
  required String password,
  required String action,
}) {
  final clean = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final endpoint =
      clean.endsWith('player_api.php') ? clean : '$clean/player_api.php';
  return Uri.parse(endpoint).replace(
    queryParameters: {
      'username': username,
      'password': password,
      'action': action,
    },
  );
}

/// شبكة + استخراج أول [limit] عناصر داخل isolate.
Future<List<Map<String, dynamic>>> fetchHomeRecentMapsViaIsolate(
  HomeRecentIsolateRequest req,
) {
  return Isolate.run(() => _fetchAndPickInIsolate(req));
}

Future<List<Map<String, dynamic>>> _fetchAndPickInIsolate(
  HomeRecentIsolateRequest req,
) async {
  if (req.limit <= 0) return const [];

  final client = HttpClient();
  client.autoUncompress = true;
  client.connectionTimeout = const Duration(seconds: 15);
  client.badCertificateCallback = (cert, host, port) => true;

  try {
    final uri = buildPlayerApiUri(
      serverUrl: req.serverUrl,
      username: req.username,
      password: req.password,
      action: req.action,
    );

    final httpRequest = await client.getUrl(uri);
    httpRequest.headers.set('Accept', 'application/json, text/plain, */*');
    httpRequest.headers.set('Accept-Encoding', 'gzip, deflate');
    httpRequest.headers.set(
      'User-Agent',
      'VLC/3.0.20 LibVLC/3.0.20',
    );
    httpRequest.headers.set('Connection', 'close');

    final response = await httpRequest.close().timeout(
      const Duration(seconds: 90),
    );
    if (response.statusCode != 200) {
      await response.drain<void>();
      return const [];
    }

    final scanner = _StreamingJsonArrayScanner(
      idKey: req.idKey,
      limit: req.limit,
    );

    await for (final chunk in response.timeout(const Duration(seconds: 90))) {
      scanner.addBytes(chunk);
      if (scanner.isComplete) break;
    }

    if (scanner.results.isNotEmpty) return scanner.results;

    final raw = scanner.fullText.trim();
    if (raw.isEmpty) return const [];
    return _parseFullBodyFallback(raw, req.idKey, req.limit);
  } catch (_) {
    return const [];
  } finally {
    client.close(force: true);
  }
}

List<Map<String, dynamic>> _parseFullBodyFallback(
  String raw,
  String idKey,
  int limit,
) {
  final cleaned = raw.replaceFirst('\uFEFF', '').trim();
  if (cleaned.isEmpty) return const [];

  if (idKey == 'stream_id') {
    return parseHomeRecentMovieMaps([cleaned, limit]);
  }
  if (idKey == 'series_id') {
    return parseHomeRecentSeriesMaps([cleaned, limit]);
  }

  try {
    final decoded = jsonDecode(cleaned);
    if (decoded is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      if (!_hasValidId(map, idKey)) continue;
      out.add(map);
      if (out.length >= limit) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

bool _hasValidId(Map<String, dynamic> map, String idKey) {
  if ((map[idKey]?.toString() ?? '').trim().isNotEmpty) return true;
  if ((map['num']?.toString() ?? '').trim().isNotEmpty) return true;
  if (idKey == 'stream_id' &&
      (map['stream_id'] ?? map['id'])?.toString().trim().isNotEmpty == true) {
    return true;
  }
  if (idKey == 'series_id' &&
      (map['series_id'] ?? map['id'])?.toString().trim().isNotEmpty == true) {
    return true;
  }
  return false;
}

class _StreamingJsonArrayScanner {
  _StreamingJsonArrayScanner({
    required this.idKey,
    required this.limit,
  });

  final String idKey;
  final int limit;

  final List<Map<String, dynamic>> results = [];
  final StringBuffer _buffer = StringBuffer();
  bool _arrayStarted = false;

  bool get isComplete => results.length >= limit;
  String get fullText => _buffer.toString();

  void addBytes(List<int> bytes) {
    if (isComplete || bytes.isEmpty) return;
    addChunk(utf8.decode(bytes, allowMalformed: true));
  }

  void addChunk(String chunk) {
    if (isComplete || chunk.isEmpty) return;
    _buffer.write(chunk);
    _drain();
  }

  void _drain() {
    var data = _buffer.toString().replaceFirst('\uFEFF', '');
    if (data.isEmpty || isComplete) return;

    if (!_arrayStarted) {
      final start = data.indexOf('[');
      if (start < 0) return;
      _arrayStarted = true;
      data = data.substring(start + 1);
    }

    while (!isComplete && data.isNotEmpty) {
      final step = _consumeNextObject(data);
      if (step == null) {
        _buffer.clear();
        _buffer.write(data);
        return;
      }
      data = data.substring(step.consumed);

      if (step.map != null && _hasValidId(step.map!, idKey)) {
        results.add(step.map!);
      }
    }

    _buffer.clear();
    if (!isComplete && data.isNotEmpty) {
      _buffer.write(data);
    }
  }
}

class _ScanStep {
  const _ScanStep({required this.consumed, this.map});

  final int consumed;
  final Map<String, dynamic>? map;
}

_ScanStep? _consumeNextObject(String data) {
  var i = 0;
  final len = data.length;

  while (i < len) {
    final c = data[i];
    if (c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == ',') {
      i++;
      continue;
    }
    break;
  }
  if (i >= len) {
    return const _ScanStep(consumed: 0);
  }
  if (data[i] == ']') {
    return _ScanStep(consumed: len - i);
  }
  if (data[i] != '{') {
    return _ScanStep(consumed: i + 1);
  }

  final start = i;
  var depth = 0;
  var inString = false;
  var escape = false;

  for (; i < len; i++) {
    final c = data[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (inString && c == r'\') {
      escape = true;
      continue;
    }
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        i++;
        break;
      }
    }
  }

  if (depth != 0) return null;

  final snippet = data.substring(start, i);
  Map<String, dynamic>? map;
  try {
    final decoded = jsonDecode(snippet);
    if (decoded is Map) {
      map = Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}

  return _ScanStep(consumed: i, map: map);
}
