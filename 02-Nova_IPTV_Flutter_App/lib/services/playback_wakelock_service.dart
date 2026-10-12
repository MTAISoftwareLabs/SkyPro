import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on during Live / Movie / Series playback.
/// Uses [WakelockPlus] only — no Android Foreground Service.
class PlaybackWakelockService {
  PlaybackWakelockService._();
  static final PlaybackWakelockService instance = PlaybackWakelockService._();

  Future<void> acquire({
    required String title,
    required bool isLive,
  }) async {
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('[WakelockService] WakelockPlus.enable failed: $e');
    }
  }

  Future<void> release() async {
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('[WakelockService] WakelockPlus.disable failed: $e');
    }
  }

  /// Kept for call-site compatibility (channel title updates).
  Future<void> updateTitle(String newTitle) async {}
}
