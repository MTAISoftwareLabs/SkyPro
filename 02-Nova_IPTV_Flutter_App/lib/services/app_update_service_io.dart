import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app_update_service_mobile.dart' as mobile;
import 'app_update_service_stub.dart' as stub;

/// Android → Google Play In-App Updates؛ باقي المنصات → no-op.
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  dynamic get _impl => Platform.isAndroid
      ? mobile.AppUpdateService.instance
      : stub.AppUpdateService.instance;

  bool get isSupported => _impl.isSupported;

  void scheduleCheckForLoginEntry(BuildContext context) =>
      _impl.scheduleCheckForLoginEntry(context);

  void scheduleCheckForHome(BuildContext context) =>
      _impl.scheduleCheckForHome(context);

  Future<void> prefetchAtLaunch() => _impl.prefetchAtLaunch();

  void onAppResumed(BuildContext? context) => _impl.onAppResumed(context);
}
