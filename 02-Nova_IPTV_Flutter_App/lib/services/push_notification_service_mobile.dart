import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mehdi_iptv/services/notification_inbox_service.dart';
import 'package:mehdi_iptv/services/stable_device_id_service.dart';
import 'package:mehdi_iptv/repository/api/activation_api.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// OneSignal — Android + iOS فقط. يربط `device_id` كـ external_id للاستهداف من اللوحة.
///
/// سياسة الصلاحيات:
/// - طلب الإشعار مرة واحدة فقط (أو عند تفعيله يدوياً من الإعدادات).
/// - رفض المستخدم = التطبيق يكمل بدون إشعارات، بلا فتح Settings وبلا حلقات إزعاج.
class PushNotificationService with WidgetsBindingObserver {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const String kStorageAppId = 'onesignal_app_id';
  static const String kStorageEnabled = 'onesignal_enabled';
  static const String kStorageUserEnabled = 'push_notifications_user_enabled';
  static const String kStoragePermissionAsked =
      'push_notifications_permission_asked';
  static const String kStoragePermissionDenied =
      'push_notifications_permission_denied';

  final GetStorage _storage = GetStorage();
  bool _started = false;
  bool _initialized = false;
  bool _clickListenerBound = false;
  bool _foregroundListenerBound = false;
  String? _boundAppId;
  Future<void>? _syncInFlight;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(syncFromStorage());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // إعادة مزامنة الاشتراك فقط — بدون إعادة طلب صلاحية أو فتح Settings.
      unawaited(syncFromStorage(requestOsPermission: false));
    }
  }

  Future<void> syncFromStorage({bool requestOsPermission = true}) async {
    var deviceId = (_storage.read('device_id') ?? '').toString().trim();
    if (deviceId.isEmpty) {
      deviceId = await StableDeviceIdService.instance.resolve();
    }
    await sync(deviceId: deviceId, requestOsPermission: requestOsPermission);
  }

  Future<void> sync({String? deviceId, bool requestOsPermission = true}) {
    if (!_started && deviceId != null && deviceId.trim().isNotEmpty) {
      // لا نستدعي start() هنا لتفادي sync مزدوج؛ نُسجّل المُراقب فقط.
      _started = true;
      WidgetsBinding.instance.addObserver(this);
    }

    final previous = _syncInFlight;
    final run = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      await _syncBody(
        deviceId: deviceId,
        requestOsPermission: requestOsPermission,
      );
    }();
    _syncInFlight = run;
    return run.whenComplete(() {
      if (identical(_syncInFlight, run)) {
        _syncInFlight = null;
      }
    });
  }

  Future<void> _syncBody({
    String? deviceId,
    required bool requestOsPermission,
  }) async {
    // صندوق الوارد من اللوحة مستقل عن صلاحية Push.
    unawaited(_syncInboxFromPanelQuiet());

    if (!_isEnabled()) {
      if (_initialized) {
        try {
          await OneSignal.User.pushSubscription.optOut();
        } catch (_) {}
      }
      return;
    }

    final appId = _resolveAppId();
    try {
      if (!_initialized || _boundAppId != appId) {
        if (kDebugMode) {
          OneSignal.Debug.setLogLevel(OSLogLevel.warn);
        }
        await OneSignal.initialize(appId);
        _initialized = true;
        _boundAppId = appId;
        _bindClickListenerOnce();
        _bindForegroundListenerOnce();
      }

      final id = (deviceId ?? '').trim();

      if (requestOsPermission) {
        await _ensureOsPermission(userInitiated: false);
      }

      if (!userNotificationsEnabled) return;

      if (OneSignal.Notifications.permission) {
        await OneSignal.User.pushSubscription.optIn();
      } else {
        // بدون صلاحية النظام: نكمل التطبيق بدون push، بلا إزعاج.
        try {
          await OneSignal.User.pushSubscription.optOut();
        } catch (_) {}
        return;
      }

      // ربط device_id بعد الاشتراك حتى يصل الإشعار عند الاستهداف من اللوحة.
      if (id.isNotEmpty) {
        try {
          await OneSignal.login(id);
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('[PushNotification] login failed: $e\n$st');
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PushNotification] sync failed: $e\n$st');
      }
    }
  }

  Future<void> _syncInboxFromPanelQuiet() async {
    try {
      await ActivationApi().syncNotificationInbox();
    } catch (_) {}
  }

  void _bindClickListenerOnce() {
    if (_clickListenerBound) return;
    _clickListenerBound = true;
    OneSignal.Notifications.addClickListener((event) {
      unawaited(_persistOsNotification(event.notification));
      unawaited(_openNotificationUrl(event));
    });
  }

  void _bindForegroundListenerOnce() {
    if (_foregroundListenerBound) return;
    _foregroundListenerBound = true;
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      unawaited(_persistOsNotification(event.notification));
      // نعرض إشعار النظام أيضاً — لا نمنع العرض الافتراضي.
    });
  }

  Future<void> _persistOsNotification(OSNotification n) async {
    try {
      NotificationInboxService.instance.ensureLoaded();
      final additional = n.additionalData;
      var url = '';
      if (additional != null) {
        url = (additional['url'] ?? additional['link'] ?? '').toString().trim();
      }
      if (url.isEmpty) {
        url = (n.launchUrl ?? '').trim();
      }
      await NotificationInboxService.instance.addIncoming(
        id: n.notificationId,
        title: (n.title ?? '').trim(),
        body: (n.body ?? '').trim(),
        url: url.isEmpty ? null : url,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PushNotification] inbox persist failed: $e\n$st');
      }
    }
  }

  Future<void> _openNotificationUrl(OSNotificationClickEvent event) async {
    try {
      final additional = event.notification.additionalData;
      var raw = '';
      if (additional != null) {
        raw = (additional['url'] ?? additional['link'] ?? '').toString().trim();
      }
      if (raw.isEmpty) {
        raw = (event.notification.launchUrl ?? '').trim();
      }
      if (raw.isEmpty) return;
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          !(uri.isScheme('http') || uri.isScheme('https')) ||
          uri.host.isEmpty) {
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PushNotification] open url failed: $e\n$st');
      }
    }
  }

  /// يطلب صلاحية النظام مرة واحدة فقط، ولا يفتح Settings أبداً تلقائياً.
  /// يرجع true إذا كانت الصلاحية ممنوحة.
  Future<bool> _ensureOsPermission({required bool userInitiated}) async {
    if (OneSignal.Notifications.permission) {
      await _storage.write(kStoragePermissionDenied, false);
      return true;
    }

    final alreadyAsked = _storage.read(kStoragePermissionAsked) == true;
    final softDenied = _storage.read(kStoragePermissionDenied) == true;

    // التشغيل التلقائي: لا نعيد الطلب بعد الرفض أو بعد أول محاولة.
    if (!userInitiated && (alreadyAsked || softDenied)) {
      return false;
    }

    bool canRequest = false;
    try {
      canRequest = await OneSignal.Notifications.canRequest();
    } catch (_) {
      canRequest = !alreadyAsked;
    }

    if (!canRequest) {
      // مرفوض نهائياً من النظام — لا نفتح Settings، نشتغل بدون إشعارات.
      await _storage.write(kStoragePermissionAsked, true);
      await _storage.write(kStoragePermissionDenied, true);
      if (!userInitiated) {
        await _storage.write(kStorageUserEnabled, false);
      }
      return false;
    }

    await _storage.write(kStoragePermissionAsked, true);
    // fallbackToSettings: false — مهم: رفض المستخدم ≠ فتح قائمة Settings.
    final granted = await OneSignal.Notifications.requestPermission(false);
    if (granted) {
      await _storage.write(kStoragePermissionDenied, false);
      return true;
    }

    await _storage.write(kStoragePermissionDenied, true);
    if (!userInitiated) {
      // أول رفض: نطفئ التفضيل داخل التطبيق ونكمل بدون إشعارات.
      await _storage.write(kStorageUserEnabled, false);
    }
    return false;
  }

  bool get userNotificationsEnabled {
    final flag = _storage.read(kStorageUserEnabled);
    if (flag is bool) return flag;
    return true;
  }

  /// تفعيل/تعطيل من إعدادات التطبيق.
  /// عند التفعيل: نطلب الصلاحية مرة (بدون فتح Settings). إن رُفضت نُبقي التفضيل
  /// ونشتغل بدون push حتى يفعّلها المستخدم من نظام الجهاز بنفسه.
  Future<bool> setUserNotificationsEnabled(bool enabled) async {
    await _storage.write(kStorageUserEnabled, enabled);
    if (!enabled) {
      try {
        if (_initialized) {
          await OneSignal.User.pushSubscription.optOut();
        }
      } catch (_) {}
      return false;
    }
    if (!_isPanelEnabled()) return false;

    var deviceId = (_storage.read('device_id') ?? '').toString().trim();
    if (deviceId.isEmpty) {
      deviceId = await StableDeviceIdService.instance.resolve();
    }

    try {
      if (!_initialized) {
        await sync(deviceId: deviceId, requestOsPermission: false);
      }
      final granted = await _ensureOsPermission(userInitiated: true);
      if (granted) {
        await OneSignal.User.pushSubscription.optIn();
        if (deviceId.isNotEmpty) {
          await OneSignal.login(deviceId);
        }
      }
      return granted;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PushNotification] enable failed: $e\n$st');
      }
      return OneSignal.Notifications.permission;
    }
  }

  bool _isPanelEnabled() {
    final flag = _storage.read(kStorageEnabled);
    if (flag == false || flag == 0 || flag == '0') return false;
    return _resolveAppId().isNotEmpty;
  }

  bool _isEnabled() {
    if (!userNotificationsEnabled) return false;
    return _isPanelEnabled();
  }

  String _resolveAppId() {
    return (_storage.read(kStorageAppId) ?? '').toString().trim();
  }
}
