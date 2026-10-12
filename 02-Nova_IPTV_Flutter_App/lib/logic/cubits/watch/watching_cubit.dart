import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mehdi_iptv/core/runtime_seal.dart';

import '../../../repository/api/api.dart';
import '../../../repository/models/watching.dart';

part 'watching_state.dart';

class WatchingCubit extends Cubit<WatchingState> {
  final WatchingLocale favoriteLocale;

  static const int _kMaxWatchHistory = 150;

  /// أقل من هذا يُعد موضعاً تافهاً (رجوع من حوار الاستكمال دون مشاهدة).
  static const double _kMinMeaningfulProgressSec = 15;

  WatchingCubit(this.favoriteLocale) : super(WatchingState.defaultData()) {
    unawaited(initialData());
  }

  void reset() {
    emit(WatchingState.defaultData());
  }

  Future<void> initialData() async {
    RuntimeSeal.touchQuiet();
    final movies = await favoriteLocale.getWatchingMovies();
    final seriesRaw = await favoriteLocale.getWatchingSeries();
    final series = _dedupeSeriesKeepLatest(seriesRaw);
    if (series.length != seriesRaw.length) {
      unawaited(favoriteLocale.saveWatchSerie(series));
    }
    emit(
      WatchingState(
        movies: movies,
        series: series,
        live: await favoriteLocale.getWatchingLives(),
      ),
    );
  }

  WatchingModel? _findByStreamId(List<WatchingModel> list, String streamId) {
    final id = streamId.trim();
    if (id.isEmpty) return null;
    for (final item in list) {
      if (item.streamId.trim() == id) return item;
    }
    return null;
  }

  /// حلقة واحدة لكل مسلسل — الأحدث أولاً (بداية القائمة).
  List<WatchingModel> _dedupeSeriesKeepLatest(List<WatchingModel> list) {
    final seenSeries = <String>{};
    final out = <WatchingModel>[];
    for (final item in list) {
      final sid = (item.seriesId ?? '').trim();
      if (sid.isEmpty) {
        out.add(item);
        continue;
      }
      if (seenSeries.contains(sid)) continue;
      seenSeries.add(sid);
      out.add(item);
    }
    return out;
  }

  /// يدمج الحفظ الجديد مع السابق دون مسح تقدّم ذي معنى بموضع شبه صفري.
  WatchingModel? _mergeWatchEntry({
    required WatchingModel incoming,
    required WatchingModel? existing,
  }) {
    if (existing == null) {
      if (incoming.sliderValue < _kMinMeaningfulProgressSec) return null;
      return incoming;
    }

    // رجوع أثناء حوار الاستكمال أو خروج فوري من البداية: أبقِ التقدّم السابق.
    if (incoming.sliderValue < _kMinMeaningfulProgressSec &&
        existing.sliderValue >= _kMinMeaningfulProgressSec) {
      return null;
    }

    final duration = incoming.durationStrm > 0
        ? incoming.durationStrm
        : existing.durationStrm;

    return WatchingModel(
      streamId: incoming.streamId,
      image: incoming.image.trim().isNotEmpty ? incoming.image : existing.image,
      title: incoming.title.trim().isNotEmpty ? incoming.title : existing.title,
      stream: incoming.stream.trim().isNotEmpty
          ? incoming.stream
          : existing.stream,
      sliderValue: incoming.sliderValue,
      durationStrm: duration,
      seriesId: incoming.seriesId ?? existing.seriesId,
      seriesName: incoming.seriesName ?? existing.seriesName,
      seriesCover: incoming.seriesCover ?? existing.seriesCover,
      rating: (incoming.rating ?? '').trim().isNotEmpty
          ? incoming.rating
          : existing.rating,
      rating5based: (incoming.rating5based ?? '').trim().isNotEmpty
          ? incoming.rating5based
          : existing.rating5based,
      categoryId: (incoming.categoryId ?? '').trim().isNotEmpty
          ? incoming.categoryId
          : existing.categoryId,
    );
  }

  void addMovie(WatchingModel movie) async {
    final existing = _findByStreamId(state.movies, movie.streamId);
    final toSave = _mergeWatchEntry(incoming: movie, existing: existing);
    if (toSave == null) return;

    List<WatchingModel> editList = state.movies
        .where((element) => element.streamId.trim() != toSave.streamId.trim())
        .toList();
    editList.insert(0, toSave);
    if (editList.length > _kMaxWatchHistory) {
      editList = editList.sublist(0, _kMaxWatchHistory);
    }
    emit(
      WatchingState(movies: editList, series: state.series, live: state.live),
    );
    await favoriteLocale.saveWatchingMovie(editList);
  }

  void addSerie(WatchingModel serie) async {
    final seriesId = (serie.seriesId ?? '').trim();
    // نفس المسلسل: ابحث عن أي حلقة سابقة لدمج التقدّم إن لزم.
    WatchingModel? existing = _findByStreamId(state.series, serie.streamId);
    if (existing == null && seriesId.isNotEmpty) {
      for (final item in state.series) {
        if ((item.seriesId ?? '').trim() == seriesId) {
          existing = item;
          break;
        }
      }
    }

    final toSave = _mergeWatchEntry(incoming: serie, existing: existing);
    if (toSave == null) return;

    // أزل كل حلقات نفس المسلسل — تبقى الحلقة الأخيرة فقط.
    List<WatchingModel> editList = state.series.where((element) {
      if (element.streamId.trim() == toSave.streamId.trim()) return false;
      final sid = (element.seriesId ?? '').trim();
      if (seriesId.isNotEmpty && sid == seriesId) return false;
      return true;
    }).toList();
    editList.insert(0, toSave);
    if (editList.length > _kMaxWatchHistory) {
      editList = editList.sublist(0, _kMaxWatchHistory);
    }
    emit(
      WatchingState(movies: state.movies, series: editList, live: state.live),
    );
    await favoriteLocale.saveWatchSerie(editList);
  }

  void addLive(WatchingModel live) async {
    List<WatchingModel> editList = state.live
        .where((element) => element.streamId != live.streamId)
        .toList();
    editList.insert(0, live);
    if (editList.length > _kMaxWatchHistory) {
      editList = editList.sublist(0, _kMaxWatchHistory);
    }
    await favoriteLocale.saveWatchLive(editList);
    emit(
      WatchingState(movies: state.movies, series: state.series, live: editList),
    );
  }
}
