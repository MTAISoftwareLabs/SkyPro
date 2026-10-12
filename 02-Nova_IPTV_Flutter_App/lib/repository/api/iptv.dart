part of 'api.dart';

/// تخزين مؤقت لاستجابات الـ API (تصنيفات + قوائم) لتقليل التحميل على بيانات الجوال
class _ApiCacheEntry<T> {
  final T data;
  final DateTime expiry;
  _ApiCacheEntry(this.data, this.expiry);
  bool get isValid => DateTime.now().isBefore(expiry);
}

class IpTvApi {
  static final Map<String, List<M3UEntry>> _m3uCache = {};

  /// Nested SS IPTV / multi-section M3U catalog (playlist mode).
  static SsIptvCatalog? _ssCatalog;
  static String? _ssCatalogUrl;
  static Future<SsIptvCatalog?>? _ssCatalogInFlight;

  /// Flat M3U only (no nested playlists) — skip nested rebuild.
  static final Set<String> _flatM3uUrls = {};

  static const Duration _categoriesCacheTtl = Duration(minutes: 5);
  static const Duration _channelsCacheTtl = Duration(minutes: 3);

  /// كتالوج All كبير — TTL أطول يقلّل إعادة التحميل الثقيلة.
  static const Duration _fullCatalogCacheTtl = Duration(minutes: 20);

  static final Map<String, _ApiCacheEntry<List<CategoryModel>>>
  _categoriesCache = {};
  static final Map<String, _ApiCacheEntry<List<ChannelLive>>>
  _liveChannelsCache = {};
  static final Map<String, _ApiCacheEntry<List<ChannelMovie>>>
  _movieChannelsCache = {};
  static final Map<String, _ApiCacheEntry<List<ChannelSerie>>>
  _seriesChannelsCache = {};

  /// منع طلبات مكررة لنفس المفتاح (مهم أثناء شاشة التحميل).
  static final Map<String, Future<List<ChannelMovie>>> _movieInFlight = {};
  static final Map<String, Future<List<ChannelSerie>>> _seriesInFlight = {};
  static final Map<String, Future<List<CategoryModel>>> _categoriesInFlight =
      {};

  static void clearM3UCache() {
    _m3uCache.clear();
    _ssCatalog = null;
    _ssCatalogUrl = null;
    _ssCatalogInFlight = null;
    _flatM3uUrls.clear();
  }

  /// يتحقق أن رابط/ملف M3U قابل للجلب وفيه قنوات قبل السماح بالدخول.
  Future<bool> validatePlaylistUrl(String playlistUrl) async {
    final url = playlistUrl.trim();
    if (url.isEmpty) return false;
    try {
      final entries = await _getM3UEntries(url);
      if (entries.isNotEmpty) return true;
      // بعض قوائم SS/متداخلة تُبنى عبر كتالوج خاص.
      final ss = await _ensureSsCatalog(url);
      if (ss == null) return false;
      return ss.liveCategories.isNotEmpty ||
          ss.movieCategories.isNotEmpty ||
          ss.seriesCategories.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static void clearApiCaches() {
    _categoriesCache.clear();
    _liveChannelsCache.clear();
    _movieChannelsCache.clear();
    _seriesChannelsCache.clear();
    _categoriesInFlight.clear();
    _movieInFlight.clear();
    _seriesInFlight.clear();
    _ssCatalog = null;
    _ssCatalogUrl = null;
    _ssCatalogInFlight = null;
    _flatM3uUrls.clear();
  }

  static bool _isHttpStreamId(String? id) {
    final s = (id ?? '').trim();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  /// Load nested SS IPTV catalog when master has type=playlist folders.
  Future<SsIptvCatalog?> _ensureSsCatalog(String playlistUrl) async {
    final url = playlistUrl.trim();
    if (url.isEmpty) return null;
    if (_flatM3uUrls.contains(url)) return null;
    if (_ssCatalog != null && _ssCatalogUrl == url) return _ssCatalog;
    if (_ssCatalogInFlight != null) return _ssCatalogInFlight;

    final future = () async {
      try {
        final master = await _getM3UEntries(url);
        if (master.isEmpty) return null;
        final nested =
            m3uLooksLikeNestedMaster(master) || isSsIptvStyleUrl(url);
        if (!nested) {
          _flatM3uUrls.add(url);
          return null;
        }
        debugPrint('SS IPTV nested catalog: loading from $url');
        final catalog = await buildSsIptvCatalog(url, master, _getM3UEntries);
        _ssCatalog = catalog;
        _ssCatalogUrl = url;
        debugPrint(
          'SS IPTV catalog ready: live=${catalog.liveChannels.length} '
          'movieCats=${catalog.movieCategories.length} '
          'seriesCats=${catalog.seriesCategories.length}',
        );
        return catalog;
      } catch (e) {
        debugPrint('SS IPTV catalog error: $e');
        return null;
      } finally {
        _ssCatalogInFlight = null;
      }
    }();
    _ssCatalogInFlight = future;
    return future;
  }

  static String _cacheKey(UserModel user, [String? suffix]) {
    final base =
        '${user.serverInfo?.serverUrl ?? ""}_${user.userInfo?.username ?? ""}';
    return suffix != null ? '${base}_$suffix' : base;
  }

  static bool _isPlaylistMode(UserModel? user) {
    if (user == null || user.serverInfo?.serverUrl == null) return false;
    final u = user.userInfo?.username?.trim() ?? '';
    final p = user.userInfo?.password?.trim() ?? '';
    return u.isEmpty && p.isEmpty;
  }

  /// قواعد player_api المحتملة: رابط الدخول أولاً، ثم بدون منفذ، ثم مع منفذ اللوحة.
  static List<String> _playerApiBases(UserModel user) {
    final bases = <String>[];
    void add(String? raw) {
      var b = (raw ?? '').trim().replaceAll(RegExp(r'/+$'), '');
      if (b.isEmpty) return;
      if (!b.startsWith('http://') && !b.startsWith('https://')) return;
      // إزالة :80/:443 الزائدين
      b = b.replaceFirst(RegExp(r':80$'), '');
      b = b.replaceFirst(RegExp(r':443$'), '');
      if (!bases.contains(b)) bases.add(b);
    }

    add(user.serverInfo?.serverUrl);

    final host = user.serverInfo?.url?.trim() ?? '';
    final protocol =
        (user.serverInfo?.serverProtocol?.trim().isNotEmpty == true)
        ? user.serverInfo!.serverProtocol!.trim()
        : 'http';
    final port = user.serverInfo?.port?.trim() ?? '';
    if (host.isNotEmpty && host != 'null') {
      add('$protocol://$host');
      if (port.isNotEmpty && port != 'null' && port != '80' && port != '443') {
        add('$protocol://$host:$port');
      }
    }

    final uri = Uri.tryParse(user.serverInfo?.serverUrl ?? '');
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      add('${uri.scheme}://${uri.host}');
      if (uri.hasPort && uri.port != 80 && uri.port != 443) {
        add('${uri.scheme}://${uri.host}:${uri.port}');
      }
    }
    return bases;
  }

  Future<void> _persistWorkingServerUrl(UserModel user, String base) async {
    final current = user.serverInfo?.serverUrl?.trim() ?? '';
    if (base.isEmpty || base == current) return;
    final updated = UserModel(
      userInfo: user.userInfo,
      serverInfo: ServerInfo(
        serverUrl: base,
        url: user.serverInfo?.url,
        port: user.serverInfo?.port,
        httpsPort: user.serverInfo?.httpsPort,
        serverProtocol: user.serverInfo?.serverProtocol,
        rtmpPort: user.serverInfo?.rtmpPort,
        timezone: user.serverInfo?.timezone,
        timestampNow: user.serverInfo?.timestampNow,
        timeNow: user.serverInfo?.timeNow,
        process: user.serverInfo?.process,
      ),
    );
    await LocaleApi.saveUser(updated);
    debugPrint('Persisted working server base: $base');
  }

  Future<List<dynamic>> _getPlayerApiList({
    required UserModel user,
    required String action,
    Map<String, dynamic>? extraQuery,
    bool rawPlainForIsolate = false,
    Duration? receiveTimeout,
  }) async {
    final bases = _playerApiBases(user);
    final username = user.userInfo?.username ?? '';
    final password = user.userInfo?.password ?? '';
    for (final base in bases) {
      try {
        final response = await _dio.get(
          '$base/player_api.php',
          queryParameters: {
            'username': username,
            'password': password,
            'action': action,
            ...?extraQuery,
          },
          options: Options(
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: receiveTimeout ?? const Duration(seconds: 35),
            responseType: rawPlainForIsolate
                ? ResponseType.plain
                : ResponseType.json,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (response.statusCode != 200) continue;
        final data = response.data;
        if (rawPlainForIsolate) {
          final raw = data is String ? data : data?.toString() ?? '';
          if (raw.trim().isEmpty) continue;
          await _persistWorkingServerUrl(user, base);
          // يُعاد كنص ليُفك في Isolate مع التحويل للنماذج.
          return <dynamic>[raw];
        }
        final json = _normalizePlayerApiList(data);
        if (json.isEmpty) continue;
        await _persistWorkingServerUrl(user, base);
        debugPrint(
          'player_api OK action=$action base=$base count=${json.length}',
        );
        return json;
      } catch (e) {
        debugPrint('player_api fail action=$action base=$base err=$e');
      }
    }
    return const [];
  }

  /// بعض لوحات Xtream ترجع مصفوفة، وأخرى كائناً بمفاتيح رقمية — نوحّدها لقائمة.
  static List<dynamic> _normalizePlayerApiList(dynamic data) {
    if (data == null) return const [];
    if (data is List) return data;
    if (data is Map) {
      final map = Map<dynamic, dynamic>.from(data);
      if (map.containsKey('category_id') ||
          map.containsKey('category_name') ||
          map.containsKey('stream_id') ||
          map.containsKey('series_id') ||
          map.containsKey('name')) {
        return <dynamic>[map];
      }
      final values = map.values.toList(growable: false);
      if (values.isEmpty) return const [];
      if (values.every((e) => e is Map)) {
        return values;
      }
      return values.whereType<Map>().toList(growable: false);
    }
    if (data is String) {
      final t = data.trim();
      if (t.isEmpty) return const [];
      try {
        return _normalizePlayerApiList(jsonDecode(t));
      } catch (_) {
        return const [];
      }
    }
    return const [];
  }

  /// مسار ملف محلي إن كان الرابط `file://` أو مسار مطلق لـ `.m3u` / `.m3u8`.
  static String? localPlaylistFilePath(String playlistUrl) {
    final t = playlistUrl.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('file:')) {
      try {
        return Uri.parse(t).toFilePath();
      } catch (_) {
        return null;
      }
    }
    final lower = t.toLowerCase();
    final looksLocal =
        t.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(t);
    if (looksLocal && (lower.endsWith('.m3u') || lower.endsWith('.m3u8'))) {
      return t;
    }
    return null;
  }

  Future<List<M3UEntry>> _getM3UEntries(String playlistUrl) async {
    if (playlistUrl.trim().isEmpty) return [];
    final cached = _m3uCache[playlistUrl];
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final localPath = localPlaylistFilePath(playlistUrl);
      late final String raw;
      if (localPath != null) {
        final file = File(localPath);
        if (!await file.exists()) {
          debugPrint('M3U local file missing: $localPath');
          return [];
        }
        raw = (await file.readAsString()).trim();
      } else {
        final response = await _dio.get(
          playlistUrl,
          options: Options(
            headers: {
              'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
              'Accept':
                  'application/x-mpegURL, application/vnd.apple.mpegurl, text/plain, */*',
            },
            responseType: ResponseType.plain,
            validateStatus: (s) => s != null && s < 400,
          ),
        );
        if (response.statusCode != 200 || response.data == null) {
          debugPrint("M3U fetch failed: status=${response.statusCode}");
          return [];
        }
        raw = (response.data as String).trim();
      }
      if (raw.isEmpty) {
        debugPrint("M3U response empty");
        return [];
      }
      // فك M3U خارج الخيط الرئيسي حتى لا يتجمّد الواجهة (قوائم كبيرة).
      final entries = raw.length > 12000
          ? await Isolate.run(() => parseM3UContent(raw, playlistUrl))
          : parseM3UContent(raw, playlistUrl);
      debugPrint(
        "M3U parsed: ${entries.length} entries from ${raw.length} chars",
      );
      if (entries.isNotEmpty) _m3uCache[playlistUrl] = entries;
      return entries;
    } catch (e) {
      debugPrint("Error fetching M3U \$playlistUrl: \$e");
      return [];
    }
  }

  Future<List<CategoryModel>> getCategories(
    String type, {
    UserModel? userOverride,
  }) async {
    try {
      final user = userOverride ?? await LocaleApi.getUser();
      if (user == null) {
        debugPrint("User is Null");
        return [];
      }

      if (_isPlaylistMode(user)) {
        final playlistUrl = user.serverInfo!.serverUrl!;
        final ss = await _ensureSsCatalog(playlistUrl);
        if (ss != null) {
          if (type == 'get_live_categories') return ss.liveCategories;
          if (type == 'get_vod_categories') return ss.movieCategories;
          if (type == 'get_series_categories') return ss.seriesCategories;
          return [];
        }
        if (type == 'get_live_categories') {
          final entries = await _getM3UEntries(playlistUrl);
          return m3uEntriesToCategories(entries);
        }
        return [];
      }

      final cacheKey = _cacheKey(user, type);
      final cached = _categoriesCache[cacheKey];
      if (cached != null && cached.isValid) return cached.data;

      final inFlight = _categoriesInFlight[cacheKey];
      if (inFlight != null) return inFlight;

      final future = _fetchCategories(
        user: user,
        type: type,
        cacheKey: cacheKey,
      );
      _categoriesInFlight[cacheKey] = future;
      try {
        return await future;
      } finally {
        _categoriesInFlight.remove(cacheKey);
      }
    } catch (e) {
      debugPrint("Error $type: $e");
      return [];
    }
  }

  Future<List<CategoryModel>> _fetchCategories({
    required UserModel user,
    required String type,
    required String cacheKey,
  }) async {
    debugPrint("SERVER: ${user.serverInfo!.serverUrl}");
    var json = await _getPlayerApiList(user: user, action: type);
    var list = _parseCategoryList(json);

    if (list.isEmpty &&
        (type == 'get_vod_categories' || type == 'get_series_categories')) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      json = await _getPlayerApiList(user: user, action: type);
      list = _parseCategoryList(json);
    }

    // احتياط: بعض اللوحات لا تُرجع get_series_categories لكن السلاسل فيها category_id
    if (list.isEmpty && type == 'get_series_categories') {
      try {
        final series = await getSeriesChannels(null);
        list = _categoriesFromSeriesChannels(series);
      } catch (e) {
        debugPrint('series categories derive failed: $e');
      }
    }

    if (list.isNotEmpty) {
      _categoriesCache[cacheKey] = _ApiCacheEntry(
        list,
        DateTime.now().add(_categoriesCacheTtl),
      );
    }
    return list;
  }

  static List<CategoryModel> _parseCategoryList(List<dynamic> json) {
    final out = <CategoryModel>[];
    final seen = <String>{};
    for (final e in json) {
      if (e is! Map) continue;
      try {
        final c = CategoryModel.fromJson(Map<String, dynamic>.from(e));
        final id = (c.categoryId ?? '').trim();
        if (id.isEmpty || id == 'null') continue;
        if (!seen.add(id)) continue;
        final name = (c.categoryName ?? '').trim();
        out.add(
          CategoryModel(
            categoryId: id,
            categoryName: name.isEmpty || name == 'null' ? id : name,
            parentId: c.parentId,
          ),
        );
      } catch (_) {}
    }
    return out;
  }

  static List<CategoryModel> _categoriesFromSeriesChannels(
    List<ChannelSerie> series,
  ) {
    final byId = <String, CategoryModel>{};
    for (final s in series) {
      final id = (s.categoryId ?? '').trim();
      if (id.isEmpty || id == 'null') continue;
      byId.putIfAbsent(
        id,
        () => CategoryModel(categoryId: id, categoryName: id, parentId: '0'),
      );
    }
    return byId.values.toList();
  }

  Future<List<ChannelLive>> getLiveChannels(String catyId) async {
    try {
      final user = await LocaleApi.getUser();
      if (user == null) {
        debugPrint("User is Null");
        return [];
      }

      if (_isPlaylistMode(user)) {
        final playlistUrl = user.serverInfo!.serverUrl!;
        final ss = await _ensureSsCatalog(playlistUrl);
        if (ss != null) {
          if (catyId.isEmpty) return ss.liveChannels;
          return ss.liveChannels
              .where((c) => (c.categoryId ?? '') == catyId)
              .toList();
        }
        final entries = await _getM3UEntries(playlistUrl);
        return m3uEntriesToChannels(entries, categoryId: catyId);
      }

      final cacheKey = _cacheKey(user, 'live_$catyId');
      final cached = _liveChannelsCache[cacheKey];
      if (cached != null && cached.isValid) return cached.data;

      final payload = await _getPlayerApiList(
        user: user,
        action: 'get_live_streams',
        extraQuery: {'category_id': catyId},
        rawPlainForIsolate: true,
      );
      if (payload.isEmpty || payload.first is! String) return [];
      final raw = payload.first as String;
      debugPrint('SIZE live_$catyId chars: ${raw.length}');
      final list = await Isolate.run(() => _parseLiveChannelsFromRawJson(raw));
      if (list.isNotEmpty) {
        _liveChannelsCache[cacheKey] = _ApiCacheEntry(
          list,
          DateTime.now().add(_channelsCacheTtl),
        );
      }
      return list;
    } catch (e) {
      log("Error Channel $catyId: $e");
      return [];
    }
  }

  ///  جلب كل قنوات Live دفعة واحدة (بدون category_id) ثم الفرز محلياً.
  Future<List<ChannelLive>> getAllLiveStreams() async {
    try {
      final user = await LocaleApi.getUser();
      if (user == null) return const [];

      if (_isPlaylistMode(user)) {
        final playlistUrl = user.serverInfo!.serverUrl!;
        final ss = await _ensureSsCatalog(playlistUrl);
        if (ss != null) return ss.liveChannels;
        final entries = await _getM3UEntries(playlistUrl);
        return m3uEntriesToChannels(entries);
      }

      final cacheKey = _cacheKey(user, 'live_all');
      final cached = _liveChannelsCache[cacheKey];
      if (cached != null && cached.isValid) return cached.data;

      final payload = await _getPlayerApiList(
        user: user,
        action: 'get_live_streams',
        rawPlainForIsolate: true,
        receiveTimeout: const Duration(seconds: 120),
      );
      if (payload.isEmpty || payload.first is! String) return const [];
      final raw = payload.first as String;
      debugPrint('SIZE live_all chars: ${raw.length}');
      final list = await Isolate.run(() => _parseLiveChannelsFromRawJson(raw));
      if (list.isNotEmpty) {
        _liveChannelsCache[cacheKey] = _ApiCacheEntry(
          list,
          DateTime.now().add(_fullCatalogCacheTtl),
        );
      }
      return list;
    } catch (e) {
      log('Error getAllLiveStreams: $e');
      return const [];
    }
  }

  Future<List<ChannelMovie>> getMovieChannels(String? catyId) async {
    final label = 'api_get_vod_${catyId ?? "all"}';
    HomePerfLogger.start(label);
    try {
      final user = await LocaleApi.getUser();
      if (user == null) {
        debugPrint("User is Null");
        return [];
      }

      if (_isPlaylistMode(user)) {
        final playlistUrl = user.serverInfo!.serverUrl!;
        final ss = await _ensureSsCatalog(playlistUrl);
        if (ss == null) {
          HomePerfLogger.end(label, extra: 'playlist_flat_empty');
          return [];
        }
        if (catyId == null || catyId.isEmpty) {
          final all = <ChannelMovie>[];
          for (final list in ss.moviesByCategory.values) {
            all.addAll(list);
          }
          HomePerfLogger.end(label, extra: 'ss_all count=${all.length}');
          return all;
        }
        final list = ss.moviesByCategory[catyId] ?? [];
        HomePerfLogger.end(label, extra: 'ss_cat count=${list.length}');
        return list;
      }

      final cacheKey = _cacheKey(user, 'vod_${catyId ?? "all"}');
      final cached = _movieChannelsCache[cacheKey];
      if (cached != null && cached.isValid) {
        HomePerfLogger.end(
          label,
          extra: 'cache_hit count=${cached.data.length}',
        );
        return cached.data;
      }

      final inFlight = _movieInFlight[cacheKey];
      if (inFlight != null) {
        HomePerfLogger.end(label, extra: 'join_in_flight');
        return inFlight;
      }

      final future = _fetchMovieChannels(
        user: user,
        catyId: catyId,
        cacheKey: cacheKey,
        label: label,
      );
      _movieInFlight[cacheKey] = future;
      try {
        return await future;
      } finally {
        _movieInFlight.remove(cacheKey);
      }
    } catch (e) {
      debugPrint("Error Channel Movie $catyId: $e");
      HomePerfLogger.end(label, extra: 'error');
      return [];
    }
  }

  Future<List<ChannelMovie>> _fetchMovieChannels({
    required UserModel user,
    required String? catyId,
    required String cacheKey,
    required String label,
  }) async {
    final extra = <String, dynamic>{};
    if (catyId != null && catyId.isNotEmpty) {
      extra['category_id'] = catyId;
    }
    final isFullCatalog = catyId == null || catyId.isEmpty;
    HomePerfLogger.start('$label.network');
    final payload = await _getPlayerApiList(
      user: user,
      action: 'get_vod_streams',
      extraQuery: extra.isEmpty ? null : extra,
      // كتالوج All: نص خام + فك JSON في Isolate (يتجنب تجميد الخيط الرئيسي).
      rawPlainForIsolate: isFullCatalog,
      receiveTimeout: isFullCatalog
          ? const Duration(seconds: 60)
          : const Duration(seconds: 35),
    );
    HomePerfLogger.end('$label.network');

    List<ChannelMovie> list;
    if (isFullCatalog) {
      if (payload.isEmpty || payload.first is! String) {
        HomePerfLogger.end(label, extra: 'empty');
        return [];
      }
      final raw = payload.first as String;
      list = await Isolate.run(
        () => _parseMovieChannelsFromRawJson(raw, sortNewest: false),
      );
    } else {
      final json = payload;
      list = json.length > 40
          ? await Isolate.run(() => _parseMovieChannelMaps(json))
          : _parseMovieChannelMaps(json);
    }
    if (list.isEmpty) {
      HomePerfLogger.end(label, extra: 'empty');
      return [];
    }
    _movieChannelsCache[cacheKey] = _ApiCacheEntry(
      list,
      DateTime.now().add(
        isFullCatalog ? _fullCatalogCacheTtl : _channelsCacheTtl,
      ),
    );
    HomePerfLogger.end(label, extra: 'count=${list.length}');
    return list;
  }

  Future<List<ChannelSerie>> getSeriesChannels(String? catyId) async {
    final label = 'api_get_series_${catyId ?? "all"}';
    HomePerfLogger.start(label);
    try {
      final user = await LocaleApi.getUser();
      if (user == null) {
        debugPrint("User is Null");
        return [];
      }

      if (_isPlaylistMode(user)) {
        final playlistUrl = user.serverInfo!.serverUrl!;
        final ss = await _ensureSsCatalog(playlistUrl);
        if (ss == null) {
          HomePerfLogger.end(label, extra: 'playlist_flat_empty');
          return [];
        }
        if (catyId == null || catyId.isEmpty) {
          final all = <ChannelSerie>[];
          for (final list in ss.seriesByCategory.values) {
            all.addAll(list);
          }
          HomePerfLogger.end(label, extra: 'ss_all count=${all.length}');
          return all;
        }
        final list = ss.seriesByCategory[catyId] ?? [];
        HomePerfLogger.end(label, extra: 'ss_cat count=${list.length}');
        return list;
      }

      final cacheKey = _cacheKey(user, 'series_${catyId ?? "all"}');
      final cached = _seriesChannelsCache[cacheKey];
      if (cached != null && cached.isValid) {
        HomePerfLogger.end(
          label,
          extra: 'cache_hit count=${cached.data.length}',
        );
        return cached.data;
      }

      final inFlight = _seriesInFlight[cacheKey];
      if (inFlight != null) {
        HomePerfLogger.end(label, extra: 'join_in_flight');
        return inFlight;
      }

      final future = _fetchSeriesChannels(
        user: user,
        catyId: catyId,
        cacheKey: cacheKey,
        label: label,
      );
      _seriesInFlight[cacheKey] = future;
      try {
        return await future;
      } finally {
        _seriesInFlight.remove(cacheKey);
      }
    } catch (e) {
      debugPrint("Error Channel Series $catyId: $e");
      HomePerfLogger.end(label, extra: 'error');
      return [];
    }
  }

  Future<List<ChannelSerie>> _fetchSeriesChannels({
    required UserModel user,
    required String? catyId,
    required String cacheKey,
    required String label,
  }) async {
    final extra = <String, dynamic>{};
    if (catyId != null && catyId.isNotEmpty) {
      extra['category_id'] = catyId;
    }
    final isFullCatalog = catyId == null || catyId.isEmpty;
    HomePerfLogger.start('$label.network');
    final payload = await _getPlayerApiList(
      user: user,
      action: 'get_series',
      extraQuery: extra.isEmpty ? null : extra,
      rawPlainForIsolate: isFullCatalog,
      receiveTimeout: isFullCatalog
          ? const Duration(seconds: 60)
          : const Duration(seconds: 35),
    );
    HomePerfLogger.end('$label.network');

    List<ChannelSerie> list;
    if (isFullCatalog) {
      if (payload.isEmpty || payload.first is! String) {
        HomePerfLogger.end(label, extra: 'empty');
        return [];
      }
      final raw = payload.first as String;
      list = await Isolate.run(
        () => _parseSerieChannelsFromRawJson(raw, sortNewest: false),
      );
    } else {
      final json = payload;
      list = json.length > 40
          ? await Isolate.run(() => _parseSerieChannelMaps(json))
          : _parseSerieChannelMaps(json);
    }
    if (list.isEmpty) {
      HomePerfLogger.end(label, extra: 'empty');
      return [];
    }
    _seriesChannelsCache[cacheKey] = _ApiCacheEntry(
      list,
      DateTime.now().add(
        isFullCatalog ? _fullCatalogCacheTtl : _channelsCacheTtl,
      ),
    );
    HomePerfLogger.end(label, extra: 'count=${list.length}');
    return list;
  }

  Future<List<ChannelMovie>> getHomeRecentMovies({int limit = 13}) async {
    const label = 'api_home_random_movies';
    HomePerfLogger.start(label);
    try {
      final user = await LocaleApi.getUser();
      if (user == null) return [];

      var maps = await _fetchHomeMapsWithFallback(
        user: user,
        action: 'get_vod_streams',
        idKey: 'stream_id',
        limit: limit,
        label: label,
      );
      var list = HomePerfLogger.timeSync('$label.to_models', () {
        return maps.map(ChannelMovie.fromJson).toList();
      });

      if (list.isEmpty) {
        HomePerfLogger.mark('$label.catalog_fallback');
        final catalog = await getMovieChannels(null);
        if (catalog.isNotEmpty) {
          list = catalog.length > limit ? catalog.sublist(0, limit) : catalog;
        }
      }

      HomePerfLogger.end(label, extra: 'count=${list.length}');
      return list;
    } catch (e) {
      debugPrint("getHomeRecentMovies error: $e");
      HomePerfLogger.end(label, extra: 'error');
      return [];
    }
  }

  Future<List<ChannelSerie>> getHomeRecentSeries({int limit = 13}) async {
    const label = 'api_home_random_series';
    HomePerfLogger.start(label);
    try {
      final user = await LocaleApi.getUser();
      if (user == null) return [];

      var maps = await _fetchHomeMapsWithFallback(
        user: user,
        action: 'get_series',
        idKey: 'series_id',
        limit: limit,
        label: label,
      );
      var list = HomePerfLogger.timeSync('$label.to_models', () {
        return maps.map(ChannelSerie.fromJson).toList();
      });

      if (list.isEmpty) {
        HomePerfLogger.mark('$label.catalog_fallback');
        final catalog = await getSeriesChannels(null);
        if (catalog.isNotEmpty) {
          list = catalog.length > limit ? catalog.sublist(0, limit) : catalog;
        }
      }

      HomePerfLogger.end(label, extra: 'count=${list.length}');
      return list;
    } catch (e) {
      debugPrint("getHomeRecentSeries error: $e");
      HomePerfLogger.end(label, extra: 'error');
      return [];
    }
  }

  /// أحدث الأفلام من السيرفر (last_modified / added) — حد أقصى [limit].
  Future<List<ChannelMovie>> getRecentlyAddedMovies({int limit = 32}) async {
    const label = 'api_recently_added_movies';
    HomePerfLogger.start(label);
    try {
      final user = await LocaleApi.getUser();
      if (user == null) return [];

      HomePerfLogger.start('$label.network');
      final payload = await _getPlayerApiList(
        user: user,
        action: 'get_vod_streams',
        rawPlainForIsolate: true,
        receiveTimeout: const Duration(seconds: 60),
      );
      HomePerfLogger.end('$label.network');
      if (payload.isEmpty || payload.first is! String) {
        HomePerfLogger.end(label, extra: 'empty');
        return [];
      }
      final raw = payload.first as String;
      final maps = await Isolate.run(
        () => parseRecentlyAddedMovieMaps([raw, limit]),
      );
      final list = maps.map(ChannelMovie.fromJson).toList(growable: false);
      HomePerfLogger.end(label, extra: 'count=${list.length}');
      return list;
    } catch (e) {
      debugPrint('getRecentlyAddedMovies error: $e');
      HomePerfLogger.end(label, extra: 'error');
      return [];
    }
  }

  /// أحدث المسلسلات من السيرفر — يتضمن تحديث الحلقات عبر last_modified.
  Future<List<ChannelSerie>> getRecentlyAddedSeries({int limit = 32}) async {
    const label = 'api_recently_added_series';
    HomePerfLogger.start(label);
    try {
      final user = await LocaleApi.getUser();
      if (user == null) return [];

      HomePerfLogger.start('$label.network');
      final payload = await _getPlayerApiList(
        user: user,
        action: 'get_series',
        rawPlainForIsolate: true,
        receiveTimeout: const Duration(seconds: 60),
      );
      HomePerfLogger.end('$label.network');
      if (payload.isEmpty || payload.first is! String) {
        HomePerfLogger.end(label, extra: 'empty');
        return [];
      }
      final raw = payload.first as String;
      final maps = await Isolate.run(
        () => parseRecentlyAddedSeriesMaps([raw, limit]),
      );
      final list = maps.map(ChannelSerie.fromJson).toList(growable: false);
      HomePerfLogger.end(label, extra: 'count=${list.length}');
      return list;
    } catch (e) {
      debugPrint('getRecentlyAddedSeries error: $e');
      HomePerfLogger.end(label, extra: 'error');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchHomeMapsWithFallback({
    required UserModel user,
    required String action,
    required String idKey,
    required int limit,
    required String label,
  }) async {
    final serverUrl = user.serverInfo?.serverUrl?.trim() ?? '';
    final username = user.userInfo?.username?.trim() ?? '';
    final password = user.userInfo?.password?.trim() ?? '';
    if (serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
      return const [];
    }

    final request = HomeRecentIsolateRequest(
      serverUrl: serverUrl,
      username: username,
      password: password,
      action: action,
      idKey: idKey,
      limit: limit,
    );

    var maps = await HomePerfLogger.timeAsync(
      '$label.isolate_fetch',
      () => fetchHomeRecentMapsViaIsolate(request),
    );
    if (maps.isNotEmpty) return maps;

    maps = await HomePerfLogger.timeAsync(
      '$label.dio_plain',
      () => _fetchHomeMapsDioPlain(
        serverUrl: serverUrl,
        username: username,
        password: password,
        action: action,
        idKey: idKey,
        limit: limit,
      ),
    );
    return maps;
  }

  Future<List<Map<String, dynamic>>> _fetchHomeMapsDioPlain({
    required String serverUrl,
    required String username,
    required String password,
    required String action,
    required String idKey,
    required int limit,
  }) async {
    try {
      final uri = buildPlayerApiUri(
        serverUrl: serverUrl,
        username: username,
        password: password,
        action: action,
      );
      final response = await _dio.get<String>(
        uri.toString(),
        options: Options(responseType: ResponseType.plain),
      );
      if (response.statusCode != 200) return const [];
      final raw = response.data?.replaceFirst('\uFEFF', '').trim() ?? '';
      if (raw.isEmpty) return const [];

      if (idKey == 'stream_id') {
        return Isolate.run(() => parseHomeRecentMovieMaps([raw, limit]));
      }
      return Isolate.run(() => parseHomeRecentSeriesMaps([raw, limit]));
    } catch (e) {
      debugPrint('_fetchHomeMapsDioPlain error ($action): $e');
      return const [];
    }
  }

  static Future<dynamic> _getPlayerApiRaw({
    required UserModel user,
    required String action,
    Map<String, dynamic>? extraQuery,
  }) async {
    final bases = _playerApiBases(user);
    final username = user.userInfo?.username ?? '';
    final password = user.userInfo?.password ?? '';
    for (final base in bases) {
      try {
        final response = await _dio.get(
          '$base/player_api.php',
          queryParameters: {
            'username': username,
            'password': password,
            'action': action,
            ...?extraQuery,
          },
          options: Options(
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 35),
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (response.statusCode != 200) continue;
        final data = response.data;
        final decoded = data is String
            ? jsonDecode(data.replaceFirst('\uFEFF', '').trim())
            : data;
        if (decoded == null) continue;
        if (decoded is List && decoded.isEmpty) continue;
        if (decoded is Map && decoded.isEmpty) continue;
        return decoded;
      } catch (_) {}
    }
    return null;
  }

  static Future<MovieDetail?> getMovieDetails(String movieId) async {
    try {
      final user = await LocaleApi.getUser();
      if (user == null) return null;

      if (_isPlaylistMode(user) || _isHttpStreamId(movieId)) {
        ChannelMovie? found;
        if (_isPlaylistMode(user)) {
          final playlistUrl = user.serverInfo?.serverUrl ?? '';
          final api = IpTvApi();
          final ss = await api._ensureSsCatalog(playlistUrl);
          if (ss != null) {
            for (final list in ss.moviesByCategory.values) {
              for (final m in list) {
                if (m.streamId == movieId) {
                  found = m;
                  break;
                }
              }
              if (found != null) break;
            }
          }
        }
        return MovieDetail(
          info: Info(movieImage: found?.streamIcon, plot: ''),
          movieData: MovieData(
            streamId: movieId,
            name: found?.name ?? 'Movie',
            categoryId: found?.categoryId,
            containerExtension: found?.containerExtension ?? 'mp4',
            directSource: '1',
          ),
        );
      }

      final data = await _getPlayerApiRaw(
        user: user,
        action: 'get_vod_info',
        extraQuery: {'vod_id': movieId},
      );
      if (data is Map) {
        try {
          return MovieDetail.fromJson(Map<String, dynamic>.from(data));
        } catch (_) {
          return null;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<SerieDetails?> getSerieDetails(String serieId) async {
    try {
      final user = await LocaleApi.getUser();
      if (user == null) return null;

      if (_isPlaylistMode(user) ||
          _isHttpStreamId(serieId) ||
          serieId.startsWith('m3u-flat:')) {
        final playlistUrl = user.serverInfo?.serverUrl ?? '';
        final api = IpTvApi();
        final ss = await api._ensureSsCatalog(playlistUrl);
        if (ss != null) {
          ChannelSerie? meta;
          for (final list in ss.seriesByCategory.values) {
            for (final s in list) {
              if (s.seriesId == serieId) {
                meta = s;
                break;
              }
            }
            if (meta != null) break;
          }
          var entries = ss.seriesEpisodeEntries[serieId];
          if (entries == null || entries.isEmpty) {
            if (_isHttpStreamId(serieId)) {
              entries = await api._getM3UEntries(serieId);
            }
          }
          if (entries != null && entries.isNotEmpty) {
            return serieDetailsFromM3uEntries(
              serieId,
              meta?.name ?? 'Series',
              meta?.cover,
              entries,
            );
          }
        }
        if (_isHttpStreamId(serieId)) {
          final api2 = IpTvApi();
          final entries = await api2._getM3UEntries(serieId);
          if (entries.isNotEmpty) {
            return serieDetailsFromM3uEntries(serieId, 'Series', null, entries);
          }
        }
        return null;
      }

      final data = await _getPlayerApiRaw(
        user: user,
        action: 'get_series_info',
        extraQuery: {'series_id': serieId},
      );
      if (data is Map) {
        try {
          return SerieDetails.fromJson(Map<String, dynamic>.from(data));
        } catch (_) {
          return null;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<EpgModel>> getEPGbyStreamId(String streamId) async {
    try {
      final user = await LocaleApi.getUser();
      if (user == null) return [];

      if (IpTvApi._isPlaylistMode(user)) return [];

      final data = await _getPlayerApiRaw(
        user: user,
        action: 'get_short_epg',
        extraQuery: {'stream_id': streamId},
      );
      if (data is Map && data['epg_listings'] is List) {
        final List<dynamic> json = data['epg_listings'] as List<dynamic>;
        return json.map((e) => EpgModel.fromJson(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}

List<ChannelLive> _parseLiveChannelMaps(List<dynamic> json) {
  return json
      .whereType<Map>()
      .map((e) => ChannelLive.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: false);
}

List<ChannelLive> _parseLiveChannelsFromRawJson(String raw) {
  final decoded = jsonDecode(raw);
  final json = IpTvApi._normalizePlayerApiList(decoded);
  return _parseLiveChannelMaps(json);
}

List<ChannelMovie> _parseMovieChannelsFromRawJson(
  String raw, {
  bool sortNewest = false,
}) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return _parseMovieChannelMaps(decoded, sortNewest: sortNewest);
}

List<ChannelSerie> _parseSerieChannelsFromRawJson(
  String raw, {
  bool sortNewest = false,
}) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return _parseSerieChannelMaps(decoded, sortNewest: sortNewest);
}

List<ChannelMovie> _parseMovieChannelMaps(
  List<dynamic> json, {
  bool sortNewest = false,
}) {
  final list = json
      .whereType<Map>()
      .map((e) => ChannelMovie.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: sortNewest);
  if (sortNewest && list.length > 1) {
    list.sort((a, b) {
      final c = b.sortTimestamp.compareTo(a.sortTimestamp);
      if (c != 0) return c;
      return (a.name ?? '').toLowerCase().compareTo(
        (b.name ?? '').toLowerCase(),
      );
    });
  }
  return list;
}

List<ChannelSerie> _parseSerieChannelMaps(
  List<dynamic> json, {
  bool sortNewest = false,
}) {
  final list = json
      .whereType<Map>()
      .map((e) => ChannelSerie.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: sortNewest);
  if (sortNewest && list.length > 1) {
    list.sort((a, b) {
      final c = b.sortTimestamp.compareTo(a.sortTimestamp);
      if (c != 0) return c;
      return (a.name ?? '').toLowerCase().compareTo(
        (b.name ?? '').toLowerCase(),
      );
    });
  }
  return list;
}
