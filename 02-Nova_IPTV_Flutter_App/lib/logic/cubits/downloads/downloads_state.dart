part of 'downloads_cubit.dart';

class DownloadsState {
  final List<DownloadedMovie> items;
  final Map<String, double> progressByStreamId;
  final Set<String> activeStreamIds;
  final bool loading;
  final double availableGb;
  final double totalGb;
  final bool storageKnown;

  const DownloadsState({
    required this.items,
    required this.progressByStreamId,
    required this.activeStreamIds,
    required this.loading,
    required this.availableGb,
    required this.totalGb,
    required this.storageKnown,
  });

  factory DownloadsState.initial() => const DownloadsState(
        items: [],
        progressByStreamId: {},
        activeStreamIds: {},
        loading: true,
        availableGb: 0,
        totalGb: 0,
        storageKnown: false,
      );

  DownloadsState copyWith({
    List<DownloadedMovie>? items,
    Map<String, double>? progressByStreamId,
    Set<String>? activeStreamIds,
    bool? loading,
    double? availableGb,
    double? totalGb,
    bool? storageKnown,
  }) {
    return DownloadsState(
      items: items ?? this.items,
      progressByStreamId: progressByStreamId ?? this.progressByStreamId,
      activeStreamIds: activeStreamIds ?? this.activeStreamIds,
      loading: loading ?? this.loading,
      availableGb: availableGb ?? this.availableGb,
      totalGb: totalGb ?? this.totalGb,
      storageKnown: storageKnown ?? this.storageKnown,
    );
  }

  bool isDownloaded(String streamId) =>
      items.any((e) => e.streamId == streamId);

  bool isDownloading(String streamId) => activeStreamIds.contains(streamId);

  double progressOf(String streamId) => progressByStreamId[streamId] ?? 0;
}
