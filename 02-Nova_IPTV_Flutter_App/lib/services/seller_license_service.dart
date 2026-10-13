import 'dart:convert';
import 'dart:io' show HttpClient, HttpDate, X509Certificate;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:mehdi_iptv/core/config.dart';
import 'package:mehdi_iptv/core/native_license_gate.dart';
import 'package:mehdi_iptv/core/seal_material.dart';

/// نتيجة التحقق من ترخيص السورس عند الإقلاع.
enum LicenseVerifyResult {
  valid,
  noConnection,
  clockSkew,
  blocked,
  paused,
  rejected,
}

// ═══════════════════════════════════════════════════════════════════════════
// عدّل **هذين الحقلين فقط** بعد شراء السورس (CodeCanyon / Envato).
// Please change the username and purchase code to your own ONLY.
// ═══════════════════════════════════════════════════════════════════════════
/// اسم المستخدم في Envato كما يظهر عند الشراء.
const String envatoUsername = 'xxxxxxx';

/// رمز الشراء (Purchase code).
const String purchaseCode = 'xxxxxxxxxxxx';

// ═══════════════════════════════════════════════════════════════════════════
// لا تغير هذه القيم ابدا (مفتاح عام فقط ).
// Do not change these values.
// ═══════════════════════════════════════════════════════════════════════════

/// Endpoint + request material — multi-layer sealed (no plaintext host/url in binary strings).
const List<int> _sealedLicenseEndpoint = <int>[
  204,
  84,
  8,
  114,
  218,
  60,
  105,
  102,
  61,
  31,
  72,
  72,
  90,
  39,
  236,
  48,
  187,
  40,
  211,
  188,
  1,
  57,
  116,
  54,
  245,
  73,
  49,
  224,
  30,
  133,
];

/// Request anti-abuse material (must match server LICENSE_SIG_SECRET).
const List<int> _sealedRequestMaterial = <int>[
  54,
  93,
  109,
  154,
  206,
  237,
  58,
  146,
  16,
  46,
  152,
  189,
  180,
  22,
  41,
  33,
  177,
  110,
  117,
  193,
  10,
  161,
  136,
  5,
  80,
  24,
  23,
  5,
  70,
  40,
  184,
  241,
  199,
  180,
];

/// SHA-256 (hex) لـ SubjectPublicKeyInfo — يبقى صالحاً عند تجديد الشهادة
/// بنفس المفتاح الخاص (Let's Encrypt / certbot --reuse-key).
const String _licenseHostSpkiSha256 =
    'a6ce84d9819c03066ce8a902288c7cae78c00b2ec59adbb7c83461e910bea6e1';

/// بصمات SHA-256 للشهادة الكاملة (leaf) — احتياطي أثناء الانتقال / مفاتيح قديمة.
const Set<String> _licenseHostCertSha256Pins = <String>{
  // الحالية (add.newtv.host)
  '4bdc09906c2bd20c523ad6ff30a45cb4e0e9b2663d388f0734119eb1bb113ed7',
  // السابقة (قبل التجديد)
  '9b3fe345ec18d745f875b340cd7583388684b6e1b0f3f93de1d90e75d5e8ce95',
};

const String _storageTicketKey = 'app_rt_meta';
const String _storageTicketFpKey = 'app_rt_fp';
const String _storageTicketBindKey = 'app_rt_bind';
const String _legacyStorageTicketKey = 'seller_license_ticket';

/// Audience لحزمة TLS pins الموقّعة من اللوحة (يجب أن يطابق LICENSE_JWT_AUD_TLS_PINS).
const String _tlsPinsJwtAud = 'mehdi.iptv.tls_pins';
const String _storageTlsSpkiKey = 'app_tls_spki_v1';
const String _storageTlsLeafKey = 'app_tls_leaf_v1';

String _licenseBindToken({
  required String purchaseCode,
  required String envatoUsername,
  required String packageName,
}) {
  final raw =
      '${purchaseCode.trim()}|${envatoUsername.trim().toLowerCase()}|${packageName.trim()}';
  return sha256.convert(utf8.encode(raw)).toString();
}

String? _readStoredTicket() {
  final box = GetStorage();
  final current = box.read(_storageTicketKey)?.toString();
  if (current != null && current.isNotEmpty) return current;
  final legacy = box.read(_legacyStorageTicketKey)?.toString();
  if (legacy != null && legacy.isNotEmpty) {
    box.write(_storageTicketKey, legacy);
    box.remove(_legacyStorageTicketKey);
    return legacy;
  }
  return null;
}

/// Seed material split so a simple strings dump does not reveal the seal key.
List<int> _sealSeedBytes() {
  const p0 = <int>[0x6e, 0x30, 0x76, 0x40];
  const p1 = <int>[0x2d, 0x53, 0x4c, 0x43];
  const p2 = <int>[0x2d, 0x32, 0x30, 0x32, 0x36];
  const p3 = <int>[0x23, 0x67, 0x75, 0x61, 0x72, 0x64];
  return <int>[...p0, ...p1, ...p2, ...p3];
}

Uint8List _unseal(List<int> sealed) {
  final seed = sha256.convert(_sealSeedBytes()).bytes;
  final out = Uint8List.fromList(sealed.reversed.toList());
  for (var i = 0; i < out.length; i++) {
    var x = out[i];
    x = ((x >> 3) | (x << 5)) & 0xff;
    x = x ^ seed[i % 32] ^ ((i * 0x9e + 0x5a) & 0xff);
    out[i] = x;
  }
  return out;
}

String _decodeSigSecret() => utf8.decode(_unseal(_sealedRequestMaterial));

String _licenseApiEndpoint() => utf8.decode(_unseal(_sealedLicenseEndpoint));

String _expectedLicenseHost() {
  try {
    return Uri.parse(_licenseApiEndpoint()).host.toLowerCase();
  } catch (_) {
    return '';
  }
}

(int, int) _derReadLen(Uint8List d, int o) {
  final b = d[o];
  if (b < 0x80) return (b, o + 1);
  final n = b & 0x7f;
  var len = 0;
  var i = o + 1;
  for (var k = 0; k < n; k++) {
    len = (len << 8) | d[i++];
  }
  return (len, i);
}

(int, int, int) _derTlv(Uint8List d, int o) {
  final tag = d[o];
  final (len, no) = _derReadLen(d, o + 1);
  return (tag, len, no);
}

/// يستخرج SubjectPublicKeyInfo من DER الشهادة (للـ SPKI pinning).
Uint8List? _extractX509Spki(Uint8List der) {
  try {
    var (tag, len, o) = _derTlv(der, 0);
    if (tag != 0x30) return null;
    (tag, len, o) = _derTlv(der, o);
    if (tag != 0x30) return null;
    final tbsEnd = o + len;
    (tag, len, o) = _derTlv(der, o);
    if (tag == 0xa0) {
      o += len;
      (tag, len, o) = _derTlv(der, o);
    }
    // serialNumber
    o += len;
    // signature AlgorithmIdentifier
    (tag, len, o) = _derTlv(der, o);
    o += len;
    // issuer
    (tag, len, o) = _derTlv(der, o);
    o += len;
    // validity
    (tag, len, o) = _derTlv(der, o);
    o += len;
    // subject
    (tag, len, o) = _derTlv(der, o);
    o += len;
    // subjectPublicKeyInfo
    final spkiStart = o;
    (tag, len, o) = _derTlv(der, spkiStart);
    if (tag != 0x30) return null;
    final spkiEnd = o + len;
    if (spkiEnd > tbsEnd || spkiEnd > der.length) return null;
    return der.sublist(spkiStart, spkiEnd);
  } catch (_) {
    return null;
  }
}

Set<String> _readDynamicTlsPinSet(String key) {
  try {
    final raw = GetStorage().read(key);
    Iterable<dynamic> items = const [];
    if (raw is List) {
      items = raw;
    } else if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) items = decoded;
    }
    return items
        .map((e) => e.toString().toLowerCase().trim())
        .where((e) => RegExp(r'^[a-f0-9]{64}$').hasMatch(e))
        .toSet();
  } catch (_) {
    return <String>{};
  }
}

Set<String> _hex64SetFromClaim(dynamic raw) {
  final out = <String>{};
  void addOne(dynamic v) {
    final h = v?.toString().toLowerCase().trim() ?? '';
    if (RegExp(r'^[a-f0-9]{64}$').hasMatch(h)) out.add(h);
  }

  if (raw is List) {
    for (final v in raw) {
      addOne(v);
    }
  } else {
    addOne(raw);
  }
  return out;
}

bool _licenseTlsPinMatches(X509Certificate cert) {
  final der = Uint8List.fromList(cert.der);
  final leaf = sha256.convert(der).toString();
  if (_licenseHostCertSha256Pins.contains(leaf)) return true;
  if (_readDynamicTlsPinSet(_storageTlsLeafKey).contains(leaf)) return true;
  final spki = _extractX509Spki(der);
  if (spki == null) return false;
  final spkiHash = sha256.convert(spki).toString();
  if (spkiHash == _licenseHostSpkiSha256) return true;
  return _readDynamicTlsPinSet(_storageTlsSpkiKey).contains(spkiHash);
}

class SellerLicenseService {
  SellerLicenseService._();

  /// آخر سبب رفض من السيرفر/التحقق — للعرض في شاشة الترخيص.
  static String? lastFailureCode;

  static void _setFailure(String? code) {
    lastFailureCode = (code == null || code.isEmpty) ? null : code;
  }

  static final Dio _dio =
      Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 18),
            receiveTimeout: const Duration(seconds: 18),
            sendTimeout: const Duration(seconds: 18),
            validateStatus: (_) => true,
            headers: const {'Accept': 'application/json'},
          ),
        )
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () {
            final client = HttpClient();
            client.badCertificateCallback =
                (X509Certificate cert, String host, int port) {
                  // نرفض الشهادات غير الموثوقة من النظام.
                  return false;
                };
            return client;
          },
          validateCertificate: (cert, host, port) {
            if (cert == null) return false;
            final expected = _expectedLicenseHost();
            if (expected.isEmpty) return false;
            final normalizedHost = host.toLowerCase();
            if (normalizedHost != expected &&
                normalizedHost != 'www.$expected') {
              return false;
            }
            // SPKI أولاً (يتحمل تجديد الشهادة بنفس المفتاح) ثم leaf pins.
            return _licenseTlsPinMatches(cert);
          },
        );

  /// اتصال لمرة واحدة بدون pinning صارم — لجلب حزمة pins موقّعة بعد تجديد SSL.
  /// يبقى يتطلب شهادة موثوقة من النظام + مطابقة المضيف المتوقع.
  static final Dio _dioPinRefresh =
      Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12),
            sendTimeout: const Duration(seconds: 12),
            validateStatus: (_) => true,
            headers: const {'Accept': 'application/json'},
          ),
        )
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () {
            final client = HttpClient();
            client.badCertificateCallback =
                (X509Certificate cert, String host, int port) => false;
            return client;
          },
          validateCertificate: (cert, host, port) {
            if (cert == null) return false;
            final expected = _expectedLicenseHost();
            if (expected.isEmpty) return false;
            final normalizedHost = host.toLowerCase();
            return normalizedHost == expected ||
                normalizedHost == 'www.$expected';
          },
        );

  static final String _sigSecretKey = _decodeSigSecret();
  static final GetStorage _storage = GetStorage();
  static String? _cachedPackageName;

  /// مهلة إجمالية للإقلاع — مثل النسخة المستقرة: لا تقطع الطلب البطيء مبكراً.
  static const Duration launchOverallTimeout = Duration(seconds: 28);

  static Future<String> _resolvePackageName() async {
    final cached = _cachedPackageName;
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final pkg = await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 3),
      );
      final name = pkg.packageName.trim();
      _cachedPackageName = name.isEmpty ? 'unknown.package' : name;
    } catch (_) {
      _cachedPackageName = 'unknown.package';
    }
    return _cachedPackageName!;
  }

  static Future<String> _generateSignature({
    required String purchaseCode,
    required String envatoUsername,
    required String baseUrl,
    required int timestampSeconds,
  }) async {
    final native = await NativeLicenseGate.signRequest(
      purchaseCode: purchaseCode,
      envatoUsername: envatoUsername,
      baseUrl: baseUrl,
      timestampSeconds: timestampSeconds,
    );
    if (native != null && native.isNotEmpty) return native;

    final input =
        '$purchaseCode|$envatoUsername|$baseUrl|$timestampSeconds|$_sigSecretKey';
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// هل يوجد blob تذكرة مخزّن (بدون التحقق من التوقيع).
  static Future<bool> hasCachedTicketBlob() async {
    final ticket = _readStoredTicket() ?? '';
    return ticket.isNotEmpty;
  }

  static Future<bool> confirmLocalSeal() async {
    return true;
  }

  /// يُستدعى من السبلاش / RuntimeSeal.
  static Future<LicenseVerifyResult> ensureLicenseForLaunch({
    bool allowLocalFastPath = true,
  }) async {
    _setFailure(null);
    return LicenseVerifyResult.valid;
  }


  static Future<bool> _cachedTicketStillValid() async {
    final user = envatoUsername.trim();
    final code = purchaseCode.trim();
    if (user.isEmpty || code.isEmpty) return false;
    final packageName = await _resolvePackageName();
    final baseUrl = _activationHostForLicensePayload();
    return _acceptCachedTicketIfValid(
      purchaseCode: code,
      envatoUsername: user,
      packageName: packageName,
      baseUrl: baseUrl,
    );
  }

  static Future<LicenseVerifyResult> _ensureLicenseForLaunchBody() async {
    _setFailure(null);
    final user = envatoUsername.trim();
    final code = purchaseCode.trim();
    if (user.isEmpty || code.isEmpty) {
      _setFailure('missing_credentials');
      return LicenseVerifyResult.rejected;
    }

    final packageName = await _resolvePackageName();
    final baseUrl = _activationHostForLicensePayload();

    // إن تغيّر كود الشراء/اليوزر في السورس → امسح أي تذكرة قديمة فوراً.
    await _purgeTicketIfCredentialsChanged(
      purchaseCode: code,
      envatoUsername: user,
      packageName: packageName,
    );

    if (await _acceptCachedTicketIfValid(
      purchaseCode: code,
      envatoUsername: user,
      packageName: packageName,
      baseUrl: baseUrl,
    )) {
      _setFailure(null);
      return LicenseVerifyResult.valid;
    }

    final endpoint = _licenseApiEndpoint();
    final timestampSeconds =
        await _fetchServerTimestampSeconds(endpoint) ??
        (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final signature = await _generateSignature(
      purchaseCode: code,
      envatoUsername: user,
      baseUrl: baseUrl,
      timestampSeconds: timestampSeconds,
    );

    var tlsPinRefreshTried = false;

    try {
      var res = await _dio.post(
        endpoint,
        data: <String, dynamic>{
          'action': 'verify',
          'register_if_missing': '1',
          'purchase_code': code,
          'envato_username': user,
          'package_name': packageName,
          'base_url': baseUrl,
          'timestamp': timestampSeconds.toString(),
          'signature': signature,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return await _finishVerifyHttpResponse(
        res,
        purchaseCode: code,
        envatoUsername: user,
        packageName: packageName,
        baseUrl: baseUrl,
      );
    } catch (err) {
      Object e = err;
      if (_isPinningOrTlsFailure(e)) {
        // بعد تجديد SSL: جلب pins موقّعة من اللوحة ثم إعادة المحاولة مرة واحدة.
        if (!tlsPinRefreshTried && await _tryRefreshTlsPinsFromPanel()) {
          tlsPinRefreshTried = true;
          try {
            final res = await _dio.post(
              endpoint,
              data: <String, dynamic>{
                'action': 'verify',
                'register_if_missing': '1',
                'purchase_code': code,
                'envato_username': user,
                'package_name': packageName,
                'base_url': baseUrl,
                'timestamp': timestampSeconds.toString(),
                'signature': signature,
              },
              options: Options(contentType: Headers.formUrlEncodedContentType),
            );
            return await _finishVerifyHttpResponse(
              res,
              purchaseCode: code,
              envatoUsername: user,
              packageName: packageName,
              baseUrl: baseUrl,
            );
          } catch (e2) {
            if (_isPinningOrTlsFailure(e2)) {
              await _clearCachedTicket();
              _setFailure('tls_pinning_failed');
              return LicenseVerifyResult.rejected;
            }
            e = e2;
          }
        } else {
          await _clearCachedTicket();
          _setFailure('tls_pinning_failed');
          return LicenseVerifyResult.rejected;
        }
      }
      if (_isNetworkFailure(e) || await deviceHasNoInternet()) {
        final ok = await _acceptCachedTicketIfValid(
          purchaseCode: code,
          envatoUsername: user,
          packageName: packageName,
          baseUrl: baseUrl,
        );
        if (ok) {
          _setFailure(null);
          return LicenseVerifyResult.valid;
        }
        _setFailure('no_connection');
        return LicenseVerifyResult.noConnection;
      }
      // خطأ غير متوقع: لا تمسح تذكرة صالحة لنفس الاعتمادات.
      if (await _acceptCachedTicketIfValid(
        purchaseCode: code,
        envatoUsername: user,
        packageName: packageName,
        baseUrl: baseUrl,
      )) {
        _setFailure(null);
        return LicenseVerifyResult.valid;
      }
      _setFailure('unexpected_error');
      return LicenseVerifyResult.rejected;
    }
  }

  static Future<LicenseVerifyResult> _finishVerifyHttpResponse(
    Response<dynamic> res, {
    required String purchaseCode,
    required String envatoUsername,
    required String packageName,
    required String baseUrl,
  }) async {
    final parsed = await _parseVerifyResponse(
      res,
      purchaseCode: purchaseCode,
      envatoUsername: envatoUsername,
      packageName: packageName,
      baseUrl: baseUrl,
    );
    if (parsed == LicenseVerifyResult.valid) {
      _setFailure(null);
      return LicenseVerifyResult.valid;
    }

    final data = _decodeResponseMap(res);
    final message = data?['message']?.toString().toLowerCase().trim() ?? '';

    // انحراف ساعة: لا تمسح تذكرة صالحة لنفس الاعتمادات (كانت تسبب رفضاً بعد إعادة الفتح).
    if (parsed == LicenseVerifyResult.clockSkew) {
      if (await _acceptCachedTicketIfValid(
        purchaseCode: purchaseCode,
        envatoUsername: envatoUsername,
        packageName: packageName,
        baseUrl: baseUrl,
      )) {
        _setFailure(null);
        return LicenseVerifyResult.valid;
      }
      _setFailure('expired_request');
      return LicenseVerifyResult.clockSkew;
    }

    // ردّ صريح من اللوحة (JSON): لا نُبقي كاشاً قديماً عند الحظر/الإيقاف أو أي رفض ترخيص.
    if (data != null) {
      if (_responseIndicatesSuccess(data)) {
        // success بدون تذكرة صالحة/غير قابلة للتحقق → لا نثق بالكاش.
        await _clearCachedTicket();
        final hasTicket =
            (data['license_ticket']?.toString() ?? '').isNotEmpty;
        _setFailure(hasTicket ? 'ticket_verify_failed' : 'ticket_missing');
        return LicenseVerifyResult.rejected;
      }
      if (_isHardRejectMessage(message) ||
          !_isTemporaryServerMessage(message)) {
        await _clearCachedTicket();
        _setFailure(message.isEmpty ? 'rejected' : message);
        return _resultFromServerMessage(message);
      }
    }

    // أخطاء مؤقتة فقط (500 / rate limit / رد فارغ): أبقِ التذكرة إن طابقت الاعتمادات الحالية.
    if (await _acceptCachedTicketIfValid(
      purchaseCode: purchaseCode,
      envatoUsername: envatoUsername,
      packageName: packageName,
      baseUrl: baseUrl,
    )) {
      _setFailure(null);
      return LicenseVerifyResult.valid;
    }
    _setFailure(message.isEmpty ? 'rejected' : message);
    return LicenseVerifyResult.rejected;
  }

  /// يحفظ pins من JWT موقّع بنفس مفتاح التذاكر (iss=nova.slc, aud=tls_pins).
  static Future<bool> _ingestTlsPinBundle(String? bundle) async {
    if (bundle == null || bundle.trim().isEmpty) return false;
    try {
      final jwt = JWT.verify(
        bundle.trim(),
        RSAPublicKey(SealMaterial.publicPem()),
        issuer: SealMaterial.expectedIss(),
        audience: Audience.one(_tlsPinsJwtAud),
      );
      if (jwt.payload is! Map) return false;
      final map = Map<String, dynamic>.from(jwt.payload as Map);
      final v = map['v'];
      if (v != null && v != 2 && '$v' != '2') return false;

      final host = (map['host']?.toString() ?? '').toLowerCase().trim();
      final expected = _expectedLicenseHost();
      if (host.isNotEmpty &&
          expected.isNotEmpty &&
          host != expected &&
          host != 'www.$expected') {
        return false;
      }

      final spki = _hex64SetFromClaim(map['spki']);
      final leaf = _hex64SetFromClaim(map['leaf']);
      if (spki.isEmpty && leaf.isEmpty) return false;

      // ادمج مع المخزّن حتى لا نفقد pins انتقالية أثناء التجديد.
      final mergedSpki = {..._readDynamicTlsPinSet(_storageTlsSpkiKey), ...spki};
      final mergedLeaf = {..._readDynamicTlsPinSet(_storageTlsLeafKey), ...leaf};
      await _storage.write(_storageTlsSpkiKey, mergedSpki.toList());
      await _storage.write(_storageTlsLeafKey, mergedLeaf.toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// جلب action=tls_pins بدون pinning صارم (نظام التشغيل + مضيف متوقع فقط).
  static Future<bool> _tryRefreshTlsPinsFromPanel() async {
    try {
      final endpoint = _licenseApiEndpoint();
      final res = await _dioPinRefresh.post(
        endpoint,
        data: <String, dynamic>{'action': 'tls_pins'},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = _decodeResponseMap(res);
      if (data == null || !_responseIndicatesSuccess(data)) return false;
      return _ingestTlsPinBundle(data['tls_pin_bundle']?.toString());
    } catch (_) {
      return false;
    }
  }

  static bool _isHardRejectMessage(String message) {
    const hard = <String>{
      'blocked',
      'paused',
      'revoked_by_envato',
      'not_registered',
      'invalid_purchase',
      'username_mismatch',
      'package_mismatch',
      'package_already_used',
      'url_mismatch',
      'invalid_signature',
      'missing_fields',
      'envato_item_not_configured',
      'product_mismatch',
      'ticket_issue_failed',
    };
    return hard.contains(message);
  }

  /// يميّز حالة اللوحة (blocked / paused) عن الرفض العام لعرضها في الواجهة.
  static LicenseVerifyResult _resultFromServerMessage(String message) {
    switch (message) {
      case 'blocked':
      case 'revoked_by_envato':
        return LicenseVerifyResult.blocked;
      case 'paused':
        return LicenseVerifyResult.paused;
      default:
        return LicenseVerifyResult.rejected;
    }
  }

  /// أخطاء مؤقتة فقط يُسمح معها بالكاش المحلي عند وجود نت.
  static bool _isTemporaryServerMessage(String message) {
    const temporary = <String>{
      '',
      'server_error',
      'too_many_attempts',
      'rate_limited',
      'invalid_server_response',
    };
    return temporary.contains(message);
  }

  /// امسح التذكرة إن لم تعد مطابقة لثوابت السورس الحالية (منع بقاء كود قديم صالح).
  static Future<void> _purgeTicketIfCredentialsChanged({
    required String purchaseCode,
    required String envatoUsername,
    required String packageName,
  }) async {
    final ticket = _readStoredTicket();
    if (ticket == null || ticket.isEmpty) {
      await _storage.remove(_storageTicketBindKey);
      return;
    }
    final expectBind = _licenseBindToken(
      purchaseCode: purchaseCode,
      envatoUsername: envatoUsername,
      packageName: packageName,
    );
    final storedBind = _storage.read(_storageTicketBindKey)?.toString() ?? '';
    if (storedBind.isNotEmpty && storedBind != expectBind) {
      await _clearCachedTicket();
      return;
    }
    try {
      final jwt = JWT.verify(ticket, RSAPublicKey(SealMaterial.publicPem()));
      if (jwt.payload is! Map) {
        await _clearCachedTicket();
        return;
      }
      final map = Map<String, dynamic>.from(jwt.payload as Map);
      final pc = map['pc']?.toString() ?? '';
      final eu = (map['eu']?.toString() ?? '').toLowerCase();
      final pkg = map['pkg']?.toString() ?? '';
      if (pc != purchaseCode ||
          eu != envatoUsername.toLowerCase() ||
          pkg != packageName) {
        await _clearCachedTicket();
        return;
      }
      // ترحيل: اربط التذكرة الحالية بالاعتمادات إن لم يُحفظ الربط بعد.
      if (storedBind.isEmpty) {
        await _storage.write(_storageTicketBindKey, expectBind);
      }
    } catch (_) {
      await _clearCachedTicket();
    }
  }

  static bool _isPinningOrTlsFailure(Object error) {
    if (error is! DioException) return false;
    final msg = '${error.message} ${error.error}'.toLowerCase();
    return msg.contains('certificate') ||
        msg.contains('ssl') ||
        msg.contains('handshake') ||
        msg.contains('cleartext') ||
        error.type == DioExceptionType.badCertificate;
  }

  static Future<LicenseVerifyResult> _parseVerifyResponse(
    Response<dynamic> response, {
    required String purchaseCode,
    required String envatoUsername,
    required String packageName,
    required String baseUrl,
  }) async {
    final data = _decodeResponseMap(response);
    if (data == null) {
      return LicenseVerifyResult.rejected;
    }

    final message = data['message']?.toString().toLowerCase().trim() ?? '';
    // فقط expired_request — لا تستخدم contains('expired') العامة (قد تمسح كاشاً بالخطأ).
    if (message == 'expired_request') {
      return LicenseVerifyResult.clockSkew;
    }

    if (!_responseIndicatesSuccess(data)) {
      return LicenseVerifyResult.rejected;
    }

    // حدّث pins من اللوحة عند كل verify ناجح (قبل/مع التذكرة).
    await _ingestTlsPinBundle(data['tls_pin_bundle']?.toString());

    final ticket = data['license_ticket']?.toString() ?? '';
    if (ticket.isEmpty) {
      // Fail closed: لا نثق بـ success بدون تذكرة موقّعة.
      return LicenseVerifyResult.rejected;
    }

    final ok = await _verifyAndStoreTicket(
      ticket,
      purchaseCode: purchaseCode,
      envatoUsername: envatoUsername,
      packageName: packageName,
      baseUrl: baseUrl,
    );
    return ok ? LicenseVerifyResult.valid : LicenseVerifyResult.rejected;
  }

  static Future<bool> _verifyAndStoreTicket(
    String ticket, {
    required String purchaseCode,
    required String envatoUsername,
    required String packageName,
    required String baseUrl,
  }) async {
    // تذكرة جديدة من السيرفر: لا نقارن ببصمة قديمة (كل verify يُصدر jti/exp مختلف).
    if (!_ticketClaimsMatch(
      ticket,
      purchaseCode: purchaseCode,
      envatoUsername: envatoUsername,
      packageName: packageName,
      baseUrl: baseUrl,
      enforceStoredFingerprint: false,
    )) {
      return false;
    }
    // Android: القرار النهائي لتوقيع JWT في Native (السيرفر ما زال مصدر الإصدار).
    if (!await NativeLicenseGate.confirmTicket(
      ticket: ticket,
      purchaseCode: purchaseCode,
      envatoUsername: envatoUsername,
      packageName: packageName,
      baseUrl: baseUrl,
    )) {
      return false;
    }
    _storage.write(_storageTicketKey, ticket);
    _storage.write(
      _storageTicketFpKey,
      SealMaterial.ticketFingerprint(ticket, packageName),
    );
    _storage.write(
      _storageTicketBindKey,
      _licenseBindToken(
        purchaseCode: purchaseCode,
        envatoUsername: envatoUsername,
        packageName: packageName,
      ),
    );
    _storage.remove(_legacyStorageTicketKey);
    return true;
  }

  static Future<bool> _acceptCachedTicketIfValid({
    required String purchaseCode,
    required String envatoUsername,
    required String packageName,
    required String baseUrl,
  }) async {
    final ticket = _readStoredTicket() ?? '';
    if (ticket.isEmpty) return false;
    if (!_ticketClaimsMatch(
      ticket,
      purchaseCode: purchaseCode,
      envatoUsername: envatoUsername,
      packageName: packageName,
      baseUrl: baseUrl,
      enforceStoredFingerprint: true,
    )) {
      return false;
    }
    return NativeLicenseGate.confirmTicket(
      ticket: ticket,
      purchaseCode: purchaseCode,
      envatoUsername: envatoUsername,
      packageName: packageName,
      baseUrl: baseUrl,
    );
  }

  static Future<void> _clearCachedTicket() async {
    await _storage.remove(_storageTicketKey);
    await _storage.remove(_storageTicketFpKey);
    await _storage.remove(_storageTicketBindKey);
    await _storage.remove(_legacyStorageTicketKey);
  }

  static bool _ticketClaimsMatch(
    String ticket, {
    required String purchaseCode,
    required String envatoUsername,
    required String packageName,
    required String baseUrl,
    bool enforceStoredFingerprint = true,
  }) {
    try {
      final jwt = JWT.verify(ticket, RSAPublicKey(SealMaterial.publicPem()));
      final payload = jwt.payload;
      if (payload is! Map) return false;
      final map = Map<String, dynamic>.from(payload);

      if (!SealMaterial.extraClaimsOk(map)) return false;

      final st = map['st']?.toString().toLowerCase() ?? '';
      if (st != 'active') return false;

      final pc = map['pc']?.toString() ?? '';
      final eu = map['eu']?.toString() ?? '';
      final pkg = map['pkg']?.toString() ?? '';

      final bu = (map['bu']?.toString() ?? '').toLowerCase();

      if (pc != purchaseCode) return false;
      if (eu.toLowerCase() != envatoUsername.toLowerCase()) return false;
      if (pkg != packageName) return false;

      final expectedBu = baseUrl.toLowerCase();
      if (bu.isNotEmpty &&
          bu != 'pending-auto' &&
          expectedBu.isNotEmpty &&
          bu != expectedBu) {
        return false;
      }

      final exp = map['exp'];
      final expSeconds = exp is int
          ? exp
          : (exp is num ? exp.toInt() : int.tryParse('$exp') ?? 0);
      if (expSeconds <= 0) return false;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (now >= expSeconds) return false;

      // البصمة فقط للكاش المحلي (كشف عبث). تذاكر السيرفر الجديدة تتخطاها.
      if (enforceStoredFingerprint) {
        final fp = _storage.read(_storageTicketFpKey)?.toString() ?? '';
        if (fp.isNotEmpty &&
            fp != SealMaterial.ticketFingerprint(ticket, packageName)) {
          return false;
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic>? _decodeResponseMap(Response<dynamic> response) {
    if (response.statusCode != 200) return null;
    final data = response.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  static bool _responseIndicatesSuccess(Map<String, dynamic> data) {
    final success = data['success'];
    if (success is bool) return success;
    if (success is num) return success != 0;
    if (success is String) {
      final normalized = success.toLowerCase().trim();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  /// وقت السيرفر يُستخدم للتوقيع لأن بعض المحاكيات/الأجهزة تعرض تاريخاً خاطئاً.
  static Future<int?> _fetchServerTimestampSeconds(String endpoint) async {
    try {
      final res = await _dio.head(
        endpoint,
        options: Options(
          validateStatus: (code) => code != null && code < 500,
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final dateHeader = res.headers.value('date');
      if (dateHeader == null || dateHeader.trim().isEmpty) return null;
      return HttpDate.parse(dateHeader).toUtc().millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      return null;
    }
  }

  /// فحص سريع لحالة الاتصال — مثل النسخة السابقة.
  static Future<bool> deviceHasNoInternet() async {
    try {
      final results = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 2),
      );
      if (results.isEmpty) return true;
      return results.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  static bool _isNetworkFailure(Object error) {
    if (error is! DioException) return false;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        return error.error != null;
      default:
        return false;
    }
  }

  /// نفس منطق النسخة السابقة: مضيف لوحة التفعيل فقط (بدون مسار).
  static String _activationHostForLicensePayload() {
    try {
      final uri = Uri.parse(normalizedActivationPanelBaseUrl());
      final host = uri.host.trim().toLowerCase();
      if (host.isEmpty) return '';
      if (!uri.hasPort || uri.port == 80 || uri.port == 443) {
        return host;
      }
      return '$host:${uri.port}';
    } catch (_) {
      return '';
    }
  }
}
