import 'm3u_parser.dart';
import 'models/category.dart';
import 'models/channel_live.dart';
import 'models/channel_movie.dart';
import 'models/channel_serie.dart';
import 'models/serie_details.dart';

/// In-memory SS IPTV / nested M3U catalog (live + movies + series).
class SsIptvCatalog {
  final List<CategoryModel> liveCategories;
  final List<ChannelLive> liveChannels;
  final List<CategoryModel> movieCategories;
  final Map<String, List<ChannelMovie>> moviesByCategory;
  final List<CategoryModel> seriesCategories;
  final Map<String, List<ChannelSerie>> seriesByCategory;
  /// seriesId → leaf stream entries (episodes) when seriesId is a playlist URL
  final Map<String, List<M3UEntry>> seriesEpisodeEntries;

  const SsIptvCatalog({
    required this.liveCategories,
    required this.liveChannels,
    required this.movieCategories,
    required this.moviesByCategory,
    required this.seriesCategories,
    required this.seriesByCategory,
    required this.seriesEpisodeEntries,
  });

  bool get isEmpty =>
      liveChannels.isEmpty &&
      moviesByCategory.values.every((e) => e.isEmpty) &&
      seriesByCategory.values.every((e) => e.isEmpty);
}

typedef M3uFetchFn = Future<List<M3UEntry>> Function(String url);

/// Build nested catalog from master playlist (SS IPTV style).
Future<SsIptvCatalog> buildSsIptvCatalog(
  String masterUrl,
  List<M3UEntry> masterEntries,
  M3uFetchFn fetch, {
  int maxDepth = 4,
}) async {
  final liveCats = <CategoryModel>[];
  final liveChannels = <ChannelLive>[];
  final movieCats = <CategoryModel>[];
  final moviesByCat = <String, List<ChannelMovie>>{};
  final seriesCats = <CategoryModel>[];
  final seriesByCat = <String, List<ChannelSerie>>{};
  final seriesEps = <String, List<M3UEntry>>{};

  final roots = masterEntries.where((e) => e.isPlaylist).toList();
  if (roots.isEmpty) {
    // Flat fallback treated as live
    final cats = m3uEntriesToCategories(masterEntries);
    liveCats.addAll(cats);
    liveChannels.addAll(m3uEntriesToChannels(masterEntries));
    return SsIptvCatalog(
      liveCategories: liveCats,
      liveChannels: liveChannels,
      movieCategories: movieCats,
      moviesByCategory: moviesByCat,
      seriesCategories: seriesCats,
      seriesByCategory: seriesByCat,
      seriesEpisodeEntries: seriesEps,
    );
  }

  for (final root in roots) {
    final section = classifySsIptvSection(root.streamUrl, root.name);
    final children = await fetch(root.streamUrl);
    if (children.isEmpty) continue;

    if (section == 'live' || section == 'unknown') {
      await _ingestLive(
        children,
        fetch,
        liveCats,
        liveChannels,
        depth: 1,
        maxDepth: maxDepth,
      );
      if (section == 'unknown' &&
          children.every((e) => !e.isPlaylist) &&
          liveChannels.isEmpty) {
        liveChannels.addAll(m3uEntriesToChannels(children));
        liveCats.addAll(m3uEntriesToCategories(children));
      }
    }
    if (section == 'movie') {
      await _ingestMovies(
        children,
        fetch,
        movieCats,
        moviesByCat,
        depth: 1,
        maxDepth: maxDepth,
      );
    }
    if (section == 'series') {
      await _ingestSeries(
        children,
        fetch,
        seriesCats,
        seriesByCat,
        seriesEps,
        depth: 1,
        maxDepth: maxDepth,
      );
    }
  }

  // Deduplicate live categories
  final seenLive = <String>{};
  final uniqueLiveCats = <CategoryModel>[];
  for (final c in liveCats) {
    final id = c.categoryId ?? '';
    if (id.isEmpty || !seenLive.add(id)) continue;
    uniqueLiveCats.add(c);
  }

  return SsIptvCatalog(
    liveCategories: uniqueLiveCats.isNotEmpty
        ? uniqueLiveCats
        : m3uEntriesToCategories(
            liveChannels
                .map(
                  (c) => M3UEntry(
                    name: c.name ?? '',
                    groupTitle: c.categoryId ?? 'General',
                    streamUrl: c.streamId ?? '',
                    tvgLogo: c.streamIcon,
                  ),
                )
                .toList(),
          ),
    liveChannels: liveChannels,
    movieCategories: movieCats,
    moviesByCategory: moviesByCat,
    seriesCategories: seriesCats,
    seriesByCategory: seriesByCat,
    seriesEpisodeEntries: seriesEps,
  );
}

Future<void> _ingestLive(
  List<M3UEntry> entries,
  M3uFetchFn fetch,
  List<CategoryModel> cats,
  List<ChannelLive> channels, {
  required int depth,
  required int maxDepth,
}) async {
  final playlists = entries.where((e) => e.isPlaylist).toList();
  final streams = entries.where((e) => !e.isPlaylist).toList();

  if (streams.isNotEmpty) {
    channels.addAll(m3uEntriesToChannels(streams));
    cats.addAll(m3uEntriesToCategories(streams));
  }

  if (playlists.isEmpty || depth >= maxDepth) return;

  for (final p in playlists) {
    final catId = p.streamUrl;
    if (!cats.any((c) => c.categoryId == catId)) {
      cats.add(CategoryModel(categoryId: catId, categoryName: p.name));
    }
    final child = await fetch(p.streamUrl);
    final childStreams = child.where((e) => !e.isPlaylist).toList();
    if (childStreams.isNotEmpty) {
      var num = channels.length + 1;
      for (final e in childStreams) {
        channels.add(
          ChannelLive(
            num: '${num++}',
            name: e.name,
            streamId: e.streamUrl,
            streamIcon: e.tvgLogo ?? p.tvgLogo,
            categoryId: catId,
            directSource: '1',
          ),
        );
      }
    } else if (child.any((e) => e.isPlaylist)) {
      await _ingestLive(
        child,
        fetch,
        cats,
        channels,
        depth: depth + 1,
        maxDepth: maxDepth,
      );
    }
  }
}

Future<void> _ingestMovies(
  List<M3UEntry> entries,
  M3uFetchFn fetch,
  List<CategoryModel> cats,
  Map<String, List<ChannelMovie>> byCat, {
  required int depth,
  required int maxDepth,
}) async {
  final playlists = entries.where((e) => e.isPlaylist).toList();
  final streams = entries.where((e) => !e.isPlaylist).toList();

  if (streams.isNotEmpty && playlists.isEmpty) {
    const id = 'all_movies';
    if (!cats.any((c) => c.categoryId == id)) {
      cats.add(CategoryModel(categoryId: id, categoryName: 'Movies'));
    }
    byCat[id] = [
      ...?byCat[id],
      ...m3uEntriesToMovies(streams, categoryId: id),
    ];
    return;
  }

  for (final p in playlists) {
    final catId = p.streamUrl;
    if (!cats.any((c) => c.categoryId == catId)) {
      cats.add(CategoryModel(categoryId: catId, categoryName: p.name));
    }
    if (depth >= maxDepth) continue;
    final child = await fetch(p.streamUrl);
    final childStreams = child.where((e) => !e.isPlaylist).toList();
    final childPlaylists = child.where((e) => e.isPlaylist).toList();
    if (childStreams.isNotEmpty) {
      byCat[catId] = m3uEntriesToMovies(childStreams, categoryId: catId);
    }
    if (childPlaylists.isNotEmpty && depth + 1 < maxDepth) {
      // Nested folder under category: flatten movies from each child
      final all = <ChannelMovie>[...?byCat[catId]];
      for (final cp in childPlaylists) {
        final deep = await fetch(cp.streamUrl);
        all.addAll(
          m3uEntriesToMovies(
            deep.where((e) => !e.isPlaylist).toList(),
            categoryId: catId,
          ),
        );
      }
      byCat[catId] = all;
    }
  }
}

Future<void> _ingestSeries(
  List<M3UEntry> entries,
  M3uFetchFn fetch,
  List<CategoryModel> cats,
  Map<String, List<ChannelSerie>> byCat,
  Map<String, List<M3UEntry>> episodeMap, {
  required int depth,
  required int maxDepth,
}) async {
  final playlists = entries.where((e) => e.isPlaylist).toList();
  final streams = entries.where((e) => !e.isPlaylist).toList();

  if (streams.isNotEmpty && playlists.isEmpty) {
    const id = 'all_series';
    if (!cats.any((c) => c.categoryId == id)) {
      cats.add(CategoryModel(categoryId: id, categoryName: 'Series'));
    }
    final list = m3uPlaylistEntriesToSeries(streams, categoryId: id);
    // Flat episodes → one series bucket keyed by group
    byCat[id] = list;
    for (final s in list) {
      final sid = s.seriesId ?? '';
      if (sid.startsWith('m3u-flat:')) {
        final group = s.name ?? '';
        episodeMap[sid] =
            streams.where((e) => e.groupTitle == group || e.name == group).toList();
        if (episodeMap[sid]!.isEmpty) episodeMap[sid] = streams;
      }
    }
    return;
  }

  for (final p in playlists) {
    final catId = p.streamUrl;
    if (!cats.any((c) => c.categoryId == catId)) {
      cats.add(CategoryModel(categoryId: catId, categoryName: p.name));
    }
    if (depth >= maxDepth) continue;
    final child = await fetch(p.streamUrl);
    final childPlaylists = child.where((e) => e.isPlaylist).toList();
    final childStreams = child.where((e) => !e.isPlaylist).toList();

    if (childPlaylists.isNotEmpty) {
      final seriesList = <ChannelSerie>[];
      var num = 1;
      for (final sp in childPlaylists) {
        final sid = sp.streamUrl;
        seriesList.add(
          ChannelSerie(
            num: '${num++}',
            name: sp.name,
            seriesId: sid,
            cover: sp.tvgLogo ?? p.tvgLogo,
            categoryId: catId,
          ),
        );
        // Prefetch episode leaves (one level)
        if (depth + 1 < maxDepth) {
          final eps = await fetch(sid);
          final leaves = eps.where((e) => !e.isPlaylist).toList();
          if (leaves.isNotEmpty) {
            episodeMap[sid] = leaves;
          } else {
            // Another nesting level: flatten
            final flat = <M3UEntry>[];
            for (final nested in eps.where((e) => e.isPlaylist)) {
              final deep = await fetch(nested.streamUrl);
              flat.addAll(deep.where((e) => !e.isPlaylist));
            }
            if (flat.isNotEmpty) episodeMap[sid] = flat;
          }
        }
      }
      byCat[catId] = seriesList;
    } else if (childStreams.isNotEmpty) {
      final list = m3uPlaylistEntriesToSeries(childStreams, categoryId: catId);
      byCat[catId] = list;
      for (final s in list) {
        final sid = s.seriesId ?? '';
        if (sid.startsWith('m3u-flat:')) {
          episodeMap[sid] = childStreams;
        }
      }
    }
  }
}

SerieDetails serieDetailsFromM3uEntries(
  String seriesId,
  String title,
  String? cover,
  List<M3UEntry> entries,
) {
  final eps = <Episode?>[];
  var n = 1;
  for (final e in entries.where((x) => !x.isPlaylist)) {
    eps.add(
      Episode(
        id: e.streamUrl,
        episodeNum: '$n',
        title: e.name,
        containerExtension: 'mp4',
        season: '1',
        directSource: '1',
        info: InfoEpisode(movieImage: e.tvgLogo, name: e.name),
      ),
    );
    n++;
  }
  return SerieDetails(
    seasons: [
      Season(
        id: '1',
        name: 'Season 1',
        seasonNumber: '1',
        episodeCount: '${eps.length}',
        cover: cover,
        coverBig: cover,
      ),
    ],
    info: InfoSerie(name: title, cover: cover),
    episodes: {'1': eps},
  );
}
