import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_hero_cache.dart';

const Duration _kInterstitialMinInterval = Duration(minutes: 2);

/// Google recommends banners typically stay 60s+ before refresh.
const Duration kBannerMinRefreshInterval = Duration(seconds: 60);

enum AppBannerPlacement { liveEpg, details, catalog }

/// Reads full AdMob config from the admin panel only (App ID + ad unit IDs).
class AdsService {
  AdsService._();

  static const MethodChannel _nativeChannel = MethodChannel(
    'main_activity_channel',
  );

  static bool _initialized = false;
  static bool _fullscreenPlaybackActive = false;
  static InterstitialAd? _interstitial;
  static bool _interstitialLoading = false;
  static DateTime? _lastInterstitialShownAt;
  static final Map<AppBannerPlacement, DateTime> _lastBannerLoadedAt = {};

  /// While the fullscreen player is open, never show interstitial (keep watching).
  static void setFullscreenPlaybackActive(bool active) {
    _fullscreenPlaybackActive = active;
  }

  /// Whether a banner slot may request a new creative (60s+ since last load).
  static bool canRefreshBanner(DateTime loadedAt) {
    return DateTime.now().difference(loadedAt) >= kBannerMinRefreshInterval;
  }

  static void markBannerLoaded(AppBannerPlacement placement) {
    _lastBannerLoadedAt[placement] = DateTime.now();
  }

  static DateTime? lastBannerLoadedAt(AppBannerPlacement placement) =>
      _lastBannerLoadedAt[placement];

  /// Preloaded compact (320x50) banners for catalog — ready before user scrolls.
  static final List<BannerAd> _compactBannerPool = [];
  static int _compactBannerInFlight = 0;
  static const int _compactBannerPoolTarget = 2;

  /// Start warming compact banners as soon as movies/series grid opens.
  static Future<void> preloadCompactBanners({
    int count = _compactBannerPoolTarget,
  }) async {
    if (!adsEnabled) return;
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final unit = bannerUnitId;
    if (unit == null || unit.isEmpty) {
      if (kDebugMode) {
        debugPrint('[Ads] compact preload skipped: missing banner unit');
      }
      return;
    }
    if (!_initialized) await init();
    if (!_initialized) {
      if (kDebugMode) {
        debugPrint('[Ads] compact preload skipped: init failed');
      }
      return;
    }

    while (_compactBannerPool.length + _compactBannerInFlight < count) {
      _compactBannerInFlight++;
      unawaited(_loadOneCompactIntoPool(unit));
    }
  }

  static Future<void> _loadOneCompactIntoPool(String unit) async {
    try {
      final completer = Completer<BannerAd?>();
      final ad = BannerAd(
        size: AdSize.banner,
        adUnitId: unit,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (loaded) {
            if (!completer.isCompleted) {
              completer.complete(loaded as BannerAd);
            }
          },
          onAdFailedToLoad: (failed, error) {
            failed.dispose();
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
      unawaited(ad.load());
      final loaded = await completer.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          ad.dispose();
          return null;
        },
      );
      if (loaded != null &&
          adsEnabled &&
          _compactBannerPool.length < _compactBannerPoolTarget) {
        _compactBannerPool.add(loaded);
        markBannerLoaded(AppBannerPlacement.catalog);
      } else {
        loaded?.dispose();
      }
    } catch (_) {
      // ignore
    } finally {
      if (_compactBannerInFlight > 0) _compactBannerInFlight--;
    }
  }

  /// Take a ready compact banner (caller owns dispose). Refills the pool.
  static BannerAd? takePreloadedCompactBanner() {
    if (_compactBannerPool.isEmpty) {
      unawaited(preloadCompactBanners());
      return null;
    }
    final ad = _compactBannerPool.removeAt(0);
    unawaited(preloadCompactBanners());
    return ad;
  }

  static void disposeCompactBannerPool() {
    for (final ad in _compactBannerPool) {
      ad.dispose();
    }
    _compactBannerPool.clear();
    _compactBannerInFlight = 0;
  }

  /// Init using App ID cached from the admin panel.
  static Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (!adsEnabled) return;

    try {
      await _prepareNativeAppId(panelAppId);
      await MobileAds.instance.initialize();
      _initialized = true;
      unawaited(preloadInterstitial());
    } catch (e) {
      debugPrint('[Ads] init failed: $e');
    }
  }

  /// Persist panel ads keys from check-activation / login payloads.
  static void persistFromPanel(Map<dynamic, dynamic> data) {
    final box = GetStorage();
    final enabled = data['ads_enabled'];
    if (enabled is bool) {
      box.write('ads_enabled', enabled);
    } else if (enabled != null) {
      box.write('ads_enabled', enabled == 1 || enabled == '1' || enabled == true);
    }

    void writeUnit(String key) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty) {
        box.write(key, v);
      } else {
        box.remove(key);
      }
    }

    writeUnit('banner_ad_unit_android');
    writeUnit('banner_ad_unit_ios');
    writeUnit('interstitial_ad_unit_android');
    writeUnit('interstitial_ad_unit_ios');
    writeUnit('admob_app_id_android');
    writeUnit('admob_app_id_ios');
    writeUnit('tv_banner_image_url');
    writeUnit('tv_banner_click_url');
    writeUnit('tv_banner_html_url');

    HomeHeroPanel.persistFromPanel(data);

    unawaited(_mirrorAppIdsToSharedPreferences());

    if (adsEnabled) {
      unawaited(init());
      unawaited(preloadInterstitial());
      unawaited(preloadCompactBanners());
    } else {
      _disposeInterstitial();
      disposeCompactBannerPool();
    }
  }

  static Future<void> _mirrorAppIdsToSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final android = panelAppIdAndroid;
      final ios = panelAppIdIos;
      if (android != null && android.isNotEmpty) {
        await prefs.setString('admob_app_id_android', android);
      } else {
        await prefs.remove('admob_app_id_android');
      }
      if (ios != null && ios.isNotEmpty) {
        await prefs.setString('admob_app_id_ios', ios);
      } else {
        await prefs.remove('admob_app_id_ios');
      }
    } catch (e) {
      debugPrint('[Ads] prefs mirror failed: $e');
    }
  }

  static Future<void> _prepareNativeAppId(String? appId) async {
    final id = (appId ?? '').trim();
    if (id.isEmpty) return;
    if (!Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod('prepareAdMobAppId', {'appId': id});
    } catch (e) {
      debugPrint('[Ads] prepareAdMobAppId: $e');
    }
  }

  static bool get adsEnabled {
    final v = GetStorage().read('ads_enabled');
    if (v is bool) return v;
    if (v == null) return false;
    return v == 1 || v == '1';
  }

  static String? get panelAppIdAndroid {
    final u =
        (GetStorage().read('admob_app_id_android') ?? '').toString().trim();
    return u.isNotEmpty ? u : null;
  }

  static String? get panelAppIdIos {
    final u = (GetStorage().read('admob_app_id_ios') ?? '').toString().trim();
    return u.isNotEmpty ? u : null;
  }

  static String? get panelAppId {
    if (Platform.isAndroid) return panelAppIdAndroid;
    if (Platform.isIOS) return panelAppIdIos;
    return null;
  }

  static bool shouldShowBanner(AppBannerPlacement placement) {
    if (!adsEnabled) return false;
    if (kIsWeb) return false;
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    // AdMob unit OR panel TV creatives (image/HTML fallback for Android TV).
    if (bannerUnitId == null && !hasTvPanelBanner) return false;
    switch (placement) {
      case AppBannerPlacement.liveEpg:
      case AppBannerPlacement.details:
      case AppBannerPlacement.catalog:
        return true;
    }
  }

  /// Panel image / HTML banner for TV when AdMob is unavailable.
  static String? get tvBannerImageUrl {
    final u = (GetStorage().read('tv_banner_image_url') ?? '').toString().trim();
    return u.isNotEmpty ? u : null;
  }

  static String? get tvBannerClickUrl {
    final u = (GetStorage().read('tv_banner_click_url') ?? '').toString().trim();
    return u.isNotEmpty ? u : null;
  }

  static String? get tvBannerHtmlUrl {
    final u = (GetStorage().read('tv_banner_html_url') ?? '').toString().trim();
    return u.isNotEmpty ? u : null;
  }

  static bool get hasTvPanelBanner =>
      tvBannerImageUrl != null || tvBannerHtmlUrl != null;

  static String? get bannerUnitId {
    final box = GetStorage();
    if (Platform.isAndroid) {
      final u = (box.read('banner_ad_unit_android') ?? '').toString().trim();
      return u.isNotEmpty ? u : null;
    }
    if (Platform.isIOS) {
      final u = (box.read('banner_ad_unit_ios') ?? '').toString().trim();
      return u.isNotEmpty ? u : null;
    }
    return null;
  }

  static String? get interstitialUnitId {
    final box = GetStorage();
    if (Platform.isAndroid) {
      final u =
          (box.read('interstitial_ad_unit_android') ?? '').toString().trim();
      return u.isNotEmpty ? u : null;
    }
    if (Platform.isIOS) {
      final u = (box.read('interstitial_ad_unit_ios') ?? '').toString().trim();
      return u.isNotEmpty ? u : null;
    }
    return null;
  }

  static Future<void> preloadInterstitial() async {
    if (!adsEnabled) return;
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final unit = interstitialUnitId;
    if (unit == null || unit.isEmpty) {
      if (kDebugMode) {
        debugPrint('[Ads] interstitial preload skipped: missing unit id');
      }
      return;
    }
    if (_interstitial != null || _interstitialLoading) return;
    if (!_initialized) await init();
    if (!_initialized) return;

    _interstitialLoading = true;
    try {
      await InterstitialAd.load(
        adUnitId: unit,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitial = ad;
            _interstitialLoading = false;
            if (kDebugMode) debugPrint('[Ads] interstitial loaded');
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                _interstitial = null;
                unawaited(preloadInterstitial());
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                debugPrint('[Ads] interstitial show failed: $error');
                ad.dispose();
                _interstitial = null;
                unawaited(preloadInterstitial());
              },
            );
          },
          onAdFailedToLoad: (error) {
            _interstitialLoading = false;
            _interstitial = null;
            debugPrint(
              '[Ads] interstitial load failed code=${error.code} '
              'domain=${error.domain} msg=${error.message}',
            );
          },
        ),
      );
    } catch (e) {
      _interstitialLoading = false;
      debugPrint('[Ads] interstitial load exception: $e');
    }
  }

  static void _disposeInterstitial() {
    _interstitial?.dispose();
    _interstitial = null;
    _interstitialLoading = false;
  }

  /// Shows a ready interstitial (if any). Always completes — never blocks UI forever.
  /// Skipped while [setFullscreenPlaybackActive] is true (inside the player).
  static Future<void> showInterstitialIfReady() async {
    if (!adsEnabled) {
      if (kDebugMode) debugPrint('[Ads] interstitial skipped: ads disabled');
      return;
    }
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    // Race with player pop: .then() can fire before dispose clears the flag.
    if (_fullscreenPlaybackActive) {
      await Future<void>.delayed(Duration.zero);
      if (_fullscreenPlaybackActive) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (_fullscreenPlaybackActive) {
        if (kDebugMode) {
          debugPrint('[Ads] interstitial skipped: fullscreen still active');
        }
        return;
      }
    }

    final last = _lastInterstitialShownAt;
    if (last != null &&
        DateTime.now().difference(last) < _kInterstitialMinInterval) {
      if (kDebugMode) {
        debugPrint('[Ads] interstitial skipped: min interval');
      }
      return;
    }

    if (interstitialUnitId == null) {
      if (kDebugMode) {
        debugPrint('[Ads] interstitial skipped: missing unit id');
      }
      return;
    }

    if (_interstitial == null) {
      await preloadInterstitial();
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (_interstitial == null &&
          DateTime.now().isBefore(deadline)) {
        if (!_interstitialLoading && _interstitial == null) {
          // Load finished with failure — stop waiting.
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    final ad = _interstitial;
    if (ad == null) {
      if (kDebugMode) {
        debugPrint('[Ads] interstitial not ready to show');
      }
      // Keep warming for the next exit.
      unawaited(preloadInterstitial());
      return;
    }

    _interstitial = null;
    _lastInterstitialShownAt = DateTime.now();
    try {
      if (kDebugMode) debugPrint('[Ads] interstitial showing');
      await ad.show();
    } catch (e) {
      debugPrint('[Ads] interstitial show exception: $e');
      ad.dispose();
      unawaited(preloadInterstitial());
    }
  }
}
