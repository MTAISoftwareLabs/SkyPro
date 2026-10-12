import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../logic/blocs/categories/channels/channels_bloc.dart';
import '../logic/blocs/categories/live_caty/live_caty_bloc.dart';
import '../logic/blocs/categories/movie_caty/movie_caty_bloc.dart';
import '../logic/blocs/categories/series_caty/series_caty_bloc.dart';
import '../repository/api/api.dart';
import '../repository/locale/catalog_disk_cache.dart';
import '../repository/locale/catalog_fingerprint.dart';
import '../repository/models/category.dart';
import '../services/parental_control_service.dart';

/// مزامنة خلفية: يجلب من السيرفر ويحدّث فقط ما تغيّرت بصمته.
class CatalogSyncService {
  CatalogSyncService._();
  static final CatalogSyncService instance = CatalogSyncService._();

  static const int _liveConcurrency = 2;
  static const Duration _gap = Duration(milliseconds: 320);

  int _generation = 0;
  bool _running = false;

  bool get isRunning => _running;

  void reset() {
    _generation++;
    _running = false;
  }

  Future<void> syncInBackground({
    required IpTvApi api,
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
    required MovieCatyBloc movieCaty,
    required SeriesCatyBloc seriesCaty,
  }) async {
    if (_running) return;
    _running = true;
    final gen = _generation;
    try {
      await _syncCategories(
        api: api,
        liveCaty: liveCaty,
        movieCaty: movieCaty,
        seriesCaty: seriesCaty,
        userKey: channels.catalogUserKey,
        gen: gen,
      );
      if (gen != _generation) return;

      await _syncLiveChannels(
        api: api,
        channels: channels,
        liveCaty: liveCaty,
        userKey: channels.catalogUserKey,
        gen: gen,
      );
      if (gen != _generation) return;

      // All أفلام/مسلسلات: يحدّث في الخلفية ويتخطّى الكتابة إن لم تتغيّر البصمة.
      unawaited(channels.ensureFullMovieCatalog());
      unawaited(channels.ensureFullSeriesCatalog());
    } catch (e) {
      if (kDebugMode) debugPrint('CatalogSyncService: $e');
    } finally {
      if (gen == _generation) _running = false;
    }
  }

  Future<void> _syncCategories({
    required IpTvApi api,
    required LiveCatyBloc liveCaty,
    required MovieCatyBloc movieCaty,
    required SeriesCatyBloc seriesCaty,
    required String userKey,
    required int gen,
  }) async {
    if (userKey.isEmpty) return;

    Future<void> one({
      required String action,
      required String kind,
      required void Function(List<CategoryModel>) apply,
    }) async {
      if (gen != _generation) return;
      try {
        var result = await api.getCategories(action);
        if (result.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          result = await api.getCategories(action);
        }
        if (result.isEmpty) return;
        final fp = CatalogFingerprint.categories(result);
        final prev = await CatalogDiskCache.getFingerprint(
          userKey,
          '${kind}_cats',
        );
        if (prev == fp) return;
        apply(result);
        await CatalogDiskCache.writeCategories(userKey, kind, result);
      } catch (e) {
        if (kDebugMode) debugPrint('CatalogSyncService.cats($kind): $e');
      }
    }

    await one(
      action: 'get_live_categories',
      kind: CatalogDiskCache.kindLive,
      apply: (list) => liveCaty.add(HydrateLiveCategories(list)),
    );
    if (gen != _generation) return;
    await one(
      action: 'get_vod_categories',
      kind: CatalogDiskCache.kindMovies,
      apply: (list) => movieCaty.add(HydrateMovieCategories(list)),
    );
    if (gen != _generation) return;
    await one(
      action: 'get_series_categories',
      kind: CatalogDiskCache.kindSeries,
      apply: (list) => seriesCaty.add(HydrateSeriesCategories(list)),
    );
  }

  Future<void> _syncLiveChannels({
    required IpTvApi api,
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
    required String userKey,
    required int gen,
  }) async {
    if (userKey.isEmpty) return;
    final ids = _liveCategoryIds(liveCaty);
    if (ids.isEmpty) return;

    final fps = await CatalogDiskCache.readFingerprints(userKey);
    final serverIds = ids.toSet();

    // احذف فئات لم تعد على السيرفر.
    for (final key in fps.keys.toList()) {
      if (!key.startsWith('live:')) continue;
      final catId = key.substring(5);
      if (serverIds.contains(catId)) continue;
      channels.evictLiveCategory(catId);
      await CatalogDiskCache.removeLiveCategory(userKey, catId);
    }

    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (gen != _generation) return;
        final i = next++;
        if (i >= ids.length) return;
        final id = ids[i];
        await _syncOneLiveCategory(
          api: api,
          channels: channels,
          userKey: userKey,
          catId: id,
          knownFp: fps['live:$id'],
        );
        await SchedulerBinding.instance.endOfFrame;
        await Future<void>.delayed(_gap);
      }
    }

    await Future.wait(
      List.generate(_liveConcurrency, (_) => worker()),
    );
  }

  Future<void> _syncOneLiveCategory({
    required IpTvApi api,
    required ChannelsBloc channels,
    required String userKey,
    required String catId,
    required String? knownFp,
  }) async {
    try {
      final remote = await api.getLiveChannels(catId);
      if (remote.isEmpty) return;
      final fp = CatalogFingerprint.lives(remote);
      final mem = channels.liveListForCategoryId(catId);
      final memFp =
          mem != null && mem.isNotEmpty ? CatalogFingerprint.lives(mem) : null;
      if (knownFp == fp && memFp == fp) {
        // متطابق مع القرص والذاكرة — لا شيء.
        return;
      }
      if (memFp == fp) {
        // الذاكرة حديثة؛ حدّث القرص فقط إن لزم.
        if (knownFp != fp) {
          await CatalogDiskCache.writeLiveCategory(userKey, catId, remote);
        }
        return;
      }
      channels.seedLiveCategory(catId, remote);
      await CatalogDiskCache.writeLiveCategory(userKey, catId, remote);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CatalogSyncService.live($catId): $e');
      }
    }
  }

  List<String> _liveCategoryIds(LiveCatyBloc liveCaty) {
    final state = liveCaty.state;
    if (state is! LiveCatySuccess) return const [];
    final cats = ParentalControlService.instance.filterAdultCategories(
      List<CategoryModel>.from(state.categories),
    );
    final ids = <String>[];
    for (final c in cats) {
      final id = (c.categoryId ?? '').trim();
      if (id.isEmpty) continue;
      ids.add(id);
    }
    return ids;
  }
}
