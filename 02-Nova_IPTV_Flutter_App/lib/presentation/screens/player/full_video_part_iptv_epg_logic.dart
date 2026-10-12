part of '../screens.dart';

extension _FullVideoIptvEpgLogic on _FullVideoScreenState {
  // ---------------------------------------------------------------------------

  Future<void> _loadLiveEpg() async {
    final myGeneration = ++_epgLoadGeneration;
    try {
      final streamId = (_currentLiveChannel ?? widget.channelLive)?.streamId
          ?.toString();
      if (streamId == null || streamId.isEmpty) return;

      List<EpgProgram> programs = EpgRefreshService.cachedListingsFor(streamId)
          .map(_epgModelToProgram)
          .whereType<EpgProgram>()
          .toList();

      if (programs.isEmpty) {
        final authState = context.read<AuthBloc>().state;
        if (authState is! AuthSuccess) return;

        final user = authState.user;
        final baseUrl = user.serverInfo?.url ?? user.serverInfo?.serverUrl;
        final username = user.userInfo?.username;
        final password = user.userInfo?.password;

        if (baseUrl == null || username == null || password == null) {
          return;
        }

        final service = XtreamEpgService(_epgDio);
        programs = await service.getShortEpg(
          baseUrl: baseUrl,
          username: username,
          password: password,
          streamId: streamId,
          limit: 10,
        );
        if (programs.isNotEmpty) {
          EpgRefreshService.putCachedListings(
            streamId,
            programs
                .map(
                  (p) => EpgModel(
                    title: p.title,
                    startTimestamp:
                        (p.start.toUtc().millisecondsSinceEpoch ~/ 1000)
                            .toString(),
                    stopTimestamp:
                        (p.end.toUtc().millisecondsSinceEpoch ~/ 1000)
                            .toString(),
                  ),
                )
                .toList(),
          );
        }
      }

      if (!mounted || myGeneration != _epgLoadGeneration) {
        return;
      }

      if (programs.isEmpty) {
        _fvSetState(() {
          _currentProgram = null;
          _nextProgram = null;
        });
        return;
      }

      final now = DateTime.now();

      EpgProgram? current = programs.firstWhereOrNull(
        (p) =>
            (now.isAtSameMomentAs(p.start) || now.isAfter(p.start)) &&
            now.isBefore(p.end),
      );

      current ??= programs.firstWhereOrNull((p) => now.isBefore(p.start));
      current ??= programs.isNotEmpty ? programs.last : null;

      EpgProgram? next;
      if (current != null) {
        final idx = programs.indexOf(current);
        if (idx >= 0 && idx + 1 < programs.length) {
          next = programs[idx + 1];
        } else {
          for (final p in programs) {
            if (p.start.isAfter(current.start)) {
              next = p;
              break;
            }
          }
        }
      }

      if (!mounted || myGeneration != _epgLoadGeneration) return;
      _fvSetState(() {
        _currentProgram = current;
        _nextProgram = next;
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // cancelled
      }
    } catch (_) {}
  }

  EpgProgram? _epgModelToProgram(EpgModel m) {
    final start = XtreamEpgService.parseXtreamDatePublic(
      m.startTimestamp ?? m.start,
    );
    final end = XtreamEpgService.parseXtreamDatePublic(
      m.stopTimestamp ?? m.end,
    );
    if (start == null || end == null) return null;
    final title = XtreamEpgService.decodeEpgTitlePublic(m.title ?? '');
    return EpgProgram(title: title, start: start, end: end);
  }

  String _buildLiveStreamLink(ChannelLive ch, UserModel user) {
    if (ch.streamId != null &&
        (ch.streamId!.startsWith('http://') ||
            ch.streamId!.startsWith('https://'))) {
      return ch.streamId!;
    }
    final serverUrl = user.serverInfo?.serverUrl ?? '';
    final username = user.userInfo?.username ?? '';
    final password = user.userInfo?.password ?? '';
    final streamId = ch.streamId ?? '';
    if (serverUrl.isEmpty || streamId.isEmpty) return '';
    // VLC: الصيغة القصيرة تفتح فوراً. Exo: /live/ مع امتداد.
    if (!_useExo) {
      return buildXtreamLiveStreamUrlShort(
        serverUrl: serverUrl,
        username: username,
        password: password,
        streamId: streamId,
      );
    }
    return buildXtreamLiveStreamUrl(
      serverUrl: serverUrl,
      username: username,
      password: password,
      streamId: streamId,
    );
  }

  Future<void> _applyPlaybackVolumeForIptvOverlay({
    required bool ducked,
  }) async {
    try {
      if (_useExo) {
        await _exoController?.setVolume(ducked ? 0.3 : 1.0);
      } else {
        final vc = _videoPlayerController;
        if (vc != null && vc.value.isInitialized) {
          await vc.setVolume(ducked ? 30 : 100);
        }
      }
    } catch (_) {}
  }

  /// IPTV side panel: no idle auto-close Ã¢â‚¬â€ user dismisses manually (back, right
  /// on channels, tap dimmed area, OK on channel, etc.).
  void _touchLiveIptvOverlayActivity() {
    if (!_showLiveIptvOverlay) return;
    _iptvOverlayIdleTimer?.cancel();
    _iptvOverlayIdleTimer = null;
  }

  void _prefetchLiveIptvPanelData({bool preferSilentCache = false}) {
    if (!widget.isLive || !mounted) return;
    final liveCaty = context.read<LiveCatyBloc>();
    final s = liveCaty.state;
    if (s is! LiveCatySuccess && s is! LiveCatyLoading) {
      liveCaty.add(GetLiveCategories());
    }
    final channelsBloc = context.read<ChannelsBloc>();
    // ابدأ فهرس كل القنوات فوراً عند دخول Live.
    unawaited(channelsBloc.ensureFullLiveIndex());
    LiveCatalogWarmService.instance.ensureStarted(
      channels: channelsBloc,
      liveCaty: liveCaty,
    );
    final catId =
        _iptvActiveCategoryId ??
        widget.initialLiveCategoryId ??
        (_currentLiveChannel ?? widget.channelLive)?.categoryId ??
        '';
    if (catId.isEmpty || _iptvIsPinnedLiveCategory(catId)) return;
    if (preferSilentCache &&
        channelsBloc.hasLiveCategoryCached(catId) &&
        (channelsBloc.liveListForCategoryId(catId)?.isNotEmpty ?? false)) {
      return;
    }
    channelsBloc.add(
      GetLiveChannelsEvent(typeCategory: TypeCategory.live, catyId: catId),
    );
  }

  void _disposeIptvItemFocusNodes({bool deferUntilNextFrame = false}) {
    final cats = _iptvCategoryFocusNodes;
    final channels = _iptvChannelFocusNodes;
    _iptvCategoryFocusNodes = [];
    _iptvChannelFocusNodes = [];
    void disposeAll() {
      for (final n in cats) {
        try {
          n.dispose();
        } catch (_) {}
      }
      for (final n in channels) {
        try {
          n.dispose();
        } catch (_) {}
      }
    }

    // لا نُفرّغ FocusNode وهو ما زال مربوطاً بـ Focus في الشجرة — يسبب تعطلاً.
    if (deferUntilNextFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => disposeAll());
    } else {
      disposeAll();
    }
  }

  void _detachIptvFocusSafetyListener() {
    if (_iptvPrimaryFocusListener != null) {
      try {
        FocusManager.instance.removeListener(_iptvPrimaryFocusListener!);
      } catch (_) {}
      _iptvPrimaryFocusListener = null;
    }
    _iptvRestoreFocusTimer?.cancel();
    _iptvRestoreFocusTimer = null;
  }

  /// Ã™Å Ã˜Â¹Ã˜ÂªÃ™â€¦Ã˜Â¯ Ã˜Â¹Ã™â€žÃ™â€° [FocusNode.debugLabel] Ã™â€žÃ˜ÂªÃ™ÂÃ˜Â§Ã˜Â¯Ã™Å  Ã˜Â­Ã™â€žÃ™â€šÃ˜Â§Ã˜Âª Ã˜Â¹Ã™â€žÃ™â€° Ã™Æ’Ã™â€ž Ã˜ÂµÃ™ÂÃ™Ë†Ã™Â Ã˜Â§Ã™â€žÃ™â€šÃ˜Â§Ã˜Â¦Ã™â€¦Ã˜Â© Ã˜Â¹Ã™â€ Ã˜Â¯ Ã™Æ’Ã™â€ž Ã˜ÂªÃ˜ÂºÃ™Å Ã™Å Ã˜Â± Ã˜ÂªÃ˜Â±Ã™Æ’Ã™Å Ã˜Â².
  bool _iptvOverlayPanelHasPrimaryFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    if (identical(focus, _iptvOverlayFocusNode)) return true;
    if (identical(focus, _iptvMiniPlayerFocusNode)) return true;
    if (identical(focus, _iptvCategorySearchNavFocus)) return true;
    if (identical(focus, _iptvCategorySearchEditFocus)) return true;
    if (identical(focus, _iptvCategoriesBackFocusNode)) return true;
    final label = focus.debugLabel;
    if (label != null) {
      if (label == 'iptv_overlay_shell' ||
          label == 'iptv_mini_player') {
        return true;
      }
      if (label == 'iptv_category_search_nav' ||
          label == 'iptv_category_search_edit' ||
          label == 'iptv_categories_back' ||
          label == 'category_search_nav' ||
          label == 'category_search_edit') {
        return true;
      }
      if (label.startsWith('iptv_cat_') || label.startsWith('iptv_ch_')) {
        return true;
      }
    }
    for (final n in _iptvCategoryFocusNodes) {
      if (identical(n, focus)) return true;
    }
    for (final n in _iptvChannelFocusNodes) {
      if (identical(n, focus)) return true;
    }
    return false;
  }

  bool _iptvCategorySearchHasFocus() {
    return _iptvCategorySearchNavFocus.hasFocus ||
        _iptvCategorySearchEditFocus.hasFocus;
  }

  void _attachIptvFocusSafetyListener() {
    _detachIptvFocusSafetyListener();
    _iptvPrimaryFocusListener = () {
      if (!_showLiveIptvOverlay || !mounted) return;
      if (_iptvTvSearchKeyboardOpen) return;
      // أثناء كتابة البحث: لا تسرق التركيز — يغلق الكلافيي على الهاتف.
      if (_iptvCategorySearchHasFocus()) return;
      if (MediaQuery.viewInsetsOf(context).bottom > 40) return;
      // قبل جاهزية عقد الفئات/القنوات: لا تستعدِ التركيز (يتسبب بحلقة/تهنيج).
      if (_iptvCategoryFocusNodes.isEmpty && _iptvChannelFocusNodes.isEmpty) {
        return;
      }
      if (_iptvOverlayPanelHasPrimaryFocus()) return;
      _iptvRestoreFocusTimer?.cancel();
      _iptvRestoreFocusTimer = Timer(const Duration(milliseconds: 90), () {
        if (!mounted || !_showLiveIptvOverlay) return;
        if (_iptvTvSearchKeyboardOpen) return;
        if (_iptvCategorySearchHasFocus()) return;
        if (MediaQuery.viewInsetsOf(context).bottom > 40) return;
        if (_iptvCategoryFocusNodes.isEmpty && _iptvChannelFocusNodes.isEmpty) {
          return;
        }
        if (_iptvOverlayPanelHasPrimaryFocus()) return;
        _iptvRestoreLastOverlayFocus();
      });
    };
    FocusManager.instance.addListener(_iptvPrimaryFocusListener!);
  }

  void _iptvRestoreLastOverlayFocus() {
    if (_iptvTvSearchKeyboardOpen) return;
    if (_iptvCategorySearchHasFocus()) return;
    if (MediaQuery.viewInsetsOf(context).bottom > 40) return;
    // إن كان التركيز فعلاً على فئة — لا تُعدّه لعمود القنوات بسبب العلم القديم.
    if (_iptvCategoryFocusNodes.any((n) => n.hasFocus)) {
      _iptvOverlayFocusOnChannelsColumn = false;
      _iptvOverlayFocusOnMiniPlayer = false;
      return;
    }
    if (_iptvOverlayFocusOnMiniPlayer) {
      _iptvFocusMiniPlayer();
      return;
    }
    if (_iptvOverlayFocusOnChannelsColumn &&
        _iptvChannelFocusNodes.isNotEmpty) {
      final ix = _iptvLastChannelFocusIndex.clamp(
        0,
        _iptvChannelFocusNodes.length - 1,
      );
      _scheduleIptvFocusSafe(_iptvChannelFocusNodes[ix]);
      return;
    }
    if (_iptvCategoryFocusNodes.isNotEmpty) {
      _iptvFocusPreferredCategory();
      return;
    }
    if (_iptvChannelFocusNodes.isNotEmpty) {
      _iptvFocusPreferredChannel();
    }
  }

  bool _iptvNavDebounceAllow() {
    final t = DateTime.now();
    if (_iptvLastNavKeyTime != null &&
        t.difference(_iptvLastNavKeyTime!) < _kIptvNavDebounce) {
      return false;
    }
    _iptvLastNavKeyTime = t;
    return true;
  }

  void _scrollIptvIndexIntoView(
    int index,
    ScrollController controller,
    double rowExtent, {
    bool smooth = false,
  }) {
    if (!controller.hasClients) return;
    final maxE = controller.position.maxScrollExtent;
    final o = (index * rowExtent - rowExtent * 2).clamp(0.0, maxE);
    if (smooth) {
      unawaited(
        controller.animateTo(
          o,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      controller.jumpTo(o);
    }
  }

  /// فئة جديدة أو نتائج بحث: ابدأ القائمة من الأول، لا تُبقِ تمرير الفئة السابقة.
  void _iptvJumpScrollToStart(ScrollController controller) {
    void jump() {
      if (!mounted || !controller.hasClients) return;
      if (controller.offset == 0) return;
      controller.jumpTo(0);
    }

    jump();
    WidgetsBinding.instance.addPostFrameCallback((_) => jump());
  }

  /// تمرير قائمة الفئات للفئة النشطة مع إعادة محاولة حتى يرتبط الـ ListView.
  void _scrollIptvActiveCategoryIntoView({int attempt = 0}) {
    if (!mounted || !_showLiveIptvOverlay) return;
    final ix = _iptvLastCategoryFocusIndex;
    if (!_iptvCategoryScrollController.hasClients) {
      if (attempt < 8) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollIptvActiveCategoryIntoView(attempt: attempt + 1);
        });
      }
      return;
    }
    _scrollIptvIndexIntoView(
      ix,
      _iptvCategoryScrollController,
      _kIptvCatRowHeight,
    );
    // إطار إضافي بعد بناء الصفوف (خصوصاً بعد الرجوع من ملء الشاشة).
    if (attempt < 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollIptvActiveCategoryIntoView(attempt: attempt + 1);
      });
    }
  }

  /// Focus after layout; avoids requestFocus during build / before nodes attach.
  void _scheduleIptvFocusSafe(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showLiveIptvOverlay) return;
      if (!node.canRequestFocus) return;
      node.requestFocus();
    });
  }

  void _iptvRequestFocusNow(FocusNode node) {
    if (!mounted || !_showLiveIptvOverlay) return;
    if (node.canRequestFocus) {
      node.requestFocus();
      return;
    }
    _scheduleIptvFocusSafe(node);
  }

  void _iptvCancelChannelFocusSchedules() {
    _iptvChannelFocusScheduleId++;
  }

  void _iptvCancelMiniPlayerFocusSchedules() {
    _iptvMiniPlayerFocusScheduleId++;
  }

  void _iptvCancelCategoryCommit() {
    _iptvCategoryCommitTimer?.cancel();
    _iptvCategoryCommitTimer = null;
    _iptvPendingCategoryId = null;
  }

  void _iptvMarkPanelColumn(int column) {
    if (_iptvActivePanelColumn == column) return;
    if (!mounted) return;
    _fvSetState(() => _iptvActivePanelColumn = column);
  }

  void _iptvFocusLastRememberedChannel() {
    _iptvCancelMiniPlayerFocusSchedules();
    _iptvOverlayFocusOnMiniPlayer = false;
    _iptvOverlayFocusOnChannelsColumn = true;
    _iptvFocusMoveToChannelsPending = false;
    _iptvMarkPanelColumn(_kIptvPanelColChannels);

    if (_iptvChannelFocusNodes.isNotEmpty &&
        _iptvChannelFocusBoundCategoryId == _iptvActiveCategoryId) {
      final ix = _iptvLastChannelFocusIndex.clamp(
        0,
        _iptvChannelFocusNodes.length - 1,
      );
      _scrollIptvIndexIntoView(
        ix,
        _iptvChannelScrollController,
        _kIptvChRowHeight,
      );
      _iptvRequestFocusNow(_iptvChannelFocusNodes[ix]);
      return;
    }
    _iptvFocusPreferredChannel();
  }

  void _onIptvCategoryNodeFocused(int index) {
    if (index < 0 ||
        index >= _iptvCategoryFocusNodes.length ||
        !_iptvCategoryFocusNodes[index].hasFocus) {
      return;
    }
    if (!mounted) return;
    _iptvMarkPanelColumn(_kIptvPanelColCategories);

    final st = context.read<LiveCatyBloc>().state;
    final rawCats = st is LiveCatySuccess ? st.categories : <CategoryModel>[];
    final visibleCats = _iptvVisibleCategories(rawCats);
    if (index >= visibleCats.length) return;
    final cat = visibleCats[index];
    final id = cat.categoryId;
    if (id == null || id.isEmpty) return;

    final pickingOtherCategory = id != (_iptvActiveCategoryId ?? '');

    // وميض تركيز مبرمج أثناء الانتقال للقنوات / مزامنة القناة المشغّلة.
    // لا تمنع اختيار المستخدم لفئة أخرى (لمس أو جهاز تحكم).
    if (!pickingOtherCategory &&
        (_iptvFocusMoveToChannelsPending ||
            _iptvOverlayFocusOnChannelsColumn ||
            _iptvFocusPlayingChannelAfterChannelSync)) {
      return;
    }

    // المستخدم على عمود الفئات — ألغِ قفل عمود القنوات حتى تُطبَّق الفئة.
    _iptvFocusMoveToChannelsPending = false;
    _iptvOverlayFocusOnChannelsColumn = false;
    _iptvOverlayFocusOnMiniPlayer = false;
    if (pickingOtherCategory) {
      _iptvFocusPlayingChannelAfterChannelSync = false;
    }
    _iptvLastCategoryFocusIndex = index;
    _scrollIptvIndexIntoView(
      index,
      _iptvCategoryScrollController,
      _kIptvCatRowHeight,
    );
    if (_iptvIsTvCategoryReordering) {
      _iptvCancelCategoryCommit();
      return;
    }
    _iptvCancelChannelFocusSchedules();
    _iptvCancelMiniPlayerFocusSchedules();
    // لا setState هنا — التركيز البصري من ListenableBuilder فوري؛
    // تبديل قائمة القنوات مؤجّل حتى لا يتجمّد كل سهم.
    if (!pickingOtherCategory) {
      _iptvCancelCategoryCommit();
      return;
    }
    // Android TV + هاتف: بعد توقّف التركيز طبّق الفئة (debounce).
    // لا تدفئة شبكة على كل سهم — كانت تغرق الـ API وتكسر الفئات التحتية.
    _iptvScheduleCategoryCommit(id);
  }

  void _iptvCommitFocusedCategoryForTvNav() {
    if (!mounted || !_showLiveIptvOverlay) return;
    if (!isTvDevice(context)) {
      _iptvFlushCategoryCommit();
      return;
    }
    final st = context.read<LiveCatyBloc>().state;
    final rawCats = st is LiveCatySuccess ? st.categories : <CategoryModel>[];
    final visibleCats = _iptvVisibleCategories(rawCats);
    if (visibleCats.isEmpty) {
      _iptvFlushCategoryCommit();
      return;
    }
    final ix = _iptvLastCategoryFocusIndex.clamp(0, visibleCats.length - 1);
    final id = visibleCats[ix].categoryId;
    if (id == null || id.isEmpty) {
      _iptvFlushCategoryCommit();
      return;
    }
    _iptvCancelCategoryCommit();
    if (_iptvActiveCategoryId != id) {
      _iptvCommitActiveCategory(id);
    } else if (_iptvNeedsActiveCategoryReload(id)) {
      _iptvReloadActiveCategoryChannels(id);
    }
  }

  /// لمس/ضغط فئة من المستخدم — طبّقها فوراً بدون انتظار مؤقّت التركيز.
  void _iptvUserSelectCategory(String? id) {
    if (!mounted || !_showLiveIptvOverlay) return;
    if (id == null || id.isEmpty) return;
    _iptvFocusMoveToChannelsPending = false;
    _iptvOverlayFocusOnChannelsColumn = false;
    _iptvOverlayFocusOnMiniPlayer = false;
    _iptvFocusPlayingChannelAfterChannelSync = false;
    _iptvCancelChannelFocusSchedules();
    _iptvCancelMiniPlayerFocusSchedules();
    final st = context.read<LiveCatyBloc>().state;
    final rawCats = st is LiveCatySuccess ? st.categories : <CategoryModel>[];
    final visibleCats = _iptvVisibleCategories(rawCats);
    final ix = visibleCats.indexWhere((c) => c.categoryId == id);
    if (ix >= 0) _iptvLastCategoryFocusIndex = ix;
    _iptvCancelCategoryCommit();
    if (_iptvActiveCategoryId == id) {
      // نفس الفئة لكن القنوات ناقصة/فارغة — أعد الجلب (مهم للفئات التحتية).
      if (_iptvNeedsActiveCategoryReload(id)) {
        _iptvReloadActiveCategoryChannels(id);
      }
      return;
    }
    _iptvCommitActiveCategory(id);
  }

  bool _iptvNeedsActiveCategoryReload(String id) {
    if (_iptvIsPinnedLiveCategory(id)) return false;
    final channelsBloc = context.read<ChannelsBloc>();
    if (channelsBloc.isLiveFetchInFlight(id)) return false;
    final list = channelsBloc.liveListForCategoryId(id);
    return list == null || list.isEmpty;
  }

  void _iptvReloadActiveCategoryChannels(String id) {
    if (!mounted || !_showLiveIptvOverlay) return;
    final channelsBloc = context.read<ChannelsBloc>();
    LiveCatalogWarmService.instance.pauseForUserFetch();
    channelsBloc.invalidateLiveCategory(id);
    _iptvChannelFocusBoundCategoryId = null;
    _iptvLastChannelFocusIndex = 0;
    _iptvJumpScrollToStart(_iptvChannelScrollController);
    _fvSetState(() {});
    channelsBloc.add(
      GetLiveChannelsEvent(typeCategory: TypeCategory.live, catyId: id),
    );
    _iptvScheduleWarmResume();
  }

  void _iptvScheduleWarmResume() {
    // استأنف التدفئة بعد اكتمال جلب الفئة النشطة (وليس مؤقّت ثابت).
    Future<void>(() async {
      final id = _iptvActiveCategoryId ?? '';
      for (var i = 0; i < 40; i++) {
        if (!mounted) return;
        final bloc = context.read<ChannelsBloc>();
        if (id.isEmpty || !bloc.isLiveFetchInFlight(id)) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      LiveCatalogWarmService.instance.resumeAfterUserFetch(
        channels: context.read<ChannelsBloc>(),
        liveCaty: context.read<LiveCatyBloc>(),
      );
    });
  }

  void _iptvScheduleCategoryCommit(String id) {
    _iptvPendingCategoryId = id;
    _iptvCategoryCommitTimer?.cancel();
    _iptvCategoryCommitTimer = Timer(_kIptvCategoryCommitDelay, () {
      if (!mounted || !_showLiveIptvOverlay) return;
      final pending = _iptvPendingCategoryId;
      _iptvPendingCategoryId = null;
      if (pending == null) return;
      _iptvCommitActiveCategory(pending);
    });
  }

  /// تطبيق الفئة النشطة فوراً (قبل الانتقال لعمود القنوات / OK).
  void _iptvFlushCategoryCommit() {
    final pending = _iptvPendingCategoryId;
    _iptvCategoryCommitTimer?.cancel();
    _iptvCategoryCommitTimer = null;
    _iptvPendingCategoryId = null;
    if (pending == null) return;
    _iptvCommitActiveCategory(pending);
  }

  void _iptvCommitActiveCategory(String id) {
    if (!mounted || !_showLiveIptvOverlay) return;
    if (_iptvActiveCategoryId == id) {
      if (_iptvNeedsActiveCategoryReload(id)) {
        _iptvReloadActiveCategoryChannels(id);
      }
      return;
    }
    _iptvActiveCategoryId = id;
    _iptvChannelFocusBoundCategoryId = null;
    _iptvLastChannelFocusIndex = 0;
    _iptvJumpScrollToStart(_iptvChannelScrollController);

    final channelsBloc = context.read<ChannelsBloc>();
    if (id == kIptvFavoritesCategoryId) {
      final favorites = context.read<FavoritesCubit>().state.lives;
      _iptvResyncChannelFocusNodes(favorites, categoryKey: id);
      _fvSetState(() {});
      return;
    }
    if (id == kIptvRecentlyWatchedCategoryId) {
      _iptvEnsureRecentlyWatchedLoaded();
      _iptvResyncChannelFocusNodes(
        _iptvRecentlyWatched,
        categoryKey: id,
      );
      _fvSetState(() {});
      return;
    }

    final cached = channelsBloc.liveListForCategoryId(id);
    if (cached != null && cached.isNotEmpty) {
      // كاش جاهز (فهرس كامل أو جلب سابق): حدّث القائمة محلياً فوراً.
      _iptvResyncChannelFocusNodes(cached, categoryKey: id);
      _fvSetState(() {});
      return;
    }

    // أولوية جلب المستخدم — أوقف التدفئة حتى لا تغرق الـ API.
    LiveCatalogWarmService.instance.pauseForUserFetch();

    // قائمة فارغة مخزّنة = غير موثوقة؛ امسح وأعد الجلب.
    if (cached != null && cached.isEmpty) {
      channelsBloc.invalidateLiveCategory(id);
    }

    _fvSetState(() {});
    channelsBloc.add(
      GetLiveChannelsEvent(typeCategory: TypeCategory.live, catyId: id),
    );
    _iptvScheduleWarmResume();
  }

  bool _iptvIsSameChannelAsPlaying(ChannelLive ch) {
    final playing = _currentLiveChannel ?? widget.channelLive;
    if (playing == null) return false;
    return liveChannelsMatch(ch, playing);
  }

  void _onIptvChannelNodeFocused(int index) {
    if (index < 0 ||
        index >= _iptvChannelFocusNodes.length ||
        !_iptvChannelFocusNodes[index].hasFocus) {
      return;
    }
    _iptvFocusMoveToChannelsPending = false;
    _iptvOverlayFocusOnChannelsColumn = true;
    _iptvOverlayFocusOnMiniPlayer = false;
    _iptvCancelMiniPlayerFocusSchedules();
    _iptvMarkPanelColumn(_kIptvPanelColChannels);
    _iptvLastChannelFocusIndex = index;
    _scrollIptvIndexIntoView(
      index,
      _iptvChannelScrollController,
      _kIptvChRowHeight,
    );
  }

  void _iptvResyncCategoryFocusNodes(int count) {
    if (!mounted || count < 0) return;
    if (count == _iptvCategoryFocusNodes.length) return;
    // أثناء كتابة البحث / الكلافيي: لا تُعد بناء العقد (يغلق الكلافيي).
    if (_iptvCategorySearchHasFocus() ||
        MediaQuery.viewInsetsOf(context).bottom > 40 ||
        _iptvCategorySearch.trim().isNotEmpty) {
      if (count < _iptvCategoryFocusNodes.length) return;
    }

    if (count > _iptvCategoryFocusNodes.length) {
      final old = _iptvCategoryFocusNodes;
      _iptvCategoryFocusNodes = List.generate(count, (i) {
        if (i < old.length) return old[i];
        final node = FocusNode(debugLabel: 'iptv_cat_$i');
        node.addListener(() => _onIptvCategoryNodeFocused(i));
        return node;
      });
      // لا setState أثناء الكتابة — يكفي تحديث القائمة المحلية.
      if (_iptvCategorySearchHasFocus() ||
          MediaQuery.viewInsetsOf(context).bottom > 40) {
        return;
      }
      _fvSetState(() {});
      return;
    }

    // أثناء البحث: لا نُعد بناء العقد (يُغلق الكلافيي) — نستخدم أول [count] فقط.
    if (_iptvCategorySearch.trim().isNotEmpty) return;

    final old = _iptvCategoryFocusNodes;
    _iptvCategoryFocusNodes = old.sublist(0, count);
    _fvSetState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (var i = count; i < old.length; i++) {
        try {
          old[i].dispose();
        } catch (_) {}
      }
    });
    if (_iptvRequestCategoryFocusAfterNextCatSync && count > 0) {
      _iptvRequestCategoryFocusAfterNextCatSync = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showLiveIptvOverlay) return;
        _iptvFocusPreferredCategory();
      });
    } else if (_showLiveIptvOverlay && count > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showLiveIptvOverlay) return;
        _scrollIptvActiveCategoryIntoView();
      });
    }
  }

  void _iptvTryFocusPlayingChannelIfPending(List<ChannelLive> channels) {
    if (!_iptvFocusPlayingChannelAfterChannelSync ||
        !_showLiveIptvOverlay ||
        !mounted ||
        !_iptvOverlayFocusOnChannelsColumn) {
      return;
    }
    if (channels.isEmpty) {
      
      if (context.read<ChannelsBloc>().state is ChannelsLoading) {
        return;
      }
      _iptvFocusPlayingChannelAfterChannelSync = false;
      _iptvOverlayFocusOnChannelsColumn = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showLiveIptvOverlay) return;
        _iptvFocusPreferredCategory();
      });
      return;
    }
    if (_iptvChannelFocusNodes.length != channels.length) return;
    final playing = _currentLiveChannel ?? widget.channelLive;
    var playIdx = 0;
    if (playing != null) {
      final ix = channels.indexWhere((c) => liveChannelsMatch(c, playing));
      playIdx = ix >= 0 ? ix : 0;
    }
    _iptvOverlayFocusOnChannelsColumn = true;
    _iptvFocusPlayingChannelAfterChannelSync = false;
    final target = playIdx;
    _iptvLastChannelFocusIndex = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showLiveIptvOverlay) return;
      if (target >= _iptvChannelFocusNodes.length) return;
      if (!_iptvChannelFocusNodes[target].canRequestFocus) return;
      _scrollIptvIndexIntoView(
        target,
        _iptvChannelScrollController,
        _kIptvChRowHeight,
      );
      _iptvChannelFocusNodes[target].requestFocus();
    });
  }

  void _iptvEnsureChannelFocusNodesSynced(
    List<ChannelLive> channels,
    String categoryKey,
  ) {
    final count = channels.length;
    if (count == _iptvChannelFocusNodes.length &&
        categoryKey == _iptvChannelFocusBoundCategoryId) {
      return;
    }
    _iptvChannelFocusBoundCategoryId = categoryKey;
    final old = _iptvChannelFocusNodes;
    _iptvChannelFocusNodes = List.generate(count, (i) {
      final node = FocusNode(debugLabel: 'iptv_ch_$i');
      node.addListener(() => _onIptvChannelNodeFocused(i));
      return node;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final n in old) {
        try {
          n.dispose();
        } catch (_) {}
      }
    });
  }

  void _iptvResyncChannelFocusNodes(
    List<ChannelLive> channels, {
    required String categoryKey,
  }) {
    if (!mounted) return;
    final count = channels.length;
    final sameStructure =
        count == _iptvChannelFocusNodes.length &&
        categoryKey == _iptvChannelFocusBoundCategoryId;
    if (sameStructure) {
      _iptvTryFocusPlayingChannelIfPending(channels);
      return;
    }
    final hadChannelFocus = _iptvChannelFocusNodes.any((n) => n.hasFocus);
    final categoryChanged = categoryKey != _iptvChannelFocusBoundCategoryId;
    final preserveIndex = hadChannelFocus
        ? _iptvChannelFocusNodes.indexWhere((n) => n.hasFocus)
        : _iptvLastChannelFocusIndex;
    _iptvEnsureChannelFocusNodesSynced(channels, categoryKey);
    _fvSetState(() {});
    if (_iptvFocusPlayingChannelAfterChannelSync) {
      _iptvTryFocusPlayingChannelIfPending(channels);
    } else if (_iptvOverlayFocusOnChannelsColumn &&
        !categoryChanged &&
        preserveIndex >= 0 &&
        preserveIndex < count) {
      _iptvLastChannelFocusIndex = preserveIndex;
      _scheduleIptvFocusSafe(_iptvChannelFocusNodes[preserveIndex]);
    }
    if (count == 0) {
      // لا تُعد التركيز للفئات أثناء انتقال يمين مقصود نحو القنوات.
      if (_iptvFocusMoveToChannelsPending ||
          _iptvOverlayFocusOnChannelsColumn) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showLiveIptvOverlay) return;
        if (_iptvFocusMoveToChannelsPending ||
            _iptvOverlayFocusOnChannelsColumn) {
          return;
        }
        if (_iptvChannelFocusNodes.isNotEmpty) return;
        if (_iptvCategoryFocusNodes.isEmpty) return;
        if (_iptvOverlayPanelHasPrimaryFocus()) return;
        final ix = _iptvLastCategoryFocusIndex.clamp(
          0,
          _iptvCategoryFocusNodes.length - 1,
        );
        _scheduleIptvFocusSafe(_iptvCategoryFocusNodes[ix]);
      });
    }
  }

  /// Ã˜Â£Ã˜Â«Ã™â€ Ã˜Â§Ã˜Â¡ Ã˜Â¬Ã™â€žÃ˜Â¨ Ã˜Â§Ã™â€žÃ™â€šÃ™â€ Ã™Ë†Ã˜Â§Ã˜Âª (Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  Ã™Æ’Ã˜Â§Ã˜Â´) Ã™Æ’Ã˜Â§Ã™â€  Ã˜Â¹Ã™â€¦Ã™Ë†Ã˜Â¯ Ã˜Â§Ã™â€žÃ™â€šÃ™â€ Ã™Ë†Ã˜Â§Ã˜Âª Ã™Å Ã™ÂÃ˜Â³Ã˜ÂªÃ˜Â¨Ã˜Â¯Ã™â€ž Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€˜Ã˜Â§Ã™â€¦Ã˜Â© Ã™Æ’Ã˜Â§Ã™â€¦Ã™â€žÃ˜Â© Ã™ÂÃ˜ÂªÃ˜Â¶Ã™Å Ã˜Â¹ Ã˜Â¹Ã™â€ Ã˜Â§Ã˜ÂµÃ˜Â± Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â±Ã™Æ’Ã™Å Ã˜Â² Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â¬Ã™â€¡Ã˜Â²Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â¨Ã˜Â·Ã™Å Ã˜Â¦Ã˜Â©.
  void _iptvRefocusCategoryWhileChannelsEmptyLoading() {
    if (!_showLiveIptvOverlay || !mounted) return;
    if (_iptvFocusMoveToChannelsPending || _iptvOverlayFocusOnChannelsColumn) {
      return;
    }
    if (_iptvChannelFocusNodes.isNotEmpty) return;
    if (_iptvCategoryFocusNodes.isEmpty) return;
    final st = context.read<ChannelsBloc>().state;
    if (st is! ChannelsLoading) return;
    _iptvOverlayFocusOnChannelsColumn = false;
    final ix = _iptvLastCategoryFocusIndex.clamp(
      0,
      _iptvCategoryFocusNodes.length - 1,
    );
    _scheduleIptvFocusSafe(_iptvCategoryFocusNodes[ix]);
  }

  /// Ã™Å Ã™â€¦Ã™Å Ã™â€  Ã™â€¦Ã™â€  Ã˜Â¹Ã™â€¦Ã™Ë†Ã˜Â¯ Ã˜Â§Ã™â€žÃ™ÂÃ˜Â¦Ã˜Â§Ã˜Âª Ã¢â€ â€™ Ã˜Â¹Ã™â€¦Ã™Ë†Ã˜Â¯ Ã˜Â§Ã™â€žÃ™â€šÃ™â€ Ã™Ë†Ã˜Â§Ã˜Âª: Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â±Ã™Æ’Ã™Å Ã˜Â² Ã˜Â­Ã˜Â³Ã˜Â¨ [streamId] Ã™â€žÃ™â€žÃ™â€šÃ™â€ Ã˜Â§Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â¹Ã˜Â±Ã™Ë†Ã˜Â¶Ã˜Â©Ã˜â€º
  /// Ã˜Â¥Ã™â€  Ã™â€žÃ™â€¦ Ã˜ÂªÃ™ÂÃ™Ë†Ã˜Â¬Ã˜Â¯ Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ™â€šÃ˜Â§Ã˜Â¦Ã™â€¦Ã˜Â© Ã¢â€ â€™ 0 (Ã™â€žÃ˜Â§ Ã™Å Ã˜Â¹Ã˜ÂªÃ™â€¦Ã˜Â¯ Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ™ÂÃ™â€¡Ã˜Â±Ã˜Â³ Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â§Ã˜Â¨Ã™â€š Ã™Æ’Ã˜Â£Ã˜Â³Ã˜Â§Ã˜Â³).
  void _iptvFocusPreferredChannel() {
    _iptvCommitFocusedCategoryForTvNav();
    _iptvCancelMiniPlayerFocusSchedules();
    _iptvMarkPanelColumn(_kIptvPanelColChannels);
    // إلغاء محاولات قديمة ثم بدء انتقال محمي نحو عمود القنوات.
    _iptvChannelFocusScheduleId++;
    final scheduleId = _iptvChannelFocusScheduleId;
    _iptvFocusMoveToChannelsPending = true;
    _iptvOverlayFocusOnChannelsColumn = true;
    _iptvOverlayFocusOnMiniPlayer = false;

    // إن كانت قائمة القنوات جاهزة للفئة النشطة — ركّز فوراً بدون انتظار إطار.
    if (_iptvChannelFocusNodes.isNotEmpty &&
        _iptvChannelFocusBoundCategoryId == _iptvActiveCategoryId) {
      // أول قناة، أو القناة قيد التشغيل إن وُجدت في هذه الفئة.
      var ix = 0;
      final playing = _currentLiveChannel ?? widget.channelLive;
      if (playing != null) {
        final channelsBloc = context.read<ChannelsBloc>();
        final list =
            channelsBloc.liveListForCategoryId(_iptvActiveCategoryId ?? '') ??
            const <ChannelLive>[];
        final found = list.indexWhere((c) => liveChannelsMatch(c, playing));
        if (found >= 0) ix = found;
      }
      ix = ix.clamp(0, _iptvChannelFocusNodes.length - 1);
      _iptvLastChannelFocusIndex = ix;
      _iptvRequestFocusNow(_iptvChannelFocusNodes[ix]);
      _scrollIptvIndexIntoView(
        ix,
        _iptvChannelScrollController,
        _kIptvChRowHeight,
      );
      // أبقِ إعادة المحاولة إن لم يثبت التركيز فوراً (مثل تنقّل الفئات↔القنوات).
      _iptvSchedulePreferredChannelFocus(attempt: 0, scheduleId: scheduleId);
      return;
    }

    _iptvSchedulePreferredChannelFocus(attempt: 0, scheduleId: scheduleId);
  }

  void _iptvSchedulePreferredChannelFocus({
    int attempt = 0,
    required int scheduleId,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showLiveIptvOverlay) return;
      if (scheduleId != _iptvChannelFocusScheduleId) return;
      if (!_iptvOverlayFocusOnChannelsColumn &&
          !_iptvFocusPlayingChannelAfterChannelSync &&
          !_iptvFocusMoveToChannelsPending) {
        return;
      }
      if (_iptvChannelFocusNodes.isEmpty) {
        if (attempt < _kIptvFocusEmptyRetries) {
          _iptvSchedulePreferredChannelFocus(
            attempt: attempt + 1,
            scheduleId: scheduleId,
          );
        } else {
          _iptvFocusMoveToChannelsPending = false;
        }
        return;
      }
      final channelsBloc = context.read<ChannelsBloc>();
      final chState = channelsBloc.state;
      final favState = context.read<FavoritesCubit>().state;
      final channels = _iptvResolveChannelsForActive(
        channelsBloc,
        chState,
        favState,
      );
      if (channels.isEmpty) {
        if (attempt < _kIptvFocusEmptyRetries) {
          _iptvSchedulePreferredChannelFocus(
            attempt: attempt + 1,
            scheduleId: scheduleId,
          );
        } else {
          _iptvFocusMoveToChannelsPending = false;
        }
        return;
      }
      if (channels.length != _iptvChannelFocusNodes.length) {
        if (attempt < _kIptvFocusEmptyRetries) {
          _iptvSchedulePreferredChannelFocus(
            attempt: attempt + 1,
            scheduleId: scheduleId,
          );
        } else {
          _iptvFocusMoveToChannelsPending = false;
        }
        return;
      }
      if (scheduleId != _iptvChannelFocusScheduleId) return;
      if (!_iptvOverlayFocusOnChannelsColumn &&
          !_iptvFocusPlayingChannelAfterChannelSync &&
          !_iptvFocusMoveToChannelsPending) {
        return;
      }
      final sid = (_currentLiveChannel ?? widget.channelLive)?.streamId;
      int ix = 0;
      if (sid != null && sid.isNotEmpty) {
        final playing = _currentLiveChannel ?? widget.channelLive;
        final found = playing == null
            ? -1
            : channels.indexWhere((c) => liveChannelsMatch(c, playing));
        ix = found >= 0 ? found : 0;
      }
      ix = ix.clamp(0, _iptvChannelFocusNodes.length - 1);
      _iptvLastChannelFocusIndex = ix;
      _iptvOverlayFocusOnChannelsColumn = true;
      _scrollIptvIndexIntoView(
        ix,
        _iptvChannelScrollController,
        _kIptvChRowHeight,
      );
      final node = _iptvChannelFocusNodes[ix];
      _iptvRequestFocusNow(node);
      if (node.hasFocus) {
        _iptvFocusMoveToChannelsPending = false;
        return;
      }
      if (attempt < _kIptvFocusEmptyRetries) {
        _iptvSchedulePreferredChannelFocus(
          attempt: attempt + 1,
          scheduleId: scheduleId,
        );
      } else {
        _iptvFocusMoveToChannelsPending = false;
      }
    });
  }

  void _iptvFocusPreferredCategory() {
    _iptvSchedulePreferredCategoryFocus(attempt: 0);
  }

  void _iptvSchedulePreferredCategoryFocus({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showLiveIptvOverlay) return;
      if (_iptvCategoryFocusNodes.isEmpty) {
        if (attempt < _kIptvFocusEmptyRetries) {
          _iptvSchedulePreferredCategoryFocus(attempt: attempt + 1);
        }
        return;
      }
      int ix = 0;
      final st = context.read<LiveCatyBloc>().state;
      final rawCats = st is LiveCatySuccess ? st.categories : <CategoryModel>[];
      final visibleCats = _iptvVisibleCategories(rawCats);
      if (visibleCats.isNotEmpty) {
        // الفئة التي يتصفحها المستخدم حالياً، وليس دائماً فئة القناة المشغّلة.
        final catId = (_iptvActiveCategoryId ?? _iptvPlayingCategoryId())
            ?.trim();
        if (catId != null && catId.isNotEmpty) {
          final i = visibleCats.indexWhere((c) => c.categoryId == catId);
          if (i >= 0) ix = i;
        } else if (_iptvLastCategoryFocusIndex >= 0 &&
            _iptvLastCategoryFocusIndex < visibleCats.length) {
          ix = _iptvLastCategoryFocusIndex;
        }
      }
      ix = ix.clamp(0, _iptvCategoryFocusNodes.length - 1);
      _iptvLastCategoryFocusIndex = ix;
      _iptvOverlayFocusOnChannelsColumn = false;
      _iptvOverlayFocusOnMiniPlayer = false;
      _scheduleIptvFocusSafe(_iptvCategoryFocusNodes[ix]);
    });
  }

  void _iptvClearCategoryReorderTimers() {
    _iptvCatReorderLongPressTimer?.cancel();
    _iptvCatReorderLongPressTimer = null;
    _iptvCatReorderLongPressTriggered = false;
  }

  bool _iptvConsumeBackForCategoryReorder() {
    if (!_iptvIsTvCategoryReordering) return false;
    _iptvCancelTvCategoryReorder();
    return true;
  }

  void _startIptvCatReorderLongPress(int index) {
    _iptvClearCategoryReorderTimers();
    if (_iptvCategorySearch.trim().isNotEmpty) return;
    if (index < _iptvPinnedLiveCategoryCount) return;
    _iptvCatReorderLongPressTimer = Timer(_kIptvCatReorderLongPress, () {
      if (!mounted) return;
      _iptvCatReorderLongPressTimer = null;
      _iptvCatReorderLongPressTriggered = true;
      _iptvBeginTvCategoryReorder(index);
    });
  }

  bool _cancelIptvCatReorderLongPressAndCheck() {
    _iptvCatReorderLongPressTimer?.cancel();
    _iptvCatReorderLongPressTimer = null;
    final wasLong = _iptvCatReorderLongPressTriggered;
    if (wasLong) _iptvCatReorderLongPressTriggered = false;
    return wasLong;
  }

  List<String> _iptvReorderableIdsFromDisplay(List<CategoryModel> display) {
    return display
        .skip(_iptvPinnedLiveCategoryCount)
        .map((c) => (c.categoryId ?? '').trim())
        .where((id) => id.isNotEmpty && !_iptvIsPinnedLiveCategory(id))
        .toList();
  }

  void _iptvBeginTvCategoryReorder(int index) {
    if (!mounted ||
        index < _iptvPinnedLiveCategoryCount ||
        _iptvIsTvCategoryReordering) {
      return;
    }
    if (_iptvCategorySearch.trim().isNotEmpty) return;
    final st = context.read<LiveCatyBloc>().state;
    final rawCats = st is LiveCatySuccess ? st.categories : <CategoryModel>[];
    final display = _iptvDisplayCategories(rawCats);
    if (index >= display.length) return;
    if (_iptvIsPinnedLiveCategory(display[index].categoryId)) return;
    _iptvTvReorderWorkingIds = _iptvReorderableIdsFromDisplay(display);
    _iptvTvReorderIndex = index;
    _iptvLastCategoryFocusIndex = index;
    _fvSetState(() {});
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  void _iptvTvMoveReorderCategory(int delta) {
    final idx = _iptvTvReorderIndex;
    final working = _iptvTvReorderWorkingIds;
    if (idx == null || working == null || working.isEmpty) return;
    final next = idx + delta;
    if (next < _iptvPinnedLiveCategoryCount) {
      if (idx >= 0 && idx < _iptvCategoryFocusNodes.length) {
        _iptvRequestFocusNow(_iptvCategoryFocusNodes[idx]);
      }
      return;
    }
    final wi = idx - _iptvPinnedLiveCategoryCount;
    final wnext = next - _iptvPinnedLiveCategoryCount;
    if (wi < 0 || wi >= working.length) return;
    if (wnext < 0 || wnext >= working.length) {
      if (idx >= 0 && idx < _iptvCategoryFocusNodes.length) {
        _iptvRequestFocusNow(_iptvCategoryFocusNodes[idx]);
      }
      return;
    }
    final item = working.removeAt(wi);
    working.insert(wnext, item);
    _iptvTvReorderIndex = next;
    _iptvLastCategoryFocusIndex = next;
    _touchLiveIptvOverlayActivity();
    _fvSetState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showLiveIptvOverlay) return;
      if (next < _iptvCategoryFocusNodes.length) {
        _iptvRequestFocusNow(_iptvCategoryFocusNodes[next]);
      }
      _scrollIptvIndexIntoView(
        next,
        _iptvCategoryScrollController,
        _kIptvCatRowHeight,
        smooth: true,
      );
    });
  }

  void _iptvCommitTvCategoryReorder() {
    final working = _iptvTvReorderWorkingIds;
    if (working == null) return;
    _iptvPersistedCatOrder = List<String>.from(working);
    LiveCategoryOrderStore.save(
      _liveCategoryOrderAccountId(),
      _iptvPersistedCatOrder,
    );
    final keepIndex = _iptvTvReorderIndex;
    _iptvTvReorderWorkingIds = null;
    _iptvTvReorderIndex = null;
    _iptvIgnoreNextCatOkUp = true;
    _iptvClearCategoryReorderTimers();
    _fvSetState(() {});
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
    if (keepIndex != null && keepIndex < _iptvCategoryFocusNodes.length) {
      _iptvRequestFocusNow(_iptvCategoryFocusNodes[keepIndex]);
    }
    if (mounted) {
      showSoftToastAboveOverlay(
        context,
        'live_cat_reorder_title'.tr,
        'live_cat_reorder_saved'.tr,
      );
    }
  }

  void _iptvCancelTvCategoryReorder() {
    if (!_iptvIsTvCategoryReordering && _iptvTvReorderWorkingIds == null) {
      return;
    }
    _iptvTvReorderWorkingIds = null;
    _iptvTvReorderIndex = null;
    _iptvClearCategoryReorderTimers();
    _fvSetState(() {});
    if (_iptvLastCategoryFocusIndex >= 0 &&
        _iptvLastCategoryFocusIndex < _iptvCategoryFocusNodes.length) {
      _iptvRequestFocusNow(
        _iptvCategoryFocusNodes[_iptvLastCategoryFocusIndex],
      );
    }
  }

  void _iptvOnPhoneCategoriesReorder(int oldIndex, int newIndex) {
    if (_iptvCategorySearch.trim().isNotEmpty) return;
    final pinned = _iptvPinnedLiveCategoryCount;
    if (oldIndex < pinned) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < pinned) newIndex = pinned;
    if (oldIndex == newIndex) return;
    final st = context.read<LiveCatyBloc>().state;
    final rawCats = st is LiveCatySuccess ? st.categories : <CategoryModel>[];
    final display = _iptvDisplayCategories(rawCats);
    if (oldIndex >= display.length) return;
    final ids = _iptvReorderableIdsFromDisplay(display);
    final from = oldIndex - pinned;
    if (from < 0 || from >= ids.length) return;
    final to = (newIndex - pinned).clamp(0, ids.length - 1);
    final item = ids.removeAt(from);
    ids.insert(to, item);
    _iptvPersistedCatOrder = ids;
    LiveCategoryOrderStore.save(_liveCategoryOrderAccountId(), ids);
    _iptvLastCategoryFocusIndex = to + pinned;
    _touchLiveIptvOverlayActivity();
    _fvSetState(() {});
  }

  bool _iptvIsOverlayBackKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.goBack;
  }

  KeyEventResult _iptvCategoryItemOnKey(
    int index,
    int nCategories,
    KeyEvent event,
  ) {
    final key = event.logicalKey;
    if (_iptvIsTvCategoryReordering) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _touchLiveIptvOverlayActivity();
        if (_iptvIsOverlayBackKey(key)) {
          if (event is KeyDownEvent) _iptvCancelTvCategoryReorder();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (!_iptvNavDebounceAllow()) return KeyEventResult.handled;
          _iptvTvMoveReorderCategory(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (!_iptvNavDebounceAllow()) return KeyEventResult.handled;
          _iptvTvMoveReorderCategory(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowLeft) {
          return KeyEventResult.handled;
        }
        if (_isOkLogicalKey(key)) {
          if (event is KeyDownEvent) _iptvCommitTvCategoryReorder();
          return KeyEventResult.handled;
        }
      }
      if (event is KeyUpEvent && _isOkLogicalKey(key)) {
        _iptvIgnoreNextCatOkUp = false;
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (_isOkLogicalKey(key)) {
      if (event is KeyDownEvent) {
        _touchLiveIptvOverlayActivity();
        if (index >= _iptvPinnedLiveCategoryCount) {
          _startIptvCatReorderLongPress(index);
          return KeyEventResult.handled;
        }
        _iptvFocusPreferredChannel();
        return KeyEventResult.handled;
      }
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (event is KeyUpEvent) {
        if (index < _iptvPinnedLiveCategoryCount) return KeyEventResult.handled;
        if (_iptvIgnoreNextCatOkUp) {
          _iptvIgnoreNextCatOkUp = false;
          return KeyEventResult.handled;
        }
        final wasLong = _cancelIptvCatReorderLongPressAndCheck();
        if (wasLong) return KeyEventResult.handled;
        _iptvFocusPreferredChannel();
        return KeyEventResult.handled;
      }
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_iptvNavDebounceAllow()) return KeyEventResult.handled;
    _touchLiveIptvOverlayActivity();
    if (key == LogicalKeyboardKey.arrowDown) {
      _iptvFocusMoveToChannelsPending = false;
      _iptvOverlayFocusOnChannelsColumn = false;
      _iptvFocusPlayingChannelAfterChannelSync = false;
      _iptvCancelChannelFocusSchedules();
      if (index < nCategories - 1) {
        _iptvRequestFocusNow(_iptvCategoryFocusNodes[index + 1]);
      } else if (index >= 0 && index < _iptvCategoryFocusNodes.length) {
        // آخر فئة: ابقَ على نفس الصف — لا انتقال للقنوات.
        _iptvRequestFocusNow(_iptvCategoryFocusNodes[index]);
        _scrollIptvIndexIntoView(
          index,
          _iptvCategoryScrollController,
          _kIptvCatRowHeight,
          smooth: true,
        );
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _iptvFocusMoveToChannelsPending = false;
      _iptvOverlayFocusOnChannelsColumn = false;
      _iptvFocusPlayingChannelAfterChannelSync = false;
      _iptvCancelChannelFocusSchedules();
      if (index > 0) {
        _iptvRequestFocusNow(_iptvCategoryFocusNodes[index - 1]);
      } else {
        _iptvFocusCategorySearch();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _iptvFocusPreferredChannel();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _iptvCategoriesBackFocusNode.canRequestFocus = true;
      _iptvRequestFocusNow(_iptvCategoriesBackFocusNode);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _iptvChannelItemOnKey(
    int index,
    int nChannels,
    UserModel user,
    ChannelLive ch,
    KeyEvent event,
  ) {
    if (event is KeyDownEvent) {
      if (!_iptvNavDebounceAllow()) return KeyEventResult.handled;
      _touchLiveIptvOverlayActivity();
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        if (index < nChannels - 1) {
          _iptvRequestFocusNow(_iptvChannelFocusNodes[index + 1]);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        if (index > 0) {
          _iptvRequestFocusNow(_iptvChannelFocusNodes[index - 1]);
        } else {
          _iptvRequestFocusNow(_iptvChannelFocusNodes[0]);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        // رجوع فوري لعمود الفئات دون إعادة جلب/إعادة بناء.
        _iptvFocusMoveToChannelsPending = false;
        _iptvOverlayFocusOnChannelsColumn = false;
        _iptvOverlayFocusOnMiniPlayer = false;
        _iptvCancelChannelFocusSchedules();
        _iptvCancelMiniPlayerFocusSchedules();
        if (_iptvCategoryFocusNodes.isNotEmpty) {
          final ix = _iptvLastCategoryFocusIndex.clamp(
            0,
            _iptvCategoryFocusNodes.length - 1,
          );
          _iptvRequestFocusNow(_iptvCategoryFocusNodes[ix]);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _iptvFocusMiniPlayer();
        return KeyEventResult.handled;
      }
      if (_isOkLogicalKey(key)) {
        _startOkLongPressTimer(channel: ch);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event is KeyUpEvent && _isOkLogicalKey(event.logicalKey)) {
      if (_iptvIgnoreNextChannelOkUp) {
        _iptvIgnoreNextChannelOkUp = false;
        _iptvIgnoreChannelOkTimer?.cancel();
        _iptvIgnoreChannelOkTimer = null;
        _okLongPressTimer?.cancel();
        _okLongPressTimer = null;
        return KeyEventResult.handled;
      }
      final wasLong = _cancelOkLongPressAndCheckTriggered();
      if (wasLong) return KeyEventResult.handled;

      final link = _buildLiveStreamLink(ch, user);
      if (link.isEmpty) return KeyEventResult.handled;
      _channelSwitchDebounce?.cancel();
      _channelSwitchDebounce = null;
      if (_iptvIsSameChannelAsPlaying(ch)) {
        _closeLiveIptvOverlay();
        return KeyEventResult.handled;
      }
      // نفس آلية المشروع القديم: بدّل داخل اللوحة دون إغلاق فوري (Exo يبقى مستقراً).
      _touchPlayerControlsActivity();
      unawaited(_switchToLiveChannel(ch, link));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _armIptvIgnoreNextChannelOkUp() {
    _iptvIgnoreNextChannelOkUp = true;
    _iptvIgnoreChannelOkTimer?.cancel();
    _iptvIgnoreChannelOkTimer = Timer(const Duration(milliseconds: 450), () {
      _iptvIgnoreNextChannelOkUp = false;
      _iptvIgnoreChannelOkTimer = null;
    });
  }

  void _iptvFocusMiniPlayer() {
    _iptvFocusMoveToChannelsPending = false;
    _iptvOverlayFocusOnMiniPlayer = true;
    _iptvOverlayFocusOnChannelsColumn = false;
    _iptvCancelChannelFocusSchedules();
    _iptvMarkPanelColumn(_kIptvPanelColPlayer);
    _iptvMiniPlayerFocusScheduleId++;
    final scheduleId = _iptvMiniPlayerFocusScheduleId;
    // فوري + إعادة محاولة — نفس موثوقية تنقّل الفئات↔القنوات.
    _iptvRequestFocusNow(_iptvMiniPlayerFocusNode);
    _iptvScheduleMiniPlayerFocus(attempt: 0, scheduleId: scheduleId);
  }

  void _iptvScheduleMiniPlayerFocus({
    int attempt = 0,
    required int scheduleId,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showLiveIptvOverlay) return;
      if (scheduleId != _iptvMiniPlayerFocusScheduleId) return;
      if (!_iptvOverlayFocusOnMiniPlayer) return;
      if (_iptvMiniPlayerFocusNode.hasFocus) return;
      _iptvRequestFocusNow(_iptvMiniPlayerFocusNode);
      if (_iptvMiniPlayerFocusNode.hasFocus) return;
      if (attempt < _kIptvFocusEmptyRetries) {
        _iptvScheduleMiniPlayerFocus(
          attempt: attempt + 1,
          scheduleId: scheduleId,
        );
      }
    });
  }

  KeyEventResult _iptvMiniPlayerOnKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    // فوق / تحت / يمين: ما كاين والو — خليه فالـ mini-player.
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      _touchLiveIptvOverlayActivity();
      if (!_iptvMiniPlayerFocusNode.hasFocus) {
        _iptvRequestFocusNow(_iptvMiniPlayerFocusNode);
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_iptvNavDebounceAllow()) return KeyEventResult.handled;
    _touchLiveIptvOverlayActivity();
    if (key == LogicalKeyboardKey.arrowLeft) {
      _iptvOverlayFocusOnMiniPlayer = false;
      _iptvFocusLastRememberedChannel();
      return KeyEventResult.handled;
    }
    if (_isOkLogicalKey(key)) {
      final hasLivePlayback =
          (_currentLiveChannel ?? widget.channelLive) != null &&
          _currentPlaybackUrl.trim().isNotEmpty;
      if (!hasLivePlayback) return KeyEventResult.handled;
      _closeLiveIptvOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onLiveIptvOverlayShellKey(FocusNode node, KeyEvent event) {
    if (!_showLiveIptvOverlay) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    _touchLiveIptvOverlayActivity();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      if (widget.startInIptvBrowser) {
        _exitLiveBrowserToHome();
      } else {
        _closeLiveIptvOverlay();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openLiveIptvOverlay() {
    if (!widget.isLive || !mounted) return;
    // يسمح بالفتح الخامل (بدون قناة) عند الدخول من قسم Live.
    if (widget.channelLive == null &&
        !widget.startInIptvBrowser &&
        _currentLiveChannel == null) {
      return;
    }
    // Warm live EPG banner before the side panel paints (phone + TV).
    if (AdsService.shouldShowBanner(AppBannerPlacement.liveEpg)) {
      unawaited(AdsService.preloadCompactBanners());
    }
    if (_showLiveIptvOverlay) {
      _prepareLiveIptvOverlayAfterMount();
      return;
    }
    // رجوع من ملء الشاشة بزر OK: KeyUp قد يصل لعقدة القناة المركّزة ويغلق اللوحة فوراً.
    _armIptvIgnoreNextChannelOkUp();
    final idleBrowser =
        widget.startInIptvBrowser &&
        widget.channelLive == null &&
        _currentLiveChannel == null;
    _iptvRequestCategoryFocusAfterNextCatSync = idleBrowser;
    _iptvCancelChannelFocusSchedules();
    // خامل من Live: تركيز الفئات. غير ذلك: تركيز القنوات/التشغيل.
    _iptvOverlayFocusOnChannelsColumn = !idleBrowser;
    _iptvFocusPlayingChannelAfterChannelSync = !idleBrowser;
    // ثبّت فئة القناة المشغّلة قبل أول رسم (تجنّب ظهور الفئة الأولى).
    _iptvRestoreActiveCategoryForOverlay(idleBrowser: idleBrowser);
    // Disable brightness/volume UI while the side panel is open.
    _clearBvUiForIptvOverlay();
    _resetLiveFullscreenExtras();
    _iptvSurfaceCoverClearTimer?.cancel();
    _iptvSurfaceCoverClearTimer = null;
    // استرجع خانة المصغّر فوراً حتى لا يُزال PlatformView → شاشة فارغة عند الرجوع.
    final cachedSlot = _iptvMiniPlayerSlotRectCache;
    final reuseSlot = cachedSlot != null &&
        _isPlausibleIptvMiniSlotRect(cachedSlot);
    _fvSetState(() {
      _iptvBrowserUiReady = true;
      _showLiveIptvOverlay = true;
      _iptvSurfaceTransitionCover = false;
      _liveBlankSurfaceUntilPlay = false;
      _liveSurfaceCoverForUrl = null;
      if (!_vlcAwaitingNewLiveFrames && !_vlcVideoMutedForSwap) {
        _vlcParkOffscreen = false;
      }
      if (reuseSlot) {
        _iptvMiniPlayerSlotRect = cachedSlot;
      }
    });
    _ensureLivePlaybackIsPlaying();
    _scheduleIptvMiniPlayerSlotMeasure();
    _exoLastFitSize = Size.zero;
    _vlcLastLayoutSize = Size.zero;
    if (_useExo) {
      _scheduleExoSurfaceFit();
    }
    _prepareLiveIptvOverlayContent(idleBrowser: idleBrowser);
  }

  /// تهيئة المحتوى/التركيز بعد أن تكون الواجهة ظاهرة (دخول سلس من قسم Live).
  void _prepareLiveIptvOverlayAfterMount() {
    if (!mounted || !_showLiveIptvOverlay) return;
    final idleBrowser =
        widget.startInIptvBrowser &&
        widget.channelLive == null &&
        _currentLiveChannel == null;
    _clearBvUiForIptvOverlay();
    _prepareLiveIptvOverlayContent(idleBrowser: idleBrowser);
  }

  /// دخول خامل من قسم Live: إطاران ثابتان ثم كشف اللوحة تدريجياً بدون تقطيع.
  void _scheduleIdleLiveBrowserReveal() {
    if (!mounted) return;
    _iptvBrowserUiReadyTimer?.cancel();
    // حضّر البيانات بصمت قبل أول رسم ثقيل.
    _prefetchLiveIptvPanelData(preferSilentCache: true);
    _iptvSeedCategoryMetaFromCache();

    void reveal() {
      if (!mounted) return;
      if (_iptvBrowserUiReady) {
        _prepareLiveIptvOverlayAfterMount();
        return;
      }
      _fvSetState(() => _iptvBrowserUiReady = true);
      // انتظر إطار تركيب اللوحة ثم ركّز/قِس بدون ضغط أول فتح.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showLiveIptvOverlay) return;
        _prepareLiveIptvOverlayAfterMount();
      });
    }

    // إطار 1 بعد التركيب الحالي، ثم تأخير قصير لإراحة الـ GPU على الأجهزة الضعيفة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _iptvBrowserUiReadyTimer?.cancel();
        _iptvBrowserUiReadyTimer = Timer(
          const Duration(milliseconds: 48),
          reveal,
        );
      });
    });
  }

  /// اختيار فئة اللوحة: القناة المشغّلة → النشطة → الأخيرة → الابتدائية.
  void _iptvRestoreActiveCategoryForOverlay({required bool idleBrowser}) {
    final liveState = context.read<LiveCatyBloc>().state;
    final rawCats = liveState is LiveCatySuccess
        ? liveState.categories
        : <CategoryModel>[];
    final displayCats = _iptvDisplayCategories(rawCats);
    final playingCatId = _iptvPlayingCategoryId()?.trim();
    final activeId = _iptvActiveCategoryId?.trim();
    final lastLiveId =
        context.read<ChannelsBloc>().lastLiveCategoryId?.trim();
    final initialId = widget.initialLiveCategoryId?.trim();

    bool inDisplay(String? id) {
      if (id == null || id.isEmpty || displayCats.isEmpty) return false;
      return displayCats.any((c) => c.categoryId == id);
    }

    String? nextId;
    if (!idleBrowser && inDisplay(playingCatId)) {
      nextId = playingCatId;
    } else if (inDisplay(activeId)) {
      // احتفظ بالفئة اللي اختارها المستخدم حتى فـ idle browser
      // (ما نرجّعوش لأوّل فئة ملي كتعاود تتفتح اللوحة).
      nextId = activeId;
    } else if (!idleBrowser && inDisplay(lastLiveId)) {
      nextId = lastLiveId;
    } else if (inDisplay(initialId)) {
      nextId = initialId;
    } else if (displayCats.isNotEmpty) {
      // Idle / fallback: أول فئة بعد المثبتة حسب ترتيب المستخدم (مش ترتيب السيرفر).
      nextId = displayCats
          .skip(_iptvPinnedLiveCategoryCount)
          .map((c) => c.categoryId)
          .firstWhere(
            (id) => id != null && id.isNotEmpty,
            orElse: () => displayCats.first.categoryId,
          );
    }
    if (nextId != null && nextId.isNotEmpty) {
      _iptvActiveCategoryId = nextId;
    }
    if (displayCats.isNotEmpty) {
      _iptvLastCategoryFocusIndex = _iptvCategoryIndexForId(
        _iptvActiveCategoryId,
        displayCats,
      ).clamp(0, displayCats.length - 1);
    }
  }

  void _prepareLiveIptvOverlayContent({required bool idleBrowser}) {
    unawaited(_applyPlaybackVolumeForIptvOverlay(ducked: true));
    _touchLiveIptvOverlayActivity();
    _attachIptvFocusSafetyListener();

    _iptvRestoreActiveCategoryForOverlay(idleBrowser: idleBrowser);

    _prefetchLiveIptvPanelData(preferSilentCache: idleBrowser);
    _iptvSeedCategoryMetaFromCache();
    // أجّل تدفئة الميتا حتى يستقر أول رسم للوحة (مهم للأجهزة الضعيفة).
    if (idleBrowser) {
      _iptvMetaPrefetchDelayTimer?.cancel();
      _iptvMetaPrefetchDelayTimer = Timer(const Duration(milliseconds: 450), () {
        if (!mounted || !_showLiveIptvOverlay) return;
        unawaited(_iptvPrefetchUncachedCategoryMeta());
      });
    } else {
      unawaited(_iptvPrefetchUncachedCategoryMeta());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showLiveIptvOverlay || !_iptvBrowserUiReady) return;
      // أظهر الفئة الحالية في قائمة الفئات فوراً (مع إعادة محاولة الربط).
      _scrollIptvActiveCategoryIntoView();
      if (idleBrowser) {
        _iptvFocusPreferredCategory();
      } else {
        _iptvFocusPreferredChannel();
      }
      _ensurePlaybackContinuesForIptvOverlay();
      _scheduleIptvMiniPlayerSlotMeasure();
    });
  }

  void _ensurePlaybackContinuesForIptvOverlay() {
    _ensureLivePlaybackIsPlaying();
  }

  /// يضمن استمرار تشغيل البث (لوحة IPTV أو ملء الشاشة) ما لم يطلب المستخدم إيقافاً.
  /// مطابق للمشروع المرجعي — بدون حراسة zap/busy تمنع التشغيل بعد قناة ميتة.
  void _ensureLivePlaybackIsPlaying() {
    if (!mounted || !widget.isLive || _userRequestedLivePause) return;
    try {
      if (_useExo) {
        final bp = _exoController;
        final playing = bp?.videoPlayerController?.value.isPlaying ?? isPlayed;
        if (bp != null && !playing) {
          bp.play();
          isPlayed = true;
        }
      } else {
        final vc = _videoPlayerController;
        if (vc != null && vc.value.isInitialized && !vc.value.isPlaying) {
          unawaited(vc.play());
          isPlayed = true;
        }
      }
    } catch (_) {}
  }

  void _closeLiveIptvOverlay() {
    if (!_showLiveIptvOverlay) return;
    if (_iptvConsumeBackForCategoryReorder()) return;
    _iptvRememberPickCategory();
    _iptvClearCategoryReorderTimers();
    _iptvTvReorderWorkingIds = null;
    _iptvTvReorderIndex = null;
    _channelSwitchDebounce?.cancel();
    _channelSwitchDebounce = null;
    // Keep pending zap if user closed panel mid-debounce; cancel only on leave.
    _iptvOverlayIdleTimer?.cancel();
    _iptvOverlayIdleTimer = null;
    _iptvMetaSetStateTimer?.cancel();
    _iptvMetaSetStateTimer = null;
    _iptvMetaPrefetchDelayTimer?.cancel();
    _iptvMetaPrefetchDelayTimer = null;
    _iptvBrowserUiReadyTimer?.cancel();
    _iptvBrowserUiReadyTimer = null;
    _iptvCancelCategoryCommit();
    _detachIptvFocusSafetyListener();
    _iptvChannelFocusBoundCategoryId = null;
    _iptvRequestCategoryFocusAfterNextCatSync = false;
    _iptvFocusPlayingChannelAfterChannelSync = false;
    _iptvFocusMoveToChannelsPending = false;
    _iptvOverlayFocusOnChannelsColumn = false;
    _iptvOverlayFocusOnMiniPlayer = false;
    _iptvMetaPrefetchStarted = false;
    _iptvCancelChannelFocusSchedules();
    _iptvCancelMiniPlayerFocusSchedules();
    // إغلاق اللوحة: بلا mute/park لـ VLC — الصورة تبقى ظاهرة.
    _iptvSurfaceCoverClearTimer?.cancel();
    _iptvSurfaceTransitionCover = false;
    _liveBlankSurfaceUntilPlay = false;
    _vlcParkOffscreen = false;
    _vlcAwaitingNewLiveFrames = false;
    _vlcVideoMutedForSwap = false;
    _fvSetState(() {
      _showLiveIptvOverlay = false;
      // احفظ القياس قبل المسح — يُستعمل عند الرجوع من fullscreen.
      if (_iptvMiniPlayerSlotRect != null &&
          _isPlausibleIptvMiniSlotRect(_iptvMiniPlayerSlotRect!)) {
        _iptvMiniPlayerSlotRectCache = _iptvMiniPlayerSlotRect;
      }
      _iptvMiniPlayerSlotRect = null;
      showControllersVideo = true;
      _iptvSurfaceTransitionCover = false;
      _liveBlankSurfaceUntilPlay = false;
      _vlcParkOffscreen = false;
    });
    if (_useExo && _isSwitchingLiveChannel) {
      _iptvSurfaceTransitionCover = true;
      _armLiveSurfaceCoverClear();
    }
    _iptvTvSearchKeyboardOpen = false;
    _iptvOverlayFocusNode.unfocus();
    _iptvMiniPlayerFocusNode.unfocus();
    _disposeIptvItemFocusNodes(deferUntilNextFrame: true);
    unawaited(_applyPlaybackVolumeForIptvOverlay(ducked: false));
    _ensureLivePlaybackIsPlaying();
    _exoLastFitSize = Size.zero;
    _vlcLastFitSize = Size.zero;
    _vlcLastLayoutSize = Size.zero;
    if (_useExo) {
      _scheduleExoSurfaceFit();
    } else {
      _scheduleVlcSurfaceFit(bumpLayout: true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _showLiveIptvOverlay) return;
      _exoLastFitSize = Size.zero;
      _vlcLastLayoutSize = Size.zero;
      if (_useExo) {
        _scheduleExoSurfaceFit();
      } else if (!_vlcParkOffscreen) {
        _vlcLastFitSize = Size.zero;
        _scheduleVlcSurfaceFit(bumpLayout: true);
      }
    });
    _requestLivePlayButtonFocus();
    unawaited(_showLiveHintOnce());
    if (showControllersVideo) {
      _schedulePlayerControlsHideAfterIdle();
    }
  }

  void _exitLiveBrowserToHome() {
    if (_exitingIdleLive) return;
    if (_iptvConsumeBackForCategoryReorder()) return;
    _exitingIdleLive = true;
    _iptvCancelChannelFocusSchedules();
    _detachIptvFocusSafetyListener();
    _channelSwitchDebounce?.cancel();
    _channelSwitchDebounce = null;
    _liveChannelSwitchDebounce?.cancel();
    _liveChannelSwitchDebounce = null;

    void goHome() {
      try {
        if (Get.currentRoute == screenWelcome) return;
        // المكدس المتوقع: Welcome → FullVideoLiveBrowser
        if (Navigator.of(context).canPop()) {
          Get.back();
          return;
        }
        Get.until(
          (route) => route.settings.name == screenWelcome || route.isFirst,
        );
        if (Get.currentRoute != screenWelcome) {
          Get.offAllNamed(screenWelcome);
        }
      } catch (_) {
        try {
          Get.offAllNamed(screenWelcome);
        } catch (_) {}
      }
    }

    // Stop stream completely, then leave — never leave playback running muted.
    unawaited(() async {
      try {
        await _haltAllPlaybackForLeave().timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      } catch (_) {}
      goHome();
    }());
  }
}
