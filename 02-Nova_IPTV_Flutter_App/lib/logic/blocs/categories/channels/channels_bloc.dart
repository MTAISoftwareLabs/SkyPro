import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mehdi_iptv/helpers/helpers.dart';
import 'package:mehdi_iptv/helpers/home_perf_logger.dart';
import 'package:mehdi_iptv/repository/models/channel_movie.dart';
import 'package:mehdi_iptv/repository/locale/all_catalog_disk_cache.dart';
import 'package:mehdi_iptv/repository/locale/catalog_category_counts_store.dart';
import 'package:mehdi_iptv/repository/locale/catalog_disk_cache.dart';
import 'package:mehdi_iptv/repository/locale/catalog_fingerprint.dart';

import '../../../../repository/api/api.dart';
import '../../../../repository/models/category.dart';
import '../../../../repository/models/channel_live.dart';
import '../../../../repository/models/channel_serie.dart';

part 'channels_event.dart';
part 'channels_state.dart';

class ChannelsBloc extends Bloc<ChannelsEvent, ChannelsState> {
  ChannelsBloc(this.api) : super(ChannelsLoading()) {
    on<ResetChannelsSession>((event, emit) async {
      clearLiveCache();
      clearMoviesCache();
      clearSeriesCache();
      _movieCounts.clear();
      _seriesCounts.clear();
      emit(ChannelsLoading());
    });
    on<GetLiveChannelsEvent>((event, emit) async {
      if (event.typeCategory == TypeCategory.series) {
        final cached = _seriesCache[event.catyId];
        if (cached != null && cached.isNotEmpty) {
          emit(ChannelsSeriesSuccess(cached, categoryId: event.catyId));
          return;
        }
        emit(ChannelsLoading());
      } else if (event.typeCategory == TypeCategory.movies) {
        final cached = _movieCache[event.catyId];
        if (cached != null && cached.isNotEmpty) {
          emit(ChannelsMovieSuccess(cached, categoryId: event.catyId));
          return;
        }
        emit(ChannelsLoading());
      } else {
        // live — القائمة غير الفارغة من الكاش جاهزة فوراً.
        // القائمة الفارغة قد تكون فشلاً سابقاً؛ نعيد الجلب بدل إظهار فئة فارغة دائماً.
        final cached = _liveCache[event.catyId];
        if (cached != null && cached.isNotEmpty) {
          _lastLiveCategoryId = event.catyId;
          emit(ChannelsLiveSuccess(cached, categoryId: event.catyId));
          return;
        }
        emit(ChannelsLoading());
      }

      if (event.typeCategory == TypeCategory.live) {
        // ألغِ نتيجة الجلب الأقدم إن طلب المستخدم فئة أحدث أثناء الانتظار.
        final serial = ++_liveFetchSerial;
        _liveFetchInFlightId = event.catyId;
        try {
          // الفهرس الكامل خلفية فقط — لا ننتظره هنا (كان يعلّق الفئات التحتية).
          if (!_fullLiveIndexReady) {
            unawaited(ensureFullLiveIndex());
          } else {
            final indexed = _liveCache[event.catyId];
            if (indexed != null && indexed.isNotEmpty) {
              if (serial != _liveFetchSerial) return;
              _lastLiveCategoryId = event.catyId;
              emit(ChannelsLiveSuccess(indexed, categoryId: event.catyId));
              return;
            }
          }

          var result = await api.getLiveChannels(event.catyId);
          // إعادة محاولة واحدة — السيرفرات أحياناً ترجع [] تحت الضغط.
          if (result.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 350));
            if (serial != _liveFetchSerial) return;
            result = await api.getLiveChannels(event.catyId);
          }
          // إن اكتمل الفهرس أثناء الانتظار واستعملناه إن بقيت النتيجة فارغة.
          if (result.isEmpty) {
            final indexed = _liveCache[event.catyId];
            if (indexed != null && indexed.isNotEmpty) result = indexed;
          }

          if (result.isNotEmpty) {
            _liveCache[event.catyId] = result;
            _persistLiveCategory(event.catyId, result);
          } else {
            // لا تسمّم الكاش بـ [] — أبقِ المفتاح غائباً لإعادة الجلب.
            _liveCache.remove(event.catyId);
          }
          if (serial != _liveFetchSerial) return;
          _lastLiveCategoryId = event.catyId;
          emit(ChannelsLiveSuccess(result, categoryId: event.catyId));
        } catch (e) {
          if (serial != _liveFetchSerial) return;
          _lastLiveCategoryId = event.catyId;
          // لا نسمّم الكاش بقائمة فارغة عند فشل الشبكة — حتى يمكن إعادة المحاولة.
          emit(ChannelsLiveSuccess(const [], categoryId: event.catyId));
        } finally {
          if (serial == _liveFetchSerial) {
            _liveFetchInFlightId = null;
          }
        }
      } else if (event.typeCategory == TypeCategory.movies) {
        final isAll = event.catyId == '__all__';
        final isRecent = event.catyId == kRecentlyAddedCategoryId;
        try {
          List<ChannelMovie> base;
          if (isRecent) {
            base = await ensureRecentlyAddedMovies();
          } else if (isAll) {
            // عرض تدريجي: أول فئة ~ثانية بدل انتظار كتالوج كامل لدقائق.
            base = await _resolveFullMovieCatalog(
              onPartial: (partial) {
                if (partial.isEmpty) return;
                _movieCache[event.catyId] = partial;
                emit(ChannelsMovieSuccess(partial, categoryId: event.catyId));
              },
            );
          } else {
            base = await api.getMovieChannels(event.catyId);
            // أحيانًا أول طلب يرجع [] بشكل مؤقت (مثلًا بسبب تجهيز بيانات المستخدم/الاتصال).
            if (base.isEmpty) {
              await Future<void>.delayed(const Duration(milliseconds: 350));
              base = await api.getMovieChannels(event.catyId);
            }
          }

          if (base.isNotEmpty) {
            _movieCache[event.catyId] = base;
            _noteMovieCount(event.catyId, base.length);
          } else if (isAll || isRecent) {
            final kept = _movieCache[event.catyId];
            if (kept != null && kept.isNotEmpty) base = kept;
          }
          emit(ChannelsMovieSuccess(base, categoryId: event.catyId));
        } catch (e) {
          final kept = _movieCache[event.catyId] ?? const <ChannelMovie>[];
          emit(ChannelsMovieSuccess(kept, categoryId: event.catyId));
        }
      } else if (event.typeCategory == TypeCategory.series) {
        final isAll = event.catyId == '__all__';
        final isRecent = event.catyId == kRecentlyAddedCategoryId;
        try {
          List<ChannelSerie> base;
          if (isRecent) {
            base = await ensureRecentlyAddedSeries();
          } else if (isAll) {
            // نفس مسار الأفلام: جلب متوازٍ للفئات + عرض تدريجي بدون فرز.
            base = await _resolveFullSeriesCatalog(
              onPartial: (partial) {
                if (partial.isEmpty) return;
                _seriesCache[event.catyId] = partial;
                emit(ChannelsSeriesSuccess(partial, categoryId: event.catyId));
              },
            );
          } else {
            base = await api.getSeriesChannels(event.catyId);
            if (base.isEmpty) {
              await Future<void>.delayed(const Duration(milliseconds: 350));
              base = await api.getSeriesChannels(event.catyId);
            }
          }

          if (base.isNotEmpty) {
            _seriesCache[event.catyId] = base;
            _noteSeriesCount(event.catyId, base.length);
          } else if (isAll || isRecent) {
            final kept = _seriesCache[event.catyId];
            if (kept != null && kept.isNotEmpty) base = kept;
          }
          emit(ChannelsSeriesSuccess(base, categoryId: event.catyId));
        } catch (e) {
          final kept = _seriesCache[event.catyId] ?? const <ChannelSerie>[];
          emit(ChannelsSeriesSuccess(kept, categoryId: event.catyId));
        }
      }
    });
  }

  final IpTvApi api;
  final Map<String, List<ChannelLive>> _liveCache = {};
  final Map<String, List<ChannelSerie>> _seriesCache = {};
  final Map<String, List<ChannelMovie>> _movieCache = {};
  Future<List<ChannelMovie>>? _movieAllResolveInFlight;
  Future<List<ChannelSerie>>? _seriesAllResolveInFlight;
  final List<void Function(List<ChannelMovie>)> _movieAllPartialListeners = [];
  final List<void Function(List<ChannelSerie>)> _seriesAllPartialListeners = [];

  final CatalogCountsTick catalogCounts = CatalogCountsTick();
  final Map<String, int> _movieCounts = {};
  final Map<String, int> _seriesCounts = {};
  int _movieCountIndexGen = 0;
  int _seriesCountIndexGen = 0;
  Timer? _movieCountIndexTimer;
  Timer? _seriesCountIndexTimer;
  Timer? _countPingTimer;
  Timer? _countPersistTimer;
  bool _countsPingQueued = false;

  /// أثناء شاشة التحميل: لا فرز/فهرسة على الخيط الرئيسي حتى لا تتجمّد الدائرة.
  bool deferIdleCatalogWork = false;

  /// آخر فئة بث مباشر حُمّلت (حتى بعد مغادرة شاشة البث أو تبديل الفئة من المشغّل).
  String? _lastLiveCategoryId;
  String? get lastLiveCategoryId => _lastLiveCategoryId;

  /// يمنع إصدار نتيجة جلب قديمة عند تبديل الفئة بسرعة.
  int _liveFetchSerial = 0;
  String? _liveFetchInFlightId;

  /// فهرس كامل لكل قنوات Live — مقسّم حسب category_id.
  bool _fullLiveIndexReady = false;
  Future<bool>? _fullLiveIndexInFlight;
  bool get isFullLiveIndexReady => _fullLiveIndexReady;

  bool hasLiveCategoryCached(String catyId) => _liveCache.containsKey(catyId);

  bool hasLiveCategoryReady(String catyId) {
    final list = _liveCache[catyId];
    return list != null && list.isNotEmpty;
  }

  bool isLiveFetchInFlight(String catyId) =>
      _liveFetchInFlightId == catyId && catyId.isNotEmpty;

  /// كل قنوات Live المخزّنة (لبحث الشريط عبر كل الفئات).
  List<ChannelLive> allCachedLiveChannels() {
    final seen = <String>{};
    final out = <ChannelLive>[];
    for (final list in _liveCache.values) {
      for (final ch in list) {
        final id = (ch.streamId ?? '').trim();
        if (id.isEmpty || !seen.add(id)) continue;
        out.add(ch);
      }
    }
    return out;
  }

  List<ChannelMovie>? movieListForCategoryId(String catyId) =>
      _movieCache[catyId];

  List<ChannelSerie>? seriesListForCategoryId(String catyId) =>
      _seriesCache[catyId];

  int movieCountForCategoryId(String? id) {
    if (id == null || id.isEmpty) return 0;
    final list = _movieCache[id];
    if (list != null) return list.length;
    return _movieCounts[id] ?? 0;
  }

  int seriesCountForCategoryId(String? id) {
    if (id == null || id.isEmpty) return 0;
    final list = _seriesCache[id];
    if (list != null) return list.length;
    return _seriesCounts[id] ?? 0;
  }

  void ensureCatalogCounts() {
    if (deferIdleCatalogWork) return;
    if (_movieCounts.isEmpty && _seriesCounts.isEmpty) {
      _hydrateSavedCounts();
    }
    final movies = _movieCache['__all__'];
    if (movies != null &&
        movies.isNotEmpty &&
        _movieCounts.length < 3) {
      _scheduleMovieCountIndex();
    }
    final series = _seriesCache['__all__'];
    if (series != null &&
        series.isNotEmpty &&
        _seriesCounts.length < 3) {
      _scheduleSeriesCountIndex();
    }
  }

  /// بعد مغادرة شاشة التحميل: Recently Added + عدّاد الفئات في الخلفية.
  void resumeIdleCatalogWork() {
    deferIdleCatalogWork = false;
    ensureCatalogCounts();
    unawaited(ensureRecentlyAddedMovies());
    unawaited(ensureRecentlyAddedSeries());
  }

  void _pingCatalogCounts({bool now = false}) {
    if (now) {
      _countPingTimer?.cancel();
      _countsPingQueued = false;
      catalogCounts.ping();
      return;
    }
    if (_countPingTimer?.isActive ?? false) {
      _countsPingQueued = true;
      return;
    }
    catalogCounts.ping();
    _countPingTimer = Timer(const Duration(milliseconds: 420), () {
      if (!_countsPingQueued) return;
      _countsPingQueued = false;
      catalogCounts.ping();
    });
  }

  void _noteMovieCount(String id, int n) {
    if (id.isEmpty || n <= 0) return;
    if (_movieCounts[id] == n) return;
    _movieCounts[id] = n;
    _pingCatalogCounts();
    _schedulePersistCounts();
  }

  void _noteSeriesCount(String id, int n) {
    if (id.isEmpty || n <= 0) return;
    if (_seriesCounts[id] == n) return;
    _seriesCounts[id] = n;
    _pingCatalogCounts();
    _schedulePersistCounts();
  }

  void _schedulePersistCounts() {
    _countPersistTimer?.cancel();
    _countPersistTimer = Timer(const Duration(seconds: 2), () {
      final key = _catalogUserKey();
      if (key.isEmpty) return;
      if (_movieCounts.isNotEmpty) {
        CatalogCategoryCountsStore.writeMovies(key, _movieCounts);
      }
      if (_seriesCounts.isNotEmpty) {
        CatalogCategoryCountsStore.writeSeries(key, _seriesCounts);
      }
    });
  }

  void _hydrateSavedCounts() {
    final key = _catalogUserKey();
    if (key.isEmpty) return;
    final movies = CatalogCategoryCountsStore.readMovies(key);
    if (movies.isNotEmpty) _movieCounts.addAll(movies);
    final series = CatalogCategoryCountsStore.readSeries(key);
    if (series.isNotEmpty) _seriesCounts.addAll(series);
    if (movies.isNotEmpty || series.isNotEmpty) {
      _pingCatalogCounts(now: true);
    }
  }

  void _scheduleMovieCountIndex() {
    if (deferIdleCatalogWork) return;
    _movieCountIndexTimer?.cancel();
    _movieCountIndexTimer = Timer(const Duration(milliseconds: 220), () {
      if (deferIdleCatalogWork) return;
      final all = _movieCache['__all__'];
      if (all == null || all.isEmpty) return;
      _indexMovieCountsIdle(all);
    });
  }

  void _scheduleSeriesCountIndex() {
    if (deferIdleCatalogWork) return;
    _seriesCountIndexTimer?.cancel();
    _seriesCountIndexTimer = Timer(const Duration(milliseconds: 220), () {
      if (deferIdleCatalogWork) return;
      final all = _seriesCache['__all__'];
      if (all == null || all.isEmpty) return;
      _indexSeriesCountsIdle(all);
    });
  }

  void _indexMovieCountsIdle(List<ChannelMovie> all) {
    final gen = ++_movieCountIndexGen;
    final acc = <String, int>{};
    var i = 0;
    const chunk = 160;

    void step(Duration _) {
      if (gen != _movieCountIndexGen || deferIdleCatalogWork) return;
      final end = i + chunk > all.length ? all.length : i + chunk;
      for (; i < end; i++) {
        final id = (all[i].categoryId ?? '').trim();
        if (id.isEmpty) continue;
        acc[id] = (acc[id] ?? 0) + 1;
      }
      if (i < all.length) {
        SchedulerBinding.instance.scheduleFrameCallback(step);
        return;
      }
      acc['__all__'] = all.length;
      final recent = _movieCache[kRecentlyAddedCategoryId];
      if (recent != null && recent.isNotEmpty) {
        acc[kRecentlyAddedCategoryId] = recent.length;
      }
      _movieCounts
        ..clear()
        ..addAll(acc);
      _pingCatalogCounts(now: true);
      _schedulePersistCounts();
    }

    SchedulerBinding.instance.scheduleFrameCallback(step);
  }

  void _indexSeriesCountsIdle(List<ChannelSerie> all) {
    final gen = ++_seriesCountIndexGen;
    final acc = <String, int>{};
    var i = 0;
    const chunk = 160;

    void step(Duration _) {
      if (gen != _seriesCountIndexGen || deferIdleCatalogWork) return;
      final end = i + chunk > all.length ? all.length : i + chunk;
      for (; i < end; i++) {
        final id = (all[i].categoryId ?? '').trim();
        if (id.isEmpty) continue;
        acc[id] = (acc[id] ?? 0) + 1;
      }
      if (i < all.length) {
        SchedulerBinding.instance.scheduleFrameCallback(step);
        return;
      }
      acc['__all__'] = all.length;
      final recent = _seriesCache[kRecentlyAddedCategoryId];
      if (recent != null && recent.isNotEmpty) {
        acc[kRecentlyAddedCategoryId] = recent.length;
      }
      _seriesCounts
        ..clear()
        ..addAll(acc);
      _pingCatalogCounts(now: true);
      _schedulePersistCounts();
    }

    SchedulerBinding.instance.scheduleFrameCallback(step);
  }

  List<ChannelLive>? liveListForCategoryId(String catyId) => _liveCache[catyId];

  /// كتالوج الأفلام الكامل للبحث عبر كل الفئات (يُخزَّن تحت `__all__`).
  Future<List<ChannelMovie>> ensureFullMovieCatalog({bool force = false}) =>
      _resolveFullMovieCatalog(force: force);

  /// كتالوج المسلسلات الكامل للبحث عبر كل الفئات (يُخزَّن تحت `__all__`).
  Future<List<ChannelSerie>> ensureFullSeriesCatalog({bool force = false}) =>
      _resolveFullSeriesCatalog(force: force);

  /// أحدث 32 فيلم من السيرفر (أو أقل إن وُجد أقل).
  Future<List<ChannelMovie>> ensureRecentlyAddedMovies({
    bool force = false,
  }) async {
    const key = kRecentlyAddedCategoryId;
    if (!force) {
      final cached = _movieCache[key];
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final all = _movieCache['__all__'];
    if (all != null && all.isNotEmpty) {
      final sliced = _sliceRecentlyAddedMovies(all);
      _movieCache[key] = sliced;
      return sliced;
    }

    try {
      final remote = await api.getRecentlyAddedMovies(
        limit: kRecentlyAddedLimit,
      );
      if (remote.isNotEmpty) {
        _movieCache[key] = remote;
        return remote;
      }
    } catch (e) { /* ignore */ }

    final full = await _resolveFullMovieCatalog();
    final sliced = _sliceRecentlyAddedMovies(full);
    _movieCache[key] = sliced;
    return sliced;
  }

  /// أحدث 32 مسلسل — last_modified يرتفع عند إضافة حلقة.
  Future<List<ChannelSerie>> ensureRecentlyAddedSeries({
    bool force = false,
  }) async {
    const key = kRecentlyAddedCategoryId;
    if (!force) {
      final cached = _seriesCache[key];
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final all = _seriesCache['__all__'];
    if (all != null && all.isNotEmpty) {
      final sliced = _sliceRecentlyAddedSeries(all);
      _seriesCache[key] = sliced;
      return sliced;
    }

    try {
      final remote = await api.getRecentlyAddedSeries(
        limit: kRecentlyAddedLimit,
      );
      if (remote.isNotEmpty) {
        _seriesCache[key] = remote;
        return remote;
      }
    } catch (e) { /* ignore */ }

    final full = await _resolveFullSeriesCatalog();
    final sliced = _sliceRecentlyAddedSeries(full);
    _seriesCache[key] = sliced;
    return sliced;
  }

  static List<ChannelMovie> _sliceRecentlyAddedMovies(
    List<ChannelMovie> all,
  ) {
    if (all.isEmpty) return const [];
    final hasTs = all.any((e) => e.sortTimestamp > 0);
    if (!hasTs) {
      return all.length > kRecentlyAddedLimit
          ? all.sublist(0, kRecentlyAddedLimit)
          : List<ChannelMovie>.from(all);
    }
    final sorted = List<ChannelMovie>.from(all)
      ..sort((a, b) {
        final c = b.sortTimestamp.compareTo(a.sortTimestamp);
        if (c != 0) return c;
        return (a.name ?? '').toLowerCase().compareTo(
          (b.name ?? '').toLowerCase(),
        );
      });
    return sorted.length > kRecentlyAddedLimit
        ? sorted.sublist(0, kRecentlyAddedLimit)
        : sorted;
  }

  static List<ChannelSerie> _sliceRecentlyAddedSeries(
    List<ChannelSerie> all,
  ) {
    if (all.isEmpty) return const [];
    final hasTs = all.any((e) => e.sortTimestamp > 0);
    if (!hasTs) {
      return all.length > kRecentlyAddedLimit
          ? all.sublist(0, kRecentlyAddedLimit)
          : List<ChannelSerie>.from(all);
    }
    final sorted = List<ChannelSerie>.from(all)
      ..sort((a, b) {
        final c = b.sortTimestamp.compareTo(a.sortTimestamp);
        if (c != 0) return c;
        return (a.name ?? '').toLowerCase().compareTo(
          (b.name ?? '').toLowerCase(),
        );
      });
    return sorted.length > kRecentlyAddedLimit
        ? sorted.sublist(0, kRecentlyAddedLimit)
        : sorted;
  }

  /// هل جلب All للأفلام جارٍ حالياً؟
  bool get isFullMovieCatalogLoading => _movieAllResolveInFlight != null;

  /// هل جلب All للمسلسلات جارٍ حالياً؟
  bool get isFullSeriesCatalogLoading => _seriesAllResolveInFlight != null;

  String get catalogUserKey => _catalogUserKey();

  String _catalogUserKey() {
    final user = LocaleApi.getUserSync();
    if (user == null) return '';
    return '${user.serverInfo?.serverUrl ?? ''}_${user.userInfo?.username ?? ''}';
  }

  /// يسترجع قنوات Live من القرص إلى الذاكرة (جلسة باردة).
  Future<int> hydrateLiveFromDisk() async {
    final userKey = _catalogUserKey();
    if (userKey.isEmpty) return 0;
    final map = await CatalogDiskCache.readAllLive(userKey);
    if (map.isEmpty) return 0;
    var n = 0;
    for (final entry in map.entries) {
      if (entry.value.isEmpty) continue;
      _liveCache[entry.key] = entry.value;
      n++;
      if (n % 6 == 0) {
        await SchedulerBinding.instance.endOfFrame;
        await Future<void>.delayed(Duration.zero);
      }
    }
    return map.length;
  }

  /// يسترجع كتالوج All من القرص إن وُجد (بدون شبكة).
  Future<bool> hydrateAllCatalogsFromDisk() async {
    final userKey = _catalogUserKey();
    if (userKey.isEmpty) return false;
    var any = false;
    _hydrateSavedCounts();
    final movies = await AllCatalogDiskCache.readMovies(userKey);
    if (movies != null && movies.isNotEmpty) {
      _movieCache['__all__'] = movies;
      if (!deferIdleCatalogWork) {
        _movieCache[kRecentlyAddedCategoryId] =
            _sliceRecentlyAddedMovies(movies);
        _scheduleMovieCountIndex();
      }
      any = true;
    }
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    final series = await AllCatalogDiskCache.readSeries(userKey);
    if (series != null && series.isNotEmpty) {
      _seriesCache['__all__'] = series;
      if (!deferIdleCatalogWork) {
        _seriesCache[kRecentlyAddedCategoryId] =
            _sliceRecentlyAddedSeries(series);
        _scheduleSeriesCountIndex();
      }
      any = true;
    }
    return any;
  }

  void evictLiveCategory(String catyId) {
    _liveCache.remove(catyId);
    if (_lastLiveCategoryId == catyId) _lastLiveCategoryId = null;
  }

  void _persistLiveCategory(String catyId, List<ChannelLive> list) {
    if (catyId.isEmpty || list.isEmpty) return;
    final userKey = _catalogUserKey();
    if (userKey.isEmpty) return;
    CatalogDiskCache.writeLiveCategory(userKey, catyId, list);
  }

  Future<void> _persistMoviesAllIfChanged(List<ChannelMovie> base) async {
    final userKey = _catalogUserKey();
    if (userKey.isEmpty || base.isEmpty) return;
    final fp = CatalogFingerprint.movies(base);
    final prev = await CatalogDiskCache.getFingerprint(userKey, 'movies_all');
    if (prev == fp) return;
    AllCatalogDiskCache.writeMovies(userKey, base);
    await CatalogDiskCache.putFingerprint(userKey, 'movies_all', fp);
  }

  Future<void> _persistSeriesAllIfChanged(List<ChannelSerie> base) async {
    final userKey = _catalogUserKey();
    if (userKey.isEmpty || base.isEmpty) return;
    final fp = CatalogFingerprint.series(base);
    final prev = await CatalogDiskCache.getFingerprint(userKey, 'series_all');
    if (prev == fp) return;
    AllCatalogDiskCache.writeSeries(userKey, base);
    await CatalogDiskCache.putFingerprint(userKey, 'series_all', fp);
  }

  /// Fetches and caches live channels without changing [state] (for IPTV overlay meta).
  Future<List<ChannelLive>> ensureLiveCategoryCached(String catyId) async {
    final existing = _liveCache[catyId];
    if (existing != null && existing.isNotEmpty) return existing;

    // لا ننتظر الفهرس الكامل — جلب الفئة مباشرة (الفهرس يملأ الكاش في الخلفية).
    if (!_fullLiveIndexReady) {
      unawaited(ensureFullLiveIndex());
    }

    try {
      final result = await api.getLiveChannels(catyId);
      if (result.isNotEmpty) {
        _liveCache[catyId] = result;
        _persistLiveCategory(catyId, result);
      }
      return result;
    } catch (e) {
      // لا نخزّن [] عند الفشل — وإلا تظهر الفئات الأولى فارغة بشكل دائم.
      return const [];
    }
  }

  ///  جلب كل الـ live streams مرة واحدة وتقسيمها حسب الفئة في الكاش.
  Future<bool> ensureFullLiveIndex() {
    if (_fullLiveIndexReady) return Future<bool>.value(true);
    return _fullLiveIndexInFlight ??= _buildFullLiveIndex();
  }

  Future<bool> _buildFullLiveIndex() async {
    try {
      final all = await api.getAllLiveStreams();
      if (all.isEmpty) {
        if (kDebugMode) {
        }
        return false;
      }

      final byCat = <String, List<ChannelLive>>{};
      for (final ch in all) {
        final id = _normalizeLiveCategoryId(ch.categoryId);
        if (id == null) continue;
        (byCat[id] ??= <ChannelLive>[]).add(ch);
      }

      var filled = 0;
      for (final entry in byCat.entries) {
        if (entry.value.isEmpty) continue;
        final existing = _liveCache[entry.key];
        // لا تستبدل قائمة جاهزة من جلب مباشر أحدث.
        if (existing != null && existing.isNotEmpty) continue;
        _liveCache[entry.key] = List<ChannelLive>.unmodifiable(entry.value);
        filled++;
      }

      _fullLiveIndexReady = filled > 0;
      if (kDebugMode) {
      }
      return _fullLiveIndexReady;
    } catch (e) {
      return false;
    } finally {
      // اسمح بإعادة المحاولة إن فشلنا؛ أبقِ future مشتركاً إن نجحنا.
      if (!_fullLiveIndexReady) {
        _fullLiveIndexInFlight = null;
      }
    }
  }

  /// أزل كاش فئة (لإعادة الجلب عند قائمة فارغة عالقة).
  void invalidateLiveCategory(String catyId) {
    if (catyId.isEmpty) return;
    _liveCache.remove(catyId);
  }

  static String? _normalizeLiveCategoryId(String? raw) {
    if (raw == null) return null;
    final id = raw.trim();
    if (id.isEmpty || id == 'null' || id == 'undefined') return null;
    return id;
  }

  void seedLiveCategory(String catyId, List<ChannelLive> channels) {
    _liveCache[catyId] = channels;
    if (catyId.isNotEmpty) _lastLiveCategoryId = catyId;
  }

  void clearMoviesCache() {
    _movieCache.clear();
    _movieAllResolveInFlight = null;
    _movieAllPartialListeners.clear();
  }

  void clearSeriesCache() {
    _seriesCache.clear();
    _seriesAllResolveInFlight = null;
    _seriesAllPartialListeners.clear();
  }

  void clearLiveCache() {
    _liveCache.clear();
    _lastLiveCategoryId = null;
    _liveFetchSerial++;
    _liveFetchInFlightId = null;
    _fullLiveIndexReady = false;
    _fullLiveIndexInFlight = null;
  }

  /// جلب فئة أفلام مرة واحدة وتخزينها — يُعاد استخدامها في الأقسام.
  Future<List<ChannelMovie>> ensureMovieCategoryCached(String catyId) async {
    if (catyId.isEmpty) return const [];
    final existing = _movieCache[catyId];
    if (existing != null) return existing;
    try {
      var result = await api.getMovieChannels(catyId);
      if (result.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        result = await api.getMovieChannels(catyId);
      }
      _movieCache[catyId] = result;
      if (result.isNotEmpty) _noteMovieCount(catyId, result.length);
      return result;
    } catch (e) {
      _movieCache[catyId] = const [];
      return const [];
    }
  }

  /// جلب فئة مسلسلات مرة واحدة وتخزينها — يُعاد استخدامها في الرئيسية والأقسام.
  Future<List<ChannelSerie>> ensureSeriesCategoryCached(String catyId) async {
    if (catyId.isEmpty) return const [];
    final existing = _seriesCache[catyId];
    if (existing != null) return existing;
    try {
      var result = await api.getSeriesChannels(catyId);
      if (result.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        result = await api.getSeriesChannels(catyId);
      }
      _seriesCache[catyId] = result;
      if (result.isNotEmpty) _noteSeriesCount(catyId, result.length);
      return result;
    } catch (e) {
      _seriesCache[catyId] = const [];
      return const [];
    }
  }

  /// عناصر الرئيسية — طلب شبكة واحد + parse في isolate (لا يجمّد الواجهة).
  Future<List<ChannelMovie>> homeMoviesFromCategories(
    List<CategoryModel> apiCategories, {
    int limit = 13,
  }) async {
    const label = 'home_fast_movies';
    HomePerfLogger.start(label);
    var result = await api.getHomeRecentMovies(limit: limit);
    if (result.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      result = await api.getHomeRecentMovies(limit: limit);
    }
    if (result.isEmpty) {
      HomePerfLogger.mark('$label.full_catalog_fallback');
      final catalog = await api.getMovieChannels(null);
      if (catalog.isNotEmpty) {
        result = catalog.length > limit ? catalog.sublist(0, limit) : catalog;
      }
    }
    if (result.length > 1) {
      await SchedulerBinding.instance.endOfFrame;
      result = List<ChannelMovie>.from(result)..shuffle(Random());
    }
    HomePerfLogger.end(label, extra: 'count=${result.length}');
    return result;
  }

  /// أفلام مرتبة بالأحدث (Recently added) — بدون shuffle.
  Future<List<ChannelMovie>> homeRecentlyAddedMovies({int limit = 13}) async {
    const label = 'home_recent_added_movies';
    HomePerfLogger.start(label);
    var result = await api.getHomeRecentMovies(limit: max(limit * 3, 40));
    if (result.isEmpty) {
      final catalog = await api.getMovieChannels(null);
      if (catalog.isNotEmpty) result = catalog;
    }
    result = List<ChannelMovie>.from(result)
      ..sort((a, b) => b.sortTimestamp.compareTo(a.sortTimestamp));
    if (result.length > limit) result = result.sublist(0, limit);
    HomePerfLogger.end(label, extra: 'count=${result.length}');
    return result;
  }

  /// عناصر الرئيسية — طلب شبكة واحد + parse في isolate (لا يجمّد الواجهة).
  Future<List<ChannelSerie>> homeSeriesFromCategories(
    List<CategoryModel> apiCategories, {
    int limit = 13,
  }) async {
    const label = 'home_fast_series';
    HomePerfLogger.start(label);
    var result = await api.getHomeRecentSeries(limit: limit);
    if (result.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      result = await api.getHomeRecentSeries(limit: limit);
    }
    if (result.isEmpty) {
      HomePerfLogger.mark('$label.full_catalog_fallback');
      final catalog = await api.getSeriesChannels(null);
      if (catalog.isNotEmpty) {
        result = catalog.length > limit ? catalog.sublist(0, limit) : catalog;
      }
    }
    if (result.length > 1) {
      await SchedulerBinding.instance.endOfFrame;
      result = List<ChannelSerie>.from(result)..shuffle(Random());
    }
    HomePerfLogger.end(label, extra: 'count=${result.length}');
    return result;
  }

  /// مسلسلات مرتبة بالأحدث (Recently added) — بدون shuffle.
  Future<List<ChannelSerie>> homeRecentlyAddedSeries({int limit = 13}) async {
    const label = 'home_recent_added_series';
    HomePerfLogger.start(label);
    var result = await api.getHomeRecentSeries(limit: max(limit * 3, 40));
    if (result.isEmpty) {
      final catalog = await api.getSeriesChannels(null);
      if (catalog.isNotEmpty) result = catalog;
    }
    result = List<ChannelSerie>.from(result)
      ..sort((a, b) => b.sortTimestamp.compareTo(a.sortTimestamp));
    if (result.length > limit) result = result.sublist(0, limit);
    HomePerfLogger.end(label, extra: 'count=${result.length}');
    return result;
  }

  /// كتالوج الأفلام الكامل: ذاكرة → قرص → فئات متوازية (سريعة) → احتياطي طلب كامل.
  Future<List<ChannelMovie>> _resolveFullMovieCatalog({
    bool force = false,
    void Function(List<ChannelMovie> partial)? onPartial,
  }) async {
    const allKey = '__all__';
    if (!force) {
      final cached = _movieCache[allKey];
      if (cached != null && cached.isNotEmpty) {
        onPartial?.call(cached);
        return cached;
      }
      final inflight = _movieAllResolveInFlight;
      if (inflight != null) {
        if (onPartial != null) {
          _movieAllPartialListeners.add(onPartial);
          final cur = _movieCache[allKey];
          if (cur != null && cur.isNotEmpty) onPartial(cur);
        }
        try {
          return await inflight;
        } finally {
          _movieAllPartialListeners.remove(onPartial);
        }
      }
    }

    final future = () async {
      if (!force) {
        final disk = await AllCatalogDiskCache.readMovies(_catalogUserKey());
        if (disk != null && disk.isNotEmpty) {
          _movieCache[allKey] = disk;
          _scheduleMovieCountIndex();
          _notifyMovieAllPartial(disk);
          // حدّث في الخلفية دون حجب الواجهة.
          unawaited(_refreshFullMovieCatalogInBackground());
          return disk;
        }
      }

      _movieCache.remove(allKey);
      var base = await _fetchFullMovieCatalogByCategories();
      if (base.isEmpty) {
        // احتياطي نادر: طلب الكتالوج الكامل دفعة واحدة.
        base = await api.getMovieChannels(null);
      }
      if (base.isNotEmpty) {
        _movieCache[allKey] = base;
        _notifyMovieAllPartial(base);
        unawaited(_persistMoviesAllIfChanged(base));
      }
      return base;
    }();

    if (!force) {
      _movieAllResolveInFlight = future;
    }
    if (onPartial != null) {
      _movieAllPartialListeners.add(onPartial);
    }
    try {
      return await future;
    } finally {
      if (onPartial != null) {
        _movieAllPartialListeners.remove(onPartial);
      }
      if (identical(_movieAllResolveInFlight, future)) {
        _movieAllResolveInFlight = null;
        _movieAllPartialListeners.clear();
      }
    }
  }

  void _notifyMovieAllPartial(List<ChannelMovie> partial) {
    if (partial.isEmpty) return;
    _movieCache[kRecentlyAddedCategoryId] = _sliceRecentlyAddedMovies(partial);
    for (final listener in List<void Function(List<ChannelMovie>)>.from(
      _movieAllPartialListeners,
    )) {
      listener(partial);
    }
  }

  /// نفس مسار الفئات العادية (~1ث) بالتوازي — بدون فرز newest.
  /// الدمج حسب ترتيب قائمة الفئات (ليس حسب تاريخ الإضافة).
  Future<List<ChannelMovie>> _fetchFullMovieCatalogByCategories() async {
    final cats = await api.getCategories('get_vod_categories');
    var ids =
        cats
            .map((c) => c.categoryId?.trim() ?? '')
            .where((id) => id.isNotEmpty && id.toLowerCase() != 'null')
            .toList();
    if (ids.isEmpty) {
      ids =
          _movieCache.keys
              .where(
                (k) =>
                    k.isNotEmpty &&
                    !k.startsWith('__') &&
                    k.toLowerCase() != 'null',
              )
              .toList();
    }
    if (ids.isEmpty) return const [];

    final slots = List<List<ChannelMovie>?>.filled(ids.length, null);
    var nextIndex = 0;
    var lastEmitCount = 0;
    final concurrency = AppPerf.instance.catalogFetchConcurrency;
    const emitEvery = 80;

    List<ChannelMovie> mergeInCategoryOrder({required int upToExclusive}) {
      final out = <ChannelMovie>[];
      final seen = <String>{};
      final end = upToExclusive.clamp(0, ids.length);
      for (var i = 0; i < end; i++) {
        final list = slots[i];
        if (list == null || list.isEmpty) continue;
        for (final m in list) {
          final sid = (m.streamId ?? '').trim();
          final key =
              (sid.isNotEmpty && sid.toLowerCase() != 'null')
                  ? sid
                  : 'n:${m.name ?? ''}|${m.num ?? ''}|${out.length}';
          if (!seen.add(key)) continue;
          out.add(m);
        }
      }
      return out;
    }

    void emitPartial({bool force = false}) {
      // اعرض البادئة المتصلة فقط (فئة 0 ثم 1…) حتى لا يبدو الترتيب كـ newest عشوائي.
      var contiguous = 0;
      while (contiguous < ids.length && slots[contiguous] != null) {
        contiguous++;
      }
      if (contiguous == 0) return;
      final list = mergeInCategoryOrder(upToExclusive: contiguous);
      if (list.isEmpty) return;
      if (!force &&
          lastEmitCount > 0 &&
          list.length - lastEmitCount < emitEvery) {
        return;
      }
      lastEmitCount = list.length;
      _movieCache['__all__'] = list;
      _notifyMovieAllPartial(list);
    }

    Future<void> worker() async {
      while (true) {
        final idx = nextIndex++;
        if (idx >= ids.length) return;
        final id = ids[idx];
        List<ChannelMovie> list;
        final cached = _movieCache[id];
        if (cached != null) {
          list = cached;
        } else {
          try {
            list = await api.getMovieChannels(id);
          } catch (_) {
            list = const [];
          }
          if (list.isNotEmpty) {
            _movieCache[id] = list;
            _noteMovieCount(id, list.length);
          }
        }
        slots[idx] = list;
        emitPartial(force: lastEmitCount == 0);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    final full = mergeInCategoryOrder(upToExclusive: ids.length);
    if (full.isNotEmpty) {
      lastEmitCount = full.length;
      _movieCache['__all__'] = full;
      _scheduleMovieCountIndex();
      _notifyMovieAllPartial(full);
    }
    return full;
  }

  Future<void> _refreshFullMovieCatalogInBackground() async {
    try {
      var base = await _fetchFullMovieCatalogByCategories();
      if (base.isEmpty) {
        base = await api.getMovieChannels(null);
      }
      if (base.isEmpty) return;
      final userKey = _catalogUserKey();
      final fp = CatalogFingerprint.movies(base);
      final prev = await CatalogDiskCache.getFingerprint(userKey, 'movies_all');
      final mem = _movieCache['__all__'];
      final memFp =
          mem != null && mem.isNotEmpty ? CatalogFingerprint.movies(mem) : null;
      if (prev == fp && memFp == fp) return;
      _movieCache['__all__'] = base;
      _scheduleMovieCountIndex();
      await _persistMoviesAllIfChanged(base);
    } catch (_) { /* ignore */ }
  }

  /// كتالوج المسلسلات الكامل: ذاكرة → قرص → فئات متوازية → احتياطي.
  Future<List<ChannelSerie>> _resolveFullSeriesCatalog({
    bool force = false,
    void Function(List<ChannelSerie> partial)? onPartial,
  }) async {
    const allKey = '__all__';
    if (!force) {
      final cached = _seriesCache[allKey];
      if (cached != null && cached.isNotEmpty) {
        onPartial?.call(cached);
        return cached;
      }
      final inflight = _seriesAllResolveInFlight;
      if (inflight != null) {
        if (onPartial != null) {
          _seriesAllPartialListeners.add(onPartial);
          final cur = _seriesCache[allKey];
          if (cur != null && cur.isNotEmpty) onPartial(cur);
        }
        try {
          return await inflight;
        } finally {
          _seriesAllPartialListeners.remove(onPartial);
        }
      }
    }

    final future = () async {
      if (!force) {
        final disk = await AllCatalogDiskCache.readSeries(_catalogUserKey());
        if (disk != null && disk.isNotEmpty) {
          _seriesCache[allKey] = disk;
          _scheduleSeriesCountIndex();
          _notifySeriesAllPartial(disk);
          unawaited(_refreshFullSeriesCatalogInBackground());
          return disk;
        }
      }

      _seriesCache.remove(allKey);
      var base = await _fetchFullSeriesCatalogByCategories();
      if (base.isEmpty) {
        base = await api.getSeriesChannels(null);
      }
      if (base.isNotEmpty) {
        _seriesCache[allKey] = base;
        _notifySeriesAllPartial(base);
        unawaited(_persistSeriesAllIfChanged(base));
      }
      return base;
    }();

    if (!force) {
      _seriesAllResolveInFlight = future;
    }
    if (onPartial != null) {
      _seriesAllPartialListeners.add(onPartial);
    }
    try {
      return await future;
    } finally {
      if (onPartial != null) {
        _seriesAllPartialListeners.remove(onPartial);
      }
      if (identical(_seriesAllResolveInFlight, future)) {
        _seriesAllResolveInFlight = null;
        _seriesAllPartialListeners.clear();
      }
    }
  }

  void _notifySeriesAllPartial(List<ChannelSerie> partial) {
    if (partial.isEmpty) return;
    _seriesCache[kRecentlyAddedCategoryId] = _sliceRecentlyAddedSeries(partial);
    for (final listener in List<void Function(List<ChannelSerie>)>.from(
      _seriesAllPartialListeners,
    )) {
      listener(partial);
    }
  }

  Future<List<ChannelSerie>> _fetchFullSeriesCatalogByCategories() async {
    final cats = await api.getCategories('get_series_categories');
    var ids =
        cats
            .map((c) => c.categoryId?.trim() ?? '')
            .where((id) => id.isNotEmpty && id.toLowerCase() != 'null')
            .toList();
    // إن فشل جلب الفئات: استخدم ما هو مُحمّل مسبقاً في الذاكرة.
    if (ids.isEmpty) {
      ids =
          _seriesCache.keys
              .where(
                (k) =>
                    k.isNotEmpty &&
                    !k.startsWith('__') &&
                    k.toLowerCase() != 'null',
              )
              .toList();
    }
    if (ids.isEmpty) return const [];

    final slots = List<List<ChannelSerie>?>.filled(ids.length, null);
    var nextIndex = 0;
    var lastEmitCount = 0;
    final concurrency = AppPerf.instance.catalogFetchConcurrency;
    const emitEvery = 80;

    List<ChannelSerie> mergeInCategoryOrder({required int upToExclusive}) {
      final out = <ChannelSerie>[];
      final seen = <String>{};
      final end = upToExclusive.clamp(0, ids.length);
      for (var i = 0; i < end; i++) {
        final list = slots[i];
        if (list == null || list.isEmpty) continue;
        for (final s in list) {
          final sid = (s.seriesId ?? '').trim();
          final key =
              (sid.isNotEmpty && sid.toLowerCase() != 'null')
                  ? sid
                  : 'n:${s.name ?? ''}|${s.num ?? ''}|${out.length}';
          if (!seen.add(key)) continue;
          out.add(s);
        }
      }
      return out;
    }

    void emitPartial({bool force = false}) {
      var contiguous = 0;
      while (contiguous < ids.length && slots[contiguous] != null) {
        contiguous++;
      }
      if (contiguous == 0) return;
      final list = mergeInCategoryOrder(upToExclusive: contiguous);
      if (list.isEmpty) return;
      if (!force &&
          lastEmitCount > 0 &&
          list.length - lastEmitCount < emitEvery) {
        return;
      }
      lastEmitCount = list.length;
      _seriesCache['__all__'] = list;
      _notifySeriesAllPartial(list);
    }

    Future<void> worker() async {
      while (true) {
        final idx = nextIndex++;
        if (idx >= ids.length) return;
        final id = ids[idx];
        List<ChannelSerie> list;
        final cached = _seriesCache[id];
        if (cached != null) {
          list = cached;
        } else {
          try {
            list = await api.getSeriesChannels(id);
          } catch (_) {
            list = const [];
          }
          if (list.isNotEmpty) {
            _seriesCache[id] = list;
            _noteSeriesCount(id, list.length);
          }
        }
        slots[idx] = list;
        emitPartial(force: lastEmitCount == 0);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    final full = mergeInCategoryOrder(upToExclusive: ids.length);
    if (full.isNotEmpty) {
      lastEmitCount = full.length;
      _seriesCache['__all__'] = full;
      _scheduleSeriesCountIndex();
      _notifySeriesAllPartial(full);
    }
    return full;
  }

  Future<void> _refreshFullSeriesCatalogInBackground() async {
    try {
      var base = await _fetchFullSeriesCatalogByCategories();
      if (base.isEmpty) {
        base = await api.getSeriesChannels(null);
      }
      if (base.isEmpty) return;
      final userKey = _catalogUserKey();
      final fp = CatalogFingerprint.series(base);
      final prev = await CatalogDiskCache.getFingerprint(userKey, 'series_all');
      final mem = _seriesCache['__all__'];
      final memFp =
          mem != null && mem.isNotEmpty ? CatalogFingerprint.series(mem) : null;
      if (prev == fp && memFp == fp) return;
      _seriesCache['__all__'] = base;
      _scheduleSeriesCountIndex();
      await _persistSeriesAllIfChanged(base);
    } catch (_) { /* ignore */ }
  }

  @override
  Future<void> close() {
    _movieCountIndexTimer?.cancel();
    _seriesCountIndexTimer?.cancel();
    _countPingTimer?.cancel();
    _countPersistTimer?.cancel();
    _movieCountIndexGen++;
    _seriesCountIndexGen++;
    return super.close();
  }
}
