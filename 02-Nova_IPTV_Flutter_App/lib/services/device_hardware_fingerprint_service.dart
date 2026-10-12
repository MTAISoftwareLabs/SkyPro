import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

/// بصمة عتاد للوحة فقط — تربط نفس الجهاز حتى بعد factory reset.
///
/// Android: Widevine ID + MAC + بيانات العتاد (ثابتة بعد الفورمات).
/// iOS: identifierForVendor + model + machine.
class DeviceHardwareFingerprintService {
  DeviceHardwareFingerprintService._();

  static final DeviceHardwareFingerprintService instance =
      DeviceHardwareFingerprintService._();

  static const MethodChannel _channel = MethodChannel('main_activity_channel');

  String? _cached;

  Future<String> resolve() async {
    final cached = _cached?.trim() ?? '';
    if (_isValid(cached)) return cached;

    final seed = await _buildSeed();
    if (seed.isEmpty) return '';

    final digest = sha256.convert(utf8.encode(seed)).toString();
    if (_isValid(digest)) {
      _cached = digest;
    }
    return digest;
  }

  Future<String> _buildSeed() async {
    if (Platform.isAndroid) {
      final native = await _androidNativeSeed();
      if (native.isNotEmpty) return native;
    }
    return _fallbackSeed();
  }

  Future<String> _androidNativeSeed() async {
    try {
      final raw = await _channel
          .invokeMethod<Object>('getDeviceBindingSeed')
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (raw is! Map) return '';
      final map = Map<String, dynamic>.from(raw);
      const order = [
        'widevine',
        'mac',
        'board',
        'hardware',
        'brand',
        'manufacturer',
        'model',
        'device',
        'product',
      ];
      final parts = <String>[];
      for (final key in order) {
        final value = (map[key] ?? '').toString().trim();
        if (value.isNotEmpty) {
          parts.add('$key=$value');
        }
      }
      if (parts.isEmpty) return '';
      return 'android-binding-v2|${parts.join('|')}';
    } catch (_) {
      return '';
    }
  }

  Future<String> _fallbackSeed() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        final parts = [
          'android-binding-v1',
          android.id.trim(),
          android.brand.trim(),
          android.model.trim(),
          android.manufacturer.trim(),
          android.device.trim(),
          android.board.trim(),
          android.hardware.trim(),
        ];
        if (parts.any((p) => p.isNotEmpty && !p.startsWith('android-'))) {
          return parts.join('|');
        }
        return '';
      }
      if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        final parts = [
          'ios',
          (ios.identifierForVendor ?? '').trim(),
          ios.model.trim(),
          ios.utsname.machine.trim(),
        ];
        if (parts.length > 2 && parts[1].isNotEmpty) {
          return parts.join('|');
        }
        return '';
      }
      if (Platform.isWindows) {
        final win = await deviceInfo.windowsInfo;
        final parts = [
          'windows',
          win.deviceId.trim(),
          win.computerName.trim(),
        ];
        if (parts[1].isNotEmpty) return parts.join('|');
      }
    } catch (_) {}
    return '';
  }

  bool _isValid(String value) {
    return RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  }
}
