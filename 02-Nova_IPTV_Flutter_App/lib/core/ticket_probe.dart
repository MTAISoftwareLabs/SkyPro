import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:mehdi_iptv/core/config.dart';
import 'package:mehdi_iptv/core/native_license_gate.dart';
import 'package:mehdi_iptv/core/seal_material.dart';
import 'package:mehdi_iptv/services/seller_license_service.dart';

/// مسار تحقق ثانٍ منفصل عن [SellerLicenseService.confirmLocalSeal].
class TicketProbe {
  TicketProbe._();

  static const String _blobKey = 'app_rt_meta';
  static const String _legacyKey = 'seller_license_ticket';

  static Future<bool> matchesEmbeddedClaims() async {
    final ticket = _readBlob();
    if (ticket == null) return false;

    String packageName = 'unknown.package';
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (pkg.packageName.trim().isNotEmpty) {
        packageName = pkg.packageName.trim();
      }
    } catch (_) {}

    final host = _panelHost();
    try {
      final jwt = JWT.verify(ticket, RSAPublicKey(SealMaterial.publicPem()));
      final payload = jwt.payload;
      if (payload is! Map) return false;
      final map = Map<String, dynamic>.from(payload);
      if (!SealMaterial.extraClaimsOk(map)) return false;
      if ((map['st']?.toString().toLowerCase() ?? '') != 'active') {
        return false;
      }
      if (map['pc']?.toString() != purchaseCode.trim()) return false;
      if ((map['eu']?.toString() ?? '').toLowerCase() !=
          envatoUsername.trim().toLowerCase()) {
        return false;
      }
      if (map['pkg']?.toString() != packageName) return false;
      final bu = (map['bu']?.toString() ?? '').toLowerCase();
      if (bu.isNotEmpty &&
          bu != 'pending-auto' &&
          host.isNotEmpty &&
          bu != host) {
        return false;
      }
      final exp = map['exp'];
      final expSeconds =
          exp is int
              ? exp
              : (exp is num ? exp.toInt() : int.tryParse('$exp') ?? 0);
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (expSeconds <= now) return false;
    } catch (_) {
      return false;
    }

    return NativeLicenseGate.confirmTicket(
      ticket: ticket,
      purchaseCode: purchaseCode.trim(),
      envatoUsername: envatoUsername.trim(),
      packageName: packageName,
      baseUrl: host,
    );
  }

  static String? _readBlob() {
    final box = GetStorage();
    final s = box.read(_blobKey)?.toString();
    if (s != null && s.isNotEmpty) return s;
    final old = box.read(_legacyKey)?.toString();
    if (old != null && old.isNotEmpty) {
      box.write(_blobKey, old);
      box.remove(_legacyKey);
      return old;
    }
    return null;
  }

  static String _panelHost() {
    try {
      final uri = Uri.parse(kActivationPanelBaseUrl);
      final h = uri.host.trim().toLowerCase();
      if (h.isEmpty) return '';
      if (!uri.hasPort || uri.port == 80 || uri.port == 443) return h;
      return '$h:${uri.port}';
    } catch (_) {
      return '';
    }
  }
}
