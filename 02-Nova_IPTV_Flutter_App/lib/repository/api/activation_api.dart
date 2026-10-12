import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mehdi_iptv/core/config.dart';
import 'package:mehdi_iptv/helpers/helpers.dart';
import 'package:mehdi_iptv/services/activation_token_service.dart';
import 'package:mehdi_iptv/services/ads_service.dart';
import 'package:mehdi_iptv/services/device_hardware_fingerprint_service.dart';
import 'package:mehdi_iptv/services/device_mac_service.dart';
import 'package:mehdi_iptv/services/stable_device_id_service.dart';
import 'package:mehdi_iptv/services/now_watching_presence.dart';
import 'package:mehdi_iptv/services/notification_inbox_service.dart';

import '../locale/panel_api_keys.dart';
import '../locale/saved_accounts.dart';

const String _kDeviceApiTokenStorage = 'device_api_token';
const String _kBoundPanelHostStorage = 'activation_panel_host';
const String _kBoundPanelBaseStorage = 'activation_panel_base';

void _actLog(String msg) {
  debugPrint('[NovaActivation] $msg');
}

String _actSnippet(dynamic data) {
  var s = data == null ? '' : data.toString();
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  if (s.length > 500) s = '${s.substring(0, 500)}…';
  return s;
}

class PlaylistCodeRedeemResult {
  final bool ok;
  final String? m3uUrl;

  /// مفتاح ترجمة في `app_translations` عند الفشل
  final String? messageKey;

  PlaylistCodeRedeemResult({required this.ok, this.m3uUrl, this.messageKey});
}

class ActivationApi {
  final Dio _dio;

  /// Panel base URL: configure in `lib/core/config.dart` (`kActivationPanelBaseUrl`).
  static String get _pinnedHost =>
      Uri.parse(normalizedActivationPanelBaseUrl()).host;

  /// فرق الساعة: (UTC السيرفر) − (UTC الجهاز). يصلح محاكيات Android TV
  /// التي تظهر تاريخاً صحيحاً في الإعدادات لكن ساعة النظام تبقى منحرفة.
  static int? _serverClockOffsetSec;
  static DateTime? _serverClockSyncedAt;

  /// حفظ الحقول العامة من لوحة التحكم (تُستدعى بعد كل فحص ناجح).
  static Future<void> persistPanelMetadataFromResponse(
    Map<String, dynamic> raw,
  ) async {
    final box = GetStorage();
    await box.write(
      'activation_enforced',
      parseActivationEnforcedFlag(raw['activation_enforced']),
    );
    if (raw.containsKey('block_screenshots')) {
      await box.write(
        'block_screenshots',
        parseActivationEnforcedFlag(raw['block_screenshots']),
      );
    }
    await applyScreenshotProtection();
    await box.write(
      'privacy_policy_url',
      (raw['privacy_policy_url'] as String? ?? '').trim(),
    );
    await box.write(
      'privacy_policy_html',
      (raw['privacy_policy_html'] as String? ?? '').trim(),
    );
    final mode = (raw['privacy_policy_mode'] as String? ?? 'url').toLowerCase();
    await box.write('privacy_policy_mode', mode == 'html' ? 'html' : 'url');
    await box.write(
      'about_us_html',
      (raw['about_us_html'] as String? ?? '').trim(),
    );
    Future<void> keepUrl(String key, String value) async {
      final v = value.trim();
      if (v.isEmpty) return;
      await box.write(key, v);
    }

    await keepUrl(
      'support_contact_url',
      raw['support_contact_url'] as String? ?? '',
    );
    await keepUrl(
      'app_activation_url',
      raw['app_activation_url'] as String? ?? '',
    );
    await keepUrl('purchase_url', raw['purchase_url'] as String? ?? '');
    await keepUrl(
      kStorageDefaultServerUrl,
      raw['default_server_url'] as String? ?? '',
    );
    if (raw.containsKey('login_servers')) {
      final cleaned = <Map<String, String>>[];
      final serversRaw = raw['login_servers'];
      if (serversRaw is List) {
        for (final row in serversRaw) {
          if (row is! Map) continue;
          final name = (row['name'] ?? '').toString().trim();
          final url = (row['url'] ?? '').toString().trim();
          if (url.isEmpty) continue;
          cleaned.add({'name': name, 'url': url});
        }
      }
      await box.write(kStorageLoginServers, cleaned);
    }
    await box.write(
      'piracy_detection_enabled',
      raw['piracy_detection_enabled'] == true ||
          raw['piracy_detection_enabled'] == 1 ||
          raw['piracy_detection_enabled'] == '1',
    );
    await box.write(
      'piracy_packages',
      (raw['piracy_packages'] as String? ?? '').trim(),
    );
    await box.write(
      'piracy_message',
      (raw['piracy_message'] as String? ?? '').trim(),
    );
    if (raw.containsKey('onesignal_app_id')) {
      await box.write(
        'onesignal_app_id',
        (raw['onesignal_app_id'] as String? ?? '').trim(),
      );
    }
    if (raw.containsKey('onesignal_enabled')) {
      final enabled = raw['onesignal_enabled'];
      await box.write(
        'onesignal_enabled',
        enabled == true || enabled == 1 || enabled == '1',
      );
    }
    await persistPanelApiKeysFromResponse(raw);
  }

  static Map<String, dynamic> _legalAndEnforcementFieldsFrom(Map responseData) {
    return <String, dynamic>{
      'activation_enforced': parseActivationEnforcedFlag(
        responseData['activation_enforced'],
      ),
      'privacy_policy_url':
          (responseData['privacy_policy_url'] as String? ?? '').trim(),
      'privacy_policy_html':
          (responseData['privacy_policy_html'] as String? ?? '').trim(),
      'privacy_policy_mode':
          ((responseData['privacy_policy_mode'] as String? ?? 'url')
                  .toLowerCase() ==
              'html')
          ? 'html'
          : 'url',
      'about_us_html': (responseData['about_us_html'] as String? ?? '').trim(),
    };
  }

  /// ضع هنا شهادة الـ PEM الموثوقة الخاصة بالدومين أعلاه (SSL pinning).
  /// مثال: انسخ الشهادة من السيرفر كما هي ثم الصقها:
  /// -----BEGIN CERTIFICATE-----
  /// MIIF....
  /// -----END CERTIFICATE-----
  static const String _pinnedCertPem = '''
// TODO: ضع شهادة السيرفر هنا بالضبط كما هي (PEM)
''';

  ActivationApi()
    : _dio = Dio(
        BaseOptions(
          baseUrl: normalizedActivationPanelBaseUrl(),
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => true,
        ),
      ) {
    _forgetStaleDeviceSessionIfPanelChanged();
    _configurePanelTls();
  }

  /// عند تغيير رابط اللوحة في config.dart نبدأ جلسة جديدة مع اللوحة الجديدة
  /// (نفس سلوك أول تشغيل على لوحتك).
  static void _forgetStaleDeviceSessionIfPanelChanged() {
    try {
      final box = GetStorage();
      final base = normalizedActivationPanelBaseUrl();
      if (base.isEmpty) return;
      final host = Uri.parse(base).host.trim().toLowerCase();
      final prevBase = (box.read(_kBoundPanelBaseStorage) ?? '')
          .toString()
          .trim();
      final prevHost = (box.read(_kBoundPanelHostStorage) ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final token = (box.read(_kDeviceApiTokenStorage) ?? '').toString().trim();
      final changed =
          (prevBase.isNotEmpty && prevBase != base) ||
          (prevHost.isNotEmpty && prevHost != host) ||
          (prevBase.isEmpty && token.isNotEmpty);
      if (changed) {
        box.remove(_kDeviceApiTokenStorage);
        box.remove('app_activation_url');
        ActivationTokenService.clear();
      }
      box.write(_kBoundPanelBaseStorage, base);
      if (host.isNotEmpty) {
        box.write(_kBoundPanelHostStorage, host);
      }
    } catch (_) {}
  }

  /// لوحات المشترين غالباً على استضافة رخيصة (سلسلة شهادات ناقصة) أو تُفتح من
  /// Android TV قديم (5/6) لا يثق بجذر Let's Encrypt. نسمح بالـ TLS للوحة فقط.
  void _configurePanelTls() {
    final pem = _pinnedCertPem.trim();
    final pin = pem.contains('-----BEGIN CERTIFICATE-----');

    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) {
          if (pin) return false;
          final panel = _pinnedHost.toLowerCase();
          final h = host.toLowerCase();
          final allow = panel.isNotEmpty && (h == panel || h == 'www.$panel');
          if (allow) {
            _actLog(
              'TLS accept panel host=$host issuer=${cert.issuer} '
              '(incomplete chain or old Android)',
            );
          }
          return allow;
        };
        return client;
      },
      validateCertificate: pin
          ? (cert, host, port) {
              if (cert == null) return false;
              if (host == _pinnedHost) {
                return cert.pem.trim() == pem;
              }
              return true;
            }
          : null,
    );
  }

  String _newNonce() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String? _storedDeviceToken() {
    final t = (GetStorage().read(_kDeviceApiTokenStorage) ?? '')
        .toString()
        .trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _persistDeviceTokenFrom(dynamic data) async {
    if (data is! Map) return;
    final token = (data['device_token'] as String?)?.trim() ?? '';
    if (token.length >= 32) {
      await GetStorage().write(_kDeviceApiTokenStorage, token);
    }
  }

  Map<String, dynamic> _withDeviceToken(Map<String, dynamic> payload) {
    final token = _storedDeviceToken();
    if (token != null) {
      payload['device_token'] = token;
    }
    return payload;
  }

  /// HMAC-SHA256 headers expected by `admin panel/includes/api_auth.php`.
  /// Canonical: `{timestamp}\n{nonce}\n{METHOD}\n{path}\n{rawBody}`
  /// Timestamp follows panel clock (Date header), not the device clock —
  /// Android TV emulators often fail automatic time sync and stay years off.
  Future<Options> _signedOptions({
    required String method,
    required String path,
    required String rawBody,
    String? contentType,
    bool forceClockSync = false,
  }) async {
    await _ensureServerClockOffset(force: forceClockSync);
    final ts = _hmacTimestampSeconds().toString();
    final nonce = _newNonce();
    final secret = kAppApiSecret.trim();
    final canonical = '$ts\n$nonce\n${method.toUpperCase()}\n$path\n$rawBody';
    final sig = secret.isEmpty
        ? ''
        : Hmac(
            sha256,
            utf8.encode(secret),
          ).convert(utf8.encode(canonical)).toString();
    return Options(
      method: method,
      contentType: contentType ?? 'application/json',
      headers: <String, dynamic>{
        'X-Nova-Timestamp': ts,
        'X-Nova-Nonce': nonce,
        'X-Nova-Signature': sig,
      },
    );
  }

  int _hmacTimestampSeconds() {
    final device =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return device + (_serverClockOffsetSec ?? 0);
  }

  Future<void> _ensureServerClockOffset({bool force = false}) async {
    if (!force &&
        _serverClockOffsetSec != null &&
        _serverClockSyncedAt != null &&
        DateTime.now().difference(_serverClockSyncedAt!) <
            const Duration(minutes: 30)) {
      return;
    }
    try {
      final base = normalizedActivationPanelBaseUrl().trim();
      if (base.isEmpty) return;
      final headUrl = base.endsWith('/') ? base : '$base/';
      final res = await _dio.head(
        headUrl,
        options: Options(
          validateStatus: (code) => code != null && code < 500,
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final dateHeader = res.headers.value('date');
      if (dateHeader == null || dateHeader.trim().isEmpty) return;
      final serverSec =
          HttpDate.parse(dateHeader).toUtc().millisecondsSinceEpoch ~/ 1000;
      final deviceSec =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      _serverClockOffsetSec = serverSec - deviceSec;
      _serverClockSyncedAt = DateTime.now();
      if (_serverClockOffsetSec!.abs() > 60) {
        _actLog(
          'panel clock offset=${_serverClockOffsetSec}s '
          '(device skew; common on Android TV emulator)',
        );
      }
    } catch (e) {
      _actLog('panel clock sync failed: $e');
    }
  }

  bool _responseLooksTimestampExpired(Response<dynamic> response) {
    if (response.statusCode != 401) return false;
    final data = response.data;
    String message = '';
    if (data is Map) {
      message = (data['message'] ?? data['error'] ?? '').toString();
    } else if (data is String) {
      message = data;
    }
    message = message.toLowerCase();
    return message.contains('timestamp_expired') ||
        message.contains('expired_request') ||
        message.contains('clock');
  }

  Map<String, String> _fieldsFromJsonBody(String rawBody) {
    try {
      final decoded = json.decode(rawBody);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry('$k', v == null ? '' : '$v'));
      }
    } catch (_) {}
    return const <String, String>{};
  }

  bool _deviceIdMissing(Response<dynamic> response) {
    final code = response.statusCode ?? 0;
    if (code == 400) return true;
    final data = response.data;
    String message = '';
    if (data is Map) {
      message = (data['message'] ?? '').toString();
    } else if (data is String) {
      message = data;
    }
    message = message.toLowerCase();
    return message.contains('device id is required') ||
        message.contains('device_required') ||
        message.contains('device_id is required');
  }

  Future<Response<dynamic>> _signedSend({
    required String method,
    required String url,
    required String hmacPath,
    required String bodyForHmac,
    Object? data,
    String? contentType,
  }) async {
    Future<Response<dynamic>> once({required bool forceClockSync}) async {
      return _dio.request<dynamic>(
        url,
        data: data,
        options: await _signedOptions(
          method: method,
          path: hmacPath,
          rawBody: bodyForHmac,
          contentType: contentType,
          forceClockSync: forceClockSync,
        ),
      );
    }

    try {
      var response = await once(forceClockSync: false);
      if (_responseLooksTimestampExpired(response)) {
        _actLog('timestamp_expired — resync panel clock and retry once');
        response = await once(forceClockSync: true);
      }
      final dbg = response.headers.value('x-nova-debug') ?? '';
      _actLog(
        '$method ${response.statusCode} $url hmacPath=$hmacPath '
        'ct=${contentType ?? 'json'} bodyLen=${bodyForHmac.length} '
        '${dbg.isNotEmpty ? 'dbg=$dbg ' : ''}'
        'resp=${_actSnippet(response.data)}',
      );
      return response;
    } catch (e) {
      _actLog('EX $method $url hmacPath=$hmacPath err=$e');
      rethrow;
    }
  }

  /// POST JSON + query أولاً (طلب واحد). GET/Form فقط إذا ردّت اللوحة 400
  /// بدون device_id — لا نعيد المحاولة عند انتهاء المهلة حتى لا يتوقف السبلاش.
  Future<Response<dynamic>> _signedPost(String path, String rawBody) async {
    final hmacPath = path.contains('/api/')
        ? path.substring(path.indexOf('/api/'))
        : path;
    final url = '${normalizedActivationPanelBaseUrl()}$path';
    final fields = _fieldsFromJsonBody(rawBody);
    final query = fields.isEmpty
        ? ''
        : '?${Uri(queryParameters: fields).query}';
    final urlWithQuery = '$url$query';
    final jsonBytes = utf8.encode(rawBody);

    Response<dynamic>? response;
    try {
      response = await _signedSend(
        method: 'POST',
        url: urlWithQuery,
        hmacPath: hmacPath,
        bodyForHmac: rawBody,
        data: jsonBytes,
        contentType: 'application/json',
      );
      if (response.statusCode == 401) {
        final uriPath = Uri.parse(url).path;
        if (uriPath.isNotEmpty && uriPath != hmacPath) {
          response = await _signedSend(
            method: 'POST',
            url: urlWithQuery,
            hmacPath: uriPath,
            bodyForHmac: rawBody,
            data: jsonBytes,
            contentType: 'application/json',
          );
        }
      }
    } catch (e) {
      _actLog('POST json failed: $e');
      return Response<dynamic>(
        requestOptions: RequestOptions(path: url),
        statusCode: 599,
        statusMessage: e.toString(),
      );
    }

    if (!_deviceIdMissing(response)) {
      return response;
    }

    try {
      response = await _signedSend(
        method: 'GET',
        url: urlWithQuery,
        hmacPath: hmacPath,
        bodyForHmac: '',
        data: null,
        contentType: 'application/json',
      );
      if (!_deviceIdMissing(response) && response.statusCode == 200) {
        return response;
      }
    } catch (e) {
      _actLog('GET fallback skipped: $e');
    }

    if (fields.isNotEmpty) {
      final form = Uri(queryParameters: fields).query;
      try {
        response = await _signedSend(
          method: 'POST',
          url: url,
          hmacPath: hmacPath,
          bodyForHmac: form,
          data: utf8.encode(form),
          contentType: 'application/x-www-form-urlencoded',
        );
      } catch (e) {
        _actLog('POST form failed: $e');
      }
    }

    return response ??
        Response<dynamic>(
          requestOptions: RequestOptions(path: url),
          statusCode: 599,
        );
  }

  static bool _asBool(dynamic v) {
    return v == true || v == 1 || v == '1' || v == 'true';
  }

  /// يحفظ حالة/انتهاء التفعيل بعد فحص ناجح من اللوحة.
  static void persistActivationGate(Map<String, dynamic> result) {
    if (result['_check_failed'] == true) return;
    final status = (result['status'] ?? '').toString().trim();
    if (status.isEmpty) return;
    GetStorage().write('activation_status', status);
    if (result.containsKey('expiry_date')) {
      GetStorage().write(
        'activation_expiry_date',
        (result['expiry_date'] ?? '').toString().trim(),
      );
    }
    final expiryRaw = (result['expiry_date'] ?? '').toString().trim();
    final parsed = parseActivationRemaining(expiryRaw);
    final lifetime =
        _asBool(result['lifetime']) || (parsed?.isLifetime ?? false);
    GetStorage().write('activation_lifetime', lifetime);
    if (result.containsKey('trial')) {
      GetStorage().write(
        'activation_is_trial',
        !lifetime && _asBool(result['trial']),
      );
    } else if (lifetime) {
      GetStorage().write('activation_is_trial', false);
    }
  }

  static Map<String, dynamic> _checkFailed([String reason = 'unknown']) {
    _actLog('CHECK FAILED → Inactive reason=$reason');
    return {
      'status': 'غير مفعل',
      'expiry_date': '',
      '_check_failed': true,
      '_inactive_reason': reason,
    };
  }

  Future<Map<String, dynamic>> checkActivation(
    String deviceId, {
    bool allowAutoRegister = true,
  }) async {
    final secret = kAppApiSecret.trim();
    _actLog(
      'check start panel=${normalizedActivationPanelBaseUrl()} '
      'deviceId=${deviceId.isEmpty ? "(EMPTY)" : deviceId} '
      'autoRegister=$allowAutoRegister '
      'secretLen=${secret.length} secretPrefix=${secret.isEmpty ? "-" : secret.substring(0, secret.length >= 4 ? 4 : secret.length)}',
    );
    Map<String, dynamic> gate(Map<String, dynamic> m) {
      persistActivationGate(m);
      return m;
    }
    try {
      if (deviceId.trim().isEmpty) {
        return _checkFailed('empty_device_id');
      }
      final bare = jsonEncode(await _deviceIdentity(deviceId, withToken: false));
      var response = await _signedPost('/api/check-activation.php', bare);
      if (response.statusCode != 200 && _storedDeviceToken() != null) {
        _actLog(
          'retry check without stored device_token (http=${response.statusCode})',
        );
        await GetStorage().remove(_kDeviceApiTokenStorage);
        response = await _signedPost('/api/check-activation.php', bare);
      }

      if (response.statusCode == 200) {
        var responseData = response.data;

        if (responseData is String) {
          try {
            responseData = json.decode(responseData);
          } catch (e) {
            return _checkFailed(
              'check_body_not_json:${_actSnippet(responseData)}',
            );
          }
        }

        if (responseData is Map) {
          ActivationTokenService.applyResponse(
            Map<String, dynamic>.from(responseData),
            deviceId,
          );
          await _persistDeviceTokenFrom(responseData);
          final String remoteStatus = (responseData['status'] as String? ?? '')
              .toLowerCase()
              .trim();
          final String expiryDate = (responseData['expiry_date'] ?? '')
              .toString()
              .trim();
          final remoteRemaining = parseActivationRemaining(expiryDate);
          final expiryStillValid =
              remoteRemaining != null && remoteRemaining.isValid;
          // لوحة قد تُظهر Active بينما status في القاعدة ما زال expired بعد إعادة التفعيل.
          // إن كان تاريخ الانتهاء في المستقبل والجهاز غير محظور → اعتبره مفعّلاً.
          final bool isActivated =
              _asBool(responseData['activated']) ||
              remoteStatus == 'active' ||
              (expiryStillValid && remoteStatus != 'blocked');
          final String username = responseData['username'] ?? '';
          final String domain = responseData['domain'] ?? '';
          final bool hasPlaylist = responseData['has_playlist'] == true;
          // إعدادات الإعلانات من لوحة التحكم (اختيارية)
          final bool adsEnabled = responseData['ads_enabled'] is bool
              ? responseData['ads_enabled'] as bool
              : true;
          final bool bannerHomeOnly = responseData['banner_home_only'] is bool
              ? responseData['banner_home_only'] as bool
              : true;
          final String bannerAndroid =
              responseData['banner_ad_unit_android'] as String? ?? '';
          final String bannerIos =
              responseData['banner_ad_unit_ios'] as String? ?? '';
          final String interAndroid =
              responseData['interstitial_ad_unit_android'] as String? ?? '';
          final String interIos =
              responseData['interstitial_ad_unit_ios'] as String? ?? '';
          final String remoteAppName =
              responseData['app_name'] as String? ?? '';
          final bool showAddChangeButton =
              responseData['show_add_change_button'] is bool
              ? responseData['show_add_change_button'] as bool
              : true;
          final bool showUsernameLogin =
              responseData['show_username_login'] is bool
              ? responseData['show_username_login'] as bool
              : true;
          final String appVersion =
              responseData['app_version'] as String? ?? '1.0.0';
          final String supportContactUrl =
              responseData['support_contact_url'] as String? ?? '';
          final String tmdbApiKey =
              (responseData['tmdb_api_key'] as String? ?? '').trim();
          final String opensubtitlesApiKey =
              (responseData['opensubtitles_api_key'] as String? ?? '').trim();
          final String opensubtitlesUsername =
              (responseData['opensubtitles_username'] as String? ?? '').trim();
          final String opensubtitlesPassword =
              (responseData['opensubtitles_password'] as String? ?? '').trim();

          AdsService.persistFromPanel(responseData);

          await persistPanelApiKeysFromResponse({
            'tmdb_api_key': tmdbApiKey,
            'opensubtitles_api_key': opensubtitlesApiKey,
            'opensubtitles_username': opensubtitlesUsername,
            'opensubtitles_password': opensubtitlesPassword,
          });

          GetStorage().write('show_add_change_button', showAddChangeButton);
          GetStorage().write('show_username_login', showUsernameLogin);
          final localVer = (GetStorage().read('local_app_version') ?? '')
              .toString()
              .trim();
          final panelVer = appVersion.trim().isEmpty ? '1.0.0' : appVersion.trim();
          // Prefer the installed build so settings never lag behind a stale panel value.
          GetStorage().write(
            'app_version',
            localVer.isNotEmpty ? localVer : panelVer,
          );

          final legal = _legalAndEnforcementFieldsFrom(responseData);
          // Full panel payload (incl. default_server_url) — do not pass a
          // partial map or other settings get wiped to empty strings.
          await persistPanelMetadataFromResponse({
            ...Map<String, dynamic>.from(responseData),
            ...legal,
            'support_contact_url': supportContactUrl,
          });

          if (isActivated) {
            _actLog('panel says ACTIVE expiry=$expiryDate');
            final blockVpn = responseData['block_vpn'] == true;
            try {
              final embedded = responseData['web_playlists'];
              if (embedded is List) {
                final mapped = embedded
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
                await SavedAccountsRepository.syncFromWebPlaylists(mapped);
              } else {
                await syncWebPlaylistsToAccounts(deviceId);
              }
            } catch (_) {
              try {
                await syncWebPlaylistsToAccounts(deviceId);
              } catch (_) {}
            }
            return gate({
              'status': 'نشط',
              'expiry_date': expiryDate,
              'lifetime':
                  _asBool(responseData['lifetime']) ||
                  (remoteRemaining?.isLifetime ?? false),
              'trial': _asBool(responseData['trial']),
              'username': username,
              'domain': domain,
              'has_playlist': hasPlaylist,
              'block_vpn': blockVpn,
              'ads_enabled': adsEnabled,
              'banner_home_only': bannerHomeOnly,
              'banner_ad_unit_android': bannerAndroid,
              'banner_ad_unit_ios': bannerIos,
              'interstitial_ad_unit_android': interAndroid,
              'interstitial_ad_unit_ios': interIos,
              'app_name': remoteAppName,
              'show_add_change_button': showAddChangeButton,
              'show_username_login': showUsernameLogin,
              'app_version': appVersion,
              'support_contact_url': supportContactUrl,
              'tmdb_api_key': tmdbApiKey,
              'opensubtitles_api_key': opensubtitlesApiKey,
              'opensubtitles_username': opensubtitlesUsername,
              'opensubtitles_password': opensubtitlesPassword,
              ...legal,
            });
          } else {
            if (remoteStatus == 'blocked') {
              return gate({
                'status': 'محظور',
                'expiry_date': expiryDate,
                'ads_enabled': adsEnabled,
                'banner_home_only': bannerHomeOnly,
                'banner_ad_unit_android': bannerAndroid,
                'banner_ad_unit_ios': bannerIos,
                'interstitial_ad_unit_android': interAndroid,
                'interstitial_ad_unit_ios': interIos,
                'app_name': remoteAppName,
                'show_add_change_button': showAddChangeButton,
                'show_username_login': showUsernameLogin,
                'app_version': appVersion,
                'support_contact_url': supportContactUrl,
                'tmdb_api_key': tmdbApiKey,
                'opensubtitles_api_key': opensubtitlesApiKey,
                'opensubtitles_username': opensubtitlesUsername,
                'opensubtitles_password': opensubtitlesPassword,
                ...legal,
              });
            } else if (remoteStatus == 'expired') {
              return gate({
                'status': 'منتهي',
                'expiry_date': expiryDate,
                // قد تكون playlist مربوطة عبر QR قبل التجديد — مرّرها للجهاز.
                'username': username,
                'domain': domain,
                'has_playlist': hasPlaylist,
                'ads_enabled': adsEnabled,
                'banner_home_only': bannerHomeOnly,
                'banner_ad_unit_android': bannerAndroid,
                'banner_ad_unit_ios': bannerIos,
                'interstitial_ad_unit_android': interAndroid,
                'interstitial_ad_unit_ios': interIos,
                'app_name': remoteAppName,
                'show_add_change_button': showAddChangeButton,
                'show_username_login': showUsernameLogin,
                'app_version': appVersion,
                'support_contact_url': supportContactUrl,
                'tmdb_api_key': tmdbApiKey,
                'opensubtitles_api_key': opensubtitlesApiKey,
                'opensubtitles_username': opensubtitlesUsername,
                'opensubtitles_password': opensubtitlesPassword,
                ...legal,
              });
            } else {
              final inactive = <String, dynamic>{
                'status': 'غير مفعل',
                'expiry_date': expiryDate,
                // QR link: اللوحة قد ترجع domain قبل أن يصبح status=active في ردّ سابق.
                'username': username,
                'domain': domain,
                'has_playlist': hasPlaylist,
                'ads_enabled': adsEnabled,
                'banner_home_only': bannerHomeOnly,
                'banner_ad_unit_android': bannerAndroid,
                'banner_ad_unit_ios': bannerIos,
                'interstitial_ad_unit_android': interAndroid,
                'interstitial_ad_unit_ios': interIos,
                'app_name': remoteAppName,
                'show_add_change_button': showAddChangeButton,
                'show_username_login': showUsernameLogin,
                'app_version': appVersion,
                'support_contact_url': supportContactUrl,
                'tmdb_api_key': tmdbApiKey,
                'opensubtitles_api_key': opensubtitlesApiKey,
                'opensubtitles_username': opensubtitlesUsername,
                'opensubtitles_password': opensubtitlesPassword,
                ...legal,
              };

              // جهاز غير موجود في اللوحة → سجّله تلقائياً إن كان مسموحاً من الإعدادات
              if (allowAutoRegister) {
                _actLog('panel Inactive → activateDevice (auto register)');
                final act = await activateDevice(deviceId);
                if (act['success'] == true) {
                  _actLog('auto register OK → re-check');
                  return checkActivation(
                    deviceId,
                    allowAutoRegister: false,
                  );
                }
                inactive['_inactive_reason'] =
                    'activate_failed:${act['message'] ?? 'unknown'} '
                    'status=$remoteStatus';
                _actLog('auto register FAILED: ${inactive['_inactive_reason']}');
                return gate(inactive);
              }

              inactive['_inactive_reason'] =
                  'panel_inactive status=$remoteStatus '
                  'allowAuto=$allowAutoRegister';
              _actLog('returning Inactive: ${inactive['_inactive_reason']}');
              return gate(inactive);
            }
          }
        }
      }

      final code = response.statusCode ?? 0;
      final panelMsg = () {
        final d = response.data;
        if (d is Map) return (d['message'] ?? '').toString();
        return _actSnippet(d);
      }();
      return _checkFailed(
        'http=$code msg=$panelMsg autoRegisterTried=$allowAutoRegister',
      );
    } catch (e) {
      return _checkFailed('exception:$e');
    }
  }

  /// إرسال نبضة (Heartbeat) لتحديث حالة تواجد الجهاز في لوحة التحكم
  Future<void> sendHeartbeat(String deviceId) async {
    try {
      if (deviceId.isEmpty) return;
      final isTrial = GetStorage().read('activation_is_trial') == true;
      final isLifetime = GetStorage().read('activation_lifetime') == true;
      // لا نرسل تاريخ انتهاء IPTV أثناء التجربة — يمنع تمديد trial بسيرفر طويل
      final iptvExp = (!isTrial && !isLifetime)
          ? (GetStorage().read('cached_iptv_exp_date') ?? '').toString().trim()
          : '';
      final deviceName = await _getDeviceDisplayName();
      final watching = NowWatchingPresence.instance.toHeartbeatFields();
      final payload = await _signedDevicePayload(<String, dynamic>{
        'device_id': deviceId,
        if (deviceName.isNotEmpty) 'device_name': deviceName,
        if (iptvExp.isNotEmpty) 'iptv_exp_date': iptvExp,
        ...watching,
      });
      final data = jsonEncode(payload);
      await _signedPost('/api/heartbeat.php', data);
    } catch (e) {
      // في حال الفشل نتجاهل الخطأ حتى لا يؤثر على تجربة المستخدم
    }
  }

  Future<Map<String, dynamic>> activateDevice(String deviceId) async {
    try {
      _actLog('activate start deviceId=$deviceId');
      final body = jsonEncode(await _deviceIdentity(deviceId));

      final response = await _signedPost('/api/activate-device.php', body);

      if (response.statusCode == 200) {
        var data = response.data;
        if (data is String) {
          try {
            data = json.decode(data);
          } catch (e) {
            return {'success': false};
          }
        }

        if (data is Map) {
          ActivationTokenService.applyResponse(
            Map<String, dynamic>.from(data),
            deviceId,
          );
          await _persistDeviceTokenFrom(data);
          await persistPanelMetadataFromResponse(
            Map<String, dynamic>.from(data),
          );
          final success = _asBool(data['success']);
          final alreadyActive = _asBool(data['already_active']);
          final message = (data['message'] as String?) ?? '';

          return {
            'success': success,
            'already_active': alreadyActive,
            'expiry_date': data['expiry_date'],
            if (message.isNotEmpty) 'message': message,
            'support_contact_url':
                (data['support_contact_url'] as String? ?? '').trim(),
            'app_activation_url':
                (data['app_activation_url'] as String? ?? '').trim(),
            'purchase_url': (data['purchase_url'] as String? ?? '').trim(),
            'activation_enforced': parseActivationEnforcedFlag(
              data['activation_enforced'],
            ),
          };
        }
      }

      return {
        'success': false,
        'message': 'http=${response.statusCode} ${_actSnippet(response.data)}',
      };
    } catch (e) {
      return {'success': false, 'message': 'exception:$e'};
    }
  }

  /// حذف رابط الـ playlist من لوحة التحكم عند تسجيل الخروج لتمكين المستخدم من إدخال رابط آخر
  Future<bool> clearPlaylistUrl(String deviceId) async {
    try {
      if (deviceId.isEmpty) return false;
      final body = jsonEncode(await _signedDevicePayload({'device_id': deviceId}));
      final response = await _signedPost('/api/delete-playlist.php', body);
      if (response.statusCode == 200) {
        var data = response.data;
        if (data is String) {
          try {
            data = json.decode(data);
          } catch (_) {}
        }
        return data is Map && data['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// قوائم M3U من موقع Manage Playlist لمزامنتها إلى Manage Accounts.
  /// تُرجع null عند فشل الطلب (لا تُفسَّر كقائمة فارغة حتى لا تُحذف الحسابات المحلية).
  Future<List<Map<String, dynamic>>?> fetchWebPlaylists(String deviceId) async {
    try {
      if (deviceId.isEmpty) return null;
      final body = jsonEncode(await _signedDevicePayload({'device_id': deviceId}));
      final response = await _signedPost('/api/device-web-playlists.php', body);
      if (response.statusCode != 200) return null;
      var data = response.data;
      if (data is String) {
        try {
          data = json.decode(data);
        } catch (_) {
          return null;
        }
      }
      if (data is! Map || data['success'] != true) return null;
      final raw = data['playlists'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// جلب ومزامنة قوائم الويب إلى الحسابات المحلية.
  Future<void> syncWebPlaylistsToAccounts(String deviceId) async {
    final playlists = await fetchWebPlaylists(deviceId);
    if (playlists == null) return;
    await SavedAccountsRepository.syncFromWebPlaylists(playlists);
  }

  /// حذف قائمة ويب من السيرفر عند حذفها من Manage Accounts.
  Future<bool> deleteWebPlaylist({
    required String deviceId,
    required String remotePlaylistId,
  }) async {
    try {
      final pid = int.tryParse(remotePlaylistId.trim()) ?? 0;
      if (deviceId.isEmpty || pid <= 0) return false;
      final body = jsonEncode(
        await _signedDevicePayload({'device_id': deviceId, 'playlist_id': pid}),
      );
      final response = await _signedPost(
        '/api/delete-device-web-playlist.php',
        body,
      );
      if (response.statusCode != 200) return false;
      var data = response.data;
      if (data is String) {
        try {
          data = json.decode(data);
        } catch (_) {
          return false;
        }
      }
      return data is Map && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// حفظ رابط الـ playlist في لوحة التحكم ليعمل عند الدخول مجدداً.
  ///
  /// [forRemoteDevice]: ربط جهاز آخر عبر QR — لا نُرسل MAC/بصمة/token الجهاز الحالي
  /// حتى لا تُعاد مطابقة الصف على الجهاز الماسح بدل الهدف.
  Future<Map<String, dynamic>> savePlaylistUrl(
    String deviceId,
    String playlistUrl, {
    bool forRemoteDevice = false,
  }) async {
    try {
      if (deviceId.isEmpty || playlistUrl.trim().isEmpty) {
        return {'success': false};
      }
      final Map<String, dynamic> payload;
      if (forRemoteDevice) {
        final ver = await _localAppVersionLabel();
        payload = <String, dynamic>{
          'device_id': deviceId.trim(),
          'playlist_url': playlistUrl.trim(),
          'link_remote': true,
          if (ver.isNotEmpty) 'app_version': ver,
        };
      } else {
        payload = await _signedDevicePayload({
          'device_id': deviceId.trim(),
          'playlist_url': playlistUrl.trim(),
        });
      }
      final body = jsonEncode(payload);
      final response = await _signedPost('/api/save-playlist.php', body);
      if (response.statusCode == 200 || response.statusCode == 409) {
        var data = response.data;
        if (data is String) {
          try {
            data = json.decode(data);
          } catch (_) {}
        }
        if (data is Map) {
          // لا نخزّن device_token الراجع عند ربط جهاز بعيد — يخص الهدف لا الماسح.
          if (!forRemoteDevice) {
            await _persistDeviceTokenFrom(data);
          }
          return Map<String, dynamic>.from(data);
        }
        return {'success': false};
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  /// فك ربط جهاز بعيد (QR): مسح playlist/account فقط — بدون إنهاء التفعيل.
  Future<bool> unlinkRemoteDevice(String deviceId) async {
    try {
      if (deviceId.trim().isEmpty) return false;
      final ver = await _localAppVersionLabel();
      final body = jsonEncode(<String, dynamic>{
        'device_id': deviceId.trim(),
        'unlink_remote': true,
        if (ver.isNotEmpty) 'app_version': ver,
      });
      final response = await _signedPost('/api/delete-playlist.php', body);
      if (response.statusCode == 200) {
        var data = response.data;
        if (data is String) {
          try {
            data = json.decode(data);
          } catch (_) {}
        }
        return data is Map && data['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// حذف الجهاز نهائياً من لوحة التحكم
  Future<bool> deleteDevice(String deviceId) async {
    try {
      if (deviceId.isEmpty) return false;
      final body = jsonEncode(await _signedDevicePayload({'device_id': deviceId}));
      final response = await _signedPost('/api/delete-device.php', body);
      if (response.statusCode == 200) {
        var data = response.data;
        if (data is String) {
          try {
            data = json.decode(data);
          } catch (_) {}
        }
        return data is Map && data['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// ربط حساب IPTV (username/password) بالجهاز لتطبيق حد الأجهزة حسب الحساب
  Future<Map<String, dynamic>> bindAccountToDevice({
    required String deviceId,
    required String username,
    required String password,

    /// هوست السيرفر القادم من كود القائمة (host-only) ليُحفظ في لوحة التحكم مع اليوزر/الباسورد اليدوي.
    String? serverHost,
    String? displayName,
  }) async {
    try {
      if (deviceId.trim().isEmpty ||
          username.trim().isEmpty ||
          password.trim().isEmpty) {
        return {'success': false};
      }
      final host = serverHost?.trim() ?? '';
      final name = displayName?.trim() ?? '';
      final body = jsonEncode(
        await _signedDevicePayload({
          'device_id': deviceId.trim(),
          'username': username.trim(),
          'password': password.trim(),
          if (host.isNotEmpty) 'server_host': host,
          if (name.isNotEmpty) 'display_name': name,
        }),
      );
      final response = await _signedPost('/api/bind-account.php', body);
      if (response.statusCode == 200 || response.statusCode == 409) {
        var data = response.data;
        if (data is String) {
          try {
            data = json.decode(data);
          } catch (_) {}
        }
        if (data is Map) {
          await _persistDeviceTokenFrom(data);
          return Map<String, dynamic>.from(data);
        }
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  /// يزامن بيانات الدخول (سيرفر + يوزر + باس) مع لوحة التحكم بعد تسجيل الدخول من التطبيق.
  Future<void> syncDeviceLoginToPanel({
    required String username,
    required String password,
    String? serverHost,
    String? displayName,
  }) async {
    try {
      final user = username.trim();
      final pass = password.trim();
      if (user.isEmpty || pass.isEmpty) return;
      final deviceId = (await getDeviceId()).trim();
      if (deviceId.isEmpty) return;
      await bindAccountToDevice(
        deviceId: deviceId,
        username: user,
        password: pass,
        serverHost: serverHost,
        displayName: displayName,
      );
    } catch (_) {
      // لا نكسر تدفق الدخول إذا فشلت المزامنة مع اللوحة
    }
  }

  Future<Map<String, dynamic>> _withDeviceBindingKeys(
    Map<String, dynamic> map,
  ) async {
    final mac = await DeviceMacService.instance.resolve();
    if (mac.isNotEmpty) {
      map['mac_address'] = mac;
    }
    final hw = await DeviceHardwareFingerprintService.instance.resolve();
    if (hw.isNotEmpty) {
      map['hardware_fingerprint'] = hw;
    }
    return map;
  }

  /// Marketing version from the installed build (pubspec), e.g. `1.2.8` — no `+build`.
  Future<String> _localAppVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      if (v.isEmpty) return '';
      // Never append buildNumber (+29); panel / UI show marketing version only.
      final plus = v.indexOf('+');
      final label = plus >= 0 ? v.substring(0, plus).trim() : v;
      if (label.isEmpty) return '';
      try {
        GetStorage().write('local_app_version', label);
        GetStorage().write('app_version', label);
      } catch (_) {}
      return label;
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, dynamic>> _signedDevicePayload(
    Map<String, dynamic> base,
  ) async {
    final withBind = await _withDeviceBindingKeys(_withDeviceToken(base));
    final ver = await _localAppVersionLabel();
    if (ver.isNotEmpty) {
      withBind['app_version'] = ver;
    }
    return withBind;
  }

  Future<Map<String, dynamic>> _deviceIdentity(
    String deviceId, {
    bool withToken = true,
  }) async {
    final name = await _getDeviceDisplayName();
    final ver = await _localAppVersionLabel();
    var map = <String, dynamic>{
      'device_id': deviceId,
      if (name.isNotEmpty) 'device_name': name,
      if (ver.isNotEmpty) 'app_version': ver,
    };
    map = await _withDeviceBindingKeys(map);
    return withToken ? _withDeviceToken(map) : map;
  }

  Future<String> _getDeviceDisplayName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        final brand = (android.brand).trim();
        final model = (android.model).trim();
        final composed = '$brand $model'.trim();
        return composed.isEmpty ? 'Android Device' : composed;
      }
      if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        final model = (ios.model).trim();
        final name = (ios.name).trim();
        final composed = '$name $model'.trim();
        return composed.isEmpty ? 'iOS Device' : composed;
      }
    } catch (_) {}
    return 'Unknown Device';
  }

  /// نتيجة التحقق من رمز القائمة (لوحة التحكم → التطبيق).
  Future<PlaylistCodeRedeemResult> redeemPlaylistCode(String rawCode) async {
    final digits = rawCode.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 5 || digits.length > 6) {
      return PlaylistCodeRedeemResult(
        ok: false,
        messageKey: 'access_code_invalid_len',
      );
    }
    try {
      final deviceId = await getDeviceId();
      final deviceName = await _getDeviceDisplayName();
      final body = jsonEncode(
        await _signedDevicePayload({
          'code': digits,
          'device_id': deviceId,
          'device_name': deviceName,
        }),
      );
      final response = await _signedPost('/api/redeem-playlist-code.php', body);
      var data = response.data;
      if (data is String) {
        try {
          data = json.decode(data);
        } catch (_) {
          return PlaylistCodeRedeemResult(
            ok: false,
            messageKey: 'access_code_network',
          );
        }
      }
      if (data is! Map) {
        return PlaylistCodeRedeemResult(
          ok: false,
          messageKey: 'access_code_server',
        );
      }
      final map = Map<String, dynamic>.from(data);
      await _persistDeviceTokenFrom(map);
      if (map['success'] == true) {
        final url = (map['m3u_url'] as String?)?.trim() ?? '';
        if (url.isEmpty) {
          return PlaylistCodeRedeemResult(
            ok: false,
            messageKey: 'access_code_not_found',
          );
        }
        return PlaylistCodeRedeemResult(ok: true, m3uUrl: url);
      }
      final msg = (map['message'] as String?) ?? '';
      if (msg == 'invalid_code') {
        return PlaylistCodeRedeemResult(
          ok: false,
          messageKey: 'access_code_invalid_len',
        );
      }
      if (msg == 'code_not_found' || msg == 'invalid_playlist') {
        return PlaylistCodeRedeemResult(
          ok: false,
          messageKey: 'access_code_not_found',
        );
      }
      if (msg == 'code_max_devices' || msg == 'device_required') {
        return PlaylistCodeRedeemResult(
          ok: false,
          messageKey: msg == 'device_required'
              ? 'access_code_server'
              : 'access_code_max_devices',
        );
      }
      if (msg == 'code_wrong_device') {
        return PlaylistCodeRedeemResult(
          ok: false,
          messageKey: 'access_code_wrong_device',
        );
      }
      return PlaylistCodeRedeemResult(
        ok: false,
        messageKey: 'access_code_server',
      );
    } catch (e) {
      return PlaylistCodeRedeemResult(
        ok: false,
        messageKey: 'access_code_network',
      );
    }
  }

  Future<bool> sendClientFeedback({
    required String note,
    String? deviceUrl,
  }) async {
    try {
      final trimmed = note.trim();
      if (trimmed.isEmpty) return false;
      final deviceId = await getDeviceId();
      final deviceName = await _getDeviceDisplayName();
      final body = jsonEncode(
        await _signedDevicePayload({
          'device_id': deviceId,
          'device_name': deviceName,
          'device_url': (deviceUrl ?? '').trim(),
          'note': trimmed,
        }),
      );
      final response = await _signedPost('/api/submit-feedback.php', body);
      if (response.statusCode != 200) return false;
      var data = response.data;
      if (data is String) {
        try {
          data = json.decode(data);
        } catch (_) {
          return false;
        }
      }
      return data is Map && data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// يجلب إشعارات اللوحة لهذا الجهاز ويدمجها في صندوق الوارد المحلي.
  /// فقط: All أو موجّه لهذا الجهاز، ومن وقت تثبيت/أول تشغيل التطبيق فما فوق.
  Future<int> syncNotificationInbox({int limit = 40}) async {
    try {
      final deviceId = await getDeviceId();
      if (deviceId.isEmpty) return 0;
      NotificationInboxService.instance.ensureLoaded();
      final since = NotificationInboxService.instance.inboxSince();
      final body = jsonEncode(
        await _signedDevicePayload({
          'device_id': deviceId,
          'limit': limit,
          'since': since.toUtc().toIso8601String(),
        }),
      );
      final response = await _signedPost('/api/device-notifications.php', body);
      if (response.statusCode != 200) return 0;
      var data = response.data;
      if (data is String) {
        try {
          data = json.decode(data);
        } catch (_) {
          return 0;
        }
      }
      if (data is! Map || data['success'] != true) return 0;
      final rawList = data['notifications'];
      if (rawList is! List) return 0;
      final mapped = <Map<String, dynamic>>[];
      for (final e in rawList) {
        if (e is Map) {
          mapped.add(Map<String, dynamic>.from(e));
        }
      }
      return NotificationInboxService.instance.mergeRemote(mapped);
    } catch (_) {
      return 0;
    }
  }

  Future<String> getDeviceId() async {
    try {
      return await StableDeviceIdService.instance
          .resolve()
          .timeout(const Duration(seconds: 4), onTimeout: () => '');
    } catch (e) {
      return '';
    }
  }
}
