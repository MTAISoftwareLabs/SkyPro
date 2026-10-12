import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

/// أعداد الفئات فقط (خريطة صغيرة) — بدون كتالوج كامل.
class CatalogCategoryCountsStore {
  CatalogCategoryCountsStore._();

  static const _moviesPrefix = 'cat_counts_movies_v1_';
  static const _seriesPrefix = 'cat_counts_series_v1_';

  static String _safe(String userKey) =>
      userKey.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  static Map<String, int> readMovies(String userKey) =>
      _read('$_moviesPrefix${_safe(userKey)}');

  static Map<String, int> readSeries(String userKey) =>
      _read('$_seriesPrefix${_safe(userKey)}');

  static void writeMovies(String userKey, Map<String, int> counts) =>
      _write('$_moviesPrefix${_safe(userKey)}', counts);

  static void writeSeries(String userKey, Map<String, int> counts) =>
      _write('$_seriesPrefix${_safe(userKey)}', counts);

  static Map<String, int> _read(String key) {
    if (key.endsWith('_')) return const {};
    try {
      final raw = GetStorage().read(key);
      if (raw is Map) {
        final out = <String, int>{};
        raw.forEach((k, v) {
          final id = k?.toString() ?? '';
          if (id.isEmpty) return;
          final n = v is int ? v : int.tryParse('$v');
          if (n == null || n <= 0) return;
          out[id] = n;
        });
        return out;
      }
    } catch (_) {}
    return const {};
  }

  static void _write(String key, Map<String, int> counts) {
    if (key.endsWith('_') || counts.isEmpty) return;
    try {
      GetStorage().write(key, Map<String, int>.from(counts));
    } catch (_) {}
  }

  static void clearAll() {
    try {
      final box = GetStorage();
      for (final raw in box.getKeys()) {
        final k = raw.toString();
        if (k.startsWith(_moviesPrefix) || k.startsWith(_seriesPrefix)) {
          box.remove(k);
        }
      }
    } catch (_) {}
  }
}

class CatalogCountsTick extends ChangeNotifier {
  void ping() {
    notifyListeners();
  }
}
