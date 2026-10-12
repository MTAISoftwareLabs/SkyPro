part of 'watching_cubit.dart';

class WatchingState {
  final List<WatchingModel> movies;
  final List<WatchingModel> series;
  final List<WatchingModel> live;

  const WatchingState({
    required this.movies,
    required this.series,
    required this.live,
  });

  factory WatchingState.defaultData() =>
      const WatchingState(movies: [], series: [], live: []);
}
