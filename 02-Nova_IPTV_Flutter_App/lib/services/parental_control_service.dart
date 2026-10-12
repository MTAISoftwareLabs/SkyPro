import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mehdi_iptv/presentation/widgets/parental_pin_dialog.dart';
import 'package:mehdi_iptv/repository/models/category.dart';
import 'package:mehdi_iptv/repository/models/channel_live.dart';
import 'package:mehdi_iptv/repository/models/channel_movie.dart';
import 'package:mehdi_iptv/repository/models/channel_serie.dart';

typedef ParentalCategoryNameResolver = String? Function(String? categoryId);

/// الأقسام التي يمكن قفلها بالرقابة الأبوية.
enum ParentalSection { live, movies, series, settings }

/// إدارة الرقابة الأبوية: التخزين، التحقق من PIN، وتصفية التصنيفات.
class ParentalControlService {
  ParentalControlService._();

  static final ParentalControlService instance = ParentalControlService._();

  static const String kStorageEnabled = 'parental_control_enabled';
  static const String kStoragePinHash = 'parental_pin_hash';
  static const String kStorageLockLive = 'parental_lock_live';
  static const String kStorageLockMovies = 'parental_lock_movies';
  static const String kStorageLockSeries = 'parental_lock_series';
  static const String kStorageLockSettings = 'parental_lock_settings';
  static const String kStorageHideAdult = 'parental_hide_adult';

  /// كلمات مفتاحية لتصنيفات +18 — يمكن تعديلها لاحقاً بسهولة.
  static const List<String> adultCategoryKeywords = [
    'adult',
    'adults',
    'for adult',
    'xxx',
    '18+',
    '+18',
    'porn',
    'porno',
    'sex',
    'erotic',
    'erotik',
    'mature',
    'hot',
    'xxx vod',
    'للبالغين',
    'كبار',
  ];

  static const int pinLength = 4;
  static const String _pinSalt = 'mehdi_iptv_parental_v1';

  GetStorage get _box => GetStorage();

  ParentalSection? _sessionUnlockedSection;
  DateTime? _sessionUnlockTime;
  DateTime? _sessionAdultUnlockTime;

  /// منح وصول مؤقت بعد إدخال PIN صحيح (يتجنب طلب PIN مرتين).
  void grantSessionAccess(ParentalSection section) {
    _sessionUnlockedSection = section;
    _sessionUnlockTime = DateTime.now();
  }

  /// هل لا يزال الوصول المؤقت سارياً؟
  bool hasSessionAccess(ParentalSection section) {
    if (_sessionUnlockedSection != section || _sessionUnlockTime == null) {
      return false;
    }
    return DateTime.now().difference(_sessionUnlockTime!) <
        const Duration(minutes: 10);
  }

  void clearSessionAccess() {
    _sessionUnlockedSection = null;
    _sessionUnlockTime = null;
    _sessionAdultUnlockTime = null;
  }

  bool get isAdultContentBlocked => isEnabled && hideAdultCategories;

  void grantAdultSessionAccess() {
    _sessionAdultUnlockTime = DateTime.now();
  }

  bool hasAdultSessionAccess() {
    final at = _sessionAdultUnlockTime;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(minutes: 10);
  }

  static bool _isTruthyAdultFlag(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes';
  }

  bool get isEnabled => _box.read(kStorageEnabled) == true;

  bool get hasPin {
    final stored = _box.read(kStoragePinHash);
    return stored is String && stored.isNotEmpty;
  }

  bool get lockLive => _box.read(kStorageLockLive) == true;

  bool get lockMovies => _box.read(kStorageLockMovies) == true;

  bool get lockSeries => _box.read(kStorageLockSeries) == true;

  bool get lockSettings => _box.read(kStorageLockSettings) == true;

  bool get hideAdultCategories => _box.read(kStorageHideAdult) == true;

  void setLockLive(bool value) => _box.write(kStorageLockLive, value);

  void setLockMovies(bool value) => _box.write(kStorageLockMovies, value);

  void setLockSeries(bool value) => _box.write(kStorageLockSeries, value);

  void setLockSettings(bool value) => _box.write(kStorageLockSettings, value);

  void setHideAdultCategories(bool value) => _box.write(kStorageHideAdult, value);

  /// هل القسم مقفول حالياً؟
  bool isSectionLocked(ParentalSection section) {
    if (!isEnabled) return false;
    return switch (section) {
      ParentalSection.live => lockLive,
      ParentalSection.movies => lockMovies,
      ParentalSection.series => lockSeries,
      ParentalSection.settings => lockSettings,
    };
  }

  /// تجزئة PIN بسيطة للتخزين المحلي.
  String hashPin(String pin) {
    var hash = 0x811C9DC5;
    for (final unit in '$_pinSalt$pin'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  bool verifyPin(String pin) {
    if (pin.length != pinLength) return false;
    final stored = _box.read(kStoragePinHash);
    if (stored is! String || stored.isEmpty) return false;
    return stored == hashPin(pin);
  }

  /// حفظ PIN جديد وتفعيل الرقابة.
  Future<bool> savePinAndEnable(String pin) async {
    if (pin.length != pinLength) return false;
    await _box.write(kStoragePinHash, hashPin(pin));
    await _box.write(kStorageEnabled, true);
    return true;
  }

  Future<bool> changePin(String currentPin, String newPin) async {
    if (!verifyPin(currentPin) || newPin.length != pinLength) return false;
    await _box.write(kStoragePinHash, hashPin(newPin));
    return true;
  }

  Future<bool> disableParentalControl(String currentPin) async {
    if (!verifyPin(currentPin)) return false;
    await _box.write(kStorageEnabled, false);
    return true;
  }

  /// تفعيل الرقابة عندما يوجد PIN مسبقاً.
  Future<bool> enableWithExistingPin() async {
    if (!hasPin) return false;
    await _box.write(kStorageEnabled, true);
    return true;
  }

  /// هل اسم التصنيف يُعتبر للبالغين؟
  bool isAdultCategoryName(String? name) {
    if (!isAdultContentBlocked) return false;
    final lower = (name ?? '').toLowerCase();
    for (final keyword in adultCategoryKeywords) {
      if (lower.contains(keyword.toLowerCase())) return true;
    }
    return false;
  }

  /// إزالة تصنيفات +18 من القائمة.
  List<CategoryModel> filterAdultCategories(List<CategoryModel> categories) {
    if (!isAdultContentBlocked) return categories;
    return categories
        .where((c) => !isAdultCategoryName(c.categoryName))
        .toList();
  }

  static String? categoryNameFromId(
    String? categoryId,
    List<CategoryModel> categories,
  ) {
    final id = categoryId?.trim();
    if (id == null || id.isEmpty) return null;
    for (final c in categories) {
      if (c.categoryId == id) return c.categoryName;
    }
    return null;
  }

  bool isAdultLiveChannel(
    ChannelLive channel, {
    String? categoryName,
  }) {
    if (!isAdultContentBlocked) return false;
    if (_isTruthyAdultFlag(channel.isAdult)) return true;
    if (isAdultCategoryName(categoryName)) return true;
    if (isAdultCategoryName(channel.name)) return true;
    return false;
  }

  bool isAdultMovie(
    ChannelMovie movie, {
    String? categoryName,
  }) {
    if (!isAdultContentBlocked) return false;
    if (_isTruthyAdultFlag(movie.isAdult)) return true;
    if (isAdultCategoryName(categoryName)) return true;
    if (isAdultCategoryName(movie.name)) return true;
    return false;
  }

  bool isAdultSerie(
    ChannelSerie serie, {
    String? categoryName,
  }) {
    if (!isAdultContentBlocked) return false;
    if (isAdultCategoryName(categoryName)) return true;
    if (isAdultCategoryName(serie.name)) return true;
    return false;
  }

  List<ChannelLive> filterAdultLiveChannels(
    List<ChannelLive> channels, {
    ParentalCategoryNameResolver? categoryNameForId,
  }) {
    if (!isAdultContentBlocked) return channels;
    return channels
        .where(
          (c) => !isAdultLiveChannel(
            c,
            categoryName: categoryNameForId?.call(c.categoryId),
          ),
        )
        .toList();
  }

  List<ChannelMovie> filterAdultMovies(
    List<ChannelMovie> movies, {
    ParentalCategoryNameResolver? categoryNameForId,
  }) {
    if (!isAdultContentBlocked) return movies;
    return movies
        .where(
          (m) => !isAdultMovie(
            m,
            categoryName: categoryNameForId?.call(m.categoryId),
          ),
        )
        .toList();
  }

  List<ChannelSerie> filterAdultSeries(
    List<ChannelSerie> series, {
    ParentalCategoryNameResolver? categoryNameForId,
  }) {
    if (!isAdultContentBlocked) return series;
    return series
        .where(
          (s) => !isAdultSerie(
            s,
            categoryName: categoryNameForId?.call(s.categoryId),
          ),
        )
        .toList();
  }

  /// هل القسم مقفول وما زال بدون جلسة PIN؟
  bool isSectionLockedWithoutSession(ParentalSection section) {
    return isSectionLocked(section) && !hasSessionAccess(section);
  }

  /// بصمة خيارات الرقابة — لإبطال كاش الهيرو عند التغيير.
  String homeSurfaceFingerprint() {
    return [
      isEnabled ? '1' : '0',
      hideAdultCategories ? '1' : '0',
      isSectionLockedWithoutSession(ParentalSection.movies) ? '1' : '0',
      isSectionLockedWithoutSession(ParentalSection.series) ? '1' : '0',
      hasAdultSessionAccess() ? '1' : '0',
    ].join(':');
  }

  /// تصفية أفلام الصفحة الرئيسية / الهيرو حسب الرقابة الأبوية المفعّلة.
  List<ChannelMovie> filterMoviesForHomeSurface(
    List<ChannelMovie> movies, {
    ParentalCategoryNameResolver? categoryNameForId,
    bool hideLockedSection = true,
  }) {
    if (hideLockedSection &&
        isSectionLockedWithoutSession(ParentalSection.movies)) {
      return const <ChannelMovie>[];
    }
    return filterAdultMovies(
      movies,
      categoryNameForId: categoryNameForId,
    );
  }

  /// تصفية مسلسلات الصفحة الرئيسية / الهيرو حسب الرقابة الأبوية المفعّلة.
  List<ChannelSerie> filterSeriesForHomeSurface(
    List<ChannelSerie> series, {
    ParentalCategoryNameResolver? categoryNameForId,
    bool hideLockedSection = true,
  }) {
    if (hideLockedSection &&
        isSectionLockedWithoutSession(ParentalSection.series)) {
      return const <ChannelSerie>[];
    }
    return filterAdultSeries(
      series,
      categoryNameForId: categoryNameForId,
    );
  }

  /// طلب PIN قبل الوصول لمحتوى +18.
  Future<bool> requestAdultContentAccess(BuildContext context) async {
    if (!isAdultContentBlocked) return true;
    if (hasAdultSessionAccess()) return true;
    final ok = await showParentalPinDialog(
      context,
      title: 'parental_pin_enter'.tr,
      subtitle: 'parental_adult_pin_sub'.tr,
    );
    if (ok == true) {
      grantAdultSessionAccess();
      return true;
    }
    return false;
  }

  /// طلب PIN قبل فتح قسم مقفول.
  Future<bool> requestSectionAccess(
    BuildContext context,
    ParentalSection section,
  ) async {
    if (!isSectionLocked(section)) return true;
    if (hasSessionAccess(section)) return true;
    final ok = await showParentalPinDialog(
      context,
      title: 'parental_pin_enter'.tr,
    );
    if (ok == true) {
      grantSessionAccess(section);
      return true;
    }
    return false;
  }

  /// تنقل محمي بـ PIN.
  Future<void> navigateToProtectedRoute(
    ParentalSection section,
    String route,
  ) async {
    final ctx = Get.context;
    if (ctx == null) return;
    if (await requestSectionAccess(ctx, section)) {
      await Get.toNamed(route);
    }
  }

  Future<void> navigateToProtectedAction(
    ParentalSection section,
    Future<void> Function() action,
  ) async {
    final ctx = Get.context;
    if (ctx == null) return;
    if (await requestSectionAccess(ctx, section)) {
      await action();
    }
  }
}
