part of 'helpers.dart';

/// Xtream lifetime غالباً: فاضي / 0 / Unlimited / تاريخ بعيد (≥2090).
bool isIptvLifetimeExpDate(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty || s == '0' || s == '-' || s.toLowerCase() == 'null') {
    return true;
  }
  final lower = s.toLowerCase();
  if (lower.contains('unlimited') ||
      lower.contains('lifetime') ||
      lower.contains('forever') ||
      lower.contains('permanent') ||
      lower == 'inf' ||
      lower == '∞' ||
      lower.contains('مدى الحياة') ||
      lower.contains('غير محدود') ||
      lower.contains('مادام') ||
      lower.contains('à vie') ||
      lower.contains('de por vida') ||
      lower.contains('a vita') ||
      lower.contains('终身')) {
    return true;
  }
  final n = int.tryParse(s);
  if (n != null) {
    if (n <= 0) return true;
    final millis = s.length > 12 ? n : n * 1000;
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(millis);
      return activationExpiryLooksLifetime(dt);
    } catch (_) {
      return false;
    }
  }
  final parsed = DateTime.tryParse(s) ??
      DateTime.tryParse(s.replaceFirst(' ', 'T'));
  if (parsed != null) return activationExpiryLooksLifetime(parsed);
  return false;
}

String expirationDate(String? timestamp) {
  final raw = (timestamp ?? '').trim();
  if (isIptvLifetimeExpDate(raw)) return 'activation_lifetime'.tr;
  try {
    final n = int.tryParse(raw);
    if (n != null) {
      final millis = raw.length > 12 ? n : n * 1000;
      final date = DateTime.fromMillisecondsSinceEpoch(millis);
      if (activationExpiryLooksLifetime(date)) return 'activation_lifetime'.tr;
      return DateFormat('dd MMM, yyyy').format(date);
    }
    final parsed = DateTime.tryParse(raw) ??
        DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (parsed != null) {
      if (activationExpiryLooksLifetime(parsed)) return 'activation_lifetime'.tr;
      return DateFormat('dd MMM, yyyy').format(parsed);
    }
  } catch (_) {}
  // ما نبقاوش نعرضو "error date" — النص الأصلي أو Lifetime إن كان غامضاً.
  if (raw.isEmpty) return 'activation_lifetime'.tr;
  return raw;
}

/// تاريخ إصدار فيلم/مسلسل من Xtream: غالباً نص (`2020-05-15`) وأحياناً Unix.
String formatVodReleaseDate(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty || t.toLowerCase() == 'null' || t == '-') return '';
  if (RegExp(r'^\d{9,13}$').hasMatch(t)) {
    try {
      final n = int.parse(t);
      final ms = t.length > 12 ? n : n * 1000;
      return DateFormat('dd MMM, yyyy').format(
        DateTime.fromMillisecondsSinceEpoch(ms),
      );
    } catch (_) {
      return t;
    }
  }
  return t;
}

/// يستخرج معرف يوتيوب أو يعيد القيمة إن كانت صالحة — يمنع كسر الرابط الكامل.
String? normalizeYoutubeTrailerRef(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty || t.toLowerCase() == 'null' || t == 'false') return null;
  if (!t.contains('://') && !t.contains('/') && RegExp(r'^[\w-]{6,}$').hasMatch(t)) {
    return t;
  }
  final uri = Uri.tryParse(t);
  if (uri == null) return t;
  final host = uri.host.toLowerCase();
  if (host.contains('youtu.be')) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first.trim() : '';
    return id.isEmpty ? t : id;
  }
  final v = uri.queryParameters['v']?.trim();
  if (v != null && v.isNotEmpty) return v;
  final segs = uri.pathSegments;
  for (var i = 0; i < segs.length - 1; i++) {
    if (segs[i] == 'embed' || segs[i] == 'shorts' || segs[i] == 'v') {
      final id = segs[i + 1].trim();
      if (id.isNotEmpty) return id;
    }
  }
  return t;
}

DateTime? parseIptvExpDate(String? timestamp) {
  try {
    final raw = (timestamp ?? '').trim();
    if (raw.isEmpty || raw == '0' || raw.toLowerCase() == 'null') {
      return null;
    }
    if (isIptvLifetimeExpDate(raw)) return null;
    final n = int.tryParse(raw);
    if (n != null) {
      // Unix seconds vs milliseconds (same heuristic as Smart TV).
      final millis = raw.length > 12 ? n : n * 1000;
      final dt = DateTime.fromMillisecondsSinceEpoch(millis);
      if (activationExpiryLooksLifetime(dt)) return null;
      return dt;
    }
    final parsed = DateTime.tryParse(raw) ??
        DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (parsed != null && activationExpiryLooksLifetime(parsed)) return null;
    return parsed;
  } catch (_) {
    return null;
  }
}

/// انتهى اشتراك السيرفر فعلياً (حسب الوقت، ليس اليوم فقط).
bool isIptvServerExpDatePassed(String? timestamp) {
  if (isIptvLifetimeExpDate(timestamp)) return false;
  final exp = parseIptvExpDate(timestamp);
  if (exp == null) return false;
  return !DateTime.now().isBefore(exp);
}

bool isIptvAccountStatusBlocked(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  return s == 'expired' ||
      s == 'disabled' ||
      s == 'banned' ||
      s == 'closed';
}

/// جلسة Xtream (يوزر/باس) منتهية أو مرفوضة — قوائم M3U بدون اعتمادات تُستثنى.
bool shouldBlockExpiredIptvSession({
  required String? expDate,
  required String? status,
  required String? username,
  required String? password,
}) {
  final u = (username ?? '').trim();
  final p = (password ?? '').trim();
  if (u.isEmpty && p.isEmpty) return false;
  if (isIptvAccountStatusBlocked(status)) return true;
  return isIptvServerExpDatePassed(expDate);
}

/// مدة الاشتراك المتبقية بالوقت الفعلي (أيام / ساعات / دقائق).
enum IptvRemainingUnit { days, hours, minutes }

class IptvSubscriptionRemaining {
  const IptvSubscriptionRemaining({
    required this.unit,
    required this.value,
    required this.expired,
    this.isLifetime = false,
  });

  final IptvRemainingUnit unit;
  final int value;
  final bool expired;
  final bool isLifetime;
}

IptvSubscriptionRemaining? iptvSubscriptionRemaining(String? timestamp) {
  if (isIptvLifetimeExpDate(timestamp)) {
    return const IptvSubscriptionRemaining(
      unit: IptvRemainingUnit.days,
      value: 0,
      expired: false,
      isLifetime: true,
    );
  }
  final exp = parseIptvExpDate(timestamp);
  if (exp == null) return null;
  final now = DateTime.now();
  if (!now.isBefore(exp)) {
    return const IptvSubscriptionRemaining(
      unit: IptvRemainingUnit.days,
      value: 0,
      expired: true,
    );
  }
  final d = exp.difference(now);
  if (d.inDays >= 1) {
    return IptvSubscriptionRemaining(
      unit: IptvRemainingUnit.days,
      value: d.inDays,
      expired: false,
    );
  }
  if (d.inHours >= 1) {
    return IptvSubscriptionRemaining(
      unit: IptvRemainingUnit.hours,
      value: d.inHours,
      expired: false,
    );
  }
  final mins = d.inMinutes <= 0 ? 1 : d.inMinutes;
  return IptvSubscriptionRemaining(
    unit: IptvRemainingUnit.minutes,
    value: mins,
    expired: false,
  );
}

/// نص قصير للإعدادات: "5 أيام" / "23 ساعة" / "45 دقيقة".
String formatIptvSubscriptionRemainingShort(String? timestamp) {
  final rem = iptvSubscriptionRemaining(timestamp);
  if (rem == null) return 'not_available'.tr;
  if (rem.isLifetime) return 'activation_lifetime'.tr;
  if (rem.expired) return 'subscription_expired'.tr;
  switch (rem.unit) {
    case IptvRemainingUnit.days:
      return 'subscription_remaining_days'.trParams({'n': '${rem.value}'});
    case IptvRemainingUnit.hours:
      return 'subscription_remaining_hours'.trParams({'n': '${rem.value}'});
    case IptvRemainingUnit.minutes:
      return 'subscription_remaining_minutes'.trParams({'n': '${rem.value}'});
  }
}

String getDurationMovie(String? time) {
  try {
    if (time == null) {
      return "";
    }

    //  List<String> list = time.split(":");
    //debugPrint("time! $list");

    var date = DateTime.parse("2022-12-21 $time");
    // debugPrint("DATE: $date");
    var hour = DateFormat("HH").format(date);
    var minuets = DateFormat("mm").format(date);
    var second = DateFormat("ss").format(date);

    return "${hour == "00" ? "" : "${hour}h"} ${minuets == "00" ? "" : "${minuets}m"} ${second == "00" ? "" : "${second}s"}";
  } catch (e) {
    debugPrint("Error: $e");
    return 'error';
  }
}

/// تنسيق موضع المشاهدة بالثواني إلى `HH:MM:SS` (مثل 00:01:30).
String formatWatchPositionSeconds(double seconds) {
  final total = seconds.isFinite ? seconds.floor().clamp(0, 359999) : 0;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}

/// نسبة شريط التقدّم (null إن لم تُشاهد أو اكتملت تقريباً).
double? watchProgressRatio(double sliderValue, double durationStrm) {
  if (sliderValue <= 0) return null;
  if (durationStrm <= 0) {
    // مدة غير محفوظة لكن يوجد موضع مشاهدة: أظهر شريطاً تقريبياً مرئياً
    if (sliderValue < 15) return null;
    return 0.18;
  }
  final ratio = (sliderValue / durationStrm).clamp(0.0, 1.0);
  if (ratio >= 0.95) return null;
  // تأكد أن الشريط يظهر حتى للتقدّم الصغير نسبياً
  return ratio < 0.02 ? 0.02 : ratio;
}

/// هل نعرض حوار استكمال المشاهدة؟ (بعد 15 ثانية على الأقل، وقبل الاكتمال تقريباً)
bool shouldOfferResumePlayback({
  required double? positionSeconds,
  double? durationSeconds,
}) {
  if (positionSeconds == null || positionSeconds < 15) return false;
  if (durationSeconds != null &&
      durationSeconds > 0 &&
      positionSeconds / durationSeconds >= 0.95) {
    return false;
  }
  return true;
}
