part of '../api/api.dart';

class FavoriteLocale {
  String _normalizeServerPart(String serverUrl) {
    var url = serverUrl.trim().toLowerCase();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url.isNotEmpty
        ? url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        : 'default';
  }

  Future<String?> _storageKey(String suffix) async {
    final user = await LocaleApi.getUser();
    if (user == null) return null;
    final username = (user.userInfo?.username ?? '').trim();
    if (username.isEmpty) return null;
    final serverUrl = (user.serverInfo?.serverUrl ?? '').trim();
    final serverPart = _normalizeServerPart(serverUrl);
    return '${username}_${serverPart}_$suffix';
  }

  String? _legacyStorageKey(String suffix, UserModel user) {
    final username = (user.userInfo?.username ?? '').trim();
    if (username.isEmpty) return null;
    return '$username-$suffix';
  }

  String _legacyMigratedFlagKey(String suffix, UserModel user) {
    final username = (user.userInfo?.username ?? '').trim();
    return '${username}_legacy_fav_migrated_$suffix';
  }

  String _encodeChannelList<T>(
    List<T> items,
    Map<String, dynamic> Function(T) toJson,
  ) {
    return jsonEncode(items.map(toJson).toList());
  }

  List<ChannelMovie> _decodeMovieList(dynamic data) {
    if (data == null) return [];
    try {
      final parsed = data is String ? jsonDecode(data) : data;
      if (parsed is! List) return [];
      return parsed.map((e) {
        if (e is String) {
          return ChannelMovie.fromJson(jsonDecode(e) as Map<String, dynamic>);
        }
        return ChannelMovie.fromJson(Map<String, dynamic>.from(e as Map));
      }).toList();
    } catch (e) {
      debugPrint('Error: decode fav movies: $e');
      return [];
    }
  }

  List<ChannelSerie> _decodeSerieList(dynamic data) {
    if (data == null) return [];
    try {
      final parsed = data is String ? jsonDecode(data) : data;
      if (parsed is! List) return [];
      return parsed.map((e) {
        if (e is String) {
          return ChannelSerie.fromJson(jsonDecode(e) as Map<String, dynamic>);
        }
        return ChannelSerie.fromJson(Map<String, dynamic>.from(e as Map));
      }).toList();
    } catch (e) {
      debugPrint('Error: decode fav series: $e');
      return [];
    }
  }

  List<ChannelLive> _decodeLiveList(dynamic data) {
    if (data == null) return [];
    try {
      final parsed = data is String ? jsonDecode(data) : data;
      if (parsed is! List) return [];
      return parsed.map((e) {
        if (e is String) {
          return ChannelLive.fromJson(jsonDecode(e) as Map<String, dynamic>);
        }
        return ChannelLive.fromJson(Map<String, dynamic>.from(e as Map));
      }).toList();
    } catch (e) {
      debugPrint('Error: decode fav lives: $e');
      return [];
    }
  }

  Future<dynamic> _readWithLegacyMigration({
    required String suffix,
    required Future<String?> Function() keyBuilder,
  }) async {
    final key = await keyBuilder();
    if (key == null) return null;
    final stored = favoritesLocale.read(key);
    if (stored != null) return stored;

    final user = await LocaleApi.getUser();
    if (user == null) return null;

    // ترحيل المفاتيح القديمة مرة واحدة فقط — لا ننسخها لسيرفر آخر عند التبديل.
    final migratedFlag = _legacyMigratedFlagKey(suffix, user);
    if (favoritesLocale.read(migratedFlag) == true) return null;

    final legacyKey = _legacyStorageKey(suffix, user);
    if (legacyKey == null) return null;
    final legacy = favoritesLocale.read(legacyKey);
    if (legacy == null) return null;

    await favoritesLocale.write(key, legacy);
    await favoritesLocale.write(migratedFlag, true);
    await favoritesLocale.remove(legacyKey);
    return legacy;
  }

  Future<bool> saveFavoriteMovie(List<ChannelMovie> movies) async {
    try {
      final name = await _storageKey('fav-movies');
      if (name == null) {
        return false;
      }

      await favoritesLocale.write(
        name,
        _encodeChannelList(movies, (m) => m.toJson()),
      );

      return true;
    } catch (e) {
      debugPrint("Error: Fav Movie: $e");
      return false;
    }
  }

  Future<bool> saveFavoriteSerie(List<ChannelSerie> series) async {
    try {
      final name = await _storageKey('fav-series');
      if (name == null) {
        return false;
      }

      await favoritesLocale.write(
        name,
        _encodeChannelList(series, (s) => s.toJson()),
      );

      return true;
    } catch (e) {
      debugPrint("Error: Fav Series: $e");
      return false;
    }
  }

  Future<List<ChannelMovie>> getFavMovies() async {
    try {
      final data = await _readWithLegacyMigration(
        suffix: 'fav-movies',
        keyBuilder: () => _storageKey('fav-movies'),
      );
      return _decodeMovieList(data);
    } catch (e) {
      debugPrint("Error: GetFav Movie: $e");
      return [];
    }
  }

  Future<List<ChannelSerie>> getFavSeries() async {
    try {
      final data = await _readWithLegacyMigration(
        suffix: 'fav-series',
        keyBuilder: () => _storageKey('fav-series'),
      );
      return _decodeSerieList(data);
    } catch (e) {
      debugPrint("Error: GetFav Series: $e");
      return [];
    }
  }

  Future<List<ChannelLive>> getFavLives() async {
    try {
      final data = await _readWithLegacyMigration(
        suffix: 'fav-lives',
        keyBuilder: () => _storageKey('fav-lives'),
      );
      return _decodeLiveList(data);
    } catch (e) {
      debugPrint("Error: GetFav Lives: $e");
      return [];
    }
  }

  Future<bool> saveFavoriteLives(List<ChannelLive> series) async {
    try {
      final name = await _storageKey('fav-lives');
      if (name == null) {
        return false;
      }

      await favoritesLocale.write(
        name,
        _encodeChannelList(series, (c) => c.toJson()),
      );

      return true;
    } catch (e) {
      debugPrint("Error: Fav Lives: $e");
      return false;
    }
  }
}

class WatchingLocale {
  String _normalizeServerPart(String serverUrl) {
    var url = serverUrl.trim().toLowerCase();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url.isNotEmpty
        ? url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        : 'default';
  }

  Future<String?> _storageKey(String suffix) async {
    final user = await LocaleApi.getUser();
    if (user == null) return null;
    final username = (user.userInfo?.username ?? '').trim();
    if (username.isEmpty) return null;
    final serverUrl = (user.serverInfo?.serverUrl ?? '').trim();
    final serverPart = _normalizeServerPart(serverUrl);
    return '${username}_${serverPart}_$suffix';
  }

  String? _legacyStorageKey(String suffix, UserModel user) {
    final username = (user.userInfo?.username ?? '').trim();
    if (username.isEmpty) return null;
    return '$username-$suffix';
  }

  String _legacyMigratedFlagKey(String suffix, UserModel user) {
    final username = (user.userInfo?.username ?? '').trim();
    return '${username}_legacy_watch_migrated_$suffix';
  }

  Future<dynamic> _readWithLegacyMigration(String suffix) async {
    final key = await _storageKey(suffix);
    if (key == null) return null;
    final stored = favoritesLocale.read(key);
    if (stored != null) return stored;

    final user = await LocaleApi.getUser();
    if (user == null) return null;

    // ترحيل المفاتيح القديمة مرة واحدة فقط — لا ننسخها لسيرفر آخر عند التبديل.
    final migratedFlag = _legacyMigratedFlagKey(suffix, user);
    if (favoritesLocale.read(migratedFlag) == true) return null;

    final legacyKey = _legacyStorageKey(suffix, user);
    if (legacyKey == null) return null;
    final legacy = favoritesLocale.read(legacyKey);
    if (legacy == null) return null;

    await favoritesLocale.write(key, legacy);
    await favoritesLocale.write(migratedFlag, true);
    await favoritesLocale.remove(legacyKey);
    return legacy;
  }

  String _encodeWatchingList(List<WatchingModel> items) {
    return jsonEncode(items.map((e) => e.toJson()).toList());
  }

  /// يدعم التنسيق الجديد + القيم القديمة (قائمة jsonEncode.toString).
  List<WatchingModel> _decodeWatchingList(dynamic data) {
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      if (decoded is! List) return [];
      final out = <WatchingModel>[];
      for (final e in decoded) {
        try {
          if (e is Map) {
            out.add(WatchingModel.fromJson(Map<String, dynamic>.from(e)));
          } else if (e is String) {
            final inner = jsonDecode(e);
            if (inner is Map) {
              out.add(WatchingModel.fromJson(Map<String, dynamic>.from(inner)));
            }
          }
        } catch (_) {}
      }
      return out;
    } catch (e) {
      debugPrint('Error: decode watching list: $e');
      return [];
    }
  }

  Future<bool> saveWatchingMovie(List<WatchingModel> movies) async {
    try {
      final name = await _storageKey('watch-movies');
      if (name == null) return false;
      await favoritesLocale.write(name, _encodeWatchingList(movies));
      return true;
    } catch (e) {
      debugPrint("Error: watch Movie: $e");
      return false;
    }
  }

  Future<bool> saveWatchSerie(List<WatchingModel> series) async {
    try {
      final name = await _storageKey('watch-series');
      if (name == null) return false;
      await favoritesLocale.write(name, _encodeWatchingList(series));
      return true;
    } catch (e) {
      debugPrint("Error: watch Series: $e");
      return false;
    }
  }

  Future<bool> saveWatchLive(List<WatchingModel> series) async {
    try {
      final name = await _storageKey('watch-live');
      if (name == null) return false;
      await favoritesLocale.write(name, _encodeWatchingList(series));
      return true;
    } catch (e) {
      debugPrint("Error: watch Live: $e");
      return false;
    }
  }

  Future<List<WatchingModel>> getWatchingMovies() async {
    try {
      final data = await _readWithLegacyMigration('watch-movies');
      if (data != null) return _decodeWatchingList(data);
      return [];
    } catch (e) {
      debugPrint("Error: Getwatch Movie: $e");
      return [];
    }
  }

  Future<List<WatchingModel>> getWatchingSeries() async {
    try {
      final data = await _readWithLegacyMigration('watch-series');
      if (data != null) return _decodeWatchingList(data);
      return [];
    } catch (e) {
      debugPrint("Error: Getwatch Series: $e");
      return [];
    }
  }

  Future<List<WatchingModel>> getWatchingLives() async {
    try {
      final data = await _readWithLegacyMigration('watch-live');
      if (data != null) return _decodeWatchingList(data);
      return [];
    } catch (e) {
      debugPrint("Error: Getwatch Live: $e");
      return [];
    }
  }

  Future<void> deleteWatching() async {
    final user = await LocaleApi.getUser();
    if (user == null) return;

    for (final suffix in ['watch-movies', 'watch-series', 'watch-live']) {
      final key = await _storageKey(suffix);
      if (key != null) await favoritesLocale.remove(key);
      final legacyKey = _legacyStorageKey(suffix, user);
      if (legacyKey != null) await favoritesLocale.remove(legacyKey);
    }
  }
}
