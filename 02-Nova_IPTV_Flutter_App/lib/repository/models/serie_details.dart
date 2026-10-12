class SerieDetails {
  final List<Season>? seasons;
  final InfoSerie? info;
  final Map<String, List<Episode?>?>? episodes;

  SerieDetails({
    this.seasons,
    this.info,
    this.episodes,
  });

  /// حلقات الموسم الذي يحتوي الحلقة [episodeId] — لعرض قائمة الحلقات في المشغّل.
  List<Episode?>? episodesInSameSeasonAs(String? episodeId) {
    final id = (episodeId ?? '').trim();
    if (id.isEmpty) return null;
    final map = episodes;
    if (map == null || map.isEmpty) return null;
    for (final entry in map.entries) {
      final list = entry.value;
      if (list == null || list.isEmpty) continue;
      for (final ep in list) {
        if (ep == null) continue;
        if (ep.id?.toString().trim() == id) {
          return list;
        }
      }
    }
    return null;
  }

  SerieDetails.fromJson(Map<String, dynamic> json)
      : seasons = _parseSeasons(json),
        info = _parseInfo(json['info']),
        episodes = _parseEpisodes(json['episodes']);

  static InfoSerie? _parseInfo(dynamic raw) {
    // Xtream panels often return "info": [] (PHP empty array) instead of {}.
    if (raw is List) {
      if (raw.isNotEmpty && raw.first is Map) {
        raw = Map<String, dynamic>.from(raw.first as Map);
      } else {
        raw = <String, dynamic>{};
      }
    }
    if (raw is! Map) return null;
    try {
      return InfoSerie.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return InfoSerie();
    }
  }

  static List<Season>? _parseSeasons(Map<String, dynamic> json) {
    final raw = json['season'] ?? json['seasons'];
    if (raw == null) return [];
    if (raw is! List) return [];
    final out = <Season>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(Season.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        // Skip malformed season rows from panel.
      }
    }
    return out;
  }

  static Map<String, List<Episode?>?>? _parseEpisodes(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw).map((key, value) {
      final list = value is List ? value : const <dynamic>[];
      final eps = <Episode?>[];
      for (final e in list) {
        if (e is! Map) continue;
        try {
          eps.add(Episode.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {
          // Skip malformed episode rows.
        }
      }
      return MapEntry(key.toString(), eps);
    });
  }

  Map<String, dynamic> toJson() => {
        'seasons': seasons,
        'info': info?.toJson(),
        //'episodes': episodes?.toJson()
      };
}

class Season {
  final String? airDate;
  final String? episodeCount;
  final String? id;
  final String? name;
  final String? overview;
  final String? seasonNumber;
  final String? cover;
  final String? coverBig;

  Season({
    this.airDate,
    this.episodeCount,
    this.id,
    this.name,
    this.overview,
    this.seasonNumber,
    this.cover,
    this.coverBig,
  });

  Season.fromJson(Map<String, dynamic> json)
      : airDate = json['air_date']?.toString(),
        episodeCount = json['episode_count']?.toString(),
        id = json['id']?.toString(),
        name = json['name']?.toString(),
        overview = json['overview']?.toString(),
        seasonNumber = json['season_number']?.toString(),
        cover = json['cover']?.toString(),
        coverBig = json['cover_big']?.toString();

  Map<String, dynamic> toJson() => {
        'air_date': airDate,
        'episode_count': episodeCount,
        'id': id,
        'name': name,
        'overview': overview,
        'season_number': seasonNumber,
        'cover': cover,
        'cover_big': coverBig
      };
}

class InfoSerie {
  final String? name;
  final String? cover;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? lastModified;
  final String? rating;
  final String? rating5based;
  final String? tmdbId;
  final List<String>? backdropPath;
  final String? youtubeTrailer;
  final String? episodeRunTime;
  final String? categoryId;

  InfoSerie({
    this.name,
    this.cover,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.lastModified,
    this.rating,
    this.rating5based,
    this.tmdbId,
    this.backdropPath,
    this.youtubeTrailer,
    this.episodeRunTime,
    this.categoryId,
  });

  InfoSerie.fromJson(Map<String, dynamic> json)
      : name = _firstStr(json, const ['name', 'title']),
        cover = _firstStr(json, const [
          'cover',
          'cover_big',
          'movie_image',
          'stream_icon',
          'poster',
          'image',
        ]),
        plot = _firstStr(json, const [
          'plot',
          'description',
          'overview',
          'synopsis',
        ]),
        cast = _firstStr(json, const ['cast', 'actors', 'stars']),
        director = _firstStr(json, const ['director', 'directors']),
        genre = _firstStr(json, const ['genre', 'genres', 'category']),
        releaseDate = _firstStr(json, const [
          'releaseDate',
          'release_date',
          'releasedate',
          'released_date',
        ]),
        lastModified = json['last_modified']?.toString(),
        rating = _firstStr(json, const ['rating', 'rate', 'score']),
        rating5based = json['rating_5based']?.toString(),
        tmdbId = _firstStr(json, const ['tmdb_id', 'tmdb']),
        backdropPath = _mergeBackdropPaths(json),
        youtubeTrailer = _firstStr(json, const [
          'youtube_trailer',
          'trailer',
          'youtube',
          'yt_trailer',
        ]),
        episodeRunTime = _firstStr(json, const [
          'episode_run_time',
          'duration',
          'runtime',
        ]),
        categoryId = json['category_id']?.toString();

  static String? _str(dynamic v) {
    if (v == null) return null;
    if (v is bool || v is Map || v is List) return null;
    final t = v.toString().trim();
    if (t.isEmpty || t.toLowerCase() == 'null' || t == 'false') return null;
    return t;
  }

  static String? _firstStr(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final s = _str(json[k]);
      if (s != null) return s;
    }
    return null;
  }

  static List<String> _mergeBackdropPaths(Map<String, dynamic> json) {
    final fromPath = _parseBackdropPath(json['backdrop_path']);
    if (fromPath.isNotEmpty) return fromPath;
    final single = _str(json['backdrop']);
    if (single != null) return <String>[single];
    return <String>[];
  }

  static List<String> _parseBackdropPath(dynamic raw) {
    if (raw == null) return [];
    if (raw is String) {
      final t = raw.trim();
      return t.isEmpty || t == 'null' ? [] : [t];
    }
    if (raw is List) {
      final out = <String>[];
      for (final e in raw) {
        if (e == null) continue;
        if (e is String) {
          final t = e.trim();
          if (t.isNotEmpty && t != 'null') out.add(t);
          continue;
        }
        if (e is Map) {
          final u = _str(
            e['url'] ??
                e['file_path'] ??
                e['path'] ??
                e['image'] ??
                e['src'] ??
                e['cover'],
          );
          if (u != null) out.add(u);
          continue;
        }
        final t = e.toString().trim();
        if (t.isNotEmpty && t != 'null') out.add(t);
      }
      return out;
    }
    if (raw is Map) {
      final u = _str(
        raw['url'] ?? raw['file_path'] ?? raw['path'] ?? raw['image'],
      );
      return u == null ? [] : [u];
    }
    return [];
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'cover': cover,
        'plot': plot,
        'cast': cast,
        'director': director,
        'genre': genre,
        'releaseDate': releaseDate,
        'last_modified': lastModified,
        'rating': rating,
        'rating_5based': rating5based,
        'tmdb_id': tmdbId,
        'backdrop_path': backdropPath,
        'youtube_trailer': youtubeTrailer,
        'episode_run_time': episodeRunTime,
        'category_id': categoryId
      };
}

class Episode {
  final String? id;
  final String? episodeNum;
  final String? title;
  final String? containerExtension;
  final InfoEpisode? info;
  final String? customSid;
  final String? added;
  final String? season;
  final String? directSource;

  Episode({
    this.id,
    this.episodeNum,
    this.title,
    this.containerExtension,
    this.info,
    this.customSid,
    this.added,
    this.season,
    this.directSource,
  });

  Episode.fromJson(Map<String, dynamic> json)
      : id = json['id']?.toString(),
        episodeNum = json['episode_num']?.toString(),
        title = json['title']?.toString(),
        containerExtension = json['container_extension']?.toString(),
        info = _parseEpisodeInfo(json['info']),
        customSid = json['custom_sid']?.toString(),
        added = json['added']?.toString(),
        season = json['season']?.toString(),
        directSource = json['direct_source']?.toString();

  static InfoEpisode? _parseEpisodeInfo(dynamic raw) {
    if (raw == null || raw is List) return null;
    if (raw is! Map) return null;
    return InfoEpisode.fromJson(Map<String, dynamic>.from(raw));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'episode_num': episodeNum,
        'title': title,
        'container_extension': containerExtension,
        'info': info?.toJson(),
        'custom_sid': customSid,
        'added': added,
        'season': season,
        'direct_source': directSource
      };
}

class InfoEpisode {
  final String? movieImage;
  final String? plot;
  final String? releasedate;
  final String? rating;
  final String? name;
  final String? durationSecs;
  final String? duration;

  final String? bitrate;

  InfoEpisode({
    this.movieImage,
    this.plot,
    this.releasedate,
    this.rating,
    this.name,
    this.durationSecs,
    this.duration,
    this.bitrate,
  });

  InfoEpisode.fromJson(Map<String, dynamic> json)
      : movieImage = json['movie_image']?.toString(),
        plot = json['plot']?.toString() ?? '',
        releasedate = json['releasedate']?.toString(),
        rating = json['rating']?.toString(),
        name = json['name']?.toString(),
        durationSecs = json['duration_secs']?.toString(),
        duration = json['duration']?.toString(),
        bitrate = json['bitrate']?.toString();

  Map<String, dynamic> toJson() => {
        'movie_image': movieImage,
        'plot': plot,
        'releasedate': releasedate,
        'rating': rating,
        'name': name,
        'duration_secs': durationSecs,
        'duration': duration,
        'bitrate': bitrate
      };
}
