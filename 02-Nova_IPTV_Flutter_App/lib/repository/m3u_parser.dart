import 'models/category.dart';
import 'models/channel_live.dart';
import 'models/channel_movie.dart';
import 'models/channel_serie.dart';

/// Result of parsing a single M3U entry (stream or nested playlist).
class M3UEntry {
  final String name;
  final String groupTitle;
  final String? tvgLogo;
  final String streamUrl;
  final String? tvgId;

  /// `playlist` = folder/nested list; anything else treated as playable stream.
  final String entryType;

  const M3UEntry({
    required this.name,
    required this.groupTitle,
    this.tvgLogo,
    required this.streamUrl,
    this.tvgId,
    this.entryType = 'stream',
  });

  bool get isPlaylist {
    final t = entryType.trim().toLowerCase();
    return t == 'playlist' || t == 'folder' || t == 'list';
  }
}

/// Parses M3U/M3U8 playlist content and returns list of entries.
/// Supports #EXTINF with tvg-id, tvg-name, tvg-logo, group-title, type.
/// Stream URL can be on the same line (after comma) or next line.
/// Skips #EXTBG and other non-URL meta lines.
List<M3UEntry> parseM3UContent(String content, String baseUrl) {
  final list = <M3UEntry>[];
  var raw = content.trim();
  if (raw.startsWith('\uFEFF')) raw = raw.substring(1);
  // Some SS IPTV servers prepend PHP HTML errors — keep from first #EXTM3U/#EXTINF.
  final m3uStart = RegExp(
    r'#EXTM3U|#EXTINF:',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m3uStart != null && m3uStart.start > 0) {
    raw = raw.substring(m3uStart.start);
  }
  final lines = raw.split(RegExp(r'\r?\n'));
  String? currentExtinf;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final upper = line.toUpperCase();
    if (upper.startsWith('#EXTBG:') ||
        upper.startsWith('#EXTVLCOPT:') ||
        upper.startsWith('#EXTGRP:')) {
      continue;
    }
    if (upper.startsWith('#EXTINF:')) {
      final commaIdx = line.indexOf(',');
      final afterComma = commaIdx >= 0 && commaIdx < line.length - 1
          ? line.substring(commaIdx + 1).trim()
          : '';
      if (afterComma.startsWith('http://') || afterComma.startsWith('https://')) {
        final entry = _parseExtinf(line, afterComma, baseUrl);
        if (entry != null) list.add(entry);
      } else {
        currentExtinf = line;
      }
      continue;
    }
    if (currentExtinf != null && !line.startsWith('#')) {
      final url = line.trim();
      if (url.isNotEmpty) {
        final entry = _parseExtinf(currentExtinf, url, baseUrl);
        if (entry != null) list.add(entry);
      }
      currentExtinf = null;
      continue;
    }
    currentExtinf = null;
  }
  return list;
}

bool m3uLooksLikeNestedMaster(List<M3UEntry> entries) {
  if (entries.isEmpty) return false;
  final playlists = entries.where((e) => e.isPlaylist).length;
  if (playlists == 0) return false;
  return playlists >= entries.length / 2 || playlists >= 2;
}

bool isSsIptvStyleUrl(String raw) {
  final u = raw.trim().toLowerCase();
  if (u.isEmpty) return false;
  return u.contains('/ssiptv/') ||
      u.contains('download_mode') ||
      u.contains('list_lives') ||
      u.contains('movie_categories') ||
      u.contains('serie_categories');
}

/// Classify nested playlist role from URL / title.
String classifySsIptvSection(String url, String name) {
  final u = url.toLowerCase();
  final n = name.toLowerCase();
  if (u.contains('list_live') ||
      u.contains('/lives') ||
      n.contains('canai') ||
      n.contains('live') ||
      n.contains('tv') ||
      n.contains('قنوات') ||
      n.contains('مباشر')) {
    return 'live';
  }
  if (u.contains('movie') ||
      u.contains('vod') ||
      u.contains('filme') ||
      n.contains('film') ||
      n.contains('movie') ||
      n.contains('vod') ||
      n.contains('أفلام') ||
      n.contains('افلام')) {
    return 'movie';
  }
  if (u.contains('serie') ||
      u.contains('series') ||
      n.contains('serie') ||
      n.contains('مسلسل')) {
    return 'series';
  }
  return 'unknown';
}

/// Parse #EXTINF:-1 tvg-id="x" tvg-name="y" tvg-logo="z" group-title="Cat" type="playlist",Name
M3UEntry? _parseExtinf(String extinf, String streamUrl, String baseUrl) {
  String name = '';
  String groupTitle = '';
  String? tvgLogo;
  String? tvgId;
  String entryType = 'stream';

  final commaIdx = extinf.indexOf(',');
  if (commaIdx != -1 && commaIdx < extinf.length - 1) {
    final afterComma = extinf.substring(commaIdx + 1).trim();
    if (!afterComma.startsWith('http://') && !afterComma.startsWith('https://')) {
      name = afterComma;
    }
  }

  final attrRegex = RegExp(
    '(tvg-id|tvg-name|tvg-logo|group-title|type)=["\']([^"\']*)["\']',
    caseSensitive: false,
  );
  for (final m in attrRegex.allMatches(extinf)) {
    final key = m.group(1)!.toLowerCase();
    final value = m.group(2) ?? '';
    switch (key) {
      case 'tvg-id':
        tvgId = value;
        break;
      case 'tvg-name':
        if (name.isEmpty) name = value;
        break;
      case 'tvg-logo':
        tvgLogo = value.isNotEmpty ? _resolveUrl(value, baseUrl) : null;
        break;
      case 'group-title':
        groupTitle = value;
        break;
      case 'type':
        entryType = value.trim().isEmpty ? 'stream' : value.trim();
        break;
    }
  }

  // Unquoted type=playlist
  if (entryType == 'stream') {
    final typeLoose = RegExp(
      r'type\s*=\s*([^\s,"'']+)',
      caseSensitive: false,
    ).firstMatch(extinf);
    if (typeLoose != null) {
      entryType = typeLoose.group(1)!.trim();
    }
  }

  if (name.isEmpty) name = 'Channel';
  if (groupTitle.isEmpty) groupTitle = 'General';

  final resolvedStreamUrl = _resolveUrl(streamUrl, baseUrl);
  if (resolvedStreamUrl.isEmpty) return null;

  // URL path hints: trailing slash or known folder paths → playlist
  final lowerUrl = resolvedStreamUrl.toLowerCase();
  if (!RegExp(r'type\s*=', caseSensitive: false).hasMatch(extinf) &&
      (lowerUrl.endsWith('/') ||
          lowerUrl.contains('list_lives') ||
          lowerUrl.contains('movie_categories') ||
          lowerUrl.contains('serie_categories') ||
          lowerUrl.contains('download_mode'))) {
    entryType = 'playlist';
  }

  return M3UEntry(
    name: name,
    groupTitle: groupTitle,
    tvgLogo: tvgLogo,
    streamUrl: resolvedStreamUrl,
    tvgId: tvgId,
    entryType: entryType,
  );
}

String _resolveUrl(String url, String baseUrl) {
  final u = url.trim();
  if (u.isEmpty) return '';
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  try {
    final base = Uri.parse(baseUrl);
    final resolved = base.resolve(u);
    return resolved.toString();
  } catch (_) {
    return u;
  }
}

/// Convert M3U stream entries to CategoryModel list (unique group-title).
List<CategoryModel> m3uEntriesToCategories(List<M3UEntry> entries) {
  final seen = <String>{};
  final list = <CategoryModel>[];
  for (final e in entries) {
    if (e.isPlaylist) continue;
    final id = e.groupTitle.trim();
    if (id.isEmpty) continue;
    if (seen.add(id)) {
      list.add(CategoryModel(
        categoryId: id,
        categoryName: id,
      ));
    }
  }
  list.sort((a, b) => (a.categoryName ?? '').compareTo(b.categoryName ?? ''));
  return list;
}

/// Convert M3U stream entries to ChannelLive list (streamId = full stream URL).
List<ChannelLive> m3uEntriesToChannels(
  List<M3UEntry> entries, {
  String? categoryId,
  int startNum = 1,
}) {
  var filtered = entries.where((e) => !e.isPlaylist).toList();
  if (categoryId != null && categoryId.isNotEmpty) {
    filtered = filtered.where((e) => e.groupTitle == categoryId).toList();
  }
  var num = startNum;
  return filtered.map((e) {
    final ch = ChannelLive(
      num: '${num++}',
      name: e.name,
      streamId: e.streamUrl,
      streamIcon: e.tvgLogo,
      categoryId: e.groupTitle,
      directSource: '1',
    );
    return ch;
  }).toList();
}

List<ChannelMovie> m3uEntriesToMovies(
  List<M3UEntry> entries, {
  String? categoryId,
  int startNum = 1,
}) {
  final filtered = entries.where((e) => !e.isPlaylist).toList();
  var num = startNum;
  final cat = (categoryId != null && categoryId.isNotEmpty)
      ? categoryId
      : null;
  return filtered.map((e) {
    return ChannelMovie(
      num: '${num++}',
      name: e.name,
      streamType: 'movie',
      streamId: e.streamUrl,
      streamIcon: e.tvgLogo,
      categoryId: cat ?? e.groupTitle,
      containerExtension: 'mp4',
      directSource: '1',
    );
  }).toList();
}

/// Nested series folders → ChannelSerie (seriesId = child playlist URL).
List<ChannelSerie> m3uPlaylistEntriesToSeries(
  List<M3UEntry> entries, {
  String? categoryId,
  int startNum = 1,
}) {
  var filtered = entries.where((e) => e.isPlaylist).toList();
  if (filtered.isEmpty) {
    // Flat episode list under a category: one synthetic "series" per group or all as one.
    final streams = entries.where((e) => !e.isPlaylist).toList();
    if (streams.isEmpty) return [];
    final byGroup = <String, List<M3UEntry>>{};
    for (final e in streams) {
      final g = e.groupTitle.trim().isEmpty ? e.name : e.groupTitle.trim();
      byGroup.putIfAbsent(g, () => []).add(e);
    }
    var num = startNum;
    return byGroup.entries.map((en) {
      final first = en.value.first;
      return ChannelSerie(
        num: '${num++}',
        name: en.key,
        seriesId: 'm3u-flat:${Uri.encodeComponent(en.key)}:${categoryId ?? first.streamUrl}',
        cover: first.tvgLogo,
        categoryId: categoryId,
      );
    }).toList();
  }
  var num = startNum;
  return filtered.map((e) {
    return ChannelSerie(
      num: '${num++}',
      name: e.name,
      seriesId: e.streamUrl,
      cover: e.tvgLogo,
      categoryId: categoryId,
    );
  }).toList();
}
