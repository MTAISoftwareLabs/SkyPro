import 'dart:convert';

List<Map<String, dynamic>> parseHomeRecentMovieMaps(List<Object?> args) {
  return _parseHomeFastMaps(args, 'stream_id');
}

List<Map<String, dynamic>> parseHomeRecentSeriesMaps(List<Object?> args) {
  return _parseHomeFastMaps(args, 'series_id');
}

/// أحدث العناصر حسب last_modified / last_update / added — ثم قصّ إلى [limit].
List<Map<String, dynamic>> parseRecentlyAddedMovieMaps(List<Object?> args) {
  return _parseRecentlyAddedMaps(args, 'stream_id');
}

List<Map<String, dynamic>> parseRecentlyAddedSeriesMaps(List<Object?> args) {
  return _parseRecentlyAddedMaps(args, 'series_id');
}

/// أول [limit] عناصر صالحة — بدون ترتيب أو فلترة إضافية (أسرع تحميل).
List<Map<String, dynamic>> _parseHomeFastMaps(
  List<Object?> args,
  String idKey,
) {
  final raw = args[0];
  final limit = args[1] as int;
  if (limit <= 0) return const [];

  final List<dynamic> jsonList;
  if (raw is String) {
    if (raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    jsonList = decoded;
  } else if (raw is List) {
    jsonList = raw;
  } else {
    return const [];
  }

  if (jsonList.isEmpty) return const [];

  final out = <Map<String, dynamic>>[];
  for (final entry in jsonList) {
    if (entry is! Map) continue;
    final map = Map<String, dynamic>.from(entry);
    final id =
        (map[idKey] ?? map['num'] ?? map['id'])?.toString().trim() ?? '';
    if (id.isEmpty) continue;
    out.add(map);
    if (out.length >= limit) break;
  }
  return out;
}

List<Map<String, dynamic>> _parseRecentlyAddedMaps(
  List<Object?> args,
  String idKey,
) {
  final raw = args[0];
  final limit = args[1] as int;
  if (limit <= 0) return const [];

  final List<dynamic> jsonList;
  if (raw is String) {
    if (raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    jsonList = decoded;
  } else if (raw is List) {
    jsonList = raw;
  } else {
    return const [];
  }

  if (jsonList.isEmpty) return const [];

  final scored = <({Map<String, dynamic> map, int ts, String name})>[];
  var anyTs = false;
  for (final entry in jsonList) {
    if (entry is! Map) continue;
    final map = Map<String, dynamic>.from(entry);
    final id =
        (map[idKey] ?? map['num'] ?? map['id'])?.toString().trim() ?? '';
    if (id.isEmpty) continue;
    final ts = _recentlyAddedTimestamp(map);
    if (ts > 0) anyTs = true;
    final name = (map['name'] ?? '').toString().toLowerCase();
    scored.add((map: map, ts: ts, name: name));
  }
  if (scored.isEmpty) return const [];

  if (anyTs) {
    scored.sort((a, b) {
      final c = b.ts.compareTo(a.ts);
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });
  }
  // بدون timestamps: نحافظ على ترتيب السيرفر (غالباً الأحدث أولاً).

  final out = <Map<String, dynamic>>[];
  for (final row in scored) {
    out.add(row.map);
    if (out.length >= limit) break;
  }
  return out;
}

int _recentlyAddedTimestamp(Map<String, dynamic> map) {
  final raw = map['last_modified'] ?? map['last_update'] ?? map['added'];
  final v = int.tryParse(raw?.toString() ?? '') ?? 0;
  if (v > 0 && v < 100000000000) return v * 1000;
  return v;
}
