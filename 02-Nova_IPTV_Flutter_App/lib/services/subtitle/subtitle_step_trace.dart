import 'dart:developer' as developer;

import '../../core/opensubtitles_config.dart';

/// Step-by-step execution trace for subtitle search debugging.
void subtitleStep(String step, [String? detail]) {
  if (!kOpensubtitlesVerboseLogs) return;
  final message =
      detail != null && detail.isNotEmpty ? '$step — $detail' : step;
  developer.log(message, name: 'OpenSubtitles.Step');
}

void subtitleStepError(String step, Object error, StackTrace stackTrace) {
  subtitleStep(step, 'STOPPED — Exception: $error');
  if (!kOpensubtitlesVerboseLogs) return;
  developer.log(
    '$step — $error\n$stackTrace',
    name: 'OpenSubtitles.Step',
    error: error,
    stackTrace: stackTrace,
  );
}
