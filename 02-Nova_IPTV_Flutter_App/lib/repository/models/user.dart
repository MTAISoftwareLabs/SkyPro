class UserModel {
  final UserInfo? userInfo;
  final ServerInfo? serverInfo;

  UserModel({
    this.userInfo,
    this.serverInfo,
  });

  UserModel.fromJson(Map<String, dynamic> json, String domain)
      : userInfo =
            json['user_info'] is Map
                ? UserInfo.fromJson(
                  Map<String, dynamic>.from(json['user_info'] as Map),
                )
                : null,
        serverInfo =
            json['server_info'] is Map
                ? ServerInfo.fromJson(
                  Map<String, dynamic>.from(json['server_info'] as Map),
                  domain,
                )
                : null;

  Map<String, dynamic> toJson() => {
        'user_info': userInfo?.toJson(),
        'server_info': serverInfo?.toJson(),
      };
}

class UserInfo {
  final String? username;
  final String? password;
  final String? message;
  final String? auth;
  final String? status;
  final String? expDate;
  final String? isTrial;
  final String? activeCons;
  final String? createdAt;
  final String? maxConnections;
  final List<String>? allowedOutputFormats;

  UserInfo({
    this.username,
    this.password,
    this.message,
    this.auth,
    this.status,
    this.expDate,
    this.isTrial,
    this.activeCons,
    this.createdAt,
    this.maxConnections,
    this.allowedOutputFormats,
  });

  UserInfo.fromJson(Map<String, dynamic> json)
      : username = json['username']?.toString(),
        password = json['password']?.toString(),
        message = json['message']?.toString(),
        auth = json['auth']?.toString(),
        status = json['status']?.toString(),
        expDate = json['exp_date']?.toString(),
        isTrial = json['is_trial']?.toString(),
        activeCons = json['active_cons']?.toString(),
        createdAt = json['created_at']?.toString(),
        maxConnections = json['max_connections']?.toString(),
        allowedOutputFormats =
            (json['allowed_output_formats'] as List?)
                ?.map((dynamic e) => e.toString())
                .toList();

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'message': message,
        'auth': auth,
        'status': status,
        'exp_date': expDate,
        'is_trial': isTrial,
        'active_cons': activeCons,
        'created_at': createdAt,
        'max_connections': maxConnections,
        'allowed_output_formats': allowedOutputFormats
      };
}

class ServerInfo {
  final String? url;
  final String? port;
  final String? httpsPort;
  final String? serverProtocol;
  final String? rtmpPort;
  final String? timezone;
  final String? timestampNow;
  final String? timeNow;
  final String? process;
  final String? serverUrl;

  ServerInfo({
    this.serverUrl,
    this.url,
    this.port,
    this.httpsPort,
    this.serverProtocol,
    this.rtmpPort,
    this.timezone,
    this.timestampNow,
    this.timeNow,
    this.process,
  });

  /// يفضّل رابط الدخول الذي نجح فعلياً (غالباً بدون منفذ خاص).
  /// بناء :8880 من لوحة Xtream يفشل على كثير من شبكات الهواتف بينما يعمل على المحاكي.
  static String resolveServerUrl(Map<String, dynamic> json, String domain) {
    final domainClean = domain.trim().replaceAll(RegExp(r'/+$'), '');
    if (domainClean.startsWith('http://') ||
        domainClean.startsWith('https://')) {
      return domainClean;
    }

    final explicit = json['server_url']?.toString().trim();
    if (explicit != null &&
        explicit.isNotEmpty &&
        explicit != 'null' &&
        explicit.startsWith('http')) {
      return explicit.replaceAll(RegExp(r'/+$'), '');
    }

    final protocol =
        (json['server_protocol']?.toString().trim().isNotEmpty == true)
            ? json['server_protocol'].toString().trim()
            : 'http';
    final host = json['url']?.toString().trim() ?? '';
    if (host.isNotEmpty && host != 'null') {
      // بدون منفذ خاص أولاً — أأمن على بيانات الجوال
      return '$protocol://$host';
    }

    return domainClean;
  }

  ServerInfo.fromJson(Map<String, dynamic> json, String domain)
      : url = json['url']?.toString(),
        port = json['port']?.toString(),
        httpsPort = json['https_port']?.toString(),
        serverProtocol = json['server_protocol']?.toString(),
        rtmpPort = json['rtmp_port']?.toString(),
        timezone = json['timezone']?.toString(),
        timestampNow = json['timestamp_now']?.toString(),
        timeNow = json['time_now']?.toString(),
        process = json['process']?.toString(),
        serverUrl = resolveServerUrl(json, domain);

  Map<String, dynamic> toJson() => {
        'url': url,
        'port': port,
        'https_port': httpsPort,
        'server_protocol': serverProtocol,
        'rtmp_port': rtmpPort,
        'timezone': timezone,
        'timestamp_now': timestampNow,
        'time_now': timeNow,
        'process': process,
        'server_url': serverUrl
      };
}

extension UserModelPlaylistUrl on UserModel {
  /// رابط قائمة التشغيل الكامل (نفس صيغة إضافة الجهاز) لإرساله مع الملاحظات للوحة.
  String? get m3uPlaylistUrl {
    final username = userInfo?.username?.trim() ?? '';
    final password = userInfo?.password?.trim() ?? '';
    final serverUrl = serverInfo?.serverUrl?.trim() ?? '';
    if (username.isEmpty || password.isEmpty || serverUrl.isEmpty) {
      return null;
    }
    final base = serverUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/get.php?username=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}&type=m3u_plus&output=m3u8';
  }
}
