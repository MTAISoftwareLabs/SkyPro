import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../logic/blocs/categories/channels/channels_bloc.dart';
import '../services/iptv_image_cache.dart';
import '../logic/blocs/categories/live_caty/live_caty_bloc.dart';
import '../logic/blocs/categories/movie_caty/movie_caty_bloc.dart';
import '../logic/blocs/categories/series_caty/series_caty_bloc.dart';
import '../logic/cubits/favorites/favorites_cubit.dart';
import '../logic/cubits/home/home_recent_cubit.dart';
import '../logic/cubits/prefetch/prefetch_cubit.dart';
import '../logic/cubits/watch/watching_cubit.dart';
import '../repository/api/api.dart';
import '../services/epg_refresh_service.dart';
import '../services/home_hero_cache.dart';
import '../services/last_live_channel_service.dart';
import '../services/subtitle/subtitle_service.dart';
import '../repository/locale/home_recent_disk_cache.dart';
import '../repository/locale/live_recently_watched_store.dart';
import '../repository/locale/all_catalog_disk_cache.dart';
import '../repository/locale/catalog_category_counts_store.dart';
import '../repository/locale/catalog_disk_cache.dart';
import 'catalog_sync_service.dart';
import 'helpers.dart';
import 'home_bootstrap_loader.dart';

/// مسح كل الكاش المرتبط بالسيرفر عند تسجيل الخروج أو تغيير الحساب.
class AppCacheClearer {
  AppCacheClearer._();

  static Future<void> clearApiAndDisk() async {
    IpTvApi.clearM3UCache();
    IpTvApi.clearApiCaches();
    CatalogSyncService.instance.reset();
    await HomeRecentDiskCache.clearAll();
    await AllCatalogDiskCache.clearAll();
    await CatalogDiskCache.clearAll();
    CatalogCategoryCountsStore.clearAll();
    PrefetchCubit.clearAllCaches();
    HomeHeroCache.clear();
    await SubtitleService.clearAllCaches();
    await EpgRefreshService.clearCache();
  }

  /// مفضلة + سجل المشاهدة المحلي (صندوق GetStorage المنفصل).
  static Future<void> clearUserLocalData() async {
    await favoritesLocale.erase();
    LastLiveChannelService.clear();
    LiveRecentlyWatchedStore.clearAll();
  }

  /// إعادة ضبط حالة الـ blocs/cubits في الذاكرة (بدون مسح API أو المفضلة المحلية).
  static void resetSessionBlocs(BuildContext context) {
    context.read<LiveCatyBloc>().add(ResetLiveCatySession());
    context.read<MovieCatyBloc>().add(ResetMovieCatySession());
    context.read<SeriesCatyBloc>().add(ResetSeriesCatySession());
    context.read<ChannelsBloc>().add(ResetChannelsSession());
    context.read<HomeRecentCubit>().reset();
    context.read<FavoritesCubit>().reset();
    context.read<WatchingCubit>().reset();
  }

  /// جلب تصنيفات السيرفر الجديد بعد تسجيل الدخول.
  static void prefetchServerCatalog(BuildContext context) {
    context.read<LiveCatyBloc>().add(GetLiveCategories());
    context.read<MovieCatyBloc>().add(GetMovieCategories());
    context.read<SeriesCatyBloc>().add(GetSeriesCategories());
    context.read<HomeRecentCubit>().load(force: true);
  }

  /// تسجيل خروج كامل: كاش API + تخزين محلي + إعادة ضبط الذاكرة.
  static Future<void> clearSessionOnLogout(BuildContext context) async {
    HomeBootstrapLoader.resetSession();
    await clearApiAndDisk();
    await clearUserLocalData();
    clearPreferredLiveStablePlayer();
    if (!context.mounted) return;
    resetSessionBlocs(context);
    try {
      await iptvImageCacheManager.emptyCache();
      clearIptvImageWarmRegistry();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
  }

  /// جلسة نظيفة قبل الدخول بسيرفر/حساب جديد (التحميل الفعلي في شاشة bootstrap).
  static Future<void> prepareNewServerSession(BuildContext context) async {
    HomeBootstrapLoader.resetSession();
    await clearApiAndDisk();
    if (!context.mounted) return;
    resetSessionBlocs(context);
  }

  static Future<void> clearAllWithBlocs(BuildContext context) async {
    await clearSessionOnLogout(context);
  }
}
