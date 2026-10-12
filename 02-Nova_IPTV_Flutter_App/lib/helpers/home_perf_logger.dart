import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Profiling helper for home-screen startup (debug / profile builds).
class HomePerfLogger {
  HomePerfLogger._();

  static const bool enabled = !kReleaseMode;

  static final DateTime _origin = DateTime.now();
  static final Map<String, DateTime> _starts = {};
  static int _buildCount = 0;

  static int? get _rssKb {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return null;
    }
  }

  static String _memSuffix() {
    final rss = _rssKb;
    if (rss == null) return '';
    final mb = (rss / (1024 * 1024)).toStringAsFixed(1);
    return ' | RSS ${mb}MB';
  }

  static String _elapsed() {
    final ms = DateTime.now().difference(_origin).inMilliseconds;
    return '+${ms}ms';
  }

  static void mark(String label) {
    if (!enabled) return;
    debugPrint('[HOME_PERF] ${_elapsed()} MARK $label${_memSuffix()}');
  }

  static void start(String label) {
    if (!enabled) return;
    _starts[label] = DateTime.now();
    debugPrint('[HOME_PERF] ${_elapsed()} START $label${_memSuffix()}');
  }

  static void end(String label, {String? extra}) {
    if (!enabled) return;
    final started = _starts.remove(label);
    final dur =
        started == null
            ? '?'
            : '${DateTime.now().difference(started).inMilliseconds}ms';
    final tail = extra == null ? '' : ' | $extra';
    debugPrint(
      '[HOME_PERF] ${_elapsed()} END $label ($dur)$tail${_memSuffix()}',
    );
  }

  static T timeSync<T>(String label, T Function() fn) {
    if (!enabled) return fn();
    start(label);
    try {
      return fn();
    } finally {
      end(label);
    }
  }

  static Future<T> timeAsync<T>(String label, Future<T> Function() fn) async {
    if (!enabled) return fn();
    start(label);
    try {
      return await fn();
    } finally {
      end(label);
    }
  }

  static void logBuildStart(String label) {
    if (!enabled) return;
    _buildCount++;
    start('$label#$_buildCount');
  }

  static void logBuildEnd(String label) {
    if (!enabled) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      end('$label#$_buildCount');
    });
  }
}
