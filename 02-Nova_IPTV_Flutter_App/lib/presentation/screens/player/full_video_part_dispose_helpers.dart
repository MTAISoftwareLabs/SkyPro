part of '../screens.dart';

extension _FullVideoDisposeHelpers on _FullVideoScreenState {
  void _cancelTimersOnDispose() {
    _liveWatchEnd(qualifyIfDue: true);
    _playerControlsIdleTimer?.cancel();
    _playerControlsIdleTimer = null;
    _liveChannelSwitchDebounce?.cancel();
    _liveChannelSwitchDebounce = null;
    _iptvSurfaceCoverClearTimer?.cancel();
    _iptvSurfaceCoverClearTimer = null;
    _vlcSurfaceFitTimer?.cancel();
    _vlcSurfaceFitTimer = null;
    _pendingLiveChannel = null;
    _pendingLiveLink = null;
    _vlcResumeRetryTimer?.cancel();
    _vlcResumeRetryTimer = null;
    _stopLiveKeepAliveWatchdog();
    _seekLoadingTimer?.cancel();
    _seekLoadingTimer = null;
    _okLongPressTimer?.cancel();
    _okLongPressTimer = null;
    _iptvIgnoreChannelOkTimer?.cancel();
    _iptvIgnoreChannelOkTimer = null;
    _iptvIgnoreNextChannelOkUp = false;
    _seekHintTimer?.cancel();
    _seekHintTimer = null;
    _vlcSeekResumeTimer?.cancel();
    _vlcSeekResumeTimer = null;
    _vlcSeekShouldResume = false;
    _epgRefreshTimer?.cancel();
    _epgRefreshTimer = null;
    _movieHintShowTimer?.cancel();
    _movieHintShowTimer = null;
    _movieHintHideTimer?.cancel();
    _movieHintHideTimer = null;
    _liveHintShowTimer?.cancel();
    _liveHintShowTimer = null;
    _liveHintHideTimer?.cancel();
    _liveHintHideTimer = null;
    _liveStreamInfoRefreshTimer?.cancel();
    _liveStreamInfoRefreshTimer = null;
    _liveStreamInfoRefreshBusy = false;
    _resumeSeekTimer1?.cancel();
    _resumeSeekTimer1 = null;
    _resumeSeekTimer2?.cancel();
    _resumeSeekTimer2 = null;
    _warmupResumeSeekTimer?.cancel();
    _warmupResumeSeekTimer = null;
    _resumeCoverReleaseTimer?.cancel();
    _resumeCoverReleaseTimer = null;
    _vodSeekBarHoldKeyUpTimer?.cancel();
    _vodSeekBarHoldKeyUpTimer = null;
    _vodSeekBarHoldTimer?.cancel();
    _vodSeekBarHoldTimer = null;
    _iptvOverlayIdleTimer?.cancel();
    _iptvOverlayIdleTimer = null;
    _iptvMetaSetStateTimer?.cancel();
    _iptvMetaSetStateTimer = null;
    _iptvMetaPrefetchDelayTimer?.cancel();
    _iptvMetaPrefetchDelayTimer = null;
    _iptvBrowserUiReadyTimer?.cancel();
    _iptvBrowserUiReadyTimer = null;
    _iptvCategoryCommitTimer?.cancel();
    _iptvCategoryCommitTimer = null;
    _iptvPendingCategoryId = null;
    _iptvCatReorderLongPressTimer?.cancel();
    _iptvCatReorderLongPressTimer = null;
    _channelSwitchDebounce?.cancel();
    _channelSwitchDebounce = null;
    _cancelVodLockUnlockHold();
    _vodLockBackGraceTimer?.cancel();
    _vodLockBackGraceTimer = null;
    _vodLockBackUnlockedAt = null;
    _unregisterVodLockHardwareHandler();
    _vodLockHintDismissTimer?.cancel();
    _vodLockHintDismissTimer = null;
    _vodLockHintShownAt = null;
    _hideVodLockToast();
    _vodScrubUiUnlockTimer?.cancel();
    _vodScrubUiUnlockTimer = null;
    _vodScrubReleaseLoading = false;
    _onVodSeekHoldEnded();
    _stopPipKeepAlive();
    _bvHideTimer?.cancel();
    _bvHideTimer = null;
  }

  void _disposeFocusNodesOnDispose() {
    _detachIptvFocusSafetyListener();
    _disposeIptvItemFocusNodes();
    _settingsGearFocusNode.removeListener(_onSettingsGearFocusChange);
    _streamInfoFocusNode.removeListener(_onStreamInfoFocusChange);
    _aspectRatioFocusNode.removeListener(_onAspectRatioFocusChange);
    _liveFavoriteFocusNode.removeListener(_onLiveFavoriteFocusChange);
    _vodSeekBarFocusNode.removeListener(_onVodSeekBarFocusChange);
    _overlayFocusNode.dispose();
    _aspectRatioFocusNode.dispose();
    _liveFavoriteFocusNode.dispose();
    _liveBackFocusNode.dispose();
    _liveChannelsListFocusNode.dispose();
    _vodSeekBarFocusNode.dispose();
    _vodBackFocusNode.dispose();
    _vodLockFocusNode.dispose();
    _vodAudioSubsFocusNode.dispose();
    _vodPipFocusNode.dispose();
    _movieOverlayFocusNode.dispose();
    _episodeOverlayFocusNode.dispose();
    _liveChannelOverlayFocusNode.dispose();
    _settingsGearFocusNode.dispose();
    _streamInfoFocusNode.dispose();
    _liveStreamInfoBarVN.dispose();
    _settingsButtonSkipNode.dispose();
    _playButtonFocusNode.dispose();
    _playButtonSkipNode.dispose();
    _iptvOverlayFocusNode.dispose();
    _iptvMiniPlayerFocusNode.dispose();
    _iptvCategorySearchNavFocus.dispose();
    _iptvCategorySearchEditFocus.dispose();
    _iptvCategoriesBackFocusNode.dispose();
    _iptvCategoryScrollController.dispose();
    _iptvChannelScrollController.dispose();
    _rootPlayerFocusNode.dispose();
  }

  void _removeOverlayEntriesOnDispose() {
    try {
      _favOverlayEntry?.remove();
    } catch (_) {}
    _favOverlayEntry = null;

    _hidePlayerInitToast();
    _hideVodLockToast();
    _unregisterVodLockHardwareHandler();
  }

  void _disposePlayersOnDispose() {
    try {
      _exoController?.removeEventsListener(_onExoEvent);
    } catch (_) {}
    if (_exoValueListenerAttached) {
      final exoVc = _exoController?.videoPlayerController;
      if (exoVc != null) {
        try {
          exoVc.removeListener(listener);
        } catch (_) {}
      }
      _exoValueListenerAttached = false;
    }
    final exoCtrl = _exoController;
    _exoController = null;
    try {
      exoCtrl?.dispose();
    } catch (_) {}

    final vc = _videoPlayerController;
    if (vc != null) {
      try {
        vc.removeListener(listener);
      } catch (_) {}
      try {
        if (vc.value.isInitialized) vc.stopRendererScanning();
      } catch (_) {}
      // [FIX] Ã™â€ Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Future.microtask Ã˜Â¨Ã˜Â¯Ã™â€ž await Ã™â€¦Ã˜Â¨Ã˜Â§Ã˜Â´Ã˜Â± Ã™ÂÃ™Å  dispose()
      // Ã™â€žÃ˜Â£Ã™â€  dispose() Ã™â€žÃ™Å Ã˜Â³ async Ã¢â‚¬â€ Ã™â€¡Ã˜Â°Ã˜Â§ Ã™Å Ã™â€¦Ã™â€ Ã˜Â¹ Ã˜Â§Ã™â€žÃ™â‚¬ race condition Ã˜Â§Ã™â€žÃ˜Â°Ã™Å  Ã™Æ’Ã˜Â§Ã™â€  Ã™Å Ã˜Â³Ã˜Â¨Ã˜Â¨
      // Ã™Æ’Ã˜Â±Ã˜Â§Ã˜Â´ "Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€š Ã™â€žÃ˜Â§ Ã™Å Ã˜Â³Ã˜ÂªÃ˜Â¬Ã™Å Ã˜Â¨" Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â¶Ã˜ÂºÃ˜Â· Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â²Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â¬Ã™Ë†Ã˜Â¹ Ã˜Â£Ã˜Â«Ã™â€ Ã˜Â§Ã˜Â¡ Ã˜ÂªÃ˜Â´Ã˜ÂºÃ™Å Ã™â€ž Ã™ÂÃ™Å Ã™â€žÃ™â€¦.
      _videoPlayerController = null;
      Future.microtask(() async {
        try {
          await vc.dispose();
        } catch (_) {}
      });
    }
  }

  /// دائرة تحميل واحدة فوق سطح المشغّل (مصغّر أو ملء الشاشة) — Exo و VLC.
  bool get _showPlayerLoadingOverlay {
    // متصفح Live خامل (لم تُختر قناة بعد): لا دائرة تحميل في المصغّر.
    if (widget.isLive &&
        _currentPlaybackUrl.trim().isEmpty &&
        (_currentLiveChannel ?? widget.channelLive) == null) {
      return false;
    }
    if (_vodScrubReleaseLoading) return false;
    if (_userRequestedLivePause) return false;
    // User-paused VOD: no spinner.
    if (!widget.isLive && !isPlayed && !progress && !_isVlcBuffering) {
      return false;
    }

    // Exo: أظهر الدائرة أثناء إعادة التخزين المؤقت حتى لو isPlaying=true.
    if (_useExo) {
      final ctrl = _exoController;
      final c = ctrl?.videoPlayerController;
      if (ctrl != null && c != null && ctrl.isVideoInitialized() == true) {
        final v = c.value;
        if (v.isBuffering) return true;
        if (v.isPlaying) return false;
        if (v.position > Duration.zero) return false;
      }
    }

    // VLC أثناء التبديل: بلا سبينر تحميل — setMedia فوري.
    if (_useExo && (_isSwitchingLiveChannel || progress)) return true;
    if (!_useExo && progress && !_isSwitchingLiveChannel) return true;
    if (_isVlcBuffering && !_isSwitchingLiveChannel) return true;

    if (_useExo) {
      final ctrl = _exoController;
      final c = ctrl?.videoPlayerController;
      if (ctrl == null || c == null) return true;
      if (ctrl.isVideoInitialized() != true) return true;
      final v = c.value;
      if (v.isBuffering) return true;
      if (widget.isLive && !v.isPlaying) return true;
      if (!widget.isLive && isPlayed && !v.isPlaying) return true;
      return false;
    }

    if (_vlcLiveReconnectBusy) return true;
    final vc = _videoPlayerController;
    if (vc == null) return true;
    final v = vc.value;
    if (!v.isInitialized) return true;
    if (v.isBuffering ||
        v.playingState == PlayingState.buffering ||
        v.playingState == PlayingState.stopped ||
        v.playingState == PlayingState.error) {
      return true;
    }
    // Live stall (do not require [isPlayed] — it flips false when decoder stops).
    if (widget.isLive && !v.isPlaying && v.playingState != PlayingState.ended) {
      return true;
    }
    if (!widget.isLive &&
        isPlayed &&
        !v.isPlaying &&
        v.playingState != PlayingState.ended) {
      return true;
    }
    return false;
  }

  void _measureIptvMiniPlayerSlot() {
    // Exo + VLC both use a positioned player over this slot (same as VLC).
    if (!mounted || !_showLiveIptvOverlay) return;
    final slotBox =
        _iptvMiniPlayerSlotKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox =
        _playerVideoStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (slotBox == null ||
        !slotBox.hasSize ||
        stackBox == null ||
        !stackBox.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showLiveIptvOverlay) return;
        _measureIptvMiniPlayerSlot();
      });
      return;
    }
    final slotGlobal = slotBox.localToGlobal(Offset.zero);
    final stackGlobal = stackBox.localToGlobal(Offset.zero);
    final newRect = Rect.fromLTWH(
      slotGlobal.dx - stackGlobal.dx,
      slotGlobal.dy - stackGlobal.dy,
      slotBox.size.width,
      slotBox.size.height,
    );
    // رفض (0,0) فوق CATEGORIES — أبقِ آخر قياس سليم.
    if (!_isPlausibleIptvMiniSlotRect(newRect)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showLiveIptvOverlay) return;
        _measureIptvMiniPlayerSlot();
      });
      return;
    }
    if (_iptvMiniPlayerSlotRect != newRect) {
      // تجاهل اهتزاز أجزاء البكسل حتى لا يُعاد قصّ Exo كل إطار.
      final prev = _iptvMiniPlayerSlotRect;
      if (prev != null &&
          (prev.left - newRect.left).abs() < 0.5 &&
          (prev.top - newRect.top).abs() < 0.5 &&
          (prev.width - newRect.width).abs() < 0.5 &&
          (prev.height - newRect.height).abs() < 0.5) {
        return;
      }
      _fvSetState(() {
        _iptvMiniPlayerSlotRect = newRect;
        _iptvMiniPlayerSlotRectCache = newRect;
      });
      if (_useExo && widget.isLive) {
        _scheduleExoSurfaceFit();
      }
    }
  }

  void _scheduleIptvMiniPlayerSlotMeasure() {
    if (!mounted || !_showLiveIptvOverlay) return;
    // تجنّب جدولة قياس من كل build (كانت تسبب ومضة متكررة).
    if (_iptvMiniSlotMeasureScheduled) return;
    _iptvMiniSlotMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iptvMiniSlotMeasureScheduled = false;
      _measureIptvMiniPlayerSlot();
    });
  }

  /// ارفض القياس الفاسد أعلى-يسار (Pause فوق الفئات).
  bool _isPlausibleIptvMiniSlotRect(Rect rect) {
    if (rect.width < 32 || rect.height < 32) return false;
    if (!rect.left.isFinite || !rect.top.isFinite) return false;
    if (rect.left < 12 && rect.top < 12) return false;
    final size = MediaQuery.sizeOf(context);
    if (rect.right > size.width + 8 || rect.bottom > size.height + 8) {
      return false;
    }
    return true;
  }

  /// Mini-player slot measured and large enough for positioned Exo/VLC layers.
  bool get _iptvMiniPlayerSlotReady {
    final r = _iptvMiniPlayerSlotRect;
    return r != null && _isPlausibleIptvMiniSlotRect(r);
  }

  Widget _buildVlcBufferingPlaceholder({
    double size = 72,
    bool bufferingOnly = false,
  }) {
    if (bufferingOnly) {
      return Center(
        child: SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            color: kColorPrimary,
            strokeWidth: size > 50 ? 4 : 3,
          ),
        ),
      );
    }
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size - 8,
              height: size - 8,
              child: CircularProgressIndicator(
                color: kColorPrimary,
                strokeWidth: size > 50 ? 4 : 3,
              ),
            ),
            Icon(
              FontAwesomeIcons.pause,
              color: Colors.white,
              size: size > 50 ? 22.sp : 14,
            ),
          ],
        ),
      ),
    );
  }

  /// Keep one Exo/BetterPlayer instance alive — reposition into the mini slot
  /// when the IPTV side panel opens (same pattern as VLC). Never remount Exo
  /// inside the panel or playback goes black.
  /// دائرة تحميل واحدة فوق المشغّل.
  /// [forceFullscreenCover] + [spinnerOnly]: أثناء الانتقال — دائرة ظاهرة دون طبقة تعتم الأزرار.
  Widget _buildPlayerBufferingOverlay({
    bool forceFullscreenCover = false,
    bool spinnerOnly = false,
  }) {
    final rect = _iptvMiniPlayerSlotRect;

    final useMiniSlot = _showLiveIptvOverlay &&
        widget.isLive &&
        rect != null &&
        _isPlausibleIptvMiniSlotRect(rect);
    if (useMiniSlot) {
      if (!_showPlayerLoadingOverlay && !forceFullscreenCover) {
        return const SizedBox.shrink();
      }
      return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: IgnorePointer(
          child: Center(
            child: _buildVlcBufferingPlaceholder(
              size: 44,
              bufferingOnly: true,
            ),
          ),
        ),
      );
    }
    // اللوحة مفتوحة والخانة لم تُقاس بعد: لا تُظهر الدائرة وسط الشاشة.
    if (_showLiveIptvOverlay && widget.isLive) {
      return const SizedBox.shrink();
    }
    if (!forceFullscreenCover && !_showPlayerLoadingOverlay) {
      return const SizedBox.shrink();
    }
    // أثناء الانتقال أو فوق التحكم: دائرة فقط حتى تبقى الأزرار ظاهرة.
    if (spinnerOnly || forceFullscreenCover) {
      return Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: _buildVlcBufferingPlaceholder(
              size: 72,
              bufferingOnly: true,
            ),
          ),
        ),
      );
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: _buildVlcBufferingPlaceholder(
            size: 72,
            bufferingOnly: widget.isLive,
          ),
        ),
      ),
    );
  }

  /// غطاء أسود فوق Texture — ملء الشاشة فقط. داخل المصغّر لا نغطّي ولا نُزيل PlatformView.
  /// هل البث الحي فعلاً يشتغل؟ (تجنّب durationMs=0 بدون إعادة تشغيل بعد قناة ميتة).
  bool _isLivePlaybackHealthy() {
    if (!widget.isLive) return true;
    if (_useExo) {
      final ctrl = _exoController;
      final c = ctrl?.videoPlayerController;
      if (ctrl == null || c == null || ctrl.isVideoInitialized() != true) {
        return false;
      }
      final v = c.value;
      return !v.hasError && (v.isPlaying || v.isBuffering);
    }
    final vc = _videoPlayerController;
    if (vc == null || !vc.value.isInitialized) return false;
    final v = vc.value;
    if (v.hasError || v.playingState == PlayingState.error) return false;
    // نفس Exo: playing أو buffering = سليم.
    return v.isPlaying ||
        v.isBuffering ||
        v.playingState == PlayingState.buffering ||
        v.playingState == PlayingState.playing;
  }

  /// VLC كيلعب فعلاً؟ (zab soft فقط هنا — buffering بعد قناة ميتة ≠ playing).
  bool _vlcIsActuallyPlaying() {
    if (_useExo || !widget.isLive) return false;
    final vc = _videoPlayerController;
    if (vc == null || !vc.value.isInitialized) return false;
    final v = vc.value;
    if (v.hasError || v.playingState == PlayingState.error) return false;
    return v.isPlaying;
  }

  /// غطاء أسود Flutter — Exo أثناء الزاب، وVLC أثناء park (آخر إطار مخفي).
  bool get _hidePlayerSurfaceFlash {
    if (!widget.isLive) return false;
    if (!_useExo) {
      return _vlcParkOffscreen || _iptvSurfaceTransitionCover;
    }
    if (!(_iptvSurfaceTransitionCover || _isSwitchingLiveChannel)) {
      return false;
    }
    return !_showLiveIptvOverlay;
  }

  bool get _vlcZapInFlight =>
      _isSwitchingLiveChannel ||
      _pendingLiveChannel != null ||
      (_liveChannelSwitchDebounce?.isActive ?? false);

  /// Engine switch / first attach: never park or mute — leftover frames only
  /// happen when setMedia reuses the same VLC texture.
  void _resetVlcLiveSwapPipeline() {
    _vlcVideoMutedForSwap = false;
    _vlcAwaitingNewLiveFrames = false;
    _vlcParkOffscreen = false;
    if (!_useExo) {
      _iptvSurfaceTransitionCover = false;
      _iptvSurfaceCoverClearTimer?.cancel();
      _iptvSurfaceCoverClearTimer = null;
    }
  }

  void _trackVlcLiveSwapPipeline(VlcPlayerValue v) {
    if (!widget.isLive || _useExo || !_vlcParkOffscreen) return;
    // ارفع الأسود فور التشغيل — بلا انتظار size (كان يؤخر الظهور).
    if (v.isPlaying && !v.hasError) {
      _clearVlcZapBlank();
      _scheduleVlcSurfaceFit(bumpLayout: !_showLiveIptvOverlay);
    }
  }

  /// ارفع الأسود/park فور ما يشتغل البث الجديد.
  void _armVlcZapBlankClear() {
    if (_useExo || !widget.isLive) return;
    _iptvSurfaceCoverClearTimer?.cancel();
    var attempts = 0;
    void tick() {
      if (!mounted || _useExo) return;
      if (!_vlcParkOffscreen && !_iptvSurfaceTransitionCover) return;
      final vc = _videoPlayerController;
      final ready = vc != null &&
          vc.value.isInitialized &&
          vc.value.isPlaying &&
          !vc.value.hasError;
      if (ready || attempts >= 40) {
        _clearVlcZapBlank();
        if (ready) {
          _scheduleVlcSurfaceFit(bumpLayout: !_showLiveIptvOverlay);
        }
        return;
      }
      attempts++;
      _iptvSurfaceCoverClearTimer = Timer(
        const Duration(milliseconds: 40),
        tick,
      );
    }
    tick();
  }

  void _clearVlcZapBlank() {
    _iptvSurfaceCoverClearTimer?.cancel();
    _iptvSurfaceCoverClearTimer = null;
    if (!_vlcParkOffscreen && !_iptvSurfaceTransitionCover) return;
    if (!mounted) {
      _vlcParkOffscreen = false;
      _iptvSurfaceTransitionCover = false;
      return;
    }
    _fvSetState(() {
      _vlcParkOffscreen = false;
      _iptvSurfaceTransitionCover = false;
      _liveBlankSurfaceUntilPlay = false;
      _vlcAwaitingNewLiveFrames = false;
    });
  }

  Widget _wrapPlayerSurface(Widget sizedPlayer) {
    if (!_hidePlayerSurfaceFlash) return sizedPlayer;
    return Stack(
      fit: StackFit.expand,
      children: [
        sizedPlayer,
        const ColoredBox(color: Colors.black),
      ],
    );
  }

  /// VLC PlatformView يرسم فوق طبقات Flutter — الدائرة داخل نفس الـ Stack.
  bool get _vlcInlineBufferingSpinner {
    if (_useExo || _userRequestedLivePause) return false;
    if (_isSwitchingLiveChannel ||
        _vlcZapInFlight ||
        _vlcParkOffscreen ||
        _iptvSurfaceTransitionCover) {
      return false;
    }
    if (_showPlayerLoadingOverlay) return true;
    return false;
  }

  Widget _buildVlcPlayerStack(Widget sizedPlayer) {
    final showSpinner = _vlcInlineBufferingSpinner;
    final hideSurface = _hidePlayerSurfaceFlash;
    final spinnerSize =
        _showLiveIptvOverlay && widget.isLive && _iptvMiniPlayerSlotReady
            ? 44.0
            : 72.0;

    if (!showSpinner && !hideSurface) return sizedPlayer;

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        sizedPlayer,
        if (showSpinner)
          IgnorePointer(
            child: Center(
              child: _buildVlcBufferingPlaceholder(
                size: spinnerSize,
                bufferingOnly: true,
              ),
            ),
          ),
        if (hideSurface) const ColoredBox(color: Colors.black),
      ],
    );
  }

  /// أخفِ إطار القناة السابقة حتى يجهز البث الجديد.
  void _armLiveSurfaceCoverClear({
    Duration? delay,
    int attempt = 0,
  }) {
    // VLC: مسار سريع منفصل — بلا تأخير 280/400ms القديم.
    if (!_useExo && widget.isLive) {
      _armVlcZapBlankClear();
      return;
    }
    final initialDelay = delay ?? const Duration(milliseconds: 450);
    _iptvSurfaceCoverClearTimer?.cancel();
    _iptvSurfaceCoverClearTimer = Timer(initialDelay, () {
      if (!mounted) return;
      // Exo داخل اللوحة: ارفع الغطاء فوراً.
      if (_showLiveIptvOverlay && _useExo) {
        _fvSetState(() {
          _iptvSurfaceTransitionCover = false;
          _liveBlankSurfaceUntilPlay = false;
          _liveSurfaceCoverForUrl = null;
        });
        return;
      }
      if (_vlcZapInFlight) {
        _armLiveSurfaceCoverClear(
          delay: const Duration(milliseconds: 160),
          attempt: attempt,
        );
        return;
      }
      if (!_iptvSurfaceTransitionCover && !_liveBlankSurfaceUntilPlay) {
        return;
      }

      final expectedUrl = _liveSurfaceCoverForUrl;
      final urlOk = expectedUrl == null ||
          expectedUrl.isEmpty ||
          _activePlaybackUrl == expectedUrl;

      var streamReady = urlOk && !progress;
      if (streamReady && _useExo) {
        final ctrl = _exoController;
        final c = ctrl?.videoPlayerController;
        if (ctrl != null &&
            c != null &&
            ctrl.isVideoInitialized() == true) {
          final v = c.value;
          streamReady = v.isPlaying && !v.hasError;
        } else {
          streamReady = false;
        }
      }

      if (!streamReady && attempt < 24) {
        _armLiveSurfaceCoverClear(
          delay: const Duration(milliseconds: 120),
          attempt: attempt + 1,
        );
        return;
      }

      _fvSetState(() {
        _iptvSurfaceTransitionCover = false;
        _liveBlankSurfaceUntilPlay = false;
        _liveSurfaceCoverForUrl = null;
      });
    });
  }

  void _clearLiveSurfaceBlankIfPlaying() {
    if (!mounted || !widget.isLive || !_useExo) return;
    if (!_liveBlankSurfaceUntilPlay && !_iptvSurfaceTransitionCover) return;
    if (_showLiveIptvOverlay) return;
    final expectedUrl = _liveSurfaceCoverForUrl;
    if (expectedUrl != null &&
        expectedUrl.isNotEmpty &&
        _activePlaybackUrl != expectedUrl) {
      return;
    }
    var playing = false;
    if (_useExo) {
      final ctrl = _exoController;
      final c = ctrl?.videoPlayerController?.value;
      playing = ctrl != null &&
          ctrl.isVideoInitialized() == true &&
          c != null &&
          c.isPlaying &&
          !c.hasError;
    } else {
      final v = _videoPlayerController?.value;
      playing = v != null && v.isInitialized && v.isPlaying && !v.hasError;
    }
    if (!playing) return;
    _fvSetState(() {
      _iptvSurfaceTransitionCover = false;
      _liveBlankSurfaceUntilPlay = false;
      _liveSurfaceCoverForUrl = null;
    });
  }

  Widget _buildExoPositionedPlayerLayer() {
    final bp = _exoController;
    if (bp == null) return const SizedBox.shrink();

    final rect = _iptvMiniPlayerSlotRect;
    final isFill = _videoAspectRatio == 0;

    // نفس GlobalKey دائماً — تبديل مصغّر/ملء الشاشة بلا إعادة تهيئة (مثل VLC).
    final player = BetterPlayer(key: _exoPlayerGlobalKey, controller: bp);

    final sizedPlayer = IgnorePointer(
      child: isFill
          ? SizedBox.expand(child: player)
          : SizedBox.expand(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _videoAspectRatio,
                  child: player,
                ),
              ),
            ),
    );

    if (_showLiveIptvOverlay &&
        widget.isLive &&
        _iptvMiniPlayerSlotReady &&
        rect != null) {
      return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: IgnorePointer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: Colors.black,
              child: _wrapPlayerSurface(sizedPlayer),
            ),
          ),
        ),
      );
    }

    if (_showLiveIptvOverlay && widget.isLive) {
      _scheduleIptvMiniPlayerSlotMeasure();
      // أبقِ PlatformView بحجم ملء الشاشة خارج الشاشة حتى يُقاس المصغّر.
      final screen = MediaQuery.sizeOf(context);
      return Positioned(
        left: -screen.width - 64,
        top: 0,
        width: screen.width,
        height: screen.height,
        child: IgnorePointer(child: _wrapPlayerSurface(sizedPlayer)),
      );
    }

    if (widget.isLive && !_showLiveIptvOverlay) {
      final screen = MediaQuery.sizeOf(context);
      return Positioned(
        left: 0,
        top: 0,
        width: screen.width,
        height: screen.height,
        child: _buildExoLiveLayoutSizeListener(
          child: _wrapPlayerSurface(sizedPlayer),
        ),
      );
    }

    return Positioned.fill(child: _wrapPlayerSurface(sizedPlayer));
  }

  Widget _buildExoLiveLayoutSizeListener({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _maybeRefitExoSurfaceAfterLayoutChange(size);
        });
        return child;
      },
    );
  }

  Widget _buildVlcLiveLayoutSizeListener({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _maybeRefitVlcSurfaceAfterLayoutChange(size);
        });
        return child;
      },
    );
  }

  /// VLC: انقل PlatformView خارج الشاشة فوراً باش آخر إطار مايبانش.
  bool get _vlcZapParkOffscreen =>
      !_useExo && widget.isLive && _vlcParkOffscreen;

  /// Stream aspect from VLC metadata; falls back to the layout slot/screen.
  double _vlcStreamAspectRatio(VlcPlayerController vc, double fallback) {
    final v = vc.value;
    if (v.isInitialized && v.size.width > 0 && v.size.height > 0) {
      final ar = v.size.width / v.size.height;
      if (ar.isFinite && ar > 0) return ar;
    }
    return fallback;
  }

  /// Match Exo [BoxFit.fill]: cover the parent — VLCTextureView otherwise
  /// shrinks height and leaves a black band under the picture.
  Widget _wrapVlcCoverFill(
    VlcPlayerController vc,
    double fallbackAspectRatio, {
    bool bumpLayout = false,
  }) {
    return ListenableBuilder(
      listenable: vc,
      builder: (context, _) {
        final videoAr = _vlcStreamAspectRatio(vc, fallbackAspectRatio);
        return Padding(
          padding: EdgeInsets.all(bumpLayout ? 0.5 : 0),
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: SizedBox(
                width: 960,
                height: 960 / videoAr,
                child: VlcPlayer(
                  key: _vlcPlayerGlobalKey,
                  controller: vc,
                  aspectRatio: videoAr,
                  virtualDisplay: true,
                  placeholder: const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVlcPositionedPlayerLayer() {
    final vc = _videoPlayerController;
    if (vc == null) return const SizedBox.shrink();

    final rect = _iptvMiniPlayerSlotRect;
    final hideNative = _vlcZapParkOffscreen;
    final useMiniSlot =
        _showLiveIptvOverlay &&
        widget.isLive &&
        _iptvMiniPlayerSlotReady &&
        !hideNative;
    final parkOffscreen = hideNative;
    final layoutRatio = useMiniSlot && rect != null && rect.height > 0
        ? rect.width / rect.height
        : (MediaQuery.of(context).size.width /
              MediaQuery.of(context).size.height);
    final isFill = _videoAspectRatio == 0;

    final bump = !useMiniSlot && _vlcLayoutBump;
    final sizedPlayer = isFill
        ? SizedBox.expand(
            child: _wrapVlcCoverFill(
              vc,
              layoutRatio,
              bumpLayout: bump,
            ),
          )
        : Center(
            child: VlcPlayer(
              key: _vlcPlayerGlobalKey,
              controller: vc,
              aspectRatio: _videoAspectRatio,
              virtualDisplay: true,
              placeholder: const ColoredBox(color: Colors.black),
            ),
          );

    if (useMiniSlot) {
      final slot = rect!;
      return Positioned(
        left: slot.left,
        top: slot.top,
        width: slot.width,
        height: slot.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildVlcPlayerStack(sizedPlayer),
        ),
      );
    }

    if (parkOffscreen) {
      // Keep leftover native pixels off-screen in overlay AND fullscreen.
      // Flutter Opacity cannot hide a VLC texture.
      final screen = MediaQuery.sizeOf(context);
      return Positioned(
        left: -screen.width - 64,
        top: 0,
        width: screen.width,
        height: screen.height,
        child: IgnorePointer(child: sizedPlayer),
      );
    }

    if (_showLiveIptvOverlay && widget.isLive) {
      _scheduleIptvMiniPlayerSlotMeasure();
      return const SizedBox.shrink();
    }

    if (widget.isLive) {
      // Same pixel size as the off-screen park — only `left` changes.
      // Positioned.fill would resize the native view and redraw the leftover.
      final screen = MediaQuery.sizeOf(context);
      return Positioned(
        left: 0,
        top: 0,
        width: screen.width,
        height: screen.height,
        child: _buildVlcLiveLayoutSizeListener(
          child: _buildVlcPlayerStack(sizedPlayer),
        ),
      );
    }

    return Positioned.fill(child: _buildVlcPlayerStack(sizedPlayer));
  }
}
