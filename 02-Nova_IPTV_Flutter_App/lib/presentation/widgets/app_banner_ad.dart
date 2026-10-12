import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mehdi_iptv/helpers/helpers.dart';
import 'package:mehdi_iptv/presentation/widgets/tv_panel_banner.dart';
import 'package:mehdi_iptv/services/ads_service.dart';

/// Adaptive / compact banner that respects admin panel ads settings.
///
/// Shown on Android/iOS. On **Android TV**, AdMob is officially unsupported by
/// Google — we prefer panel HTML/image creatives when configured, else try a
/// fixed 320×50 AdMob banner.
///
/// Google recommends keeping a loaded banner on screen typically **60s+**
/// before refreshing — we never auto-refresh faster than that.
class AppBannerAd extends StatefulWidget {
  const AppBannerAd({
    super.key,
    required this.placement,
    this.padding = EdgeInsets.zero,
    this.compact = false,
    /// When false, hide on TV form factors.
    this.showOnTv = true,
    this.excludeFocus = false,
    /// Keep slot height while loading (avoids jump + feels faster).
    this.reserveHeight = false,
  });

  final AppBannerPlacement placement;
  final EdgeInsetsGeometry padding;
  final bool compact;
  final bool showOnTv;
  final bool excludeFocus;
  final bool reserveHeight;

  @override
  State<AppBannerAd> createState() => _AppBannerAdState();
}

class _AppBannerAdState extends State<AppBannerAd> {
  BannerAd? _banner;
  bool _loaded = false;
  int _loadToken = 0;
  DateTime? _loadedAt;
  String? _loadedUnitId;
  int _failRetries = 0;
  bool _adMobFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(force: false));
  }

  @override
  void didUpdateWidget(covariant AppBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement ||
        oldWidget.compact != widget.compact ||
        oldWidget.showOnTv != widget.showOnTv) {
      _load(force: true);
    }
  }

  @override
  void dispose() {
    _banner?.dispose();
    _banner = null;
    super.dispose();
  }

  bool _isTv() {
    try {
      return isTv(context);
    } catch (_) {
      return false;
    }
  }

  /// On TV, prefer panel image/HTML when set (AdMob is unreliable).
  bool _preferTvPanel() => _isTv() && AdsService.hasTvPanelBanner;

  bool _mayRefreshNow({required bool force}) {
    if (force) return true;
    if (!_loaded || _banner == null || _loadedAt == null) return true;
    final unit = AdsService.bannerUnitId;
    if (unit != null && _loadedUnitId != null && unit != _loadedUnitId) {
      return true;
    }
    return AdsService.canRefreshBanner(_loadedAt!);
  }

  Future<void> _load({required bool force}) async {
    if (!mounted) return;
    if (!widget.showOnTv && _isTv()) return;
    if (!AdsService.shouldShowBanner(widget.placement)) return;

    // TV panel creatives: no AdMob request needed.
    if (_preferTvPanel()) {
      if (mounted) {
        setState(() {
          _adMobFailed = false;
          _banner?.dispose();
          _banner = null;
          _loaded = false;
        });
      }
      return;
    }

    final unit = AdsService.bannerUnitId;
    if (unit == null || unit.isEmpty) {
      if (kDebugMode) {
        debugPrint('[Ads] banner skipped: missing unit id');
      }
      // Still allow TV panel fallback slot if configured later.
      if (mounted && AdsService.hasTvPanelBanner && _isTv()) {
        setState(() => _adMobFailed = true);
      }
      return;
    }

    if (!_mayRefreshNow(force: force)) return;

    await AdsService.init();
    if (!mounted) return;
    if (!_mayRefreshNow(force: force)) return;

    final tv = _isTv();
    // TV: دائماً 320×50 — الأحجام التكيفية تفشل كثيراً على Android TV.
    final useCompact = widget.compact || tv;

    if (useCompact) {
      final preloaded = AdsService.takePreloadedCompactBanner();
      if (preloaded != null) {
        final previous = _banner;
        if (!mounted) {
          preloaded.dispose();
          return;
        }
        previous?.dispose();
        setState(() {
          _banner = preloaded;
          _loaded = true;
          _loadedAt = DateTime.now();
          _loadedUnitId = unit;
          _failRetries = 0;
          _adMobFailed = false;
        });
        AdsService.markBannerLoaded(widget.placement);
        return;
      }
    }

    final token = ++_loadToken;
    AdSize size;
    if (useCompact) {
      size = AdSize.banner;
    } else {
      final rawW = MediaQuery.sizeOf(context).width.truncate();
      if (rawW <= 0) return;
      final width = rawW.clamp(320, 728);
      AdSize? adaptive;
      try {
        adaptive = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
      } catch (_) {
        adaptive = AdSize.banner;
      }
      size = adaptive ?? AdSize.banner;
    }

    await _requestBanner(
      unit: unit,
      size: size,
      token: token,
      allowRetryAsBanner: !useCompact,
    );
  }

  Future<void> _requestBanner({
    required String unit,
    required AdSize size,
    required int token,
    required bool allowRetryAsBanner,
  }) async {
    final previous = _banner;
    final ad = BannerAd(
      size: size,
      adUnitId: unit,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loaded) {
          if (!mounted || token != _loadToken) {
            loaded.dispose();
            return;
          }
          previous?.dispose();
          setState(() {
            _banner = loaded as BannerAd;
            _loaded = true;
            _loadedAt = DateTime.now();
            _loadedUnitId = unit;
            _failRetries = 0;
            _adMobFailed = false;
          });
          AdsService.markBannerLoaded(widget.placement);
          if (kDebugMode) {
            debugPrint(
              '[Ads] banner loaded placement=${widget.placement} '
              'size=${size.width}x${size.height} tv=${_isTv()}',
            );
          }
        },
        onAdFailedToLoad: (failed, error) {
          failed.dispose();
          if (kDebugMode) {
            debugPrint(
              '[Ads] banner fail placement=${widget.placement} '
              'code=${error.code} domain=${error.domain} msg=${error.message} '
              'tv=${_isTv()} size=${size.width}x${size.height}',
            );
          }
          if (!mounted || token != _loadToken) return;

          // Retry once with standard 320×50 (TV / adaptive failures).
          if (allowRetryAsBanner &&
              _failRetries < 1 &&
              size != AdSize.banner) {
            _failRetries++;
            unawaited(
              _requestBanner(
                unit: unit,
                size: AdSize.banner,
                token: token,
                allowRetryAsBanner: false,
              ),
            );
            return;
          }

          if (previous != null && _loaded) return;
          setState(() {
            _banner = null;
            _loaded = false;
            _loadedAt = null;
            _loadedUnitId = null;
            // On TV, fall back to panel HTML/image if configured.
            _adMobFailed = _isTv() && AdsService.hasTvPanelBanner;
          });
        },
      ),
    );

    try {
      await ad.load();
    } catch (e) {
      if (kDebugMode) debugPrint('[Ads] banner load exception: $e');
      ad.dispose();
      if (mounted && token == _loadToken) {
        setState(() {
          _adMobFailed = _isTv() && AdsService.hasTvPanelBanner;
        });
      }
    }
  }

  Widget _buildTvPanel() {
    return TvPanelBanner(
      imageUrl: AdsService.tvBannerImageUrl,
      clickUrl: AdsService.tvBannerClickUrl,
      htmlUrl: AdsService.tvBannerHtmlUrl,
      padding: widget.padding,
      excludeFocus: widget.excludeFocus,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return const SizedBox.shrink();
    }
    if (!widget.showOnTv && _isTv()) {
      return const SizedBox.shrink();
    }
    if (!AdsService.shouldShowBanner(widget.placement)) {
      return const SizedBox.shrink();
    }

    if (_preferTvPanel() || _adMobFailed) {
      return _buildTvPanel();
    }

    final ad = _banner;
    final reservedH = widget.reserveHeight || widget.compact || _isTv()
        ? AdSize.banner.height.toDouble()
        : 0.0;

    if (!_loaded || ad == null) {
      if (reservedH <= 0) return const SizedBox.shrink();
      return Padding(
        padding: widget.padding,
        child: SizedBox(height: reservedH, width: double.infinity),
      );
    }

    Widget child = Center(
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );

    if (widget.excludeFocus) {
      child = ExcludeFocus(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          descendantsAreFocusable: false,
          descendantsAreTraversable: false,
          child: child,
        ),
      );
    }

    return Padding(padding: widget.padding, child: child);
  }
}
