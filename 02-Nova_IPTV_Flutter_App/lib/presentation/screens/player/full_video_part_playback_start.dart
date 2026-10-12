part of '../screens.dart';

extension _FullVideoPlaybackStart on _FullVideoScreenState {
  // ---------------------------------------------------------------------------
  // Player init helpers
  // ---------------------------------------------------------------------------
  void _initPlayerAfterFirstFrame() {
    WidgetsBinding.instance.addPostFrameCallback((callback) {
      if (!mounted) return;
      unawaited(_startPlayback(widget.link));
    });
  }

  Future<void> _startPlayback(String url) async {
    _beginNewPlaybackSession(url);
    _liveAudioUseDefault = true;
    if (!mounted) return;
    // iOS: VLC دائماً. Android VOD: Exo فقط. Android live: إعدادات المستخدم.
    if (Platform.isIOS) {
      _currentPlayer = AppVideoPlayer.vlc;
    } else if (!widget.isLive) {
      _currentPlayer = AppVideoPlayer.exo;
    }
    final useVlc = _currentPlayer == AppVideoPlayer.vlc;

    // زاب سلس: إلا VLC كيلعب فعلاً → soft setMedia (بحال Exo setupDataSource).
    // بعد قناة ميتة (!isPlaying) → كنترولر جديد (إصلاح الـ poison).
    if (useVlc && widget.isLive && _vlcIsActuallyPlaying()) {
      _disposeExoSafely();
      _stopLiveKeepAliveWatchdog();
      if (mounted) {
        _fvSetState(() {
          progress = false;
          _isVlcBuffering = false;
          _vlcParkOffscreen = true;
          _iptvSurfaceTransitionCover = true;
          _vlcVideoMutedForSwap = false;
          _vlcAwaitingNewLiveFrames = false;
        });
      }
      if (!mounted) return;
      await _playVlcUrl(url);
      return;
    }

    if (!widget.isLive) {
      _resetVlcLiveSwapPipeline();
    } else if (useVlc) {
      _vlcParkOffscreen = true;
      _iptvSurfaceTransitionCover = true;
      _vlcVideoMutedForSwap = false;
      _vlcAwaitingNewLiveFrames = false;
    }
    _fvSetState(_resetPlaybackUiState);
    if (widget.isLive && useVlc && mounted) {
      _vlcParkOffscreen = true;
      _iptvSurfaceTransitionCover = true;
      progress = false;
    }
    if (useVlc) {
      final hadExoController = _exoController != null;
      _disposeExoSafely();
      _stopLiveKeepAliveWatchdog();
      if (widget.isLive && hadExoController) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (!mounted) return;
      await _playVlcUrl(url);
    } else {
      _stopLiveKeepAliveWatchdog();
      final hadVlcController = _videoPlayerController != null;
      await _disposeVlcSafely();
      if (widget.isLive && hadVlcController) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (!mounted) return;
      await _playExoUrl(url);
    }
  }

  /// أفلام/مسلسلات (VLC): networkCaching خفيف + start-time عند الاستكمال.
  /// البث: كاش adaptive حسب السيرفر.
  VlcPlayerController _createVlcController(String url, {bool forLive = false}) {
    final resumeSec = _effectiveResumeSeekSeconds;
    final hasResume = !forLive && resumeSec != null && resumeSec > 0;
    final autoPlay = !_awaitingResumeChoice;

    if (!forLive) {
      final styleExtras = SubtitleAppearanceService.instance
          .load()
          .toVlcFreetypeExtras();
      final extras = <String>[
        if (hasResume) ':start-time=${resumeSec.floor()}',
        ...styleExtras,
      ];
      return VlcPlayerController.network(
        url,
        hwAcc: HwAcc.full,
        autoPlay: autoPlay,
        autoInitialize: true,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([
            VlcAdvancedOptions.networkCaching(1500),
          ]),
          extras: extras.isEmpty ? null : extras,
        ),
      );
    }

    // بث: كاش أقرب لـ Exo (1000ms) — أخف على الأجهزة الضعيفة مع إقلاع أسرع.
    return VlcPlayerController.network(
      url,
      hwAcc: HwAcc.full,
      autoPlay: autoPlay,
      autoInitialize: true,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions([
          VlcAdvancedOptions.networkCaching(1500),
          VlcAdvancedOptions.liveCaching(1500),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Live channel switch
  // ---------------------------------------------------------------------------
  void _drainPendingLiveChannelSwitch() {
    if (!mounted) return;
    final ch = _pendingLiveChannel;
    final link = _pendingLiveLink;
    if (ch == null || link == null) return;
    // مثل المرجع: حتى لو الرابط نفسه عالق، pending الجديد يُصرَّف بعد timeout.
    if (link == _currentPlaybackUrl) {
      _pendingLiveChannel = null;
      _pendingLiveLink = null;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Pending already holds latest; commit without re-debounce.
      unawaited(_commitLiveChannelSwitch());
    });
  }

  bool get _liveZapInFlight =>
      _isSwitchingLiveChannel ||
      _pendingLiveLink != null ||
      (_liveChannelSwitchDebounce?.isActive ?? false);

  String? _liveZapCategoryId() {
    final pick = _iptvPickCategoryId?.trim();
    if (pick != null && pick.isNotEmpty) return pick;
    final active = _iptvActiveCategoryId?.trim();
    if (active != null && active.isNotEmpty) return active;
    return _iptvPlayingCategoryId();
  }

  List<ChannelLive> _liveZapChannelList() {
    if (!mounted || !widget.isLive) return const [];
    final id = _liveZapCategoryId() ?? '';
    if (id.isEmpty) return const [];
    final parental = ParentalControlService.instance;
    final catState = context.read<LiveCatyBloc>().state;
    final cats = catState is LiveCatySuccess
        ? catState.categories
        : const <CategoryModel>[];
    String? categoryName(String? categoryId) =>
        ParentalControlService.categoryNameFromId(categoryId, cats);
    if (_iptvIsFavoritesCategory(id)) {
      return parental.filterAdultLiveChannels(
        context.read<FavoritesCubit>().state.lives,
        categoryNameForId: categoryName,
      );
    }
    if (_iptvIsRecentlyWatchedCategory(id)) {
      _iptvEnsureRecentlyWatchedLoaded();
      return parental.filterAdultLiveChannels(
        _iptvRecentlyWatched,
        categoryNameForId: categoryName,
      );
    }
    final list =
        context.read<ChannelsBloc>().liveListForCategoryId(id) ??
        const <ChannelLive>[];
    return parental.filterAdultLiveChannels(
      list,
      categoryNameForId: categoryName,
    );
  }

  int _liveZapCurrentIndex() {
    final list = _liveZapChannelList();
    if (list.isEmpty) return -1;
    final current = _currentLiveChannel ?? widget.channelLive;
    if (current == null) return -1;
    return list.indexWhere((c) => liveChannelsMatch(c, current));
  }

  bool _liveZapCanMove(int delta) {
    final list = _liveZapChannelList();
    final ix = _liveZapCurrentIndex();
    if (ix < 0) return false;
    final next = ix + delta;
    return next >= 0 && next < list.length;
  }

  Future<void> _zapLiveChannelByDelta(int delta) async {
    if (!mounted || !widget.isLive || _showLiveIptvOverlay) return;
    final list = _liveZapChannelList();
    final ix = _liveZapCurrentIndex();
    if (ix < 0) return;
    final next = ix + delta;
    if (next < 0 || next >= list.length) return;
    final ch = list[next];
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthSuccess) return;
    final link = _buildLiveStreamLink(ch, auth.user);
    if (link.isEmpty) return;
    _hideLiveStreamInfoBar();
    if (!showControllersVideo) {
      _fvSetState(() => showControllersVideo = true);
    }
    _touchPlayerControlsActivity();
    await _switchToLiveChannel(ch, link);
  }

  Future<void> _switchToLiveChannel(ChannelLive channel, String link) async {
    if (!mounted) return;
    final parental = ParentalControlService.instance;
    final catState = context.read<LiveCatyBloc>().state;
    final cats = catState is LiveCatySuccess
        ? catState.categories
        : const <CategoryModel>[];
    final categoryName = ParentalControlService.categoryNameFromId(
      channel.categoryId,
      cats,
    );
    if (parental.isAdultLiveChannel(channel, categoryName: categoryName)) {
      final ok = await parental.requestAdultContentAccess(context);
      if (!ok || !mounted) return;
    }
    _iptvRememberPickCategory();
    if (_currentPlaybackUrl == link &&
        !_isSwitchingLiveChannel &&
        _isLivePlaybackHealthy()) {
      return;
    }

    // Debounce: only the last selected channel is loaded.
    _pendingLiveChannel = channel;
    _pendingLiveLink = link;
    _vlcLiveReconnectTimer?.cancel();
    _vlcLiveReconnectTimer = null;

    // عنوان/تحميل فوري في المشغّل — بلا انتظار قطع القناة الميتة.
    if (mounted) {
      _fvSetState(() {
        _currentLiveChannel = channel;
        _currentProgram = null;
        _nextProgram = null;
        if (_useExo) progress = true;
      });
    }

    // إلا كان تبديل عالق على قناة ميتة: أبطله فوراً وابدأ الجديد.
    var commitNow = false;
    if (_isSwitchingLiveChannel) {
      _preemptHungLiveChannelSwitch();
      commitNow = true;
    }

    final debounce =
        _useExo ? _kLiveChannelSwitchDebounceExo : _kLiveChannelSwitchDebounceVlc;
    _liveChannelSwitchDebounce?.cancel();
    _liveChannelSwitchDebounce = Timer(
      commitNow ? Duration.zero : debounce,
      () {
        if (!mounted) return;
        unawaited(_commitLiveChannelSwitch());
      },
    );
  }

  /// يبطل commit/reconnect عالق (قناة ميتة) باش الزاب الجديد يبدا sur place.
  void _preemptHungLiveChannelSwitch() {
    _liveSwitchGeneration++;
    _isSwitchingLiveChannel = false;
    _vlcLiveReconnectBusy = false;
    _vlcLiveMediaSwapBusy = false;
    _exoLiveCandidateRetryBusy = false;
    _exoStallConfirmTicks = 0;
    _exoBufferStarveSince = null;
    _exoStartTimeoutTimer?.cancel();
    _exoStartTimeoutTimer = null;
    _cancelLiveNeverHealthyFallbackTimer();
    _stopLiveKeepAliveWatchdog();
    _vlcLiveReconnectTimer?.cancel();
    _vlcLiveReconnectTimer = null;
    _activeSessionId++;
    _currentPlaybackUrl = '';
    if (_useExo) {
      _disposeExoSafely();
    }
  }

  /// يقطع ارتباط البث الحالي (رابط + HTTP) قبل تشغيل قناة جديدة.
  /// [forceDispose] = true عندما القناة القديمة ميتة/عالقة.
  Future<void> _severCurrentLiveConnection({
    required bool forceDispose,
  }) async {
    _cancelLiveNeverHealthyFallbackTimer();
    _stopLiveKeepAliveWatchdog();
    _vlcLiveReconnectTimer?.cancel();
    _vlcLiveReconnectTimer = null;
    _vlcLiveReconnectBusy = false;
    _vlcLiveMediaSwapBusy = false;
    _exoStartTimeoutTimer?.cancel();
    _exoStartTimeoutTimer = null;
    _exoLiveCandidateRetryBusy = false;
    // أبطل أي startPlayback/reconnect ما زال يعمل على الرابط القديم.
    _activeSessionId++;
    // امسح الرابط الميت فوراً حتى لا يلتقطه reconnect بعد bump الجلسة.
    _currentPlaybackUrl = '';

    if (!_useExo) {
      // مثل Exo: إلا البث سليم (كيلعب) ما نمسّحوش — soft setMedia.
      // بعد قناة ميتة / !isPlaying → dispose (إصلاح poison).
      if (!forceDispose && _vlcIsActuallyPlaying()) return;
      await _disposeVlcSafely();
      try {
        await _awaitLiveSocketRelease();
      } catch (_) { /* ignore */ }
      return;
    }

    // Exo: لا await على pause — القناة الميتة كتعلّق pause وتمنع الزاب.
    if (forceDispose || _exoController == null || !_isLivePlaybackHealthy()) {
      _disposeExoSafely();
      try {
        await _awaitLiveSocketRelease();
      } catch (_) { /* ignore */ }
      return;
    }

    final ctrl = _exoController;
    if (ctrl != null) {
      try {
        await ctrl.pause();
      } catch (_) { /* ignore */ }
      try {
        await ctrl.setVolume(0);
      } catch (_) { /* ignore */ }
    }
  }

  /// Exo: إعادة إنشاء عند فشل الإقلاع.
  Future<void> _coldRestartExoLive(String url) async {
    if (!mounted || !widget.isLive || url.isEmpty || !_useExo) return;
    final sessionId = _beginNewPlaybackSession(url);
    _disposeExoSafely();
    try {
      await _awaitLiveSocketRelease();
    } catch (_) { /* ignore */ }
    if (!mounted || sessionId != _activeSessionId) return;
    await _playExoUrl(url);
  }

  /// VLC: نفس `_coldRestartExoLive` حرفياً.
  Future<void> _coldRestartVlcLive(String url) async {
    if (!mounted || !widget.isLive || url.isEmpty || _useExo) return;
    final sessionId = _beginNewPlaybackSession(url);
    await _disposeVlcSafely();
    try {
      await _awaitLiveSocketRelease();
    } catch (_) { /* ignore */ }
    if (!mounted || sessionId != _activeSessionId) return;
    await _playVlcUrl(url);
  }

  Future<void> _commitLiveChannelSwitch() async {
    if (!mounted) return;
    final channel = _pendingLiveChannel;
    final link = _pendingLiveLink;
    if (channel == null || link == null) return;

    // تبديل عالق: أبطله وصرّف الـ pending فوراً (ما نستناوش 9ث).
    if (_isSwitchingLiveChannel) {
      _preemptHungLiveChannelSwitch();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_commitLiveChannelSwitch());
      });
      return;
    }

    if (_currentPlaybackUrl == link && _isLivePlaybackHealthy()) {
      _pendingLiveChannel = null;
      _pendingLiveLink = null;
      if (mounted) {
        _setProgressSafe(false);
        if (!_useExo) _vlcAwaitingNewLiveFrames = false;
        if (_iptvSurfaceTransitionCover ||
            _liveBlankSurfaceUntilPlay ||
            _vlcParkOffscreen) {
          if (_useExo) {
            _fvSetState(() {
              _iptvSurfaceTransitionCover = false;
              _liveBlankSurfaceUntilPlay = false;
              _liveSurfaceCoverForUrl = null;
            });
          } else {
            _armLiveSurfaceCoverClear();
          }
        }
      }
      return;
    }

    final gen = ++_liveSwitchGeneration;

    // أقفل الزاب فوراً قبل أي await — وإلا reconnect القناة الميتة يسرق الجلسة.
    _isSwitchingLiveChannel = true;
    _vlcLiveReconnectTimer?.cancel();
    _vlcLiveReconnectTimer = null;
    _cancelLiveNeverHealthyFallbackTimer();
    _stopLiveKeepAliveWatchdog();
    _exoStartTimeoutTimer?.cancel();
    _exoStartTimeoutTimer = null;
    _exoLiveCandidateRetryBusy = false;
    _exoStallConfirmTicks = 0;
    _exoBufferStarveSince = null;

    _pendingLiveChannel = null;
    _pendingLiveLink = null;

    _iptvSurfaceCoverClearTimer?.cancel();
    _vlcLiveMediaSwapBusy = false;

    // واجهة فورية قبل قطع المصدر — العنوان ما يبقاش على القناة الميتة.
    _fvSetState(() {
      _currentLiveChannel = channel;
      _currentProgram = null;
      _nextProgram = null;
      if (_useExo) {
        progress = true;
      } else {
        progress = false;
        _iptvSurfaceTransitionCover = true;
        _liveBlankSurfaceUntilPlay = false;
        _vlcParkOffscreen = true;
        _vlcAwaitingNewLiveFrames = false;
        _vlcVideoMutedForSwap = false;
      }
      _isVlcBuffering = false;
      isPlayed = true;
    });

    // Exo: ديما dispose. VLC: dispose غير إلا ما كيلعبش (قناة ميتة/عالقة).
    await _severCurrentLiveConnection(
      forceDispose: _useExo || !_vlcIsActuallyPlaying(),
    );
    if (!mounted || gen != _liveSwitchGeneration) return;

    if (widget.startInIptvBrowser) {
      PlaybackWakelockService.instance
          .acquire(title: channel.name ?? widget.title, isLive: true)
          .ignore();
    } else {
      PlaybackWakelockService.instance
          .updateTitle(channel.name ?? widget.title)
          .ignore();
    }

    void releaseSwitchLock() {
      if (!mounted || !_isSwitchingLiveChannel) return;
      if (gen != _liveSwitchGeneration) return;
      if (!_useExo) {
        _fvSetState(() {
          _isSwitchingLiveChannel = false;
          progress = false;
          // أبقِ الأسود/park حتى يشتغل البث الجديد.
        });
        _armVlcZapBlankClear();
        _ensureLivePlaybackIsPlaying();
        return;
      }
      final keepCoverBriefly = !_showLiveIptvOverlay;
      _fvSetState(() {
        _isSwitchingLiveChannel = false;
        if (keepCoverBriefly) {
          _iptvSurfaceTransitionCover = true;
        }
      });
      if (keepCoverBriefly) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _showLiveIptvOverlay) return;
          if (gen != _liveSwitchGeneration) return;
          _ensureLivePlaybackIsPlaying();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _showLiveIptvOverlay) return;
            if (gen != _liveSwitchGeneration) return;
            if (_iptvSurfaceTransitionCover) {
              _fvSetState(() => _iptvSurfaceTransitionCover = false);
            }
            _ensureLivePlaybackIsPlaying();
          });
        });
      } else {
        _ensureLivePlaybackIsPlaying();
      }
    }

    try {
      // مهلة قصيرة: إلا علقت القناة الميتة نحرّرو القفل ونصرّفو pending.
      await _startPlayback(link).timeout(
        _kLiveChannelSwitchTimeout,
        onTimeout: () {},
      );
      if (gen != _liveSwitchGeneration) return;
      // Exo و VLC نفس الشيء: إلا ما صابش صحة بعد الإقلاع → cold restart.
      if (mounted &&
          _activePlaybackUrl == link &&
          !_isLivePlaybackHealthy()) {
        if (_useExo) {
          await _coldRestartExoLive(link);
        } else {
          await _coldRestartVlcLive(link);
        }
      }
    } catch (_) {
    } finally {
      // Always drain when this generation still owns the lock.
      if (gen == _liveSwitchGeneration) {
        releaseSwitchLock();
        if (mounted) {
          _drainPendingLiveChannelSwitch();
        }
      }
    }
    if (!mounted) return;
    if (gen != _liveSwitchGeneration) return;
    if (_activePlaybackUrl != link) return;
    _persistLastLiveChannel(channel: channel, link: link);
    _loadLiveEpg();
  }

  void _persistLastLiveChannel({ChannelLive? channel, String? link}) {
    if (!widget.isLive || !LastLiveChannelService.isEnabled) return;
    final ch = channel ?? _currentLiveChannel ?? widget.channelLive;
    final streamLink = (link ?? _currentPlaybackUrl).trim().isNotEmpty
        ? (link ?? _currentPlaybackUrl).trim()
        : widget.link.trim();
    if (ch == null || streamLink.isEmpty) return;
    final categoryId =
        _iptvActiveCategoryId ?? widget.initialLiveCategoryId ?? ch.categoryId;
    LastLiveChannelService.save(
      channel: ch,
      link: streamLink,
      categoryId: categoryId,
    );
  }

  void _liveWatchCancelTimer() {
    _liveWatchQualifyTimer?.cancel();
    _liveWatchQualifyTimer = null;
  }

  void _liveWatchFlushSegment() {
    final start = _liveWatchSegmentStart;
    if (start == null) return;
    _liveWatchAccumulated += DateTime.now().difference(start);
    _liveWatchSegmentStart = null;
  }

  void _liveWatchQualifyNow() {
    final ch = _liveWatchTrackedChannel;
    if (ch == null || _liveWatchQualified) return;
    if (!_liveWatchSawRealProgress) return;
    final sid = (ch.streamId ?? '').trim();
    if (sid.isEmpty) return;
    _liveWatchQualified = true;
    _liveWatchCancelTimer();
    _iptvEnsureRecentlyWatchedLoaded();
    _iptvRecentlyWatched = LiveRecentlyWatchedStore.record(
      _liveCategoryOrderAccountId(),
      ch,
      current: _iptvRecentlyWatched,
    );
    if (!mounted) return;
    if (_showLiveIptvOverlay &&
        _iptvIsRecentlyWatchedCategory(_iptvActiveCategoryId)) {
      _iptvResyncChannelFocusNodes(
        _iptvRecentlyWatched,
        categoryKey: kIptvRecentlyWatchedCategoryId,
      );
    }
    _fvSetState(() {});
  }

  void _liveWatchBegin(ChannelLive ch) {
    _liveWatchEnd(qualifyIfDue: true);
    final sid = (ch.streamId ?? '').trim();
    if (sid.isEmpty) return;
    _liveWatchTrackedChannel = ch;
    _liveWatchAccumulated = Duration.zero;
    _liveWatchQualified = false;
    _liveWatchSawRealProgress = false;
    _liveWatchSegmentStart = null;
  }

  void _liveWatchEnd({required bool qualifyIfDue}) {
    _liveWatchFlushSegment();
    _liveWatchCancelTimer();
    if (qualifyIfDue &&
        !_liveWatchQualified &&
        _liveWatchSawRealProgress &&
        _liveWatchTrackedChannel != null &&
        _liveWatchAccumulated >= _kLiveWatchQualifyDuration) {
      _liveWatchQualifyNow();
    }
    _liveWatchTrackedChannel = null;
    _liveWatchAccumulated = Duration.zero;
    _liveWatchQualified = false;
    _liveWatchSawRealProgress = false;
    _liveWatchSegmentStart = null;
  }

  void _liveWatchArmTimer() {
    _liveWatchCancelTimer();
    if (_liveWatchQualified ||
        _liveWatchTrackedChannel == null ||
        !_liveWatchSawRealProgress) {
      return;
    }
    final left = _kLiveWatchQualifyDuration - _liveWatchAccumulated;
    if (left <= Duration.zero) {
      _liveWatchQualifyNow();
      return;
    }
    _liveWatchQualifyTimer = Timer(left, () {
      if (!mounted) return;
      _liveWatchFlushSegment();
      if (!_liveWatchSawRealProgress) {
        _liveWatchCancelTimer();
        return;
      }
      if (_liveWatchAccumulated >= _kLiveWatchQualifyDuration) {
        _liveWatchQualifyNow();
        return;
      }
      if (isPlayed && !_isSwitchingLiveChannel && _liveWatchSawRealProgress) {
        _liveWatchSegmentStart = DateTime.now();
        _liveWatchArmTimer();
      }
    });
  }

  void _liveWatchSyncPlaying(bool playing) {
    if (!widget.isLive) return;
    final ch = _currentLiveChannel ?? widget.channelLive;
    if (ch == null) return;
    if (_liveWatchTrackedChannel == null ||
        !liveChannelsMatch(_liveWatchTrackedChannel!, ch)) {
      _liveWatchBegin(ch);
    }
    if (_isSwitchingLiveChannel) {
      _liveWatchFlushSegment();
      _liveWatchCancelTimer();
      return;
    }
    if (playing) {
      if (!_liveWatchSawRealProgress) {
        _liveWatchFlushSegment();
        _liveWatchCancelTimer();
        return;
      }
      if (_liveWatchSegmentStart == null && !_liveWatchQualified) {
        _liveWatchSegmentStart = DateTime.now();
        _liveWatchArmTimer();
      }
    } else {
      _liveWatchFlushSegment();
      _liveWatchCancelTimer();
      if (!_liveWatchQualified &&
          _liveWatchSawRealProgress &&
          _liveWatchAccumulated >= _kLiveWatchQualifyDuration) {
        _liveWatchQualifyNow();
      }
    }
  }

  void _toggleFavoriteForChannel(ChannelLive ch) {
    final favCubit = context.read<FavoritesCubit>();
    final isLiked = favCubit.state.lives.any((l) => liveChannelsMatch(l, ch));
    favCubit.addLive(ch, isAdd: !isLiked);
    _showFavSnackbar(!isLiked);
  }

  void _toggleFavoriteFromKey() {
    final favCubit = context.read<FavoritesCubit>();
    final state = favCubit.state;
    if (widget.channelMovie != null) {
      final ch = widget.channelMovie!;
      final isLiked = state.movies.any((m) => m.streamId == ch.streamId);
      favCubit.addMovie(ch, isAdd: !isLiked);
      _showFavSnackbar(!isLiked);
    } else if (widget.isLive) {
      final ch = _currentLiveChannel ?? widget.channelLive;
      if (ch == null) return;
      _toggleFavoriteForChannel(ch);
    } else if (widget.channelSerie != null) {
      final ch = widget.channelSerie!;
      final isLiked = state.series.any((s) => s.seriesId == ch.seriesId);
      favCubit.addSerie(ch, isAdd: !isLiked);
      _showFavSnackbar(!isLiked);
    }
  }

  Future<void> _settingPage() async {
    await _initBrightnessVolumeLevels();
  }

  void _onSettingsGearFocusChange() {
    if (_settingsGearFocusNode.hasFocus) {
      _touchPlayerControlsActivity();
    }
  }

  void _onStreamInfoFocusChange() {
    if (_streamInfoFocusNode.hasFocus) {
      _touchPlayerControlsActivity();
    }
  }

  void _onAspectRatioFocusChange() {
    if (_aspectRatioFocusNode.hasFocus) {
      _touchPlayerControlsActivity();
    }
  }

  void _onLiveFavoriteFocusChange() {
    if (_liveFavoriteFocusNode.hasFocus) {
      _touchPlayerControlsActivity();
    }
  }

  void _onVodSeekBarFocusChange() {
    if (_vodSeekBarFocusNode.hasFocus) {
      _touchPlayerControlsActivity();
    }
  }

  void _stopVodSeekBarHoldTimer() {
    _vodSeekBarHoldTimer?.cancel();
    _vodSeekBarHoldTimer = null;
  }

  void _cancelVodSeekBarHoldKeyUpDebounce() {
    _vodSeekBarHoldKeyUpTimer?.cancel();
    _vodSeekBarHoldKeyUpTimer = null;
  }

  void _scheduleVodSeekBarHoldEndAfterKeyUp() {
    _vodSeekBarHoldKeyUpTimer?.cancel();
    _vodSeekBarHoldKeyUpTimer = Timer(_kVodSeekBarHoldKeyUpGrace, () {
      _vodSeekBarHoldKeyUpTimer = null;
      if (!mounted) return;
      _onVodSeekHoldEnded();
      _resetVodSeekBarRapidSteps();
    });
  }

  void _clearVodScrubUiOverride() {
    _vodScrubUiUnlockTimer?.cancel();
    _vodScrubUiUnlockTimer = null;
    _vodScrubPostReleaseUiLock = false;
    _vodScrubUiPositionOverride = null;
    _vodScrubUiDurationOverride = null;
  }

  /// موضع أساس للتقديم النسبي: لا تعتمد على موضع VLC المتأخر أثناء قفزة سابقة.
  Duration _vodSeekBasePosition(Duration playerPos) {
    final override = _vodScrubUiPositionOverride;
    if (override != null) return override;
    if (!widget.isLive && validPosition) {
      final uiPos = Duration(milliseconds: (sliderValue * 1000).round());
      if ((uiPos - playerPos).inMilliseconds.abs() > 700) {
        return uiPos;
      }
    }
    return playerPos;
  }

  void _lockVodSeekUiTo(Duration target, Duration duration) {
    _vodScrubUiPositionOverride = target;
    _vodScrubUiDurationOverride = duration > Duration.zero
        ? duration
        : _vodScrubUiDurationOverride;
    _vodScrubUiUnlockTimer?.cancel();
    // أثناء الضغط المستمر: أبقِ الموضع بدون قفل post-release (حتى لا يُمسَح بالخطأ).
    if (_vodSeekBarHoldActive) {
      _vodScrubPostReleaseUiLock = false;
      _vodScrubUiUnlockTimer = null;
      return;
    }
    _vodScrubPostReleaseUiLock = true;
    final unlockMs = _useExo ? 1200 : 2200;
    _vodScrubUiUnlockTimer = Timer(Duration(milliseconds: unlockMs), () {
      if (!mounted) return;
      if (_vodSeekBarHoldActive) return;
      _clearVodScrubUiOverride();
    });
  }

  /// أطول مدة معروفة للشريط — لا تعتمد على مدة قصيرة عابرة من المشغّل.
  Duration _vodKnownDuration() {
    final playerMs = _readDurationFromController().inMilliseconds;
    final overrideMs = _vodScrubUiDurationOverride?.inMilliseconds ?? 0;
    final maxMs = (_maxDurationSeconds * 1000).round();
    final best = math.max(math.max(playerMs, overrideMs), maxMs);
    if (best > 1000) return Duration(milliseconds: best);
    return Duration.zero;
  }

  /// تحديث الشريط أثناء الضغط المطوّل بدون لمس المشغّل (يمنع تعليق التحميل المسبق).
  void _writeHoldScrubHud(Duration pos, Duration dur) {
    Duration displayDuration = dur;
    if (displayDuration <= Duration.zero && _maxDurationSeconds > 1) {
      displayDuration = Duration(
        milliseconds: (_maxDurationSeconds * 1000).round(),
      );
    }
    final durSec = displayDuration.inMilliseconds / 1000.0;
    if (durSec > _maxDurationSeconds) {
      _maxDurationSeconds = durSec;
    }
    if (displayDuration.inHours == 0) {
      final strPosition = pos.toString().split('.')[0];
      final strDuration = displayDuration.toString().split('.')[0];
      final posParts = strPosition.split(':');
      final durParts = strDuration.split(':');
      position = posParts.length >= 3
          ? '${posParts[1]}:${posParts[2]}'
          : strPosition;
      duration = durParts.length >= 3
          ? '${durParts[1]}:${durParts[2]}'
          : strDuration;
    } else {
      position = pos.toString().split('.')[0];
      duration = displayDuration.toString().split('.')[0];
    }
    final maxSec = _maxDurationSeconds < 1 ? 1.0 : _maxDurationSeconds;
    final posSec = (pos.inMilliseconds / 1000.0).clamp(0.0, maxSec);
    sliderValue = posSec;
    validPosition = maxSec > 1.0;
    // أثناء التمرير: لا تحميل مسبق مرئي — الثانوي ملتصق بالرأس.
    _bufferSeconds = posSec;
  }

  /// مثل المشروع المرجعي: تسارع +3 كل تكة أثناء الضغط المطوّل.
  void _tickVodSeekBarHoldRightStep() {
    _touchPlayerControlsActivity();
    final now = DateTime.now();
    if (_lastVodHoldSeekEmittedAt != null &&
        now.difference(_lastVodHoldSeekEmittedAt!) < _kVodHoldSeekMinInterval) {
      return;
    }
    final isRapidChain =
        _lastRemoteForwardSeekAt != null &&
        now.difference(_lastRemoteForwardSeekAt!) <=
            const Duration(milliseconds: 950);
    if (isRapidChain) {
      _rapidForwardSeekSeconds = (_rapidForwardSeekSeconds + 3).clamp(
        10,
        _kRapidDoubleTapMaxSeekSeconds,
      );
    } else {
      _rapidForwardSeekSeconds = 10;
    }
    _lastRemoteForwardSeekAt = now;
    _seekRelative(_rapidForwardSeekSeconds);
  }

  void _tickVodSeekBarHoldLeftStep() {
    _touchPlayerControlsActivity();
    final now = DateTime.now();
    if (_lastVodHoldSeekEmittedAt != null &&
        now.difference(_lastVodHoldSeekEmittedAt!) < _kVodHoldSeekMinInterval) {
      return;
    }
    final isRapidChain =
        _lastRemoteBackwardSeekAt != null &&
        now.difference(_lastRemoteBackwardSeekAt!) <=
            const Duration(milliseconds: 950);
    if (isRapidChain) {
      _rapidBackwardSeekSeconds = (_rapidBackwardSeekSeconds + 3).clamp(
        10,
        _kRapidDoubleTapMaxSeekSeconds,
      );
    } else {
      _rapidBackwardSeekSeconds = 10;
    }
    _lastRemoteBackwardSeekAt = now;
    _seekRelative(-_rapidBackwardSeekSeconds);
  }

  void _resetVodSeekBarRapidSteps() {
    _rapidForwardSeekSeconds = 10;
    _rapidBackwardSeekSeconds = 10;
    _lastRemoteForwardSeekAt = null;
    _lastRemoteBackwardSeekAt = null;
  }

  /// ضغطة/ضغط مطوّل على شريط التقدّم — واجهة فقط حتى الإفلات المستقر.
  void _beginVodSeekBarDirectionalHold(LogicalKeyboardKey k) {
    if (widget.isLive) return;
    // اسمح بالتمرير حتى أثناء buffering إن كان الشريط جاهزاً.
    if (!_canInteractWithPlayback &&
        !_vodSeekBarHoldActive &&
        _maxDurationSeconds <= 1 &&
        sliderValue <= 0) {
      return;
    }
    final goingRight = k == LogicalKeyboardKey.arrowRight;
    final goingLeft = k == LogicalKeyboardKey.arrowLeft;
    if (!goingRight && !goingLeft) return;
    final dir = goingRight ? 1 : -1;

    _cancelVodSeekBarHoldKeyUpDebounce();

    // KeyDown متكرر بنفس الاتجاه: لا تُعد البذرة من موضع المشغّل.
    if (_vodSeekBarHoldActive && _vodSeekBarHoldDirection == dir) {
      return;
    }

    final alreadyHolding = _vodSeekBarHoldActive;
    if (alreadyHolding && _vodSeekBarHoldDirection != dir) {
      _stopVodSeekBarHoldTimer();
      _resetVodSeekBarRapidSteps();
    }

    _vodSeekBarHoldActive = true;
    _vodSeekBarHoldDirection = dir;
    _lastVodHoldSeekEmittedAt = null;

    // بذرة واحدة فقط عند بدء السحب — لا تعِد الكتابة فوق هدف UI عند تغيير الاتجاه.
    if (!alreadyHolding) {
      final seedPos =
          _vodScrubUiPositionOverride ??
          Duration(milliseconds: (sliderValue * 1000).round());
      final seedDur = _vodKnownDuration();
      _vodScrubUiPositionOverride = seedPos;
      if (seedDur > Duration.zero) {
        _vodScrubUiDurationOverride = seedDur;
        final sec = seedDur.inMilliseconds / 1000.0;
        if (sec > _maxDurationSeconds) _maxDurationSeconds = sec;
      }
      _writeHoldScrubHud(seedPos, seedDur);
    }
    _setBufferingUi(false);

    if (!_vodScrubPausedPlayback) {
      _wasPlayingBeforeVodScrub = isPlayed;
      if (_wasPlayingBeforeVodScrub) {
        if (_useExo) {
          _exoController?.pause();
        } else {
          _videoPlayerController?.pause();
        }
        _vodScrubPausedPlayback = true;
      }
    }

    _stopVodSeekBarHoldTimer();
    if (goingLeft) {
      _consumeVodSeekBarArrowKeys(k);
      _vodSeekBarHoldTimer = Timer.periodic(_kVodSeekBarHoldInterval, (_) {
        if (!mounted || !_vodSeekBarHoldActive) return;
        _tickVodSeekBarHoldLeftStep();
      });
    } else {
      _consumeVodSeekBarArrowKeys(k);
      _vodSeekBarHoldTimer = Timer.periodic(_kVodSeekBarHoldInterval, (_) {
        if (!mounted || !_vodSeekBarHoldActive) return;
        _tickVodSeekBarHoldRightStep();
      });
    }
  }

  /// سهم يمين/يسار على الشريط: خطوة أولى متصاعدة (+5) ثم المؤقّت (+3).
  KeyEventResult _consumeVodSeekBarArrowKeys(LogicalKeyboardKey key) {
    if (widget.isLive) return KeyEventResult.ignored;
    if (!_canInteractWithPlayback &&
        !_vodSeekBarHoldActive &&
        _maxDurationSeconds <= 1 &&
        sliderValue <= 0) {
      return KeyEventResult.ignored;
    }
    final now = DateTime.now();
    if (key == LogicalKeyboardKey.arrowLeft) {
      _lastRightKeyTime = null;
      _lastRemoteForwardSeekAt = null;
      _lastLeftKeyTime = null;
      final isRapidChain =
          _lastRemoteBackwardSeekAt != null &&
          now.difference(_lastRemoteBackwardSeekAt!) <=
              const Duration(milliseconds: 950);
      if (isRapidChain) {
        _rapidBackwardSeekSeconds = (_rapidBackwardSeekSeconds + 5).clamp(
          10,
          _kRapidDoubleTapMaxSeekSeconds,
        );
      } else {
        _rapidBackwardSeekSeconds = 10;
      }
      _lastRemoteBackwardSeekAt = now;
      _seekRelative(-_rapidBackwardSeekSeconds);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _lastLeftKeyTime = null;
      _lastRemoteBackwardSeekAt = null;
      _rapidBackwardSeekSeconds = 10;
      final isRapidChain =
          _lastRemoteForwardSeekAt != null &&
          now.difference(_lastRemoteForwardSeekAt!) <=
              const Duration(milliseconds: 950);
      if (isRapidChain) {
        _rapidForwardSeekSeconds = (_rapidForwardSeekSeconds + 5).clamp(
          10,
          _kRapidDoubleTapMaxSeekSeconds,
        );
      } else {
        _rapidForwardSeekSeconds = 10;
      }
      _lastRemoteForwardSeekAt = now;
      _seekRelative(_rapidForwardSeekSeconds);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// قفزة VLC موثوقة بدون إبقاء الفيديو على pause بعد التقديم السريع.
  Future<void> _seekVlcAccurate(
    Duration target, {
    required bool resumePlaying,
  }) async {
    final vc = _videoPlayerController;
    if (vc == null || !vc.value.isInitialized) return;
    var t = target;
    final dur = vc.value.duration;
    if (t < Duration.zero) t = Duration.zero;
    if (dur > Duration.zero && t > dur) t = dur;

    if (resumePlaying) {
      _vlcSeekShouldResume = true;
    }
    final token = ++_vlcSeekToken;
    _lockVodSeekUiTo(t, dur);
    try {
      // لا نعمل pause هنا — يسبب بقاء الفيديو متوقفاً عند التقديم المتتالي.
      await vc.seekTo(t);
      if (token != _vlcSeekToken) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || token != _vlcSeekToken) return;
      if (!identical(_videoPlayerController, vc)) return;
      final pos = vc.value.position;
      if ((pos - t).inMilliseconds.abs() > 1200) {
        await vc.seekTo(t);
        if (token != _vlcSeekToken) return;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (!mounted || token != _vlcSeekToken) return;
      if (_vlcSeekShouldResume) {
        try {
          await vc.play();
          isPlayed = true;
        } catch (_) { /* ignore */ }
      }
    } catch (e) {
      if (token != _vlcSeekToken) return;
      try {
        await vc.setTime(t.inMilliseconds);
      } catch (_) { /* ignore */ }
      if (_vlcSeekShouldResume && mounted && token == _vlcSeekToken) {
        try {
          await vc.play();
          isPlayed = true;
        } catch (_) { /* ignore */ }
      }
    }
  }

  /// بعد سلسلة تقديم سريع: تأكيد الاستئناف عندما تهدأ القفزات.
  void _armVlcSeekResume() {
    if (!_vlcSeekShouldResume || _useExo) return;
    _vlcSeekResumeTimer?.cancel();
    _vlcSeekResumeTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || _useExo || !_vlcSeekShouldResume) return;
      if (_awaitingResumeChoice || _vodSeekBarHoldActive) return;
      try {
        _videoPlayerController?.play();
        isPlayed = true;
        if (mounted) _fvSetState(() {});
      } catch (_) { /* ignore */ }
    });
  }

  Duration _readDurationFromController() {
    if (_useExo) {
      return _exoController?.videoPlayerController?.value.duration ??
          Duration.zero;
    }
    final vc = _videoPlayerController;
    if (vc == null || !vc.value.isInitialized) return Duration.zero;
    return vc.value.duration;
  }

  void _maybeSyncVodScrubUiFromPlayerIfCaughtUp(Duration pos) {
    if (_vodSeekBarHoldActive) return;
    if (!_vodScrubPostReleaseUiLock || _vodScrubUiPositionOverride == null) {
      return;
    }
    final t = _vodScrubUiPositionOverride!;
    // VLC على الشبكة يصل غالباً لأقرب keyframe — هامش أوسع من Exo.
    final thresholdMs = _useExo ? 900 : 2200;
    if ((pos.inMilliseconds - t.inMilliseconds).abs() < thresholdMs) {
      _clearVodScrubUiOverride();
    }
  }

  Future<void> _waitForVodScrubPlaybackReadyAfterSeek(
    bool expectPlaying,
  ) async {
    if (!expectPlaying) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final sw = Stopwatch()..start();
    while (mounted && sw.elapsed < const Duration(seconds: 5)) {
      if (_useExo) {
        final c = _exoController?.videoPlayerController;
        if (c != null) {
          final v = c.value;
          if (v.isPlaying && !v.isBuffering) return;
        }
      } else {
        final vc = _videoPlayerController;
        if (vc != null && vc.value.isInitialized) {
          final v = vc.value;
          if (v.isPlaying) {
            if (!v.isBuffering) return;
            if (sw.elapsed > const Duration(milliseconds: 900)) return;
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
  }

  Future<void> _commitVodScrubAfterHoldRelease(
    Duration target,
    Duration? durHint,
    bool savedWasPlaying,
  ) async {
    if (!mounted) return;
    _fvSetState(() => _vodScrubReleaseLoading = true);
    try {
      if (_useExo) {
        await _exoController?.seekTo(target);
      } else {
        await _seekVlcAccurate(target, resumePlaying: false);
      }
      if (!mounted) return;
      final dur = durHint ?? _readDurationFromController();
      _vodScrubPausedPlayback = false;
      _wasPlayingBeforeVodScrub = false;
      _applyPlaybackSnapshot(
        isPlaying: savedWasPlaying,
        positionValue: target,
        durationValue: dur,
      );
      if (savedWasPlaying) {
        if (_useExo) {
          _exoController?.play();
        } else {
          _videoPlayerController?.play();
        }
        await _waitForVodScrubPlaybackReadyAfterSeek(true);
      } else {
        await _waitForVodScrubPlaybackReadyAfterSeek(false);
      }
      if (!mounted) return;
      _lockVodSeekUiTo(target, dur);
    } catch (_) { /* ignore */ } finally {
      if (mounted) {
        _fvSetState(() => _vodScrubReleaseLoading = false);
      }
    }
  }

  void _resumeVodSeekScrubIfNeeded() {
    if (!_vodScrubPausedPlayback) return;
    _vodScrubPausedPlayback = false;
    final resume = _wasPlayingBeforeVodScrub;
    _wasPlayingBeforeVodScrub = false;
    if (!mounted) return;
    if (resume) {
      if (_useExo) {
        _exoController?.play();
      } else {
        _videoPlayerController?.play();
      }
    }
  }

  void _onVodSeekHoldEnded() {
    _cancelVodSeekBarHoldKeyUpDebounce();
    _stopVodSeekBarHoldTimer();
    final wasHold = _vodSeekBarHoldActive;
    final resumeTarget = _vodScrubUiPositionOverride;
    final durSnap = _vodScrubUiDurationOverride ?? _vodKnownDuration();
    final savedWasPlaying = _wasPlayingBeforeVodScrub;
    _vodSeekBarHoldActive = false;
    _vodSeekBarHoldDirection = 0;
    _lastVodHoldSeekEmittedAt = null;

    if (wasHold && !widget.isLive && resumeTarget != null) {
      _vodScrubPostReleaseUiLock = true;
      unawaited(
        _commitVodScrubAfterHoldRelease(resumeTarget, durSnap, savedWasPlaying),
      );
      return;
    }
    _clearVodScrubUiOverride();
    _resumeVodSeekScrubIfNeeded();
  }

  void _ensurePlaybackRunningAfterSeek() {
    if (!_canInteractWithPlayback) return;
    if (_useExo) {
      _exoController?.play();
    } else {
      _videoPlayerController?.play();
    }
  }

  void _cancelPlayerControlsHideTimer() {
    _playerControlsIdleTimer?.cancel();
    _playerControlsIdleTimer = null;
  }

  /// Ã™Å Ã™ÂÃ˜Â¬Ã˜Â¯Ã™Ë†Ã™â€ž Ã˜Â¥Ã˜Â®Ã™ÂÃ˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â²Ã˜Â±Ã˜Â§Ã˜Â± Ã˜Â¨Ã˜Â¹Ã˜Â¯ Ã˜Â®Ã™â€¦Ã™Ë†Ã™â€ž Ã™ÂÃ™â€šÃ˜Â· Ã¢â‚¬â€ Ã˜Â£Ã™Å  Ã˜ÂªÃ™ÂÃ˜Â§Ã˜Â¹Ã™â€ž Ã™Å Ã˜Â³Ã˜ÂªÃ˜Â¯Ã˜Â¹Ã™Å  [_touchPlayerControlsActivity].
  void _schedulePlayerControlsHideAfterIdle() {
    if (!mounted) return;
    _cancelPlayerControlsHideTimer();
    if (_awaitingResumeChoice) return;
    if (!showControllersVideo) return;
    if (_showMovieSuggestionsOverlay ||
        _showEpisodeSuggestionsOverlay ||
        _showLiveChannelSuggestionsOverlay) {
      return;
    }
    if (_showLiveIptvOverlay) return;
    if (_playerOptionSheetOpen) return;

    _playerControlsIdleTimer = Timer(_kPlayerControlsIdleBeforeHide, () {
      if (!mounted) return;
      _playerControlsIdleTimer = null;
      if (_awaitingResumeChoice) return;
      if (!showControllersVideo) return;
      if (_playerOptionSheetOpen) return;
      if (_showMovieSuggestionsOverlay ||
          _showEpisodeSuggestionsOverlay ||
          _showLiveChannelSuggestionsOverlay) {
        return;
      }
      if (_showLiveIptvOverlay) return;
      if (_vodSeekBarHoldActive) {
        _schedulePlayerControlsHideAfterIdle();
        return;
      }
      _onVodSeekHoldEnded();
      _fvSetState(() {
        showControllersVideo = false;
        _dismissBvIntro();
      });
      _releaseToolbarFocusToPlayer();
    });
  }

  /// Ã˜Â£Ã™Å  Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â· Ã™ÂÃ™Å  Ã™Ë†Ã˜Â§Ã˜Â¬Ã™â€¡Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜ÂºÃ™â€˜Ã™â€ž Ã™Å Ã™ÂÃ˜Â¨Ã™â€šÃ™Å  Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â²Ã˜Â±Ã˜Â§Ã˜Â± Ã˜Â¸Ã˜Â§Ã™â€¡Ã˜Â±Ã˜Â© Ã™Ë†Ã™Å Ã˜Â¹Ã™Å Ã˜Â¯ Ã™â€¦Ã˜Â¤Ã™â€šÃ˜Âª Ã˜Â§Ã™â€žÃ˜Â®Ã™â€¦Ã™Ë†Ã™â€ž.
  void _touchPlayerControlsActivity() {
    if (!mounted) return;
    if (!showControllersVideo) return;
    _schedulePlayerControlsHideAfterIdle();
  }
}
