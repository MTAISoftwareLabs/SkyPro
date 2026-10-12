/// منصات بلا OneSignal (Windows / macOS / Linux / Web).
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  bool get userNotificationsEnabled => true;

  Future<bool> setUserNotificationsEnabled(bool enabled) async => false;

  void start() {}

  void stop() {}

  Future<void> sync({String? deviceId, bool requestOsPermission = true}) async {}
}
