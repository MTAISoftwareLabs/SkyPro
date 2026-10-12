import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:mehdi_iptv/core/seal_material.dart';
import 'package:mehdi_iptv/services/seller_license_service.dart';

/// عيّنة مقاييس صامتة — مسار تحقق رابع خفيف.
class MetricSampler {
  MetricSampler._();

  static const String _blobKey = 'app_rt_meta';
  static const String _fpKey = 'app_rt_fp';

  static Future<bool> sampleOk() async {
    final box = GetStorage();
    final ticket = box.read(_blobKey)?.toString() ?? '';
    if (ticket.isEmpty) return false;
    String pkg = 'unknown.package';
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.packageName.trim().isNotEmpty) {
        pkg = info.packageName.trim();
      }
    } catch (_) {}
    final expectFp = SealMaterial.ticketFingerprint(ticket, pkg);
    final storedFp = box.read(_fpKey)?.toString() ?? '';
    if (storedFp.isNotEmpty && storedFp != expectFp) {
      return false;
    }
    try {
      final jwt = JWT.verify(ticket, RSAPublicKey(SealMaterial.publicPem()));
      if (jwt.payload is! Map) return false;
      final map = Map<String, dynamic>.from(jwt.payload as Map);
      if (!SealMaterial.extraClaimsOk(map)) return false;
      if (map['pkg']?.toString() != pkg) return false;
      if (map['pc']?.toString() != purchaseCode.trim()) return false;
      if ((map['eu']?.toString() ?? '').toLowerCase() !=
          envatoUsername.trim().toLowerCase()) {
        return false;
      }
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
}
