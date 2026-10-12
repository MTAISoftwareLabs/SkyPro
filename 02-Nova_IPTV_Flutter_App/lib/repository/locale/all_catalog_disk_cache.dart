import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/channel_movie.dart';
import '../models/channel_serie.dart';
import '../../helpers/home_perf_logger.dart';

/// كاش قرص لكتالوج All (أفلام/مسلسلات) — يفتح All فوراً في الزيارات التالية.
/// v2: بدون فرز newest عند الكتابة (v1 كان يُحفظ مرتّباً كأحدث).
class AllCatalogDiskCache {
  AllCatalogDiskCache._();

  static const _ttl = Duration(days: 30);
  static const _dirName = 'all_catalog_v2';
  static const _legacyDirNames = ['all_catalog_v1'];

  static Future<Directory> _dir() async {
    final root = await getApplicationSupportDirectory();
    final d = Directory('${root.path}/$_dirName');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  static Future<void> _purgeLegacyDirs() async {
    try {
      final root = await getApplicationSupportDirectory();
      for (final name in _legacyDirNames) {
        final d = Directory('${root.path}/$name');
        if (await d.exists()) {
          await d.delete(recursive: true);
        }
      }
    } catch (_) {}
  }

  static String _safeKey(String userKey) =>
      userKey.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  static Future<File> _file(String userKey, String kind) async {
    final d = await _dir();
    return File('${d.path}/${_safeKey(userKey)}_$kind.json');
  }

  static Future<List<ChannelMovie>?> readMovies(String userKey) async {
    if (userKey.isEmpty) return null;
    unawaited(_purgeLegacyDirs());
    return HomePerfLogger.timeAsync('all_disk_read_movies', () async {
      try {
        final f = await _file(userKey, 'movies');
        if (!await f.exists()) return null;
        final st = await f.stat();
        if (DateTime.now().difference(st.modified) > _ttl) return null;
        final raw = await f.readAsString();
        if (raw.isEmpty) return null;
        final list = await Isolate.run(() {
          final decoded = jsonDecode(raw);
          if (decoded is! List) return <ChannelMovie>[];
          return decoded
              .whereType<Map>()
              .map(
                (e) => ChannelMovie.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList(growable: false);
        });
        if (list.isEmpty) return null;
        return list;
      } catch (e) {
        if (kDebugMode) debugPrint('AllCatalogDiskCache.readMovies: $e');
        return null;
      }
    });
  }

  static Future<List<ChannelSerie>?> readSeries(String userKey) async {
    if (userKey.isEmpty) return null;
    unawaited(_purgeLegacyDirs());
    return HomePerfLogger.timeAsync('all_disk_read_series', () async {
      try {
        final f = await _file(userKey, 'series');
        if (!await f.exists()) return null;
        final st = await f.stat();
        if (DateTime.now().difference(st.modified) > _ttl) return null;
        final raw = await f.readAsString();
        if (raw.isEmpty) return null;
        final list = await Isolate.run(() {
          final decoded = jsonDecode(raw);
          if (decoded is! List) return <ChannelSerie>[];
          return decoded
              .whereType<Map>()
              .map(
                (e) => ChannelSerie.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList(growable: false);
        });
        if (list.isEmpty) return null;
        return list;
      } catch (e) {
        if (kDebugMode) debugPrint('AllCatalogDiskCache.readSeries: $e');
        return null;
      }
    });
  }

  static Future<void> writeMovies(
    String userKey,
    List<ChannelMovie> list,
  ) async {
    if (userKey.isEmpty || list.isEmpty) return;
    unawaited(_writeMoviesImpl(userKey, list));
  }

  static Future<void> writeSeries(
    String userKey,
    List<ChannelSerie> list,
  ) async {
    if (userKey.isEmpty || list.isEmpty) return;
    unawaited(_writeSeriesImpl(userKey, list));
  }

  static Future<void> _writeMoviesImpl(
    String userKey,
    List<ChannelMovie> list,
  ) async {
    await HomePerfLogger.timeAsync('all_disk_write_movies', () async {
      try {
        final maps = list.map((e) => e.toJson()).toList(growable: false);
        final encoded = await Isolate.run(() => jsonEncode(maps));
        final f = await _file(userKey, 'movies');
        await f.writeAsString(encoded, flush: true);
      } catch (e) {
        if (kDebugMode) debugPrint('AllCatalogDiskCache.writeMovies: $e');
      }
    });
  }

  static Future<void> _writeSeriesImpl(
    String userKey,
    List<ChannelSerie> list,
  ) async {
    await HomePerfLogger.timeAsync('all_disk_write_series', () async {
      try {
        final maps = list.map((e) => e.toJson()).toList(growable: false);
        final encoded = await Isolate.run(() => jsonEncode(maps));
        final f = await _file(userKey, 'series');
        await f.writeAsString(encoded, flush: true);
      } catch (e) {
        if (kDebugMode) debugPrint('AllCatalogDiskCache.writeSeries: $e');
      }
    });
  }

  static Future<void> clearAll() async {
    try {
      final root = await getApplicationSupportDirectory();
      for (final name in [_dirName, ..._legacyDirNames]) {
        final d = Directory('${root.path}/$name');
        if (await d.exists()) {
          await d.delete(recursive: true);
        }
      }
    } catch (_) {}
  }
}
