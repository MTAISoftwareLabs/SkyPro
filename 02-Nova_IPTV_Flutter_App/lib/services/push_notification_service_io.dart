import 'dart:io';

import 'push_notification_service_mobile.dart' as mobile;
import 'push_notification_service_stub.dart' as stub;

/// Android / iOS → OneSignal؛ Windows / macOS / Linux → no-op.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  dynamic get _impl => (Platform.isAndroid || Platform.isIOS)
      ? mobile.PushNotificationService.instance
      : stub.PushNotificationService.instance;

  void start() => _impl.start();

  void stop() => _impl.stop();

  bool get userNotificationsEnabled => _impl.userNotificationsEnabled;

  Future<bool> setUserNotificationsEnabled(bool enabled) =>
      _impl.setUserNotificationsEnabled(enabled) as Future<bool>;

  Future<void> sync({String? deviceId, bool requestOsPermission = true}) =>
      _impl.sync(
        deviceId: deviceId,
        requestOsPermission: requestOsPermission,
      ) as Future<void>;
}
