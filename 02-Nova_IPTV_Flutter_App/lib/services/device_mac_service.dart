import 'dart:io';

import 'package:flutter/services.dart';

/// MAC address للوحة فقط — لا يُعرض في واجهة المستخدم (متوافق مع Google Play).
class DeviceMacService {
  DeviceMacService._();

  static final DeviceMacService instance = DeviceMacService._();

  static const MethodChannel _channel = MethodChannel('main_activity_channel');

  String? _cached;

  Future<String> resolve() async {
    final cached = _cached?.trim() ?? '';
    if (_isValid(cached)) return cached;

    if (!Platform.isAndroid) return '';

    final mac = _normalize(await _fromAndroidNative());
    if (_isValid(mac)) {
      _cached = mac;
    }
    return mac;
  }

  Future<String> _fromAndroidNative() async {
    try {
      final raw = await _channel
          .invokeMethod<String>('getMacAddress')
          .timeout(const Duration(seconds: 3), onTimeout: () => '');
      return raw ?? '';
    } catch (_) {
      return '';
    }
  }

  String _normalize(String raw) {
    final hex = raw.toUpperCase().replaceAll(RegExp(r'[^A-F0-9]'), '');
    if (hex.length != 12) return '';
    if (hex == '020000000000' || hex == '000000000000') return '';
    final pairs = <String>[];
    for (var i = 0; i < 12; i += 2) {
      pairs.add(hex.substring(i, i + 2));
    }
    return pairs.join(':');
  }

  bool _isValid(String mac) {
    if (mac.isEmpty) return false;
    return RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(mac);
  }
}
