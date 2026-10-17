part of 'api.dart';

class AuthApi {
  Future<UserModel?> registerUser(
    String username,
    String password,
    String link,
    String name,
  ) async {
    try {
      final cleanUsername = username.trim();
      final cleanPassword = password.trim();
      if (cleanUsername.isEmpty || cleanPassword.isEmpty) return null;

      final bases = _loginBases(link);
      if (bases.isEmpty) return null;

      for (final base in bases) {
        final user = await _tryPlayerApiLogin(
          base: base,
          username: cleanUsername,
          password: cleanPassword,
        );
        if (user != null) return user;
      }
      return null;
    } catch (e) {
      debugPrint("Error: $e");
      return null;
    }
  }

  /// قواعد محتملة لـ player_api (http/https، مع/بدون منفذ افتراضي).
  static List<String> _loginBases(String link) {
    var clean = link.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty) return const [];

    final bool isSslPort = clean.contains(':25463') ||
        clean.contains(':25500') ||
        clean.contains(':443') ||
        clean.contains('skypro-app.com');

    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = isSslPort ? 'https://$clean' : 'http://$clean';
    } else if (clean.startsWith('http://') && isSslPort) {
      clean = clean.replaceFirst('http://', 'https://');
    }

    final out = <String>[];
    void add(String? raw) {
      var b = (raw ?? '').trim().replaceAll(RegExp(r'/+$'), '');
      if (b.isEmpty) return;
      if (!out.contains(b)) out.add(b);
    }

    add(clean);

    final uri = Uri.tryParse(clean);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return out;

    final host = uri.host;
    final scheme = uri.scheme.toLowerCase();
    final hasExplicitPort = uri.hasPort;
    final port = uri.hasPort ? uri.port : null;

    // نفس المضيف بالبروتوكول الآخر (مع تجنب إرسال http صريح لمنافذ SSL حصراً)
    if (scheme == 'http') {
      add('https://$host${hasExplicitPort ? ':${uri.port}' : ''}');
    } else if (scheme == 'https' && port != 25463 && port != 25500 && port != 443) {
      add('http://$host${hasExplicitPort ? ':${uri.port}' : ''}');
    }

    // بدون منفذ افتراضي / معه
    if (hasExplicitPort && (uri.port == 80 || uri.port == 443)) {
      add('$scheme://$host');
      add('${scheme == 'https' ? 'http' : 'https'}://$host');
    } else if (!hasExplicitPort) {
      add('$scheme://$host:80');
      add('$scheme://$host:8080');
      add('http://$host:8080');
      add('https://$host:443');
    }

    return out;
  }

  Future<UserModel?> _tryPlayerApiLogin({
    required String base,
    required String username,
    required String password,
  }) async {
    try {
      final endpoint = "$base/player_api.php";
      debugPrint("$endpoint?username=$username&password=***");

      final Response<String> response = await _dio.get(
        endpoint,
        queryParameters: {
          "username": username,
          "password": password,
        },
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
            'Accept': 'application/json, text/plain, */*',
          },
          sendTimeout: const Duration(seconds: 18),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode != 200) return null;
      final raw = (response.data ?? '').replaceFirst('\uFEFF', '').trim();
      if (raw.isEmpty || raw.startsWith('<')) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      if (json['user_info'] is Map) {
        json['user_info'] = Map<String, dynamic>.from(
          json['user_info'] as Map,
        );
      }
      if (json['server_info'] is Map) {
        json['server_info'] = Map<String, dynamic>.from(
          json['server_info'] as Map,
        );
      }

      final userInfo = json['user_info'];
      if (userInfo is! Map) return null;

      // بعض اللوحات لا تُرجع password — يكفي وجود username / auth
      final remoteUser = (userInfo['username'] ?? '').toString().trim();
      if (remoteUser.isEmpty &&
          (userInfo['auth']?.toString() != '1' &&
              userInfo['auth']?.toString() != 'true')) {
        // إن وُجدت حالة صريحة بدون يوزر نرفض؛ وإلا نقبل إن auth=1
        if (userInfo['auth'] == null && userInfo['status'] == null) {
          return null;
        }
      }

      // ثبّت الاعتمادات المُدخلة إن نقصت في الرد
      userInfo['username'] =
          remoteUser.isNotEmpty ? remoteUser : username;
      final remotePass = (userInfo['password'] ?? '').toString();
      if (remotePass.isEmpty) {
        userInfo['password'] = password;
      }
      json['user_info'] = userInfo;

      final user = UserModel.fromJson(json, base);

      final status = (user.userInfo?.status ?? '').trim().toLowerCase();
      const ok = {
        '',
        'active',
        'enabled',
        'open',
        'ok',
        '1',
        'true',
      };
      if (status.isNotEmpty && !ok.contains(status)) {
        debugPrint('registerUser rejected status=$status base=$base');
        return null;
      }

      // auth=0 صريح = رفض
      final auth = (user.userInfo?.auth ?? '').trim().toLowerCase();
      if (auth == '0' || auth == 'false') return null;

      if (shouldBlockExpiredIptvSession(
        expDate: user.userInfo?.expDate,
        status: user.userInfo?.status,
        username: user.userInfo?.username ?? username,
        password: user.userInfo?.password ?? password,
      )) {
        debugPrint('registerUser rejected expired subscription base=$base');
        return null;
      }

      await LocaleApi.saveUser(user);
      debugPrint('registerUser OK base=$base');
      return user;
    } catch (e) {
      debugPrint('registerUser try fail base=$base err=$e');
      return null;
    }
  }
}
