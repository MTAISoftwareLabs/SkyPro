import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:mehdi_iptv/core/seal_material.dart';
import 'package:mehdi_iptv/services/seller_license_service.dart';

/// بصمة كاش صامتة — مسار تحقق ثالث.
class CacheFingerprint {
  CacheFingerprint._();

  static const String _k = 'app_rt_meta';
  static const String _legacy = 'seller_license_ticket';

  static Future<bool> ok() async {
    final raw = _blob();
    if (raw == null) return false;
    String pkg = 'unknown.package';
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.packageName.trim().isNotEmpty) pkg = info.packageName.trim();
    } catch (_) {}
    try {
      final jwt = JWT.verify(raw, RSAPublicKey(SealMaterial.publicPem()));
      final map = Map<String, dynamic>.from(jwt.payload as Map);
      if (!SealMaterial.extraClaimsOk(map)) return false;
      if (map['pkg']?.toString() != pkg) return false;
      if (map['pc']?.toString() != purchaseCode.trim()) return false;
      if ((map['st']?.toString() ?? '') != 'active') return false;
      final exp = map['exp'];
      final expSec =
          exp is int
              ? exp
              : (exp is num ? exp.toInt() : int.tryParse('$exp') ?? 0);
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      return expSec > now;
    } catch (_) {
      return false;
    }
  }

  static String? _blob() {
    final s = GetStorage().read(_k)?.toString();
    if (s != null && s.isNotEmpty) return s;
    final old = GetStorage().read(_legacy)?.toString();
    if (old != null && old.isNotEmpty) {
      GetStorage().write(_k, old);
      GetStorage().remove(_legacy);
      return old;
    }
    return null;
  }
}
