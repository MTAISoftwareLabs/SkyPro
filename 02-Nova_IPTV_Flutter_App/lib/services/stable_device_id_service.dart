import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// معرّف الجهاز الظاهر للمستخدم — شكل مألوف + بصمة فريدة قوية.
///
/// Android مثال: `UP1A.231005.007-A1B2C3D4E5F67890`
/// - قبل الشرطة: Build.ID (شكل فقط — قد يتكرر)
/// - بعد الشرطة: 16 hex من SHA-256(ANDROID_ID + Widevine + MAC)
///   → احتمال التصادم بين جهازين حقيقيين ≈ صفر عملياً
///
/// iOS: identifierForVendor (فريد لكل جهاز لنفس المطوّر).
class StableDeviceIdService {
  StableDeviceIdService._();

  static final StableDeviceIdService instance = StableDeviceIdService._();

  static const MethodChannel _channel = MethodChannel('main_activity_channel');

  static const String kStableDeviceIdStorage = 'stable_device_id_v4';
  static const String kLegacyStableV3 = 'stable_device_id_v3';
  static const String kLegacyStableV2 = 'stable_device_id_v2';
  static const String kLegacyStableV1 = 'stable_device_id_v1';
  static const String kLegacyDeviceIdStorage = 'device_id';

  static const String _kBrokenAndroidId = '9774D56D682E549C';

  /// 16 hex = 64 بت — كافية ضد التصادم حتى لملايين الأجهزة.
  static const int _kUniqueSuffixLen = 16;

  String? _cached;

  Future<String> resolve() async {
    // المصدر الحي أولاً (ثابت لنفس الجهاز، مختلف بين الأجهزة).
    final native = await _readPlatformUniqueId();
    if (_isUniqueValid(native)) {
      return _finish(native!);
    }

    final cached = _clean(_cached);
    if (_isUniqueValid(cached)) {
      return cached!;
    }

    final box = GetStorage();
    for (final key in [
      kStableDeviceIdStorage,
      kLegacyStableV3,
      kLegacyStableV2,
      kLegacyStableV1,
      kLegacyDeviceIdStorage,
    ]) {
      final id = _clean(box.read(key));
      if (_isUniqueValid(id)) {
        return _finish(id!);
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        kStableDeviceIdStorage,
        kLegacyStableV3,
        kLegacyStableV2,
        kLegacyStableV1,
        kLegacyDeviceIdStorage,
      ]) {
        final id = _clean(prefs.getString(key));
        if (_isUniqueValid(id)) {
          return _finish(id!);
        }
      }
    } catch (_) {}

    // آخر ملاذ: عشوائي قوي يُحفظ مرة واحدة ولا يُعاد توليده.
    final generated = _composeId(null, _generateInstallId());
    return _finish(generated);
  }

  Future<String?> _readPlatformUniqueId() async {
    try {
      if (Platform.isAndroid) {
        final buildId = await _readAndroidBuildId();
        final fingerprint = await _buildAndroidUniqueFingerprint();
        if (fingerprint == null || fingerprint.isEmpty) return null;
        return _composeId(buildId, fingerprint);
      }
      if (Platform.isIOS) {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        final id = (iosInfo.identifierForVendor ?? '').trim().toUpperCase();
        if (_isUniqueValid(id)) return id;
      }
      if (Platform.isWindows) {
        final win = await DeviceInfoPlugin().windowsInfo;
        final id = win.deviceId.trim().toUpperCase();
        if (_isUniqueValid(id)) return id;
      }
    } catch (_) {}
    return null;
  }

  /// يجمع كل مصادر التفرّد المتاحة ثم يهرّسها — حتى لو ANDROID_ID
  /// تكرر نادراً على أجهزة رخيصة، Widevine/MAC يفرّقون.
  Future<String?> _buildAndroidUniqueFingerprint() async {
    final androidId = await _readAndroidIdNative();
    final seed = await _readBindingSeedMap();
    final widevine = (seed?['widevine'] ?? '').toString().trim().toUpperCase();
    final mac = (seed?['mac'] ?? '').toString().trim().toUpperCase();

    final parts = <String>[];
    if (androidId != null && androidId.isNotEmpty) {
      parts.add('aid=$androidId');
    }
    if (widevine.length >= 8) {
      parts.add('wv=$widevine');
    }
    if (mac.length >= 8) {
      parts.add('mac=$mac');
    }

    if (parts.isEmpty) {
      // لا مصدر عتاد — لا نُرجع null فوراً؛ المُستدعي يستخدم التخزين/التوليد.
      return null;
    }

    // إن وُجد ANDROID_ID وحده بطول كامل (≥16) نستخدمه كما هو لثبات أوضح.
    // مع مصادر إضافية نهرّس الكل حتى لا يعتمد على مصدر واحد.
    if (parts.length == 1 &&
        androidId != null &&
        androidId.length >= _kUniqueSuffixLen) {
      return androidId.length > 32
          ? androidId.substring(0, 32)
          : androidId;
    }

    final digest = sha256.convert(utf8.encode(parts.join('|'))).toString();
    return digest.substring(0, _kUniqueSuffixLen).toUpperCase();
  }

  Future<String?> _readAndroidBuildId() async {
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final id = androidInfo.id.trim();
      if (id.isEmpty) return null;
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readAndroidIdNative() async {
    try {
      final raw = await _channel
          .invokeMethod<Object>('getAndroidId')
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      final id = (raw ?? '').toString().trim().toUpperCase();
      if (id.isEmpty || id == _kBrokenAndroidId) return null;
      final plain = id.replaceAll('-', '');
      if (!_looksLikeHexId(plain)) return null;
      return plain;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readBindingSeedMap() async {
    try {
      final raw = await _channel
          .invokeMethod<Object>('getDeviceBindingSeed')
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (raw is! Map) return null;
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }

  /// `UP1A.231005.007-A1B2C3D4E5F67890`
  String _composeId(String? buildId, String uniqueRaw) {
    final suffix = _normalizeSuffix(uniqueRaw);
    final build = (buildId ?? '').trim();
    if (build.isEmpty) return suffix;
    if (_isCompositeUniqueId(build)) return build;
    return '$build-$suffix';
  }

  String _normalizeSuffix(String uniqueRaw) {
    final hex =
        uniqueRaw.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '').toUpperCase();
    if (hex.length >= _kUniqueSuffixLen) {
      return hex.substring(0, _kUniqueSuffixLen);
    }
    if (hex.isNotEmpty) {
      final padded = (hex + _generateInstallId()).toUpperCase();
      return padded.substring(0, _kUniqueSuffixLen);
    }
    return _generateInstallId().substring(0, _kUniqueSuffixLen);
  }

  Future<String> _finish(String id) async {
    await _persistAll(id);
    _cached = id;
    return id;
  }

  String? _clean(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  bool _isUniqueValid(String? id) {
    if (id == null || id.isEmpty) return false;
    final value = id.trim();
    if (value.length < _kUniqueSuffixLen || value.length > 128) return false;
    if (value.toUpperCase() == _kBrokenAndroidId) return false;
    if (_isCompositeUniqueId(value)) return true;
    if (_looksLikeBareBuildId(value)) return false;
    // iOS UUID أو hex كامل
    return _looksLikeHexId(value) || _looksLikeUuid(value);
  }

  /// يشترط لاحقة ≥ 16 hex بعد آخر شرطة (يرفض اللاحقات القصيرة القديمة).
  bool _isCompositeUniqueId(String id) {
    return RegExp(
      r'^.+-([A-Fa-f0-9]{16,64})$',
    ).hasMatch(id.trim());
  }

  bool _looksLikeBareBuildId(String id) {
    final value = id.trim();
    if (_isCompositeUniqueId(value)) return false;
    // لاحقة قصيرة قديمة (8 hex) — نعتبرها غير كافية ونُعيد البناء.
    if (RegExp(r'^.+-([A-Fa-f0-9]{1,15})$').hasMatch(value)) {
      return true;
    }
    if (value.contains('.')) {
      if (RegExp(r'^[A-Za-z][A-Za-z0-9]*\.\d{5,}').hasMatch(value)) {
        return true;
      }
      if ('.'.allMatches(value).length >= 2) return true;
    }
    return false;
  }

  bool _looksLikeHexId(String id) {
    return RegExp(r'^[A-Fa-f0-9]{16,64}$').hasMatch(id.trim());
  }

  bool _looksLikeUuid(String id) {
    return RegExp(
      r'^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$',
    ).hasMatch(id.trim());
  }

  String _generateInstallId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  Future<void> _persistAll(String id) async {
    final box = GetStorage();
    await box.write(kStableDeviceIdStorage, id);
    await box.write(kLegacyStableV3, id);
    await box.write(kLegacyStableV2, id);
    await box.write(kLegacyStableV1, id);
    await box.write(kLegacyDeviceIdStorage, id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kStableDeviceIdStorage, id);
      await prefs.setString(kLegacyStableV3, id);
      await prefs.setString(kLegacyStableV2, id);
      await prefs.setString(kLegacyStableV1, id);
      await prefs.setString(kLegacyDeviceIdStorage, id);
    } catch (_) {}
  }
}
