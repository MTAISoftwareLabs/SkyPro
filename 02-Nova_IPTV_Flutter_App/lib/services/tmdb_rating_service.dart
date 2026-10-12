import 'package:dio/dio.dart';
import 'package:get_storage/get_storage.dart';

import '../core/tmdb_config.dart';
import '../helpers/helpers.dart';
import '../repository/locale/panel_api_keys.dart';

class _TmdbSearchHit {
  const _TmdbSearchHit({required this.id, this.voteAverage});

  final String id;
  final double? voteAverage;
}

/// Fetches, resolves, and persistently caches TMDB ratings for movies and TV shows.
class TmdbRatingService {
  TmdbRatingService._();
  static final TmdbRatingService instance = TmdbRatingService._();

  static const _boxName = 'tmdb_rating_cache_v1';
  static const _ratingsKey = 'ratings';
  static const _tmdbIdsKey = 'tmdb_ids';
  static const _missedKey = 'missed';
  static const _legacySubtitleBox = 'subtitle_service_cache_v1';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );

  final GetStorage _box = GetStorage(_boxName);

  final Map<String, double> _memoryRatingsByContent = {};
  final Map<String, double> _memoryRatingsByTmdb = {};
  final Map<String, String> _memoryTmdbIds = {};
  final Set<String> _memoryMissed = {};
  final Map<String, Future<double?>> _ratingInFlight = {};
  final Map<String, Future<String?>> _tmdbIdInFlight = {};

  bool _legacyMigrated = false;

  static bool needsTmdbFallback(String? rating, [String? rating5based]) {
    return formatContentRating(rating, rating5based) == null;
  }

  Map<String, dynamic> get _ratingsStore =>
      Map<String, dynamic>.from(_box.read(_ratingsKey) ?? {});

  Map<String, dynamic> get _tmdbIdStore =>
      Map<String, dynamic>.from(_box.read(_tmdbIdsKey) ?? {});

  Set<String> get _missedStore {
    final raw = _box.read(_missedKey);
    if (raw is List) {
      return raw.map((e) => e.toString()).toSet();
    }
    return {};
  }

  void _ensureLegacyMigration() {
    if (_legacyMigrated) return;
    _legacyMigrated = true;
    try {
      final legacy = GetStorage(_legacySubtitleBox);
      final legacyIds = legacy.read(_tmdbIdsKey);
      if (legacyIds is! Map) return;

      final store = _tmdbIdStore;
      var changed = false;
      legacyIds.forEach((key, value) {
        final contentKey = key.toString();
        final id = value?.toString().trim() ?? '';
        if (id.isEmpty || id == 'null' || id == '0') return;
        if (!store.containsKey(contentKey)) {
          store[contentKey] = id;
          changed = true;
        }
      });
      if (changed) {
        _box.write(_tmdbIdsKey, store);
      }
    } catch (_) {}
  }

  String _tmdbCacheKey(String tmdbId, bool isSeries) =>
      '${isSeries ? 'tv' : 'movie'}:${tmdbId.trim()}';

  String? _normalizeId(String? value) {
    final id = value?.trim() ?? '';
    if (id.isEmpty || id == 'null' || id == '0') return null;
    return id;
  }

  Future<void> _persistRating(String contentKey, double rating10) async {
    if (rating10 <= 0) return;
    _memoryRatingsByContent[contentKey] = rating10;
    final store = _ratingsStore;
    store[contentKey] = rating10;
    await _box.write(_ratingsKey, store);
  }

  Future<void> _persistTmdbId(String contentKey, String tmdbId) async {
    final id = tmdbId.trim();
    if (id.isEmpty) return;
    _memoryTmdbIds[contentKey] = id;
    final store = _tmdbIdStore;
    store[contentKey] = id;
    await _box.write(_tmdbIdsKey, store);
  }

  Future<void> _markMissed(String contentKey) async {
    _memoryMissed.add(contentKey);
    final store = _missedStore..add(contentKey);
    await _box.write(_missedKey, store.toList());
  }

  bool _isMissed(String contentKey) {
    if (_memoryMissed.contains(contentKey)) return true;
    return _missedStore.contains(contentKey);
  }

  double? getCachedRating10ForContent(String contentKey) {
    final mem = _memoryRatingsByContent[contentKey];
    if (mem != null && mem > 0) return mem;

    final raw = _ratingsStore[contentKey];
    if (raw is num) {
      final value = raw.toDouble();
      if (value > 0) {
        _memoryRatingsByContent[contentKey] = value;
        return value;
      }
    }
    return null;
  }

  String? getCachedTmdbId(String contentKey) {
    _ensureLegacyMigration();
    final mem = _memoryTmdbIds[contentKey];
    if (mem != null) return _normalizeId(mem);

    final raw = _tmdbIdStore[contentKey]?.toString();
    final id = _normalizeId(raw);
    if (id != null) {
      _memoryTmdbIds[contentKey] = id;
    }
    return id;
  }

  double? getCachedRating({required String tmdbId, bool isSeries = false}) {
    final id = _normalizeId(tmdbId);
    if (id == null) return null;
    final key = _tmdbCacheKey(id, isSeries);
    final mem = _memoryRatingsByTmdb[key];
    if (mem != null && mem > 0) return mem;
    return null;
  }

  /// Returns TMDB vote_average (0–10) or null if unavailable.
  Future<double?> fetchRating({
    required String tmdbId,
    bool isSeries = false,
    String? contentKey,
  }) async {
    final id = _normalizeId(tmdbId);
    if (id == null) return null;

    if (contentKey != null) {
      final byContent = getCachedRating10ForContent(contentKey);
      if (byContent != null && byContent > 0) return byContent;
    }

    final key = _tmdbCacheKey(id, isSeries);
    final cached = _memoryRatingsByTmdb[key];
    if (cached != null && cached > 0) return cached;

    try {
      final path = isSeries ? '/tv/$id' : '/movie/$id';
      final response = await _dio.get<Map<String, dynamic>>(
        '$kTmdbBaseUrl$path',
        queryParameters: {'api_key': effectiveTmdbApiKey},
      );
      final average = (response.data?['vote_average'] as num?)?.toDouble();
      if (average != null && average > 0) {
        _memoryRatingsByTmdb[key] = average;
        if (contentKey != null) {
          await _persistRating(contentKey, average);
        }
        return average;
      }
    } catch (_) {}

    return null;
  }

  Future<String?> resolveTmdbId({
    required String contentKey,
    required String title,
    required bool isSeries,
    int? year,
    String? existingTmdbId,
  }) async {
    _ensureLegacyMigration();

    final direct = _normalizeId(existingTmdbId);
    if (direct != null) {
      await _persistTmdbId(contentKey, direct);
      return direct;
    }

    final cached = getCachedTmdbId(contentKey);
    if (cached != null) return cached;

    if (_isMissed(contentKey)) return null;

    final inFlight = _tmdbIdInFlight[contentKey];
    if (inFlight != null) return inFlight;

    final future = _searchTmdb(
      title: title,
      isSeries: isSeries,
      year: year,
    ).then((hit) async {
      if (hit == null) {
        await _markMissed(contentKey);
        return null;
      }
      await _persistTmdbId(contentKey, hit.id);
      if (hit.voteAverage != null &&
          hit.voteAverage! > 0 &&
          getCachedRating10ForContent(contentKey) == null) {
        await _persistRating(contentKey, hit.voteAverage!);
      }
      return hit.id;
    }).whenComplete(() => _tmdbIdInFlight.remove(contentKey));

    _tmdbIdInFlight[contentKey] = future;
    return future;
  }

  Future<double?> resolveVoteAverage10({
    required bool isSeries,
    String? iptvRating,
    String? rating5based,
    String? tmdbId,
    String? contentKey,
    String? title,
    int? year,
  }) async {
    if (!needsTmdbFallback(iptvRating, rating5based)) return null;
    if (effectiveTmdbApiKey.trim().isEmpty) return null;

    _ensureLegacyMigration();

    if (contentKey != null) {
      final cached = getCachedRating10ForContent(contentKey);
      if (cached != null && cached > 0) return cached;
    }

    final dedupeKey =
        contentKey ?? '${isSeries ? 'series' : 'movie'}:${title ?? ''}:$year';
    final inFlight = _ratingInFlight[dedupeKey];
    if (inFlight != null) return inFlight;

    final future = _resolveVoteAverage10(
      isSeries: isSeries,
      tmdbId: tmdbId,
      contentKey: contentKey,
      title: title,
      year: year,
    ).whenComplete(() => _ratingInFlight.remove(dedupeKey));

    _ratingInFlight[dedupeKey] = future;
    return future;
  }

  Future<double?> _resolveVoteAverage10({
    required bool isSeries,
    String? tmdbId,
    String? contentKey,
    String? title,
    int? year,
  }) async {
    var id = _normalizeId(tmdbId);

    if (id == null &&
        contentKey != null &&
        title != null &&
        title.trim().isNotEmpty) {
      id = await resolveTmdbId(
        contentKey: contentKey,
        title: title,
        isSeries: isSeries,
        year: year ?? extractReleaseYear(title),
      );
    }

    if (id != null) {
      return fetchRating(
        tmdbId: id,
        isSeries: isSeries,
        contentKey: contentKey,
      );
    }

    if (title == null || title.trim().isEmpty) return null;
    if (contentKey != null && _isMissed(contentKey)) return null;

    final hit = await _searchTmdb(
      title: title,
      isSeries: isSeries,
      year: year ?? extractReleaseYear(title),
    );
    if (hit == null) {
      if (contentKey != null) await _markMissed(contentKey);
      return null;
    }

    if (contentKey != null) {
      await _persistTmdbId(contentKey, hit.id);
      if (hit.voteAverage != null && hit.voteAverage! > 0) {
        await _persistRating(contentKey, hit.voteAverage!);
        return hit.voteAverage;
      }
    }

    return fetchRating(
      tmdbId: hit.id,
      isSeries: isSeries,
      contentKey: contentKey,
    );
  }

  /// Returns a 0–5 star string for detail-page rating widgets.
  Future<String> resolveStarRating5({
    required String? iptvRating,
    String? rating5based,
    String? tmdbId,
    required bool isSeries,
    String? contentKey,
    String? title,
    int? year,
  }) async {
    final iptv = formatContentRating(iptvRating, rating5based);
    if (iptv != null) {
      final parsed = double.tryParse(iptv);
      if (parsed != null && parsed > 0) {
        return (parsed / 2).toStringAsFixed(1);
      }
    }

    final average = await resolveVoteAverage10(
      isSeries: isSeries,
      iptvRating: iptvRating,
      rating5based: rating5based,
      tmdbId: tmdbId,
      contentKey: contentKey,
      title: title,
      year: year,
    );
    if (average == null || average <= 0) return '0';
    return (average / 2).toStringAsFixed(1);
  }

  /// Returns a 0–10 display string (e.g. "7.5") for poster badges.
  Future<String?> resolveDisplayRating10({
    String? rating,
    String? rating5based,
    String? tmdbId,
    bool isSeries = false,
    String? contentKey,
    String? title,
    int? year,
  }) async {
    final iptv = formatContentRating(rating, rating5based);
    if (iptv != null) return iptv;

    final average = await resolveVoteAverage10(
      isSeries: isSeries,
      iptvRating: rating,
      rating5based: rating5based,
      tmdbId: tmdbId,
      contentKey: contentKey,
      title: title,
      year: year ?? extractReleaseYear(title),
    );
    if (average == null || average <= 0) return null;
    return average.toStringAsFixed(1);
  }

  Future<_TmdbSearchHit?> _searchTmdb({
    required String title,
    required bool isSeries,
    int? year,
  }) async {
    if (effectiveTmdbApiKey.trim().isEmpty) return null;

    try {
      final cleaned = _cleanTitle(title);
      if (cleaned.isEmpty) return null;

      final path = isSeries ? '/search/tv' : '/search/movie';
      final params = <String, dynamic>{
        'api_key': effectiveTmdbApiKey,
        'query': cleaned,
      };
      if (year != null && year > 0) {
        params[isSeries ? 'first_air_date_year' : 'year'] = year;
      }

      final response = await _dio.get<Map<String, dynamic>>(
        '$kTmdbBaseUrl$path',
        queryParameters: params,
      );
      final results = response.data?['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      Map<String, dynamic>? best;
      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;
        final itemYear = _releaseYearFromItem(item, isSeries);
        if (year != null && itemYear != null && itemYear != year) continue;
        best = item;
        break;
      }
      best ??= results.first as Map<String, dynamic>;

      final id = best['id']?.toString();
      if (id == null || id.isEmpty) return null;

      final vote = (best['vote_average'] as num?)?.toDouble();
      return _TmdbSearchHit(
        id: id,
        voteAverage: vote != null && vote > 0 ? vote : null,
      );
    } catch (_) {
      return null;
    }
  }

  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\(\s*\d{4}\s*\)'), '')
        .replaceAll(RegExp(r'\[\s*\d{4}\s*\]'), '')
        .trim();
  }

  int? _releaseYearFromItem(Map<String, dynamic> item, bool isSeries) {
    final raw = isSeries
        ? item['first_air_date']?.toString()
        : item['release_date']?.toString();
    if (raw == null || raw.length < 4) return null;
    return int.tryParse(raw.substring(0, 4));
  }
}

int? extractReleaseYear(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final match = RegExp(r'(19|20)\d{2}').firstMatch(raw);
  if (match == null) return null;
  return int.tryParse(match.group(0)!);
}
