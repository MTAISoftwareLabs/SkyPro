import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/opensubtitles_config.dart';
import '../../core/tmdb_config.dart';
import '../../repository/locale/panel_api_keys.dart';
import '../tmdb_rating_service.dart';
import 'opensubtitles_debug_log.dart';
import 'subtitle_models.dart';
import 'subtitle_step_trace.dart';

class SubtitleSearchException implements Exception {
  SubtitleSearchException(this.messageKey);

  final String messageKey;
}

/// Handles TMDB id resolution, OpenSubtitles search/download, and caching.
class SubtitleService {
  SubtitleService._();
  static final SubtitleService instance = SubtitleService._();

  static const _storageBox = 'subtitle_service_cache_v1';
  static const _defaultLangKey = 'default_language';

  /// UI language codes + native labels for default-subtitle picker.
  static const List<MapEntry<String, String>> supportedUiLanguages = [
    MapEntry('ar', 'العربية'),
    MapEntry('en', 'English'),
    MapEntry('fr', 'Français'),
    MapEntry('es', 'Español'),
    MapEntry('de', 'Deutsch'),
    MapEntry('it', 'Italiano'),
    MapEntry('pt', 'Português'),
    MapEntry('tr', 'Türkçe'),
    MapEntry('fa', 'فارسی'),
  ];

  static String labelForLanguageCode(String code) {
    final normalized = code.trim().toLowerCase();
    for (final e in supportedUiLanguages) {
      if (e.key == normalized) return e.value;
    }
    return normalized.toUpperCase();
  }

  static const Map<String, String> _languageToOpenSubtitles = {
    // OpenSubtitles /infos/languages uses ISO 639-1 (ar, en, fr…), NOT 639-2 (ara, eng).
    'ara': 'ar',
    'eng': 'en',
    'fre': 'fr',
    'fra': 'fr',
    'spa': 'es',
    'deu': 'de',
    'ger': 'de',
    'ita': 'it',
    'por': 'pt-pt',
    'pt': 'pt-pt',
    'tur': 'tr',
    'per': 'fa',
    'fas': 'fa',
  };

  static const Duration _downloadTimeout = Duration(seconds: 25);
  static const Duration _cascadeStepTimeout = Duration(seconds: 7);

  static const _imdbIdsKey = 'imdb_ids';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      headers: {'Accept': 'application/json'},
    ),
  );

  /// Dedicated client for `/subtitles` so login/TMDB on [_dio] can never block search.
  final Dio _searchDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 12),
      headers: {'Accept': 'application/json'},
    ),
  );

  final GetStorage _box = GetStorage(_storageBox);

  final Map<String, List<SubtitleResultItem>> _searchCache = {};
  final Map<String, String> _fileCache = {};
  final Map<String, Future<List<SubtitleResultItem>>> _searchInFlight = {};
  final Map<String, Future<String?>> _downloadInFlight = {};

  String? _jwtToken;
  DateTime? _jwtExpiresAt;
  Future<String?>? _jwtLoginInFlight;

  String get defaultLanguageCode =>
      (_box.read(_defaultLangKey) as String?)?.trim().isNotEmpty == true
      ? (_box.read(_defaultLangKey) as String).trim()
      : 'ar';

  Future<void> setDefaultLanguageCode(String code) async {
    await _box.write(_defaultLangKey, code.trim().toLowerCase());
  }

  /// Instant IMDb lookup from local cache (no network).
  String? peekCachedImdbId({required String? tmdbId, required bool isSeries}) {
    final id = _normalizeTmdbId(tmdbId);
    if (id == null) return null;
    return _cachedImdbId(id, isSeries);
  }

  /// Warm JWT in background so download is fast.
  /// Never throws — search must not depend on login.
  void warmUpAuth() {
    unawaited(() async {
      try {
        await _ensureJwtToken();
      } catch (_) {}
    }());
  }

  String? getCachedTmdbId(String contentKey) {
    return TmdbRatingService.instance.getCachedTmdbId(contentKey);
  }

  Future<String?> resolveTmdbId({
    required String contentKey,
    required String title,
    required bool isSeries,
    int? year,
    String? existingTmdbId,
  }) async {
    OpenSubtitlesDebugLog.logTmdbContext(
      tmdbId: existingTmdbId,
      contentKey: contentKey,
      title: title,
      isSeries: isSeries,
      year: year,
      searchBy: 'resolve',
    );

    final cached = getCachedTmdbId(contentKey);
    if (cached != null) {
      OpenSubtitlesDebugLog.logTmdbResolveResult(
        resolvedId: cached,
        reason: 'Found in persistent cache',
      );
      return cached;
    }

    final result = await TmdbRatingService.instance.resolveTmdbId(
      contentKey: contentKey,
      title: title,
      isSeries: isSeries,
      year: year,
      existingTmdbId: existingTmdbId,
    );

    OpenSubtitlesDebugLog.logTmdbResolveResult(
      resolvedId: result,
      reason: result != null
          ? 'Resolved via TMDB search by title/year'
          : 'TMDB search returned no match for "$title"${year != null ? ' ($year)' : ''}',
    );
    return result;
  }

  /// Resolves IMDb id (numeric, no tt/leading zeros) from TMDB id via TMDB API.
  Future<String?> resolveImdbId({
    required String? tmdbId,
    required bool isSeries,
  }) async {
    final id = _normalizeTmdbId(tmdbId);
    if (id == null) return null;
    final result = await _fetchImdbIdFromTmdb(tmdbId: id, isSeries: isSeries);
    return result.normalized;
  }

  String? _resolveImdbFromQuery(SubtitleSearchQuery query) {
    final direct = _normalizeImdbId(query.imdbId);
    if (direct != null) return direct;

    if (query.searchBy == SubtitleSearchBy.imdbId &&
        query.query.trim().isNotEmpty) {
      return _normalizeImdbId(query.query);
    }

    return null;
  }

  /// IMDb available without a live TMDB network call.
  String? _availableImdbIdSync(SubtitleSearchQuery query) {
    final fromQuery = _resolveImdbFromQuery(query);
    if (fromQuery != null) return fromQuery;

    final tmdb = _pickTmdbId(query);
    if (tmdb == null) return null;
    return peekCachedImdbId(tmdbId: tmdb, isSeries: query.isSeries);
  }

  String? _pickTmdbId(SubtitleSearchQuery query) {
    if (query.searchBy == SubtitleSearchBy.tmdbId &&
        query.query.trim().isNotEmpty) {
      return _normalizeTmdbId(query.query);
    }
    return _normalizeTmdbId(query.tmdbId);
  }

  String _originalTitle(SubtitleSearchQuery query) {
    final fromField = query.title?.trim() ?? '';
    if (fromField.isNotEmpty) return fromField;
    // Avoid treating IMDb/TMDB typed ids as a title.
    if (query.searchBy == SubtitleSearchBy.imdbId ||
        query.searchBy == SubtitleSearchBy.tmdbId) {
      return '';
    }
    return query.query.trim();
  }

  String _sanitizeTitle(String title) {
    return title
        .replaceAll(RegExp(r'\(\s*\d{4}\s*\)'), '')
        .replaceAll(RegExp(r'\[\s*\d{4}\s*\]'), '')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _sanitizeFileName(String? fileName) {
    var name = fileName?.trim() ?? '';
    if (name.isEmpty) return null;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    name = name
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return name.isEmpty ? null : name;
  }

  Future<List<SubtitleResultItem>> searchSubtitles(
    SubtitleSearchQuery query,
  ) async {
    final sw = Stopwatch()..start();
    if (kOpensubtitlesVerboseLogs) {
      subtitleStep('STEP 4', 'searchSubtitles entered key=${query.cacheKey()}');
    }
    if (effectiveOpensubtitlesApiKey.isEmpty) {
      throw SubtitleSearchException('subtitle_api_not_configured');
    }

    final key = query.cacheKey();
    final cached = _searchCache[key];
    if (cached != null) {
      return List<SubtitleResultItem>.from(cached);
    }

    final inFlight = _searchInFlight[key];
    if (inFlight != null) {
      return inFlight;
    }

    final future = () async {
      try {
        final items = await _fastSearch(query).timeout(
          const Duration(seconds: 22),
          onTimeout: () {
            if (kOpensubtitlesVerboseLogs) {
              subtitleStep(
                'SEARCH TIMEOUT',
                'overall timeout after ${sw.elapsedMilliseconds}ms',
              );
            }
            return const <SubtitleResultItem>[];
          },
        );
        if (kOpensubtitlesVerboseLogs) {
          subtitleStep(
            'SEARCH DONE',
            '${items.length} results in ${sw.elapsedMilliseconds}ms',
          );
        }
        if (items.isNotEmpty) {
          _searchCache[key] = items;
        }
        return items;
      } finally {
        _searchInFlight.remove(key);
      }
    }();

    _searchInFlight[key] = future;
    return future;
  }

  Map<String, String> _openSubtitlesHeaders({String? bearer}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': kOpensubtitlesUserAgent,
      'Api-Key': effectiveOpensubtitlesApiKey,
    };
    if (bearer != null && bearer.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearer';
    }
    return headers;
  }

  String _toOpenSubtitlesLanguage(String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) return 'ar';
    // Prefer ISO 639-1 as returned by GET /infos/languages.
    return _languageToOpenSubtitles[normalized] ?? normalized;
  }

  /// Cascade: sync IMDb → tmdb_id (native OS) → title(+year) → file_name.
  /// Never blocks on a live TMDB→IMDb conversion before searching.
  Future<List<SubtitleResultItem>> _fastSearch(SubtitleSearchQuery query) async {
    // Do NOT start JWT login here — same-host Dio login was blocking first search.
    final lang = _toOpenSubtitlesLanguage(
      query.languageCode.trim().isEmpty ? 'ar' : query.languageCode,
    );
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': kOpensubtitlesUserAgent,
      'Api-Key': effectiveOpensubtitlesApiKey,
    };

    final originalImdb =
        query.imdbId?.trim().isNotEmpty == true ? query.imdbId!.trim() : null;
    final imdbId = _availableImdbIdSync(query);

    final originalTmdb =
        query.tmdbId?.trim().isNotEmpty == true ? query.tmdbId!.trim() : null;
    final tmdbId = _pickTmdbId(query);

    final originalTitle = _originalTitle(query);
    final sanitizedTitle =
        originalTitle.isEmpty ? '' : _sanitizeTitle(originalTitle);

    final originalFileName = query.fileName?.trim();
    final sanitizedFileName = _sanitizeFileName(query.fileName);

    var anyAttempt = false;

    // a) IMDb — only if already available (query / sync cache). No TMDB network.
    if (imdbId != null) {
      anyAttempt = true;
      final params = <String, dynamic>{'languages': lang};
      final imdbKey = query.isSeries ? 'parent_imdb_id' : 'imdb_id';
      params[imdbKey] = imdbId;
      if (query.isSeries) params.addAll(_seriesEpisodeParams(query));

      final items = await _tryCascadeStep(
        stepName: 'imdb',
        params: params,
        headers: headers,
        originalImdbId: originalImdb ?? imdbId,
        normalizedImdbId: imdbId,
        imdbParamKey: imdbKey,
        imdbParamValue: imdbId,
      );
      if (items.isNotEmpty) return items;
    }

    // b) TMDB id sent DIRECTLY to OpenSubtitles (no IMDb conversion).
    if (tmdbId != null) {
      anyAttempt = true;
      final params = <String, dynamic>{'languages': lang};
      final tmdbKey = query.isSeries ? 'parent_tmdb_id' : 'tmdb_id';
      params[tmdbKey] = tmdbId;
      if (query.isSeries) params.addAll(_seriesEpisodeParams(query));

      final items = await _tryCascadeStep(
        stepName: 'tmdb',
        params: params,
        headers: headers,
        originalTmdbId: originalTmdb ?? tmdbId,
        tmdbParamKey: tmdbKey,
        tmdbParamValue: tmdbId,
      );
      if (items.isNotEmpty) return items;
    }

    // c) Title + optional year (+ season/episode for series).
    if (sanitizedTitle.isNotEmpty) {
      anyAttempt = true;
      final params = <String, dynamic>{
        'languages': lang,
        'query': sanitizedTitle,
      };
      if (query.year != null && query.year! > 0) {
        params['year'] = query.year;
      }
      if (query.isSeries) params.addAll(_seriesEpisodeParams(query));

      final items = await _tryCascadeStep(
        stepName: 'title',
        params: params,
        headers: headers,
        originalTitle: originalTitle,
        sanitizedTitle: sanitizedTitle,
        queryTitleSent: sanitizedTitle,
        yearSent: query.year != null && query.year! > 0 ? query.year : null,
      );
      if (items.isNotEmpty) return items;
    }

    // d) File name — last resort.
    if (sanitizedFileName != null) {
      anyAttempt = true;
      final params = <String, dynamic>{
        'languages': lang,
        'query': sanitizedFileName,
      };
      if (query.isSeries) params.addAll(_seriesEpisodeParams(query));

      final items = await _tryCascadeStep(
        stepName: 'filename',
        params: params,
        headers: headers,
        originalFileName: originalFileName,
        sanitizedFileName: sanitizedFileName,
        queryFileNameSent: sanitizedFileName,
      );
      if (items.isNotEmpty) return items;
    }

    if (!anyAttempt) {
      throw SubtitleSearchException('subtitle_imdb_required');
    }
    return const [];
  }

  /// Runs one OpenSubtitles attempt. Empty/timeout → []; fatal auth errors rethrow.
  Future<List<SubtitleResultItem>> _tryCascadeStep({
    required String stepName,
    required Map<String, dynamic> params,
    required Map<String, String> headers,
    String? originalImdbId,
    String? normalizedImdbId,
    String? imdbParamKey,
    String? imdbParamValue,
    String? originalTmdbId,
    String? tmdbParamKey,
    String? tmdbParamValue,
    String? originalTitle,
    String? sanitizedTitle,
    String? queryTitleSent,
    int? yearSent,
    String? originalFileName,
    String? sanitizedFileName,
    String? queryFileNameSent,
  }) async {
    final url = '$kOpensubtitlesBaseUrl/subtitles';
    OpenSubtitlesDebugLog.logSearchAttempt(
      url: url,
      queryParameters: params,
      headers: headers,
      originalImdbId: originalImdbId,
      normalizedImdbId: normalizedImdbId,
      imdbParamKey: imdbParamKey,
      imdbParamValue: imdbParamValue,
      originalTmdbId: originalTmdbId,
      tmdbParamKey: tmdbParamKey,
      tmdbParamValue: tmdbParamValue,
      originalTitle: originalTitle,
      sanitizedTitle: sanitizedTitle,
      queryTitleSent: queryTitleSent,
      yearSent: yearSent,
      originalFileName: originalFileName,
      sanitizedFileName: sanitizedFileName,
      queryFileNameSent: queryFileNameSent,
    );

    try {
      final response = await _searchDio
          .get<dynamic>(
            url,
            queryParameters: params,
            options: Options(
              headers: headers,
              contentType: null,
              connectTimeout: _cascadeStepTimeout,
              sendTimeout: _cascadeStepTimeout,
              receiveTimeout: _cascadeStepTimeout,
              validateStatus: (code) =>
                  code != null && code >= 200 && code < 500,
            ),
          )
          .timeout(_cascadeStepTimeout);

      final status = response.statusCode ?? 0;
      final raw = response.data;
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      if (status == 401) {
        throw SubtitleSearchException('subtitle_unauthorized');
      }
      if (status == 403) {
        final message = data['message']?.toString().toLowerCase() ?? '';
        if (message.contains('api') || message.contains('consume')) {
          throw SubtitleSearchException('subtitle_invalid_api_key');
        }
        throw SubtitleSearchException('subtitle_forbidden');
      }
      if (status == 429) {
        throw SubtitleSearchException('subtitle_too_many_requests');
      }
      if (status < 200 || status >= 300) {
        return const [];
      }

      final items = _parseSearchResults(data);
      if (kOpensubtitlesVerboseLogs) {
        subtitleStep(
          'CASCADE',
          'step=$stepName results=${items.length} '
          '(total_count=${_readTotalCount(data)})',
        );
      }
      return items;
    } on SubtitleSearchException {
      rethrow;
    } on TimeoutException catch (e, st) {
      OpenSubtitlesDebugLog.logGenericError(e, st);
      return const [];
    } on DioException catch (e, st) {
      if (e.response?.statusCode == 401) {
        throw SubtitleSearchException('subtitle_unauthorized');
      }
      if (e.response?.statusCode == 403) {
        throw SubtitleSearchException('subtitle_forbidden');
      }
      if (e.response?.statusCode == 429) {
        throw SubtitleSearchException('subtitle_too_many_requests');
      }
      OpenSubtitlesDebugLog.logGenericError(e, st);
      return const [];
    } catch (e, st) {
      OpenSubtitlesDebugLog.logGenericError(e, st);
      return const [];
    }
  }

  List<SubtitleResultItem> _parseSearchResults(Map<String, dynamic>? data) {
    if (data == null) return [];

    final entries = data['data'];
    if (entries is! List || entries.isEmpty) return [];

    final items = <SubtitleResultItem>[];
    for (final raw in entries) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final attributesRaw = row['attributes'];
      if (attributesRaw is! Map) continue;
      final attributes = Map<String, dynamic>.from(attributesRaw);

      final parsedFileId = _extractFileId(row, attributes);
      if (parsedFileId == null || parsedFileId <= 0) continue;

      final featureDetailsRaw = attributes['feature_details'];
      final featureDetails = featureDetailsRaw is Map
          ? Map<String, dynamic>.from(featureDetailsRaw)
          : null;
      final releaseName =
          (attributes['release'] ??
                  attributes['file_name'] ??
                  featureDetails?['title'] ??
                  featureDetails?['movie_name'] ??
                  attributes['movie_name'])
              ?.toString()
              .trim();
      if (releaseName == null || releaseName.isEmpty) continue;

      final language = attributes['language']?.toString().trim() ?? '';
      final downloads = _parseDownloads(attributes['download_count']);

      items.add(
        SubtitleResultItem(
          releaseName: releaseName,
          language: language.isEmpty ? '—' : language,
          downloads: downloads,
          fileId: parsedFileId,
        ),
      );
    }
    return items;
  }

  Map<String, dynamic> get _imdbIdStore =>
      Map<String, dynamic>.from(_box.read(_imdbIdsKey) ?? {});

  String _imdbCacheKey(String tmdbId, bool isSeries) =>
      '${isSeries ? 'tv' : 'movie'}:$tmdbId';

  String? _normalizeTmdbId(String? value) {
    final id = value?.trim() ?? '';
    if (id.isEmpty || id == 'null' || id == '0') return null;
    return id;
  }

  String? _normalizeImdbId(String? value) {
    if (value == null) return null;
    var id = value.trim();
    if (id.isEmpty || id == 'null' || id == '0') return null;
    if (id.toLowerCase().startsWith('tt')) id = id.substring(2);
    // OpenSubtitles API: remove "tt" AND leading zeros (tt0118480 → 118480).
    final numeric = int.tryParse(id);
    if (numeric == null || numeric <= 0) return null;
    return numeric.toString();
  }

  String? _cachedImdbId(String tmdbId, bool isSeries) {
    final entry = _imdbIdStore[_imdbCacheKey(tmdbId, isSeries)];
    if (entry is Map) {
      return _normalizeImdbId(entry['normalized']?.toString() ?? entry['original']?.toString());
    }
    return _normalizeImdbId(entry?.toString());
  }

  String? _cachedOriginalImdbId(String tmdbId, bool isSeries) {
    final entry = _imdbIdStore[_imdbCacheKey(tmdbId, isSeries)];
    if (entry is Map) {
      final original = entry['original']?.toString().trim();
      if (original != null && original.isNotEmpty) return original;
      final normalized = entry['normalized']?.toString();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized.startsWith('tt') ? normalized : 'tt$normalized';
      }
      return null;
    }
    final raw = entry?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('tt') ? raw : 'tt$raw';
  }

  Future<void> _cacheImdbId(
    String tmdbId,
    bool isSeries, {
    required String? original,
    required String? normalized,
  }) async {
    if (normalized == null || normalized.isEmpty) return;
    final store = _imdbIdStore;
    store[_imdbCacheKey(tmdbId, isSeries)] = {
      'original': original ?? 'tt$normalized',
      'normalized': normalized,
    };
    await _box.write(_imdbIdsKey, store);
  }

  Map<String, dynamic> _seriesEpisodeParams(SubtitleSearchQuery query) {
    final params = <String, dynamic>{};
    if (query.season != null) params['season_number'] = query.season;
    if (query.episode != null) params['episode_number'] = query.episode;
    if (query.season != null && query.episode != null) {
      params['type'] = 'episode';
    }
    return params;
  }

  Future<({String? normalized, String? original})> _fetchImdbIdFromTmdb({
    required String tmdbId,
    required bool isSeries,
  }) async {
    final cachedNormalized = _cachedImdbId(tmdbId, isSeries);
    final cachedOriginal = _cachedOriginalImdbId(tmdbId, isSeries);
    if (cachedNormalized != null) {
      subtitleStep(
        'IMDb resolve',
        'Using cached imdb original=$cachedOriginal normalized=$cachedNormalized for tmdb_id=$tmdbId',
      );
      return (normalized: cachedNormalized, original: cachedOriginal);
    }

    final apiKey = effectiveTmdbApiKey.trim();
    if (apiKey.isEmpty) {
      subtitleStep('IMDb resolve STOPPED', 'TMDB API key is empty');
      return (normalized: null, original: null);
    }

    final path = isSeries
        ? '/tv/$tmdbId/external_ids'
        : '/movie/$tmdbId/external_ids';
    subtitleStep(
      'IMDb resolve',
      'Fetching from TMDB $kTmdbBaseUrl$path',
    );

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$kTmdbBaseUrl$path',
        queryParameters: {'api_key': apiKey},
      );
      var rawImdb = response.data?['imdb_id']?.toString();
      var imdbId = _normalizeImdbId(rawImdb);

      if (imdbId == null && !isSeries) {
        subtitleStep('IMDb resolve', 'external_ids empty — trying /movie/$tmdbId');
        final detail = await _dio.get<Map<String, dynamic>>(
          '$kTmdbBaseUrl/movie/$tmdbId',
          queryParameters: {'api_key': apiKey},
        );
        rawImdb = detail.data?['imdb_id']?.toString();
        imdbId = _normalizeImdbId(rawImdb);
      }

      subtitleStep(
        'IMDb resolve',
        'TMDB → IMDb original=${rawImdb ?? 'null'} normalized=$imdbId',
      );
      if (imdbId != null) {
        await _cacheImdbId(
          tmdbId,
          isSeries,
          original: rawImdb,
          normalized: imdbId,
        );
      }
      return (normalized: imdbId, original: rawImdb);
    } catch (e, st) {
      subtitleStepError('IMDb resolve FAILED', e, st);
      return (normalized: null, original: null);
    }
  }

  int _readTotalCount(Map<String, dynamic>? data) {
    if (data == null) return 0;
    final total = data['total_count'];
    if (total is int) return total;
    if (total is num) return total.toInt();
    return int.tryParse(total?.toString() ?? '') ?? 0;
  }

  int? _extractFileId(Map<String, dynamic> raw, Map<String, dynamic> attributes) {
    final files = attributes['files'];
    if (files is List && files.isNotEmpty) {
      final firstFile = files.first;
      if (firstFile is Map) {
        final fromFile = _parseInt(Map<String, dynamic>.from(firstFile)['file_id']);
        if (fromFile != null && fromFile > 0) return fromFile;
      }
    }

    final fromAttributes = _parseInt(attributes['file_id']);
    if (fromAttributes != null && fromAttributes > 0) return fromAttributes;

    return _parseInt(raw['id']);
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int _parseDownloads(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<String?> _ensureJwtToken() async {
    subtitleStep('STEP 6a', '_ensureJwtToken() entered');
    if (_jwtToken != null &&
        _jwtExpiresAt != null &&
        DateTime.now().isBefore(_jwtExpiresAt!)) {
      subtitleStep('STEP 6b', 'Using cached JWT token (still valid)');
      return _jwtToken;
    }

    if (_jwtLoginInFlight != null) {
      subtitleStep('STEP 6c', 'Login already in-flight — awaiting same future');
      try {
        return await _jwtLoginInFlight!.timeout(const Duration(seconds: 16));
      } on TimeoutException {
        subtitleStep('STEP 6c TIMEOUT', 'In-flight login timed out');
        _jwtLoginInFlight = null;
        return null;
      }
    }

    subtitleStep('STEP 6d', 'No valid token — starting _loginOpenSubtitles()');
    final future = () async {
      try {
        return await _loginOpenSubtitles().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            subtitleStep('STEP 6 LOGIN TIMEOUT', 'login exceeded 15s');
            return null;
          },
        );
      } finally {
        _jwtLoginInFlight = null;
      }
    }();
    _jwtLoginInFlight = future;
    return future;
  }

  Future<String?> _loginOpenSubtitles() async {
    subtitleStep('STEP 6e', 'Logging into OpenSubtitles at $kOpensubtitlesBaseUrl/login');
    OpenSubtitlesDebugLog.logSettings();

    final username = effectiveOpensubtitlesUsername;
    final password = effectiveOpensubtitlesPassword;
    if (effectiveOpensubtitlesApiKey.isEmpty ||
        username.isEmpty ||
        password.isEmpty) {
      if (effectiveOpensubtitlesApiKey.isEmpty) {
        subtitleStep('STEP 6 STOPPED', 'Missing OpenSubtitles API key — login skipped');
        OpenSubtitlesDebugLog.logLoginSkipped(
          reason: 'Missing OpenSubtitles API key',
        );
      } else if (username.isEmpty) {
        subtitleStep('STEP 6 STOPPED', 'Missing OpenSubtitles username — login skipped');
        OpenSubtitlesDebugLog.logLoginSkipped(
          reason: 'Missing OpenSubtitles username',
        );
      } else {
        subtitleStep('STEP 6 STOPPED', 'Missing OpenSubtitles password — login skipped');
        OpenSubtitlesDebugLog.logLoginSkipped(
          reason: 'Missing OpenSubtitles password',
        );
      }
      return null;
    }

    final loginUrl = '$kOpensubtitlesBaseUrl/login';
    final headers = _openSubtitlesHeaders();
    subtitleStep('STEP 6f', 'Dio POST → $loginUrl');
    OpenSubtitlesDebugLog.logLoginRequest(
      url: loginUrl,
      headers: headers,
      username: username,
    );

    try {
      subtitleStep('STEP 6g', 'Awaiting Dio login response...');
      final response = await _dio
          .post<Map<String, dynamic>>(
            loginUrl,
            data: {'username': username, 'password': password},
            options: Options(headers: headers),
          )
          .timeout(const Duration(seconds: 15));

      subtitleStep('STEP 6h', 'Login response statusCode=${response.statusCode}');
      subtitleStep('STEP 6i', 'Login response.data=${response.data}');

      final token = response.data?['token']?.toString().trim();
      if (token == null || token.isEmpty) {
        subtitleStep('STEP 6 STOPPED', 'Login response did not contain a token');
        OpenSubtitlesDebugLog.logLoginFailure(
          statusCode: response.statusCode,
          responseBody: response.data,
          error: 'Login response did not contain a token',
        );
        return null;
      }

      subtitleStep('STEP 7', 'JWT Token = ${token.substring(0, token.length.clamp(0, 20))}...');
      OpenSubtitlesDebugLog.logLoginSuccess(
        statusCode: response.statusCode,
        responseBody: response.data,
        token: token,
      );

      _jwtToken = token;
      _jwtExpiresAt = DateTime.now().add(const Duration(hours: 20));
      return token;
    } on DioException catch (e, st) {
      subtitleStepError('STEP ERROR (login DioException)', e, st);
      OpenSubtitlesDebugLog.logLoginFailure(
        statusCode: e.response?.statusCode,
        responseBody: e.response?.data,
        error: e,
        stackTrace: st,
      );
      return null;
    } catch (e, st) {
      subtitleStepError('STEP ERROR (login unhandled)', e, st);
      OpenSubtitlesDebugLog.logLoginFailure(
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<String?> downloadSubtitleFile(SubtitleResultItem item) async {
    final cacheKey = _downloadCacheKey(item);
    final cached = _fileCache[cacheKey];
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }

    final inFlight = _downloadInFlight[cacheKey];
    if (inFlight != null) {
      try {
        return await inFlight.timeout(const Duration(seconds: 28));
      } on TimeoutException {
        _downloadInFlight.remove(cacheKey);
        return null;
      }
    }

    final future = () async {
      try {
        final path = await _downloadToCache(item, cacheKey).timeout(
          const Duration(seconds: 28),
          onTimeout: () => null,
        );
        if (path != null) _fileCache[cacheKey] = path;
        return path;
      } finally {
        _downloadInFlight.remove(cacheKey);
      }
    }();

    _downloadInFlight[cacheKey] = future;
    return future;
  }

  String _downloadCacheKey(SubtitleResultItem item) {
    return md5.convert('${item.fileId}'.codeUnits).toString();
  }

  Future<String?> _downloadToCache(
    SubtitleResultItem item,
    String cacheKey,
  ) async {
    OpenSubtitlesDebugLog.logDownloadRequest(fileId: item.fileId);

    final token = await _ensureJwtToken().timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );
    if (token == null || token.isEmpty) {
      subtitleStep('DOWNLOAD STOPPED', 'JWT login failed — cannot download');
      return null;
    }

    try {
      final downloadResponse = await _dio
          .post<Map<String, dynamic>>(
            '$kOpensubtitlesBaseUrl/download',
            data: {'file_id': item.fileId},
            options: Options(headers: _openSubtitlesHeaders(bearer: token)),
          )
          .timeout(_downloadTimeout);

      final link = downloadResponse.data?['link']?.toString().trim();
      OpenSubtitlesDebugLog.logDownloadResponse(
        downloadUrl: link,
        statusCode: downloadResponse.statusCode,
        responseBody: downloadResponse.data,
      );
      if (link == null || link.isEmpty) return null;

      final fileName =
          downloadResponse.data?['file_name']?.toString().trim() ??
          item.releaseName;

      final dir = await getTemporaryDirectory();
      final subtitlesDir = Directory('${dir.path}/subtitles_cache');
      if (!subtitlesDir.existsSync()) {
        subtitlesDir.createSync(recursive: true);
      }

      final ext = _subtitleExtension(fileName);
      final target = File('${subtitlesDir.path}/$cacheKey$ext');
      if (target.existsSync()) return target.path;

      final fileResponse = await _dio
          .get<List<int>>(
            link,
            options: Options(
              responseType: ResponseType.bytes,
              receiveTimeout: _downloadTimeout,
            ),
          )
          .timeout(_downloadTimeout);

      OpenSubtitlesDebugLog.logDownloadFileFetch(
        url: link,
        statusCode: fileResponse.statusCode,
        byteCount: fileResponse.data?.length,
      );

      final bytes = fileResponse.data;
      if (bytes == null || bytes.isEmpty) return null;
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    } catch (e, st) {
      subtitleStepError('DOWNLOAD FAILED', e, st);
      rethrow;
    }
  }

  String _subtitleExtension(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.vtt')) return '.vtt';
    if (lower.endsWith('.ass')) return '.ass';
    if (lower.endsWith('.ssa')) return '.ssa';
    return '.srt';
  }

  static void clearMemoryCache() {
    instance._searchCache.clear();
    instance._fileCache.clear();
    instance._searchInFlight.clear();
    instance._downloadInFlight.clear();
    instance._jwtToken = null;
    instance._jwtExpiresAt = null;
    instance._jwtLoginInFlight = null;
  }

  static Future<void> clearAllCaches() async {
    clearMemoryCache();
    await instance._box.erase();
    try {
      final dir = await getTemporaryDirectory();
      final subtitlesDir = Directory('${dir.path}/subtitles_cache');
      if (subtitlesDir.existsSync()) {
        subtitlesDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  }
}
