import 'dart:async';

import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';

/// حدث تقدّم تنزيل/تثبيت من Google Play (أندرويد).
class AppUpdateProgressEvent {
  const AppUpdateProgressEvent({
    required this.status,
    required this.bytesDownloaded,
    required this.totalBytesToDownload,
  });

  final InstallStatus status;
  final int bytesDownloaded;
  final int totalBytesToDownload;

  double? get fraction {
    if (totalBytesToDownload <= 0) return null;
    return (bytesDownloaded / totalBytesToDownload).clamp(0.0, 1.0);
  }

  int get percent {
    final f = fraction;
    if (f == null) return 0;
    return (f * 100).round().clamp(0, 100);
  }
}

/// قناة أصلية تبث بايتات التنزيل (غير متوفرة في in_app_update الافتراضي).
abstract final class AppUpdateProgressChannel {
  static const EventChannel _channel = EventChannel(
    'nova.iptv/app_update_progress',
  );

  static Stream<AppUpdateProgressEvent>? _stream;

  static Stream<AppUpdateProgressEvent> get events {
    return _stream ??= _channel.receiveBroadcastStream().map((raw) {
      final map = Map<Object?, Object?>.from(raw as Map);
      final statusCode = (map['status'] as num?)?.toInt() ?? 0;
      return AppUpdateProgressEvent(
        status: InstallStatus.values.firstWhere(
          (e) => e.value == statusCode,
          orElse: () => InstallStatus.unknown,
        ),
        bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt() ?? 0,
        totalBytesToDownload:
            (map['totalBytesToDownload'] as num?)?.toInt() ?? 0,
      );
    }).cast<AppUpdateProgressEvent>();
  }
}
