import '../../repository/models/channel_movie.dart';
import '../../repository/models/channel_serie.dart';
import '../../repository/models/serie_details.dart';
import 'subtitle_models.dart';

/// Builds playback metadata for subtitle search without widget logic.
class SubtitlePlaybackContextBuilder {
  SubtitlePlaybackContextBuilder._();

  static SubtitleContentContext fromMovie({
    required ChannelMovie channelMovie,
    required String title,
    String? tmdbId,
    int? year,
    String? playbackUrl,
  }) {
    final streamId = channelMovie.streamId?.toString() ?? title;
    return SubtitleContentContext(
      contentKey: 'movie:$streamId',
      isSeries: false,
      title: channelMovie.name?.trim().isNotEmpty == true
          ? channelMovie.name!.trim()
          : title,
      tmdbId: tmdbId,
      year: year,
      fileName: _fileNameFromUrl(playbackUrl),
    );
  }

  static SubtitleContentContext fromSeries({
    required ChannelSerie channelSerie,
    required String title,
    List<Episode?>? episodes,
    String? currentEpisodeId,
    String? tmdbId,
    int? year,
    String? playbackUrl,
  }) {
    int? season;
    int? episode;
    if (episodes != null && currentEpisodeId != null) {
      for (final ep in episodes) {
        if (ep == null) continue;
        if (ep.id?.toString() == currentEpisodeId) {
          season = int.tryParse(ep.season ?? '');
          episode = int.tryParse(ep.episodeNum ?? '');
          break;
        }
      }
    }

    final seriesId = channelSerie.seriesId?.toString() ?? title;
    return SubtitleContentContext(
      contentKey: 'series:$seriesId',
      isSeries: true,
      title: channelSerie.name?.trim().isNotEmpty == true
          ? channelSerie.name!.trim()
          : title,
      tmdbId: tmdbId,
      year: year,
      season: season,
      episode: episode,
      fileName: _fileNameFromUrl(playbackUrl),
    );
  }

  static String? _fileNameFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    return segments.last;
  }
}
