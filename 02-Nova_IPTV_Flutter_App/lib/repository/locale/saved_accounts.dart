import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mehdi_iptv/helpers/helpers.dart';
import 'package:mehdi_iptv/repository/api/api.dart';
import 'package:mehdi_iptv/repository/models/user.dart';

/// حساب محفوظ للتبديل السريع بين عدة اشتراكات.
class SavedAccount {
  const SavedAccount({
    required this.id,
    required this.displayName,
    required this.username,
    required this.password,
    required this.serverUrl,
    required this.loginMethod,
    this.userJson,
    this.source,
    this.remoteId,
    this.avatarAsset,
    this.avatarFile,
  });

  final String id;
  final String displayName;
  final String username;
  final String password;
  final String serverUrl;
  final String loginMethod;
  final Map<String, dynamic>? userJson;
  /// `web` = مُزامَن من موقع Manage Playlist
  final String? source;
  final String? remoteId;
  /// Preset file name under assets/images/avatars (e.g. `cinema.png`).
  final String? avatarAsset;
  /// Absolute path to a custom image copied into app documents.
  final String? avatarFile;

  String get initial {
    final name = displayName.trim();
    if (name.isNotEmpty) return name[0].toUpperCase();
    return '?';
  }

  bool get hasCustomAvatar {
    final f = avatarFile?.trim() ?? '';
    if (f.isNotEmpty) return true;
    final a = avatarAsset?.trim() ?? '';
    return a.isNotEmpty;
  }

  /// معلومات عامة فقط — بدون سيرفر أو يوزر.
  String get publicSubtitle =>
      SavedAccountsRepository.publicAccountLabel(loginMethod);

  String get subtitle => SavedAccountsRepository.serverSubtitle(serverUrl);

  factory SavedAccount.fromJson(Map<String, dynamic> json) {
    return SavedAccount(
      id: (json['id'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      serverUrl: (json['serverUrl'] ?? '').toString(),
      loginMethod: (json['loginMethod'] ?? 'username_password').toString(),
      userJson:
          json['userJson'] is Map
              ? Map<String, dynamic>.from(json['userJson'] as Map)
              : null,
      source: json['source']?.toString(),
      remoteId: json['remoteId']?.toString(),
      avatarAsset: json['avatarAsset']?.toString(),
      avatarFile: json['avatarFile']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'username': username,
    'password': password,
    'serverUrl': serverUrl,
    'loginMethod': loginMethod,
    if (userJson != null) 'userJson': userJson,
    if (source != null && source!.isNotEmpty) 'source': source,
    if (remoteId != null && remoteId!.isNotEmpty) 'remoteId': remoteId,
    if (avatarAsset != null && avatarAsset!.isNotEmpty)
      'avatarAsset': avatarAsset,
    if (avatarFile != null && avatarFile!.isNotEmpty) 'avatarFile': avatarFile,
  };

  SavedAccount copyWith({
    String? displayName,
    String? username,
    String? password,
    String? serverUrl,
    String? loginMethod,
    Map<String, dynamic>? userJson,
    String? source,
    String? remoteId,
    String? avatarAsset,
    String? avatarFile,
    bool clearAvatar = false,
  }) {
    return SavedAccount(
      id: id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      password: password ?? this.password,
      serverUrl: serverUrl ?? this.serverUrl,
      loginMethod: loginMethod ?? this.loginMethod,
      userJson: userJson ?? this.userJson,
      source: source ?? this.source,
      remoteId: remoteId ?? this.remoteId,
      avatarAsset: clearAvatar ? null : (avatarAsset ?? this.avatarAsset),
      avatarFile: clearAvatar ? null : (avatarFile ?? this.avatarFile),
    );
  }
}

class SavedAccountsRepository {
  SavedAccountsRepository._();

  static GetStorage get _box => GetStorage();

  /// يمنع سباق الكتابة (كود → AuthUsePlaylist + auto AuthRegister).
  static Future<void>? _writeChain;

  static Future<T> _exclusive<T>(Future<T> Function() action) {
    final previous = _writeChain;
    final done = Completer<void>();
    _writeChain = done.future;
    return () async {
      try {
        if (previous != null) await previous;
        return await action();
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }();
  }

  static String accountIdFor(String serverUrl, String username) {
    final s = _canonicalHostKey(serverUrl);
    final u = username.trim().toLowerCase();
    return '$s::$u';
  }

  static String normalizeServerUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// مفتاح مضيف مستقر: يتجاهل فرق http/https على المنافذ الافتراضية.
  static String _canonicalHostKey(String serverUrl) {
    final hp = _hostPortKey(serverUrl);
    if (hp == null || hp.isEmpty) {
      return normalizeServerUrl(serverUrl).toLowerCase();
    }
    final parts = hp.split(':');
    final host = parts.first;
    final port = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 80;
    if (port == 80 || port == 443) return host;
    return hp;
  }

  static bool _hostPortKeysCompatible(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final partsA = a.split(':');
    final partsB = b.split(':');
    if (partsA.first != partsB.first) return false;
    final portA = int.tryParse(partsA.length > 1 ? partsA[1] : '') ?? 80;
    final portB = int.tryParse(partsB.length > 1 ? partsB[1] : '') ?? 80;
    const defaults = {80, 443};
    return defaults.contains(portA) && defaults.contains(portB);
  }

  /// نفس المضيف بغضّ النظر عن المنفذ (سبب شائع لازدواج Xtream ↔ رابط ويب).
  static bool _sameHostIgnorePort(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
    var hostA = a.split(':').first.toLowerCase();
    var hostB = b.split(':').first.toLowerCase();
    if (hostA.startsWith('www.')) hostA = hostA.substring(4);
    if (hostB.startsWith('www.')) hostB = hostB.substring(4);
    return hostA.isNotEmpty && hostA == hostB;
  }

  /// تطابق سيرفر للهوية: نفس host:port أو نفس المضيف (منفذ مختلف).
  static bool _hostsMatchForIdentity(String? a, String? b) {
    return _hostPortKeysCompatible(a, b) || _sameHostIgnorePort(a, b);
  }

  static String serverSubtitle(String serverUrl) {
    final trimmed = serverUrl.trim();
    if (trimmed.isEmpty) return 'account_server_xtream'.tr;
    try {
      final uri = Uri.parse(trimmed);
      final host = uri.host;
      if (host.isNotEmpty) {
        return '${'account_server_xtream'.tr} · $host';
      }
    } catch (_) {}
    return 'account_server_xtream'.tr;
  }

  /// تسمية عامة لنوع الحساب دون كشف السيرفر أو بيانات الدخول.
  static String publicAccountLabel(String loginMethod) {
    switch (loginMethod) {
      case 'playlist_code':
        return 'account_type_playlist'.tr;
      default:
        return 'account_type_subscription'.tr;
    }
  }

  static List<SavedAccount> listAccounts() {
    final raw = _box.read(kStorageSavedAccounts);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => SavedAccount.fromJson(Map<String, dynamic>.from(e)))
        .where((a) => a.id.isNotEmpty)
        .toList();
  }

  static String? get activeAccountId =>
      (_box.read(kStorageActiveAccountId) as String?)?.trim();

  static SavedAccount? getActiveAccount() {
    final id = activeAccountId;
    if (id == null || id.isEmpty) return null;
    for (final a in listAccounts()) {
      if (a.id == id) return a;
    }
    return null;
  }

  static SavedAccount? findById(String id) {
    for (final a in listAccounts()) {
      if (a.id == id) return a;
    }
    return null;
  }

  static Future<void> _writeAccounts(List<SavedAccount> accounts) async {
    await _box.write(
      kStorageSavedAccounts,
      accounts.map((e) => e.toJson()).toList(),
    );
  }

  static Future<void> setActiveAccountId(String? id) async {
    if (id == null || id.trim().isEmpty) {
      await _box.remove(kStorageActiveAccountId);
    } else {
      await _box.write(kStorageActiveAccountId, id.trim());
    }
  }

  /// يفضّل اسم الحساب الجديد إن كان مخصّصاً؛ وإلا يحافظ على القديم؛ وإلا اليوزر.
  static String _preferDisplayName(
    String? existingName,
    String incomingName,
    String username,
  ) {
    final existing = (existingName ?? '').trim();
    final incoming = incomingName.trim();
    final user = username.trim();
    final incomingIsCustom =
        incoming.isNotEmpty &&
        (user.isEmpty || incoming.toLowerCase() != user.toLowerCase());
    if (incomingIsCustom) return incoming;
    if (existing.isNotEmpty) return existing;
    if (incoming.isNotEmpty) return incoming;
    return user.isNotEmpty ? user : 'Account';
  }

  static String _decodeSecret(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    try {
      return Uri.decodeComponent(t.replaceAll('+', ' ')).trim();
    } catch (_) {
      return t;
    }
  }

  /// يوزر/باس/host:port بعد التنظيف + استخراج من get.php / userJson.
  static ({String user, String pass, String hostPort})? _resolveLogin(
    SavedAccount a,
  ) {
    var user = _decodeSecret(a.username);
    var pass = _decodeSecret(a.password);
    var server = a.serverUrl;
    final fromUrl = parseXtreamCredentialsFromUrl(a.serverUrl);
    if (fromUrl != null) {
      if (user.isEmpty) user = _decodeSecret(fromUrl.username);
      if (pass.isEmpty) pass = _decodeSecret(fromUrl.password);
      server = fromUrl.serverBase;
    }
    if ((user.isEmpty || pass.isEmpty) && a.userJson != null) {
      try {
        final uiRaw = a.userJson!['user_info'] ?? a.userJson!['userInfo'];
        if (uiRaw is Map) {
          final ui = Map<String, dynamic>.from(uiRaw);
          if (user.isEmpty) {
            user = _decodeSecret((ui['username'] ?? '').toString());
          }
          if (pass.isEmpty) {
            pass = _decodeSecret((ui['password'] ?? '').toString());
          }
        }
        final siRaw = a.userJson!['server_info'] ?? a.userJson!['serverInfo'];
        if (siRaw is Map && server.trim().isEmpty) {
          final si = Map<String, dynamic>.from(siRaw);
          server = (si['server_url'] ?? si['url'] ?? '').toString();
        }
      } catch (_) {}
    }
    user = user.toLowerCase();
    final hp = _hostPortKey(server);
    if (user.isEmpty || hp == null) return null;
    return (user: user, pass: pass, hostPort: hp);
  }

  static bool _sameAccountIdentity(SavedAccount a, SavedAccount b) {
    if (identical(a, b) || a.id == b.id) return true;

    final raId = (a.remoteId ?? '').trim();
    final rbId = (b.remoteId ?? '').trim();
    if (raId.isNotEmpty && raId == rbId) return true;

    final ia = _stableCredentialId(a);
    final ib = _stableCredentialId(b);
    if (ia != null && ib != null && ia == ib) return true;

    final ra = _resolveLogin(a);
    final rb = _resolveLogin(b);
    if (ra != null && rb != null) {
      if (ra.user != rb.user) return false;
      if (!_passwordsCompatible(ra.pass, rb.pass)) return false;
      // نفس اليوزر+الباس+المضيف = نفس البروفايل (حتى لو المنفذ/شكل الرابط اختلف)
      if (_hostsMatchForIdentity(ra.hostPort, rb.hostPort)) return true;
      // نفس الاعتمادات كاملة حتى لو اختلف CDN/دومين اللوحة
      if (ra.pass.isNotEmpty && rb.pass.isNotEmpty && ra.pass == rb.pass) {
        return true;
      }
      return false;
    }
    // أحدهما فيه يوزر والآخر قائمة/ويب على نفس السيرفر بلا اعتمادات متعارضة
    if (ra != null && rb == null) {
      return _resolvedMatchesUnresolved(ra, b);
    }
    if (rb != null && ra == null) {
      return _resolvedMatchesUnresolved(rb, a);
    }

    // يوزر ظاهر متطابق (displayName أو username) + باس متوافق
    final ua = _visibleUsername(a);
    final ub = _visibleUsername(b);
    if (ua.isNotEmpty && ua == ub) {
      if (_passwordsCompatible(a.password, b.password)) {
        final ha = _hostPortKey(a.serverUrl);
        final hb = _hostPortKey(b.serverUrl);
        if (ha == null || hb == null || _hostsMatchForIdentity(ha, hb)) {
          return true;
        }
        if (_serversEquivalent(a.serverUrl, b.serverUrl)) return true;
        final pa = _decodeSecret(a.password);
        final pb = _decodeSecret(b.password);
        if (pa.isNotEmpty && pa == pb) return true;
      }
    }

    // قوائم بلا اعتمادات: نفس مسار الرابط
    final ka = _playlistIdentityKey(a.serverUrl);
    final kb = _playlistIdentityKey(b.serverUrl);
    return ka != null && kb != null && ka == kb;
  }

  /// يوزر للمقارنة: من الاعتمادات أو الحقل أو اسم العرض الرقمي.
  static String _visibleUsername(SavedAccount a) {
    final r = _resolveLogin(a);
    if (r != null && r.user.isNotEmpty) return r.user;
    final u = _decodeSecret(a.username).toLowerCase();
    if (u.isNotEmpty) return u;
    final d = a.displayName.trim().toLowerCase();
    if (d.isEmpty || d == 'account' || d == 'playlist') return '';
    return d;
  }

  /// معرّف ثابت: مضيف قانوني + يوزر — يدمج http/https ونسخ web/يدوي.
  /// يتجاهل المنفذ حتى لا يُنشأ صفّان لنفس الاشتراك (مثلاً :8080 مقابل بدون منفذ).
  static String? _stableCredentialId(SavedAccount a) {
    final r = _resolveLogin(a);
    if (r == null || r.user.isEmpty) return null;
    final host = r.hostPort.split(':').first.toLowerCase();
    final clean = host.startsWith('www.') ? host.substring(4) : host;
    if (clean.isEmpty) return null;
    return '$clean::${r.user}';
  }

  /// حساب فيه يوزر/باس يطابق صف ويب/قائمة على نفس المضيف دون يوزر متعارض.
  static bool _resolvedMatchesUnresolved(
    ({String user, String pass, String hostPort}) resolved,
    SavedAccount other,
  ) {
    final otherUser = _decodeSecret(other.username).toLowerCase();
    if (otherUser.isNotEmpty && otherUser != resolved.user) return false;
    final otherPass = _decodeSecret(other.password);
    if (!_passwordsCompatible(resolved.pass, otherPass)) return false;
    final otherHp = _hostPortKey(other.serverUrl);
    if (_hostsMatchForIdentity(resolved.hostPort, otherHp)) return true;
    return _serversEquivalent(
      'http://${resolved.hostPort}',
      other.serverUrl,
    );
  }

  static int _indexOfSameCredentials(
    List<SavedAccount> list, {
    required String username,
    required String password,
  }) {
    final u = _decodeSecret(username).toLowerCase();
    final p = _decodeSecret(password);
    if (u.isEmpty || p.isEmpty) return -1;
    return list.indexWhere((e) {
      final r = _resolveLogin(e);
      if (r == null) return false;
      return r.user == u && _passwordsCompatible(r.pass, p);
    });
  }

  /// نفس اليوزر + الباس + نفس السيرفر (حتى لو اختلف شكل الرابط).
  static int _indexOfSameXtreamIdentity(
    List<SavedAccount> list, {
    required String username,
    required String password,
    required String serverUrl,
    String? excludeId,
  }) {
    final u = _decodeSecret(username).toLowerCase();
    final p = _decodeSecret(password);
    if (u.isEmpty) return -1;
    final probe = SavedAccount(
      id: '_probe',
      displayName: u,
      username: u,
      password: p,
      serverUrl: serverUrl,
      loginMethod: 'username_password',
    );
    return list.indexWhere((e) {
      if (excludeId != null && e.id == excludeId) return false;
      return _sameAccountIdentity(probe, e);
    });
  }

  static bool _passwordsCompatible(String a, String b) {
    final pa = _decodeSecret(a);
    final pb = _decodeSecret(b);
    if (pa.isEmpty && pb.isEmpty) return true;
    if (pa.isEmpty || pb.isEmpty) return true;
    return pa == pb;
  }

  static bool _serversEquivalent(String a, String b) {
    final na = normalizeServerUrl(a).toLowerCase();
    final nb = normalizeServerUrl(b).toLowerCase();
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    if (_playlistUrlsLikelySame(na, nb)) return true;
    final ha = _hostPortKey(na);
    final hb = _hostPortKey(nb);
    return _hostsMatchForIdentity(ha, hb);
  }

  /// فهرس حساب قائمة/ويب بنفس الرابط (أو مضيف Xtream المستخرج منه).
  static int _indexOfSamePlaylistUrl(
    List<SavedAccount> list,
    String serverUrl, {
    String? preferUsername,
  }) {
    final url = normalizeServerUrl(serverUrl);
    if (url.isEmpty) return -1;
    final urlLower = url.toLowerCase();
    final preferUser = _decodeSecret(preferUsername ?? '').toLowerCase();

    int? webMatch;
    int? credMatch;
    int? otherMatch;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      final existing = normalizeServerUrl(e.serverUrl).toLowerCase();
      if (existing.isEmpty) continue;
      final same = existing == urlLower ||
          _playlistUrlsLikelySame(existing, urlLower) ||
          _serversEquivalent(existing, urlLower);
      if (!same) continue;

      final otherUser =
          _resolveLogin(e)?.user ?? _decodeSecret(e.username).toLowerCase();
      if (preferUser.isNotEmpty &&
          otherUser.isNotEmpty &&
          otherUser != preferUser) {
        continue;
      }

      if (e.source == 'web' || e.id.startsWith('web:')) {
        webMatch ??= i;
      } else if (preferUser.isNotEmpty && otherUser == preferUser) {
        credMatch ??= i;
      } else if (e.loginMethod == 'playlist_code' || otherUser.isEmpty) {
        otherMatch ??= i;
      } else if (preferUser.isNotEmpty) {
        // اشتراك يدوي على نفس المضيف بدون يوزر محفوظ بعد — مرشّح احتياطي
        credMatch ??= i;
      }
    }
    return webMatch ?? credMatch ?? otherMatch ?? -1;
  }

  /// تطابق رابط M3U كامل مع سيرفر Xtream الأساسي المستخرج منه (سبب شائع للازدواج).
  static bool _playlistUrlsLikelySame(String a, String b) {
    if (a == b) return true;
    try {
      final ua = Uri.parse(a);
      final ub = Uri.parse(b);
      if (ua.host.isEmpty || ub.host.isEmpty) return false;
      if (ua.host.toLowerCase() != ub.host.toLowerCase()) return false;
      final portA = ua.hasPort ? ua.port : (ua.scheme == 'https' ? 443 : 80);
      final portB = ub.hasPort ? ub.port : (ub.scheme == 'https' ? 443 : 80);
      if (portA != portB) {
        const defaults = {80, 443};
        if (!(defaults.contains(portA) && defaults.contains(portB))) {
          return false;
        }
      }

      final pathA = ua.path.toLowerCase();
      final pathB = ub.path.toLowerCase();
      final aIsHostOnly = pathA.isEmpty || pathA == '/';
      final bIsHostOnly = pathB.isEmpty || pathB == '/';
      // سيرفر فقط ↔ رابط get.php على نفس المضيف
      if (aIsHostOnly || bIsHostOnly) return true;

      if (pathA == pathB) {
        // نفس المسار: إن اختلفا في username فهما قائمتان مختلفتان
        final userA = ua.queryParameters['username'] ?? '';
        final userB = ub.queryParameters['username'] ?? '';
        if (userA.isNotEmpty && userB.isNotEmpty) {
          return userA.toLowerCase() == userB.toLowerCase();
        }
        return a == b;
      }
    } catch (_) {}
    return false;
  }

  /// قاعدة الدمج الوحيدة:
  /// نفس السيرفر (host:port) + نفس اليوزر + نفس الباس
  /// = نفس البروفايل — بغضّ النظر عن طريقة الدخول (Xtream / M3U / Code / Web).
  static Future<void> upsertFromLogin({
    required UserModel user,
    required String displayName,
    required String loginMethod,
    required String serverDomain,
    bool forceNewProfile = false,
  }) {
    return _exclusive(
      () => _upsertFromLoginImpl(
        user: user,
        displayName: displayName,
        loginMethod: loginMethod,
        serverDomain: serverDomain,
        forceNewProfile: forceNewProfile,
      ),
    );
  }

  static Future<void> _upsertFromLoginImpl({
    required UserModel user,
    required String displayName,
    required String loginMethod,
    required String serverDomain,
    bool forceNewProfile = false,
  }) async {
    // 1) استخرج الاعتمادات من الموديل أو من رابط get.php
    var username = _decodeSecret(user.userInfo?.username ?? '');
    var password = _decodeSecret(user.userInfo?.password ?? '');
    var serverUrl =
        serverDomain.trim().isNotEmpty
            ? normalizeServerUrl(serverDomain)
            : normalizeServerUrl(user.serverInfo?.serverUrl ?? '');

    final fromDomain = parseXtreamCredentialsFromUrl(
      serverDomain.trim().isNotEmpty ? serverDomain : serverUrl,
    );
    if (fromDomain != null) {
      if (username.isEmpty) username = _decodeSecret(fromDomain.username);
      if (password.isEmpty) password = _decodeSecret(fromDomain.password);
      serverUrl = normalizeServerUrl(fromDomain.serverBase);
    }

    final list = listAccounts();

    // 2) ابحث عن أي حساب سابق بنفس السيرفر+يوزر+باس (أي طريقة دخول)
    var idx = -1;
    if (username.isNotEmpty) {
      idx = _indexOfSameXtreamIdentity(
        list,
        username: username,
        password: password,
        serverUrl: serverUrl,
      );
    }

    // قوائم بلا يوزر: طابق بالرابط فقط
    if (idx < 0 && username.isEmpty && serverUrl.isNotEmpty) {
      idx = _indexOfSamePlaylistUrl(list, serverUrl);
    }

    final tentativeId = accountIdFor(
      serverUrl,
      username.isNotEmpty ? username : displayName,
    );
    if (idx < 0) {
      idx = list.indexWhere((e) => e.id == tentativeId);
    }

    final existing = idx >= 0 ? list[idx] : null;

    // 3) forceNewProfile لا يتجاوز قاعدة السيرفر+يوزر+باس
    final id = existing?.id ?? tentativeId;

    final mergeIntoWeb =
        existing != null &&
        (existing.source == 'web' || existing.id.startsWith('web:'));

    final name = _preferDisplayName(
      existing?.displayName,
      displayName,
      username,
    );

    final keepServerUrl =
        (mergeIntoWeb && existing.serverUrl.trim().isNotEmpty)
            ? normalizeServerUrl(existing.serverUrl)
            : (serverUrl.isNotEmpty
                ? serverUrl
                : (existing?.serverUrl ?? ''));

    final resolvedUser =
        username.isNotEmpty
            ? username
            : _decodeSecret(existing?.username ?? '');
    final resolvedPass =
        password.isNotEmpty
            ? password
            : _decodeSecret(existing?.password ?? '');

    final keptMethod =
        mergeIntoWeb
            ? (existing.loginMethod.isNotEmpty
                ? existing.loginMethod
                : 'playlist_code')
            : (existing != null &&
                    existing.loginMethod.isNotEmpty &&
                    resolvedUser.isNotEmpty
                ? existing.loginMethod
                : loginMethod);

    final updated = SavedAccount(
      id: id,
      displayName: name,
      username: resolvedUser,
      password: resolvedPass,
      serverUrl: keepServerUrl,
      loginMethod: keptMethod,
      userJson: user.toJson(),
      source: existing?.source,
      remoteId: existing?.remoteId,
      avatarAsset: existing?.avatarAsset,
      avatarFile: existing?.avatarFile,
    );

    if (idx >= 0) {
      list[idx] = updated;
    } else {
      list.add(updated);
    }

    // 4) احذف أي صف آخر بنفس السيرفر+يوزر+باس
    if (resolvedUser.isNotEmpty) {
      list.removeWhere((e) {
        if (e.id == id) return false;
        return _sameAccountIdentity(updated, e);
      });
    }

    final deduped = _collapseDuplicateIdentities(list, preferId: id);
    await _writeAccounts(deduped);
    final stillThere = deduped.any((e) => e.id == id);
    await setActiveAccountId(
      stillThere ? id : (deduped.isNotEmpty ? deduped.first.id : id),
    );
  }

  /// مفتاح مضيف:منفذ موحّد للمقارنة.
  static String? _hostPortKey(String serverUrl) {
    try {
      final u = Uri.parse(normalizeServerUrl(serverUrl));
      if (u.host.isEmpty) return null;
      var host = u.host.toLowerCase();
      if (host.startsWith('www.')) host = host.substring(4);
      final port = u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);
      return '$host:$port';
    } catch (_) {
      return null;
    }
  }

  static String? _playlistIdentityKey(String raw) {
    final n = normalizeServerUrl(raw).toLowerCase();
    if (n.isEmpty) return null;
    try {
      final u = Uri.parse(n);
      if (u.host.isEmpty) return n;
      final hostKey = _canonicalHostKey(n);
      final user =
          _decodeSecret(u.queryParameters['username'] ?? '').toLowerCase();
      if (user.isNotEmpty) return '$hostKey|u=$user';
      var path = u.path.toLowerCase();
      while (path.endsWith('/') && path.length > 1) {
        path = path.substring(0, path.length - 1);
      }
      return '$hostKey$path';
    } catch (_) {
      return n;
    }
  }

  /// يدمج الصفوف المكررة: نفس اليوزر + نفس الباس + نفس السيرفر
  /// (أو نفس رابط القائمة بلا اعتمادات).
  static List<SavedAccount> _collapseDuplicateIdentities(
    List<SavedAccount> input, {
    String? preferId,
  }) {
    if (input.length < 2) return input;
    final out = List<SavedAccount>.from(input);
    var guard = 0;
    while (guard++ < 64) {
      var mergedAny = false;
      for (var i = 0; i < out.length; i++) {
        final a = out[i];
        final dupIndexes = <int>[];
        for (var j = 0; j < out.length; j++) {
          if (j == i) continue;
          if (!_sameAccountIdentity(a, out[j])) continue;
          dupIndexes.add(j);
        }
        if (dupIndexes.isEmpty) continue;

        final candidates = <SavedAccount>[a, ...dupIndexes.map((j) => out[j])];
        SavedAccount keep = a;
        for (final c in candidates) {
          if (c.source == 'web' || c.id.startsWith('web:')) {
            keep = c;
            break;
          }
        }
        if (keep.source != 'web' && !keep.id.startsWith('web:')) {
          if (preferId != null) {
            for (final c in candidates) {
              if (c.id == preferId) {
                keep = c;
                break;
              }
            }
          } else {
            final active = activeAccountId;
            if (active != null) {
              for (final c in candidates) {
                if (c.id == active) {
                  keep = c;
                  break;
                }
              }
            }
          }
        }

        var merged = keep;
        for (final c in candidates) {
          if (c.id == keep.id) continue;
          final resolved = _resolveLogin(merged) ?? _resolveLogin(c);
          final mergedUser =
              resolved?.user.isNotEmpty == true
                  ? (merged.username.trim().isNotEmpty
                      ? merged.username.trim()
                      : (c.username.trim().isNotEmpty
                          ? c.username.trim()
                          : resolved!.user))
                  : (merged.username.trim().isNotEmpty
                      ? merged.username
                      : c.username);
          final mergedPass =
              merged.password.trim().isNotEmpty
                  ? merged.password.trim()
                  : (c.password.trim().isNotEmpty
                      ? c.password.trim()
                      : (resolved?.pass ?? ''));
          merged = SavedAccount(
            id: keep.id,
            displayName: _preferDisplayName(
              merged.displayName,
              c.displayName,
              mergedUser,
            ),
            username: mergedUser,
            password: mergedPass,
            serverUrl:
                (keep.source == 'web' && keep.serverUrl.trim().isNotEmpty)
                    ? keep.serverUrl
                    : (merged.serverUrl.trim().isNotEmpty
                        ? merged.serverUrl
                        : c.serverUrl),
            loginMethod: merged.loginMethod,
            userJson: merged.userJson ?? c.userJson,
            source: keep.source ?? c.source,
            remoteId: keep.remoteId ?? c.remoteId,
            avatarAsset: merged.avatarAsset ?? c.avatarAsset ?? keep.avatarAsset,
            avatarFile: merged.avatarFile ?? c.avatarFile ?? keep.avatarFile,
          );
        }

        final removeIds =
            candidates.where((c) => c.id != keep.id).map((c) => c.id).toSet();
        out.removeWhere((e) => removeIds.contains(e.id));
        final keepAt = out.indexWhere((e) => e.id == keep.id);
        if (keepAt >= 0) out[keepAt] = merged;
        mergedAny = true;
        break;
      }
      if (!mergedAny) break;
    }
    return out;
  }

  /// تنظيف الازدواج الحالي (يُستدعى من Manage Accounts وعند كل دخول).
  static Future<int> dedupeEquivalentAccounts() {
    return _exclusive(_dedupeEquivalentAccountsImpl);
  }

  static Future<int> _dedupeEquivalentAccountsImpl() async {
    final before = listAccounts();
    // املأ اليوزر/الباس من الروابط ثم ادمج
    final normalized = before.map((a) {
      final r = _resolveLogin(a);
      if (r == null) return a;
      return a.copyWith(
        username: a.username.trim().isNotEmpty ? a.username : r.user,
        password: a.password.trim().isNotEmpty ? a.password : r.pass,
        serverUrl: (() {
          final fromUrl = parseXtreamCredentialsFromUrl(a.serverUrl);
          if (fromUrl != null) {
            return normalizeServerUrl(fromUrl.serverBase);
          }
          return a.serverUrl;
        })(),
      );
    }).toList();
    final after = _collapseDuplicateIdentities(normalized);
    final beforeIds = before.map((e) => e.id).toSet();
    final afterIds = after.map((e) => e.id).toSet();
    final changed =
        beforeIds.length != afterIds.length ||
        !beforeIds.containsAll(afterIds) ||
        before.length != after.length;
    if (!changed) {
      // حتى بدون حذف صفوف: احفظ التطبيع إن تغيّر محتوى الحقول
      var contentChanged = false;
      if (before.length == after.length) {
        for (var i = 0; i < before.length; i++) {
          final b = before[i];
          final a = after.firstWhere(
            (e) => e.id == b.id,
            orElse: () => b,
          );
          if (a.username != b.username ||
              a.password != b.password ||
              a.serverUrl != b.serverUrl) {
            contentChanged = true;
            break;
          }
        }
      }
      if (!contentChanged) return 0;
    }
    await _writeAccounts(after);
    final active = activeAccountId;
    if (active != null && after.every((e) => e.id != active)) {
      await setActiveAccountId(after.isNotEmpty ? after.first.id : null);
    }
    return before.length - after.length;
  }

  static Future<void> migrateCurrentUserIfNeeded() async {
    final user = LocaleApi.getUserSync();
    if (user == null) {
      await dedupeEquivalentAccounts();
      return;
    }
    final username = (user.userInfo?.username ?? '').trim();
    final password = (user.userInfo?.password ?? '').trim();
    final serverUrl = normalizeServerUrl(user.serverInfo?.serverUrl ?? '');
    if (serverUrl.isEmpty && username.isEmpty) {
      await dedupeEquivalentAccounts();
      return;
    }

    final id = accountIdFor(
      serverUrl,
      username.isNotEmpty ? username : 'playlist',
    );
    if (findById(id) != null) {
      if (activeAccountId == null) {
        await setActiveAccountId(id);
      }
      await dedupeEquivalentAccounts();
      return;
    }

    // حساب ويب نشط أو بنفس رابط القائمة — لا تنشئ صفّاً ثانياً
    final active = activeAccountId;
    if (active != null && active.startsWith('web:') && findById(active) != null) {
      final method =
          (_box.read(kStorageLoginMethod) as String?) ?? 'playlist_code';
      final existing = findById(active)!;
      await upsertFromLogin(
        user: user,
        displayName: existing.displayName,
        loginMethod: method,
        serverDomain: existing.serverUrl.isNotEmpty
            ? existing.serverUrl
            : serverUrl,
      );
      await dedupeEquivalentAccounts();
      return;
    }

    final list = listAccounts();
    SavedAccount? existing;
    if (username.isNotEmpty) {
      final byIdentity = _indexOfSameXtreamIdentity(
        list,
        username: username,
        password: password,
        serverUrl: serverUrl,
      );
      if (byIdentity >= 0) existing = list[byIdentity];
    }
    if (existing == null) {
      final byUrl = _indexOfSamePlaylistUrl(
        list,
        serverUrl,
        preferUsername: username,
      );
      if (byUrl >= 0) {
        existing = list[byUrl];
      } else {
        final byCreds = _indexOfSameCredentials(
          list,
          username: username,
          password: password,
        );
        if (byCreds >= 0) existing = list[byCreds];
      }
    }
    if (existing != null) {
      final method =
          (_box.read(kStorageLoginMethod) as String?) ?? existing.loginMethod;
      await upsertFromLogin(
        user: user,
        displayName: existing.displayName,
        loginMethod: method,
        serverDomain: existing.source == 'web' && existing.serverUrl.isNotEmpty
            ? existing.serverUrl
            : (serverUrl.isNotEmpty ? serverUrl : existing.serverUrl),
      );
      await dedupeEquivalentAccounts();
      return;
    }

    final method =
        (_box.read(kStorageLoginMethod) as String?) ?? 'username_password';
    await upsertFromLogin(
      user: user,
      displayName: username.isNotEmpty ? username : 'Playlist',
      loginMethod: method,
      serverDomain: serverUrl,
    );
    await dedupeEquivalentAccounts();
  }

  static Future<void> removeById(String id) async {
    final list = listAccounts()..removeWhere((e) => e.id == id);
    await _writeAccounts(list);
    if (activeAccountId == id) {
      await setActiveAccountId(null);
    }
  }

  static Future<bool> renameById(String id, String newDisplayName) async {
    final name = newDisplayName.trim();
    if (name.isEmpty) return false;
    final list = listAccounts();
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return false;
    list[idx] = list[idx].copyWith(displayName: name);
    await _writeAccounts(list);
    return true;
  }

  /// Set preset avatar (`cinema.png`) or clear when [assetFileName] is empty.
  static Future<bool> setAvatarAssetById(String id, String? assetFileName) async {
    final list = listAccounts();
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return false;
    final name = (assetFileName ?? '').trim();
    if (name.isEmpty) {
      list[idx] = list[idx].copyWith(clearAvatar: true);
    } else {
      list[idx] = list[idx].copyWith(
        avatarAsset: name,
        avatarFile: null,
        clearAvatar: false,
      );
      // copyWith keeps old avatarFile if we only pass avatarAsset — force clear file
      final a = list[idx];
      list[idx] = SavedAccount(
        id: a.id,
        displayName: a.displayName,
        username: a.username,
        password: a.password,
        serverUrl: a.serverUrl,
        loginMethod: a.loginMethod,
        userJson: a.userJson,
        source: a.source,
        remoteId: a.remoteId,
        avatarAsset: name,
        avatarFile: null,
      );
    }
    await _writeAccounts(list);
    return true;
  }

  /// Store a custom image path for the account (absolute file path).
  static Future<bool> setAvatarFileById(String id, String filePath) async {
    final path = filePath.trim();
    if (path.isEmpty) return false;
    final list = listAccounts();
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return false;
    final a = list[idx];
    list[idx] = SavedAccount(
      id: a.id,
      displayName: a.displayName,
      username: a.username,
      password: a.password,
      serverUrl: a.serverUrl,
      loginMethod: a.loginMethod,
      userJson: a.userJson,
      source: a.source,
      remoteId: a.remoteId,
      avatarAsset: null,
      avatarFile: path,
    );
    await _writeAccounts(list);
    return true;
  }

  /// مزامنة قوائم موقع Manage Playlist إلى Manage Accounts (دمج، بدون حذف اليدوي).
  static Future<void> syncFromWebPlaylists(
    List<Map<String, dynamic>> remote,
  ) {
    return _exclusive(() => _syncFromWebPlaylistsImpl(remote));
  }

  static Future<void> _syncFromWebPlaylistsImpl(
    List<Map<String, dynamic>> remote,
  ) async {
    final list = listAccounts();
    final keepIds = <String>{};

    for (final raw in remote) {
      final remoteId = (raw['id'] ?? '').toString().trim();
      final name = (raw['name'] ?? '').toString().trim();
      final url = normalizeServerUrl((raw['m3u_url'] ?? '').toString());
      if (remoteId.isEmpty || remoteId == '0' || url.isEmpty) continue;
      keepIds.add(remoteId);

      final id = 'web:$remoteId';
      final display = name.isNotEmpty ? name : 'Playlist';
      final urlKey = url.toLowerCase();
      final user = UserModel(
        userInfo: UserInfo(
          username: '',
          password: '',
          message: '',
          auth: '1',
          status: 'Active',
          expDate: null,
          isTrial: '',
          activeCons: '',
          createdAt: '',
          maxConnections: '',
          allowedOutputFormats: null,
        ),
        serverInfo: ServerInfo(
          serverUrl: url,
          url: '',
          port: '',
          httpsPort: '',
          serverProtocol: '',
          rtmpPort: '',
          timezone: '',
          timestampNow: '',
          timeNow: '',
          process: '',
        ),
      );

      final account = SavedAccount(
        id: id,
        displayName: display,
        username: '',
        password: '',
        serverUrl: url,
        loginMethod: 'playlist_code',
        userJson: user.toJson(),
        source: 'web',
        remoteId: remoteId,
      );

      // اعتمادات الرابط من الموقع (إن وُجدت) لمطابقة حساب التطبيق اليدوي
      final urlCreds = parseXtreamCredentialsFromUrl(url);

      var idx = list.indexWhere((e) => e.id == id || e.remoteId == remoteId);

      // العكس: حساب من التطبيق بنفس السيرفر + نفس اليوزر/الباس → ادمجه مع قائمة الموقع
      if (idx < 0 && urlCreds != null) {
        idx = _indexOfSameXtreamIdentity(
          list,
          username: urlCreds.username,
          password: urlCreds.password,
          serverUrl: urlCreds.serverBase,
          excludeId: id,
        );
        if (idx >= 0 && list[idx].source == 'web') idx = -1;
      }

      if (idx < 0) {
        // ادمج حسابات قائمة/ويب أو يدوي على نفس المضيف (بدون تخمين بين عدة يوزرات)
        final webHost = _hostPortKey(url);
        idx = list.indexWhere((e) {
          if (e.id == id) return false;
          if (e.source == 'web') return false;

          final other = normalizeServerUrl(e.serverUrl).toLowerCase();
          if (other.isEmpty) return false;
          final sameUrl =
              other == urlKey || _playlistUrlsLikelySame(other, urlKey);
          final sameHost = _hostsMatchForIdentity(webHost, _hostPortKey(other));

          final isManualXtream =
              e.loginMethod == 'username_password' &&
              e.username.trim().isNotEmpty;

          if (isManualXtream) {
            if (urlCreds != null) {
              return _sameAccountIdentity(
                e,
                SavedAccount(
                  id: '_web_probe',
                  displayName: '',
                  username: urlCreds.username,
                  password: urlCreds.password,
                  serverUrl: urlCreds.serverBase,
                  loginMethod: 'playlist_code',
                ),
              );
            }
            // رابط ويب بلا اعتمادات: ادمج فقط إن كان هناك حساب يدوي واحد على نفس المضيف
            if (!sameHost && !sameUrl) return false;
            final manualsOnHost = list.where((x) {
              if (x.source == 'web') return false;
              if (x.username.trim().isEmpty) return false;
              return _hostsMatchForIdentity(
                webHost,
                _hostPortKey(x.serverUrl),
              );
            }).toList();
            return manualsOnHost.length == 1 && manualsOnHost.first.id == e.id;
          }

          if (!sameUrl && !sameHost) return false;
          return e.loginMethod == 'playlist_code' || e.username.trim().isEmpty;
        });
      }

      if (idx >= 0) {
        final existing = list[idx];
        final mergedUsername =
            existing.username.trim().isNotEmpty
                ? existing.username
                : (urlCreds?.username ?? '');
        final mergedPassword =
            existing.password.isNotEmpty
                ? existing.password
                : (urlCreds?.password ?? '');
        final oldId = existing.id;
        list[idx] = SavedAccount(
          id: id,
          displayName: _preferDisplayName(
            existing.displayName,
            display,
            mergedUsername,
          ),
          username: mergedUsername,
          password: mergedPassword,
          serverUrl: url,
          loginMethod: 'playlist_code',
          userJson: existing.userJson ?? account.userJson,
          source: 'web',
          remoteId: remoteId,
          avatarAsset: existing.avatarAsset,
          avatarFile: existing.avatarFile,
        );
        // إن كان النشط يشير للمفتاح اليدوي القديم — حوّله لمعرّف الويب
        if (activeAccountId == oldId && oldId != id) {
          await setActiveAccountId(id);
        }
      } else {
        list.add(account);
      }

      // أزل بقايا مزدوجة: قوائم فارغة أو نفس الاعتمادات بعد الدمج مع ويب
      list.removeWhere((e) {
        if (e.id == id) return false;
        final other = normalizeServerUrl(e.serverUrl).toLowerCase();
        if (other.isEmpty) return false;
        final sameUrl =
            other == urlKey || _playlistUrlsLikelySame(other, urlKey);
        final sameHost = _hostsMatchForIdentity(
          _hostPortKey(url),
          _hostPortKey(other),
        );
        if (!sameUrl && urlCreds != null) {
          final base = normalizeServerUrl(urlCreds.serverBase).toLowerCase();
          final sameCredHost =
              other == base ||
              _playlistUrlsLikelySame(other, base) ||
              _serversEquivalent(other, base) ||
              _hostsMatchForIdentity(
                _hostPortKey(other),
                _hostPortKey(base),
              );
          if (!sameCredHost) return false;
          return _sameAccountIdentity(
            e,
            SavedAccount(
              id: '_web_probe',
              displayName: '',
              username: urlCreds.username,
              password: urlCreds.password,
              serverUrl: urlCreds.serverBase,
              loginMethod: 'playlist_code',
            ),
          );
        }
        if (!sameUrl && !sameHost) return false;
        if (e.loginMethod == 'username_password' &&
            e.username.trim().isNotEmpty) {
          // احذف اليدوي إن طابق اعتمادات الرابط، أو إن دُمج مسبقاً في صف الويب
          if (urlCreds != null) {
            return _sameAccountIdentity(
              e,
              SavedAccount(
                id: '_web_probe',
                displayName: '',
                username: urlCreds.username,
                password: urlCreds.password,
                serverUrl: urlCreds.serverBase,
                loginMethod: 'playlist_code',
              ),
            );
          }
          SavedAccount? webRow;
          for (final x in list) {
            if (x.id == id) {
              webRow = x;
              break;
            }
          }
          if (webRow != null && _sameAccountIdentity(e, webRow)) return true;
          return false;
        }
        return e.source == 'web' ||
            e.loginMethod == 'playlist_code' ||
            e.username.trim().isEmpty;
      });
    }

    list.removeWhere(
      (e) =>
          e.source == 'web' &&
          (e.remoteId == null ||
              e.remoteId!.isEmpty ||
              !keepIds.contains(e.remoteId)),
    );

    final collapsed = _collapseDuplicateIdentities(list);
    await _writeAccounts(collapsed);

    // أصلح activeAccountId إن كان يشير لنسخة قديمة دُمجت
    final active = activeAccountId;
    if (active != null && collapsed.every((e) => e.id != active)) {
      String? replacementId;
      for (final e in collapsed) {
        if (e.source == 'web' && e.id.startsWith('web:')) {
          replacementId = e.id;
          break;
        }
      }
      replacementId ??= collapsed.isNotEmpty ? collapsed.first.id : null;
      await setActiveAccountId(replacementId);
    }
  }

  /// تحديث جلسة حساب ويب/قائمة بعد التحقق من الرابط دون تغيير معرّفه.
  static Future<void> updateWebAccountSession({
    required String accountId,
    required UserModel user,
    required String serverUrl,
  }) {
    return _exclusive(
      () => _updateWebAccountSessionImpl(
        accountId: accountId,
        user: user,
        serverUrl: serverUrl,
      ),
    );
  }

  static Future<void> _updateWebAccountSessionImpl({
    required String accountId,
    required UserModel user,
    required String serverUrl,
  }) async {
    final list = listAccounts();
    final idx = list.indexWhere((e) => e.id == accountId);
    if (idx < 0) return;
    final existing = list[idx];
    list[idx] = SavedAccount(
      id: existing.id,
      displayName: existing.displayName,
      username: user.userInfo?.username ?? existing.username,
      password: user.userInfo?.password ?? existing.password,
      serverUrl: normalizeServerUrl(serverUrl),
      loginMethod: 'playlist_code',
      userJson: user.toJson(),
      source: existing.source,
      remoteId: existing.remoteId,
      avatarAsset: existing.avatarAsset,
      avatarFile: existing.avatarFile,
    );
    // بعد ملء اليوزر/الباس: ادمج أي صف يدوي مكرر فوراً
    final collapsed = _collapseDuplicateIdentities(list, preferId: accountId);
    await _writeAccounts(collapsed);
    final active = activeAccountId;
    if (active != null && collapsed.every((e) => e.id != active)) {
      await setActiveAccountId(
        collapsed.any((e) => e.id == accountId)
            ? accountId
            : (collapsed.isNotEmpty ? collapsed.first.id : null),
      );
    }
  }

  /// ألوان دائرية ثابتة لكل حساب.
  static List<Color> avatarGradientFor(String seed) {
    const palettes = <List<Color>>[
      [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
      [Color(0xFFFF5E9A), Color(0xFFB565D8)],
      [Color(0xFF7C5CFF), Color(0xFF5B8DEF)],
      [Color(0xFF2EC4B6), Color(0xFF3DD68C)],
      [Color(0xFF4FACFE), Color(0xFF00F2FE)],
      [Color(0xFFF7971E), Color(0xFFFFD200)],
    ];
    var hash = 0;
    for (final c in seed.codeUnits) {
      hash = (hash + c) % palettes.length;
    }
    return palettes[hash];
  }
}
