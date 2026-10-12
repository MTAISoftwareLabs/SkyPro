import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../logic/blocs/categories/channels/channels_bloc.dart';
import '../logic/blocs/categories/live_caty/live_caty_bloc.dart';
import '../repository/models/category.dart';
import '../services/parental_control_service.dart';

class LiveCatalogWarmService {
  LiveCatalogWarmService._();
  static final LiveCatalogWarmService instance = LiveCatalogWarmService._();

  /// كنت كنسخّن غير أول 11 فئة عند الإقلاع (باش التطبيق ما يبطأش فالبداية)،
  /// والفئات الباقية كانت كتسخّن بهدوء وحدة وحدة (tail) بفارق زمني بينهم،
  /// وهو اللي كان كيبان أنه أبطأ فالفئات التحتانية. دابا كل الفئات كتدخل
  /// فمرحلة "priority" بحال بحال (تسخين متوازي)، ولو خدا الوقت أكتر شوية
  /// عند الإقلاع، لي المهم أن كل الفئات تولي جاهزة فالكاش بسرعة متقاربة.
  static const int priorityCategoryCount = 1 << 30;

  /// توازي أقل أثناء التدفئة الاحتياطية (إن فشل الفهرس الكامل).
  static const int _bootstrapConcurrency = 2;

  static const Duration _tailGap = Duration(milliseconds: 480);
  static const Duration _retryGap = Duration(milliseconds: 350);
  static const Duration _fetchTimeout = Duration(seconds: 18);

  int _generation = 0;
  bool _priorityDone = false;
  bool _tailRunning = false;
  bool _allDone = false;
  bool _userPaused = false;

  bool get isRunning =>
      !_userPaused && (_tailRunning || (!_priorityDone && !_allDone));
  bool get hasCompletedOnce => _allDone;
  bool get hasPriorityDone => _priorityDone;
  bool get isUserPaused => _userPaused;

  void reset() {
    _generation++;
    _priorityDone = false;
    _tailRunning = false;
    _allDone = false;
    _userPaused = false;
  }

  /// أوقف التدفئة فوراً حتى لا تنافس جلب فئة اختارها المستخدم.
  void pauseForUserFetch() {
    if (_userPaused) {
      _generation++;
      return;
    }
    _userPaused = true;
    _generation++;
  }

  /// استأنف التدفئة الهادئة بعد جلب فئة المستخدم.
  void resumeAfterUserFetch({
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
  }) {
    if (!_userPaused) return;
    _userPaused = false;
    if (_allDone && channels.isFullLiveIndexReady) return;
    ensureStarted(channels: channels, liveCaty: liveCaty);
  }

  Future<void> warmPriorityDuringBootstrap({
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
  }) async {
    if (_allDone || _userPaused) return;
    final gen = _generation;

    try {
      // فهرس كامل مرة واحدة → كل الفئات جاهزة محلياً.
      final indexed = await channels.ensureFullLiveIndex();
      if (gen != _generation || _userPaused) return;
      if (indexed) {
        _priorityDone = true;
        _allDone = true;
        return;
      }

      final ids = await _waitForCategoryIds(liveCaty, gen);
      if (gen != _generation || _userPaused) return;
      if (ids.isEmpty) return;

      final priority = ids.take(priorityCategoryCount).toList(growable: false);
      await _warmBatch(
        channels,
        priority,
        gen,
        concurrency: _bootstrapConcurrency,
      );

      if (gen == _generation && !_userPaused) {
        final missing = [
          for (final id in priority)
            if (!channels.hasLiveCategoryCached(id)) id,
        ];
        for (final id in missing) {
          if (gen != _generation || _userPaused) return;
          await _warmOne(channels, id);
          await _yieldUi();
          await Future<void>.delayed(_retryGap);
        }
      }

      if (gen == _generation && !_userPaused) _priorityDone = true;
    } catch (e) {
      if (gen == _generation && !_userPaused) {
        final ids = _categoryIds(liveCaty);
        final priority = ids.take(priorityCategoryCount);
        final allCached = priority.isNotEmpty &&
            priority.every(channels.hasLiveCategoryCached);
        _priorityDone = allCached;
      }
    }
  }

  /// بعد اختفاء شاشة التحميل: يكمل بقية الفئات بهدوء إن لزم.
  Future<void> continueTailInBackground({
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
  }) async {
    if (_allDone || _tailRunning || _userPaused) return;
    _tailRunning = true;
    final gen = _generation;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (gen != _generation || _userPaused) return;

      if (!_priorityDone) {
        await warmPriorityDuringBootstrap(
          channels: channels,
          liveCaty: liveCaty,
        );
        if (gen != _generation || _userPaused) return;
      }

      if (channels.isFullLiveIndexReady) {
        _allDone = true;
        return;
      }

      final ids = _categoryIds(liveCaty);
      if (ids.isEmpty) return;

      for (final id in ids) {
        if (gen != _generation || _userPaused) return;
        if (channels.hasLiveCategoryCached(id)) continue;
        await _warmOne(channels, id);
        await _yieldUi();
        await Future<void>.delayed(_tailGap);
      }

      if (gen == _generation && !_userPaused) {
        final remaining =
            ids.where((id) => !channels.hasLiveCategoryCached(id));
        _allDone = remaining.isEmpty;
        if (!_allDone && kDebugMode) {
        }
      }
    } catch (e) { /* ignore */ } finally {
      if (gen == _generation) _tailRunning = false;
    }
  }

  /// إن دخل المستخدم Live قبل اكتمال التدفئة — يبدأ الفهرس الكامل / الذيل.
  void ensureStarted({
    required ChannelsBloc channels,
    required LiveCatyBloc liveCaty,
  }) {
    if (_userPaused) return;

    if (_allDone) {
      if (channels.isFullLiveIndexReady) return;
      final ids = _categoryIds(liveCaty);
      final hasMissing = ids.any((id) => !channels.hasLiveCategoryCached(id));
      if (!hasMissing) return;
      _allDone = false;
      _priorityDone = false;
    }

    if (channels.isFullLiveIndexReady) {
      _priorityDone = true;
      _allDone = true;
      return;
    }

    final priorityIds =
        _categoryIds(liveCaty).take(priorityCategoryCount).toList();
    final priorityMissing = priorityIds.any(
      (id) => !channels.hasLiveCategoryCached(id),
    );
    if (priorityMissing) {
      _priorityDone = false;
    }

    if (!_priorityDone) {
      unawaited(() async {
        await warmPriorityDuringBootstrap(
          channels: channels,
          liveCaty: liveCaty,
        );
        await continueTailInBackground(channels: channels, liveCaty: liveCaty);
      }());
      return;
    }
    unawaited(continueTailInBackground(channels: channels, liveCaty: liveCaty));
  }

  Future<void> _warmBatch(
    ChannelsBloc channels,
    List<String> ids,
    int gen, {
    required int concurrency,
  }) async {
    for (var i = 0; i < ids.length; i += concurrency) {
      if (gen != _generation || _userPaused) return;
      final batch = ids.skip(i).take(concurrency).toList();
      await Future.wait([for (final id in batch) _warmOne(channels, id)]);
      await _yieldUi();
      if (i + concurrency < ids.length) {
        await Future<void>.delayed(_retryGap);
      }
    }
  }

  Future<void> _warmOne(ChannelsBloc channels, String id) async {
    if (id.isEmpty || channels.hasLiveCategoryCached(id)) return;
    try {
      await channels.ensureLiveCategoryCached(id).timeout(_fetchTimeout);
    } catch (_) { /* ignore */ }
  }

  Future<List<String>> _waitForCategoryIds(LiveCatyBloc liveCaty, int gen) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      if (gen != _generation) return const [];
      final ids = _categoryIds(liveCaty);
      if (ids.isNotEmpty) return ids;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return _categoryIds(liveCaty);
  }

  List<String> _categoryIds(LiveCatyBloc liveCaty) {
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

  Future<void> _yieldUi() async {
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
  }
}
