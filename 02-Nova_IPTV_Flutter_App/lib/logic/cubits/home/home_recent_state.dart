part of 'home_recent_cubit.dart';

@immutable
sealed class HomeRecentState {
  const HomeRecentState();
}

class HomeRecentInitial extends HomeRecentState {
  const HomeRecentInitial();
}

/// لا يوجد كاش محلي — يُعرض مؤشر التحميل المركزي + shimmer.
class HomeRecentLoading extends HomeRecentState {
  const HomeRecentLoading();
}

class HomeRecentSuccess extends HomeRecentState {
  const HomeRecentSuccess({
    required this.movies,
    required this.series,
    this.recentMovies = const [],
    this.recentSeries = const [],
    this.fromCache = false,
    this.isRefreshing = false,
    this.isComplete = false,
  });

  /// Recommended / suggested (shuffled) — هاتف + تلفزيون.
  final List<ChannelMovie> movies;
  final List<ChannelSerie> series;

  /// Recently added (sorted by date) — صفوف إضافية على التلفزيون.
  final List<ChannelMovie> recentMovies;
  final List<ChannelSerie> recentSeries;

  final bool fromCache;
  final bool isRefreshing;
  final bool isComplete;

  HomeRecentSuccess copyWith({
    List<ChannelMovie>? movies,
    List<ChannelSerie>? series,
    List<ChannelMovie>? recentMovies,
    List<ChannelSerie>? recentSeries,
    bool? fromCache,
    bool? isRefreshing,
    bool? isComplete,
  }) {
    return HomeRecentSuccess(
      movies: movies ?? this.movies,
      series: series ?? this.series,
      recentMovies: recentMovies ?? this.recentMovies,
      recentSeries: recentSeries ?? this.recentSeries,
      fromCache: fromCache ?? this.fromCache,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}
