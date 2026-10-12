part of '../screens.dart';

// لون شريط تقدّم الأفلام/المسلسلات — يتبع الثيم المختار
Color get _kVodProgressTheme => kColorPrimary;

extension _VodPlayerControls on _FullVideoScreenState {
  String get _vodHeaderTitle {
    if (_isSeriesStyle && widget.serieEpisodes != null) {
      for (final ep in widget.serieEpisodes!) {
        if (ep == null) continue;
        if (ep.id?.toString() == _currentEpisodeId) {
          final season = (ep.season ?? '1').padLeft(2, '0');
          final epNum = (ep.episodeNum ?? '1').padLeft(2, '0');
          final name = ep.title?.trim();
          if (name != null && name.isNotEmpty) {
            return 'S$season.E$epNum $name';
          }
          return 'S$season.E$epNum';
        }
      }
    }
    return _currentPlaybackTitle;
  }

  String get _vodHeaderMeta {
    if (_isSeriesStyle) {
      return widget.channelSerie?.name?.trim() ?? '';
    }
    if (_isMovieStyle) {
      return widget.channelMovie?.name?.trim() ?? '';
    }
    return '';
  }

  Future<void> _enterVodPipMode() async {
    if (widget.isLive) {
      Get.snackbar(
        '',
        'player_pip_unavailable'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (!_useExo) {
      final url = _currentPlaybackUrl;
      if (url.isEmpty) {
        Get.snackbar(
          '',
          'player_pip_unavailable'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      final resumeSec = _sliderVN.value;
      await _playExoUrl(url);
      await _waitExoReadyForPip();
      if (!mounted) return;
      if (resumeSec > 0) {
        try {
          await _exoController?.seekTo(
            Duration(seconds: resumeSec.round()),
          );
        } catch (_) {}
      }
    }

    final ctrl = _exoController;
    if (ctrl == null || ctrl.isVideoInitialized() != true) {
      await _waitExoReadyForPip();
    }
    final ready = _exoController;
    if (ready == null || ready.isVideoInitialized() != true) {
      Get.snackbar(
        '',
        'player_pip_unavailable'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    _wasPlayingBeforePip = isPlayed;
    _enteringPipMode = true;
    ready.setBetterPlayerGlobalKey(_exoPlayerGlobalKey);
    try {
      await ready.enablePictureInPicture(_exoPlayerGlobalKey);
      _isInPipMode = true;
      _startPipKeepAlive();
    } catch (e) {
      _isInPipMode = false;
      _enteringPipMode = false;
      _wasPlayingBeforePip = false;
      _stopPipKeepAlive();
      Get.snackbar(
        '',
        'player_pip_unavailable'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _waitExoReadyForPip() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (mounted && DateTime.now().isBefore(deadline)) {
      final ctrl = _exoController;
      if (ctrl != null && ctrl.isVideoInitialized() == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  void _armSuggestionSwipeTapGuard() {
    _suggestionSwipeJustHandled = true;
    _suggestionSwipeTapGuardTimer?.cancel();
    _suggestionSwipeTapGuardTimer = Timer(const Duration(milliseconds: 350), () {
      _suggestionSwipeJustHandled = false;
      _suggestionSwipeTapGuardTimer = null;
    });
  }

  void _handleSuggestionsVerticalSwipe(
    DragEndDetails details, {
    required double startDx,
    required double dragDy,
    double absDragDy = 0,
  }) {
    if (_vodLockActive || _showLiveIptvOverlay) return;
    if (_bvGestureConsumed) return;
    // TV unchanged: only remote ↓ from toolbar/focus opens suggestions.
    if (!mounted || isTvDevice(context)) return;

    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;

    // Tiny movement = tap, not a swipe (don't mix with show/hide controls).
    final travel = absDragDy > 0 ? absDragDy : dragDy.abs();
    if (travel < _kSuggestionClickSlopPx) return;

    final velocity = details.primaryVelocity ?? 0;
    final minDrag = height * _kSuggestionMinDragFraction;
    // Phone: swipe bottom → top (up) opens; swipe down closes.
    final swipeDown = dragDy > minDrag ||
        (velocity > _kSuggestionSwipeDownVelocity &&
            travel > _kSuggestionClickSlopPx * 1.5);
    final swipeUp = dragDy < -minDrag ||
        (velocity < _kSuggestionSwipeUpVelocity &&
            travel > _kSuggestionClickSlopPx * 1.5);

    if (swipeDown) {
      if (_showMovieSuggestionsOverlay) {
        _armSuggestionSwipeTapGuard();
        _closeMovieOverlay();
        return;
      }
      if (_showEpisodeSuggestionsOverlay) {
        _armSuggestionSwipeTapGuard();
        _closeEpisodeOverlay();
        return;
      }
      if (_showLiveChannelSuggestionsOverlay) {
        _armSuggestionSwipeTapGuard();
        _closeLiveChannelOverlay();
        return;
      }
    }

    if (!swipeUp) return;

    // Allow swipe above the centered toolbar; only skip weak edge nudges.
    if (_isInBvEdgeZone(startDx, width) && travel < minDrag * 1.15) {
      return;
    }

    if (widget.isLive) {
      if (!_showLiveChannelSuggestionsOverlay) {
        _armSuggestionSwipeTapGuard();
        _openLiveChannelOverlay();
      }
      return;
    }

    if (_showMovieSuggestionsOverlay || _showEpisodeSuggestionsOverlay) return;

    if (_isMovieStyle) {
      _armSuggestionSwipeTapGuard();
      _openMovieOverlay();
    } else if (_isSeriesStyle &&
        widget.serieEpisodes != null &&
        widget.serieEpisodes!.isNotEmpty) {
      _armSuggestionSwipeTapGuard();
      _openEpisodeOverlay();
    }
  }

  void _ensureVodControlsVisible() {
    if (_vodLockActive) return;
    if (!showControllersVideo) {
      _scheduleFullVideoRebuild(() => showControllersVideo = true);
      _schedulePlayerControlsHideAfterIdle();
    } else {
      _touchPlayerControlsActivity();
    }
  }

  void _vodFocusSeekBar() {
    void tryFocus() {
      if (!mounted) return;
      if (_vodSeekBarFocusNode.canRequestFocus) {
        _vodSeekBarFocusNode.requestFocus();
      }
    }

    _ensureVodControlsVisible();
    tryFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => tryFocus());
  }

  void _vodFocusBackButton() {
    void tryFocus() {
      if (!mounted) return;
      if (_vodBackFocusNode.canRequestFocus) {
        _vodBackFocusNode.requestFocus();
      }
    }

    _ensureVodControlsVisible();
    tryFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => tryFocus());
  }

  void _vodFocusPlayButton() {
    void tryFocus() {
      if (!mounted) return;
      if (_playButtonFocusNode.canRequestFocus) {
        _playButtonFocusNode.requestFocus();
      }
    }

    _ensureVodControlsVisible();
    tryFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => tryFocus());
  }

  void _vodFocusToolbarButton({FocusNode? preferred}) {
    _ensureVodControlsVisible();
    _touchPlayerControlsActivity();
    final target = preferred ?? _vodLockFocusNode;

    void tryFocus() {
      if (!mounted) return;
      if (_vodToolbarHasFocus()) return;
      if (_playButtonFocusNode.hasFocus) {
        _playButtonFocusNode.unfocus();
      }
      // Prefer ordered nextFocus while seek still owns focus (order 1 → 2).
      if (_vodSeekBarFocusNode.hasFocus) {
        if (_vodSeekBarFocusNode.nextFocus() && _vodToolbarHasFocus()) {
          return;
        }
      }
      _vodSeekBarFocusNode.unfocus();
      target.requestFocus();
      if (!_vodToolbarHasFocus()) {
        _vodLockFocusNode.requestFocus();
      }
    }

    tryFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tryFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) => tryFocus());
    });
  }

  bool _vodToolbarHasFocus() {
    return _vodLockFocusNode.hasFocus ||
        _vodAudioSubsFocusNode.hasFocus ||
        _vodSpeedFocusNode.hasFocus ||
        _aspectRatioFocusNode.hasFocus ||
        _vodPipFocusNode.hasFocus ||
        _streamInfoFocusNode.hasFocus;
  }

  bool _vodRemoteSeekAllowed() {
    return _rootPlayerFocusNode.hasFocus ||
        _playButtonFocusNode.hasFocus ||
        _vodSeekBarFocusNode.hasFocus;
  }

  KeyEventResult _vodToolbarHorizontalNavigate(LogicalKeyboardKey key) {
    final nodes = <FocusNode>[
      _vodLockFocusNode,
      _vodAudioSubsFocusNode,
      _vodSpeedFocusNode,
      _aspectRatioFocusNode,
      _vodPipFocusNode,
      _streamInfoFocusNode,
    ];
    var focusedIndex = -1;
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].hasFocus) {
        focusedIndex = i;
        break;
      }
    }
    if (focusedIndex < 0) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowLeft && focusedIndex > 0) {
      nodes[focusedIndex - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        focusedIndex < nodes.length - 1) {
      nodes[focusedIndex + 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  void _vodCaptureToolbarFocus() {
    if (_vodLockFocusNode.hasFocus) {
      _vodRestoreToolbarFocusNode = _vodLockFocusNode;
    } else if (_vodAudioSubsFocusNode.hasFocus) {
      _vodRestoreToolbarFocusNode = _vodAudioSubsFocusNode;
    } else if (_vodSpeedFocusNode.hasFocus) {
      _vodRestoreToolbarFocusNode = _vodSpeedFocusNode;
    } else if (_aspectRatioFocusNode.hasFocus) {
      _vodRestoreToolbarFocusNode = _aspectRatioFocusNode;
    } else if (_vodPipFocusNode.hasFocus) {
      _vodRestoreToolbarFocusNode = _vodPipFocusNode;
    } else if (_streamInfoFocusNode.hasFocus) {
      _vodRestoreToolbarFocusNode = _streamInfoFocusNode;
    } else {
      _vodRestoreToolbarFocusNode = _vodLockFocusNode;
    }
  }

  void _vodRestoreToolbarFocus() {
    _ensureVodControlsVisible();
    final target = _vodRestoreToolbarFocusNode ?? _vodLockFocusNode;
    void tryFocus() {
      if (!mounted) return;
      if (target.canRequestFocus) {
        target.requestFocus();
      }
    }

    tryFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => tryFocus());
  }

  bool _vodTryOpenSuggestionsOverlay() {
    if (_isMovieStyle && !_showMovieSuggestionsOverlay) {
      _openMovieOverlay();
      return true;
    }
    if (_isSeriesStyle &&
        !_showEpisodeSuggestionsOverlay &&
        widget.serieEpisodes != null &&
        widget.serieEpisodes!.isNotEmpty) {
      _openEpisodeOverlay();
      return true;
    }
    return false;
  }

  KeyEventResult _vodToolbarVerticalKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) {
      return _vodVerticalFocusNavigate(key);
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _vodTryOpenSuggestionsOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _vodVerticalFocusNavigate(LogicalKeyboardKey key) {
    if (widget.isLive) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (_vodBackFocusNode.hasFocus) {
        _vodFocusPlayButton();
        return KeyEventResult.handled;
      }
      if (_playButtonFocusNode.hasFocus) {
        if (_vodControlsLocked) return KeyEventResult.ignored;
        _vodFocusSeekBar();
        return KeyEventResult.handled;
      }
      if (_rootPlayerFocusNode.hasFocus) {
        if (_vodControlsLocked) return KeyEventResult.ignored;
        _vodFocusPlayButton();
        return KeyEventResult.handled;
      }
      if (_vodSeekBarFocusNode.hasFocus) {
        _vodFocusToolbarButton();
        return KeyEventResult.handled;
      }
      if (_vodToolbarHasFocus()) {
        if (_vodTryOpenSuggestionsOverlay()) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled;
      }
      // Fallback: show controls and land on play.
      if (!_vodControlsLocked) {
        _vodFocusPlayButton();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_vodControlsLocked || !showControllersVideo) {
        return KeyEventResult.ignored;
      }

      if (_vodToolbarHasFocus()) {
        _vodFocusSeekBar();
        return KeyEventResult.handled;
      }
      if (_vodSeekBarFocusNode.hasFocus) {
        _vodFocusPlayButton();
        return KeyEventResult.handled;
      }
      if (_playButtonFocusNode.hasFocus) {
        _vodFocusBackButton();
        return KeyEventResult.handled;
      }
      if (_vodBackFocusNode.hasFocus) {
        _vodBackFocusNode.unfocus();
        _requestRootFocusOnce();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _showVodAudioSubtitlesPicker() async {
    if (widget.isLive) return;
    subtitleStep('STEP 1', 'Audio & Subtitle button pressed');
    _touchPlayerControlsActivity();
    if (_playerOptionSheetOpen) return;
    if (!mounted) return;

    final action = await _openPlayerOptionSheet<String>(
      builder: (ctx) {
        return _PlayerSheetShell(
          centered: true,
          header: _PlayerSheetHeader(
            icon: LucideIcons.audio_lines,
            title: 'player_audio_subtitles'.tr,
          ),
          children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: _PlayerFocusTile(
                autofocus: true,
                leading: Icon(
                  LucideIcons.audio_lines,
                  color: kColorFocus,
                  size: 22,
                ),
                title: 'player_audio_tracks'.tr,
                onTap: () => Navigator.of(ctx).pop('audio'),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _PlayerFocusTile(
                leading: Icon(
                  Icons.subtitles_outlined,
                  color: kColorFocus,
                  size: 22,
                ),
                title: 'player_subtitles'.tr,
                onTap: () {
                  subtitleStep(
                    'STEP 1a',
                    'Subtitles menu item tapped (VOD chooser)',
                  );
                  Navigator.of(ctx).pop('subtitles');
                },
              ),
            ),
          ],
        );
      },
    );

    if (!mounted || action == null) return;
    // Let the chooser finish dismissing before opening the next sheet.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;

    if (action == 'audio') {
      await _showAudioTracksPicker();
    } else if (action == 'subtitles') {
      await _openSubtitleSearchSheet();
    }
  }

  String _playbackSpeedLabel(double speed) {
    if ((speed - 1.0).abs() < 0.001) return 'player_speed_normal'.tr;
    final text = speed == speed.roundToDouble()
        ? speed.toStringAsFixed(0)
        : speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '${text}x';
  }

  Future<void> _applyPlaybackSpeed(double speed) async {
    final clamped = speed.clamp(0.25, 2.0).toDouble();
    _playbackSpeed = clamped;
    try {
      if (_useExo) {
        await _exoController?.setSpeed(clamped);
      } else {
        await _videoPlayerController?.setPlaybackSpeed(clamped);
      }
    } catch (_) {}
    if (mounted) _fvSetState(() {});
  }

  Future<T?> _openPlayerOptionSheet<T>({
    required Widget Function(BuildContext ctx) builder,
  }) async {
    _cancelPlayerControlsHideTimer();
    _playerOptionSheetOpen = true;
    try {
      if (!mounted) return null;
      return await showModalBottomSheet<T>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        useRootNavigator: true,
        builder: builder,
      );
    } finally {
      _playerOptionSheetOpen = false;
      if (mounted && showControllersVideo) {
        _schedulePlayerControlsHideAfterIdle();
      }
    }
  }

  Future<void> _showPlaybackSpeedPicker() async {
    if (widget.isLive) return;
    _touchPlayerControlsActivity();
    if (!mounted) return;
    const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    await _openPlayerOptionSheet<void>(
      builder: (ctx) {
        var order = 0.0;
        return _PlayerSheetShell(
          header: _PlayerSheetHeader(
            icon: LucideIcons.gauge,
            title: 'player_playback_speed'.tr,
          ),
          children: [
            for (final speed in speeds)
              FocusTraversalOrder(
                order: NumericFocusOrder(order++),
                child: _PlayerFocusTile(
                  autofocus: (speed - _playbackSpeed).abs() < 0.001,
                  selected: (speed - _playbackSpeed).abs() < 0.001,
                  compact: true,
                  title: _playbackSpeedLabel(speed),
                  onTap: () {
                    unawaited(_applyPlaybackSpeed(speed));
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showLiveAudioTracksPicker() async {
    if (!widget.isLive) return;
    await _showAudioTracksPicker();
  }

  /// Audio tracks for Live + Movies/Series (Exo ASMS/native or VLC demux).
  Future<void> _showAudioTracksPicker() async {
    // زر الصوت كي يطلق onTap + OK ف نفس الوقت → جوج نداءات = قائمة + snackbar غالط
    if (_liveAudioPickerBusy || _playerOptionSheetOpen) return;
    _liveAudioPickerBusy = true;
    _touchPlayerControlsActivity();
    try {
      if (_useExo) {
        await _showExoLiveAudioTracksPicker();
      } else {
        await _showVlcLiveAudioTracksPicker();
      }
    } finally {
      _liveAudioPickerBusy = false;
    }
  }

  String _friendlyAudioTrackTitle(String? label, String? language, {int? fallbackIndex}) {
    String pick = (label ?? '').trim();
    if (pick.isEmpty) pick = (language ?? '').trim();
    if (pick.startsWith('nova:')) {
      final parts = pick.substring(5).split('|');
      if (parts.length >= 5 && parts[4].trim().isNotEmpty) {
        pick = parts[4].trim();
      }
    }
    if (pick.isEmpty) {
      return fallbackIndex == null
          ? 'player_track_default'.tr
          : '${'player_track_default'.tr} ${fallbackIndex + 1}';
    }
    // Common ISO-ish codes → readable names for the picker.
    const names = <String, String>{
      'en': 'English',
      'eng': 'English',
      'ar': 'Arabic',
      'ara': 'Arabic',
      'fr': 'French',
      'fra': 'French',
      'fre': 'French',
      'it': 'italiano',
      'ita': 'italiano',
      'es': 'Español',
      'spa': 'Español',
      'de': 'Deutsch',
      'deu': 'Deutsch',
      'ger': 'Deutsch',
      'pt': 'Português',
      'por': 'Português',
      'tr': 'Türkçe',
      'tur': 'Türkçe',
      'ru': 'Русский',
      'rus': 'Русский',
      'und': 'Audio',
    };
    final mapped = names[pick.toLowerCase()];
    if (mapped != null) return mapped;
    return pick;
  }

  Future<void> _showExoLiveAudioTracksPicker() async {
    final ctrl = _exoController;
    if (ctrl == null) return;

    // Prefer playlist ASMS audio; fall back to Exo demux tracks (MPEG-TS multi-PID).
    var audios = List<BetterPlayerAsmsAudioTrack>.from(
      ctrl.betterPlayerAsmsAudioTracks ?? const <BetterPlayerAsmsAudioTrack>[],
    );
    if (audios.isEmpty) {
      for (var attempt = 0; attempt < 4; attempt++) {
        final native = await ctrl.getNativeAudioTracks();
        audios = [
          for (final row in native)
            BetterPlayerAsmsAudioTrack(
              id: (row['id'] as num?)?.toInt() ??
                  (row['groupIndex'] as num?)?.toInt(),
              label: (row['label'] as String?)?.trim().isNotEmpty == true
                  ? (row['label'] as String).trim()
                  : (row['language'] as String?)?.trim(),
              language: (row['language'] as String?)?.trim().isNotEmpty == true
                  ? (row['language'] as String).trim()
                  : ((row['label'] as String?)?.trim().isNotEmpty == true
                      ? (row['label'] as String).trim()
                      : 'und'),
              isDefault: false,
            ),
        ];
        if (audios.isNotEmpty) break;
        await Future<void>.delayed(Duration(milliseconds: 280 + attempt * 180));
        if (!mounted) return;
      }
    }

    if (audios.isEmpty) {
      if (_playerOptionSheetOpen) return;
      Get.snackbar(
        '',
        'player_no_tracks'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final defaultTrack = BetterPlayerAsmsAudioTrack(
      id: -1,
      label: 'player_track_default'.tr,
      language: null,
      isDefault: true,
    );
    final rows = <BetterPlayerAsmsAudioTrack>[defaultTrack, ...audios];
    final selectedId = ctrl.betterPlayerAsmsAudioTrack?.id;
    final selectedIsDefault = _liveAudioUseDefault ||
        ctrl.betterPlayerAsmsAudioTrack?.isDefault == true ||
        selectedId == null ||
        selectedId < 0;

    if (!mounted) return;
    await _openPlayerOptionSheet<void>(
      builder: (ctx) {
        return _PlayerSheetShell(
          centered: true,
          header: _PlayerSheetHeader(
            icon: LucideIcons.audio_lines,
            title: 'player_audio_tracks'.tr,
          ),
          children: [
            for (var i = 0; i < rows.length; i++)
              FocusTraversalOrder(
                order: NumericFocusOrder(i.toDouble()),
                child: _PlayerFocusTile(
                  autofocus: rows[i].isDefault == true
                      ? selectedIsDefault
                      : (!selectedIsDefault && rows[i].id == selectedId),
                  selected: rows[i].isDefault == true
                      ? selectedIsDefault
                      : (!selectedIsDefault && rows[i].id == selectedId),
                  compact: true,
                  title: rows[i].isDefault == true
                      ? 'player_track_default'.tr
                      : _friendlyAudioTrackTitle(
                          rows[i].label,
                          rows[i].language,
                          fallbackIndex: i - 1,
                        ),
                  onTap: () {
                    final pickDefault = rows[i].isDefault == true;
                    _liveAudioUseDefault = pickDefault;
                    ctrl.setAudioTrack(rows[i]);
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showVlcLiveAudioTracksPicker() async {
    final ctrl = _videoPlayerController;
    if (ctrl == null) return;
    Map<int, String> tracks = const {};
    int? currentId;
    // Tracks often appear only after demux — retry briefly.
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        tracks = await ctrl.getAudioTracks().timeout(
          const Duration(milliseconds: 1200),
        );
        currentId = await ctrl.getAudioTrack().timeout(
          const Duration(milliseconds: 600),
        );
      } catch (_) {
        tracks = const {};
      }
      final usable = tracks.entries.where((e) => e.key >= 0).length;
      if (usable > 0) break;
      await Future<void>.delayed(Duration(milliseconds: 350 + attempt * 200));
      if (!mounted) return;
    }
    final entries = tracks.entries
        .where((e) => e.key >= 0)
        .toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) {
      Get.snackbar(
        '',
        'player_no_tracks'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    if (!mounted) return;
    await _openPlayerOptionSheet<void>(
      builder: (ctx) {
        final useDefault = _liveAudioUseDefault;
        return _PlayerSheetShell(
          centered: true,
          header: _PlayerSheetHeader(
            icon: LucideIcons.audio_lines,
            title: 'player_audio_tracks'.tr,
          ),
          children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: _PlayerFocusTile(
                autofocus: useDefault,
                selected: useDefault,
                compact: true,
                title: 'player_track_default'.tr,
                onTap: () {
                  _liveAudioUseDefault = true;
                  // -1 → native resets to first demux track (does not mute).
                  unawaited(ctrl.setAudioTrack(-1));
                  Navigator.of(ctx).pop();
                },
              ),
            ),
            for (var i = 0; i < entries.length; i++)
              FocusTraversalOrder(
                order: NumericFocusOrder((i + 1).toDouble()),
                child: _PlayerFocusTile(
                  autofocus: !useDefault && entries[i].key == currentId,
                  selected: !useDefault && entries[i].key == currentId,
                  compact: true,
                  title: _friendlyAudioTrackTitle(
                    entries[i].value,
                    null,
                    fallbackIndex: i,
                  ),
                  onTap: () {
                    _liveAudioUseDefault = false;
                    unawaited(ctrl.setAudioTrack(entries[i].key));
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  SubtitleContentContext _buildSubtitleContentContext() {
    if (_isMovieStyle) {
      return SubtitlePlaybackContextBuilder.fromMovie(
        channelMovie: widget.channelMovie!,
        title: widget.title,
        playbackUrl: _currentPlaybackUrl,
      );
    }
    return SubtitlePlaybackContextBuilder.fromSeries(
      channelSerie: widget.channelSerie!,
      title: widget.title,
      episodes: widget.serieEpisodes,
      currentEpisodeId: _currentEpisodeId,
      playbackUrl: _currentPlaybackUrl,
    );
  }

  Future<void> _openSubtitleSearchSheet() async {
    if (!_isMovieStyle && !_isSeriesStyle) return;

    // Open instantly — never block on IPTV/TMDB network before showing the sheet.
    var contextData = _buildSubtitleContentContext();
    String? tmdbId = contextData.tmdbId;
    var year = contextData.year;

    if (_isMovieStyle) {
      final streamId = widget.channelMovie?.streamId?.toString();
      if (streamId != null) {
        final detail = context.read<PrefetchCubit>().peekMovieDetail(streamId);
        tmdbId ??= detail?.info?.tmdbId;
        year ??= extractReleaseYear(detail?.info?.releasedate);
      }
    } else if (_isSeriesStyle) {
      final seriesId = widget.channelSerie?.seriesId?.toString();
      if (seriesId != null) {
        final detail = context.read<PrefetchCubit>().peekSerieDetail(seriesId);
        tmdbId ??= detail?.info?.tmdbId;
        year ??= extractReleaseYear(detail?.info?.releaseDate);
      }
    }

    final imdbId = SubtitleService.instance.peekCachedImdbId(
      tmdbId: tmdbId,
      isSeries: contextData.isSeries,
    );

    contextData = SubtitleContentContext(
      contentKey: contextData.contentKey,
      isSeries: contextData.isSeries,
      title: contextData.title,
      tmdbId: tmdbId,
      imdbId: imdbId,
      year: year,
      season: contextData.season,
      episode: contextData.episode,
      fileName: contextData.fileName,
    );

    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    // Let the Audio/Subtitles sheet finish dismissing.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    final selection = await SubtitleSearchSheet.show(
      context: context,
      contextData: contextData,
      onTurnOff: _turnOffSubtitles,
    );

    if (!mounted || selection == null) return;

    // Wait briefly for routes/overlays to clear before binding subtitles.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    await _applyDownloadedSubtitle(
      localPath: selection.localPath,
      displayName: selection.item.releaseName,
    );
    if (mounted) {
      _scheduleFullVideoRebuild();
      _touchPlayerControlsActivity();
    }
  }

  Future<void> _turnOffSubtitles() {
    if (_useExo) {
      final ctrl = _exoController;
      if (ctrl != null) {
        return ctrl.setupSubtitleSource(
          BetterPlayerSubtitlesSource(
            type: BetterPlayerSubtitlesSourceType.none,
            name: 'player_track_default'.tr,
          ),
        );
      }
    } else {
      final ctrl = _videoPlayerController;
      if (ctrl != null) {
        return ctrl.setSpuTrack(-1);
      }
    }
    return Future<void>.value();
  }

  Future<void> _applyDownloadedSubtitle({
    required String localPath,
    required String displayName,
  }) async {
    final file = File(localPath);
    if (!file.existsSync()) return;
    final absolutePath = file.absolute.path;

    if (_useExo) {
      final ctrl = _exoController;
      if (ctrl == null) return;
      await ctrl.setupSubtitleSource(
        BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.file,
          urls: [absolutePath],
          name: displayName,
          selectedByDefault: true,
        ),
      );
      // Some devices need a second bind after the modal/route dismiss animation.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || _exoController == null) return;
      await _exoController!.setupSubtitleSource(
        BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.file,
          urls: [absolutePath],
          name: displayName,
          selectedByDefault: true,
        ),
      );
      return;
    }

    final ctrl = _videoPlayerController;
    if (ctrl == null) return;
    await ctrl.addSubtitleFromFile(File(absolutePath), isSelected: true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || _videoPlayerController == null) return;
    await _videoPlayerController!
        .addSubtitleFromFile(File(absolutePath), isSelected: true);
  }

  Widget _buildVodPlayerControlsOverlay() {
    if (_vodLockActive) {
      return _buildVodLockedOverlay();
    }

    final bottomPad = MediaQuery.of(context).padding.bottom;
    final topPad = MediaQuery.of(context).padding.top;
    final overlayActive =
        showControllersVideo &&
        !(_showMovieSuggestionsOverlay || _showEpisodeSuggestionsOverlay);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _onBvVerticalDragStart,
      onVerticalDragUpdate: _onBvVerticalDragUpdate,
      onVerticalDragCancel: _onBvVerticalDragCancel,
      onVerticalDragEnd: (details) {
        _onBvVerticalDragEnd(details);
      },
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedOpacity(
      opacity: overlayActive && !progress ? 1 : (overlayActive ? 0.55 : 0),
      duration: const Duration(milliseconds: 220),
      child:
          overlayActive
              ? Stack(
                fit: StackFit.expand,
                children: [
                  ...[
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 22.h.clamp(120.0, 200.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.82),
                              Colors.black.withValues(alpha: 0.35),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 42.h.clamp(180.0, 320.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.92),
                              Colors.black.withValues(alpha: 0.5),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  Positioned(
                      top: topPad + 8,
                      left: 8,
                      right: 18,
                      child: Row(
                        children: [
                          ListenableBuilder(
                            listenable: _vodBackFocusNode,
                            builder: (context, _) {
                              final tv = isTvDevice(context);
                              final focused =
                                  tv && _vodBackFocusNode.hasFocus;
                              return Focus(
                                focusNode: _vodBackFocusNode,
                                canRequestFocus: tv,
                                skipTraversal: !tv,
                                onKeyEvent: (node, event) {
                                  if (event is! KeyDownEvent &&
                                      event is! KeyRepeatEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  final k = event.logicalKey;
                                  if (k == LogicalKeyboardKey.arrowDown ||
                                      k == LogicalKeyboardKey.arrowUp) {
                                    return _vodVerticalFocusNavigate(k);
                                  }
                                  if (_isOkLogicalKey(k) &&
                                      event is KeyDownEvent) {
                                    _popWithResult();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: GestureDetector(
                                  onTap: _popWithResult,
                                  behavior: HitTestBehavior.opaque,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            focused
                                                ? kColorFocus
                                                : Colors.transparent,
                                        width: focused ? 2.2 : 1,
                                      ),
                                      boxShadow:
                                          focused
                                              ? [
                                                BoxShadow(
                                                  color: kColorFocus.withValues(
                                                    alpha: 0.45,
                                                  ),
                                                  blurRadius: 12,
                                                  spreadRadius: 0.4,
                                                ),
                                              ]
                                              : null,
                                    ),
                                    child: const Icon(
                                      LucideIcons.arrow_left,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _vodHeaderTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Get.textTheme.headlineSmall!.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17.sp,
                                  ),
                                ),
                                if (_vodHeaderMeta.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _vodHeaderMeta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Text(
                              'HD',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontWeight: FontWeight.w800,
                                fontSize: 11.sp,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Center(
                      child: _LiveCenterControls(
                        isPlaying: _isVlcBuffering || isPlayed,
                        playFocusNode: _playButtonFocusNode,
                        allowFocus: isTvDevice(context),
                        onPlayPause: _togglePlayPause,
                        onPlayKey: (node, event) {
                          if (event is KeyDownEvent || event is KeyRepeatEvent) {
                            final lk = event.logicalKey;
                            if (lk == LogicalKeyboardKey.arrowDown ||
                                lk == LogicalKeyboardKey.arrowUp) {
                              return _vodVerticalFocusNavigate(lk);
                            }
                            // Keep focus on play; double left/right seeks.
                            // Never let directional focus jump to toolbar.
                            if (lk == LogicalKeyboardKey.arrowLeft ||
                                lk == LogicalKeyboardKey.arrowRight) {
                              if (event is KeyDownEvent) {
                                _handleKeyDownEvent(lk);
                              }
                              return KeyEventResult.handled;
                            }
                          }
                          if (!_isOkLogicalKey(event.logicalKey)) {
                            return KeyEventResult.ignored;
                          }
                          if (event is KeyDownEvent) {
                            _startOkLongPressTimer();
                            _togglePlayPause();
                            return KeyEventResult.handled;
                          }
                          if (event is KeyUpEvent) {
                            _cancelOkLongPressAndCheckTriggered();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        onRewind: () => _seekRelative(-10),
                        onForward: () => _seekRelative(10),
                        seekStyle: true,
                      ),
                    ),

                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: bottomPad + 12,
                      child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FocusTraversalOrder(
                              order: const NumericFocusOrder(1),
                              child: Focus(
                                focusNode: _vodSeekBarFocusNode,
                                canRequestFocus: isTvDevice(context),
                                skipTraversal: !isTvDevice(context),
                                onKeyEvent: _vodSeekBarOnKey,
                                child: ListenableBuilder(
                                  listenable: Listenable.merge([
                                    _positionVN,
                                    _durationVN,
                                    _sliderVN,
                                    _maxDurationVN,
                                    _validPositionVN,
                                    _bufferVN,
                                    _vodSeekBarFocusNode,
                                  ]),
                                  builder: (context, _) {
                                    final seekFocused =
                                        isTvDevice(context) &&
                                        _vodSeekBarFocusNode.hasFocus;
                                    final maxSec =
                                        _maxDurationSeconds < 1
                                            ? 1.0
                                            : _maxDurationSeconds;
                                    final posSec = sliderValue.clamp(
                                      0.0,
                                      maxSec,
                                    );
                                    // أثناء التمرير: لا تعرض تحميلاً مسبقاً (الثانوي = الرأس).
                                    final bufferedSec =
                                        _vodSeekBarHoldActive
                                            ? posSec
                                            : _bufferSeconds
                                                .clamp(posSec, maxSec)
                                                .toDouble();
                                    return Column(
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              position,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.92,
                                                ),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 11.sp,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              duration,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.92,
                                                ),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 11.sp,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color:
                                                  seekFocused
                                                      ? kColorFocus
                                                      : Colors.transparent,
                                              width: seekFocused ? 2 : 0,
                                            ),
                                          ),
                                          child: SliderTheme(
                                            data: SliderThemeData(
                                              trackHeight: 3.2,
                                              activeTrackColor:
                                                  _kVodProgressTheme,
                                              secondaryActiveTrackColor:
                                                  Colors.white.withValues(
                                                    alpha: 0.48,
                                                  ),
                                              inactiveTrackColor: Colors.black
                                                  .withValues(alpha: 0.55),
                                              thumbColor: _kVodProgressTheme,
                                              overlayColor: Colors.transparent,
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                    enabledThumbRadius: 7,
                                                  ),
                                            ),
                                            child: ExcludeFocus(
                                              child: Slider(
                                                value: posSec,
                                                secondaryTrackValue:
                                                    bufferedSec,
                                                min: 0.0,
                                                max: maxSec,
                                                onChanged:
                                                    validPosition
                                                        ? _onSliderPositionChanged
                                                        : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FocusTraversalOrder(
                                    order: const NumericFocusOrder(2),
                                    child: _VodToolbarButton(
                                      icon: LucideIcons.lock_open,
                                      label: 'player_lock'.tr,
                                      focusNode: _vodLockFocusNode,
                                      onTap: _enableVodControlsLock,
                                      onKey: _vodToolbarOnKey(
                                        _enableVodControlsLock,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  FocusTraversalOrder(
                                    order: const NumericFocusOrder(3),
                                    child: _VodToolbarButton(
                                      icon: LucideIcons.captions,
                                      label: 'player_audio_subtitles'.tr,
                                      focusNode: _vodAudioSubsFocusNode,
                                      onTap: _showVodAudioSubtitlesPicker,
                                      onKey: _vodToolbarOnKey(
                                        () => unawaited(
                                          _showVodAudioSubtitlesPicker(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  FocusTraversalOrder(
                                    order: const NumericFocusOrder(4),
                                    child: _VodToolbarButton(
                                      icon: LucideIcons.gauge,
                                      label: (_playbackSpeed - 1.0).abs() < 0.001
                                          ? 'player_playback_speed'.tr
                                          : _playbackSpeedLabel(_playbackSpeed),
                                      focusNode: _vodSpeedFocusNode,
                                      onTap: () => unawaited(
                                        _showPlaybackSpeedPicker(),
                                      ),
                                      onKey: _vodToolbarOnKey(
                                        () => unawaited(
                                          _showPlaybackSpeedPicker(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  FocusTraversalOrder(
                                    order: const NumericFocusOrder(5),
                                    child: _VodToolbarButton(
                                      imageAsset: kIconAspectRatio,
                                      label: 'player_aspect_ratio'.tr,
                                      focusNode: _aspectRatioFocusNode,
                                      onTap: _cycleAspectRatio,
                                      onKey: (node, event) {
                                        if (event is! KeyDownEvent) {
                                          return KeyEventResult.ignored;
                                        }
                                        final lk = event.logicalKey;
                                        if (lk == LogicalKeyboardKey.arrowUp) {
                                          return _vodToolbarVerticalKey(lk);
                                        }
                                        if (lk ==
                                            LogicalKeyboardKey.arrowDown) {
                                          return _vodToolbarVerticalKey(lk);
                                        }
                                        if (lk ==
                                                LogicalKeyboardKey.arrowLeft ||
                                            lk ==
                                                LogicalKeyboardKey.arrowRight) {
                                          return _vodToolbarHorizontalNavigate(
                                            lk,
                                          );
                                        }
                                        if (_isOkLogicalKey(lk)) {
                                          _cycleAspectRatio();
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  FocusTraversalOrder(
                                    order: const NumericFocusOrder(6),
                                    child: _VodToolbarButton(
                                      icon: LucideIcons.picture_in_picture_2,
                                      label: 'player_pip'.tr,
                                      focusNode: _vodPipFocusNode,
                                      onTap:
                                          () => unawaited(_enterVodPipMode()),
                                      onKey: _vodToolbarOnKey(
                                        () => unawaited(_enterVodPipMode()),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  FocusTraversalOrder(
                                    order: const NumericFocusOrder(7),
                                    child: _VodToolbarButton(
                                      icon: LucideIcons.info,
                                      label: 'stream_info_title'.tr,
                                      focusNode: _streamInfoFocusNode,
                                      onTap: _showStreamInfoDialog,
                                      onKey: _vodToolbarOnKey(
                                        _showStreamInfoDialog,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              )
              : const SizedBox.shrink(),
            ),
            _buildLiveStreamInfoBar(),
          ],
        ),
      ),
    );
  }

  FocusOnKeyEventCallback _vodToolbarOnKey(VoidCallback action) {
    return (node, event) {
      if (event is KeyRepeatEvent) {
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown) {
          _vodTryOpenSuggestionsOverlay();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          return _vodToolbarVerticalKey(key);
        }
        return KeyEventResult.ignored;
      }
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        return _vodToolbarHorizontalNavigate(key);
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        return _vodToolbarVerticalKey(key);
      }
      if (_isOkLogicalKey(key)) {
        action();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  KeyEventResult _vodSeekBarOnKey(FocusNode node, KeyEvent event) {
    if (widget.isLive) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final isSeekKey =
        k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight;

    // Vertical focus must work even while the player is still buffering.
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (k == LogicalKeyboardKey.arrowDown) {
        _cancelVodSeekBarHoldKeyUpDebounce();
        _onVodSeekHoldEnded();
        _vodFocusToolbarButton();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        _cancelVodSeekBarHoldKeyUpDebounce();
        _onVodSeekHoldEnded();
        return _vodVerticalFocusNavigate(k);
      }
    }

    // KeyUp مؤجّل: لا تُنه السحب فوراً (KeyUp متقطع = رجوع للخلف + تحميل مسبق).
    if (event is KeyUpEvent) {
      if (isSeekKey) {
        _scheduleVodSeekBarHoldEndAfterKeyUp();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event is KeyRepeatEvent) {
      if (isSeekKey && _vodSeekBarFocusNode.hasFocus && _vodSeekBarHoldActive) {
        _cancelVodSeekBarHoldKeyUpDebounce();
        if (k == LogicalKeyboardKey.arrowLeft) {
          _tickVodSeekBarHoldLeftStep();
        } else {
          _tickVodSeekBarHoldRightStep();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // أثناء السحب الجاري: اسمح بالاستمرار حتى لو ظهر progress/buffering.
    if (progress && !_vodSeekBarHoldActive) return KeyEventResult.ignored;

    if (isSeekKey) {
      _cancelVodSeekBarHoldKeyUpDebounce();
      _beginVodSeekBarDirectionalHold(k);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class _VodToolbarButton extends StatelessWidget {
  const _VodToolbarButton({
    this.icon,
    this.imageAsset,
    required this.label,
    required this.focusNode,
    required this.onTap,
    required this.onKey,
  }) : assert(icon != null || imageAsset != null);

  final IconData? icon;
  final String? imageAsset;
  final String label;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final FocusOnKeyEventCallback onKey;

  @override
  Widget build(BuildContext context) {
    final tv = isTvDevice(context);
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final showFocus = tv && focusNode.hasFocus;
        return Focus(
          focusNode: focusNode,
          skipTraversal: !tv,
          canRequestFocus: tv,
          onKeyEvent: onKey,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 78,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color:
                    showFocus
                        ? kColorFocus.withValues(alpha: 0.16)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: showFocus ? kColorFocus : Colors.transparent,
                  width: showFocus ? 2.2 : 1,
                ),
                boxShadow: showFocus
                    ? [
                        BoxShadow(
                          color: kColorFocus.withValues(alpha: 0.5),
                          blurRadius: 14,
                          spreadRadius: 0.6,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (imageAsset != null)
                    Image.asset(
                      imageAsset!,
                      width: 22,
                      height: 22,
                      color: Colors.white,
                      filterQuality: FilterQuality.medium,
                    )
                  else
                    Icon(
                      icon,
                      color: Colors.white,
                      size: 22,
                    ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w800,
                      fontSize: 11.sp,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Focusable row for Audio & Subtitles sheet (remote OK / Enter).
class _PlayerFocusTile extends StatefulWidget {
  const _PlayerFocusTile({
    required this.title,
    required this.onTap,
    this.leading,
    this.selected = false,
    this.autofocus = false,
    this.compact = false,
  });

  final String title;
  final VoidCallback onTap;
  final Widget? leading;
  final bool selected;
  final bool autofocus;
  final bool compact;

  @override
  State<_PlayerFocusTile> createState() => _PlayerFocusTileState();
}

class _PlayerFocusTileState extends State<_PlayerFocusTile> {
  late final FocusNode _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.autofocus) {
      void tryFocus() {
        if (!mounted) return;
        if (!isTvDevice(context)) return;
        if (_node.canRequestFocus) _node.requestFocus();
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        tryFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) => tryFocus());
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTvDevice(context);
    final showFocus = tv && _node.hasFocus;
    final selected = widget.selected;
    final compact = widget.compact;
    final radius = compact ? 10.0 : 12.0;
    final tile = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: EdgeInsets.symmetric(vertical: compact ? 2 : 3),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 10,
            vertical: compact ? 7 : 10,
          ),
          decoration: BoxDecoration(
            color: selected
                ? kColorFocus.withValues(alpha: 0.12)
                : showFocus
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: showFocus
                  ? kColorFocus
                  : selected
                      ? kColorFocus.withValues(alpha: 0.4)
                      : Colors.transparent,
              width: showFocus ? 2 : 1,
            ),
            boxShadow: showFocus
                ? [
                    BoxShadow(
                      color: kColorFocus.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? kColorFocus : Colors.white,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: compact ? 13 : 14,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  color: kColorFocus,
                  size: compact ? 16 : 20,
                ),
            ],
          ),
        ),
      ),
    );

    if (!tv) return tile;

    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) =>
          settingsTvActivateOnSelect(event, widget.onTap),
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_node.hasFocus) return;
          Scrollable.ensureVisible(
            context,
            alignment: 0.45,
            duration: Duration.zero,
            curve: Curves.linear,
          );
        });
      },
      child: tile,
    );
  }
}

class _PlayerSheetShell extends StatelessWidget {
  const _PlayerSheetShell({
    required this.header,
    required this.children,
    this.centered = false,
  });

  final Widget header;
  final List<Widget> children;
  /// Audio-style menus: card in the middle of the screen (not bottom).
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final tv = isTvDevice(context);
    final size = MediaQuery.sizeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Phone/TV: tap empty area outside the card to dismiss.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: const SizedBox.expand(),
        ),
        SafeArea(
          child: Align(
            alignment: centered ? Alignment.center : Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: tv ? 420 : 340,
                  maxHeight: size.height * (centered ? (tv ? 0.62 : 0.55) : (tv ? 0.55 : 0.48)),
                ),
                child: Material(
                  color: const Color(0xFF1A1F2E),
                  elevation: 14,
                  shadowColor: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: FocusScope(
                    autofocus: true,
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            child: header,
                          ),
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              children: children,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerSheetHeader extends StatelessWidget {
  const _PlayerSheetHeader({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 28,
            height: 3,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        Row(
          children: [
            Icon(icon, color: kColorFocus, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
