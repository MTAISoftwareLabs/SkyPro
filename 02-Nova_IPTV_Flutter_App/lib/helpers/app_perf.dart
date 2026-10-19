import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';

/// مستوى أداء الجهاز — الميزات تبقى كاملة؛ يتغيّر فقط تكلفة الصور/الذاكرة/الشبكة.
enum AppPerfLevel { lite, mid, full }

class _DetectResult {
  const _DetectResult({
    required this.level,
    required this.isTelevisionLike,
    required this.isPhoneLike,
  });

  final AppPerfLevel level;
  final bool isTelevisionLike;
  final bool isPhoneLike;
}

/// بروفايل تكيّفي لأجهزة Android/TV **والهواتف** الضعيفة.
/// إجبار يدوي عبر التخزين: `app_perf_force` = lite | mid | full
class AppPerf {
  AppPerf._({
    required this.level,
    required this.thumbW,
    required this.thumbH,
    required this.homePosterW,
    required this.homePosterH,
    required this.thumbSmallW,
    required this.thumbSmallH,
    required this.backdropW,
    required this.backdropH,
    required this.imageConcurrentFetches,
    required this.imageCacheMaxEntries,
    required this.imageCacheMaxBytes,
    required this.diskCacheObjects,
    required this.catalogFetchConcurrency,
    required this.catalogCacheExtent,
    required this.useSystemFonts,
    required this.posterFadeMs,
    required this.useLowFilterQuality,
    required this.reduceFocusMotion,
    required this.focusAnimMs,
    required this.isTelevisionLike,
    required this.isPhoneLike,
  });

  final AppPerfLevel level;
  final int thumbW;
  final int thumbH;
  final int homePosterW;
  final int homePosterH;
  final int thumbSmallW;
  final int thumbSmallH;
  final int backdropW;
  final int backdropH;
  final int imageConcurrentFetches;
  final int imageCacheMaxEntries;
  final int imageCacheMaxBytes;
  final int diskCacheObjects;
  final int catalogFetchConcurrency;
  final double catalogCacheExtent;
  final bool useSystemFonts;
  /// مدة ظهور الصورة — 0 على الأجهزة الضعيفة لتفادي أنيميشن الـ GPU.
  final int posterFadeMs;
  final bool useLowFilterQuality;
  /// إيقاف تكبير/هالة التركيز على الأجهزة الضعيفة (إطار فقط) — هاتف + تلفاز.
  final bool reduceFocusMotion;
  final int focusAnimMs;
  final bool isTelevisionLike;
  final bool isPhoneLike;

  bool get isLite => level == AppPerfLevel.lite;
  bool get isMid => level == AppPerfLevel.mid;

  Duration get focusAnimDuration => Duration(milliseconds: focusAnimMs);

  static AppPerf instance = _full();

  static bool _initialized = false;

  static Timer? _imageCacheRestoreTimer;
  static const int _memoryPressureMinCacheBytes = 8 << 20; // 8 MB during severe pressure
  static const Duration _memoryPressureRestoreDelay = Duration(seconds: 10);

  static AppPerf _lite({
    bool isTelevisionLike = false,
    bool isPhoneLike = true,
  }) =>
      AppPerf._(
        level: AppPerfLevel.lite,
        thumbW: 150,
        thumbH: 225,
        homePosterW: 150,
        homePosterH: 225,
        thumbSmallW: 110,
        thumbSmallH: 154,
        backdropW: 300,
        backdropH: 420,
        imageConcurrentFetches: 3,
        // سقف آمن للأجهزة 1GB RAM لتفادي Dalvik/ART OOM وموت العملية
        imageCacheMaxEntries: 100,
        imageCacheMaxBytes: 32 << 20, // 32 MB
        diskCacheObjects: 600,
        catalogFetchConcurrency: 2,
        catalogCacheExtent: 100,
        useSystemFonts: true,
        posterFadeMs: 0,
        useLowFilterQuality: true,
        reduceFocusMotion: true,
        focusAnimMs: 0,
        isTelevisionLike: isTelevisionLike,
        isPhoneLike: isPhoneLike,
      );

  static AppPerf _mid({
    required bool reduceFocusMotion,
    bool isTelevisionLike = false,
    bool isPhoneLike = true,
  }) =>
      AppPerf._(
        level: AppPerfLevel.mid,
        thumbW: 200,
        thumbH: 300,
        homePosterW: 200,
        homePosterH: 300,
        thumbSmallW: 140,
        thumbSmallH: 196,
        backdropW: 360,
        backdropH: 504,
        imageConcurrentFetches: 5,
        // أجهزة 2GB RAM: كاش متوازن وسريع بدون ضغط الذاكرة
        imageCacheMaxEntries: 180,
        imageCacheMaxBytes: 64 << 20, // 64 MB
        diskCacheObjects: 1200,
        catalogFetchConcurrency: 3,
        catalogCacheExtent: 180,
        useSystemFonts: false,
        posterFadeMs: 80,
        useLowFilterQuality: true,
        reduceFocusMotion: reduceFocusMotion,
        focusAnimMs: reduceFocusMotion ? 0 : 70,
        isTelevisionLike: isTelevisionLike,
        isPhoneLike: isPhoneLike,
      );

  static AppPerf _full({
    bool isTelevisionLike = false,
    bool isPhoneLike = true,
  }) =>
      AppPerf._(
        level: AppPerfLevel.full,
        thumbW: 260,
        thumbH: 390,
        homePosterW: 260,
        homePosterH: 390,
        thumbSmallW: 180,
        thumbSmallH: 252,
        backdropW: 440,
        backdropH: 616,
        imageConcurrentFetches: 8,
        imageCacheMaxEntries: 350,
        imageCacheMaxBytes: 128 << 20, // 128 MB
        diskCacheObjects: 2000,
        catalogFetchConcurrency: 5,
        catalogCacheExtent: 260,
        useSystemFonts: false,
        posterFadeMs: 140,
        useLowFilterQuality: false,
        reduceFocusMotion: false,
        focusAnimMs: 120,
        isTelevisionLike: isTelevisionLike,
        isPhoneLike: isPhoneLike,
      );

  static AppPerfLevel? _forcedLevel() {
    try {
      final raw = (GetStorage().read('app_perf_force') ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (raw == 'lite' || raw == 'low') return AppPerfLevel.lite;
      if (raw == 'mid' || raw == 'medium') return AppPerfLevel.mid;
      if (raw == 'full' || raw == 'high') return AppPerfLevel.full;
    } catch (_) {}
    return null;
  }

  static Future<_DetectResult> _detect() async {
    final forced = _forcedLevel();
    var score = 0; // أعلى = أضعف
    var isTv = false;
    var isPhone = true;

    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        final features = a.systemFeatures.join(' ').toLowerCase();
        isTv = features.contains('leanback') ||
            features.contains('television') ||
            features.contains('android.software.leanback');
        isPhone = !isTv;

        final model =
            '${a.model} ${a.device} ${a.hardware} ${a.board} ${a.product} ${a.brand} ${a.manufacturer}'
                .toLowerCase();

        // Firestick / Amazon TV detection
        if (model.contains('amazon') || model.contains('aft')) {
          isTv = true;
          isPhone = false;
          score += 2;
        }

        // قياس الذاكرة الحقيقية من النظام مباشرة لكشف أجهزة 1GB / 2GB بدقة
        int? totalMemMb;
        bool? isLowRamNative;
        try {
          const channel = MethodChannel('main_activity_channel');
          final mem = await channel.invokeMapMethod<String, dynamic>('getDeviceMemoryInfo');
          if (mem != null) {
            final totalBytes = (mem['totalMem'] as num?)?.toInt() ?? 0;
            if (totalBytes > 0) {
              totalMemMb = totalBytes ~/ (1024 * 1024);
            }
            isLowRamNative = mem['isLowRamDevice'] as bool?;
          }
        } catch (_) {}

        if (isLowRamNative == true || a.isLowRamDevice) {
          score += 5;
        }

        if (totalMemMb != null) {
          if (totalMemMb <= 1350) {
            // أجهزة 1GB RAM أو أقل (Firestick Lite/Basic، TV Boxes رخيصة)
            score += 6;
          } else if (totalMemMb <= 2350) {
            // أجهزة 2GB RAM (Firestick 4K، تي في بوكس متوسط)
            score += 3;
          }
        }

        final sdk = a.version.sdkInt;
        if (sdk < 26) {
          score += 4;
        } else if (sdk < 28) {
          score += 3;
        } else if (sdk < 30) {
          score += 2;
        } else if (sdk < 33) {
          score += 1;
        }

        // TV boxes + هواتف دخول (MediaTek / Unisoc / Adreno قديم / Amlogic).
        if (RegExp(
          r'amlogic|s905|s905x|s905w|s905y|rk322|rk3328|rk3128|allwinner|h3\b|h6\b|'
          r'mali-400|mali-450|mali-t720|mali-t760|mali-g31|mali-g51|'
          r'adreno\s?(3|4|5)0[0-9]|adreno\s?610|'
          r'helio\s?p(1|2|3)|helio\s?g(25|35|37|85|88)|'
          r'mt67(35|53|65|67|69)|mt676[1-5]|mt6833|sc98|unisoc|spreadtrum|tiger\s?t[0-9]|'
          r'snapdragon\s?(4[0-9]{2}|6[0-5]0)|sdm4[0-9]{2}|msm8[89]',
        ).hasMatch(model)) {
          score += 3;
        }

        // Android Go / edition — هواتف ضعيفة شائعة.
        if (RegExp(r'\b(go|edition)\b').hasMatch(model)) {
          score += 3;
        }
        if (model.contains(' redmi ') &&
            RegExp(r'\b(a[0-9]|go|note [4-7])\b').hasMatch(model)) {
          score += 2;
        }
        if (RegExp(r'\b(nokia c|itel |tecno spark [1-5]|infinix smart)\b')
            .hasMatch(model)) {
          score += 2;
        }

        if (isTv && sdk < 30) score += 1;
        // هواتف: عتبة أخف شوية باش lit/mid يتفعلو أكثر على الأجهزة الدخولية.
        if (isPhone && sdk < 29) score += 1;
      } else if (Platform.isIOS) {
        isTv = false;
        isPhone = true;
        final ios = await plugin.iosInfo;
        final m = ios.utsname.machine.toLowerCase();
        if (RegExp(r'iphone(6,|7,|8,|9,|10,)|ipad(5,|6,|7,)').hasMatch(m)) {
          score += 4;
        } else if (RegExp(r'iphone11,').hasMatch(m)) {
          score += 2;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AppPerf] detect failed: $e');
    }

    // صناديق التلفاز غالباً GPU ضعيف حتى لو RAM ما تباش low-ram.
    if (isTv) score += 2;

    AppPerfLevel levelFromScore;
    if (kIsWeb) {
      levelFromScore = AppPerfLevel.full;
    } else if (score >= 4) {
      // عتبة أخف من 5 باش الأجهزة الضعيفة تدخل lite أسهل.
      levelFromScore = AppPerfLevel.lite;
    } else if (score >= 2) {
      levelFromScore = AppPerfLevel.mid;
    } else {
      levelFromScore = AppPerfLevel.full;
    }
    _autoDetectedLevel = levelFromScore;

    final level = forced ?? levelFromScore;

    return _DetectResult(
      level: level,
      isTelevisionLike: isTv,
      isPhoneLike: isPhone,
    );
  }

  static AppPerf _build(_DetectResult d) {
    final tv = d.isTelevisionLike;
    final phone = d.isPhoneLike;
    final built = switch (d.level) {
      AppPerfLevel.lite => _lite(isTelevisionLike: tv, isPhoneLike: phone),
      AppPerfLevel.mid => _mid(
          // mid + هاتف/تلفاز: تخفيف التركيز (blur/scale كيطيّحو الإطارات).
          reduceFocusMotion: phone || tv,
          isTelevisionLike: tv,
          isPhoneLike: phone,
        ),
      AppPerfLevel.full => _full(isTelevisionLike: tv, isPhoneLike: phone),
    };
    return tv ? _capForTelevision(built) : built;
  }

  /// التلفاز: نفس الواجهة، تكلفة GPU/RAM أقل (فك صور أصغر، بلا blur/scale).
  static AppPerf _capForTelevision(AppPerf p) {
    int minInt(int a, int b) => a < b ? a : b;
    final maxBytesCap = p.isLite ? (32 << 20) : (64 << 20);
    final maxEntriesCap = p.isLite ? 100 : 180;

    return AppPerf._(
      level: p.level,
      thumbW: minInt(p.thumbW, 180),
      thumbH: minInt(p.thumbH, 270),
      homePosterW: minInt(p.homePosterW, 180),
      homePosterH: minInt(p.homePosterH, 270),
      thumbSmallW: minInt(p.thumbSmallW, 130),
      thumbSmallH: minInt(p.thumbSmallH, 182),
      backdropW: minInt(p.backdropW, 340),
      backdropH: minInt(p.backdropH, 476),
      imageConcurrentFetches: minInt(p.imageConcurrentFetches, p.isLite ? 3 : 4),
      imageCacheMaxEntries: minInt(p.imageCacheMaxEntries, maxEntriesCap),
      imageCacheMaxBytes: minInt(p.imageCacheMaxBytes, maxBytesCap),
      diskCacheObjects: minInt(p.diskCacheObjects, 1000),
      catalogFetchConcurrency: minInt(p.catalogFetchConcurrency, 2),
      catalogCacheExtent: p.catalogCacheExtent < 120 ? p.catalogCacheExtent : 120,
      useSystemFonts: p.useSystemFonts,
      posterFadeMs: 0,
      useLowFilterQuality: true,
      reduceFocusMotion: true,
      focusAnimMs: 0,
      isTelevisionLike: true,
      isPhoneLike: false,
    );
  }

  static AppPerfLevel? _autoDetectedLevel;

  /// المستوى الذي اختاره النظام بدون فرض المستخدم.
  static AppPerfLevel get autoDetectedLevel =>
      _autoDetectedLevel ?? instance.level;

  /// اختيار المستخدم: `auto` | `lite` | `mid` | `full`
  static String currentUserChoice() {
    try {
      final raw = (GetStorage().read('app_perf_force') ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (raw == 'lite' || raw == 'low') return 'lite';
      if (raw == 'mid' || raw == 'medium') return 'mid';
      if (raw == 'full' || raw == 'high') return 'full';
    } catch (_) {}
    return 'auto';
  }

  /// يطبّق اختيار المستخدم فوراً (من الإعدادات) ويعيد ضبط كاش الصور.
  static Future<AppPerf> applyUserChoice(String choice) async {
    final key = choice.trim().toLowerCase();
    final box = GetStorage();
    if (key.isEmpty || key == 'auto') {
      try {
        box.remove('app_perf_force');
      } catch (_) {
        box.write('app_perf_force', '');
      }
    } else if (key == 'lite' || key == 'mid' || key == 'full') {
      box.write('app_perf_force', key);
    }
    final detected = await _detect();
    instance = _build(detected);
    _initialized = true;
    applyToFlutterImageCache();
    if (kDebugMode) {
      debugPrint(
        '[AppPerf] userChoice=$key effective=${instance.level.name} '
        'auto=${autoDetectedLevel.name} reduceFocus=${instance.reduceFocusMotion}',
      );
    }
    return instance;
  }

  /// يُستدعى مرة واحدة من [main] قبل [runApp].
  static Future<AppPerf> init() async {
    if (_initialized) return instance;
    final detected = await _detect();
    instance = _build(detected);
    _initialized = true;
    applyToFlutterImageCache();

    if (Platform.isAndroid) {
      try {
        const MethodChannel('main_activity_channel')
            .setMethodCallHandler((call) async {
          if (call.method == 'onNativeLowMemory') {
            onMemoryPressure(isUrgent: true);
          }
        });
      } catch (_) {}
    }

    if (kDebugMode) {
      debugPrint(
        '[AppPerf] level=${instance.level.name} '
        'phone=${instance.isPhoneLike} tv=${instance.isTelevisionLike} '
        'reduceFocus=${instance.reduceFocusMotion} '
        'imgConcurrency=${instance.imageConcurrentFetches} '
        'thumb=${instance.thumbW}x${instance.thumbH} '
        'cacheLimit=${instance.imageCacheMaxBytes ~/ (1024 * 1024)}MB',
      );
    }
    return instance;
  }

  static void applyToFlutterImageCache() {
    try {
      final p = instance;
      final cache = PaintingBinding.instance.imageCache;
      cache.maximumSize = p.imageCacheMaxEntries;
      cache.maximumSizeBytes = p.imageCacheMaxBytes;
    } catch (e) {
      if (kDebugMode) debugPrint('[AppPerf] imageCache tune failed: $e');
    }
  }

  /// عند ضغط الذاكرة — مسح الكاشات الحية فوراً وتقليل السقف مؤقتاً لتجنب القتل بواسطة LMK.
  static void onMemoryPressure({bool isUrgent = false}) {
    try {
      final cache = PaintingBinding.instance.imageCache;
      if (isUrgent || instance.isLite) {
        cache.clear();
        cache.clearLiveImages();
      }
      final originalBytes = instance.imageCacheMaxBytes;
      final reduced = (originalBytes ~/ 2).clamp(
        _memoryPressureMinCacheBytes,
        originalBytes,
      );

      _imageCacheRestoreTimer?.cancel();
      cache.maximumSizeBytes = reduced;

      _imageCacheRestoreTimer = Timer(_memoryPressureRestoreDelay, () {
        _imageCacheRestoreTimer = null;
        applyToFlutterImageCache();
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppPerf] imageCache memory pressure trim failed: $e');
      }
    }
  }
}
