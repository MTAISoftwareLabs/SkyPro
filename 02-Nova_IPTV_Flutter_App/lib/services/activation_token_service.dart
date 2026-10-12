import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mehdi_iptv/core/config.dart';
import 'package:mehdi_iptv/helpers/helpers.dart';

/// Signed panel activation token (`stv1.{payload}.{hmac}`) — same format as Smart TV.
class ActivationTokenService {
  ActivationTokenService._();

  static const String storageKey = 'activation_signed_token';

  static String panelHost() => licenseBoundPanelHost();

  static String _b64urlDecode(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    switch (s.length % 4) {
      case 2:
        s += '==';
        break;
      case 3:
        s += '=';
        break;
    }
    return utf8.decode(base64.decode(s));
  }

  static Map<String, dynamic>? _parseClaims(
    String token,
    String deviceId,
    String panelHost,
    String secret,
  ) {
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != 'stv1') return null;
    if (secret.isEmpty || deviceId.isEmpty || panelHost.isEmpty) return null;
    final payload = parts[1];
    final sig = parts[2].toLowerCase();
    final expected = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(payload)).toString();
    if (expected != sig) return null;
    try {
      final decoded = json.decode(_b64urlDecode(payload));
      if (decoded is! Map) return null;
      final claims = Map<String, dynamic>.from(decoded);
      if (claims['v'] != 1) return null;
      if ('${claims['did'] ?? ''}' != deviceId) return null;
      if ('${claims['ph'] ?? ''}'.toLowerCase() != panelHost.toLowerCase()) {
        return null;
      }
      final exp = int.tryParse('${claims['exp'] ?? ''}') ?? 0;
      if (exp <= DateTime.now().millisecondsSinceEpoch ~/ 1000) return null;
      return claims;
    } catch (_) {
      return null;
    }
  }

  static bool _deviceExpiryPassed(Map<String, dynamic> claims) {
    final lt = claims['lt'];
    if (lt == 1 || lt == true) return false;
    final raw = '${claims['ed'] ?? ''}'.trim();
    if (raw.isEmpty) return false;
    final expiry = DateTime.tryParse(raw.contains(' ') ? raw.replaceFirst(' ', 'T') : raw);
    if (expiry == null) return false;
    if (activationExpiryLooksLifetime(expiry)) return false;
    return !expiry.isAfter(DateTime.now());
  }

  static Map<String, dynamic>? storedClaims(String deviceId) {
    final token = (GetStorage().read(storageKey) ?? '').toString().trim();
    if (token.isEmpty) return null;
    return _parseClaims(token, deviceId, panelHost(), kAppApiSecret.trim());
  }

  static void clear() {
    GetStorage().remove(storageKey);
  }

  /// Store and verify token from panel response. Returns true when token is valid.
  static bool applyResponse(Map<String, dynamic> raw, String deviceId) {
    final token = (raw['activation_token'] as String?)?.trim() ?? '';
    if (token.isNotEmpty) {
      final claims = _parseClaims(token, deviceId, panelHost(), kAppApiSecret.trim());
      if (claims == null) {
        clear();
        return false;
      }
      GetStorage().write(storageKey, token);
      return true;
    }
    final status = '${raw['status'] ?? ''}'.toLowerCase().trim();
    final activated = raw['activated'] == true || raw['activated'] == 1;
    if (!activated || status == 'inactive') {
      clear();
    }
    return false;
  }

  static String _statusFromClaims(Map<String, dynamic> claims) {
    final st = '${claims['st'] ?? ''}'.toLowerCase().trim();
    if (st == 'blocked') return 'محظور';
    if (st == 'expired' || _deviceExpiryPassed(claims)) return 'منتهي';
    if (st == 'active') return 'نشط';
    return 'غير مفعل';
  }

  static String signedStatusForDevice(String deviceId) {
    final claims = storedClaims(deviceId.trim());
    if (claims == null) return 'غير مفعل';
    return _statusFromClaims(claims);
  }

  /// Prefer signed status when activation is enforced on the panel.
  static String effectiveActivationStatus({String? storedStatus}) {
    if (!activationEnforcedFromStorage()) {
      return (storedStatus ?? GetStorage().read('activation_status') ?? '')
          .toString();
    }
    final deviceId = (GetStorage().read('device_id') ?? '').toString().trim();
    if (deviceId.isEmpty) return 'غير مفعل';
    return signedStatusForDevice(deviceId);
  }
}
