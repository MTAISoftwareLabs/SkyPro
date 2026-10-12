import 'dart:async';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mehdi_iptv/helpers/helpers.dart';
import 'package:mehdi_iptv/services/activation_token_service.dart';
import 'package:mehdi_iptv/repository/api/activation_api.dart';

/// فحص التفعيل عند الفتح + كل ساعة، وإخراج الجلسة إلى شاشة الدخول إن انتهى.
class ActivationGuardService {
  ActivationGuardService._();
  static final ActivationGuardService instance = ActivationGuardService._();

  static const Duration serverInterval = Duration(hours: 1);
  static const Duration _serverTimeout = Duration(seconds: 12);

  final ActivationApi _api = ActivationApi();
  final GetStorage _storage = GetStorage();
  Timer? _hourlyTimer;
  Timer? _expiryTimer;
  bool _started = false;
  bool _kicking = false;
  bool _serverInFlight = false;
  DateTime? _lastServerCheckAt;

  void start() {
    if (_started) return;
    _started = true;
    _hourlyTimer?.cancel();
    _hourlyTimer = Timer.periodic(serverInterval, (_) {
      unawaited(enforce(forceServer: true));
    });
    _armLocalExpiryTimer();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _hourlyTimer?.cancel();
    _hourlyTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  void markServerChecked() {
    _lastServerCheckAt = DateTime.now();
    _armLocalExpiryTimer();
  }

  bool get _onAuthGateRoute {
    final r = Get.currentRoute;
    return r.isEmpty ||
        r == screenSplash ||
        r == '/' ||
        r == screenEntry ||
        r == screenLicenseInvalid ||
        r == screenRegister;
  }

  String get _storedStatus => ActivationTokenService.effectiveActivationStatus();

  bool get _serverCheckStale =>
      _lastServerCheckAt == null ||
      DateTime.now().difference(_lastServerCheckAt!) >= serverInterval;

  /// يحدّث الحالة من اللوحة دون إخراج المستخدم.
  Future<void> refreshFromServer() async {
    if (_serverInFlight) return;
    _serverInFlight = true;
    try {
      var deviceId = (_storage.read('device_id') ?? '').toString().trim();
      if (deviceId.isEmpty) {
        deviceId = await _api.getDeviceId().timeout(
          const Duration(seconds: 6),
          onTimeout: () => '',
        );
        if (deviceId.isNotEmpty) {
          await _storage.write('device_id', deviceId);
        }
      }
      if (deviceId.isEmpty) return;
      await _api
          .checkActivation(deviceId, allowAutoRegister: false)
          .timeout(_serverTimeout);
      markServerChecked();
    } catch (_) {
      // عند فشل الشبكة نبقى على الحالة المحلية (تاريخ الانتهاء).
    } finally {
      _serverInFlight = false;
    }
  }

  /// يفحص محلياً ثم من اللوحة إن طُلب، ويُخرج إلى الدخول إن مُنع.
  Future<bool> enforce({bool forceServer = false}) async {
    if (isActivationLoginDenied(_storedStatus)) {
      await _kickToEntryIfNeeded();
      return false;
    }
    if (forceServer) {
      await refreshFromServer();
      if (isActivationLoginDenied(_storedStatus)) {
        await _kickToEntryIfNeeded();
        return false;
      }
    }
    _armLocalExpiryTimer();
    return true;
  }

  /// عند العودة للتطبيق: فحص محلي فوراً، ومن اللوحة إن مضت ساعة.
  Future<bool> enforceOnResume() {
    return enforce(forceServer: _serverCheckStale);
  }

  void _armLocalExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final status = _storedStatus.trim();
    if (status != 'محظور' && !activationEnforcedFromStorage()) return;
    final info = parseActivationRemaining(
      (_storage.read('activation_expiry_date') ?? '').toString(),
    );
    if (info == null) return;
    if (info.isLifetime) return;
    if (!info.isValid) return;
    _expiryTimer = Timer(Duration(seconds: info.totalSeconds + 2), () {
      unawaited(enforce(forceServer: true));
    });
  }

  Future<void> _kickToEntryIfNeeded() async {
    if (_kicking || _onAuthGateRoute) return;
    _kicking = true;
    try {
      await lockEntryScreenOrientations();
      await _storage.write('activation_kick_notified', true);
      if (Get.currentRoute != screenEntry) {
        Get.offAllNamed(screenEntry);
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final ctx = Get.context;
      if (ctx != null && ctx.mounted) {
        showActivationLoginDeniedToast(ctx, _storedStatus);
      }
    } catch (_) {
    } finally {
      _kicking = false;
    }
  }
}
