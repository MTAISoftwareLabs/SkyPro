import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mehdi_iptv/core/runtime_seal.dart';

import '../../../helpers/home_perf_logger.dart';
import '../../../repository/api/api.dart';
import '../../../repository/locale/home_recent_disk_cache.dart';
import '../../../repository/models/channel_movie.dart';
import '../../../repository/models/channel_serie.dart';
import '../../../repository/models/user.dart';
import '../../blocs/categories/channels/channels_bloc.dart';

part 'home_recent_state.dart';

/// عدد العناصر المعروضة في الصفحة الرئيسية (أفلام + مسلسلات عشوائية).
const int kHomeRecentLimit = 13;

/// عدد بطاقات الـ shimmer المرئية أثناء التحميل (أخف من العدد الكامل).
const int kHomeShimmerPlaceholderCount = 6;

String _homeUserKey(UserModel? user) {
  if (user == null) return '';
  return '${user.serverInfo?.serverUrl ?? ''}_${user.userInfo?.username ?? ''}';
}

/// أفلام/مسلسلات للرئيسية — كتalog كامل من السيرفر (نفس منطق التطبيق الأصلي).
class HomeRecentCubit extends Cubit<HomeRecentState> {
  HomeRecentCubit(this._channelsBloc) : super(const HomeRecentInitial()) {
    _hydrateFromDiskSync();
  }

  final ChannelsBloc _channelsBloc;
  bool _refreshInFlight = false;
  Completer<void>? _refreshCompleter;
  String? _loadedUserKey;

  void reset() {
    _refreshInFlight = false;
    if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
      _refreshCompleter!.complete();
    }
    _refreshCompleter = null;
    _loadedUserKey = null;
    emit(const HomeRecentInitial());
  }

  void _hydrateFromDiskSync() {
    final userKey = _homeUserKey(LocaleApi.getUserSync());
    if (userKey.isEmpty) return;
    final disk = HomeRecentDiskCache.readSync(userKey);
    if (disk == null) return;

    _loadedUserKey = userKey;
    emit(
      HomeRecentSuccess(
        movies: disk.movies,
        series: disk.series,
        fromCache: true,
        isComplete: false,
      ),
    );
    HomePerfLogger.mark(
      'home_disk_hydrate movies=${disk.movies.length} series=${disk.series.length}',
    );
  }

  /// يعرض الكاش فوراً إن وُجد، ثم يحدّث من الكتalog الكامل.
  Future<void> load({bool force = false}) async {
    RuntimeSeal.touchQuiet();
    final userKey = _homeUserKey(LocaleApi.getUserSync());

    if (_refreshInFlight && !force) return;

    if (!force &&
        state is HomeRecentSuccess &&
        _loadedUserKey == userKey &&
        userKey.isNotEmpty &&
        (state as HomeRecentSuccess).isComplete) {
      return;
    }

    if (userKey.isNotEmpty &&
        _loadedUserKey != null &&
        _loadedUserKey != userKey) {
      force = true;
      emit(const HomeRecentInitial());
      _loadedUserKey = null;
    }

    if (force) {
      _hydrateFromDiskSync();
    }

    final hasVisibleData = _hasVisibleData(state);

    if (!hasVisibleData) {
      emit(const HomeRecentLoading());
    } else if (state is HomeRecentSuccess) {
      emit((state as HomeRecentSuccess).copyWith(isRefreshing: true));
    }

    if (hasVisibleData && !force) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) unawaited(_refreshFromFullCatalog(userKey));
      });
      return;
    }

    await _refreshFromFullCatalog(userKey);
  }

  bool _hasVisibleData(HomeRecentState s) {
    if (s is! HomeRecentSuccess) return false;
    return s.movies.isNotEmpty || s.series.isNotEmpty;
  }

  Future<void> _refreshFromFullCatalog(String userKey) async {
    if (_refreshInFlight) {
      // انضم للتحديث الجاري بدل الخروج المبكر (كان يسبب تعليق 100%).
      await (_refreshCompleter?.future ?? Future<void>.value())
          .timeout(const Duration(seconds: 20), onTimeout: () {});
      return;
    }
    _refreshInFlight = true;
    _refreshCompleter = Completer<void>();
    HomePerfLogger.mark('home_recent_refresh_begin');

    try {
      HomePerfLogger.start('home_full_catalog_parallel');
      // مقترحة (shuffle) + مضافة حديثاً (sort) بالتوازي.
      final results = await Future.wait([
        HomePerfLogger.timeAsync(
          'home_full_catalog_movies',
          () => _channelsBloc.homeMoviesFromCategories(
            const [],
            limit: kHomeRecentLimit,
          ),
        ),
        HomePerfLogger.timeAsync(
          'home_full_catalog_series',
          () => _channelsBloc.homeSeriesFromCategories(
            const [],
            limit: kHomeRecentLimit,
          ),
        ),
        HomePerfLogger.timeAsync(
          'home_recent_added_movies',
          () => _channelsBloc.homeRecentlyAddedMovies(limit: kHomeRecentLimit),
        ),
        HomePerfLogger.timeAsync(
          'home_recent_added_series',
          () => _channelsBloc.homeRecentlyAddedSeries(limit: kHomeRecentLimit),
        ),
      ]).timeout(const Duration(seconds: 25));
      if (isClosed) return;

      final movies = results[0] as List<ChannelMovie>;
      final series = results[1] as List<ChannelSerie>;
      final recentMovies = results[2] as List<ChannelMovie>;
      final recentSeries = results[3] as List<ChannelSerie>;

      HomePerfLogger.end('home_full_catalog_parallel');
      _loadedUserKey = userKey;
      emit(
        HomeRecentSuccess(
          movies: movies,
          series: series,
          recentMovies: recentMovies,
          recentSeries: recentSeries,
          fromCache: false,
          isRefreshing: false,
          isComplete: true,
        ),
      );

      if (userKey.isNotEmpty) {
        unawaited(
          HomeRecentDiskCache.write(
            userKey,
            movies: movies,
            series: series,
          ),
        );
      }
      HomePerfLogger.mark('home_recent_refresh_complete');
    } catch (e) {
      if (kDebugMode) debugPrint('HomeRecentCubit refresh error: $e');
      if (state is! HomeRecentSuccess) {
        emit(
          const HomeRecentSuccess(
            movies: [],
            series: [],
            isComplete: true,
          ),
        );
      } else if (state is HomeRecentSuccess) {
        emit(
          (state as HomeRecentSuccess).copyWith(
            isRefreshing: false,
            isComplete: true,
          ),
        );
      }
    } finally {
      _refreshInFlight = false;
      final c = _refreshCompleter;
      _refreshCompleter = null;
      if (c != null && !c.isCompleted) c.complete();
    }
  }
}
