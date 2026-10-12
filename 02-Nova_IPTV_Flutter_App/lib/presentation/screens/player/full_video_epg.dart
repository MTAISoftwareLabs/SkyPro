part of '../screens.dart';

// ---------------------------------------------------------------------------
// نماذج / خدمات EPG المختصر (Xtream Codes) لعرض البرنامج الحالي/التالي في الهيدر
// ---------------------------------------------------------------------------

class EpgProgram {
  final String title;
  final DateTime start;
  final DateTime end;

  EpgProgram({required this.title, required this.start, required this.end});
}

class XtreamEpgService {
  final Dio _dio;

  XtreamEpgService(this._dio);

  static DateTime? parseXtreamDatePublic(dynamic v) => _parseXtreamDate(v);

  static String decodeEpgTitlePublic(String raw) => decodeEpgTitle(raw);

  static DateTime? _parseXtreamDate(dynamic v) {
    if (v == null) return null;
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        v * 1000,
        isUtc: true,
      ).toLocal();
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    final asInt = int.tryParse(s);
    if (asInt != null && s.length >= 9) {
      return DateTime.fromMillisecondsSinceEpoch(
        asInt * 1000,
        isUtc: true,
      ).toLocal();
    }

    final normalized =
        s.contains(' ') && !s.contains('T') ? s.replaceFirst(' ', 'T') : s;
    try {
      return DateTime.parse(normalized).toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<List<EpgProgram>> getShortEpg({
    required String baseUrl,
    required String username,
    required String password,
    required String streamId,
    int limit = 10,
  }) async {
    final normalizedBaseUrl =
        baseUrl.startsWith('http://') || baseUrl.startsWith('https://')
            ? baseUrl
            : 'http://$baseUrl';
    final uri = Uri.parse(normalizedBaseUrl);
    final base = '${uri.scheme}://${uri.authority}';
    final url = '$base/player_api.php';

    final response = await _dio.get(
      url,
      queryParameters: <String, dynamic>{
        'username': username,
        'password': password,
        'action': 'get_short_epg',
        'stream_id': streamId,
        'limit': limit,
      },
    );

    final data = response.data;
    if (data == null) return const [];

    List<dynamic> items = const [];
    if (data is List) {
      items = data;
    } else if (data is Map) {
      final listings = data['epg_listings'];
      if (listings is List) {
        items = listings;
      } else if (listings is Map) {
        items = listings.values.toList();
      }
    }
    if (items.isEmpty) return const [];

    final result = <EpgProgram>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final titleRaw = (item['title'] ??
              item['name'] ??
              item['programme'] ??
              item['program'] ??
              '')
          .toString();
      final start = _parseXtreamDate(
        item['start_timestamp'] ?? item['start'],
      );
      final end = _parseXtreamDate(
        item['stop_timestamp'] ?? item['end'] ?? item['stop'],
      );
      if (start == null || end == null) continue;

      final decodedTitle = decodeEpgTitle(titleRaw);
      // لا نعرض سطراً بعنوان فارغ/وهمي — نحتفظ بالأوقات فقط عبر UI عندما يلزم.
      result.add(EpgProgram(title: decodedTitle, start: start, end: end));
    }

    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }
}
