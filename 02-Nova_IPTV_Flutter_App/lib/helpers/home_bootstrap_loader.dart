import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import '../logic/blocs/categories/channels/channels_bloc.dart';
import '../logic/blocs/categories/live_caty/live_caty_bloc.dart';
import '../logic/blocs/categories/movie_caty/movie_caty_bloc.dart';
import '../logic/blocs/categories/series_caty/series_caty_bloc.dart';
import '../logic/cubits/favorites/favorites_cubit.dart';
import '../logic/cubits/home/home_recent_cubit.dart';
import '../logic/cubits/settings/settings_cubit.dart';
import '../logic/cubits/watch/watching_cubit.dart';
import '../repository/api/api.dart';
import '../repository/locale/catalog_disk_cache.dart';
import '../repository/models/category.dart';
import 'catalog_sync_service.dart';
import 'helpers.dart';
import 'live_catalog_warm_service.dart';
import 'package:mehdi_iptv/core/runtime_seal.dart';
import 'package:mehdi_iptv/services/epg_refresh_service.dart';
import 'package:mehdi_iptv/services/iptv_image_cache.dart';
import 'package:mehdi_iptv/services/home_hero_cache.dart';
import 'package:mehdi_iptv/services/parental_control_service.dart';
import '../logic/cubits/prefetch/prefetch_cubit.dart';

/// تحميل بيانات الرئيسية قبل عرضها — يعمل في الخلفية دون لمس الواجهة.
class HomeBootstrapLoader {
  HomeBootstrapLoader._();

  static const Duration _stepTimeout = Duration(seconds: 18);

  /// سقف شاشة التحميل — قصير حتى لا يبدو التطبيق متجمداً لمراجعي Play.
  static const Duration _bootstrapHardCap = Duration(seconds: 16);
  static const Duration _bootstrapImageBudget = Duration(seconds: 8);
  static const Duration _minDisplay = Duration(milliseconds: 220);
  static const Duration _minDisplayCached = Duration(milliseconds: 140);

  static int get _bootstrapImageLimit {
    if (AppPerf.instance.isTelevisionLike) {
      if (AppPerf.instance.isLite) return 28;
      if (AppPerf.instance.isMid) return 40;
      return 56;
    }
    if (AppPerf.instance.isLite) return 36;
    if (AppPerf.instance.isMid) return 64;
    return 90;
  }

  static int get _bootstrapMoviesFromAll {
    if (AppPerf.instance.isTelevisionLike) return 24;
    if (AppPerf.instance.isLite) return 24;
    if (AppPerf.instance.isMid) return 40;
    return 56;
  }

  static int get _bootstrapSeriesFromAll {
    if (AppPerf.instance.isTelevisionLike) return 24;
    if (AppPerf.instance.isLite) return 24;
    if (AppPerf.instance.isMid) return 40;
    return 56;
  }

  static int get _bootstrapLiveCategories {
    if (AppPerf.instance.isLite) return 2;
    if (AppPerf.instance.isMid) return 3;
    return 5;
  }

  static int get _bootstrapLivePerCategory {
    if (AppPerf.instance.isLite) return 16;
    if (AppPerf.instance.isMid) return 24;
    return 32;
  }

  static int get _bootstrapImageConcurrency =>
      AppPerf.instance.imageConcurrentFetches.clamp(2, 5);

  /// يُعاد ضبطه عند تسجيل الخروج أو تغيير السيرفر.
  static bool _sessionBootstrapped = false;
  static bool _pendingBackgroundSync = false;

  static void resetSession() {
    _sessionBootstrapped = false;
    _pendingBackgroundSync = false;
    LiveCatalogWarmService.instance.reset();
    CatalogSyncService.instance.reset();
    HomeHeroCache.clear();
  }

  static void markSessionBootstrapped() => _sessionBootstrapped = true;

  /// بعد مغادرة دائرة التحميل: فهرسة هادئة + تسخين Live في الخلفية.
  static void onLeftLoadingScreen({
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
    required MovieCatyBloc movieCaty,
    required SeriesCatyBloc seriesCaty,
  }) {
    channels.resumeIdleCatalogWork();
    if (_pendingBackgroundSync) {
      _pendingBackgroundSync = false;
      _startBackgroundSync(
        channels: channels,
        liveCaty: liveCaty,
        movieCaty: movieCaty,
        seriesCaty: seriesCaty,
      );
    }
    _startLiveWarm(channels, liveCaty);
  }

  static Future<void> run(
    BuildContext context, {
    bool isDemo = false,
    ValueNotifier<double>? progress,
  }) async {
    void setProgress(double value) {
      final n = progress;
      if (n == null) return;
      final v = value.clamp(0.0, 1.0);
      // monotonic — لا تراجع (86% → 72% مثلاً).
      if (v <= n.value + 0.0005) return;
      n.value = v;
    }

    if (!await RuntimeSeal.denyBrokenSession()) return;
    if (isDemo) {
      setProgress(0.08);
      for (var i = 1; i <= 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        setProgress(i / 8);
      }
      setProgress(1);
      return;
    }

    // سقف زمني: أي علق شبكة/JSON ما يخلي الدائرة واقفة عند 97%.
    if (!context.mounted) return;
    try {
      await _runBody(context, setProgress: setProgress).timeout(
        _bootstrapHardCap,
        onTimeout: () {},
      );
    } catch (_) {
      // نتابع للرئيسية حتى لو فشل جزء من التحميل.
    }
    setProgress(1);
  }

  static Future<void> _runBody(
    BuildContext context, {
    required void Function(double) setProgress,
  }) async {
    final started = DateTime.now();
    ChannelsBloc? channelsBloc;
    LiveCatyBloc? liveCatyBloc;
    MovieCatyBloc? movieCatyBloc;
    SeriesCatyBloc? seriesCatyBloc;

    setProgress(0.04);
    await _yieldFrames(2);
    setProgress(0.08);

    if (context.mounted && LocaleApi.getUserSync() != null) {
      unawaited(context.read<FavoritesCubit>().initialData());
      unawaited(context.read<WatchingCubit>().initialData());
    }
    if (!context.mounted) return;

    channelsBloc = context.read<ChannelsBloc>();
    liveCatyBloc = context.read<LiveCatyBloc>();
    movieCatyBloc = context.read<MovieCatyBloc>();
    seriesCatyBloc = context.read<SeriesCatyBloc>();
    channelsBloc.deferIdleCatalogWork = true;

    // 1) استرجاع القرص — خفيف أثناء الشاشة؛ All الثقيل بلا انتظار طويل.
    setProgress(0.14);
    final disk = await _hydrateFromDisk(
      channels: channelsBloc,
      liveCaty: liveCatyBloc,
      movieCaty: movieCatyBloc,
      seriesCaty: seriesCatyBloc,
    );
    if (!context.mounted) return;
    setProgress(0.28);

    final home = context.read<HomeRecentCubit>();
    home.load(force: !disk.any);

    final canSkipNetworkWait = disk.any && _hasUsableCache(context, disk);

    if (canSkipNetworkWait) {
      setProgress(0.68);
      await _yieldFrame();
      markSessionBootstrapped();
      _pendingBackgroundSync = true;
      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minDisplayCached) {
        await Future<void>.delayed(_minDisplayCached - elapsed);
      }
      await _warmLiveBrowserShell(
        channels: channelsBloc,
        liveCaty: liveCatyBloc,
      ).timeout(const Duration(seconds: 4), onTimeout: () {});
      await _warmLiveCategoriesForIcons(
        channels: channelsBloc,
        liveCaty: liveCatyBloc,
      );
      if (!context.mounted) return;
      await _warmHomeHero(context);
      if (!context.mounted) return;
      await _warmBootstrapImageCache(
        context,
        channels: channelsBloc,
        liveCaty: liveCatyBloc,
        setProgress: setProgress,
        progressStart: 0.72,
        progressEnd: 0.98,
      );
      setProgress(1);
      return;
    }

    // 2) أول زيارة: فئات + رئيسية فقط — كتالوج All والصور في الخلفية لاحقاً.
    setProgress(0.32);
    unawaited(_ensureLiveCategories(context));

    await Future.wait([
      home.stream
          .firstWhere((s) => s is HomeRecentSuccess && s.isComplete)
          .timeout(_stepTimeout, onTimeout: () => home.state),
      _ensureMovieCategories(context),
      _ensureSeriesCategories(context),
    ]);
    setProgress(0.7);
    await _yieldFrame();

    if (!context.mounted) return;
    // نبدأ All مبكراً؛ قبل الصور ننتظره بميزانية قصيرة لملصقات إضافية.
    final movieAllFuture = channelsBloc.ensureFullMovieCatalog();
    final seriesAllFuture = channelsBloc.ensureFullSeriesCatalog();
    setProgress(0.86);

    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minDisplay) {
      await Future<void>.delayed(_minDisplay - elapsed);
    }

    if (context.mounted) {
      final homeState = context.read<HomeRecentCubit>().state;
      if (homeState is HomeRecentSuccess &&
          (homeState.movies.isNotEmpty || homeState.series.isNotEmpty)) {
        markSessionBootstrapped();
      } else if (_categoriesReady(context)) {
        markSessionBootstrapped();
      }
    }

    try {
      await Future.wait([movieAllFuture, seriesAllFuture]).timeout(
        const Duration(seconds: 10),
        onTimeout: () => [
          channelsBloc?.movieListForCategoryId('__all__') ?? const [],
          channelsBloc?.seriesListForCategoryId('__all__') ?? const [],
        ],
      );
    } catch (_) {}

    await _warmLiveBrowserShell(
      channels: channelsBloc,
      liveCaty: liveCatyBloc,
    ).timeout(const Duration(seconds: 4), onTimeout: () {});
    await _warmLiveCategoriesForIcons(
      channels: channelsBloc,
      liveCaty: liveCatyBloc,
    );
    if (!context.mounted) return;
    await _warmHomeHero(context);
    if (!context.mounted) return;
    await _warmBootstrapImageCache(
      context,
      channels: channelsBloc,
      liveCaty: liveCatyBloc,
      setProgress: setProgress,
      progressStart: 0.86,
      progressEnd: 0.98,
    );
    setProgress(1);
  }

  /// تجهيز هيرو TV أثناء شاشة التحميل (تفاصيل + backdrop على القرص).
  static Future<void> _warmHomeHero(BuildContext context) async {
    if (!context.mounted) return;
    final home = context.read<HomeRecentCubit>().state;
    if (home is! HomeRecentSuccess) return;
    final movieCaty = context.read<MovieCatyBloc>().state;
    final seriesCaty = context.read<SeriesCatyBloc>().state;
    final movieCats =
        movieCaty is MovieCatySuccess ? movieCaty.categories : const <CategoryModel>[];
    final seriesCats = seriesCaty is SeriesCatySuccess
        ? seriesCaty.categories
        : const <CategoryModel>[];
    final parental = ParentalControlService.instance;
    final movies = parental.filterMoviesForHomeSurface(
      filterHomeContentTitles(home.movies, (m) => m.name),
      categoryNameForId: (id) =>
          ParentalControlService.categoryNameFromId(id, movieCats),
    );
    final series = parental.filterSeriesForHomeSurface(
      filterHomeContentTitles(home.series, (s) => s.name),
      categoryNameForId: (id) =>
          ParentalControlService.categoryNameFromId(id, seriesCats),
    );
    if (movies.isEmpty && series.isEmpty && !HomeHeroPanel.hasPromoSlide) {
      HomeHeroCache.clear();
      return;
    }
    final serverUrl = LocaleApi.getUserSync()?.serverInfo?.serverUrl;
    try {
      await HomeHeroCache.warm(
        movies: movies,
        series: series,
        prefetch: context.read<PrefetchCubit>(),
        serverUrl: serverUrl,
        movieCategories: movieCats,
        seriesCategories: seriesCats,
      ).timeout(const Duration(seconds: 14));
    } catch (_) {}
  }

  /// تسخين صور الرئيسية + أفلام/مسلسلات + Live إلى كاش القرص (بدون فك GPU).
  static Future<void> _warmBootstrapImageCache(
    BuildContext context, {
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
    required void Function(double) setProgress,
    double progressStart = 0.72,
    double progressEnd = 0.98,
  }) async {
    if (!context.mounted) return;
    final urls = _collectBootstrapImageUrls(
      context,
      channels: channels,
      liveCaty: liveCaty,
    );
    if (urls.isEmpty) {
      setProgress(progressEnd);
      return;
    }

    final span = (progressEnd - progressStart).clamp(0.05, 0.35);
    setProgress(progressStart);

    await warmIptvImagesToDisk(
      urls,
      limit: _bootstrapImageLimit,
      concurrency: _bootstrapImageConcurrency,
      maxDuration: _bootstrapImageBudget,
      onProgress: (done, total) {
        if (total <= 0) return;
        final t = (done / total).clamp(0.0, 1.0);
        setProgress(progressStart + span * t);
      },
    );
    setProgress(progressEnd);
  }

  static List<String> _collectBootstrapImageUrls(
    BuildContext context, {
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
  }) {
    final serverUrl = LocaleApi.getUserSync()?.serverInfo?.serverUrl;
    final seen = <String>{};
    final urls = <String>[];

    void add(String? raw) {
      if (urls.length >= _bootstrapImageLimit) return;
      final url = resolveImageUrl(raw, serverUrl);
      if (url.isEmpty || !seen.add(url)) return;
      urls.add(url);
    }

    // هيرو TV أولاً — أول ما يبان فـ Home.
    for (final u in HomeHeroCache.imageUrls) {
      if (urls.length >= _bootstrapImageLimit) break;
      if (u.isEmpty || !seen.add(u)) continue;
      urls.add(u);
    }

    final home = context.read<HomeRecentCubit>().state;
    if (home is HomeRecentSuccess) {
      for (final m in home.movies) {
        add(m.streamIcon);
      }
      for (final s in home.series) {
        add(s.cover);
      }
    }

    final movies = channels.movieListForCategoryId('__all__');
    if (movies != null && movies.isNotEmpty) {
      for (final m in movies.take(_bootstrapMoviesFromAll)) {
        add(m.streamIcon);
      }
    }

    final series = channels.seriesListForCategoryId('__all__');
    if (series != null && series.isNotEmpty) {
      for (final s in series.take(_bootstrapSeriesFromAll)) {
        add(s.cover);
      }
    }

    final liveState = liveCaty.state;
    if (liveState is LiveCatySuccess && liveState.categories.isNotEmpty) {
      final catIds = liveState.categories
          .take(_bootstrapLiveCategories)
          .map((c) => (c.categoryId ?? '').trim())
          .where((id) => id.isNotEmpty);
      for (final catId in catIds) {
        final list = channels.liveListForCategoryId(catId);
        if (list == null || list.isEmpty) continue;
        for (final ch in list.take(_bootstrapLivePerCategory)) {
          add(ch.streamIcon);
        }
      }
    }

    return urls;
  }

  /// يحمّل أول فئات Live (لوجos القنوات) قبل جمع روابط الصور.
  static Future<void> _warmLiveCategoriesForIcons({
    required ChannelsBloc? channels,
    required LiveCatyBloc? liveCaty,
  }) async {
    if (channels == null || liveCaty == null) return;
    final state = liveCaty.state;
    if (state is! LiveCatySuccess || state.categories.isEmpty) return;

    final ids = state.categories
        .take(_bootstrapLiveCategories)
        .map((c) => (c.categoryId ?? '').trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return;

    for (final id in ids) {
      if (channels.hasLiveCategoryCached(id) &&
          (channels.liveListForCategoryId(id)?.isNotEmpty ?? false)) {
        continue;
      }
      try {
        await channels.ensureLiveCategoryCached(id).timeout(
          const Duration(seconds: 6),
          onTimeout: () => const [],
        );
      } catch (_) {}
      await _yieldFrame();
    }
  }

  /// يحمّل ملصقات الرئيسية في الكاش (بعد مغادرة شاشة التحميل — احتياطي).
  static Future<void> warmHomePosters(BuildContext context) async {
    if (!context.mounted) return;
    final channels = context.read<ChannelsBloc>();
    final liveCaty = context.read<LiveCatyBloc>();
    final urls = _collectBootstrapImageUrls(
      context,
      channels: channels,
      liveCaty: liveCaty,
    );
    if (urls.isEmpty) return;
    await warmIptvImagesToDisk(
      urls,
      limit: AppPerf.instance.isLite ? 24 : 40,
      concurrency: _bootstrapImageConcurrency,
      maxDuration: const Duration(seconds: 8),
    );
  }

  /// أثناء شاشة التحميل: أول فئة Live في الذاكرة حتى أول دخول ما يبانش فارغ.
  static Future<void> _warmLiveBrowserShell({
    required ChannelsBloc? channels,
    required LiveCatyBloc? liveCaty,
  }) async {
    if (channels == null || liveCaty == null) return;
    var state = liveCaty.state;
    if (state is! LiveCatySuccess || state.categories.isEmpty) {
      liveCaty.add(GetLiveCategories());
      try {
        await liveCaty.stream
            .firstWhere((s) => s is LiveCatySuccess)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      state = liveCaty.state;
    }
    if (state is! LiveCatySuccess || state.categories.isEmpty) return;
    final firstId = (state.categories.first.categoryId ?? '').trim();
    if (firstId.isEmpty) return;
    if (channels.hasLiveCategoryCached(firstId) &&
        (channels.liveListForCategoryId(firstId)?.isNotEmpty ?? false)) {
      return;
    }
    try {
      await channels.ensureLiveCategoryCached(firstId).timeout(
        const Duration(seconds: 3),
        onTimeout: () => const [],
      );
    } catch (_) {}
  }

  static void _startLiveWarm(ChannelsBloc? channels, LiveCatyBloc? liveCaty) {
    if (channels == null || liveCaty == null) return;
    unawaited(() async {
      await LiveCatalogWarmService.instance.warmPriorityDuringBootstrap(
        channels: channels,
        liveCaty: liveCaty,
      );
      await LiveCatalogWarmService.instance.continueTailInBackground(
        channels: channels,
        liveCaty: liveCaty,
      );
      // Light EPG warm only — full catalog prefetch OOMs on many devices.
      unawaited(_softPrefetchPriorityEpg(channels, liveCaty));
    }());
  }

  static Future<void> _softPrefetchPriorityEpg(
    ChannelsBloc channels,
    LiveCatyBloc liveCaty,
  ) async {
    try {
      // Let home UI settle before any network/cache pressure.
      await Future<void>.delayed(const Duration(seconds: 10));
      final user = await LocaleApi.getUser();
      if (user == null) return;
      final u = user.userInfo?.username?.trim() ?? '';
      final p = user.userInfo?.password?.trim() ?? '';
      if (u.isEmpty && p.isEmpty) return;
      final ids = _epgIdsFromChannelsBloc(channels, liveCaty);
      if (ids.isEmpty) return;
      await EpgRefreshService.prefetchStreamIds(
        ids,
        concurrency: 2,
        maxStreams: EpgRefreshService.backgroundPrefetchMaxStreams,
        cancelPrevious: true,
      );
    } catch (e) {
      debugPrint('EPG soft prefetch failed: $e');
    }
  }

  static Set<String> _epgIdsFromChannelsBloc(
    ChannelsBloc channels,
    LiveCatyBloc liveCaty,
  ) {
    final ids = <String>{};
    final liveState = liveCaty.state;
    if (liveState is! LiveCatySuccess) return ids;
    final cats =
        liveState.categories.take(LiveCatalogWarmService.priorityCategoryCount);
    for (final cat in cats) {
      final catId = cat.categoryId?.trim() ?? '';
      if (catId.isEmpty) continue;
      final list = channels.liveListForCategoryId(catId);
      if (list == null) continue;
      ids.addAll(EpgRefreshService.streamIdsWithEpg(list));
    }
    return ids;
  }

  static void _startBackgroundSync({
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
    required MovieCatyBloc movieCaty,
    required SeriesCatyBloc seriesCaty,
  }) {
    unawaited(
      CatalogSyncService.instance.syncInBackground(
        api: channels.api,
        channels: channels,
        liveCaty: liveCaty,
        movieCaty: movieCaty,
        seriesCaty: seriesCaty,
      ),
    );
  }

  static Future<_DiskHydrateResult> _hydrateFromDisk({
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
    required MovieCatyBloc movieCaty,
    required SeriesCatyBloc seriesCaty,
  }) async {
    final userKey = channels.catalogUserKey;
    if (userKey.isEmpty) return const _DiskHydrateResult();

    var liveCats = false;
    var movieCats = false;
    var seriesCats = false;

    final liveList = await CatalogDiskCache.readCategories(
      userKey,
      CatalogDiskCache.kindLive,
    );
    if (liveList != null && liveList.isNotEmpty) {
      final wait = liveCaty.stream.firstWhere((s) => s is LiveCatySuccess);
      liveCaty.add(HydrateLiveCategories(List<CategoryModel>.from(liveList)));
      await wait.timeout(
        const Duration(seconds: 2),
        onTimeout: () => liveCaty.state,
      );
      liveCats = liveCaty.state is LiveCatySuccess;
    }

    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);

    final movieList = await CatalogDiskCache.readCategories(
      userKey,
      CatalogDiskCache.kindMovies,
    );
    if (movieList != null && movieList.isNotEmpty) {
      final wait = movieCaty.stream.firstWhere((s) => s is MovieCatySuccess);
      movieCaty.add(
        HydrateMovieCategories(List<CategoryModel>.from(movieList)),
      );
      await wait.timeout(
        const Duration(seconds: 2),
        onTimeout: () => movieCaty.state,
      );
      movieCats = movieCaty.state is MovieCatySuccess;
    }

    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);

    final seriesList = await CatalogDiskCache.readCategories(
      userKey,
      CatalogDiskCache.kindSeries,
    );
    if (seriesList != null && seriesList.isNotEmpty) {
      final wait = seriesCaty.stream.firstWhere((s) => s is SeriesCatySuccess);
      seriesCaty.add(
        HydrateSeriesCategories(List<CategoryModel>.from(seriesList)),
      );
      await wait.timeout(
        const Duration(seconds: 2),
        onTimeout: () => seriesCaty.state,
      );
      seriesCats = seriesCaty.state is SeriesCatySuccess;
    }

    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);

    final liveCount = await channels.hydrateLiveFromDisk();
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);

    // كتالوج All كبير جداً — لا نجمّد شاشة التحميل بانتظاره كاملاً.
    final allBudget = AppPerf.instance.isLite
        ? const Duration(seconds: 2)
        : const Duration(seconds: 4);
    var allOk = false;
    final allFuture = channels.hydrateAllCatalogsFromDisk();
    try {
      allOk = await allFuture.timeout(allBudget, onTimeout: () => false);
    } catch (_) {
      allOk = false;
    }
    // إن تجاوز الميزانية يستمر allFuture في الخلفية دون استدعاء ثانٍ.

    return _DiskHydrateResult(
      liveCats: liveCats,
      movieCats: movieCats,
      seriesCats: seriesCats,
      liveChannels: liveCount > 0,
      allCatalogs: allOk,
    );
  }

  static bool _hasUsableCache(BuildContext context, _DiskHydrateResult disk) {
    final home = context.read<HomeRecentCubit>().state;
    final homeOk =
        home is HomeRecentSuccess &&
        (home.movies.isNotEmpty || home.series.isNotEmpty);

    final catsOk = disk.liveCats || disk.movieCats || disk.seriesCats;
    return catsOk && (homeOk || disk.allCatalogs || disk.liveChannels);
  }

  static bool _categoriesReady(BuildContext context) {
    final live = context.read<LiveCatyBloc>().state;
    final movies = context.read<MovieCatyBloc>().state;
    final series = context.read<SeriesCatyBloc>().state;
    return (live is LiveCatySuccess && live.categories.isNotEmpty) ||
        (movies is MovieCatySuccess && movies.categories.isNotEmpty) ||
        (series is SeriesCatySuccess && series.categories.isNotEmpty);
  }

  /// عند العودة للتطبيق أو فتح الرئيسية بدون بيانات: شاشة التحميل أولاً.
  static Future<void> ensureHomeDataIfNeeded(BuildContext context) async {
    if (!context.mounted) return;
    if (context.read<SettingsCubit>().state.isDemo) return;
    if (LocaleApi.getUserSync() == null) return;
    if (!_needsReload(context)) return;

    final route = Get.currentRoute;
    if (route == screenHomeBootstrap) return;

    if (_isHomeDataMissing(context)) {
      if (route == screenWelcome) {
        await navigateToHomeBootstrap();
        return;
      }
      await run(context);
      return;
    }

    if (route == screenWelcome || _sessionBootstrapped) {
      await run(context);
      return;
    }

    await navigateToHomeBootstrap();
  }

  static bool _needsReload(BuildContext context) {
    if (_isHomeDataMissing(context)) return true;

    final live = context.read<LiveCatyBloc>().state;
    if (live is! LiveCatySuccess) return true;
    if (live.categories.isEmpty) return true;

    final movies = context.read<MovieCatyBloc>().state;
    if (movies is! MovieCatySuccess) return true;
    if (movies.categories.isEmpty) return true;

    final series = context.read<SeriesCatyBloc>().state;
    if (series is! SeriesCatySuccess) return true;
    if (series.categories.isEmpty) return true;

    return false;
  }

  static bool _isHomeDataMissing(BuildContext context) {
    final home = context.read<HomeRecentCubit>().state;
    if (home is HomeRecentInitial || home is HomeRecentLoading) return true;
    if (home is! HomeRecentSuccess) return true;
    // كاش القرص قد يكون isComplete=false أثناء التحديث في الخلفية.
    if (home.movies.isNotEmpty || home.series.isNotEmpty) return false;
    if (!home.isComplete) return true;
    return true;
  }

  static Future<void> _yieldFrame() async {
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
  }

  static Future<void> _yieldFrames(int count) async {
    for (var i = 0; i < count; i++) {
      await _yieldFrame();
    }
  }

  static Future<void> _ensureLiveCategories(BuildContext context) async {
    final bloc = context.read<LiveCatyBloc>();
    if (bloc.state is LiveCatySuccess &&
        (bloc.state as LiveCatySuccess).categories.isNotEmpty) {
      return;
    }
    bloc.add(GetLiveCategories());
    await bloc.stream
        .firstWhere((s) => s is LiveCatySuccess)
        .timeout(_stepTimeout, onTimeout: () => bloc.state);
  }

  static Future<void> _ensureMovieCategories(BuildContext context) async {
    final bloc = context.read<MovieCatyBloc>();
    if (bloc.state is MovieCatySuccess &&
        (bloc.state as MovieCatySuccess).categories.isNotEmpty) {
      return;
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      if (!context.mounted) return;
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      final current = bloc.state;
      if (current is MovieCatySuccess && current.categories.isNotEmpty) {
        return;
      }

      bloc.add(GetMovieCategories());
      await bloc.stream
          .firstWhere((s) => s is MovieCatySuccess)
          .timeout(_stepTimeout, onTimeout: () => bloc.state);

      if (bloc.state is MovieCatySuccess &&
          (bloc.state as MovieCatySuccess).categories.isNotEmpty) {
        return;
      }
    }
  }

  static Future<void> _ensureSeriesCategories(BuildContext context) async {
    final bloc = context.read<SeriesCatyBloc>();
    if (bloc.state is SeriesCatySuccess &&
        (bloc.state as SeriesCatySuccess).categories.isNotEmpty) {
      return;
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      if (!context.mounted) return;
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      final current = bloc.state;
      if (current is SeriesCatySuccess && current.categories.isNotEmpty) {
        return;
      }

      bloc.add(GetSeriesCategories());
      await bloc.stream
          .firstWhere((s) => s is SeriesCatySuccess)
          .timeout(_stepTimeout, onTimeout: () => bloc.state);

      if (bloc.state is SeriesCatySuccess &&
          (bloc.state as SeriesCatySuccess).categories.isNotEmpty) {
        return;
      }
    }
  }
}

class _DiskHydrateResult {
  const _DiskHydrateResult({
    this.liveCats = false,
    this.movieCats = false,
    this.seriesCats = false,
    this.liveChannels = false,
    this.allCatalogs = false,
  });

  final bool liveCats;
  final bool movieCats;
  final bool seriesCats;
  final bool liveChannels;
  final bool allCatalogs;

  bool get any =>
      liveCats || movieCats || seriesCats || liveChannels || allCatalogs;
}
