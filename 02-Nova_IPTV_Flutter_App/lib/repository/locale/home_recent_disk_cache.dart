import 'package:get_storage/get_storage.dart';

import '../models/channel_movie.dart';
import '../models/channel_serie.dart';
import '../../helpers/home_perf_logger.dart';

/// قراءة/كتابة 13 فيلم + 13 مسلسل عشوائي (بصور) محلياً لعرض فوري على الرئيسية.
class HomeRecentDiskCache {
  HomeRecentDiskCache._();

  static const _boxKey = 'home_recent_disk_v1';
  static final GetStorage _box = GetStorage();

  static Map<String, dynamic> _readAll() {
    final raw = _box.read(_boxKey);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  static ({List<ChannelMovie> movies, List<ChannelSerie> series})? _parseEntry(
    Object? raw,
  ) {
    if (raw is! Map) return null;
    try {
      final moviesJson = raw['movies'];
      final seriesJson = raw['series'];
      final movies =
          moviesJson is List
              ? moviesJson
                  .whereType<Map>()
                  .map(
                    (e) => ChannelMovie.fromJson(Map<String, dynamic>.from(e)),
                  )
                  .toList()
              : <ChannelMovie>[];
      final series =
          seriesJson is List
              ? seriesJson
                  .whereType<Map>()
                  .map(
                    (e) => ChannelSerie.fromJson(Map<String, dynamic>.from(e)),
                  )
                  .toList()
              : <ChannelSerie>[];
      if (movies.isEmpty && series.isEmpty) return null;
      return (movies: movies, series: series);
    } catch (_) {
      return null;
    }
  }

  /// قراءة فورية (متزامنة) لعرض الكاش قبل أول إطار.
  static ({List<ChannelMovie> movies, List<ChannelSerie> series})? readSync(
    String userKey,
  ) {
    if (userKey.isEmpty) return null;
    return _parseEntry(_readAll()[userKey]);
  }

  static Future<({List<ChannelMovie> movies, List<ChannelSerie> series})?>
  read(String userKey) async {
    return HomePerfLogger.timeAsync('home_disk_read', () async {
      return readSync(userKey);
    });
  }

  static Future<void> write(
    String userKey, {
    required List<ChannelMovie> movies,
    required List<ChannelSerie> series,
  }) async {
    await HomePerfLogger.timeAsync('home_disk_write', () async {
      final all = _readAll();
      all[userKey] = {
        'movies': movies.map((e) => e.toJson()).toList(),
        'series': series.map((e) => e.toJson()).toList(),
        'savedAt': DateTime.now().toIso8601String(),
      };
      await _box.write(_boxKey, all);
    });
  }

  static Future<void> clear(String userKey) async {
    final all = _readAll();
    if (!all.containsKey(userKey)) return;
    all.remove(userKey);
    if (all.isEmpty) {
      await _box.remove(_boxKey);
    } else {
      await _box.write(_boxKey, all);
    }
  }

  static Future<void> clearAll() async {
    await _box.remove(_boxKey);
  }
}
