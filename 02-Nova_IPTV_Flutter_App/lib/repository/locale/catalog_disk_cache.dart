import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/category.dart';
import '../models/channel_live.dart';
import '../../helpers/home_perf_logger.dart';
import 'catalog_fingerprint.dart';

/// تخزين دائم للفئات وقنوات Live — لفتح التطبيق بدون إعادة تحميل كامل.
class CatalogDiskCache {
  CatalogDiskCache._();

  static const _dirName = 'catalog_disk_v1';
  static const kindLive = 'live';
  static const kindMovies = 'movies';
  static const kindSeries = 'series';

  static Future<Directory> _root() async {
    final support = await getApplicationSupportDirectory();
    final d = Directory('${support.path}/$_dirName');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  static String _safeKey(String userKey) =>
      userKey.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  static Future<File> _catsFile(String userKey, String kind) async {
    final d = await _root();
    return File('${d.path}/${_safeKey(userKey)}_${kind}_cats.json');
  }

  static Future<File> _metaFile(String userKey) async {
    final d = await _root();
    return File('${d.path}/${_safeKey(userKey)}_meta.json');
  }

  static Future<Directory> _liveDir(String userKey) async {
    final d = await _root();
    final live = Directory('${d.path}/live_${_safeKey(userKey)}');
    if (!await live.exists()) {
      await live.create(recursive: true);
    }
    return live;
  }

  static Future<File> _liveCatFile(String userKey, String catId) async {
    final d = await _liveDir(userKey);
    final safeCat = catId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File('${d.path}/$safeCat.json');
  }

  // ── Categories ──────────────────────────────────────────────

  static Future<List<CategoryModel>?> readCategories(
    String userKey,
    String kind,
  ) async {
    if (userKey.isEmpty) return null;
    try {
      final f = await _catsFile(userKey, kind);
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.isEmpty) return null;
      final list = await Isolate.run(() {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return <CategoryModel>[];
        return decoded
            .whereType<Map>()
            .map((e) => CategoryModel.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      });
      if (list.isEmpty) return null;
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('CatalogDiskCache.readCategories($kind): $e');
      return null;
    }
  }

  static Future<void> writeCategories(
    String userKey,
    String kind,
    List<CategoryModel> list,
  ) async {
    if (userKey.isEmpty || list.isEmpty) return;
    unawaited(_writeCategoriesImpl(userKey, kind, list));
  }

  static Future<void> _writeCategoriesImpl(
    String userKey,
    String kind,
    List<CategoryModel> list,
  ) async {
    await HomePerfLogger.timeAsync('catalog_disk_write_${kind}_cats', () async {
      try {
        final maps = list.map((e) => e.toJson()).toList(growable: false);
        final encoded = await Isolate.run(() => jsonEncode(maps));
        final f = await _catsFile(userKey, kind);
        await f.writeAsString(encoded, flush: true);
        await putFingerprint(userKey, '${kind}_cats', CatalogFingerprint.categories(list));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('CatalogDiskCache.writeCategories($kind): $e');
        }
      }
    });
  }

  // ── Live channels by category ───────────────────────────────

  static Future<List<ChannelLive>?> readLiveCategory(
    String userKey,
    String catId,
  ) async {
    if (userKey.isEmpty || catId.isEmpty) return null;
    try {
      final f = await _liveCatFile(userKey, catId);
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.isEmpty) return null;
      final list = await Isolate.run(() {
        final decoded = jsonDecode(raw);
        List? items;
        if (decoded is Map) {
          items = decoded['channels'] as List?;
        } else if (decoded is List) {
          items = decoded;
        }
        if (items == null) return <ChannelLive>[];
        return items
            .whereType<Map>()
            .map((e) => ChannelLive.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      });
      if (list.isEmpty) return null;
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('CatalogDiskCache.readLiveCategory: $e');
      return null;
    }
  }

  /// يحمّل كل فئات Live المخزّنة (للجلسة الباردة).
  static Future<Map<String, List<ChannelLive>>> readAllLive(
    String userKey,
  ) async {
    if (userKey.isEmpty) return const {};
    return HomePerfLogger.timeAsync('catalog_disk_read_all_live', () async {
      try {
        final d = await _liveDir(userKey);
        if (!await d.exists()) return const {};
        final out = <String, List<ChannelLive>>{};
        await for (final entity in d.list(followLinks: false)) {
          if (entity is! File || !entity.path.endsWith('.json')) continue;
          try {
            final raw = await entity.readAsString();
            if (raw.isEmpty) continue;
            final parsed = await Isolate.run(() {
              final decoded = jsonDecode(raw);
              String catId = '';
              List? items;
              if (decoded is Map) {
                catId = (decoded['category_id'] ?? '').toString().trim();
                items = decoded['channels'] as List?;
              } else if (decoded is List) {
                items = decoded;
              }
              if (items == null) return null;
              final list =
                  items
                      .whereType<Map>()
                      .map(
                        (e) =>
                            ChannelLive.fromJson(Map<String, dynamic>.from(e)),
                      )
                      .toList(growable: false);
              if (list.isEmpty) return null;
              if (catId.isEmpty) {
                catId = (list.first.categoryId ?? '').trim();
              }
              return (catId: catId, list: list);
            });
            if (parsed == null || parsed.catId.isEmpty) continue;
            out[parsed.catId] = parsed.list;
          } catch (_) {}
        }
        return out;
      } catch (e) {
        if (kDebugMode) debugPrint('CatalogDiskCache.readAllLive: $e');
        return const {};
      }
    });
  }

  static Future<void> writeLiveCategory(
    String userKey,
    String catId,
    List<ChannelLive> list,
  ) async {
    if (userKey.isEmpty || catId.isEmpty || list.isEmpty) return;
    unawaited(_writeLiveCategoryImpl(userKey, catId, list));
  }

  static Future<void> _writeLiveCategoryImpl(
    String userKey,
    String catId,
    List<ChannelLive> list,
  ) async {
    try {
      final maps = list.map((e) => e.toJson()).toList(growable: false);
      final payload = {'category_id': catId, 'channels': maps};
      final encoded = await Isolate.run(() => jsonEncode(payload));
      final f = await _liveCatFile(userKey, catId);
      await f.writeAsString(encoded, flush: true);
      await putFingerprint(
        userKey,
        'live:$catId',
        CatalogFingerprint.lives(list),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('CatalogDiskCache.writeLiveCategory: $e');
    }
  }

  static Future<void> removeLiveCategory(String userKey, String catId) async {
    if (userKey.isEmpty || catId.isEmpty) return;
    try {
      final f = await _liveCatFile(userKey, catId);
      if (await f.exists()) await f.delete();
      final fps = await readFingerprints(userKey);
      if (fps.remove('live:$catId') != null) {
        await writeFingerprints(userKey, fps);
      }
    } catch (_) {}
  }

  // ── Fingerprints ────────────────────────────────────────────

  static Future<Map<String, String>> readFingerprints(String userKey) async {
    if (userKey.isEmpty) return {};
    try {
      final f = await _metaFile(userKey);
      if (!await f.exists()) return {};
      final raw = await f.readAsString();
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        if (k is String && v != null) out[k] = v.toString();
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> writeFingerprints(
    String userKey,
    Map<String, String> fps,
  ) async {
    if (userKey.isEmpty) return;
    try {
      final f = await _metaFile(userKey);
      await f.writeAsString(jsonEncode(fps), flush: true);
    } catch (e) {
      if (kDebugMode) debugPrint('CatalogDiskCache.writeFingerprints: $e');
    }
  }

  static Future<void> putFingerprint(
    String userKey,
    String key,
    String value,
  ) async {
    if (userKey.isEmpty || key.isEmpty) return;
    final fps = await readFingerprints(userKey);
    if (fps[key] == value) return;
    fps[key] = value;
    await writeFingerprints(userKey, fps);
  }

  static Future<String?> getFingerprint(String userKey, String key) async {
    final fps = await readFingerprints(userKey);
    return fps[key];
  }

  static Future<void> clearAll() async {
    try {
      final support = await getApplicationSupportDirectory();
      final d = Directory('${support.path}/$_dirName');
      if (await d.exists()) {
        await d.delete(recursive: true);
      }
    } catch (_) {}
  }
}
