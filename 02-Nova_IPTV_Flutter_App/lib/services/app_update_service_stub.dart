import 'package:flutter/widgets.dart';

/// No-op على المنصات غير المدعومة (iOS / Windows / Web).
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  bool get isSupported => false;

  void scheduleCheckForLoginEntry(BuildContext context) {}

  void scheduleCheckForHome(BuildContext context) {}

  Future<void> prefetchAtLaunch() async {}

  void onAppResumed(BuildContext? context) {}
}
