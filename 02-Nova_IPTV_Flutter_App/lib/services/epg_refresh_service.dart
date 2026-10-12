import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

import '../repository/api/api.dart';
import '../repository/models/category.dart';
import '../repository/models/channel_live.dart';
import '../repository/models/epg.dart';
import '../repository/models/user.dart';

/// تحديث دليل البرامج (EPG) من السيرفر وتخزينه محلياً للاستخدام السريع.
class EpgRefreshService {
  EpgRefreshService._();

  static const String kStorageEpgCache = 'epg_prefetch_cache_v1';
  static const int _legacyMaxStreams = 50;
  static const int _legacyMaxCategories = 6;
  static const int _legacyChannelsPerCategory = 12;
  static const int _prefetchConcurrency = 2;
  static const int _legacyConcurrency = 4;
  /// Hard cap for background warm — avoids OOM from huge GetStorage maps.
  static const int backgroundPrefetchMaxStreams = 12;
  static const int _maxCacheEntries = 40;

  static final GetStorage _box = GetStorage();
  static int _prefetchGen = 0;
  static Map<String, dynamic>? _memoryCache;

  static bool channelHasEpg(ChannelLive ch) {
    final e = ch.epgChannelId?.toString().trim() ?? '';
    if (e.isEmpty) return false;
    final lower = e.toLowerCase();
    return lower != 'null' && lower != '0' && lower != 'false';
  }

  static String? streamIdOf(ChannelLive ch) {
    final sid = ch.streamId?.trim() ?? '';
    if (sid.isEmpty || sid.toLowerCase() == 'null') return null;
    return sid;
  }

  static Set<String> streamIdsWithEpg(Iterable<ChannelLive> channels) {
    final out = <String>{};
    for (final ch in channels) {
      if (!channelHasEpg(ch)) continue;
      final sid = streamIdOf(ch);
      if (sid != null) out.add(sid);
    }
    return out;
  }

  /// Manual settings refresh (capped sample) — kept for Settings UI.
  static Future<EpgRefreshResult> refreshFromServer({
    required IpTvApi api,
    required UserModel user,
    required List<CategoryModel> categories,
    List<String> priorityStreamIds = const [],
    void Function(double progress)? onProgress,
  }) async {
    void report(double value) {
      onProgress?.call(value.clamp(0.0, 1.0));
    }

    report(0.02);

    if (_isPlaylistMode(user)) {
      report(1);
      return const EpgRefreshResult(
        successCount: 0,
        attemptedCount: 0,
        playlistMode: true,
      );
    }

    final streamIds = <String>{};
    for (final id in priorityStreamIds) {
      final t = id.trim();
      if (t.isNotEmpty && t.toLowerCase() != 'null') streamIds.add(t);
      if (streamIds.length >= _legacyMaxStreams) break;
    }

    final cats = categories.take(_legacyMaxCategories).toList();
    for (var c = 0; c < cats.length; c++) {
      if (streamIds.length >= _legacyMaxStreams) break;
      final catId = cats[c].categoryId?.trim() ?? '';
      if (catId.isEmpty) continue;
      try {
        final channels = await api.getLiveChannels(catId);
        for (final ch in channels.take(_legacyChannelsPerCategory)) {
          if (!channelHasEpg(ch)) continue;
          final sid = streamIdOf(ch);
          if (sid == null) continue;
          streamIds.add(sid);
          if (streamIds.length >= _legacyMaxStreams) break;
        }
      } catch (e) {
        debugPrint('EPG refresh category $catId failed: $e');
      }
      report(0.04 + ((c + 1) / (cats.isEmpty ? 1 : cats.length)) * 0.14);
    }

    if (streamIds.isEmpty) {
      report(1);
      return const EpgRefreshResult(successCount: 0, attemptedCount: 0);
    }

    return prefetchStreamIds(
      streamIds,
      concurrency: _legacyConcurrency,
      onProgress: (p) => report(0.18 + p * 0.82),
    );
  }

  /// Prefetch EPG for the given stream IDs (capped when [maxStreams] set).
  static Future<EpgRefreshResult> prefetchStreamIds(
    Set<String> streamIds, {
    int concurrency = _prefetchConcurrency,
    int? maxStreams,
    void Function(double progress)? onProgress,
    bool cancelPrevious = false,
  }) async {
    final gen = cancelPrevious ? ++_prefetchGen : _prefetchGen;
    void report(double value) => onProgress?.call(value.clamp(0.0, 1.0));

    var ids = streamIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
        .toList();
    final cap = maxStreams;
    if (cap != null && ids.length > cap) {
      ids = ids.take(cap).toList();
    }
    if (ids.isEmpty) {
      report(1);
      return const EpgRefreshResult(successCount: 0, attemptedCount: 0);
    }

    var success = 0;
    var processed = 0;
    final conc = concurrency.clamp(1, 4);
    final pendingWrites = <String, List<EpgModel>>{};

    for (var i = 0; i < ids.length; i += conc) {
      if (gen != _prefetchGen) {
        if (pendingWrites.isNotEmpty) {
          putCachedListingsBatch(pendingWrites);
        }
        return EpgRefreshResult(
          successCount: success,
          attemptedCount: processed,
        );
      }
      final batch = ids.skip(i).take(conc).toList();
      final results = await Future.wait(
        batch.map((id) async {
          try {
            if (cachedListingsFor(id).isNotEmpty) {
              return MapEntry(id, const <EpgModel>[]);
            }
            final list = await IpTvApi.getEPGbyStreamId(id);
            return MapEntry(id, list);
          } catch (e) {
            debugPrint('EPG prefetch stream $id failed: $e');
            return MapEntry(id, const <EpgModel>[]);
          }
        }),
      );

      for (final entry in results) {
        processed++;
        if (entry.value.isEmpty) continue;
        success++;
        pendingWrites[entry.key] = entry.value;
      }

      if (pendingWrites.length >= 4) {
        putCachedListingsBatch(pendingWrites);
        pendingWrites.clear();
      }

      report(processed / ids.length);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    if (pendingWrites.isNotEmpty) {
      putCachedListingsBatch(pendingWrites);
    }

    if (gen != _prefetchGen) {
      return EpgRefreshResult(
        successCount: success,
        attemptedCount: processed,
      );
    }

    report(1);

    return EpgRefreshResult(
      successCount: success,
      attemptedCount: ids.length,
    );
  }

  static Map<String, dynamic> _loadCacheMap() {
    final mem = _memoryCache;
    if (mem != null) return mem;
    final raw = _box.read(kStorageEpgCache);
    if (raw is! Map) {
      _memoryCache = <String, dynamic>{};
      return _memoryCache!;
    }
    // Oversized disk cache → drop to avoid OOM on next write.
    if (raw.length > _maxCacheEntries * 3) {
      debugPrint('EPG cache too large (${raw.length}); clearing');
      _box.remove(kStorageEpgCache);
      _memoryCache = <String, dynamic>{};
      return _memoryCache!;
    }
    _memoryCache = Map<String, dynamic>.from(raw);
    return _memoryCache!;
  }

  static void _persistCache(Map<String, dynamic> cache) {
    _pruneCache(cache);
    _memoryCache = cache;
    try {
      _box.write(kStorageEpgCache, cache);
    } catch (e) {
      debugPrint('EPG cache write failed: $e');
      cache.clear();
      _memoryCache = cache;
      try {
        _box.remove(kStorageEpgCache);
      } catch (_) {}
    }
  }

  static void _pruneCache(Map<String, dynamic> cache) {
    if (cache.length <= _maxCacheEntries) return;
    final entries = cache.entries.toList()
      ..sort((a, b) {
        final am = (a.value is Map) ? (a.value['fetched_at_ms'] as int? ?? 0) : 0;
        final bm = (b.value is Map) ? (b.value['fetched_at_ms'] as int? ?? 0) : 0;
        return am.compareTo(bm);
      });
    final drop = cache.length - _maxCacheEntries;
    for (var i = 0; i < drop; i++) {
      cache.remove(entries[i].key);
    }
  }

  static List<EpgModel> cachedListingsFor(String streamId) {
    final id = streamId.trim();
    if (id.isEmpty) return const [];
    final raw = _loadCacheMap();
    final entry = raw[id];
    if (entry is! Map) return const [];
    final listings = entry['listings'];
    if (listings is! List) return const [];
    return listings
        .whereType<Map>()
        .map((e) => EpgModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static void putCachedListings(String streamId, List<EpgModel> listings) {
    putCachedListingsBatch({streamId: listings});
  }

  static void putCachedListingsBatch(Map<String, List<EpgModel>> batch) {
    if (batch.isEmpty) return;
    final cache = _loadCacheMap();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in batch.entries) {
      final id = e.key.trim();
      if (id.isEmpty || e.value.isEmpty) continue;
      cache[id] = {
        'fetched_at_ms': now,
        'listings': e.value.map((m) => m.toJson()).toList(),
      };
    }
    _persistCache(cache);
  }

  static Future<void> clearCache() async {
    _memoryCache = null;
    await _box.remove(kStorageEpgCache);
  }

  static bool _isPlaylistMode(UserModel user) {
    final u = user.userInfo?.username?.trim() ?? '';
    final p = user.userInfo?.password?.trim() ?? '';
    return u.isEmpty && p.isEmpty;
  }
}

class EpgRefreshResult {
  const EpgRefreshResult({
    required this.successCount,
    required this.attemptedCount,
    this.playlistMode = false,
  });

  final int successCount;
  final int attemptedCount;
  final bool playlistMode;

  bool get hasData => successCount > 0;
}
