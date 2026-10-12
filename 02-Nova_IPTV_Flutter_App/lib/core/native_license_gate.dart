import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// جسر Android الأصلي لقرار قبول التذكرة محلياً وتوقيع طلب التحقق.
/// السيرفر يبقى مصدر الحقيقة؛ هذه الطبقة ترفع تكلفة تجاوز التحقق من Dart فقط.
class NativeLicenseGate {
  NativeLicenseGate._();

  static const MethodChannel _channel = MethodChannel('nova.iptv.license_gate');

  static bool get _isAndroidNative => !kIsWeb && Platform.isAndroid;

  /// على Android: يجب أن يؤكد Native التوقيع والمطالبات. غير ذلك: Dart يكفي.
  static Future<bool> confirmTicket({
    required String ticket,
    required String purchaseCode,
    required String envatoUsername,
    required String packageName,
    required String baseUrl,
  }) async {
    if (!_isAndroidNative) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('confirmTicket', <String, dynamic>{
        'ticket': ticket,
        'pc': purchaseCode,
        'eu': envatoUsername,
        'pkg': packageName,
        'bu': baseUrl,
      });
      return ok == true;
    } catch (_) {
      // Fail closed على Android إن تعطّل الجسر.
      return false;
    }
  }

  /// يفضّل توقيع الطلب من Native على Android؛ وإلا null ليعود Dart لمساره.
  static Future<String?> signRequest({
    required String purchaseCode,
    required String envatoUsername,
    required String baseUrl,
    required int timestampSeconds,
  }) async {
    if (!_isAndroidNative) return null;
    try {
      final sig = await _channel.invokeMethod<String>('signRequest', <String, dynamic>{
        'pc': purchaseCode,
        'eu': envatoUsername,
        'bu': baseUrl,
        'ts': timestampSeconds,
      });
      if (sig == null || sig.isEmpty) return null;
      return sig;
    } catch (_) {
      return null;
    }
  }
}
