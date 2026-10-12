part of 'helpers.dart';

/// تنظيف عنوان للعرض: إزالة الرموز غير المفهومة وترميز HTML
String sanitizeDisplayTitle(String? text) {
  if (text == null || text.isEmpty) return '';

  String s = text
      // إزالة رمز الاستبدال الذي يظهر عادة كمربع أسود أو �
      .replaceAll('\uFFFD', '')
      // فك ترميز HTML الشائع
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');

  // إزالة أحرف التحكم غير القابلة للطباعة
  s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

  // فك ترميز &#123; للأرقام
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1) ?? '');
    if (code != null && code > 0 && code < 0x10FFFF) {
      return String.fromCharCode(code);
    }
    return m.group(0) ?? '';
  });

  // تنظيف إضافي: السماح فقط بمجموعة من المحارف المعقولة (عربي، لاتيني، أرقام، بعض الرموز)
  final buffer = StringBuffer();
  for (final code in s.runes) {
    final isLatinBasic = code >= 0x0020 && code <= 0x007E;
    final isLatin1 = code >= 0x00A0 && code <= 0x00FF;
    final isArabicMain = code >= 0x0600 && code <= 0x06FF;
    final isArabicSupplement = code >= 0x0750 && code <= 0x077F;
    final isArabicExtended = code >= 0x08A0 && code <= 0x08FF;
    final isArabicPresentationA = code >= 0xFB50 && code <= 0xFDFF;
    final isArabicPresentationB = code >= 0xFE70 && code <= 0xFEFF;
    final isCommonPunctuation = code >= 0x2000 && code <= 0x206F;
    final isStarOrBullet = code == 0x2605 || code == 0x2606; // ★ ☆

    if (isLatinBasic ||
        isLatin1 ||
        isArabicMain ||
        isArabicSupplement ||
        isArabicExtended ||
        isArabicPresentationA ||
        isArabicPresentationB ||
        isCommonPunctuation ||
        isStarOrBullet) {
      buffer.writeCharCode(code);
    }
    // أي شيء خارج هذه النطاقات يتم تجاهله حتى لا يظهر كمربعات غريبة
  }

  // استبدال الفراغات المكررة بفراغ واحد
  final cleaned = buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
  return cleaned.trim();
}

/// فك عنوان EPG من Xtream (غالباً Base64) ثم تنظيفه للعرض.
String decodeEpgTitle(String? raw) {
  var t = (raw ?? '').trim();
  if (t.isEmpty || t.toLowerCase() == 'null') return '';

  final looksBase64 = RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(t) &&
      t.length >= 8 &&
      t.length % 4 == 0;
  if (looksBase64) {
    try {
      final decoded =
          utf8.decode(base64Decode(t), allowMalformed: true).trim();
      if (decoded.isNotEmpty) t = decoded;
    } catch (_) {}
  }

  t = sanitizeDisplayTitle(t).trim();
  if (t.isEmpty) return '';

  final lower = t.toLowerCase();
  const junk = {
    'title',
    'null',
    'undefined',
    'none',
    'n/a',
    'na',
    'epg',
    'program',
    'programme',
  };
  if (junk.contains(lower)) return '';
  return t;
}

/// هل العنوان عنصر ترويجي/تواصل وليس فيلماً أو مسلسلاً حقيقياً؟
/// يُستخدم في الصفحة الرئيسية فقط (ليس الرقابة الأبوية).
bool isHomeNonContentTitle(String? name) {
  var n = (name ?? '').trim().toLowerCase();
  if (n.isEmpty) return true;

  n = n
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[_\-./\\|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (n.isEmpty) return true;

  // روابط أو أرقام تواصل فقط
  if (RegExp(r'^(https?|www)\b').hasMatch(n)) return true;
  if (RegExp(r'^(\+|00)?\d[\d\s\-()]{6,}$').hasMatch(n)) return true;

  // عبارات كاملة شائعة
  const phrases = <String>[
    'contact us',
    'contact me',
    'call us',
    'email us',
    'customer service',
    'customer care',
    'how to',
    'how to renew',
    'how to subscribe',
    'follow us',
    'join us',
    'visit us',
    'for support',
    'for help',
    'tech support',
    'technical support',
    'whats app',
    'تواصل معنا',
    'اتصل بنا',
    'خدمة العملاء',
    'الدعم الفني',
    'كيف اشترك',
    'كيف تجدد',
    'للتواصل',
    'للدعم',
  ];
  for (final p in phrases) {
    if (n == p || n.contains(p)) return true;
  }

  // كلمات مفتاحية: تطابق كامل، أو تبدأ بالكلمة ويتبعها أرقام/رموز قصيرة فقط
  // (مثل online12 / support1 / contact) دون لمس عناوين مثل "The Online Survivor"
  const keywords = <String>[
    // EN
    'online',
    'support',
    'contact',
    'contacts',
    'whatsapp',
    'telegram',
    'info',
    'infos',
    'information',
    'help',
    'helpline',
    'howto',
    'tutorial',
    'tutorials',
    'guide',
    'guides',
    'promo',
    'promotion',
    'promotions',
    'advert',
    'advertise',
    'advertisement',
    'advertising',
    'ads',
    'ad',
    'update',
    'updates',
    'renew',
    'renewal',
    'renewals',
    'subscribe',
    'subscription',
    'reseller',
    'resellers',
    'panel',
    'test',
    'testing',
    'demo',
    'message',
    'messages',
    'announcement',
    'announcements',
    'notice',
    'notices',
    'alert',
    'alerts',
    'facebook',
    'instagram',
    'youtube',
    'tiktok',
    'website',
    'web',
    'www',
    'http',
    'https',
    'server',
    'servers',
    'activation',
    'activate',
    'expired',
    'expiry',
    'expiration',
    'payment',
    'payments',
    'pay',
    'billing',
    'invoice',
    'order',
    'orders',
    'free trial',
    'freetrial',
    'trial',
    'iptv',
    'm3u',
    'playlist',
    'account',
    'accounts',
    'login',
    'password',
    'credentials',
    // AR
    'تواصل',
    'دعم',
    'اتصل',
    'معلومات',
    'اشترك',
    'اشتراك',
    'تجديد',
    'اعلان',
    'إعلان',
    'دعاية',
    'مساعدة',
    'واتساب',
    'واتس',
    'تيليجرام',
    'تلجرام',
    'تليجرام',
    'فيسبوك',
    'انستغرام',
    'يوتيوب',
    'تحديث',
    'تفعيل',
    'انتهاء',
    'منتهي',
    'تجربة',
    'اختبار',
    'رسالة',
    'رسائل',
    'تنويه',
    'تنبيه',
    'لوحة',
    'موزع',
    'موزعين',
    'دفع',
    'فاتورة',
  ];

  for (final k in keywords) {
    if (n == k) return true;
    if (!n.startsWith(k)) continue;
    final rest = n.substring(k.length).trim();
    if (rest.isEmpty) return true;
    // online12 / support-01 / contact us (بعد التطبيع)
    if (RegExp(r'^[\d\s\-_.]+$').hasMatch(rest)) return true;
    if (rest.length <= 2 && !RegExp(r'[a-z\u0600-\u06FF]{3,}').hasMatch(rest)) {
      return true;
    }
  }

  return false;
}

/// فلترة قائمة الصفحة الرئيسية من العناوين الترويجية/التواصل.
List<T> filterHomeContentTitles<T>(
  List<T> items,
  String? Function(T item) titleOf,
) {
  return items.where((e) => !isHomeNonContentTitle(titleOf(e))).toList();
}

/// يحوّل رابط صورة الأفلام/المسلسلات إلى رابط كامل.
/// إن كان الرابط يبدأ بـ http أو https يُعاد كما هو، وإلا يُضاف له عنوان السيرفر.
String resolveImageUrl(String? imagePath, String? serverBaseUrl) {
  final path = imagePath?.trim();
  if (path == null || path.isEmpty || path == 'null') return '';
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final base = serverBaseUrl?.trim();
  if (base == null || base.isEmpty) return path;
  final baseNorm = base.endsWith('/') ? base : '$base/';
  final pathNorm = path.startsWith('/') ? path.substring(1) : path;
  return '$baseNorm$pathNorm';
}

Future<void> applyUserAppPerfChoice(String choice) async {
  await AppPerf.applyUserChoice(choice);
  AppPerf.applyToFlutterImageCache();
}

/// يعيد تشغيل التطبيق تلقائياً (أندرويد) لتطبيق وضع الأداء بالكامل.
/// إن فشل القناة الأصلية، يغلق التطبيق كحل احتياطي.
Future<void> forceRelaunchApp() async {
  if (Platform.isAndroid) {
    try {
      await const MethodChannel(
        'main_activity_channel',
      ).invokeMethod<bool>('restartApp');
      return;
    } catch (_) {}
  }
  try {
    await SystemNavigator.pop();
  } catch (_) {}
  try {
    exit(0);
  } catch (_) {}
}

/// مزامنة `is_tv_device` مع النظام (Leanback / UI_MODE_TELEVISION) ثم الحجم عند الحاجة.
/// لا تُسقِط علماً صحيحاً من التلفاز بناءً على MediaQuery وحده.
Future<bool> syncAndPersistTvDeviceFlag([BuildContext? context]) async {
  bool? nativeTv;
  if (Platform.isAndroid) {
    try {
      nativeTv = await const MethodChannel(
        'main_activity_channel',
      ).invokeMethod<bool>('isTelevisionDevice');
    } catch (_) {}
  }

  if (nativeTv == true) {
    GetStorage().write('is_tv_device', true);
    return true;
  }

  var sizeLooksTv = false;
  if (context != null && context.mounted) {
    final size = MediaQuery.sizeOf(context);
    sizeLooksTv = size.width > sizeTablet || size.height > sizeTablet;
  } else {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isNotEmpty) {
      final view = views.first;
      final sz = view.physicalSize / view.devicePixelRatio;
      sizeLooksTv = sz.width > sizeTablet || sz.height > sizeTablet;
    }
  }

  if (nativeTv == false) {
    GetStorage().write('is_tv_device', false);
    return false;
  }

  // النظام غير معروف: الحجم أو القيمة السابقة.
  if (sizeLooksTv) {
    GetStorage().write('is_tv_device', true);
    return true;
  }
  final existing = GetStorage().read('is_tv_device');
  if (existing is bool) return existing;
  GetStorage().write('is_tv_device', false);
  return false;
}

bool get isStoredTvDevice => GetStorage().read('is_tv_device') == true;

const MethodChannel _mainActivityChannel = MethodChannel('main_activity_channel');

Future<void> _nativeLockLandscape() async {
  if (!Platform.isAndroid) return;
  try {
    await _mainActivityChannel.invokeMethod<bool>('lockLandscape');
  } catch (_) {}
}

/// قفل الاتجاه أفقياً دائماً (هاتف + تلفاز).
Future<void> applyDevicePreferredOrientations() async {
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await _nativeLockLandscape();
}

/// أول اتجاه عند التشغيل: مزامنة التلفاز ثم قفل أفقي دائماً (شاشة الدخول أفقية).
Future<void> applyInitialAppOrientation() async {
  await syncAndPersistTvDeviceFlag();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await _nativeLockLandscape();
}

void changeDeviceOrient() {
  // أقسام التطبيق بعد الدخول: أفقي دائماً على كل الأجهزة.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  unawaited(_nativeLockLandscape());
}

/// الانتقال لشاشة التحميل الأولي قبل الرئيسية (أفقي دائماً على كل الأجهزة).
Future<void> navigateToHomeBootstrap() async {
  if (!await RuntimeSeal.denyBrokenSession()) return;
  unawaited(RuntimeSeal.pulseRemote(force: false));
  await lockHomeScreenLandscape();
  if (Get.currentRoute == screenHomeBootstrap) return;
  Get.offAllNamed(screenHomeBootstrap);
}

/// قفل أفقي للصفحة الرئيسية والأقسام على كل الأجهزة (هاتف، تابلت، تلفاز).
Future<void> lockHomeScreenLandscape() async {
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await _nativeLockLandscape();
}

void changeDeviceOrientBack() {
  // شاشات الدخول أفقية دائماً — لا نرجع للوضع العمودي على الهاتف.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  unawaited(_nativeLockLandscape());
}

/// شاشات الدخول والتسجيل وإضافة القائمة: أفقية دائماً على كل الأجهزة.
Future<void> lockEntryScreenOrientations() async {
  await applyDevicePreferredOrientations();
}

/// وضع أفقي ثابت لأقسام التطبيق بعد الدخول (رئيسية، بث، أفلام، مسلسلات، مفضلة، Catch-up، إعدادات…).
/// يُعاد تطبيقه بعد قفل/فتح الهاتف وتغيّر المقاسات حتى لا يعود Portrait.
mixin LandscapeMainAppStateMixin<T extends StatefulWidget> on State<T> {
  _AppLandscapeRelockObserver? _appLandscapeRelockObserver;

  @override
  void initState() {
    super.initState();
    changeDeviceOrient();
    _appLandscapeRelockObserver = _AppLandscapeRelockObserver(_relockAppLandscapeIfCurrent);
    WidgetsBinding.instance.addObserver(_appLandscapeRelockObserver!);
  }

  @override
  void dispose() {
    final obs = _appLandscapeRelockObserver;
    if (obs != null) {
      WidgetsBinding.instance.removeObserver(obs);
      _appLandscapeRelockObserver = null;
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _relockAppLandscapeIfCurrent();
    });
  }

  void _relockAppLandscapeIfCurrent() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent ?? false) {
      changeDeviceOrient();
    }
  }
}

class _AppLandscapeRelockObserver with WidgetsBindingObserver {
  _AppLandscapeRelockObserver(this.onRelock);

  final VoidCallback onRelock;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onRelock();
    }
  }

  @override
  void didChangeMetrics() {
    onRelock();
  }
}

/// يثبّت الصفحة الرئيسية أفقياً دائماً: عند الفتح، العودة، تدوير الجهاز، واستئناف التطبيق.
mixin HomeLandscapeLockMixin<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(lockHomeScreenLandscape());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _relockHomeLandscapeIfCurrent();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _relockHomeLandscapeIfCurrent();
    }
  }

  @override
  void didChangeMetrics() {
    _relockHomeLandscapeIfCurrent();
  }

  void _relockHomeLandscapeIfCurrent() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent ?? false) {
      unawaited(lockHomeScreenLandscape());
    }
  }
}

/// قيمة `activation_enforced` من اللوحة/التخزين.
/// لا تستخدم `v != false` لأن `0 != false` في Dart تُعتبر true.
bool parseActivationEnforcedFlag(dynamic v, {bool ifMissing = true}) {
  if (v == null) return ifMissing;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase().trim();
  if (s.isEmpty) return ifMissing;
  return s != 'false' && s != '0' && s != 'off' && s != 'no';
}

/// `activation_enforced` من لوحة التحكم (افتراضي: مفعّل = يُفرض واجهة التفعيل).
bool activationEnforcedFromStorage() {
  return parseActivationEnforcedFlag(GetStorage().read('activation_enforced'));
}

/// منع لقطات الشاشة من اللوحة (افتراضي: مفعّل = ممنوع السكرينشوت).
bool blockScreenshotsFromStorage() {
  return parseActivationEnforcedFlag(GetStorage().read('block_screenshots'));
}

Future<void> applyScreenshotProtection({bool? block}) async {
  if (!Platform.isAndroid) return;
  final enabled = block ?? blockScreenshotsFromStorage();
  try {
    await _mainActivityChannel.invokeMethod<bool>(
      'setBlockScreenshots',
      <String, dynamic>{'block': enabled},
    );
  } catch (_) {}
}

/// المدة المتبقية لتفعيل التطبيق من تاريخ الانتهاء المخزّن.
class ActivationRemainingInfo {
  const ActivationRemainingInfo({
    required this.days,
    required this.hours,
    required this.mins,
    required this.totalSeconds,
    required this.expiry,
    this.isLifetime = false,
  });

  final int days;
  final int hours;
  final int mins;
  final int totalSeconds;
  final DateTime expiry;
  final bool isLifetime;

  bool get isValid => isLifetime || totalSeconds > 0;
}

bool activationExpiryLooksLifetime(DateTime expiry) => expiry.year >= 2090;

ActivationRemainingInfo? parseActivationRemaining(String? expiryRaw) {
  final raw = (expiryRaw ?? '').trim();
  if (raw.isEmpty) return null;
  DateTime? expiry;
  try {
    expiry = DateTime.tryParse(raw);
    if (expiry == null && raw.contains(' ')) {
      expiry = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    }
  } catch (_) {
    expiry = null;
  }
  if (expiry == null) return null;
  final lifetime = activationExpiryLooksLifetime(expiry);
  if (lifetime) {
    return ActivationRemainingInfo(
      days: 0,
      hours: 0,
      mins: 0,
      totalSeconds: 1,
      expiry: expiry,
      isLifetime: true,
    );
  }
  final sec = expiry.difference(DateTime.now()).inSeconds;
  if (sec <= 0) {
    return ActivationRemainingInfo(
      days: 0,
      hours: 0,
      mins: 0,
      totalSeconds: 0,
      expiry: expiry,
    );
  }
  final days = sec ~/ 86400;
  final hours = (sec % 86400) ~/ 3600;
  final mins = (sec % 3600) ~/ 60;
  return ActivationRemainingInfo(
    days: days,
    hours: hours,
    mins: mins,
    totalSeconds: sec,
    expiry: expiry,
  );
}

/// شريط التفعيل العلوي: ممتلئ = سنتان.
const int kActivationProgressFullSeconds = 2 * 365 * 86400;

double activationProgressFraction(ActivationRemainingInfo? info) {
  if (info == null) return 0;
  if (info.isLifetime) return 1;
  if (!info.isValid) return 0;
  return (info.totalSeconds / kActivationProgressFullSeconds).clamp(0.0, 1.0);
}

/// نص المدة لحبّة التفعيل (مثل: 361 DAYS LEFT).
String formatActivationPillRemaining(ActivationRemainingInfo info) {
  if (info.isLifetime) return 'activation_lifetime'.tr;
  if (!info.isValid) return 'activation_remaining_expired'.tr;
  String n(int value) => '\u2066$value\u2069';
  if (info.days > 0) {
    return 'activation_days_left'.trParams({'days': n(info.days)});
  }
  if (info.hours > 0) {
    return 'activation_remaining_hm'.trParams({
      'hours': n(info.hours),
      'mins': n(info.mins),
    });
  }
  return 'activation_remaining_m'.trParams({'mins': n(info.mins)});
}

/// أقل من 5 أيام متبقية → نعرض زر تجديد التفعيل.
const int kActivationRenewWithinDays = 5;

bool shouldOfferActivationRenewal(String? expiryRaw) {
  final info = parseActivationRemaining(expiryRaw);
  return info != null &&
      info.isValid &&
      !info.isLifetime &&
      info.days < kActivationRenewWithinDays;
}

/// يفتح رابط التواصل من اللوحة (`support_contact_url`) مع رسالة جاهزة.
/// يدعم WhatsApp / Telegram / mailto؛ باقي الروابط تُفتح كما هي.
Future<bool> openSupportContactWithMessage(String message) async {
  final raw =
      (GetStorage().read('support_contact_url') ?? '').toString().trim();
  if (raw.isEmpty || message.trim().isEmpty) return false;

  try {
    var href = raw;
    if (!href.contains('://') && !href.startsWith('mailto:')) {
      href = 'https://$href';
    }
    final lower = href.toLowerCase();
    final encoded = Uri.encodeComponent(message.trim());
    Uri url;

    if (lower.contains('whatsapp.com') || lower.contains('wa.me')) {
      final join = href.contains('?') ? '&' : '?';
      url = Uri.parse(
        '$href${join}text=$encoded&type=phone_number&app_absent=0',
      );
    } else if (lower.contains('t.me/') || lower.contains('telegram.me/')) {
      final join = href.contains('?') ? '&' : '?';
      url = Uri.parse('$href${join}text=$encoded');
    } else if (lower.startsWith('tg:')) {
      final join = href.contains('?') ? '&' : '?';
      url = Uri.parse('$href${join}text=$encoded');
    } else if (lower.startsWith('mailto:')) {
      final join = href.contains('?') ? '&' : '?';
      url = Uri.parse('$href${join}body=$encoded');
    } else {
      url = Uri.parse(href);
    }

    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// يفتح رابط صفحة تفعيل التطبيق من إعدادات اللوحة.
/// يعيد true إذا فُتح الرابط بنجاح.
Future<bool> openAppActivationPage({String deviceId = ''}) async {
  final raw =
      (GetStorage().read('app_activation_url') ?? '').toString().trim();
  if (raw.isEmpty) return false;

  var id = deviceId.trim();
  if (id.isEmpty) {
    id = (GetStorage().read('device_id') ?? '').toString().trim();
  }
  if (id.isEmpty) return false;

  try {
    Uri url;
    var href = raw;
    if (!href.contains('://')) {
      href = 'https://$href';
    }
    final isWa = href.contains('whatsapp.com') || href.contains('wa.me');
    if (isWa) {
      final message = '${'activation_message'.tr}: $id';
      final join = href.contains('?') ? '&' : '?';
      url = Uri.parse(
        '$href${join}text=${Uri.encodeComponent(message)}&type=phone_number&app_absent=0',
      );
    } else {
      url = Uri.parse(_activationUrlWithDeviceId(href, id));
    }
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// يبني رابط التفعيل مع device_id في الاستعلام وفي الـ hash (احتياطي إن حُذف الـ query بإعادة توجيه).
String _activationUrlWithDeviceId(String raw, String deviceId) {
  final trimmed = raw.trim();
  final encoded = Uri.encodeComponent(deviceId);
  final parsed = Uri.tryParse(trimmed);

  if (parsed != null &&
      parsed.hasScheme &&
      (parsed.isScheme('http') || parsed.isScheme('https'))) {
    final q = Map<String, String>.from(parsed.queryParameters);
    q.remove('deviceId');
    q['device_id'] = deviceId;
    final next = parsed.replace(
      queryParameters: q,
      fragment: 'device_id=$encoded',
    );
    final out = next.toString();
    if (out.contains('device_id=')) return out;
  }

  // مسار يدوي مضمّن لتجنّب مشاكل Uri.replace على بعض الروابط
  final withoutHash = trimmed.split('#').first;
  final join = withoutHash.contains('?') ? '&' : '?';
  return '$withoutHash${join}device_id=$encoded#device_id=$encoded';
}

/// هل نعرض بانر حالة التفعيل؟ عند فرض الواجهة، أو دائماً إذا الجهاز محظور.
bool shouldShowActivationStatusBanner(String status) {
  if (status.trim() == 'محظور') return true;
  return activationEnforcedFromStorage();
}

/// يُمنع الدخول: محظور دائماً؛ منتهي/غير مفعل عند فرض واجهة التفعيل.
bool isActivationLoginDenied(String status) {
  final s = activationEnforcedFromStorage()
      ? ActivationTokenService.effectiveActivationStatus(storedStatus: status)
      : status.trim();
  if (s == 'محظور') return true;
  if (!activationEnforcedFromStorage()) return false;
  if (s == 'منتهي') return true;
  if (s != 'نشط') return true;
  final remaining = parseActivationRemaining(
    (GetStorage().read('activation_expiry_date') ?? '').toString(),
  );
  if (remaining != null && !remaining.isValid) return true;
  return false;
}

const String kStorageIptvServerExpiredKick = 'iptv_server_expired_kick';

/// Toast عند طرد الجلسة بسبب انتهاء اشتراك سيرفر IPTV.
bool showIptvServerExpiredToast(BuildContext context) {
  showWarningToast(
    context,
    'notice_title'.tr,
    'server_subscription_expired'.tr,
  );
  return true;
}

/// يعرض رسالة مترجمة ويمنع المتابعة. يرجع true إذا مُنع الدخول.
bool showActivationLoginDeniedToast(BuildContext context, String status) {
  final s = activationEnforcedFromStorage()
      ? ActivationTokenService.effectiveActivationStatus(storedStatus: status)
      : status.trim();
  if (s == 'محظور') {
    showWarningToast(
      context,
      'activation_failed_title'.tr,
      'login_blocked_activation_banned'.tr,
    );
    return true;
  }
  if (!activationEnforcedFromStorage()) return false;
  final remaining = parseActivationRemaining(
    (GetStorage().read('activation_expiry_date') ?? '').toString(),
  );
  final expiredLocally = remaining != null && !remaining.isValid;
  if (s == 'منتهي' || expiredLocally) {
    showWarningToast(
      context,
      'activation_failed_title'.tr,
      'login_blocked_activation_expired'.tr,
    );
    return true;
  }
  if (s != 'نشط') {
    showWarningToast(
      context,
      'app_not_activated'.tr,
      'please_activate_first'.tr,
    );
    return true;
  }
  return false;
}

bool canPassActivationGate({
  required String status,
  required bool hasPlaylist,
}) {
  final s = activationEnforcedFromStorage()
      ? ActivationTokenService.effectiveActivationStatus(storedStatus: status)
      : status.trim();
  // محظور: لا دخول أبداً (حتى لو فرض التفعيل معطّل).
  if (s == 'محظور') return false;
  // فرض التفعيل معطّل → مفتوح (ما عدا المحظور أعلاه).
  if (!activationEnforcedFromStorage()) return true;
  // وجود حساب/قائمة محفوظة لا يتجاوز التفعيل.
  if (s != 'نشط') return false;
  final remaining = parseActivationRemaining(
    (GetStorage().read('activation_expiry_date') ?? '').toString(),
  );
  if (remaining != null && !remaining.isValid) return false;
  return true;
}

/// هل يُسمح بمحاولة الدخول التلقائي من playlist؟
bool canAttemptPlaylistAutoLogin(String status) {
  return !isActivationLoginDenied(status);
}

/// روابط get.php / m3u / SS IPTV تُعالَج كقائمة كاملة وليس كـ Xtream host فقط.
bool isM3uStylePlaylistUrl(String raw) {
  final u = raw.trim().toLowerCase();
  if (u.isEmpty) return false;
  return u.contains('get.php') ||
      u.contains('.m3u') ||
      u.contains('type=m3u') ||
      u.contains('/playlist') ||
      u.contains('/ssiptv/') ||
      u.contains('download_mode') ||
      u.contains('list_lives') ||
      u.contains('movie_categories') ||
      u.contains('serie_categories');
}

/// قراءة باراميتر الاستعلام من [Uri] بغض النظر عن حالة الأحرف (مثل `Username` مقابل `username`).
String? uriQueryParamIgnoreCase(Uri uri, String name) {
  final want = name.toLowerCase();
  for (final key in uri.queryParameters.keys) {
    if (key.toLowerCase() == want) {
      return uri.queryParameters[key]?.trim();
    }
  }
  return null;
}

/// رابط سيرفر Xtream فقط (مثل `http://host:80`) بدون مسار/استعلام/اعتمادات.
/// يُستخدم لإظهار حقول اليوزر/الباس بدل الدخول كقائمة M3U فارغة.
bool isXtreamHostOnlyUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  final u = uriQueryParamIgnoreCase(uri, 'username') ?? '';
  final p = uriQueryParamIgnoreCase(uri, 'password') ?? '';
  if (u.isNotEmpty || p.isNotEmpty) return false;
  return (uri.path.isEmpty || uri.path == '/') &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;
}

/// أساس السيرفر `scheme://host[:port]` مع الاحتفاظ بالمنفذ كما في الرابط.
String? xtreamServerBaseFromUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
}

/// اعتمادات Xtream المستخرجة من رابط get.php / playlist.
class XtreamUrlCredentials {
  final String serverBase;
  final String username;
  final String password;

  const XtreamUrlCredentials({
    required this.serverBase,
    required this.username,
    required this.password,
  });
}

/// يستخرج اليوزر والباس ورابط السيرفر من رابط مثل:
/// `http://host/get.php?username=...&password=...&type=m3u_plus`
/// ليُعامل مثل الدخول اليدوي عبر player_api.
XtreamUrlCredentials? parseXtreamCredentialsFromUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

  var username = uriQueryParamIgnoreCase(uri, 'username') ?? '';
  var password = uriQueryParamIgnoreCase(uri, 'password') ?? '';

  // بعض الروابط تضع الاعتمادات في المسار: /get.php/USER/PASS/
  if (username.isEmpty || password.isEmpty) {
    final segments =
        uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    final getIdx = segments.indexWhere((s) => s.toLowerCase() == 'get.php');
    if (getIdx >= 0 && segments.length > getIdx + 2) {
      username = segments[getIdx + 1].trim();
      password = segments[getIdx + 2].trim();
    }
  }
  if (username.isEmpty || password.isEmpty) return null;

  // احتفظ بالمنفذ كما جاء في الرابط (بما فيه :80 / :443)
  var base = '${uri.scheme}://${uri.host}';
  if (uri.hasPort) {
    base = '$base:${uri.port}';
  }
  return XtreamUrlCredentials(
    serverBase: base,
    username: username,
    password: password,
  );
}

/// يحفظ رابط get.php كدخول يدوي (يوزر + باس + سيرفر) للدخول التلقائي.
Future<bool> persistAutoLoginAsManualXtream(
  GetStorage storage,
  String rawUrl, {
  bool markFillFromM3u = false,
}) async {
  final creds = parseXtreamCredentialsFromUrl(rawUrl);
  if (creds == null) return false;
  await storage.write('activation_auto_enabled', true);
  await storage.write('activation_auto_username', creds.username);
  await storage.write('activation_auto_password', creds.password);
  await storage.write('activation_auto_domain', creds.serverBase);
  await storage.write('activation_domain', creds.serverBase);
  if (markFillFromM3u) {
    await storage.write(kStorageFillManualFromM3u, true);
  }
  return true;
}

class PanelLoginServer {
  const PanelLoginServer({required this.name, required this.url});
  final String name;
  final String url;
}

List<PanelLoginServer> panelLoginServers() {
  final box = GetStorage();
  final parsed = <PanelLoginServer>[];
  final raw = box.read(kStorageLoginServers);
  if (raw is List) {
    for (final row in raw) {
      if (row is! Map) continue;
      final name = (row['name'] ?? '').toString().trim();
      final url = (row['url'] ?? '').toString().trim();
      if (url.isEmpty) continue;
      parsed.add(PanelLoginServer(name: name, url: url));
    }
  }
  return parsed;
}

/// null = External بدون رابط (خطأ). غير ذلك رابط السيرفر المختار.
String? selectedLoginServerRawUrl(String selectedKey, String typedUrl) {
  if (selectedKey == kLoginServerExternalKey) {
    final t = typedUrl.trim();
    return t.isEmpty ? null : t;
  }
  final idx = int.tryParse(selectedKey);
  final servers = panelLoginServers();
  if (idx == null || idx < 0 || idx >= servers.length) return null;
  final url = servers[idx].url.trim();
  return url.isEmpty ? null : url;
}

/// يستخرج رابط السيرفر فقط لملء خانة Server URL (بدون get.php، مع المنفذ إن وُجد).
String? serverUrlForManualFields(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final parsed = parseXtreamCredentialsFromUrl(s);
  if (parsed != null) {
    return parsed.serverBase.replaceAll(RegExp(r'/+$'), '');
  }
  if (isM3uStylePlaylistUrl(s)) return null;
  var clean = s.replaceAll(RegExp(r'/+$'), '');
  if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
    clean = 'http://$clean';
  }
  // أعد بناء الرابط مع المنفذ الظاهر في النص إن وُجد
  final uri = Uri.tryParse(clean);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    var base = '${uri.scheme}://${uri.host}';
    if (uri.hasPort) base = '$base:${uri.port}';
    return base;
  }
  return clean;
}

/// عند فشل الدخول: امسح بيانات الدخول التلقائي محلياً حتى لا تتكرر المحاولة.
Future<void> clearLocalFailedPlaylistAutoLogin(GetStorage storage) async {
  await storage.write('activation_auto_enabled', false);
  await storage.remove('activation_auto_username');
  await storage.remove('activation_auto_password');
  await storage.remove('activation_auto_domain');
  await storage.remove('activation_domain');
  await storage.remove('activation_just_added_playlist');
  await storage.remove(kStorageFillManualFromM3u);
  await storage.remove('saved_login_username');
  await storage.remove('saved_login_password');
}

/// تجهيز وضع نافذة QR: دخول عادي أو انتظار حساب جديد عند «إضافة حساب».
void prepareDeviceQrDialogLoginMode() {
  final box = GetStorage();
  if (box.read(kStorageAddingNewAccount) == true) {
    box.write(kStorageQrAwaitNewAccount, true);
    box.remove(kStorageQrBaselineReady);
    box.remove(kStorageQrBaselineDomain);
    box.remove(kStorageQrBaselineUsername);
    box.remove(kStorageForceQrAutoLogin);
  } else {
    box.remove(kStorageQrAwaitNewAccount);
    box.remove(kStorageQrBaselineReady);
    box.remove(kStorageQrBaselineDomain);
    box.remove(kStorageQrBaselineUsername);
    box.write(kStorageForceQrAutoLogin, true);
    box.remove(kStorageSuppressPlaylistAutoLogin);
  }
}

void clearQrAwaitNewAccountFlags() {
  final box = GetStorage();
  box.remove(kStorageQrAwaitNewAccount);
  box.remove(kStorageQrBaselineReady);
  box.remove(kStorageQrBaselineDomain);
  box.remove(kStorageQrBaselineUsername);
}

/// إشعار حوار QR بالنجاح ثم انتظار الأنيميشن قبل المتابعة.
Future<void> signalDeviceQrLinkSuccess() async {
  if (Get.isDialogOpen != true) return;
  final box = GetStorage();
  box.write(kStorageQrLinkResult, 'success');
  await Future.delayed(const Duration(milliseconds: 2400));
}

/// إشعار حوار QR بالفشل (مثلاً حد الأجهزة) لإظهار failed.gif في المركز.
void signalDeviceQrLinkFailed() {
  if (Get.isDialogOpen != true) return;
  GetStorage().write(kStorageQrLinkResult, 'failed');
}

/// هل يُسمح بالدخول التلقائي من playlist اللوحة؟
/// عند إضافة حساب عبر QR: لا تدخل للحساب المرتبط مسبقاً؛ انتظر حساباً مختلفاً بعد المسح.
bool shouldAllowPlaylistAutoLogin() {
  final box = GetStorage();
  if (box.read(kStorageSuppressPlaylistAutoLogin) == true) {
    return false;
  }
  final awaitNew = box.read(kStorageQrAwaitNewAccount) == true;
  if (!awaitNew) {
    return box.read(kStorageAddingNewAccount) != true;
  }

  final domain =
      (box.read('activation_auto_domain') ?? '').toString().trim();
  final username =
      (box.read('activation_auto_username') ?? '').toString().trim();

  if (box.read(kStorageQrBaselineReady) != true) {
    box.write(kStorageQrBaselineDomain, domain);
    box.write(kStorageQrBaselineUsername, username);
    box.write(kStorageQrBaselineReady, true);
    return false;
  }

  final baselineDomain =
      (box.read(kStorageQrBaselineDomain) ?? '').toString().trim();
  final baselineUsername =
      (box.read(kStorageQrBaselineUsername) ?? '').toString().trim();

  final sameAccount =
      domain == baselineDomain && username == baselineUsername;
  if (sameAccount) return false;

  // تم ربط حساب مختلف عبر المسح
  clearQrAwaitNewAccountFlags();
  box.remove(kStorageAddingNewAccount);
  return true;
}

bool _isNullishRating(String? value) {
  if (value == null) return true;
  final t = value.trim().toLowerCase();
  return t.isEmpty || t == 'null' || t == '0' || t == '0.0';
}

/// Converts IPTV/TMDB rating fields to a 0–10 display string (e.g. "7.5").
String? formatContentRating(String? rating, [String? rating5based]) {
  double? to10Scale(String? raw) {
    if (_isNullishRating(raw)) return null;
    final v = double.tryParse(raw!.trim());
    if (v == null || v <= 0) return null;
    if (v <= 5) return v * 2;
    return v;
  }

  final score = to10Scale(rating) ?? to10Scale(rating5based);
  if (score == null || score <= 0) return null;
  return score.toStringAsFixed(1);
}

/// نتيجة إغلاق المشغّل: `[positionSec, durationSec, streamId?]`.
/// إن بُدّل الفيلم/الحلقة داخل المشغّل لا يحدّث الـ caller سجل العنصر الأصلي.
bool watchingPopMatchesOpenedStream(dynamic result, String openedStreamId) {
  if (result == null || result is! List || result.isEmpty) return false;
  if (result.length > 2) {
    final returnedId = result[2]?.toString().trim() ?? '';
    final expected = openedStreamId.trim();
    if (returnedId.isNotEmpty &&
        expected.isNotEmpty &&
        returnedId != expected) {
      return false;
    }
  }
  return true;
}
