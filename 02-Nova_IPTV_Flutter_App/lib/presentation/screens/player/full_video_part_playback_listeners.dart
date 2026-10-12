part of '../screens.dart';

extension _FullVideoPlaybackListeners on _FullVideoScreenState {

  void _updateBufferedEndSeconds(double bufferedEndSeconds) {
    if (widget.isLive) return;
    final maxD = _maxDurationSeconds < 1 ? 1.0 : _maxDurationSeconds;
    // Never show buffer behind the playhead (YouTube-style).
    final next = bufferedEndSeconds.clamp(sliderValue, maxD).toDouble();
    if ((_bufferSeconds - next).abs() < 0.15) return;
    _bufferSeconds = next;
  }

  void _syncExoBufferedEnd(Duration duration, List<dynamic> ranges) {
    if (widget.isLive || duration <= Duration.zero) return;
    var endMs = 0;
    for (final range in ranges) {
      final end = range.end;
      if (end is! Duration) continue;
      final ms = end.inMilliseconds;
      if (ms > endMs) endMs = ms;
    }
    if (endMs <= 0) {
      _updateBufferedEndSeconds(sliderValue);
      return;
    }
    _updateBufferedEndSeconds(endMs / 1000.0);
  }

  void _syncVlcBufferedEnd({
    required Duration duration,
    required Duration position,
    required double bufferPercent,
    required bool isBuffering,
  }) {
    if (widget.isLive || duration <= Duration.zero) return;
    final durSec = duration.inMilliseconds / 1000.0;
    final posSec = position.inMilliseconds / 1000.0;
    final pct = bufferPercent.clamp(0.0, 100.0);

    // LibVLC bufferPercent is cache-fill (0–100), NOT media download position.
    // Mapping it as duration*pct/100 fills the whole bar gray (esp. when pct=100).
    final maxAhead = math.min(45.0, math.max(0.0, durSec - posSec));
    final endSec =
        isBuffering || pct > 0
            ? posSec + maxAhead * (pct <= 0 && isBuffering ? 0.35 : pct / 100.0)
            : posSec + math.min(12.0, maxAhead * 0.25);
    _updateBufferedEndSeconds(endSec);
  }

  void _setBufferingUi(bool buffering) {
    if (!mounted) return;
    // أثناء التمرير المطوّل: لا تُظهر دائرة التحميل المسبق (تسبب التعليق والوميض).
    if (_vodSeekBarHoldActive) {
      _bufferingUiDebounce?.cancel();
      _bufferingUiDebounce = null;
      if (_isVlcBuffering) {
        _fvSetState(() => _isVlcBuffering = false);
      }
      return;
    }
    if (_isVlcBuffering == buffering) {
      _bufferingUiDebounce?.cancel();
      _bufferingUiDebounce = null;
      return;
    }
    _bufferingUiDebounce?.cancel();
    if (!buffering) {
      // Hide spinner immediately when playback resumes.
      _fvSetState(() => _isVlcBuffering = false);
      return;
    }
    // VLC: show quickly so the user sees loading above the surface.
    // Exo live: debounce أطول — تجنّب وميض التحميل أثناء rebuffer قصير بعد التحويل.
    // Exo VOD: slightly longer to avoid flicker.
    final delay = widget.isLive
        ? (_useExo
            ? const Duration(milliseconds: 900)
            : const Duration(milliseconds: 60))
        : (_useExo
            ? const Duration(milliseconds: 220)
            : const Duration(milliseconds: 60));
    _bufferingUiDebounce = Timer(delay, () {
      _bufferingUiDebounce = null;
      if (!mounted || _isVlcBuffering) return;
      if (_vodSeekBarHoldActive) return;
      _fvSetState(() => _isVlcBuffering = true);
    });
  }

  void _handleExoListenerTick() {
    final ctrl = _exoController;
    final c = ctrl?.videoPlayerController;
    if (ctrl == null || c == null) return;
    final v = c.value;
    final isBuffering = v.isBuffering;

    // أثناء التمرير المطوّل: لا تلمس الواجهة ولا التحميل المسبق إطلاقاً.
    if (_vodSeekBarHoldActive) {
      _setBufferingUi(false);
      return;
    }

    // Exo buffering is authoritative. Do not suppress it just because
    // isPlaying is still true; Media3 can remain READY/playing-intent while
    // the underlying live stream is starving.
    _setBufferingUi(isBuffering);

    final isInit = ctrl.isVideoInitialized() == true;
    if (progress && isInit) {
      _setProgressSafe(false);
    }
    if (!isInit) return;
    final dur = v.duration ?? Duration.zero;
    _syncExoBufferedEnd(dur, v.buffered);
    _maybeSyncVodScrubUiFromPlayerIfCaughtUp(v.position);
    if (!widget.isLive &&
        _vodScrubUiPositionOverride != null &&
        _vodScrubPostReleaseUiLock) {
      _applyPlaybackSnapshot(
        isPlaying: v.isPlaying,
        positionValue: _vodScrubUiPositionOverride!,
        durationValue: _vodScrubUiDurationOverride ?? dur,
      );
      return;
    }
    _applyPlaybackSnapshot(
      isPlaying: v.isPlaying,
      positionValue: v.position,
      durationValue: dur,
    );
    _enforceResumePromptPause();
    if (widget.isLive &&
        isInit &&
        !v.isPlaying &&
        !v.isBuffering &&
        !_userRequestedLivePause &&
        !_isSwitchingLiveChannel) {
      _ensureLivePlaybackIsPlaying();
    }
    if (widget.isLive && isInit) {
      // نبضات التقدم لكشف تجمّد الصورة على Exo (الـ watchdog الدوري فقط يعيد التشغيل).
      var bufferPct = 0.0;
      for (final range in v.buffered) {
        final end = range.end;
        if (end > Duration.zero) {
          bufferPct = math.max(bufferPct, end.inMilliseconds / 1000.0);
        }
      }
      _updateLiveProgressHeartbeat(
        isInitialized: true,
        isPlaying: v.isPlaying,
        isBuffering: isBuffering,
        position: v.position,
        bufferPercent: bufferPct,
      );
    }
  }

  void _handleVlcListenerTick() {
    final vc = _videoPlayerController;
    if (vc == null) return;
    final v = vc.value;
    _trackVlcLiveSwapPipeline(v);
    // أثناء التمرير المطوّل: لا تلمس الواجهة ولا التحميل المسبق إطلاقاً.
    if (_vodSeekBarHoldActive) {
      _setBufferingUi(false);
      return;
    }
    // Do not key off [isPlayed] for live stalls — snapshot sets it false when
    // the decoder stops, which would hide the spinner on the next tick.
    final liveStall =
        widget.isLive &&
        !_userRequestedLivePause &&
        v.isInitialized &&
        !v.isPlaying &&
        v.playingState != PlayingState.ended;
    final vodStall =
        !widget.isLive &&
        isPlayed &&
        v.isInitialized &&
        !v.isPlaying &&
        v.playingState != PlayingState.ended &&
        v.playingState != PlayingState.paused;
    final isBuffering =
        v.isBuffering ||
        v.playingState == PlayingState.buffering ||
        v.playingState == PlayingState.stopped ||
        liveStall ||
        vodStall;
    _setBufferingUi(isBuffering);

    if (progress && vc.value.isInitialized) {
      final holdForLiveMini =
          widget.isLive && _showLiveIptvOverlay && !vc.value.isPlaying;
      if (!holdForLiveMini) {
        _setProgressSafe(false);
      }
    }
    if (!vc.value.isInitialized) return;

    final oPosition = vc.value.position;
    final oDuration = vc.value.duration;
    _syncVlcBufferedEnd(
      duration: oDuration,
      position: oPosition,
      bufferPercent: vc.value.bufferPercent,
      isBuffering: isBuffering,
    );
    _maybeSyncVodScrubUiFromPlayerIfCaughtUp(oPosition);
    if (!widget.isLive &&
        _vodScrubUiPositionOverride != null &&
        _vodScrubPostReleaseUiLock) {
      _applyPlaybackSnapshot(
        isPlaying: vc.value.isPlaying,
        positionValue: _vodScrubUiPositionOverride!,
        durationValue: _vodScrubUiDurationOverride ?? oDuration,
      );
      return;
    }
    _applyPlaybackSnapshot(
      isPlaying: vc.value.isPlaying,
      positionValue: oPosition,
      durationValue: oDuration,
    );
    _enforceResumePromptPause();
    if (widget.isLive &&
        _showLiveIptvOverlay &&
        progress &&
        vc.value.isInitialized &&
        vc.value.isPlaying) {
      _setProgressSafe(false);
    }
    if (widget.isLive) {
      _evaluateLiveKeepAlive();
    }
    _maybeRefitVlcSurfaceAfterSizeChange(vc.value.size);
  }

  void _maybeRefitVlcSurfaceAfterSizeChange(Size size) {
    if (_useExo) return;
    if (size.width <= 1 || size.height <= 1) return;
    if (size == _vlcLastFitSize) return;
    _vlcLastFitSize = size;
    // Applying native fit while the view is moving on-screen redraws the
    // leftover mini-frame. Reveal already fits off-screen before unparking.
    if (_vlcParkOffscreen || _iptvSurfaceTransitionCover) return;
    _scheduleVlcSurfaceFit();
  }

  void _applyPlaybackSnapshot({
    required bool isPlaying,
    required Duration positionValue,
    required Duration durationValue,
  }) {
    // أثناء الضغط المطوّل الشريط يُحدَّث فقط عبر [_writeHoldScrubHud].
    if (_vodSeekBarHoldActive) return;
    isPlayed = isPlaying;
    if (widget.isLive) {
      _liveWatchSyncPlaying(isPlaying);
      if (isPlaying) {
        _clearLiveSurfaceBlankIfPlaying();
      }
    }
    if (durationValue > Duration.zero ||
        positionValue > Duration.zero ||
        isPlaying) {
      _markPlaybackTransitionComplete();
    }
    // Never collapse a known duration to 0 while the new player is still
    // initializing — that clamps the thumb to the end and grays the Slider.
    // Equally important: never *shrink* a known longer duration (HLS/Exo may
    // briefly report a short/partial duration and pin the scrubber).
    final incomingMaxSec = durationValue.inMilliseconds / 1000.0;
    if (incomingMaxSec > _maxDurationSeconds + 0.25) {
      _maxDurationSeconds = incomingMaxSec;
    } else if (incomingMaxSec > 1.0 && _maxDurationSeconds <= 1.0) {
      _maxDurationSeconds = incomingMaxSec;
    } else if (_maxDurationSeconds <= 1.0) {
      final resume = _resumeSeekTargetSeconds ?? 0;
      if (resume > 1) {
        _maxDurationSeconds = resume + 120;
      }
    }
    final maxSec = _maxDurationSeconds < 1 ? 1.0 : _maxDurationSeconds;

    Duration displayDuration = durationValue;
    Duration displayPosition = positionValue;
    if (durationValue <= Duration.zero && maxSec > 1.0) {
      displayDuration = Duration(milliseconds: (maxSec * 1000).round());
    }
    // قبل اكتمال قفزة الاستكمال: اعرض الموضع المحفوظ لا 00:00.
    if (!_awaitingResumeChoice &&
        _resumeSeekTargetSeconds != null &&
        _resumeSeekTargetSeconds! > 0 &&
        _initialResumeSeekDoneForSessionId != _activeSessionId) {
      displayPosition = Duration(
        milliseconds: (_resumeSeekTargetSeconds! * 1000).round(),
      );
    } else if (positionValue <= Duration.zero &&
        !_awaitingResumeChoice &&
        _resumeSeekTargetSeconds != null &&
        _resumeSeekTargetSeconds! > 0) {
      displayPosition = Duration(
        milliseconds: (_resumeSeekTargetSeconds! * 1000).round(),
      );
    }

    if (displayDuration.inHours == 0) {
      final strPosition = displayPosition.toString().split('.')[0];
      final strDuration = displayDuration.toString().split('.')[0];
      final posParts = strPosition.split(':');
      final durParts = strDuration.split(':');
      position =
          posParts.length >= 3 ? '${posParts[1]}:${posParts[2]}' : strPosition;
      duration =
          durParts.length >= 3 ? '${durParts[1]}:${durParts[2]}' : strDuration;
    } else {
      position = displayPosition.toString().split('.')[0];
      duration = displayDuration.toString().split('.')[0];
    }

    final posSec = displayPosition.inMilliseconds / 1000.0;
    validPosition = maxSec > 1.0 && posSec <= maxSec + 1.0;
    if (validPosition) {
      sliderValue = posSec.clamp(0.0, maxSec);
    } else if (durationValue <= Duration.zero &&
        _resumeSeekTargetSeconds != null &&
        _resumeSeekTargetSeconds! > 0) {
      sliderValue = _resumeSeekTargetSeconds!.clamp(0.0, maxSec);
      validPosition = maxSec > 1.0;
    } else if (_vodScrubPostReleaseUiLock &&
        _vodScrubUiPositionOverride != null) {
      sliderValue = (_vodScrubUiPositionOverride!.inMilliseconds / 1000.0)
          .clamp(0.0, maxSec);
      validPosition = maxSec > 1.0;
    }
    // لا تُصفّر الشريط أبداً بسبب مدة/موضع غير صالح — يسبب وميض الرجوع.
    if (!widget.isLive && sliderValue > _bufferSeconds) {
      _bufferSeconds = sliderValue;
    }
    if (!widget.isLive && _bufferSeconds > maxSec) {
      _bufferSeconds = maxSec;
    }
    _maybeAutoAdvancePlayback(positionValue, durationValue);

    final startSec = _resumeSeekTargetSeconds;
    if (!widget.isLive &&
        !_awaitingResumeChoice &&
        !_vodSeekBarHoldActive &&
        startSec != null &&
        startSec > 0 &&
        durationValue > Duration.zero) {
      _scheduleInitialResumeSeekAfterWarmup(startSec);
    }
    if (!widget.isLive &&
        !_awaitingResumeChoice &&
        startSec != null &&
        startSec > 0 &&
        _initialResumeSeekDoneForSessionId != _activeSessionId) {
      final sessionId = _activeSessionId;
      _vlcResumeRetryTimer?.cancel();
      _vlcResumeRetryTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted || sessionId != _activeSessionId) return;
        unawaited(_applyResumeSeekAfterPlayerReady(sessionId));
      });
    }

    // No setState here: position/duration/slider are in ValueNotifiers;
    // UI that shows them should use ListenableBuilder to avoid full-page rebuilds every tick.
  }

  void _maybeAutoAdvancePlayback(
    Duration positionValue,
    Duration durationValue,
  ) {
    if (_vodSeekBarHoldActive || _vodScrubPostReleaseUiLock) return;
    if (!autoPlayNextEnabled || widget.isLive) return;
    if (durationValue <= Duration.zero || positionValue <= Duration.zero) {
      return;
    }
    // Ã™â€žÃ˜Â§ Ã™â€ Ã˜Â¹Ã˜ÂªÃ˜Â¨Ã˜Â± Ã™â€ Ã™â€¡Ã˜Â§Ã™Å Ã˜Â© Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â´Ã˜ÂºÃ™Å Ã™â€ž Ã˜Â¥Ã™â€žÃ˜Â§ Ã˜Â¨Ã˜Â¹Ã˜Â¯ Ã™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â¬Ã˜Â²Ã˜Â¡ Ã™Æ’Ã˜Â§Ã™ÂÃ™Â Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜ÂªÃ™Ë†Ã™â€°.
    if (positionValue < const Duration(seconds: 20)) return;
    final remaining = durationValue - positionValue;
    if (remaining > const Duration(seconds: 1)) return;
    if (_autoAdvanceRunning) return;
    if (_autoAdvanceHandledSessionId == _activeSessionId) return;
    _autoAdvanceHandledSessionId = _activeSessionId;
    _autoAdvanceRunning = true;
    unawaited(_handleAutoAdvancePlayback());
  }

  String _buildMoviePlaybackLink(ChannelMovie movie, UserModel userAuth) {
    final sid = movie.streamId?.toString() ?? '';
    if (sid.startsWith('http://') || sid.startsWith('https://')) return sid;
    final base =
        userAuth.serverInfo?.serverUrl ?? userAuth.serverInfo?.url ?? '';
    final user = userAuth.userInfo?.username ?? '';
    final pass = userAuth.userInfo?.password ?? '';
    final ext = movie.containerExtension;
    if (ext != null && ext.isNotEmpty) {
      return '$base/movie/$user/$pass/$sid.$ext';
    }
    return '$base/movie/$user/$pass/$sid';
  }

  String _buildEpisodePlaybackLink(Episode episode) {
    final eid = episode.id?.toString() ?? '';
    if (eid.startsWith('http://') || eid.startsWith('https://')) return eid;
    final userAuth = widget.serieUserAuth;
    if (userAuth == null) return '';
    final base = userAuth.serverInfo?.serverUrl ?? '';
    final user = userAuth.userInfo?.username ?? '';
    final pass = userAuth.userInfo?.password ?? '';
    return '$base/series/$user/$pass/${episode.id}.${episode.containerExtension}';
  }

  Future<void> _handleAutoAdvancePlayback() async {
    try {
      if (_isSeriesStyle && widget.serieEpisodes != null) {
        final episodes = widget.serieEpisodes!.whereType<Episode>().toList();
        if (episodes.isNotEmpty) {
          final currentId = _currentEpisodeId ?? widget.serieCurrentEpisodeId;
          var currentIndex = -1;
          if (currentId != null && currentId.isNotEmpty) {
            currentIndex = episodes.indexWhere(
              (e) => e.id?.toString() == currentId,
            );
          }
          if (currentIndex >= 0 && currentIndex + 1 < episodes.length) {
            final nextEpisode = episodes[currentIndex + 1];
            final link = _buildEpisodePlaybackLink(nextEpisode);
            if (link.isNotEmpty) {
              await _switchToEpisode(nextEpisode, link);
              return;
            }
          }
        }
      }

      if (_isMovieStyle) {
        final authState = context.read<AuthBloc>().state;
        if (authState is! AuthSuccess) return;
        final currentMovie = _currentMovie ?? widget.channelMovie;
        if (currentMovie == null) return;
        final channelsState = context.read<ChannelsBloc>().state;
        if (channelsState is! ChannelsMovieSuccess ||
            channelsState.channels.isEmpty) {
          final catId = currentMovie.categoryId ?? '';
          if (catId.isNotEmpty) {
            context.read<ChannelsBloc>().add(
              GetLiveChannelsEvent(
                typeCategory: TypeCategory.movies,
                catyId: catId,
              ),
            );
          }
          return;
        }
        final currentSid = currentMovie.streamId?.toString() ?? '';
        final candidates =
            channelsState.channels.where((m) {
              final sid = m.streamId?.toString() ?? '';
              return sid.isNotEmpty && sid != currentSid;
            }).toList();
        if (candidates.isEmpty) return;
        final idx = DateTime.now().millisecondsSinceEpoch % candidates.length;
        final nextMovie = candidates[idx];
        final link = _buildMoviePlaybackLink(nextMovie, authState.user);
        if (link.isNotEmpty) {
          await _switchToMovie(nextMovie, link);
        }
      }
    } finally {
      _autoAdvanceRunning = false;
    }
  }

  void _onSliderPositionChanged(double progress) {
    if (!_canInteractWithPlayback || widget.isLive) return;
    _touchPlayerControlsActivity();
    final targetSeconds = progress.floor().toDouble();
    final targetSecondsInt = targetSeconds.toInt();
    _flashSeekLoading();
    if (_useExo) {
      final vc = _exoController?.videoPlayerController;
      if (vc == null) return;
      final dur = vc.value.duration ?? Duration.zero;
      final maxSec = dur.inSeconds.clamp(0, 1 << 30);
      final clamped = targetSecondsInt.clamp(0, maxSec);
      final target = Duration(seconds: clamped);
      _exoController?.seekTo(target);
      _applyPlaybackSnapshot(
        isPlaying: isPlayed,
        positionValue: target,
        durationValue: dur,
      );
      _lockVodSeekUiTo(target, dur);
      if (isPlayed) _ensurePlaybackRunningAfterSeek();
    } else {
      final vc = _videoPlayerController;
      if (vc == null || !vc.value.isInitialized) return;
      final dur = vc.value.duration;
      final maxSec = dur.inSeconds.clamp(0, 1 << 30);
      final clamped = targetSecondsInt.clamp(0, maxSec);
      final target = Duration(seconds: clamped);
      final resumePlaying = isPlayed;
      _applyPlaybackSnapshot(
        isPlaying: resumePlaying,
        positionValue: target,
        durationValue: dur,
      );
      unawaited(
        _seekVlcAccurate(target, resumePlaying: resumePlaying || isPlayed),
      );
      if (resumePlaying || isPlayed) {
        _armVlcSeekResume();
      }
    }
  }

  List<dynamic>? _getPopResult() {
    // أثناء حوار الاستكمال لا نُرجع موضعاً حتى لا يُمسح التقدّم المحفوظ.
    if (_awaitingResumeChoice) return null;

    String currentStreamId = '';
    if (_isMovieStyle) {
      currentStreamId =
          ((_currentMovie ?? widget.channelMovie)?.streamId ?? '').trim();
    } else if (_isSeriesStyle) {
      currentStreamId =
          (_currentEpisodeId ?? widget.serieCurrentEpisodeId ?? '').trim();
    }

    if (_useExo) {
      final ctrl = _exoController;
      final c = ctrl?.videoPlayerController;
      if (ctrl == null || c == null) return null;
      final isInit = ctrl.isVideoInitialized() == true;
      final dur =
          isInit ? (c.value.duration?.inSeconds.toDouble() ?? 0.0) : 0.0;
      return [sliderValue, dur, currentStreamId];
    }
    final c = _videoPlayerController;
    if (c == null) return null;
    final dur =
        c.value.isInitialized ? c.value.duration.inSeconds.toDouble() : 0.0;
    return [sliderValue, dur, currentStreamId];
  }

  void _popWithResult() {
    if (!mounted) return;
    // احفظ موضع الفيلم/الحلقة الحالية (بما فيها بعد التبديل من متابعة المشاهدة).
    if (!widget.isLive && (_isMovieStyle || _isSeriesStyle)) {
      _persistCurrentVodProgressBeforeSwitch();
    }
    try {
      Navigator.of(context).pop(_getPopResult());
    } catch (_) {
      // Route may already be popped during dispose races.
    }
  }

  void _cycleAspectRatio() {
    _fvSetState(() {
      _aspectRatioIndex = (_aspectRatioIndex + 1) % _kAspectRatios.length;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_useExo) {
        _applyExoAspectFit();
      } else {
        _applyVlcAspectFit();
      }
    });
    _touchPlayerControlsActivity();
  }

  void _applyExoAspectFit() {
    final ctrl = _exoController;
    if (ctrl == null) return;
    final isFill = _videoAspectRatio == 0;
    try {
      ctrl.setOverriddenFit(isFill ? BoxFit.fill : BoxFit.contain);
      if (!isFill) {
        ctrl.setOverriddenAspectRatio(_videoAspectRatio);
      }
      ctrl.videoPlayerController?.refresh();
    } catch (_) {}
  }

  /// إعادة ضبط Exo بعد تغيير حجم المصغّر ↔ ملء الشاشة (مثل VLC surface fit).
  void _scheduleExoSurfaceFit() {
    if (!_useExo || !widget.isLive) return;
    const gaps = <int>[0, 80, 220, 500, 1100];
    for (var i = 0; i < gaps.length; i++) {
      final delay = gaps[i];
      if (delay == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_useExo) return;
          _applyExoAspectFit();
          _ensureLivePlaybackIsPlaying();
        });
      } else {
        Future<void>.delayed(Duration(milliseconds: delay), () {
          if (!mounted || !_useExo) return;
          _applyExoAspectFit();
          _ensureLivePlaybackIsPlaying();
        });
      }
    }
  }

  void _maybeRefitExoSurfaceAfterLayoutChange(Size layoutSize) {
    if (!_useExo || !widget.isLive || _showLiveIptvOverlay) return;
    if (layoutSize.width <= 1 || layoutSize.height <= 1) return;
    if (layoutSize == _exoLastFitSize) return;
    _exoLastFitSize = layoutSize;
    if (_iptvSurfaceTransitionCover) return;
    _scheduleExoSurfaceFit();
  }

  void _maybeRefitVlcSurfaceAfterLayoutChange(Size layoutSize) {
    if (_useExo || !widget.isLive || _showLiveIptvOverlay) return;
    if (layoutSize.width <= 1 || layoutSize.height <= 1) return;
    if (layoutSize == _vlcLastLayoutSize) return;
    final prev = _vlcLastLayoutSize;
    _vlcLastLayoutSize = layoutSize;
    if (_vlcParkOffscreen || _iptvSurfaceTransitionCover) return;
    if (prev == Size.zero ||
        layoutSize.height > prev.height * 1.12 ||
        layoutSize.width > prev.width * 1.12) {
      _vlcLastFitSize = Size.zero;
      _scheduleVlcSurfaceFit(bumpLayout: true);
    }
  }

  /// Sync native VLC aspect + scale with the toolbar cycle.
  /// Fill: reset native ratio — Flutter [BoxFit.cover] scales the texture.
  void _applyVlcAspectFit() {
    final vc = _videoPlayerController;
    if (vc == null || !vc.value.isInitialized) return;
    if (_aspectRatioIndex == 0) {
      try {
        unawaited(vc.setVideoAspectRatio(''));
        unawaited(vc.setVideoScale(0));
      } catch (_) {}
      return;
    }
    final String ratio;
    switch (_aspectRatioIndex) {
      case 1:
        ratio = '16:9';
        break;
      case 2:
        ratio = '4:3';
        break;
      case 3:
        ratio = '21:9';
        break;
      default:
        ratio = '16:9';
        break;
    }
    try {
      unawaited(vc.setVideoAspectRatio(ratio));
      unawaited(vc.setVideoScale(0));
    } catch (_) {}
  }

  /// Re-apply native fit after zap / overlay close. Retries because VLC reports
  /// the new video layout a few hundred ms after setMedia.
  void _scheduleVlcSurfaceFit({bool bumpLayout = false}) {
    if (_useExo) return;
    _vlcSurfaceFitTimer?.cancel();
    final gen = ++_vlcFitGeneration;
    const gaps = <int>[0, 80, 220, 500, 1100];
    var attempt = 0;

    void run() {
      if (!mounted || gen != _vlcFitGeneration || _useExo) return;
      _applyVlcAspectFit();
      if (bumpLayout &&
          attempt == 0 &&
          !_showLiveIptvOverlay &&
          !_vlcParkOffscreen) {
        _fvSetState(() => _vlcLayoutBump = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || gen != _vlcFitGeneration) return;
          _fvSetState(() => _vlcLayoutBump = false);
        });
      }
      attempt++;
      if (attempt >= gaps.length) return;
      final waitMs = gaps[attempt] - gaps[attempt - 1];
      _vlcSurfaceFitTimer = Timer(Duration(milliseconds: waitMs), run);
    }

    run();
  }

  void _togglePlayPause() {
    if (!_canInteractWithPlayback) return;
    _fvSetState(() {
      if (isPlayed) {
        _vlcSeekShouldResume = false;
        _vlcSeekResumeTimer?.cancel();
        _vlcSeekResumeTimer = null;
        if (_useExo) {
          _exoController?.pause();
        } else {
          _videoPlayerController?.pause();
        }
        isPlayed = false;
        if (widget.isLive) {
          _userRequestedLivePause = true;
          _stopLiveKeepAliveWatchdog();
        }
      } else {
        _vlcSeekShouldResume = false;
        if (_useExo) {
          _exoController?.play();
        } else {
          _videoPlayerController?.play();
        }
        isPlayed = true;
        if (widget.isLive) {
          _userRequestedLivePause = false;
          _resetLiveKeepAliveState();
          _seedLiveKeepAliveHeartbeat();
          _startLiveKeepAliveWatchdog();
        }
      }
    });
    _touchPlayerControlsActivity();
  }

  void _flashSeekLoading() {
    _seekLoadingTimer?.cancel();
    _fvSetState(() => _showSeekLoading = true);
    _seekLoadingTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      _fvSetState(() => _showSeekLoading = false);
    });
  }

  Widget _buildSeekHint(int seconds) {
    final isForward = seconds > 0;
    final text = isForward ? '+${seconds.abs()}' : '-${seconds.abs()}';
    final icon =
        isForward ? FontAwesomeIcons.forward : FontAwesomeIcons.backward;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children:
          isForward
              ? [
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 30, color: Colors.white),
              ]
              : [
                Icon(icon, size: 30, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
    );
  }

  void _seekRelative(int seconds) {
    if (widget.isLive) return;
    final holdSeek = _vodSeekBarHoldActive;
    // أثناء السحب المستمر: واصل حتى لو ظهر buffering.
    if (!holdSeek && !_canInteractWithPlayback) return;
    if (!mounted) return;
    _touchPlayerControlsActivity();
    final delta = Duration(seconds: seconds);
    if (!holdSeek) {
      _flashSeekLoading();
    }
    final playingSnapshot = isPlayed;

    final knownDur = _vodKnownDuration();
    if (knownDur > Duration.zero) {
      final sec = knownDur.inMilliseconds / 1000.0;
      if (sec > _maxDurationSeconds) _maxDurationSeconds = sec;
    }

    Duration playerPos = Duration.zero;
    if (_useExo) {
      final vc = _exoController?.videoPlayerController;
      if (vc == null && !holdSeek) return;
      playerPos = vc?.value.position ?? Duration.zero;
    } else {
      final vc = _videoPlayerController;
      if ((vc == null || !vc.value.isInitialized) && !holdSeek) {
        if (_vodScrubUiPositionOverride == null) return;
      }
      if (vc != null && vc.value.isInitialized) {
        playerPos = vc.value.position;
      }
    }

    // أثناء الضغط: سلاسل من آخر هدف UI فقط (بدون seek للمشغّل).
    final base =
        (holdSeek && _vodScrubUiPositionOverride != null)
            ? _vodScrubUiPositionOverride!
            : _vodSeekBasePosition(playerPos);

    var target = base + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (knownDur > Duration.zero && target > knownDur) target = knownDur;

    final dur =
        knownDur > Duration.zero
            ? knownDur
            : (_vodScrubUiDurationOverride ?? _readDurationFromController());

    if (holdSeek) {
      // واجهة فقط — أي seek حي أثناء الضغط يشغّل التحميل المسبق ويعلّق الشريط.
      _vodScrubUiPositionOverride = target;
      if (dur > Duration.zero) {
        _vodScrubUiDurationOverride = dur;
      }
      _lastVodHoldSeekEmittedAt = DateTime.now();
      _writeHoldScrubHud(target, dur);
      return;
    }

    if (_useExo) {
      final vc = _exoController?.videoPlayerController;
      if (vc == null) return;
      _exoController?.seekTo(target);
      _applyPlaybackSnapshot(
        isPlaying: playingSnapshot,
        positionValue: target,
        durationValue: dur,
      );
      _lockVodSeekUiTo(target, dur);
      if (playingSnapshot) {
        _ensurePlaybackRunningAfterSeek();
      }
    } else {
      final vc = _videoPlayerController;
      if (vc == null || !vc.value.isInitialized) return;
      _applyPlaybackSnapshot(
        isPlaying: playingSnapshot,
        positionValue: target,
        durationValue: dur,
      );
      final wantPlay = playingSnapshot || isPlayed || _vlcSeekShouldResume;
      unawaited(_seekVlcAccurate(target, resumePlaying: wantPlay));
      _armVlcSeekResume();
    }

    _seekHintTimer?.cancel();
    _fvSetState(() {
      _showSeekForwardHint = seconds > 0;
      _showSeekBackwardHint = seconds < 0;
      if (seconds > 0) {
        _forwardSeekHintSeconds = seconds.abs();
      } else if (seconds < 0) {
        _backwardSeekHintSeconds = seconds.abs();
      }
    });
    _seekHintTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _fvSetState(() {
        _showSeekForwardHint = false;
        _showSeekBackwardHint = false;
      });
    });
  }

  void _handleRapidDoubleTapSeek(Offset localPosition, double width) {
    final isForward = localPosition.dx >= (width / 2);
    if (!isForward) {
      _rapidForwardSeekSeconds = 10;
      _seekRelative(-10);
      return;
    }

    final now = DateTime.now();
    final isRapid =
        _lastDoubleTapSeekAt != null &&
        now.difference(_lastDoubleTapSeekAt!) <=
            const Duration(milliseconds: 950);
    if (isRapid) {
      _rapidForwardSeekSeconds = (_rapidForwardSeekSeconds + 5).clamp(
        10,
        _kRapidDoubleTapMaxSeekSeconds,
      );
    } else {
      _rapidForwardSeekSeconds = 10;
    }
    _lastDoubleTapSeekAt = now;
    _seekRelative(_rapidForwardSeekSeconds);
  }

  String _formatStreamBitrate(int? bps) {
    if (bps == null || bps <= 0) return '—';
    final kbps = bps / 1000.0;
    if (kbps >= 1000) {
      return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
    }
    return '${kbps.round()} kbps';
  }

  String _formatStreamResolution(int? width, int? height) {
    if (width != null && width > 0 && height != null && height > 0) {
      return '$width×$height';
    }
    return '—';
  }

  String _formatStreamFps(num? fps) {
    if (fps == null || fps <= 0) return '—';
    final v = fps.toDouble();
    if ((v - v.round()).abs() < 0.05) return '${v.round()}';
    return v.toStringAsFixed(2);
  }

  String _friendlyStreamCodec({
    String? mime,
    String? codecs,
    String? label,
  }) {
    final fromCodecs = _codecNameFromToken(codecs);
    if (fromCodecs != null) return fromCodecs;
    final fromMime = _codecNameFromToken(mime);
    if (fromMime != null) return fromMime;
    final fromLabel = _codecNameFromToken(label);
    if (fromLabel != null) return fromLabel;
    final trimmed = (codecs ?? mime ?? label ?? '').trim();
    if (trimmed.isEmpty) return '—';
    if (trimmed.contains('/')) {
      return trimmed.split('/').last.toUpperCase();
    }
    return trimmed;
  }

  String? _codecNameFromToken(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final t = raw.toLowerCase();
    if (RegExp(r'\b(hevc|h\.?265|hvc1|hev1)\b').hasMatch(t)) return 'HEVC';
    if (RegExp(r'\b(h\.?264|avc1|avc3|avc)\b').hasMatch(t) ||
        t.contains('video/avc')) {
      return 'H.264';
    }
    if (RegExp(r'\b(av1|av01)\b').hasMatch(t) || t.contains('video/av01')) {
      return 'AV1';
    }
    if (RegExp(r'\b(vp9|vp09)\b').hasMatch(t) || t.contains('vp9')) return 'VP9';
    if (RegExp(r'\b(vp8|vp08)\b').hasMatch(t) || t.contains('vp8')) return 'VP8';
    if (t.contains('mpeg2') || t.contains('mp2v') || t.contains('video/mpeg2')) {
      return 'MPEG-2';
    }
    if (t.contains('mpeg4') || t.contains('mp4v') || t.contains('xvid')) {
      return 'MPEG-4';
    }
    if (t.contains('eac3') || t.contains('ec-3') || t.contains('e-ac-3')) {
      return 'E-AC-3';
    }
    if (t.contains('ac-3') || t.contains('ac3') || t.contains('audio/ac3')) {
      return 'AC-3';
    }
    if (t.contains('mp4a') ||
        t.contains('aac') ||
        t.contains('audio/mp4a')) {
      return 'AAC';
    }
    if (t.contains('opus')) return 'Opus';
    if (t.contains('vorbis')) return 'Vorbis';
    if (t.contains('flac')) return 'FLAC';
    if (t.contains('dts')) return 'DTS';
    if (t.contains('mp3') || t == 'audio/mpeg') return 'MP3';
    if (t.contains('pcm')) return 'PCM';
    return null;
  }

  int? _asPositiveInt(dynamic value) {
    if (value is int) return value > 0 ? value : null;
    if (value is num) {
      final n = value.round();
      return n > 0 ? n : null;
    }
    if (value is String) {
      final n = int.tryParse(value);
      if (n != null && n > 0) return n;
    }
    return null;
  }

  double? _asPositiveDouble(dynamic value) {
    if (value is num) {
      final d = value.toDouble();
      return d > 0 ? d : null;
    }
    if (value is String) {
      final d = double.tryParse(value);
      if (d != null && d > 0) return d;
    }
    return null;
  }

  void _applyNovaVlcTrackLabel(
    String raw, {
    required void Function(String codec) onCodec,
    required void Function(int width, int height) onSize,
    required void Function(double fps) onFps,
    required void Function(int bitrate) onBitrate,
  }) {
    var text = raw;
    if (raw.startsWith('nova:')) {
      final body = raw.substring(5);
      final parts = body.split('|');
      if (parts.length >= 5) {
        final codec = _friendlyStreamCodec(
          codecs: parts[0],
          label: parts[4],
        );
        if (codec != '—') onCodec(codec);
        final wh = parts[1].split('x');
        if (wh.length == 2) {
          final w = int.tryParse(wh[0]) ?? 0;
          final h = int.tryParse(wh[1]) ?? 0;
          if (w > 0 && h > 0) onSize(w, h);
        }
        final fpsParts = parts[2].split('/');
        final numF = double.tryParse(fpsParts[0]) ?? 0;
        final denF =
            fpsParts.length > 1 ? (double.tryParse(fpsParts[1]) ?? 0) : 1;
        if (numF > 0) {
          onFps(numF / (denF > 0 ? denF : 1));
        }
        final br = int.tryParse(parts[3]) ?? 0;
        if (br > 0) onBitrate(br);
        text = parts[4];
      }
    }
    final codec = _friendlyStreamCodec(label: text);
    if (codec != '—') onCodec(codec);
    final fpsMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:fps|hz)',
      caseSensitive: false,
    ).firstMatch(text);
    if (fpsMatch != null) {
      final fps = double.tryParse(fpsMatch.group(1)!);
      if (fps != null && fps > 0) onFps(fps);
    }
    final brMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*(kbps|mbps|kbit|mbit)',
      caseSensitive: false,
    ).firstMatch(text);
    if (brMatch != null) {
      final n = double.tryParse(brMatch.group(1)!) ?? 0;
      final unit = brMatch.group(2)!.toLowerCase();
      if (n > 0) {
        final bps =
            unit.startsWith('m') ? (n * 1000000).round() : (n * 1000).round();
        onBitrate(bps);
      }
    }
  }

  Future<Map<String, String>> _liveStreamInfoFields() async {
    final liveName = (_currentLiveChannel ?? widget.channelLive)?.name?.trim();
    final vodTitle = sanitizeDisplayTitle(widget.title).trim();
    final channel = widget.isLive
        ? ((liveName == null || liveName.isEmpty) ? null : liveName)
        : (vodTitle.isEmpty ? null : vodTitle);
    var resolution = '—';
    var videoCodec = '—';
    var audioCodec = '—';
    var bitrate = '—';
    var fps = '—';

    void fillSize(int? w, int? h) {
      if (resolution == '—' && w != null && h != null) {
        resolution = _formatStreamResolution(w, h);
      }
    }

    void fillVideoCodec(String? mime, String? codecs, [String? label]) {
      if (videoCodec != '—') return;
      videoCodec = _friendlyStreamCodec(
        mime: mime,
        codecs: codecs,
        label: label,
      );
    }

    void fillAudioCodec(String? mime, String? codecs, [String? label]) {
      if (audioCodec != '—') return;
      audioCodec = _friendlyStreamCodec(
        mime: mime,
        codecs: codecs,
        label: label,
      );
    }

    void fillBitrate(int? bps) {
      if (bitrate != '—' || bps == null || bps <= 0) return;
      bitrate = _formatStreamBitrate(bps);
    }

    void fillFps(num? value) {
      if (fps != '—' || value == null || value <= 0) return;
      fps = _formatStreamFps(value);
    }

    if (_useExo && _exoController != null) {
      final size = _exoController!.videoPlayerController?.value.size;
      if (size != null) {
        fillSize(size.width.round(), size.height.round());
      }
      try {
        final stats = await _exoController!.getStreamStats().timeout(
          const Duration(milliseconds: 700),
        );
        fillSize(_asPositiveInt(stats['width']), _asPositiveInt(stats['height']));
        fillVideoCodec(
          stats['videoMime']?.toString(),
          stats['videoCodecs']?.toString(),
        );
        fillAudioCodec(
          stats['audioMime']?.toString(),
          stats['audioCodecs']?.toString(),
        );
        fillBitrate(_asPositiveInt(stats['bitrate']));
        fillFps(_asPositiveDouble(stats['fps']));
      } catch (_) {}
      final track = _exoController!.betterPlayerAsmsTrack;
      final asmsTracks = _exoController!.betterPlayerAsmsTracks;
      final asms = track ??
          (asmsTracks.isEmpty
              ? null
              : asmsTracks.firstWhere(
                (t) => (t.bitrate ?? 0) > 0 || (t.codecs ?? '').isNotEmpty,
                orElse: () => asmsTracks.first,
              ));
      if (asms != null) {
        fillSize(asms.width, asms.height);
        fillFps(asms.frameRate);
        fillBitrate(asms.bitrate);
        final codecs = asms.codecs?.trim() ?? '';
        if (codecs.isNotEmpty) {
          final parts = codecs.split(',');
          fillVideoCodec(asms.mimeType, parts.isNotEmpty ? parts.first : codecs);
          if (parts.length > 1) {
            fillAudioCodec(null, parts[1]);
          }
        } else {
          fillVideoCodec(asms.mimeType, null);
        }
      }
    } else if (_videoPlayerController != null) {
      final size = _videoPlayerController!.value.size;
      fillSize(size.width.round(), size.height.round());
      try {
        final videos = await _videoPlayerController!.getVideoTracks().timeout(
          const Duration(milliseconds: 700),
        );
        for (final label in videos.values) {
          _applyNovaVlcTrackLabel(
            label,
            onCodec: (c) {
              if (videoCodec == '—') videoCodec = c;
            },
            onSize: (w, h) => fillSize(w, h),
            onFps: fillFps,
            onBitrate: fillBitrate,
          );
        }
      } catch (_) {}
      try {
        final audios = await _videoPlayerController!.getAudioTracks().timeout(
          const Duration(milliseconds: 700),
        );
        for (final label in audios.values) {
          _applyNovaVlcTrackLabel(
            label,
            onCodec: (c) {
              if (audioCodec == '—') audioCodec = c;
            },
            onSize: (_, _) {},
            onFps: (_) {},
            onBitrate: fillBitrate,
          );
        }
      } catch (_) {}
    }

    return {
      'channel': (channel == null || channel.isEmpty) ? '—' : channel,
      'resolution': resolution,
      'video_codec': videoCodec,
      'audio_codec': audioCodec,
      'bitrate': bitrate,
      'fps': fps,
    };
  }

  bool _liveStreamInfoMapsEqual(Map<String, String> a, Map<String, String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Map<String, String> _mergeLiveStreamInfo(
    Map<String, String> next,
    Map<String, String>? prev,
  ) {
    if (prev == null) return next;
    final out = Map<String, String>.from(next);
    for (final e in prev.entries) {
      final n = next[e.key];
      if ((n == null || n.isEmpty || n == '—') &&
          e.value.isNotEmpty &&
          e.value != '—') {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  void _stopLiveStreamInfoRefresh() {
    _liveStreamInfoRefreshTimer?.cancel();
    _liveStreamInfoRefreshTimer = null;
    _liveStreamInfoRefreshBusy = false;
  }

  void _startLiveStreamInfoRefresh() {
    _stopLiveStreamInfoRefresh();
    _liveStreamInfoRefreshTimer = Timer.periodic(_kLiveStreamInfoRefresh, (_) {
      unawaited(_refreshLiveStreamInfoBar());
    });
  }

  Future<void> _refreshLiveStreamInfoBar() async {
    if (_liveStreamInfoRefreshBusy) return;
    if (_liveStreamInfoBarVN.value == null || !mounted) {
      return;
    }
    _liveStreamInfoRefreshBusy = true;
    final token = _liveStreamInfoBarToken;
    try {
      final next = await _liveStreamInfoFields();
      if (!mounted || token != _liveStreamInfoBarToken) return;
      final prev = _liveStreamInfoBarVN.value;
      if (prev == null) return;
      final merged = _mergeLiveStreamInfo(next, prev);
      if (_liveStreamInfoMapsEqual(merged, prev)) return;
      _liveStreamInfoBarVN.value = merged;
    } catch (_) {
    } finally {
      _liveStreamInfoRefreshBusy = false;
    }
  }

  void _hideLiveStreamInfoBar() {
    _liveStreamInfoBarToken++;
    _stopLiveStreamInfoRefresh();
    if (_liveStreamInfoBarVN.value == null) return;
    _liveStreamInfoBarVN.value = null;
  }

  void _showStreamInfoDialog() {
    if (!mounted) return;
    _touchPlayerControlsActivity();
    unawaited(_toggleLiveStreamInfoBar());
  }

  Future<void> _toggleLiveStreamInfoBar() async {
    if (_liveStreamInfoBarVN.value != null) {
      _hideLiveStreamInfoBar();
      return;
    }
    final token = ++_liveStreamInfoBarToken;
    var info = await _liveStreamInfoFields();
    if (!mounted || token != _liveStreamInfoBarToken) return;
    if (info['fps'] == '—') {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted || token != _liveStreamInfoBarToken) return;
      info = _mergeLiveStreamInfo(await _liveStreamInfoFields(), info);
    }
    if (!mounted || token != _liveStreamInfoBarToken) return;
    _liveStreamInfoBarVN.value = info;
    _startLiveStreamInfoRefresh();
  }

  Widget _buildLiveStreamInfoBar() {
    return ValueListenableBuilder<Map<String, String>?>(
      valueListenable: _liveStreamInfoBarVN,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        final nameLabel =
            widget.isLive ? 'stream_info_channel'.tr : 'stream_info_title'.tr;
        final items = <(String, String)>[
          (nameLabel, info['channel'] ?? '—'),
          ('stream_info_resolution'.tr, info['resolution'] ?? '—'),
          ('stream_info_video_codec'.tr, info['video_codec'] ?? '—'),
          ('stream_info_audio_codec'.tr, info['audio_codec'] ?? '—'),
          ('stream_info_bitrate'.tr, info['bitrate'] ?? '—'),
          ('stream_info_fps'.tr, info['fps'] ?? '—'),
        ];
        final maxBarWidth = MediaQuery.sizeOf(context).width - 32;
        return Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 10,
          child: IgnorePointer(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBarWidth),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Container(
                              width: 1,
                              height: 12,
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                        Text(
                          '${items[i].$1}  ${items[i].$2}',
                          softWrap: false,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.sp,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showChangePlayerDialog() {
    if (!mounted) return;
    // iOS: VLC فقط — لا حوار تبديل.
    if (Platform.isIOS) return;
    // Android أفلام/مسلسلات: Exo فقط — لا حوار تبديل.
    if (Platform.isAndroid && !widget.isLive) return;
    _touchPlayerControlsActivity();
    final current = _currentPlayer;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('change_player'.tr),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Image.asset(
                    'assets/images/vlc_icon.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                  title: const Text('VLC'),
                  trailing:
                      current == AppVideoPlayer.vlc
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    if (!widget.isLive) return;
                    if (current != AppVideoPlayer.vlc) {
                      unawaited(
                        _switchToPlayer(
                          AppVideoPlayer.vlc,
                          saveAsDefault: true,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Image.asset(
                    'assets/images/exo_icon.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                  title: const Text('ExoPlayer'),
                  trailing:
                      current == AppVideoPlayer.exo
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    if (current != AppVideoPlayer.exo) {
                      unawaited(
                        _switchToPlayer(
                          AppVideoPlayer.exo,
                          saveAsDefault: true,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
    );
  }

  void _showFavSnackbar(bool isAdd) {
    if (!mounted) return;
    _favOverlayEntry?.remove();
    final overlay =
        Overlay.maybeOf(context) ??
        Navigator.maybeOf(context, rootNavigator: true)?.overlay;
    if (overlay == null) return;
    final title = isAdd ? 'fav_added_title'.tr : 'fav_removed_title'.tr;
    final message = isAdd ? 'fav_added_message'.tr : 'fav_removed_message'.tr;
    final categoryLabel = _favToastCategoryLabel();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (ctx) => _FavCenterToast(
            isAdd: isAdd,
            title: title,
            message: message,
            categoryLabel: categoryLabel,
            onDismissed: () {
              try {
                entry.remove();
              } catch (_) {}
              if (identical(_favOverlayEntry, entry)) {
                _favOverlayEntry = null;
              }
            },
          ),
    );
    _favOverlayEntry = entry;
    overlay.insert(entry);
  }

  String _favToastCategoryLabel() {
    if (widget.isLive) return 'fav_live'.tr;
    if (widget.channelMovie != null) return 'fav_movies'.tr;
    if (widget.channelSerie != null) return 'fav_series'.tr;
    return '';
  }

  void _hidePlayerInitToast() {
    try {
      _playerToastEntry?.remove();
    } catch (_) {}
    _playerToastEntry = null;
  }

  void _showPlayerInitToast(AppVideoPlayer player) {
    if (!mounted) return;
    _hidePlayerInitToast();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final overlay =
          Overlay.maybeOf(context) ??
          Navigator.maybeOf(context, rootNavigator: true)?.overlay;
      if (overlay == null) return;

      final text =
          player == AppVideoPlayer.exo
              ? 'player_init_exo'.tr
              : 'player_init_vlc'.tr;
      final isExo = player == AppVideoPlayer.exo;

      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) {
          return _PlayerInitToastLayer(
            text: text,
            isExo: isExo,
            onDismissed: () {
              try {
                entry.remove();
              } catch (_) {}
              if (identical(_playerToastEntry, entry)) {
                _playerToastEntry = null;
              }
            },
          );
        },
      );

      _playerToastEntry = entry;
      overlay.insert(entry);
    });
  }

  Future<void> _switchToPlayer(
    AppVideoPlayer player, {
    bool saveAsDefault = true,
  }) async {
    // iOS: VLC فقط (أفلام + بث) — تجاهل أي طلب لـ Exo/AVPlayer.
    if (Platform.isIOS) {
      if (player != AppVideoPlayer.vlc) return;
      player = AppVideoPlayer.vlc;
    }
    // Android أفلام/مسلسلات: Exo فقط على كل الأجهزة.
    if (Platform.isAndroid && !widget.isLive) {
      if (player != AppVideoPlayer.exo) return;
      player = AppVideoPlayer.exo;
    }
    final targetUrl =
        _activePlaybackUrl.isNotEmpty ? _activePlaybackUrl : widget.link;
    if (player == _currentPlayer &&
        ((_useExo && _exoController != null) ||
            (!_useExo && _videoPlayerController != null))) {
      return;
    }
    // احفظ موضع المشاهدة قبل إعادة التهيئة حتى لا نبدأ من 00:00.
    final resumePos = _captureCurrentVodPositionSeconds();
    if (resumePos != null && resumePos > 1) {
      _resumeSeekTargetSeconds = resumePos;
      _pendingResumeSeconds = resumePos;
    }
    _fvSetState(() => _currentPlayer = player);
    _resetVlcLiveSwapPipeline();
    _showPlayerInitToast(player);
    if (saveAsDefault) {
      // تفضيل الإعدادات يخص البث أساساً؛ أفلام أندرويد تبقى Exo إجبارياً.
      if (!(Platform.isAndroid && !widget.isLive)) {
        setPreferredVideoPlayer(player);
      } else {
        setPreferredVideoPlayer(AppVideoPlayer.exo);
      }
    }
    await _startPlayback(targetUrl);
  }

}
