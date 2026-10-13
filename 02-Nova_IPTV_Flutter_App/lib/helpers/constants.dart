part of 'helpers.dart';

const String kAppName = "SkyPro";

/// اسم العرض الثابت للتطبيق — لا يُستبدل باسم اللوحة حتى لا يظهر اسم قديم بعد النسخ.
String get appName => kAppName;

/// التحكم بإظهار/إخفاء تسجيل الدخول باسم المستخدم وكلمة المرور في شاشة الدخول.
bool get showUsernameLogin {
  final box = GetStorage();
  final stored = box.read('show_username_login');
  if (stored is bool) return stored;
  return true;
}

/// إصدار التطبيق المعروض داخل الإعدادات (من البناء المحلي، ثم لوحة التحكم).
String get appVersionText {
  final box = GetStorage();
  String clean(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final plus = t.indexOf('+');
    return plus >= 0 ? t.substring(0, plus).trim() : t;
  }

  final local = box.read('local_app_version');
  if (local is String) {
    final c = clean(local);
    if (c.isNotEmpty) return c;
  }
  final stored = box.read('app_version');
  if (stored is String) {
    final c = clean(stored);
    if (c.isNotEmpty) return c;
  }
  return '1.0.0';
}

const String kIconLiveTv = "assets/images/live tv.png";
const String kIconSeries = "assets/images/series.png";
const String kIconMovies = "assets/images/film-reel.png";
const String kSkyProLogo = "assets/images/skypro_logo.png";
const String kIconSplash = kSkyProLogo;

/// أيقونات شريط Home على التلفزيون — نفس أصول Smart TV.
const String kSmartTvNavHome = 'assets/images/smart_tv_nav/nav-home.png';
const String kSmartTvNavLive = 'assets/images/smart_tv_nav/nav-live.png';
const String kSmartTvNavMovies = 'assets/images/smart_tv_nav/nav-movies.png';
const String kSmartTvNavSeries = 'assets/images/smart_tv_nav/nav-series.png';
const String kSmartTvNavFav = 'assets/images/smart_tv_nav/nav-fav.png';
const String kSmartTvNavWifi = 'assets/images/smart_tv_nav/wifi.png';
const String kSmartTvNavNoWifi = 'assets/images/smart_tv_nav/no-wifi.png';
const String kSmartTvNavProfile = 'assets/images/smart_tv_nav/profile.png';
const String kSmartTvNavSettings = 'assets/images/smart_tv_nav/settings.png';

const String kLoadingBackground = "assets/images/loading.jpg";
const String kLoginBackground = "assets/images/back_login.webp";
const String kIconFavourite = "assets/images/favourite.png";
const String kIconExit = "assets/images/exit.png";
const String kIconAspectRatio = "assets/images/aspect-ratio.png";
const String kIconPlayerSwitch = "assets/images/player.png";
const String kNoPosterAsset = "assets/images/no_poster.png";

/// Pseudo category id for live IPTV overlay favorites row (always first).
const String kIptvFavoritesCategoryId = '__iptv_favorites__';

/// Pseudo category under favorites: channels played for 15+ seconds.
const String kIptvRecentlyWatchedCategoryId = '__iptv_recently_watched__';

bool isIptvPinnedLiveCategory(String? id) =>
    id == kIptvFavoritesCategoryId || id == kIptvRecentlyWatchedCategoryId;

/// فئة وهمية في أفلام/مسلسلات: «المضافة حديثاً» (last_modified).
const String kRecentlyAddedCategoryId = '__recently_added__';

/// فئات مثبتة أعلى شريط أفلام/مسلسلات (لا تُعاد ترتيبها).
const String kCatalogAllCategoryId = '__all__';
const String kCatalogWatchedCategoryId = '__watched__';

bool isCatalogPinnedCategory(String? id) =>
    id == kCatalogAllCategoryId ||
    id == kCatalogWatchedCategoryId ||
    id == kRecentlyAddedCategoryId;

/// حد عناصر فئة recently added (مطابق لـ getRecentlyAdded* API).
const int kRecentlyAddedLimit = 32;

/// يُستعمل لإعادة تسخين صور الرئيسية عند الرجوع من الأقسام.
final RouteObserver<ModalRoute<void>> kAppRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// مدى التحميل المسبق للشبكات (Grid/List) — أقل على الأجهزة الضعيفة.
double get kCatalogCacheExtent => AppPerf.instance.catalogCacheExtent;

/// قوائم جانبية (لايف / أوفرلاي) — نصف مدى الشبكة تقريباً.
double get kListCacheExtent =>
    (AppPerf.instance.catalogCacheExtent * 0.5).clamp(80.0, 220.0);

/// أجهزة ضعيفة (هاتف أو تلفاز): بدون تكبير تركيز ولا هالات blur (إطار فقط).
bool get kReduceFocusMotion => AppPerf.instance.reduceFocusMotion;

Duration get kFocusAnimDuration => AppPerf.instance.focusAnimDuration;

/// تمرير العنصر المركّز إلى الشاشة — فوري على TV/lite (بدون تأخير الريموت).
Duration get kTvEnsureVisibleDuration {
  if (kReduceFocusMotion ||
      AppPerf.instance.isLite ||
      AppPerf.instance.isTelevisionLike) {
    return Duration.zero;
  }
  return const Duration(milliseconds: 160);
}

bool get kTvSnapFocusScroll => kTvEnsureVisibleDuration == Duration.zero;

/// مقياس التركيز — 1.0 دائماً على الأجهزة الضعيفة.
double kTvFocusScale(bool focused, [double focusedScale = 1.05]) {
  if (kReduceFocusMotion || !focused) return 1.0;
  return focusedScale;
}

/// هالة تركيز اختيارية — فارغة على lite.
List<BoxShadow>? kTvFocusGlow({
  required bool focused,
  Color? color,
  double blur = 14,
  double spread = 0,
  double alpha = 0.4,
}) {
  if (!focused || kReduceFocusMotion) return null;
  return [
    BoxShadow(
      color: (color ?? kColorFocus).withValues(alpha: alpha),
      blurRadius: blur,
      spreadRadius: spread,
    ),
  ];
}

/// تسمية وضع الأداء المعروض في الإعدادات.
String appPerfChoiceLabel(String choice) {
  switch (choice) {
    case 'lite':
      return 'settings_perf_mode_lite'.tr;
    case 'mid':
      return 'settings_perf_mode_mid'.tr;
    case 'full':
      return 'settings_perf_mode_full'.tr;
    default:
      return 'settings_perf_mode_auto'.trParams({
        'level': appPerfLevelShortLabel(AppPerf.autoDetectedLevel),
      });
  }
}

String appPerfLevelShortLabel(AppPerfLevel level) {
  switch (level) {
    case AppPerfLevel.lite:
      return 'settings_perf_mode_lite'.tr;
    case AppPerfLevel.mid:
      return 'settings_perf_mode_mid'.tr;
    case AppPerfLevel.full:
      return 'settings_perf_mode_full'.tr;
  }
}

String appPerfEffectiveLabel() {
  final choice = AppPerf.currentUserChoice();
  if (choice == 'auto') {
    return 'settings_perf_mode_auto'.trParams({
      'level': appPerfLevelShortLabel(AppPerf.instance.level),
    });
  }
  return appPerfChoiceLabel(choice);
}

const String kDemoUrl = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

const double sizeTablet = 950;

enum TypeCategory { live, movies, series }

/// المشغل الافتراضي للفيديو داخل التطبيق
enum AppVideoPlayer { vlc, exo }

/// مفتاح التخزين للمشغل المختار
const String kStorageVideoPlayer = 'video_player';
const String kStorageAutoPlayNext = 'auto_play_next';
const String kStorageRememberLastChannel = 'remember_last_channel';
const String kStorageDemoSession = 'is_demo_session';
const String kStorageLiveStablePlayer = 'live_stable_player';
const String kStorageXtreamLiveFormat = 'xtream_live_format';

/// صيغة البث: Default / MPEGTS(.ts) / HLS(.m3u8) — نفس قيم live_format.
/// Default و HLS → `.m3u8`؛ MPEGTS فقط → `.ts`.
enum XtreamLiveStreamFormat { defaultFmt, hls, mpegTs }

String xtreamLiveFormatStorageKey(XtreamLiveStreamFormat format) {
  switch (format) {
    case XtreamLiveStreamFormat.defaultFmt:
      return 'default';
    case XtreamLiveStreamFormat.hls:
      return 'hls';
    case XtreamLiveStreamFormat.mpegTs:
      return 'ts';
  }
}

XtreamLiveStreamFormat? parseXtreamLiveFormatStorage(dynamic stored) {
  if (stored is int) {
    switch (stored) {
      case 1:
        return XtreamLiveStreamFormat.mpegTs;
      case 2:
        return XtreamLiveStreamFormat.hls;
      case 0:
        return XtreamLiveStreamFormat.defaultFmt;
    }
  }
  if (stored is! String) return null;
  switch (stored.trim().toLowerCase()) {
    case 'default':
    case '0':
      return XtreamLiveStreamFormat.defaultFmt;
    case 'hls':
    case 'm3u8':
    case '2':
      return XtreamLiveStreamFormat.hls;
    case 'ts':
    case 'mpegts':
    case 'mpeg-ts':
    case '1':
      return XtreamLiveStreamFormat.mpegTs;
    default:
      return null;
  }
}

/// يستنتج الصيغة من `allowed_output_formats` (0 default / 2 hls / 1 ts).
XtreamLiveStreamFormat resolveXtreamLiveFormatFromServer(
  List<String>? allowedOutputFormats,
) {
  if (allowedOutputFormats == null || allowedOutputFormats.isEmpty) {
    return XtreamLiveStreamFormat.defaultFmt;
  }
  final lower = allowedOutputFormats.map((e) => e.toLowerCase()).toList();
  if (lower.contains('m3u8') || lower.contains('hls')) {
    return XtreamLiveStreamFormat.hls;
  }
  return XtreamLiveStreamFormat.mpegTs;
}

/// يحفظ Default بعد الدخول إلا إذا اختار المستخدم يدوياً في الإعدادات.
void syncXtreamLiveFormatFromLogin(List<String>? _) {
  if (GetStorage().read(kStorageXtreamLiveFormatUserLocked) == true) return;
  GetStorage().write(
    kStorageXtreamLiveFormat,
    xtreamLiveFormatStorageKey(XtreamLiveStreamFormat.defaultFmt),
  );
}

const String kStorageXtreamLiveFormatUserLocked =
    'xtream_live_format_user_locked';

void setPreferredXtreamLiveStreamFormat(XtreamLiveStreamFormat format) {
  GetStorage().write(
    kStorageXtreamLiveFormat,
    xtreamLiveFormatStorageKey(format),
  );
  GetStorage().write(kStorageXtreamLiveFormatUserLocked, true);
}

XtreamLiveStreamFormat get preferredXtreamLiveStreamFormat {
  final stored = GetStorage().read(kStorageXtreamLiveFormat);
  return parseXtreamLiveFormatStorage(stored) ??
      XtreamLiveStreamFormat.defaultFmt;
}

/// الامتداد الفعلي للرابط: ts فقط لـ MPEGTS؛ وإلا m3u8 (Default + HLS).
bool get preferredXtreamLiveUsesMpegTs =>
    preferredXtreamLiveStreamFormat == XtreamLiveStreamFormat.mpegTs;

/// بناء رابط بث مباشر Xtream القياسي: `/live/user/pass/id.m3u8` أو `.ts`.
String buildXtreamLiveStreamUrl({
  required String serverUrl,
  required String username,
  required String password,
  required String streamId,
  XtreamLiveStreamFormat? format,
}) {
  final id = streamId.trim();
  if (id.isEmpty) return '';
  if (id.startsWith('http://') || id.startsWith('https://')) return id;

  final base = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final user = username.trim();
  final pass = password.trim();
  if (base.isEmpty || user.isEmpty || pass.isEmpty) return '';

  final fmt = format ?? preferredXtreamLiveStreamFormat;
  final ext = fmt == XtreamLiveStreamFormat.mpegTs ? 'ts' : 'm3u8';
  return '$base/live/$user/$pass/$id.$ext';
}

/// صيغة قصيرة للبث على VLC: `server/user/pass/id` (بدون /live/ وبدون امتداد).
String buildXtreamLiveStreamUrlShort({
  required String serverUrl,
  required String username,
  required String password,
  required String streamId,
}) {
  final rawId = streamId.trim();
  if (rawId.isEmpty) return '';
  if (rawId.startsWith('http://') || rawId.startsWith('https://')) return rawId;

  final base = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final user = username.trim();
  final pass = password.trim();
  if (base.isEmpty || user.isEmpty || pass.isEmpty) return '';

  final id = rawId.replaceAll(
    RegExp(r'\.(m3u8|ts|mpd)$', caseSensitive: false),
    '',
  );
  if (id.isEmpty) return '';
  return '$base/$user/$pass/$id';
}

/// حوّل أي رابط Xtream live معروف إلى الصيغة القصيرة إن أمكن.
String? xtreamLiveUrlToShortForm(String url) {
  final raw = url.trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 3) return null;

  String user;
  String pass;
  String id;
  if (segments.first.toLowerCase() == 'live' && segments.length >= 4) {
    user = segments[segments.length - 3];
    pass = segments[segments.length - 2];
    id = segments.last;
  } else {
    user = segments[segments.length - 3];
    pass = segments[segments.length - 2];
    id = segments.last;
  }
  id = id.replaceAll(RegExp(r'\.(m3u8|ts|mpd)$', caseSensitive: false), '');
  if (user.isEmpty || pass.isEmpty || id.isEmpty) return null;
  final base =
      '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  return '$base/$user/$pass/$id';
}

/// مرشّحو Exo للبث — /live/ أولاً (Xtream القياسي)، ثم الأصلي، ثم الصيغة القصيرة.
List<String> buildExoLiveUrlCandidates(
  String originalUrl, {
  XtreamLiveStreamFormat? preferredFormat,
}) {
  final out = <String>[];
  void add(String? u) {
    final t = u?.trim() ?? '';
    if (t.isEmpty) return;
    final lower = t.toLowerCase();
    if (out.any((e) => e.toLowerCase() == lower)) return;
    out.add(t);
  }

  final pref = preferredFormat ?? preferredXtreamLiveStreamFormat;
  final hls = normalizeXtreamLiveUrlForNativePlayer(originalUrl);
  final ts = normalizeXtreamLiveUrlForNativePlayerTs(originalUrl);
  final short = xtreamLiveUrlToShortForm(originalUrl);

  // Canonical /live/ paths first — short XUI forms break many panels on Exo.
  if (pref == XtreamLiveStreamFormat.mpegTs) {
    add(ts);
    add(hls);
  } else {
    add(hls);
    add(ts);
  }
  add(originalUrl);

  if (short != null && short.isNotEmpty) {
    add(short);
    if (pref == XtreamLiveStreamFormat.mpegTs) {
      add('$short.ts');
      add('$short.m3u8');
    } else {
      add('$short.m3u8');
      add('$short.ts');
    }
  }
  return out;
}

/// طريقة آخر دخول: `username_password` | `playlist_code` (يُحفظ مع الجلسة)
const String kStorageLoginMethod = 'login_method';

/// حسابات محفوظة للتبديل السريع
const String kStorageSavedAccounts = 'saved_accounts';
const String kStorageActiveAccountId = 'active_account_id';

/// ترتيب فئات البث المباشر لكل حساب: `live_cat_order_<accountId>`
const String kStorageLiveCategoryOrderPrefix = 'live_cat_order_';

/// ترتيب فئات الأفلام/المسلسلات لكل حساب.
const String kStorageMovieCategoryOrderPrefix = 'movie_cat_order_';
const String kStorageSeriesCategoryOrderPrefix = 'series_cat_order_';

/// قنوات شوهدت مؤخراً لكل حساب: `live_recently_watched_<accountId>`
const String kStorageLiveRecentlyWatchedPrefix = 'live_recently_watched_';
const String kStorageAddingNewAccount = 'adding_new_account';

/// أثناء إضافة حساب عبر QR: انتظر ربط حساب مختلف عن المرتبط حالياً بالجهاز
const String kStorageQrAwaitNewAccount = 'qr_await_new_account';
const String kStorageQrBaselineDomain = 'qr_baseline_domain';
const String kStorageQrBaselineUsername = 'qr_baseline_username';
const String kStorageQrBaselineReady = 'qr_baseline_ready';
const String kStorageForceQrAutoLogin = 'force_qr_auto_login';

/// نتيجة ربط QR داخل الحوار: `success` | `failed` (يشاهدها `_DeviceQrDialog`)
const String kStorageQrLinkResult = 'qr_link_result';

/// بعد تسجيل الخروج / إضافة حساب: لا تُعد الدخول تلقائياً من playlist اللوحة
const String kStorageSuppressPlaylistAutoLogin = 'suppress_playlist_auto_login';

/// املأ خانات register فقط بعد Add/Change Playlist (M3U) وليس من اللوحة عامة
const String kStorageFillManualFromM3u = 'fill_manual_from_m3u';

/// رابط السيرفر الافتراضي من لوحة التحكم (Default server URL)
const String kStorageDefaultServerUrl = 'default_server_url';

/// سيرفرات Xtream المسماة من لوحة التحكم (List of {name, url})
const String kStorageLoginServers = 'login_servers';
const String kLoginServerExternalKey = 'external';

AppVideoPlayer get preferredVideoPlayer {
  // iOS: VLC only — ignore any stored Exo/AVPlayer preference.
  if (Platform.isIOS) return AppVideoPlayer.vlc;

  final box = GetStorage();
  final stored = box.read(kStorageVideoPlayer);
  if (stored is String) {
    switch (stored) {
      case 'exo':
        return AppVideoPlayer.exo;
      case 'vlc':
        return AppVideoPlayer.vlc;
    }
  }
  // Android Live default: VLC primary (Exo remains selectable for live).
  // Movies & series always use Exo regardless (enforced in FullVideoScreen).
  return AppVideoPlayer.vlc;
}

void setPreferredVideoPlayer(AppVideoPlayer player) {
  // iOS cannot use Exo/AVPlayer path in this app — keep storage as VLC.
  if (Platform.isIOS) {
    GetStorage().write(kStorageVideoPlayer, AppVideoPlayer.vlc.name);
    return;
  }
  GetStorage().write(kStorageVideoPlayer, player.name);
}

const String kStorageExoSoftwareDecoder = 'exo_prefer_software_decoder';

/// اختيار المستخدم: `auto` | `software` | `hardware`
String exoSoftwareDecoderUserChoice() {
  try {
    final raw = (GetStorage().read(kStorageExoSoftwareDecoder) ?? 'auto')
        .toString()
        .trim()
        .toLowerCase();
    // توافق مع القيم القديمة on/off
    if (raw == 'software' || raw == 'on' || raw == 'true' || raw == '1') {
      return 'software';
    }
    if (raw == 'hardware' || raw == 'off' || raw == 'false' || raw == '0') {
      return 'hardware';
    }
  } catch (_) {}
  return 'auto';
}

void setExoSoftwareDecoderUserChoice(String choice) {
  final key = choice.trim().toLowerCase();
  final box = GetStorage();
  if (key == 'software' || key == 'hardware' || key == 'auto') {
    box.write(kStorageExoSoftwareDecoder, key);
  } else if (key == 'on') {
    box.write(kStorageExoSoftwareDecoder, 'software');
  } else if (key == 'off') {
    box.write(kStorageExoSoftwareDecoder, 'hardware');
  }
}

/// Exo: هل نفضّل software؟ (بعد حل auto حسب الجهاز)
bool get preferExoSoftwareDecoder {
  if (Platform.isIOS) return false;
  final choice = exoSoftwareDecoderUserChoice();
  if (choice == 'software') return true;
  if (choice == 'hardware') return false;
  // auto: صناديق TV + lite غالباً HW decode كيعلّق على بعض القنوات.
  return AppPerf.instance.isTelevisionLike || AppPerf.instance.isLite;
}

const String _kStorageVideoPlayerVlcPrimaryMigrated =
    'video_player_vlc_primary_v1';

/// One-shot: default live player VLC on Android (Exo still selectable in settings).
void migratePreferredPlayerToVlcPrimary() {
  final box = GetStorage();
  if (box.read(_kStorageVideoPlayerVlcPrimaryMigrated) == true) return;
  box.write(kStorageVideoPlayer, AppVideoPlayer.vlc.name);
  box.write(_kStorageVideoPlayerVlcPrimaryMigrated, true);
}

void clearPreferredLiveStablePlayer() {
  GetStorage().remove(kStorageLiveStablePlayer);
}

AppVideoPlayer? get preferredLiveStablePlayer {
  final box = GetStorage();
  final stored = box.read(kStorageLiveStablePlayer);
  if (stored is! String) return null;
  switch (stored) {
    case 'exo':
      return AppVideoPlayer.exo;
    case 'vlc':
      return AppVideoPlayer.vlc;
  }
  return null;
}

void setPreferredLiveStablePlayer(AppVideoPlayer player) {
  GetStorage().write(kStorageLiveStablePlayer, player.name);
}

/// تحويل روابط البث القصيرة Xtream (`/user/pass/id`) إلى HLS
/// (`/live/user/pass/id.m3u8`) لـ ExoPlayer/AVPlayer على كل الأجهزة.
String normalizeXtreamLiveUrlForNativePlayer(String url) {
  if (url.isEmpty) return url;
  final lower = url.toLowerCase();
  if (lower.contains('.m3u8') || lower.contains('.mpd')) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return url;
  final path = uri.path;
  if (path.toLowerCase().endsWith('.ts')) {
    return uri
        .replace(path: '${path.substring(0, path.length - 3)}.m3u8')
        .toString();
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 3) return url;
  final id = segments.last;
  if (id.contains('.')) return url;
  if (segments.first.toLowerCase() == 'live') {
    return uri.replace(path: '${uri.path}.m3u8').toString();
  }
  final user = segments[segments.length - 3];
  final pass = segments[segments.length - 2];
  final prefix = segments.length > 3
      ? '/${segments.sublist(0, segments.length - 3).join('/')}'
      : '';
  final newPath = '$prefix/live/$user/$pass/$id.m3u8'.replaceAll('//', '/');
  return uri.replace(path: newPath).toString();
}

/// نفس [normalizeXtreamLiveUrlForNativePlayer] لكن بامتداد MPEG-TS (.ts).
String normalizeXtreamLiveUrlForNativePlayerTs(String url) {
  if (url.isEmpty) return url;
  final lower = url.toLowerCase();
  if (lower.contains('.ts') && !lower.contains('.m3u8')) return url;
  if (lower.contains('.mpd')) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return url;
  final path = uri.path;
  if (path.toLowerCase().endsWith('.m3u8')) {
    return uri
        .replace(path: '${path.substring(0, path.length - 5)}.ts')
        .toString();
  }
  if (path.toLowerCase().endsWith('.ts')) return url;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 3) return url;
  final id = segments.last;
  if (id.contains('.')) return url;
  if (segments.first.toLowerCase() == 'live') {
    return uri.replace(path: '${uri.path}.ts').toString();
  }
  final user = segments[segments.length - 3];
  final pass = segments[segments.length - 2];
  final prefix = segments.length > 3
      ? '/${segments.sublist(0, segments.length - 3).join('/')}'
      : '';
  final newPath = '$prefix/live/$user/$pass/$id.ts'.replaceAll('//', '/');
  return uri.replace(path: newPath).toString();
}

bool get autoPlayNextEnabled {
  final box = GetStorage();
  final stored = box.read(kStorageAutoPlayNext);
  if (stored is bool) return stored;
  return false;
}

void setAutoPlayNextEnabled(bool enabled) {
  GetStorage().write(kStorageAutoPlayNext, enabled);
}

bool get rememberLastChannelEnabled {
  final stored = GetStorage().read(kStorageRememberLastChannel);
  if (stored is bool) return stored;
  return false;
}

/// إشعارات الدفع (OneSignal) — تظهر في الإعدادات على Android/iOS فقط عند تفعيلها من اللوحة.
bool get pushNotificationsSettingAvailable {
  if (!Platform.isAndroid && !Platform.isIOS) return false;
  final panelFlag = GetStorage().read('onesignal_enabled');
  if (panelFlag == false || panelFlag == 0 || panelFlag == '0') return false;
  final appId = (GetStorage().read('onesignal_app_id') ?? '').toString().trim();
  return appId.isNotEmpty;
}

Size getSize(BuildContext context) => MediaQuery.of(context).size;

bool isTv(BuildContext context) {
  final stored = GetStorage().read('is_tv_device');
  if (stored is bool) return stored;
  if (!Platform.isAndroid) return false;
  final size = MediaQuery.of(context).size;
  return size.width > sizeTablet || size.height > sizeTablet;
}

// تحسين دعم التلفاز
bool isAndroidTv(BuildContext context) {
  return isTv(context);
}

// تحسين دعم التلفاز
bool isTvDevice(BuildContext context) {
  return isTv(context) || isAndroidTv(context);
}
