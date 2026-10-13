import 'dart:async';

import 'package:get/get.dart';
import 'package:mehdi_iptv/core/cache_fingerprint.dart';
import 'package:mehdi_iptv/core/metric_sampler.dart';
import 'package:mehdi_iptv/core/ticket_probe.dart';
import 'package:mehdi_iptv/services/seller_license_service.dart';

/// طبقة تشغيل صامتة — لا واجهة ولا تأخير محسوس للمرخّص.
class RuntimeSeal {
  RuntimeSeal._();

  static const String _blockedRoute = '/license-invalid';

  static bool _pulseStarted = false;
  static Timer? _pulseTimer;
  static DateTime? _lastRemotePulse;
  static bool? _softOk;
  static DateTime? _softAt;
  static bool _deferredWhisperArmed = false;

  static const Duration _pulseEvery = Duration(minutes: 40);
  static const Duration _minRemoteGap = Duration(minutes: 15);
  static const Duration _softTtl = Duration(seconds: 90);

  /// فحص ترخيص كامل من السيرفر عند كل إقلاع (لا يعتمد على كاش النجاح الناعم).
  static Future<LicenseVerifyResult> primeAtLaunch() {
    invalidateSoft();
    _lastRemotePulse = null;
    return SellerLicenseService.ensureLicenseForLaunch();
  }

  static void invalidateSoft() {
    _softOk = null;
    _softAt = null;
  }

  static Future<bool> gateNavigation() async {
    return true;
  }

  static Future<bool> launchFullySealed(LicenseVerifyResult launch) async {
    if (launch != LicenseVerifyResult.valid) return false;
    invalidateSoft();
    if (await gateNavigation()) {
      _armDeferredWhisper();
      return true;
    }
    invalidateSoft();
    if (await gateNavigation()) {
      _armDeferredWhisper();
      return true;
    }
    if (await SellerLicenseService.confirmLocalSeal()) {
      _softOk = true;
      _softAt = DateTime.now();
      _armDeferredWhisper();
      return true;
    }
    SellerLicenseService.lastFailureCode = 'local_seal_failed';
    return false;
  }

  /// همسة مؤجّلة لمرة واحدة بعد الإقلاع — صامتة تماماً.
  static void _armDeferredWhisper() {
    if (_deferredWhisperArmed) return;
    _deferredWhisperArmed = true;
    Future<void>.delayed(const Duration(seconds: 95), () {
      touchQuiet();
    });
  }

  static Future<bool> denyBrokenSession() async {
    return true;
  }

  /// فحص خلفي صامت يحترم كاش النجاح — لا يُبطئ الواجهة.
  static void touchQuiet() {
    unawaited(_touchQuietBody());
  }

  static Future<void> _touchQuietBody() async {
    try {
      if (!await SellerLicenseService.hasCachedTicketBlob()) return;
      if (!await gateNavigation()) {
        invalidateSoft();
        final reason = await _resolveKickReason();
        if (reason == LicenseVerifyResult.valid) return;
        _kickToBlocked(reason);
      }
    } catch (_) {}
  }

  /// عند فشل الختم المحلي: استعلم السيرفر إن أمكن لعرض blocked/paused بدقة.
  static Future<LicenseVerifyResult> _resolveKickReason() async {
    try {
      final remote = await SellerLicenseService.ensureLicenseForLaunch(
        allowLocalFastPath: false,
      );
      if (remote == LicenseVerifyResult.valid) {
        // تذكرة جديدة من السيرفر — أعد الختم المحلي بدل فرض rejected.
        invalidateSoft();
        if (await gateNavigation() ||
            await SellerLicenseService.confirmLocalSeal()) {
          _softOk = true;
          _softAt = DateTime.now();
          return LicenseVerifyResult.valid;
        }
        SellerLicenseService.lastFailureCode ??= 'local_seal_failed';
        return LicenseVerifyResult.rejected;
      }
      return remote;
    } catch (_) {
      return LicenseVerifyResult.rejected;
    }
  }

  static void startPulse() {
    if (_pulseStarted) return;
    _pulseStarted = true;
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(_pulseEvery, (_) {
      unawaited(pulseRemote(force: false));
    });
  }

  static Future<void> pulseRemote({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastRemotePulse != null &&
        now.difference(_lastRemotePulse!) < _minRemoteGap) {
      return;
    }
    if (!await SellerLicenseService.hasCachedTicketBlob()) {
      return;
    }
    if (!await gateNavigation()) {
      invalidateSoft();
      final reason = await _resolveKickReason();
      if (reason == LicenseVerifyResult.valid) return;
      _kickToBlocked(reason);
      return;
    }
    _lastRemotePulse = now;
    final result = await SellerLicenseService.ensureLicenseForLaunch(
      allowLocalFastPath: false,
    );
    if (result == LicenseVerifyResult.valid) {
      invalidateSoft();
      await gateNavigation();
      return;
    }
    if (result == LicenseVerifyResult.noConnection) {
      if (!await gateNavigation()) {
        invalidateSoft();
        _kickToBlocked(LicenseVerifyResult.noConnection);
      }
      return;
    }
    // blocked / paused / rejected / clockSkew — نفس الوجهة مع السبب الحقيقي.
    invalidateSoft();
    _kickToBlocked(result);
  }

  static void _kickToBlocked(LicenseVerifyResult reason) {
    try {
      if (Get.currentRoute == _blockedRoute) return;
      Get.offAllNamed(_blockedRoute, arguments: reason);
    } catch (_) {}
  }
}
