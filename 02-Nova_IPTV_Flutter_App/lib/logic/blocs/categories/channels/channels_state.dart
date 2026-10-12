part of 'channels_bloc.dart';

@immutable
abstract class ChannelsState {}

class ChannelsLoading extends ChannelsState {}

class ChannelsLiveSuccess extends ChannelsState {
  final List<ChannelLive> channels;
  /// معرّف الفئة التي تُعرض قنواتها حالياً (لمزامنة قائمة الفئات).
  final String categoryId;
  ChannelsLiveSuccess(this.channels, {this.categoryId = ''});
}

class ChannelsMovieSuccess extends ChannelsState {
  final List<ChannelMovie> channels;
  /// `__all__` / category id — لتمييز نتيجة التحميل في الواجهة.
  final String categoryId;
  ChannelsMovieSuccess(this.channels, {this.categoryId = ''});
}

class ChannelsSeriesSuccess extends ChannelsState {
  final List<ChannelSerie> channels;
  final String categoryId;
  ChannelsSeriesSuccess(this.channels, {this.categoryId = ''});
}
