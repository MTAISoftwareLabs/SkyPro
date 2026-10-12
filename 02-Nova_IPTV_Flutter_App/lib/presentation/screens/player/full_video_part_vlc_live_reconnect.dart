part of '../screens.dart';

/// Confirmed hard stall (stopped/error/not playing) before reconnect.
const Duration _kLiveStallThreshold = Duration(seconds: 2);
/// First-frame / init hang only — keep generous so slow opens stay intact.
const Duration _kLiveInitStallThreshold = Duration(seconds: 14);
/// Absolute max continuous buffering (حتى لو كاين نمو بطيء جداً).
const Duration _kLiveBufferingGrace = Duration(seconds: 60);
/// Buffering بلا أي تقدّم (موضع/بافر) = ستريم ميت غالباً — أسرع من الـ grace الكامل.
const Duration _kLiveBufferStarveThreshold = Duration(seconds: 12);
/// Real picture freeze (VLC): no progress heartbeat while stream should be alive.
const Duration _kLiveFrozenThreshold = Duration(seconds: 15);
/// Exo playing لكن بلا تقدّم حقيقي — وسط بين السرعة وعدم الحساسية الزائدة.
const Duration _kLiveFrozenThresholdExo = Duration(seconds: 22);
/// Ignore freeze checks briefly after start/reconnect (startup jitter).
const Duration _kLiveArmBeforeFreezeCheck = Duration(seconds: 5);
const Duration _kLiveStaticStreamHealthyAfter = Duration(seconds: 12);
/// Poll often enough to notice a freeze quickly without heavy work.
const Duration _kLiveWatchdogInterval = Duration(seconds: 1);
const double _kLiveBufferProgressDelta = 0.02;
/// تأكيدات متتالية (كل ثانية) قبل reconnect عند تجمّد/جوع البافر.
const int _kExoStallConfirmTicks = 2;
/// توقف كلي (!playing && !buffering): 3 ثوانٍ متتالية.
const int _kExoHardStopConfirmTicks = 3;

/// مهلة أول إطار صحي — إعادة محاولة على نفس المحرّك فقط (بلا تبديل Exo↔VLC).
const Duration _kLiveNeverHealthySameEngineRetry = Duration(seconds: 9);

extension _LiveStreamKeepAlive on _FullVideoScreenState {
  bool get _liveKeepAliveEnabled =>
      widget.isLive &&
      _activePlaybackUrl.isNotEmpty &&
      !_isInPipMode &&
      !_enteringPipMode;

  void _resetLiveKeepAliveState() {
    _vlcLiveStallSince = null;
    _vlcLiveInitStallSince = null;
    _vlcLiveBufferingSince = null;
    _exoBufferStarveSince = null;
    _exoStallConfirmTicks = 0;
    _liveLastProgressAt = null;
    _liveLastPositionSnapshot = null;
    _liveLastBufferPercentSnapshot = null;
    _liveHadHealthyPlayback = false;
    _livePlayingSince = null;
    _liveKeepAliveArmedAt = null;
    _vlcLiveReconnectAttempt = 0;
    _vlcLiveReconnectBusy = false;
    _vlcLivePlayNudgeAt = null;
    _cancelLiveKeepAliveTimers();
    _cancelLiveNeverHealthyFallbackTimer();
  }

  void _seedLiveKeepAliveHeartbeat() {
    final now = DateTime.now();
    _liveLastProgressAt = now;
    _liveLastPositionSnapshot = null;
    _liveLastBufferPercentSnapshot = null;
    _livePlayingSince = null;
    _liveKeepAliveArmedAt = now.add(_kLiveArmBeforeFreezeCheck);
    // Exo فقط — VLC يعتمد على watchdog الخفيف بلا إعادة تحميل مبكرة.
    if (_useExo) {
      _armLiveNeverHealthyFallbackTimer();
    } else {
      _cancelLiveNeverHealthyFallbackTimer();
    }
  }

  void _cancelLiveKeepAliveTimers() {
    _vlcLiveWatchdogTimer?.cancel();
    _vlcLiveWatchdogTimer = null;
    _vlcLiveReconnectTimer?.cancel();
    _vlcLiveReconnectTimer = null;
  }

  void _cancelLiveNeverHealthyFallbackTimer() {
    _liveNeverHealthyTimer?.cancel();
    _liveNeverHealthyTimer = null;
  }

  /// مؤقّت أول تشغيل: إلا ما وصلاتش لتشغيل صحي، عاود نفس المحرّك فقط.
  void _armLiveNeverHealthyFallbackTimer() {
    _cancelLiveNeverHealthyFallbackTimer();
    if (!widget.isLive || !_useExo) return;
    final sessionAtArm = _activeSessionId;
    final urlAtArm = _activePlaybackUrl;
    _liveNeverHealthyTimer = Timer(_kLiveNeverHealthySameEngineRetry, () {
      _liveNeverHealthyTimer = null;
      if (!mounted || !widget.isLive || !_useExo) return;
      if (sessionAtArm != _activeSessionId) return;
      if (_liveHadHealthyPlayback) return;
      if (_userRequestedLivePause) return;
      if (_isSwitchingLiveChannel || _liveZapInFlight) return;
      if (_vlcLiveReconnectBusy || _vlcLiveMediaSwapBusy) return;
      final url = urlAtArm.isNotEmpty ? urlAtArm : _activePlaybackUrl;
      if (url.isEmpty) return;
      unawaited(_recoverExoLiveFullRestart(url, sessionAtArm));
    });
  }

  void _startLiveKeepAliveWatchdog() {
    if (!_liveKeepAliveEnabled) return;
    _vlcLiveWatchdogTimer?.cancel();
    _vlcLiveWatchdogTimer = Timer.periodic(
      _kLiveWatchdogInterval,
      (_) {
        try {
          _evaluateLiveKeepAlive();
        } catch (_) {
          // keep watchdog alive
        }
      },
    );
  }

  void _stopLiveKeepAliveWatchdog() {
    _cancelLiveKeepAliveTimers();
  }

  bool _livePlaybackProgressChanged({
    required Duration position,
    required double bufferPercent,
  }) {
    if (_liveLastPositionSnapshot != position) return true;
    final lastBuffer = _liveLastBufferPercentSnapshot;
    if (lastBuffer == null) return false;
    return (bufferPercent - lastBuffer).abs() > _kLiveBufferProgressDelta;
  }

  void _updateLiveProgressHeartbeat({
    required bool isInitialized,
    required bool isPlaying,
    required bool isBuffering,
    required Duration position,
    required double bufferPercent,
  }) {
    if (!widget.isLive || _userRequestedLivePause || !isInitialized) return;
    if (!isPlaying && !isBuffering) {
      _livePlayingSince = null;
      return;
    }

    if (isPlaying && !isBuffering) {
      _livePlayingSince ??= DateTime.now();
      if (!_liveHadHealthyPlayback &&
          DateTime.now().difference(_livePlayingSince!) >=
              _kLiveStaticStreamHealthyAfter) {
        _liveHadHealthyPlayback = true;
        _cancelLiveNeverHealthyFallbackTimer();
      }
    } else {
      _livePlayingSince = null;
    }

    final changed = _livePlaybackProgressChanged(
      position: position,
      bufferPercent: bufferPercent,
    );

    // Some live TS/HLS feeds keep a static clock while decoding fine (VLC).
    // Exo: only real progress refreshes the heartbeat so a frozen frame triggers reconnect.
    if (isPlaying) {
      if (changed) {
        _liveLastPositionSnapshot = position;
        _liveLastBufferPercentSnapshot = bufferPercent;
        _liveLastProgressAt = DateTime.now();
        if (!isBuffering) {
          _liveHadHealthyPlayback = true;
          _cancelLiveNeverHealthyFallbackTimer();
          final ch = _currentLiveChannel ?? widget.channelLive;
          if (ch != null &&
              (_liveWatchTrackedChannel == null ||
                  !liveChannelsMatch(_liveWatchTrackedChannel!, ch))) {
            _liveWatchBegin(ch);
          }
          _liveWatchSawRealProgress = true;
          _liveWatchSyncPlaying(true);
        }
      } else if (!_useExo && !isBuffering) {
        // VLC static PTS: keep heartbeat warm while playing without clock movement.
        _liveLastProgressAt = DateTime.now();
      }
    } else if (changed && isBuffering) {
      _liveLastPositionSnapshot = position;
      _liveLastBufferPercentSnapshot = bufferPercent;
      _liveLastProgressAt = DateTime.now();
    }
  }

  void _updateLiveProgressHeartbeatFromVlc(VlcPlayerValue value) {
    _updateLiveProgressHeartbeat(
      isInitialized: value.isInitialized,
      isPlaying: value.isPlaying,
      isBuffering:
          value.isBuffering || value.playingState == PlayingState.buffering,
      position: value.position,
      bufferPercent: value.bufferPercent,
    );
  }

  bool _isLivePictureFrozen() {
    if (!_liveHadHealthyPlayback || _userRequestedLivePause) return false;
    final armedAt = _liveKeepAliveArmedAt;
    if (armedAt != null && DateTime.now().isBefore(armedAt)) return false;
    final last = _liveLastProgressAt;
    if (last == null) return false;
    final threshold =
        _useExo ? _kLiveFrozenThresholdExo : _kLiveFrozenThreshold;
    return DateTime.now().difference(last) >= threshold;
  }

  bool _isLiveBufferingTooLong() {
    final since = _vlcLiveBufferingSince;
    if (since == null) return false;
    return DateTime.now().difference(since) >= _kLiveBufferingGrace;
  }

  bool _trackLiveBuffering({required bool isBuffering}) {
    if (isBuffering) {
      _vlcLiveBufferingSince ??= DateTime.now();
      return !_isLiveBufferingTooLong();
    }
    _vlcLiveBufferingSince = null;
    return false;
  }

  bool _isVlcLivePlaybackHealthy(VlcPlayerValue value) {
    if (!value.isInitialized) return false;
    if (value.hasError || value.isEnded) return false;
    if (value.playingState == PlayingState.error ||
        value.playingState == PlayingState.stopped ||
        value.playingState == PlayingState.ended) {
      return false;
    }

    _updateLiveProgressHeartbeatFromVlc(value);

    final isBuffering =
        value.isBuffering || value.playingState == PlayingState.buffering;

    if (value.isPlaying) {
      return !_isLivePictureFrozen();
    }

    if (isBuffering) {
      return _trackLiveBuffering(isBuffering: true);
    }

    return false;
  }

  bool _isVlcLivePlaybackStalled(VlcPlayerValue value) {
    if (_userRequestedLivePause) return false;
    if (_vodLockActive) return false;
    if (_isSwitchingLiveChannel) return false;
    if (_vlcLiveReconnectBusy || _vlcLiveMediaSwapBusy) return false;

    if (_isLivePictureFrozen()) return true;

    if (!value.isInitialized) {
      _vlcLiveInitStallSince ??= DateTime.now();
      return DateTime.now().difference(_vlcLiveInitStallSince!) >=
          _kLiveInitStallThreshold;
    }
    _vlcLiveInitStallSince = null;

    if (value.hasError || value.isEnded) return true;
    if (value.playingState == PlayingState.error ||
        value.playingState == PlayingState.stopped ||
        value.playingState == PlayingState.ended) {
      return true;
    }

    final isBuffering =
        value.isBuffering || value.playingState == PlayingState.buffering;
    if (isBuffering) {
      return _isLiveBufferingTooLong();
    }

    if (value.playingState == PlayingState.paused && !value.isPlaying) {
      return true;
    }
    if (!value.isPlaying) return true;
    return false;
  }

  void _evaluateLiveKeepAlive() {
    if (!mounted || !_liveKeepAliveEnabled) return;
    if (_userRequestedLivePause || _isSwitchingLiveChannel) return;
    if (_isPlaybackTransitionInProgress) return;
    if (_liveZapInFlight) return;
    if (_vlcLiveReconnectBusy ||
        _vlcLiveReconnectTimer != null ||
        _vlcLiveMediaSwapBusy) {
      return;
    }

    if (_useExo) {
      _evaluateExoLiveKeepAlive();
      return;
    }

    final vc = _videoPlayerController;
    if (vc == null) {
      _markLiveStalledAndMaybeReconnect();
      return;
    }

    final value = vc.value;
    if (value.hasError || value.playingState == PlayingState.error) {
      _scheduleLiveReconnect(immediate: true);
      return;
    }

    if (_isVlcLivePlaybackHealthy(value)) {
      _vlcLivePlayNudgeAt = null;
      _clearLiveStallMarkers();
      return;
    }

    // توقف بدون خطأ: جرّب play مرة قبل إعادة التحميل الكاملة (يقلل الكراش).
    final isBuffering =
        value.isBuffering || value.playingState == PlayingState.buffering;
    if (value.isInitialized &&
        !value.isPlaying &&
        !isBuffering &&
        !_isLivePictureFrozen()) {
      final nudgedAt = _vlcLivePlayNudgeAt;
      final canNudge = nudgedAt == null ||
          DateTime.now().difference(nudgedAt) > const Duration(seconds: 4);
      if (canNudge) {
        _vlcLivePlayNudgeAt = DateTime.now();
        try {
          unawaited(vc.play());
        } catch (_) {}
        return;
      }
    }

    if (!_isVlcLivePlaybackStalled(value)) return;
    _recordVlcLiveCachingStruggle(_activePlaybackUrl);
    _markLiveStalledAndMaybeReconnect();
  }

  /// Exo live: كشف ذكي — سريع للستريم الميت، متسامح مع التوقفات القصيرة.
  void _evaluateExoLiveKeepAlive() {
    final ctrl = _exoController;
    final c = ctrl?.videoPlayerController;
    if (ctrl == null || c == null) {
      if (_liveHadHealthyPlayback) {
        _markLiveStalledAndMaybeReconnect();
      }
      return;
    }

    final value = c.value;
    final initialized = ctrl.isVideoInitialized() == true;
    if (!initialized) return;

    if (value.hasError) {
      _exoStallConfirmTicks = 0;
      _exoBufferStarveSince = null;
      _scheduleLiveReconnect(immediate: true);
      return;
    }

    var bufferPct = 0.0;
    for (final range in value.buffered) {
      final end = range.end;
      if (end > Duration.zero) {
        bufferPct = math.max(bufferPct, end.inMilliseconds / 1000.0);
      }
    }
    final progressChanged = _livePlaybackProgressChanged(
      position: value.position,
      bufferPercent: bufferPct,
    );

    // ── Buffering ───────────────────────────────────────────────
    if (value.isBuffering) {
      _trackLiveBuffering(isBuffering: true);
      if (progressChanged) {
        // Rebuffer صحي: البافر/الموضع كيتحرّك — ما نعيدش الاتصال.
        _liveLastPositionSnapshot = value.position;
        _liveLastBufferPercentSnapshot = bufferPct;
        _liveLastProgressAt = DateTime.now();
        _exoBufferStarveSince = null;
        _exoStallConfirmTicks = 0;
        return;
      }
      // Buffering بلا نمو = جوع الستريم (أقصر من 60s).
      _exoBufferStarveSince ??= DateTime.now();
      final starved = DateTime.now().difference(_exoBufferStarveSince!) >=
          _kLiveBufferStarveThreshold;
      final absoluteLong = _isLiveBufferingTooLong();
      if (starved || absoluteLong) {
        if (_confirmExoStall(needed: _kExoStallConfirmTicks)) {
          _scheduleLiveReconnect(immediate: true);
        }
        return;
      }
      _exoStallConfirmTicks = 0;
      return;
    }
    _trackLiveBuffering(isBuffering: false);
    _exoBufferStarveSince = null;

    // ── Playing ─────────────────────────────────────────────────
    if (value.isPlaying) {
      if (progressChanged) {
        _liveLastPositionSnapshot = value.position;
        _liveLastBufferPercentSnapshot = bufferPct;
        _liveLastProgressAt = DateTime.now();
      }
      if (_isLivePictureFrozen()) {
        if (_confirmExoStall(needed: _kExoStallConfirmTicks)) {
          _scheduleLiveReconnect(immediate: true);
        }
        return;
      }
      _clearLiveStallMarkers();
      return;
    }

    // ── Hard stop: !playing && !buffering ───────────────────────
    // توقف قصير جداً (ومضة) يتجاهل؛ 3 ثوانٍ متتالية = ميت.
    if (_liveHadHealthyPlayback && !_userRequestedLivePause) {
      if (_confirmExoStall(needed: _kExoHardStopConfirmTicks)) {
        _markLiveStalledAndMaybeReconnect();
      }
      return;
    }
    _exoStallConfirmTicks = 0;
  }

  /// يزيد عدّاد التأكيد؛ يرجع true إلا وصلنا لعدد التأكيدات المطلوب.
  bool _confirmExoStall({required int needed}) {
    _exoStallConfirmTicks++;
    if (_exoStallConfirmTicks >= needed) {
      _exoStallConfirmTicks = 0;
      return true;
    }
    return false;
  }

  void _clearLiveStallMarkers() {
    _vlcLiveStallSince = null;
    _vlcLiveInitStallSince = null;
    _vlcLiveBufferingSince = null;
    _exoBufferStarveSince = null;
    _exoStallConfirmTicks = 0;
    if (_vlcLiveReconnectAttempt > 0) {
      _vlcLiveReconnectAttempt = 0;
    }
  }

  void _markLiveStalledAndMaybeReconnect() {
    // Confirmed picture freeze: reconnect ASAP (no extra stall wait / backoff).
    if (_isLivePictureFrozen()) {
      _scheduleLiveReconnect(immediate: true);
      return;
    }

    final now = DateTime.now();
    _vlcLiveStallSince ??= now;
    if (now.difference(_vlcLiveStallSince!) < _kLiveStallThreshold) return;
    _scheduleLiveReconnect(immediate: true);
  }

  /// [immediate]: real freeze/stop — start recovery now.
  /// Retries after failure still back off so we do not hammer a dying link.
  Duration _liveReconnectDelay({required bool immediate}) {
    if (immediate && _vlcLiveReconnectAttempt == 0) {
      return Duration.zero;
    }
    final attempt = _vlcLiveReconnectAttempt.clamp(0, 8);
    if (attempt == 0) {
      return const Duration(milliseconds: 300);
    }
    final seconds = (1 + attempt).clamp(1, 12);
    return Duration(seconds: seconds);
  }

  void _scheduleLiveReconnect({bool immediate = false}) {
    if (!mounted || !_liveKeepAliveEnabled) return;
    if (_userRequestedLivePause || _isSwitchingLiveChannel) return;
    // أثناء التصفح/الزاب السريع: لا تعِد تحميل بث قديم فوق القناة الجديدة.
    if (_liveZapInFlight || _vlcLiveMediaSwapBusy) return;
    if (_vlcLiveReconnectBusy || _vlcLiveReconnectTimer != null) return;

    _vlcLiveReconnectTimer = Timer(_liveReconnectDelay(immediate: immediate), () {
      _vlcLiveReconnectTimer = null;
      if (!mounted) return;
      if (_liveZapInFlight || _isSwitchingLiveChannel) return;
      if (_activePlaybackUrl.isEmpty) return;
      unawaited(_performLiveStreamReconnect());
    });
  }

  Future<void> _performLiveStreamReconnect() async {
    if (!mounted || !_liveKeepAliveEnabled) return;
    if (_userRequestedLivePause || _isSwitchingLiveChannel) return;
    if (_liveZapInFlight || _vlcLiveMediaSwapBusy) return;
    if (_vlcLiveReconnectBusy) return;

    final url = _activePlaybackUrl;
    if (url.isEmpty) return;

    _vlcLiveReconnectBusy = true;
    _vlcLiveReconnectAttempt += 1;
    final sessionAtStart = _activeSessionId;

    if (mounted) {
      _setProgressSafe(true);
    }

    try {
      // بعد الزاب: الجلسة أو الرابط تغيّرا — لا تُعد تحميل القناة الميتة.
      if (!mounted ||
          sessionAtStart != _activeSessionId ||
          url != _activePlaybackUrl ||
          _liveZapInFlight) {
        return;
      }
      if (_useExo) {
        // Soft reload first (same controller). Full VLC bounce only after
        // repeated failures — avoids visible teardown stutter.
        if (_vlcLiveReconnectAttempt <= 2) {
          await _recoverExoLiveSameController(url, sessionAtStart);
        } else {
          await _recoverExoLiveFullRestart(url, sessionAtStart);
        }
      } else {
        await _reconnectVlcLive(url, sessionAtStart);
      }

      if (!mounted ||
          sessionAtStart != _activeSessionId ||
          url != _activePlaybackUrl) {
        return;
      }
      _seedLiveKeepAliveHeartbeat();
      _clearLiveStallMarkers();
      _startLiveKeepAliveWatchdog();
    } catch (e) {
      if (mounted &&
          sessionAtStart == _activeSessionId &&
          url == _activePlaybackUrl &&
          !_liveZapInFlight) {
        _scheduleLiveReconnect();
      }
    } finally {
      _vlcLiveReconnectBusy = false;
      if (mounted && sessionAtStart == _activeSessionId) {
        _setProgressSafe(false);
      }
    }
  }

  /// Soft recovery: reload media on the same ExoPlayer (no dispose).
  Future<void> _recoverExoLiveSameController(
    String url,
    int sessionAtStart,
  ) async {
    if (!mounted || sessionAtStart != _activeSessionId) return;
    if (_liveZapInFlight || url != _activePlaybackUrl) return;
    await _playExoUrl(url);
  }

  /// Last resort: full Exo teardown + cold restart (no VLC bounce).
  Future<void> _recoverExoLiveFullRestart(
    String url,
    int sessionAtStart,
  ) async {
    if (!mounted || sessionAtStart != _activeSessionId) return;
    if (_liveZapInFlight || url != _activePlaybackUrl) return;
    _disposeExoSafely();
    await _awaitLiveSocketRelease();
    if (!mounted || sessionAtStart != _activeSessionId) return;
    if (_liveZapInFlight || url != _activePlaybackUrl) return;
    _currentPlayer = AppVideoPlayer.exo;
    if (mounted) _fvSetState(() {});
    await _playExoUrl(url);
  }

  Future<void> _reconnectVlcLive(String url, int sessionAtStart) async {
    // ديما full reset — بلا setMedia على نفس الـ instance (يسمّم بعد قناة ميتة).
    await _disposeVlcSafely();
    if (!mounted || sessionAtStart != _activeSessionId) return;
    await _playVlcUrl(url);
  }
}

