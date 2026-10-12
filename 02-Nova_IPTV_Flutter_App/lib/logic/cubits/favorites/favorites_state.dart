part of 'favorites_cubit.dart';

class FavoritesState {
  final List<ChannelMovie> movies;
  final List<ChannelLive> lives;
  final List<ChannelSerie> series;

  const FavoritesState({
    required this.movies,
    required this.lives,
    required this.series,
  });

  factory FavoritesState.defaultData() =>
      const FavoritesState(movies: [], lives: [], series: []);
}
