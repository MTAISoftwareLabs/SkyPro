class DownloadedMovie {
  final String streamId;
  final String name;
  final String streamIcon;
  final String videoUrl;
  final String containerExtension;
  final String tempName;
  final String localVideoPath;
  final String localPosterPath;
  final int fileSizeBytes;
  final int createdAtMs;

  const DownloadedMovie({
    required this.streamId,
    required this.name,
    required this.streamIcon,
    required this.videoUrl,
    required this.containerExtension,
    required this.tempName,
    required this.localVideoPath,
    required this.localPosterPath,
    this.fileSizeBytes = 0,
    this.createdAtMs = 0,
  });

  DownloadedMovie copyWith({
    String? streamId,
    String? name,
    String? streamIcon,
    String? videoUrl,
    String? containerExtension,
    String? tempName,
    String? localVideoPath,
    String? localPosterPath,
    int? fileSizeBytes,
    int? createdAtMs,
  }) {
    return DownloadedMovie(
      streamId: streamId ?? this.streamId,
      name: name ?? this.name,
      streamIcon: streamIcon ?? this.streamIcon,
      videoUrl: videoUrl ?? this.videoUrl,
      containerExtension: containerExtension ?? this.containerExtension,
      tempName: tempName ?? this.tempName,
      localVideoPath: localVideoPath ?? this.localVideoPath,
      localPosterPath: localPosterPath ?? this.localPosterPath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'streamId': streamId,
        'name': name,
        'streamIcon': streamIcon,
        'videoUrl': videoUrl,
        'containerExtension': containerExtension,
        'tempName': tempName,
        'localVideoPath': localVideoPath,
        'localPosterPath': localPosterPath,
        'fileSizeBytes': fileSizeBytes,
        'createdAtMs': createdAtMs,
      };

  factory DownloadedMovie.fromJson(Map<String, dynamic> json) {
    return DownloadedMovie(
      streamId: json['streamId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      streamIcon: json['streamIcon']?.toString() ?? '',
      videoUrl: json['videoUrl']?.toString() ?? '',
      containerExtension: json['containerExtension']?.toString() ?? 'mp4',
      tempName: json['tempName']?.toString() ?? '',
      localVideoPath: json['localVideoPath']?.toString() ?? '',
      localPosterPath: json['localPosterPath']?.toString() ?? '',
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
