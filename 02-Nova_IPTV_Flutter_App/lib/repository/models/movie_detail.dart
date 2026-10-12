class MovieDetail {
  final Info? info;
  final MovieData? movieData;

  MovieDetail({this.info, this.movieData});

  MovieDetail.fromJson(Map<String, dynamic> json)
      : info = _tryParseInfo(json['info']),
        movieData = _tryParseMovieData(json['movie_data']);

  static Info? _tryParseInfo(dynamic raw) {
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
      return Info.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      // Keep movie playable even if optional info/video block is malformed.
      try {
        final map = Map<String, dynamic>.from(raw);
        map.remove('video');
        map.remove('audio');
        map.remove('bitrate');
        return Info.fromJson(map);
      } catch (_) {
        return Info();
      }
    }
  }

  static MovieData? _tryParseMovieData(dynamic raw) {
    if (raw is! Map) return null;
    try {
      return MovieData.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'info': info?.toJson(),
        'movie_data': movieData?.toJson(),
      };
}

class Info {
  final String? movieImage;
  final String? tmdbId;
  final String? backdrop;
  final String? youtubeTrailer;
  final String? genre;
  final String? plot;
  final String? cast;
  final String? rating;
  final String? director;
  final String? releasedate;
  final List<String>? backdropPath;
  final String? durationSecs;
  final String? duration;
  final Video? video;

  final String? bitrate;

  Info({
    this.movieImage,
    this.tmdbId,
    this.backdrop,
    this.youtubeTrailer,
    this.genre,
    this.plot,
    this.cast,
    this.rating,
    this.director,
    this.releasedate,
    this.backdropPath,
    this.durationSecs,
    this.duration,
    this.video,
    this.bitrate,
  });

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

  Info.fromJson(Map<String, dynamic> json)
      : movieImage = _firstStr(json, const [
          'movie_image',
          'cover_big',
          'cover',
          'stream_icon',
          'poster',
          'image',
        ]),
        tmdbId = _firstStr(json, const ['tmdb_id', 'tmdb']),
        backdrop = _str(json['backdrop']),
        youtubeTrailer = _firstStr(json, const [
          'youtube_trailer',
          'trailer',
          'youtube',
          'yt_trailer',
        ]),
        genre = _firstStr(json, const ['genre', 'genres', 'category']),
        plot = _firstStr(json, const [
          'plot',
          'description',
          'overview',
          'synopsis',
        ]),
        cast = _firstStr(json, const ['cast', 'actors', 'stars']),
        rating = _firstStr(json, const ['rating', 'rate', 'score']),
        director = _firstStr(json, const ['director', 'directors']),
        releasedate = _firstStr(json, const [
          'releasedate',
          'release_date',
          'releaseDate',
          'released_date',
        ]),
        backdropPath = _mergeBackdropPaths(json),
        durationSecs = _firstStr(json, const ['duration_secs', 'durationSecs']),
        duration = _firstStr(json, const ['duration', 'runtime']),
        video = _tryParseVideo(json['video']),
        bitrate = _str(json['bitrate']);

  static Video? _tryParseVideo(dynamic raw) {
    if (raw == null || raw is List) return null;
    if (raw is! Map) return null;
    try {
      return Video.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  static List<String> _mergeBackdropPaths(Map<String, dynamic> json) {
    final fromPath = _parseBackdropPath(json['backdrop_path']);
    if (fromPath.isNotEmpty) return fromPath;
    final single = _str(json['backdrop']);
    if (single != null) return <String>[single];
    return <String>[];
  }

  static List<String> _parseBackdropPath(dynamic raw) {
    if (raw == null) return <String>[];
    if (raw is String) {
      final t = raw.trim();
      return (t.isEmpty || t == 'null') ? <String>[] : <String>[t];
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
                e['movie_image'],
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
      return u == null ? <String>[] : <String>[u];
    }
    return <String>[];
  }

  Map<String, dynamic> toJson() => {
        'movie_image': movieImage,
        'tmdb_id': tmdbId,
        'backdrop': backdrop,
        'youtube_trailer': youtubeTrailer,
        'genre': genre,
        'plot': plot,
        'cast': cast,
        'rating': rating,
        'director': director,
        'releasedate': releasedate,
        'backdrop_path': backdropPath,
        'duration_secs': durationSecs,
        'duration': duration,
        'video': video?.toJson(),
        'bitrate': bitrate,
      };
}

class Video {
  final String? index;
  final String? codecName;
  final String? codecLongName;
  final String? profile;
  final String? codecType;
  final String? codecTimeBase;
  final String? codecTagString;
  final String? codecTag;
  final String? width;
  final String? height;
  final String? codedWidth;
  final String? codedHeight;
  final String? hasBFrames;
  final String? sampleAspectRatio;
  final String? displayAspectRatio;
  final String? pixFmt;
  final String? level;
  final String? colorRange;
  final String? colorSpace;
  final String? colorTransfer;
  final String? colorPrimaries;
  final String? chromaLocation;
  final String? refs;
  final String? isAvc;
  final String? nalLengthSize;
  final String? rFrameRate;
  final String? avgFrameRate;
  final String? timeBase;
  final String? startPts;
  final String? startTime;
  final String? durationTs;
  final String? duration;
  final String? bitRate;
  final String? bitsPerRawSample;
  final String? nbFrames;

  final Tags? tags;

  Video({
    this.index,
    this.codecName,
    this.codecLongName,
    this.profile,
    this.codecType,
    this.codecTimeBase,
    this.codecTagString,
    this.codecTag,
    this.width,
    this.height,
    this.codedWidth,
    this.codedHeight,
    this.hasBFrames,
    this.sampleAspectRatio,
    this.displayAspectRatio,
    this.pixFmt,
    this.level,
    this.colorRange,
    this.colorSpace,
    this.colorTransfer,
    this.colorPrimaries,
    this.chromaLocation,
    this.refs,
    this.isAvc,
    this.nalLengthSize,
    this.rFrameRate,
    this.avgFrameRate,
    this.timeBase,
    this.startPts,
    this.startTime,
    this.durationTs,
    this.duration,
    this.bitRate,
    this.bitsPerRawSample,
    this.nbFrames,
    this.tags,
  });

  Video.fromJson(Map<String, dynamic> json)
      : index = json['index']?.toString(),
        codecName = json['codec_name']?.toString(),
        codecLongName = json['codec_long_name']?.toString(),
        profile = json['profile']?.toString(),
        codecType = json['codec_type']?.toString(),
        codecTimeBase = json['codec_time_base']?.toString(),
        codecTagString = json['codec_tag_string']?.toString(),
        codecTag = json['codec_tag']?.toString(),
        width = json['width']?.toString(),
        height = json['height']?.toString(),
        codedWidth = json['coded_width']?.toString(),
        codedHeight = json['coded_height']?.toString(),
        hasBFrames = json['has_b_frames']?.toString(),
        sampleAspectRatio = json['sample_aspect_ratio']?.toString(),
        displayAspectRatio = json['display_aspect_ratio']?.toString(),
        pixFmt = json['pix_fmt']?.toString(),
        level = json['level']?.toString(),
        colorRange = json['color_range']?.toString(),
        colorSpace = json['color_space']?.toString(),
        colorTransfer = json['color_transfer']?.toString(),
        colorPrimaries = json['color_primaries']?.toString(),
        chromaLocation = json['chroma_location']?.toString(),
        refs = json['refs']?.toString(),
        isAvc = json['is_avc']?.toString(),
        nalLengthSize = json['nal_length_size']?.toString(),
        rFrameRate = json['r_frame_rate']?.toString(),
        avgFrameRate = json['avg_frame_rate']?.toString(),
        timeBase = json['time_base']?.toString(),
        startPts = json['start_pts']?.toString(),
        startTime = json['start_time']?.toString(),
        durationTs = json['duration_ts']?.toString(),
        duration = json['duration']?.toString(),
        bitRate = json['bit_rate']?.toString(),
        bitsPerRawSample = json['bits_per_raw_sample']?.toString(),
        nbFrames = json['nb_frames']?.toString(),
        tags = _tryParseTags(json['tags']);

  static Tags? _tryParseTags(dynamic raw) {
    if (raw is! Map) return null;
    try {
      return Tags.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'codec_name': codecName,
        'codec_long_name': codecLongName,
        'profile': profile,
        'codec_type': codecType,
        'codec_time_base': codecTimeBase,
        'codec_tag_string': codecTagString,
        'codec_tag': codecTag,
        'width': width,
        'height': height,
        'coded_width': codedWidth,
        'coded_height': codedHeight,
        'has_b_frames': hasBFrames,
        'sample_aspect_ratio': sampleAspectRatio,
        'display_aspect_ratio': displayAspectRatio,
        'pix_fmt': pixFmt,
        'level': level,
        'color_range': colorRange,
        'color_space': colorSpace,
        'color_transfer': colorTransfer,
        'color_primaries': colorPrimaries,
        'chroma_location': chromaLocation,
        'refs': refs,
        'is_avc': isAvc,
        'nal_length_size': nalLengthSize,
        'r_frame_rate': rFrameRate,
        'avg_frame_rate': avgFrameRate,
        'time_base': timeBase,
        'start_pts': startPts,
        'start_time': startTime,
        'duration_ts': durationTs,
        'duration': duration,
        'bit_rate': bitRate,
        'bits_per_raw_sample': bitsPerRawSample,
        'nb_frames': nbFrames,
        'tags': tags?.toJson(),
      };
}

class Tags {
  final String? language;
  final String? handlerName;

  Tags({this.language, this.handlerName});

  Tags.fromJson(Map<String, dynamic> json)
      : language = json['language']?.toString(),
        handlerName = json['handler_name']?.toString();

  Map<String, dynamic> toJson() => {
        'language': language,
        'handler_name': handlerName,
      };
}

class MovieData {
  final String? streamId;
  final String? name;
  final String? added;
  final String? categoryId;
  final String? containerExtension;
  final String? customSid;
  final String? directSource;

  MovieData({
    this.streamId,
    this.name,
    this.added,
    this.categoryId,
    this.containerExtension,
    this.customSid,
    this.directSource,
  });

  MovieData.fromJson(Map<String, dynamic> json)
      : streamId = json['stream_id']?.toString(),
        name = json['name']?.toString(),
        added = json['added']?.toString(),
        categoryId = json['category_id']?.toString(),
        containerExtension = json['container_extension']?.toString(),
        customSid = json['custom_sid']?.toString(),
        directSource = json['direct_source']?.toString();

  Map<String, dynamic> toJson() => {
        'stream_id': streamId,
        'name': name,
        'added': added,
        'category_id': categoryId,
        'container_extension': containerExtension,
        'custom_sid': customSid,
        'direct_source': directSource,
      };
}
