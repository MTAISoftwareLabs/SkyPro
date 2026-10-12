import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../repository/api/api.dart';
import '../../../repository/models/movie_detail.dart';
import '../../../repository/models/serie_details.dart';

/// كاش خفيف لتفاصيل فيلم/مسلسل عند فتح الصفحة (لا يوجد تحميل مسبق للأقسام من الرئيسية).
class PrefetchCubit extends Cubit<int> {
  PrefetchCubit() : super(0);

  static final Map<String, MovieDetail> _movieDetailsCache = {};
  static final Map<String, Future<MovieDetail?>> _movieDetailsInFlight = {};
  static final Map<String, SerieDetails> _serieDetailsCache = {};
  static final Map<String, Future<SerieDetails?>> _serieDetailsInFlight = {};

  Future<MovieDetail?> getMovieDetailCached(
    String movieId, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh) {
      _movieDetailsCache.remove(movieId);
      _movieDetailsInFlight.remove(movieId);
    }

    final existing = _movieDetailsCache[movieId];
    if (existing != null) return Future.value(existing);

    final inFlight = _movieDetailsInFlight[movieId];
    if (inFlight != null) return inFlight;

    final fut = IpTvApi.getMovieDetails(movieId).then((detail) {
      if (detail != null && detail.movieData != null) {
        _movieDetailsCache[movieId] = detail;
      }
      return detail;
    }).whenComplete(() {
      _movieDetailsInFlight.remove(movieId);
    });
    _movieDetailsInFlight[movieId] = fut;
    return fut;
  }

  /// Instant memory lookup — no network.
  MovieDetail? peekMovieDetail(String movieId) => _movieDetailsCache[movieId];

  /// Instant memory lookup — no network.
  SerieDetails? peekSerieDetail(String seriesId) => _serieDetailsCache[seriesId];

  Future<SerieDetails?> getSerieDetailCached(
    String seriesId, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh) {
      _serieDetailsCache.remove(seriesId);
      _serieDetailsInFlight.remove(seriesId);
    }

    final existing = _serieDetailsCache[seriesId];
    if (existing != null) return Future.value(existing);

    final inFlight = _serieDetailsInFlight[seriesId];
    if (inFlight != null) return inFlight;

    final fut = IpTvApi.getSerieDetails(seriesId).then((detail) {
      if (detail != null && detail.info != null) {
        _serieDetailsCache[seriesId] = detail;
      }
      return detail;
    }).whenComplete(() {
      _serieDetailsInFlight.remove(seriesId);
    });
    _serieDetailsInFlight[seriesId] = fut;
    return fut;
  }

  static void clearAllCaches() {
    _movieDetailsCache.clear();
    _movieDetailsInFlight.clear();
    _serieDetailsCache.clear();
    _serieDetailsInFlight.clear();
  }
}
