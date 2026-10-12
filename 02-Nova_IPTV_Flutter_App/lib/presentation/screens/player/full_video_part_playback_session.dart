part of '../screens.dart';

extension _FullVideoPlaybackSession on _FullVideoScreenState {
  // ---------------------------------------------------------------------------

  /// Call when starting playback of a new source. Cancels session-scoped work and sets active URL.
  int _beginNewPlaybackSession(String url) {
    _warmupResumeSeekTimer?.cancel();
    _warmupResumeSeekTimer = null;
    _resumeSeekWarmupScheduledSessionId = null;
    _resumeCoverReleaseTimer?.cancel();
    _resumeCoverReleaseTimer = null;
    _activeSessionId += 1;
    _currentPlaybackUrl = url;
    _initialResumeSeekDoneForSessionId = null;
    _isPlaybackTransitionInProgress = true;
    // Do NOT clear `_isSwitchingLiveChannel` here — channel-switch lock must
    // stay held for the whole `_commitLiveChannelSwitch` to prevent overlapping
    // Exo loads (black flashes / stutter on rapid zaps).
    _exoVodColdRetryUsed = false;
    _exoLiveUrlCandidates = const [];
    _exoLiveUrlCandidateIndex = 0;
    _exoLiveCandidateRetryBusy = false;
    _resetLiveKeepAliveState();
    _cancelSessionScopedWork();
    _cancelTransientPlaybackUiWork();
    return _activeSessionId;
  }

  void _cancelSessionScopedWork() {}

  void _cancelTransientPlaybackUiWork() {
    _bufferingUiDebounce?.cancel();
    _bufferingUiDebounce = null;
    _vodScrubUiUnlockTimer?.cancel();
    _vodScrubUiUnlockTimer = null;
    _vodScrubPostReleaseUiLock = false;
    _vodScrubUiPositionOverride = null;
    _vodScrubUiDurationOverride = null;
    _vodScrubReleaseLoading = false;
    _vodSeekBarHoldActive = false;
    _vodSeekBarHoldDirection = 0;
    _lastVodHoldSeekEmittedAt = null;
    _vodSeekBarHoldKeyUpTimer?.cancel();
    _vodSeekBarHoldKeyUpTimer = null;
    _vlcSeekResumeTimer?.cancel();
    _vlcSeekResumeTimer = null;
    _vlcSeekShouldResume = false;
    _seekHintTimer?.cancel();
    _seekHintTimer = null;
    _seekLoadingTimer?.cancel();
    _seekLoadingTimer = null;
    _movieHintShowTimer?.cancel();
    _movieHintShowTimer = null;
    _movieHintHideTimer?.cancel();
    _movieHintHideTimer = null;
  }

  void _markPlaybackTransitionComplete() {
    _isPlaybackTransitionInProgress = false;
  }

  bool get _canInteractWithPlayback {
    if (!mounted) return false;
    if (_awaitingResumeChoice) return false;
    if (_isPlaybackTransitionInProgress) return false;
    if (progress) return false;
    if (_useExo) {
      final ctrl = _exoController;
      final vc = ctrl?.videoPlayerController;
      return ctrl != null && vc != null && ctrl.isVideoInitialized() == true;
    }
    final vc = _videoPlayerController;
    return vc != null && vc.value.isInitialized;
  }

  void _seedResumeScrubUiIfNeeded() {
    final startSec = _resumeSeekTargetSeconds ?? _pendingResumeSeconds;
    if (widget.isLive || startSec <= 0) return;
    sliderValue = startSec;
    _bufferSeconds = startSec;
    if (_maxDurationSeconds <= startSec + 1) {
      _maxDurationSeconds = startSec + 120;
    }
    validPosition = true;
  }

  void _resetPlaybackUiState() {
    progress = true;
    _isVlcBuffering = false;
    position = '';
    duration = '';
    sliderValue = 0;
    _bufferSeconds = 0;
    validPosition = false;
    _maxDurationSeconds = 1.0;
    // Keep a usable scrubber while the newly selected player initializes.
    _seedResumeScrubUiIfNeeded();
    // Ã˜Â£Ã˜Â«Ã™â€ Ã˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€¦Ã™Å Ã™â€ž Ã™â€žÃ˜Â§ Ã™â€ Ã˜Â¹Ã˜Â±Ã˜Â¶ Ã¢â€“Â¶ Ã™Æ’Ã˜Â£Ã™â€  Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â´Ã˜ÂºÃ™Å Ã™â€ž Ã™â€¦Ã˜ÂªÃ™Ë†Ã™â€šÃ™Â Ã¢â‚¬â€ Ã™â€ Ã™ÂÃ˜ÂªÃ˜Â±Ã˜Â¶ Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â´Ã˜ÂºÃ™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂªÃ™â€žÃ™â€šÃ˜Â§Ã˜Â¦Ã™Å  Ã˜Â­Ã˜ÂªÃ™â€° Ã™Å Ã˜ÂµÃ™â€ž Ã˜Â£Ã™Ë†Ã™â€ž Ã˜ÂªÃ˜Â­Ã˜Â¯Ã™Å Ã˜Â« Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜ÂºÃ™â€˜Ã™â€ž.
    isPlayed = true;
    _showSeekForwardHint = false;
    _showSeekBackwardHint = false;
    _showSeekLoading = false;
  }

  void _setProgressSafe(bool value) {
    if (!mounted) return;
    if (!value) {
      // أخفِ الإطار الأول عند 00:00 حتى تكتمل قفزة الاستكمال.
      if (_shouldHoldProgressCoverForResume()) {
        _armResumeCoverReleaseFallback();
        return;
      }
      _markPlaybackTransitionComplete();
      _resumeCoverReleaseTimer?.cancel();
      _resumeCoverReleaseTimer = null;
    }
    if (progress == value) return;
    _fvSetState(() => progress = value);
  }

  bool _shouldHoldProgressCoverForResume() {
    if (widget.isLive || _awaitingResumeChoice) return false;
    // VLC: إبقاء الغطاء يطيل الشاشة السوداء عند الاستكمال — Exo فقط يستفيد منه.
    if (!_useExo) return false;
    final s = _resumeSeekTargetSeconds;
    if (s == null || s <= 0) return false;
    return _initialResumeSeekDoneForSessionId != _activeSessionId;
  }

  void _armResumeCoverReleaseFallback() {
    if (_resumeCoverReleaseTimer != null) return;
    final sid = _activeSessionId;
    _resumeCoverReleaseTimer = Timer(const Duration(seconds: 2), () {
      _resumeCoverReleaseTimer = null;
      if (!mounted || sid != _activeSessionId) return;
      if (_initialResumeSeekDoneForSessionId != sid &&
          (_resumeSeekTargetSeconds ?? 0) > 0) {
        // لا تنتظر إلى الأبد — اسمح بالعرض ثم حاول القفزة.
        _initialResumeSeekDoneForSessionId = sid;
      }
      _setProgressSafe(false);
    });
  }

  double? get _effectiveResumeSeekSeconds {
    if (widget.isLive || _awaitingResumeChoice) return null;
    final s = _resumeSeekTargetSeconds;
    if (s == null || s <= 0) return null;
    return s;
  }

  double? _captureCurrentVodPositionSeconds() {
    if (widget.isLive) return null;
    if (_vodScrubUiPositionOverride != null) {
      return _vodScrubUiPositionOverride!.inMilliseconds / 1000.0;
    }
    double pos = sliderValue;
    try {
      if (_useExo) {
        final p = _exoController
            ?.videoPlayerController
            ?.value
            .position
            .inMilliseconds;
        if (p != null && p > 0) pos = math.max(pos, p / 1000.0);
      } else {
        final vc = _videoPlayerController;
        if (vc != null && vc.value.isInitialized) {
          final p = vc.value.position.inMilliseconds;
          if (p > 0) pos = math.max(pos, p / 1000.0);
        }
      }
    } catch (_) { /* ignore */ }
    if (pos <= 1) return null;
    return pos;
  }

  /// Detach listener and dispose VLC controller.
  Future<void> _disposeVlcSafely() async {
    final vc = _videoPlayerController;
    _videoPlayerController = null;
    if (vc == null) return;
    try {
      vc.removeListener(listener);
    } catch (_) { /* ignore */ }
    try {
      if (vc.value.isInitialized) vc.stopRendererScanning();
    } catch (_) { /* ignore */ }
    try {
      await vc.dispose().timeout(
        const Duration(milliseconds: 700),
        onTimeout: () {},
      );
    } catch (_) { /* ignore */ }
  }

  void _disposeExoSafely() {
    try {
      _exoController?.removeEventsListener(_onExoEvent);
    } catch (_) { /* ignore */ }
    _exoStartTimeoutTimer?.cancel();
    _exoStartTimeoutTimer = null;
    if (_exoValueListenerAttached) {
      final exoVc = _exoController?.videoPlayerController;
      if (exoVc != null) {
        try {
          exoVc.removeListener(listener);
        } catch (_) { /* ignore */ }
      }
      _exoValueListenerAttached = false;
    }
    final c = _exoController;
    _exoController = null;
    try {
      c?.dispose();
    } catch (_) { /* ignore */ }
  }

  /// Brief pause after tearing down a live HTTP GET (Xtream single-stream).
  Future<void> _awaitLiveSocketRelease() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  /// Full stop when leaving live: invalidate session, clear pending zaps, dispose.
  Future<void> _haltAllPlaybackForLeave() async {
    _activeSessionId++;
    _liveChannelSwitchDebounce?.cancel();
    _liveChannelSwitchDebounce = null;
    _channelSwitchDebounce?.cancel();
    _channelSwitchDebounce = null;
    _pendingLiveChannel = null;
    _pendingLiveLink = null;
    _isSwitchingLiveChannel = false;
    _currentPlaybackUrl = '';
    _currentLiveChannel = null;

    try {
      await _exoController?.setVolume(0);
    } catch (_) { /* ignore */ }
    try {
      await _exoController?.pause();
    } catch (_) { /* ignore */ }
    final vc = _videoPlayerController;
    if (vc != null) {
      try {
        if (vc.value.isInitialized) {
          await vc.setVolume(0);
          await vc.pause();
        }
      } catch (_) { /* ignore */ }
    }

    _disposeExoSafely();
    await _disposeVlcSafely();
    try {
      await PlaybackWakelockService.instance.release();
    } catch (_) { /* ignore */ }
  }

  void _ensureExoValueListener() {
    if (_exoValueListenerAttached) return;
    final vc = _exoController?.videoPlayerController;
    if (vc == null) return;
    vc.addListener(listener);
    _exoValueListenerAttached = true;
  }

  void _onExoEvent(BetterPlayerEvent event) {
    if (!mounted || !_useExo) return;
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.exception:
        if (!widget.isLive) break;
        // أعد تجربة صيغ URL على نفس Exo فقط.
        unawaited(_retryExoLiveNextCandidate('exo exception'));
        break;
      case BetterPlayerEventType.pipStart:
        _enteringPipMode = false;
        _wasPlayingBeforePip = isPlayed;
        _isInPipMode = true;
        _startPipKeepAlive();
        _resumePipPlaybackIfNeeded();
        break;
      case BetterPlayerEventType.pipStop:
        _stopPipKeepAlive();
        _isInPipMode = false;
        _enteringPipMode = false;
        unawaited(_restoreLandscapeAfterPip());
        _resumePipPlaybackIfNeeded();
        _wasPlayingBeforePip = false;
        break;
      case BetterPlayerEventType.pause:
        if (_isInPipMode || _enteringPipMode) {
          _resumePipPlaybackIfNeeded();
        } else if (widget.isLive &&
            !_userRequestedLivePause &&
            !_isSwitchingLiveChannel) {
          // Exo على Android قد يرسل pause تلقائياً بعد إعادة تخطيط السطح —
          // استأنف فوراً كما في استقرار المشروع القديم.
          Future.microtask(() {
            if (!mounted || _userRequestedLivePause) return;
            _ensureLivePlaybackIsPlaying();
          });
        }
        break;
      default:
        break;
    }
  }

  void _resumePipPlaybackIfNeeded() {
    if (!_wasPlayingBeforePip) return;
    Future.microtask(() {
      if (!mounted) return;
      try {
        _exoController?.play();
        isPlayed = true;
      } catch (_) { /* ignore */ }
    });
  }

  void _startPipKeepAlive() {
    _pipKeepAliveTimer?.cancel();
    _pipKeepAliveTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted || (!_isInPipMode && !_enteringPipMode)) {
        _stopPipKeepAlive();
        return;
      }
      if (_wasPlayingBeforePip) {
        final playing =
            _exoController?.videoPlayerController?.value.isPlaying ?? isPlayed;
        if (!playing) {
          _resumePipPlaybackIfNeeded();
        }
      }
    });
  }

  void _stopPipKeepAlive() {
    _pipKeepAliveTimer?.cancel();
    _pipKeepAliveTimer = null;
  }

  Future<void> _restoreLandscapeAfterPip() async {
    changeDeviceOrient();
    for (final delay in [50, 150, 350, 600]) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      changeDeviceOrient();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) changeDeviceOrient();
    });
  }

  bool _isIosCompatibleVodUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('.m3u8') || u.contains('.mp4') || u.contains('.m4v');
  }

  String _replaceUrlExtension(String url, String newExt) {
    final qIndex = url.indexOf('?');
    final base = qIndex >= 0 ? url.substring(0, qIndex) : url;
    final query = qIndex >= 0 ? url.substring(qIndex) : '';
    final lastSlash = base.lastIndexOf('/');
    final lastDot = base.lastIndexOf('.');
    final hasExt = lastDot > lastSlash;
    final replaced = hasExt
        ? '${base.substring(0, lastDot + 1)}$newExt'
        : '$base.$newExt';
    return '$replaced$query';
  }

  Future<String> _resolveIosVodUrl(String url) async {
    if (!Platform.isIOS) return url;
    if (widget.isLive) return url;
    if (_isIosCompatibleVodUrl(url)) return url;

    final candidates = <String>{
      _replaceUrlExtension(url, 'm3u8'),
      _replaceUrlExtension(url, 'mp4'),
      _replaceUrlExtension(url, 'm4v'),
    }.toList();

    for (final cand in candidates) {
      try {
        final resp = await _epgDio.requestUri(
          Uri.parse(cand),
          options: Options(
            method: 'GET',
            responseType: ResponseType.bytes,
            followRedirects: true,
            receiveDataWhenStatusError: false,
            headers: const {'Range': 'bytes=0-1', 'Accept': '*/*'},
            validateStatus: (s) => s != null && s >= 200 && s < 400,
          ),
        );
        final code = resp.statusCode ?? 0;
        if (code == 200 || code == 206) return cand;
      } catch (_) { /* ignore */ }
    }
    return url;
  }

  /// إعدادات Exo للبث المباشر.
  BetterPlayerConfiguration _buildExoConfiguration() {
    final initFit = _kAspectRatios[_aspectRatioIndex] == 0
        ? BoxFit.fill
        : BoxFit.contain;
    final resumeSec = _effectiveResumeSeekSeconds;
    final startAt = (resumeSec != null && resumeSec > 0)
        ? Duration(milliseconds: (resumeSec * 1000).round())
        : null;
    // بدون autoPlay عند الاستكمال: seek أولاً ثم play لتجنّب ومضة 00:00.
    final autoPlay = startAt == null && !_awaitingResumeChoice;
    return BetterPlayerConfiguration(
      autoPlay: autoPlay,
      startAt: startAt,
      fit: initFit,
      handleLifecycle: false,
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false,
        enableSkips: false,
        enableSubtitles: false,
        enableQualities: false,
        enableAudioTracks: false,
        enableOverflowMenu: false,
        enablePlaybackSpeed: false,
        enableFullscreen: false,
        controlBarColor: Colors.black.withValues(alpha: 0.05),
      ),
    );
  }

  /// Live: deeper buffers — logcat showed underrun loops (aheadMs≈40ms,
  /// BUFFERING every ~5–6s). Lean 5s/1.5s rebuffer caused stutter on IPTV.
  BetterPlayerBufferingConfiguration get _exoLiveBuffering {
    return const BetterPlayerBufferingConfiguration(
      minBufferMs: 30000,
      maxBufferMs: 120000,
      bufferForPlaybackMs: 2500,
      bufferForPlaybackAfterRebufferMs: 6000,
    );
  }

  /// VOD: deeper buffers for smooth movie playback (if Exo is used).
  BetterPlayerBufferingConfiguration get _exoVodBuffering {
    return const BetterPlayerBufferingConfiguration(
      minBufferMs: 15000,
      maxBufferMs: 50000,
      bufferForPlaybackMs: 1000,
      bufferForPlaybackAfterRebufferMs: 2000,
    );
  }

  BetterPlayerVideoFormat? _inferVideoFormat(String url) {
    final u = url.toLowerCase();
    if (u.contains('.m3u8')) return BetterPlayerVideoFormat.hls;
    if (u.contains('.mpd')) return BetterPlayerVideoFormat.dash;
    if (u.contains('.ts')) return BetterPlayerVideoFormat.other;
    // Progressive (.mp4/.mkv/…) — other مثل المرجع لـ ProgressiveMediaSource.
    return BetterPlayerVideoFormat.other;
  }

  List<String> _buildExoLiveUrlCandidates(String originalUrl) {
    return buildExoLiveUrlCandidates(originalUrl);
  }

  String _resolveExoPlaybackUrl(String url) {
    if (!widget.isLive) return url;
    final pref = preferredXtreamLiveStreamFormat;
    if (pref == XtreamLiveStreamFormat.mpegTs) {
      return normalizeXtreamLiveUrlForNativePlayerTs(url);
    }
    return normalizeXtreamLiveUrlForNativePlayer(url);
  }

  Future<void> _setupExoLiveWithFallback(
    BetterPlayerController ctrl,
    String originalUrl,
  ) async {
    final sessionAtStart = _activeSessionId;
    final candidates = _exoLiveUrlCandidates.isNotEmpty
        ? _exoLiveUrlCandidates
        : _buildExoLiveUrlCandidates(originalUrl);
    _exoLiveUrlCandidates = candidates;
    Object? lastError;
    for (var i = _exoLiveUrlCandidateIndex; i < candidates.length; i++) {
      if (!mounted || sessionAtStart != _activeSessionId) return;
      // لا تحمّل رابط قناة ميتة فوق قناة جديدة (جلسة/رابط) —
      // لا تستخدم _liveZapInFlight هنا: التشغيل الشرعي كيوقع أثناء الزاب.
      if (_activePlaybackUrl.isEmpty || originalUrl != _activePlaybackUrl) {
        return;
      }
      final cand = candidates[i];
      try {
        await ctrl.setupDataSource(
          _buildExoDataSource(cand, resolveLiveUrl: false),
        );
        if (!mounted || sessionAtStart != _activeSessionId) return;
        if (originalUrl != _activePlaybackUrl) return;
        _exoLiveUrlCandidateIndex = i;
        return;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
  }

  /// جرّب الصيغة التالية على Exo (بدون الانتقال لـ VLC).
  Future<void> _retryExoLiveNextCandidate(String reason) async {
    if (!mounted || !widget.isLive || !_useExo) return;
    if (_exoLiveCandidateRetryBusy) return;
    final sessionId = _activeSessionId;
    final expectedUrl = _activePlaybackUrl;
    if (expectedUrl.isEmpty) return;
    final next = _exoLiveUrlCandidateIndex + 1;
    if (next >= _exoLiveUrlCandidates.length) {
      // استنفاد المرشحات: أعد الاتصال لنفس القناة بدل الإبقاء على شاشة تحميل أبدية.
      if (mounted) {
        _setProgressSafe(false);
        if (_liveHadHealthyPlayback &&
            !_userRequestedLivePause &&
            !_isSwitchingLiveChannel &&
            expectedUrl == _activePlaybackUrl) {
          _scheduleLiveReconnect(immediate: true);
        }
      }
      return;
    }
    _exoLiveCandidateRetryBusy = true;
    _exoLiveUrlCandidateIndex = next;
    final nextUrl = _exoLiveUrlCandidates[next];
    _exoStartTimeoutTimer?.cancel();
    try {
      if (!mounted ||
          sessionId != _activeSessionId ||
          expectedUrl != _activePlaybackUrl) {
        return;
      }
      var ctrl = _exoController;
      if (ctrl == null) {
        await _playExoUrl(_activePlaybackUrl, resumeCandidateIndex: next);
        return;
      }
      await ctrl.setupDataSource(
        _buildExoDataSource(nextUrl, resolveLiveUrl: false),
      );
      if (!mounted ||
          sessionId != _activeSessionId ||
          expectedUrl != _activePlaybackUrl) {
        return;
      }
      if (!_awaitingResumeChoice) {
        await ctrl.play();
        isPlayed = true;
      }
      _armExoStartWatchdog(sessionId);
      if (mounted) {
        _setProgressSafe(false);
        _fvSetState(() {});
      }
    } catch (e) {
      _exoLiveCandidateRetryBusy = false;
      if (mounted && sessionId == _activeSessionId) {
        await _retryExoLiveNextCandidate('setup: $e');
      }
    } finally {
      _exoLiveCandidateRetryBusy = false;
    }
  }

  BetterPlayerDataSource _buildExoDataSource(
    String url, {
    bool resolveLiveUrl = true,
  }) {
    final playbackUrl = resolveLiveUrl ? _resolveExoPlaybackUrl(url) : url;
    final isIos = Platform.isIOS;
    // بث: UA شبيه بـ VLC — كثير من اللوحات كتقبل VLC وترفض UA أندرويد العادي.
    final liveUa = 'VLC/3.0.21 LibVLC/3.0.21';
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      playbackUrl,
      liveStream: widget.isLive,
      videoFormat: _inferVideoFormat(playbackUrl),
      headers: isIos
          ? const {
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
              'Accept': '*/*',
            }
          : {
              'User-Agent': widget.isLive
                  ? liveUa
                  : 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
              'Accept': '*/*',
              // Long progressive live GET needs keep-alive. Fresh TCP is forced
              // only on soft-reload/retry (native forceFreshConnection).
              'Connection': 'keep-alive',
              'Accept-Encoding': 'identity',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
      useAsmsTracks: false,
      useAsmsSubtitles: false,
      useAsmsAudioTracks: false,
      bufferingConfiguration: widget.isLive
          ? _exoLiveBuffering
          : _exoVodBuffering,
      // Live: never cache. Movies/Series: 300 MB (native ignores FLAG_BLOCK_ON_CACHE).
      cacheConfiguration: widget.isLive
          ? const BetterPlayerCacheConfiguration(useCache: false)
          : const BetterPlayerCacheConfiguration(
              useCache: true,
              maxCacheSize: 300 * 1024 * 1024,
              maxCacheFileSize: 50 * 1024 * 1024,
            ),
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,
      ),
    );
  }

  Future<void> _playExoUrl(String url, {int resumeCandidateIndex = 0}) async {
    if (!mounted || url.isEmpty) return;
    _currentPlayer = AppVideoPlayer.exo;
    // Live: always start in Fill; user can still cycle other aspect modes.
    if (widget.isLive && _aspectRatioIndex != 0) {
      _aspectRatioIndex = 0;
    }

    _exoStartTimeoutTimer?.cancel();
    _exoStartTimeoutTimer = null;
    final sessionId = _activeSessionId;

    if (widget.isLive) {
      _exoLiveUrlCandidates = _buildExoLiveUrlCandidates(url);
      _exoLiveUrlCandidateIndex = resumeCandidateIndex.clamp(
        0,
        _exoLiveUrlCandidates.length - 1,
      );
    }

    var resolvedUrl = widget.isLive
        ? _exoLiveUrlCandidates[_exoLiveUrlCandidateIndex]
        : url;
    if (!widget.isLive && Platform.isIOS) {
      resolvedUrl = await _resolveIosVodUrl(resolvedUrl);
    }
    if (!mounted || sessionId != _activeSessionId) return;

    if (widget.isLive && resolvedUrl != url) {
    }

    // البث: ارفض فقط رابط لم يعد نشطاً (reconnect قديم). لا توقف على
    // _liveZapInFlight — وإلا الزاب الشرعي ما كيكمّلش التشغيل.
    if (widget.isLive) {
      if (_activePlaybackUrl.isEmpty || url != _activePlaybackUrl) return;
    }

    // البث داخل اللوحة: إعادة استخدام المتحكّم. fullscreen: دائماً سطح جديد بعد tear-down.
    final existing = _exoController;
    if (existing != null && widget.isLive && _showLiveIptvOverlay) {
      try {
        if (sessionId != _activeSessionId || url != _activePlaybackUrl) {
          return;
        }
        await _setupExoLiveWithFallback(existing, url);
        if (!mounted ||
            sessionId != _activeSessionId ||
            url != _activePlaybackUrl) {
          return;
        }
        await _applyResumeSeekAfterPlayerReady(sessionId);
        if (!mounted || sessionId != _activeSessionId) return;
        if (_awaitingResumeChoice) {
          await existing.pause();
          isPlayed = false;
        } else {
          await existing.play();
          isPlayed = true;
        }
        _ensureExoValueListener();
        _armExoStartWatchdog(sessionId);
        if (mounted) {
          _setProgressSafe(false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _useExo) _applyExoAspectFit();
          });
        }
      } catch (e) {
        if (mounted && sessionId == _activeSessionId) {
          _setProgressSafe(false);
        }
      }
      return;
    }

    if (existing != null) {
      _disposeExoSafely();
    }

    if (!mounted) return;

    final ctrl = BetterPlayerController(_buildExoConfiguration());
    ctrl.addEventsListener(_onExoEvent);
    // GlobalKey فقط لـ VOD/PiP — البث يستخدم ValueKey لكل زاب.
    if (!widget.isLive) {
      ctrl.setBetterPlayerGlobalKey(_exoPlayerGlobalKey);
    }
    // أظهر سطح المشغّل فوراً بدل دائرة التحميل الفارغة أثناء setup.
    _exoController = ctrl;
    if (mounted) {
      // اسمح بتركيب PlatformView فوراً بعد dispose القناة السابقة.
      _liveBlankSurfaceUntilPlay = false;
      _iptvSurfaceTransitionCover = false;
      _liveSurfaceCoverForUrl = null;
      // مع استكمال معلّق أبقِ الغطاء؛ وإلا أزل التحميل.
      _setProgressSafe(false);
      _fvSetState(() {});
    }

    try {
      if (widget.isLive) {
        if (sessionId != _activeSessionId || url != _activePlaybackUrl) {
          return;
        }
        await _setupExoLiveWithFallback(ctrl, url);
      } else {
        await ctrl.setupDataSource(_buildExoDataSource(resolvedUrl));
      }
      if (!mounted || !identical(_exoController, ctrl)) return;
      if (widget.isLive &&
          (sessionId != _activeSessionId || url != _activePlaybackUrl)) {
        return;
      }
      await _applyResumeSeekAfterPlayerReady(sessionId);
      if (!mounted || !identical(_exoController, ctrl)) return;
      if (widget.isLive &&
          (sessionId != _activeSessionId || url != _activePlaybackUrl)) {
        return;
      }
      if (_awaitingResumeChoice) {
        await ctrl.pause();
        isPlayed = false;
      } else {
        await ctrl.play();
        isPlayed = true;
      }
      _ensureExoValueListener();
      _armExoStartWatchdog(sessionId);
      if (mounted) {
        _setProgressSafe(false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_useExo) return;
          _applyExoAspectFit();
          _clearLiveSurfaceBlankIfPlaying();
        });
      }
    } catch (e) {
      if (widget.isLive && mounted && sessionId == _activeSessionId) {
        _setProgressSafe(false);
      } else if (!widget.isLive && mounted && sessionId == _activeSessionId) {
        unawaited(_retryExoVodColdStart(resolvedUrl, sessionId));
      }
    }
  }

  void _armExoStartWatchdog(int sessionId) {
    if (!widget.isLive) {
      // أفلام: إن لم يتهيأ خلال مهلة — إعادة تهيئة باردة مرة واحدة.
      _exoStartTimeoutTimer = Timer(const Duration(seconds: 12), () {
        if (!mounted) return;
        if (!_useExo) return;
        if (sessionId != _activeSessionId) return;
        if (_exoController?.isVideoInitialized() == true) return;
        final url = _activePlaybackUrl;
        if (url.isEmpty) return;
        unawaited(_retryExoVodColdStart(url, sessionId));
      });
      return;
    }
    _exoStartTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (!_useExo) return;
      if (sessionId != _activeSessionId) return;
      if (_exoController?.isVideoInitialized() == true) return;
      // Stay on Exo — try MPEG-TS / original URL before giving up.
      unawaited(_retryExoLiveNextCandidate('exo init timeout'));
    });
    _seedLiveKeepAliveHeartbeat();
    _startLiveKeepAliveWatchdog();
  }

  Future<void> _retryExoVodColdStart(String url, int sessionId) async {
    if (!mounted || widget.isLive) return;
    if (sessionId != _activeSessionId) return;
    if (_exoVodColdRetryUsed) return;
    _exoVodColdRetryUsed = true;
    _disposeExoSafely();
    if (!mounted || sessionId != _activeSessionId) return;
    final ctrl = BetterPlayerController(_buildExoConfiguration());
    ctrl.addEventsListener(_onExoEvent);
    _exoController = ctrl;
    if (mounted) {
      _setProgressSafe(false);
      _fvSetState(() {});
    }
    try {
      await ctrl.setupDataSource(_buildExoDataSource(url));
      if (!mounted || !identical(_exoController, ctrl)) return;
      await _applyResumeSeekAfterPlayerReady(sessionId);
      if (!mounted || !identical(_exoController, ctrl)) return;
      if (!_awaitingResumeChoice) {
        await ctrl.play();
        isPlayed = true;
      }
      _ensureExoValueListener();
      if (mounted) {
        _fvSetState(() {});
        _setProgressSafe(false);
      }
    } catch (e) { /* ignore */ }
  }

  /// تشغيل رابط عبر VLC.
  /// بث حي سليم (isPlaying): soft setMedia — زاب سلس بحال Exo.
  /// بث ميت/عالق: dispose + كنترولر جديد (ما كيسمّمش اللاعب).
  Future<void> _playVlcUrl(String url) async {
    if (!mounted || url.isEmpty) return;
    _currentPlayer = AppVideoPlayer.vlc;
    final playbackUrl = url;
    final sessionId = _activeSessionId;
    final needsFreshForResume =
        !widget.isLive && (_effectiveResumeSeekSeconds ?? 0) > 0;

    if (widget.isLive) {
      var vc = _videoPlayerController;
      final canSoft = vc != null &&
          vc.value.isInitialized &&
          vc.value.isPlaying &&
          !vc.value.hasError &&
          vc.value.playingState != PlayingState.error;

      if (canSoft) {
        if (!_vlcParkOffscreen || !_iptvSurfaceTransitionCover) {
          _fvSetState(() {
            _vlcParkOffscreen = true;
            _iptvSurfaceTransitionCover = true;
          });
        }
        try {
          await vc.setMediaFromNetwork(
            playbackUrl,
            autoPlay: true,
            hwAcc: HwAcc.full,
          );
        } catch (_) {}
        if (!mounted || sessionId != _activeSessionId) return;
        isPlayed = true;
        unawaited(vc.play());
        if (mounted) _setProgressSafe(false);
        _seedLiveKeepAliveHeartbeat();
        _startLiveKeepAliveWatchdog();
        _armVlcZapBlankClear();
        // بلا bump أثناء park — كينقص setState على الأجهزة الضعيفة.
        _scheduleVlcSurfaceFit(bumpLayout: false);
        return;
      }

      await _disposeVlcSafely();
      if (!mounted || sessionId != _activeSessionId) return;
      await _attachFreshVlcController(
        playbackUrl,
        sessionId: sessionId,
        forLive: true,
      );
      return;
    }

    var vc = _videoPlayerController;
    if (vc != null && !vc.value.isInitialized) {
      await _disposeVlcSafely();
      vc = null;
    }

    // استكمال مشاهدة: أنشئ متحكماً جديداً مع --start-time (setMedia يفقده).
    if (vc != null && vc.value.isInitialized && needsFreshForResume) {
      await _disposeVlcSafely();
      vc = null;
    }

    if (vc != null && vc.value.isInitialized) {
      try {
        await vc.setMediaFromNetwork(
          playbackUrl,
          autoPlay: !_awaitingResumeChoice,
          hwAcc: HwAcc.full,
        );
      } catch (_) {}
      if (!mounted || sessionId != _activeSessionId) return;
      if (_awaitingResumeChoice) {
        try {
          await vc.pause();
        } catch (_) {}
        isPlayed = false;
      } else {
        isPlayed = true;
        unawaited(vc.play());
      }
      final resume = _effectiveResumeSeekSeconds;
      if (resume != null && resume > 0) {
        _initialResumeSeekDoneForSessionId = sessionId;
        _lockVodSeekUiTo(
          Duration(milliseconds: (resume * 1000).round()),
          _vodKnownDuration(),
        );
        unawaited(_vlcEnsureResumePositionInBackground(vc, sessionId, resume));
      }
      if (mounted) {
        _setProgressSafe(false);
      }
      return;
    }

    await _disposeVlcSafely();
    if (!mounted) return;
    await _attachFreshVlcController(
      playbackUrl,
      sessionId: sessionId,
      forLive: false,
    );
  }

  /// إعادة إنشاء متحكّم VLC عند الحاجة (يُستدعى عبر dispose + attach).
  Future<void> _attachFreshVlcController(
    String url, {
    required int sessionId,
    required bool forLive,
  }) async {
    final newVc = _createVlcController(url, forLive: forLive);
    newVc.addListener(listener);
    newVc.addOnInitListener(() {
      if (!mounted || sessionId != _activeSessionId) return;
      unawaited(_onVlcControllerReadyForResume(newVc, sessionId));
    });
    if (!mounted) {
      try {
        newVc.dispose();
      } catch (_) { /* ignore */ }
      return;
    }
    _fvSetState(() {
      _videoPlayerController = newVc;
    });
    _setProgressSafe(false);
    if (forLive) {
      _vlcVideoMutedForSwap = false;
      _vlcAwaitingNewLiveFrames = false;
      // بلا bump أثناء park — _clearVlcZapBlank كيدير fit بعد الظهور.
      _scheduleVlcSurfaceFit(bumpLayout: false);
      _seedLiveKeepAliveHeartbeat();
      _startLiveKeepAliveWatchdog();
      _armVlcZapBlankClear();
    }
  }

  Future<void> _onVlcControllerReadyForResume(
    VlcPlayerController vc,
    int sessionId,
  ) async {
    if (!mounted || sessionId != _activeSessionId) return;

    final resume = _effectiveResumeSeekSeconds;
    // لا ننتظر القفزة قبل التشغيل — هذا سبب الشاشة السوداء الطويلة مقابل Exo.
    if (resume != null && resume > 0) {
      _initialResumeSeekDoneForSessionId = sessionId;
      final target = Duration(milliseconds: (resume * 1000).round());
      _lockVodSeekUiTo(target, _vodKnownDuration());
      _seedResumeScrubUiIfNeeded();
    }

    if (mounted) _setProgressSafe(false);

    if (!mounted || sessionId != _activeSessionId) return;
    if (_awaitingResumeChoice) {
      try {
        await vc.pause();
      } catch (_) { /* ignore */ }
      isPlayed = false;
      return;
    }

    try {
      await vc.play();
    } catch (_) { /* ignore */ }
    isPlayed = true;
    if (widget.isLive) {
      _scheduleVlcSurfaceFit();
    }

    // تأكيد الموضع في الخلفية إن لم يطبّق :start-time بعد.
    if (resume != null && resume > 0) {
      unawaited(_vlcEnsureResumePositionInBackground(vc, sessionId, resume));
    }
  }

  Future<void> _vlcEnsureResumePositionInBackground(
    VlcPlayerController vc,
    int sessionId,
    double resumeSec,
  ) async {
    // انتظر لحظة قصيرة حتى يبدأ فك التشفير ثم صحّح الموضع إن لزم.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || sessionId != _activeSessionId) return;
    if (!identical(_videoPlayerController, vc)) return;

    final posSec = vc.value.position.inMilliseconds / 1000.0;
    if (posSec + 6 >= resumeSec) return;

    final targetMs = (resumeSec * 1000).round();
    try {
      await vc.setTime(targetMs).timeout(const Duration(milliseconds: 600));
    } catch (_) {
      try {
        await vc
            .seekTo(Duration(milliseconds: targetMs))
            .timeout(const Duration(milliseconds: 600));
      } catch (_) { /* ignore */ }
    }
    if (!mounted || sessionId != _activeSessionId) return;
    try {
      await vc.play();
    } catch (_) { /* ignore */ }
    isPlayed = true;
    if (mounted) _setProgressSafe(false);
  }

  void _scheduleDeferredResumeSeekTimers(double startSec) {
    _resumeSeekTargetSeconds = startSec;
    _seedResumeScrubUiIfNeeded();
    final sessionId = _activeSessionId;
    _resumeSeekTimer1?.cancel();
    _resumeSeekTimer2?.cancel();

    // احتياطي فقط — القفزة الأساسية فورية عبر [_applyResumeSeekAfterPlayerReady].
    _resumeSeekTimer1 = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || sessionId != _activeSessionId) return;
      if (_initialResumeSeekDoneForSessionId == sessionId) return;
      unawaited(_applyResumeSeekAfterPlayerReady(sessionId));
    });
    _resumeSeekTimer2 = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || sessionId != _activeSessionId) return;
      if (_initialResumeSeekDoneForSessionId == sessionId) return;
      unawaited(_applyResumeSeekAfterPlayerReady(sessionId));
    });
  }

  /// عند تبديل فيلم/حلقة داخل المشغّل: لا نُرحّل موضع العنصر السابق.
  /// إن وُجد تقدّم محفوظ للعنصر الجديد نستخدمه، وإلا نبدأ من الصفر.
  void _applyResumeTargetForContentSwitch({
    required String streamId,
    required bool fromSeries,
  }) {
    _resumeSeekTimer1?.cancel();
    _resumeSeekTimer2?.cancel();
    _resumeSeekTimer1 = null;
    _resumeSeekTimer2 = null;
    _warmupResumeSeekTimer?.cancel();
    _warmupResumeSeekTimer = null;
    _resumeSeekWarmupScheduledSessionId = null;
    _initialResumeSeekDoneForSessionId = null;
    _awaitingResumeChoice = false;
    _pendingResumeSeconds = 0;
    _resumeSeekTargetSeconds = null;
    sliderValue = 0;
    _bufferSeconds = 0;

    double? savedSec;
    final id = streamId.trim();
    if (id.isNotEmpty) {
      final sessionPos = _sessionVodProgressByStreamId[id];
      if (sessionPos != null && sessionPos > 0) {
        savedSec = sessionPos;
      } else if (mounted) {
        final watch = context.read<WatchingCubit>().state;
        final list = fromSeries ? watch.series : watch.movies;
        for (final w in list) {
          // تطابق بمعرّف الفيلم/الحلقة فقط — لا نأخذ موضع عنصر آخر.
          if (w.streamId.trim() == id && w.sliderValue > 0) {
            savedSec = w.sliderValue;
            break;
          }
        }
      }
    }

    if (savedSec != null && savedSec > 0) {
      _resumeSeekTargetSeconds = savedSec;
      _scheduleDeferredResumeSeekTimers(savedSec);
    } else {
      _resumeSeekTargetSeconds = null;
      _pendingResumeSeconds = 0;
    }
  }

  /// يحفظ موضع المحتوى الحالي قبل التبديل حتى يُستكمل عند الرجوع إليه.
  void _persistCurrentVodProgressBeforeSwitch() {
    if (widget.isLive || !mounted) return;

    final pos =
        _captureCurrentVodPositionSeconds() ??
        (sliderValue > 1 ? sliderValue : null);
    if (pos == null || pos <= 1) return;

    var duration = _maxDurationSeconds;
    try {
      if (_useExo) {
        final d = _exoController
            ?.videoPlayerController
            ?.value
            .duration
            ?.inSeconds
            .toDouble();
        if (d != null && d > 1) duration = d;
      } else {
        final vc = _videoPlayerController;
        if (vc != null && vc.value.isInitialized) {
          final d = vc.value.duration.inSeconds.toDouble();
          if (d > 1) duration = d;
        }
      }
    } catch (_) { /* ignore */ }
    if (duration < pos) duration = pos;

    final playbackUrl = _currentPlaybackUrl.trim().isNotEmpty
        ? _currentPlaybackUrl
        : widget.link;

    if (_isMovieStyle) {
      final movie = _currentMovie ?? widget.channelMovie;
      final streamId = (movie?.streamId ?? '').trim();
      if (streamId.isEmpty) return;
      _sessionVodProgressByStreamId[streamId] = pos;
      context.read<WatchingCubit>().addMovie(
        WatchingModel(
          streamId: streamId,
          image: movie?.streamIcon ?? '',
          title: movie?.name ?? _currentPlaybackTitle,
          stream: playbackUrl,
          sliderValue: pos,
          durationStrm: duration,
          rating: movie?.rating,
          rating5based: movie?.rating5based,
          categoryId: movie?.categoryId,
        ),
      );
      return;
    }

    if (_isSeriesStyle) {
      final episodeId =
          (_currentEpisodeId ?? widget.serieCurrentEpisodeId ?? '').trim();
      if (episodeId.isEmpty) return;
      Episode? episode;
      for (final ep in widget.serieEpisodes ?? const <Episode?>[]) {
        if (ep == null) continue;
        if (ep.id?.toString().trim() == episodeId) {
          episode = ep;
          break;
        }
      }
      final serie = widget.channelSerie;
      _sessionVodProgressByStreamId[episodeId] = pos;
      context.read<WatchingCubit>().addSerie(
        WatchingModel(
          streamId: episodeId,
          image: episode?.info?.movieImage ?? serie?.cover ?? '',
          title: episode?.title ?? _currentPlaybackTitle,
          stream: playbackUrl,
          sliderValue: pos,
          durationStrm: duration,
          seriesId: serie?.seriesId,
          seriesName: serie?.name,
          seriesCover: serie?.cover,
          rating: serie?.rating,
          rating5based: serie?.rating5based,
        ),
      );
    }
  }

  void _onResumePlaybackContinue() {
    if (!_awaitingResumeChoice || !mounted) return;
    _fvSetState(() {
      _awaitingResumeChoice = false;
      _resumeSeekTargetSeconds = _pendingResumeSeconds;
      isPlayed = true;
      showControllersVideo = true;
    });
    _scheduleDeferredResumeSeekTimers(_pendingResumeSeconds);
    unawaited(_continueResumePlaybackAfterChoice());
    _schedulePlayerControlsHideAfterIdle();
    _requestRootFocusOnce();
  }

  Future<void> _continueResumePlaybackAfterChoice() async {
    final sessionId = _activeSessionId;
    final resume = _resumeSeekTargetSeconds ?? _pendingResumeSeconds;
    if (mounted) _setProgressSafe(false);

    if (_useExo) {
      await _applyResumeSeekAfterPlayerReady(sessionId);
      if (!mounted) return;
      try {
        await _exoController?.play();
      } catch (_) { /* ignore */ }
    } else {
      final vc = _videoPlayerController;
      // VLC: شغّل فوراً ثم صحّح الموضع في الخلفية (يتجنب الشاشة السوداء).
      if (resume > 0) {
        _initialResumeSeekDoneForSessionId = sessionId;
        _lockVodSeekUiTo(
          Duration(milliseconds: (resume * 1000).round()),
          _vodKnownDuration(),
        );
      }
      try {
        await vc?.play();
      } catch (_) { /* ignore */ }
      isPlayed = true;
      if (vc != null && resume > 0) {
        unawaited(_vlcEnsureResumePositionInBackground(vc, sessionId, resume));
      }
    }
    if (mounted) _setProgressSafe(false);
  }

  Future<void> _onResumePlaybackRestart() async {
    if (!_awaitingResumeChoice || !mounted) return;
    _fvSetState(() {
      _awaitingResumeChoice = false;
      _resumeSeekTargetSeconds = null;
      _pendingResumeSeconds = 0;
      _sliderVN.value = 0;
      _bufferVN.value = 0;
      isPlayed = true;
      showControllersVideo = true;
    });
    try {
      if (_useExo) {
        final exo = _exoController;
        if (exo != null) {
          // انتظار الـ seek ثم التشغيل؛ بعض المشغّلات تتوقف بعد seek إن لم يُنتظر.
          await exo.seekTo(Duration.zero);
          if (!mounted) return;
          await exo.play();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (!mounted) return;
          await exo.play();
        }
      } else {
        final vc = _videoPlayerController;
        if (vc != null) {
          vc.setTime(0);
          await Future<void>.delayed(const Duration(milliseconds: 80));
          if (!mounted) return;
          await vc.play();
        }
      }
    } catch (_) { /* ignore */ }
    if (!mounted) return;
    _fvSetState(() => isPlayed = true);
    _schedulePlayerControlsHideAfterIdle();
    _requestRootFocusOnce();
  }

  /// أثناء انتظار اختيار الاستكمال: إبقاء الفيديو متوقفاً.
  void _enforceResumePromptPause() {
    if (!_awaitingResumeChoice || widget.isLive) return;
    try {
      if (_useExo) {
        final playing =
            _exoController?.videoPlayerController?.value.isPlaying ?? false;
        if (playing) {
          _exoController?.pause();
        }
      } else {
        final vc = _videoPlayerController;
        if (vc != null && vc.value.isPlaying) {
          vc.pause();
        }
      }
    } catch (_) { /* ignore */ }
    if (isPlayed) {
      isPlayed = false;
    }
  }

  /// One-time resume seek for this session. Returns true if seek was performed.
  /// لا تنتظر معرفة المدة — القفز فوراً يمنع ومضة البداية من 00:00.
  Future<bool> _tryInitialResumeSeekForSession(
    int sessionId,
    double startSec,
    Duration durationValue,
  ) async {
    if (_initialResumeSeekDoneForSessionId == sessionId) return false;
    if (startSec <= 0) return false;
    if (!mounted || sessionId != _activeSessionId) return false;

    if (_useExo) {
      if (_exoController == null) return false;
    } else {
      final vc = _videoPlayerController;
      if (vc == null || !vc.value.isInitialized) return false;
    }

    var seekSec = startSec;
    final maxSec = durationValue.inMilliseconds / 1000.0;
    if (maxSec > 1) {
      seekSec = startSec.clamp(0.0, maxSec);
    }
    _initialResumeSeekDoneForSessionId = sessionId;
    sliderValue = seekSec;
    final target = Duration(milliseconds: (seekSec * 1000).round());
    final durForUi = durationValue > Duration.zero
        ? durationValue
        : (_maxDurationSeconds > 1
              ? Duration(milliseconds: (_maxDurationSeconds * 1000).round())
              : Duration.zero);
    _lockVodSeekUiTo(target, durForUi);
    _seedResumeScrubUiIfNeeded();

    try {
      if (_useExo) {
        await _exoController?.seekTo(target);
      } else {
        final vc = _videoPlayerController;
        if (vc != null) {
          try {
            await vc
                .setTime(target.inMilliseconds)
                .timeout(const Duration(milliseconds: 700));
          } catch (_) {
            try {
              await vc
                  .seekTo(target)
                  .timeout(const Duration(milliseconds: 700));
            } catch (_) { /* ignore */ }
          }
        }
      }
    } catch (e) { /* ignore */ }
    if (mounted) _setProgressSafe(false);
    return true;
  }

  Future<void> _applyResumeSeekAfterPlayerReady(int sessionId) async {
    if (!mounted || sessionId != _activeSessionId) return;
    if (_awaitingResumeChoice) return;
    final startSec = _resumeSeekTargetSeconds;
    if (startSec == null || startSec <= 0) return;
    if (_initialResumeSeekDoneForSessionId == sessionId) {
      if (mounted) _setProgressSafe(false);
      return;
    }

    Duration dur = Duration.zero;
    if (_useExo) {
      dur =
          _exoController?.videoPlayerController?.value.duration ??
          Duration.zero;
    } else {
      final vc = _videoPlayerController;
      if (vc != null && vc.value.isInitialized) {
        dur = vc.value.duration;
      }
    }
    final ok = await _tryInitialResumeSeekForSession(sessionId, startSec, dur);
    if (ok && mounted) _fvSetState(() {});
  }

  void _scheduleInitialResumeSeekAfterWarmup(double startSec) {
    if (widget.isLive) return;
    final sid = _activeSessionId;
    if (startSec <= 0) return;
    if (_initialResumeSeekDoneForSessionId == sid) return;
    if (_resumeSeekWarmupScheduledSessionId == sid) return;
    _resumeSeekWarmupScheduledSessionId = sid;
    _warmupResumeSeekTimer?.cancel();
    // محاولة سريعة جداً؛ الاحتياطي عبر المؤقّتات المؤجّلة.
    _warmupResumeSeekTimer = Timer(const Duration(milliseconds: 80), () {
      _warmupResumeSeekTimer = null;
      if (!mounted || sid != _activeSessionId) return;
      unawaited(_applyResumeSeekAfterPlayerReady(sid));
    });
  }

  /// Restore focus to player with guard to avoid churn.
  void _requestRootFocusOnce() {
    // أثناء حوار الاستكمال: لا تسرق التركيز من أزرار القائمة.
    if (_awaitingResumeChoice) return;
    if (_focusRestoreScheduled) return;
    if (!_rootPlayerFocusNode.canRequestFocus) return;
    _focusRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _focusRestoreScheduled = false;
        return;
      }
      if (_awaitingResumeChoice) {
        _focusRestoreScheduled = false;
        return;
      }
      if (_rootPlayerFocusNode.canRequestFocus) {
        _rootPlayerFocusNode.requestFocus();
      }
      _focusRestoreScheduled = false;
    });
  }

  /// عند إخفاء أزرار التحكم العلوية — إرجاع التركيز للمشغّل (تشغيل/إيقاف على التلفاز).
  void _releaseToolbarFocusToPlayer() {
    _liveFavoriteFocusNode.unfocus();
    _aspectRatioFocusNode.unfocus();
    _settingsGearFocusNode.unfocus();
    _playButtonFocusNode.unfocus();
    _vodSeekBarFocusNode.unfocus();
    _vodBackFocusNode.unfocus();
    _vodLockFocusNode.unfocus();
    _vodAudioSubsFocusNode.unfocus();
    _vodPipFocusNode.unfocus();
    _requestRootFocusOnce();
  }

  Future<void> _showMovieHintOnce() async {
    final forEpisodes = _isSeriesStyle;
    if (!_isMovieStyle && !forEpisodes) return;
    final prefs = await SharedPreferences.getInstance();
    final prefsKey = forEpisodes
        ? 'episode_down_hint_shown'
        : 'movie_down_hint_shown';
    final shown = prefs.getBool(prefsKey) ?? false;
    if (!shown && mounted) {
      _movieHintShowTimer?.cancel();
      _movieHintHideTimer?.cancel();
      _movieHintShowTimer = Timer(const Duration(seconds: 3), () async {
        if (!mounted) return;
        _fvSetState(() => _showMovieDownHint = true);
        await prefs.setBool(prefsKey, true);
        _movieHintHideTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) _fvSetState(() => _showMovieDownHint = false);
        });
      });
    }
  }

  Future<void> _showLiveHintOnce() async {
    if (!widget.isLive || _showLiveIptvOverlay) return;
    final prefs = await SharedPreferences.getInstance();
    const prefsKey = 'live_down_hint_shown';
    final shown = prefs.getBool(prefsKey) ?? false;
    if (!shown && mounted) {
      _liveHintShowTimer?.cancel();
      _liveHintHideTimer?.cancel();
      _liveHintShowTimer = Timer(const Duration(seconds: 3), () async {
        if (!mounted || _showLiveIptvOverlay) return;
        _fvSetState(() => _showLiveDownHint = true);
        await prefs.setBool(prefsKey, true);
        _liveHintHideTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) _fvSetState(() => _showLiveDownHint = false);
        });
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Xtream Codes EPG (get_short_epg) for LIVE header
}
