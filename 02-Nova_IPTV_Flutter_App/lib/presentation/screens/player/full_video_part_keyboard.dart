part of '../screens.dart';

extension _FullVideoKeyboard on _FullVideoScreenState {
  // ---------------------------------------------------------------------------
  // Keyboard / Remote helpers
  // ---------------------------------------------------------------------------
  bool _isOkLogicalKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space;
  }

  void _startOkLongPressTimer({ChannelLive? channel}) {
    _okLongPressTimer?.cancel();
    _okLongPressTriggered = false;
    _iptvOkLongPressChannel = channel;
    _okLongPressTimer = Timer(_okLongPressDuration, () {
      if (!mounted) return;
      _okLongPressTimer = null;
      _okLongPressTriggered = true;
      final target = _iptvOkLongPressChannel;
      if (target != null) {
        _toggleFavoriteForChannel(target);
      } else {
        _toggleFavoriteFromKey();
      }
    });
  }

  bool _cancelOkLongPressAndCheckTriggered() {
    _okLongPressTimer?.cancel();
    _okLongPressTimer = null;
    _iptvOkLongPressChannel = null;
    final wasLong = _okLongPressTriggered;
    if (wasLong) _okLongPressTriggered = false;
    return wasLong;
  }

  KeyEventResult _handleOkKeyEvent(KeyEvent event) {
    if (_vodLockActive) {
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      if (_vodSeekBarFocusNode.hasFocus) {
        _startOkLongPressTimer();
        if (!showControllersVideo) {
          _fvSetState(() => showControllersVideo = true);
          _schedulePlayerControlsHideAfterIdle();
        } else {
          _touchPlayerControlsActivity();
          _okDeferPlayPauseUntilKeyUp = true;
        }
        return KeyEventResult.handled;
      }
      if (_liveFavoriteFocusNode.hasFocus) {
        _toggleFavoriteFromKey();
        return KeyEventResult.handled;
      }
      if (_aspectRatioFocusNode.hasFocus) {
        _cycleAspectRatio();
        return KeyEventResult.handled;
      }
      if (_liveAudioFocusNode.hasFocus) {
        unawaited(_showLiveAudioTracksPicker());
        return KeyEventResult.handled;
      }
      if (_streamInfoFocusNode.hasFocus) {
        _showStreamInfoDialog();
        return KeyEventResult.handled;
      }
      if (_settingsGearFocusNode.hasFocus) {
        if (!Platform.isIOS) {
          _showChangePlayerDialog();
        }
        return KeyEventResult.handled;
      }

      _startOkLongPressTimer();

      if (!showControllersVideo) {
        _fvSetState(() => showControllersVideo = true);
        _schedulePlayerControlsHideAfterIdle();
      } else {
        _touchPlayerControlsActivity();
        _okDeferPlayPauseUntilKeyUp = true;
      }
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      final wasLong = _cancelOkLongPressAndCheckTriggered();
      if (!wasLong && _okDeferPlayPauseUntilKeyUp) {
        _okDeferPlayPauseUntilKeyUp = false;
        _togglePlayPause();
      } else {
        _okDeferPlayPauseUntilKeyUp = false;
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _openEpisodeOverlay() {
    if (_showEpisodeSuggestionsOverlay) return;
    _vodCaptureToolbarFocus();
    _onVodSeekHoldEnded();
    _lastRightKeyTime = null;
    _lastLeftKeyTime = null;
    _fvSetState(() => _showEpisodeSuggestionsOverlay = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _episodeOverlayFocusNode.requestFocus();
    });
  }

  void _closeEpisodeOverlay() {
    if (!_showEpisodeSuggestionsOverlay) return;
    _fvSetState(() => _showEpisodeSuggestionsOverlay = false);
    _episodeOverlayFocusNode.unfocus();
    _lastRightKeyTime = null;
    _lastLeftKeyTime = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _vodRestoreToolbarFocus();
    });
  }

  Future<void> _switchToEpisode(Episode episode, String link) async {
    if (!mounted) return;
    _persistCurrentVodProgressBeforeSwitch();
    _applyResumeTargetForContentSwitch(
      streamId: episode.id?.toString() ?? '',
      fromSeries: true,
    );
    _fvSetState(() {
      _currentEpisodeId = episode.id?.toString();
      _currentPlaybackTitle =
          episode.title ?? episode.info?.name ?? widget.title;
    });
    await _startPlayback(link);
  }

  void _openMovieOverlay() {
    if (_showMovieSuggestionsOverlay) return;
    _vodCaptureToolbarFocus();
    _onVodSeekHoldEnded();
    _lastRightKeyTime = null;
    _lastLeftKeyTime = null;
    _fvSetState(() => _showMovieSuggestionsOverlay = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _movieOverlayFocusNode.requestFocus();
    });
  }

  void _closeMovieOverlay() {
    if (!_showMovieSuggestionsOverlay) return;
    _fvSetState(() => _showMovieSuggestionsOverlay = false);
    _movieOverlayFocusNode.unfocus();
    _lastRightKeyTime = null;
    _lastLeftKeyTime = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _vodRestoreToolbarFocus();
    });
  }

  void _resetLiveFullscreenExtras() {
    _liveHintShowTimer?.cancel();
    _liveHintHideTimer?.cancel();
    _liveHintShowTimer = null;
    _liveHintHideTimer = null;
    _showLiveDownHint = false;
    _showLiveChannelSuggestionsOverlay = false;
    _liveChannelOverlayFocusNode.unfocus();
    _hideLiveStreamInfoBar();
  }

  bool _liveTopBarHasFocus() {
    return _liveBackFocusNode.hasFocus ||
        _liveChannelsListFocusNode.hasFocus ||
        _liveFavoriteFocusNode.hasFocus ||
        _aspectRatioFocusNode.hasFocus ||
        _liveAudioFocusNode.hasFocus ||
        _streamInfoFocusNode.hasFocus ||
        _settingsGearFocusNode.hasFocus;
  }

  void _requestLivePlayButtonFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isLive || _showLiveIptvOverlay) return;
      _liveBackFocusNode.unfocus();
      _liveChannelsListFocusNode.unfocus();
      _liveFavoriteFocusNode.unfocus();
      _aspectRatioFocusNode.unfocus();
      _liveAudioFocusNode.unfocus();
      _streamInfoFocusNode.unfocus();
      _settingsGearFocusNode.unfocus();
      if (_playButtonFocusNode.canRequestFocus) {
        _playButtonFocusNode.requestFocus();
      }
    });
  }

  void _openLiveChannelOverlay() {
    if (_showLiveChannelSuggestionsOverlay ||
        !widget.isLive ||
        _showLiveIptvOverlay) {
      return;
    }
    final catId = _liveZapCategoryId() ?? '';
    if (catId.isNotEmpty &&
        !_iptvIsFavoritesCategory(catId) &&
        !_iptvIsRecentlyWatchedCategory(catId)) {
      context.read<ChannelsBloc>().add(
        GetLiveChannelsEvent(typeCategory: TypeCategory.live, catyId: catId),
      );
    }
    _fvSetState(() => _showLiveChannelSuggestionsOverlay = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _liveChannelOverlayFocusNode.requestFocus();
    });
  }

  void _closeLiveChannelOverlay() {
    if (!_showLiveChannelSuggestionsOverlay) return;
    _fvSetState(() => _showLiveChannelSuggestionsOverlay = false);
    _liveChannelOverlayFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _playButtonFocusNode.canRequestFocus) {
        _playButtonFocusNode.requestFocus();
      }
    });
  }

  Future<void> _selectLiveChannelFromOverlay(ChannelLive channel) async {
    if (!mounted || !widget.isLive) return;
    _closeLiveChannelOverlay();
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthSuccess) return;
    final link = _buildLiveStreamLink(channel, auth.user);
    if (link.isEmpty) return;
    if (!showControllersVideo) {
      _fvSetState(() => showControllersVideo = true);
    }
    _touchPlayerControlsActivity();
    await _switchToLiveChannel(channel, link);
  }

  // ---------------------------------------------------------------------------
  // Movie switching Ã¢â‚¬â€œ replaces the currently playing movie without navigating back
  // ---------------------------------------------------------------------------
  Future<void> _switchToMovie(ChannelMovie movie, String link) async {
    if (!mounted) return;
    final parental = ParentalControlService.instance;
    final catState = context.read<MovieCatyBloc>().state;
    final cats = catState is MovieCatySuccess
        ? catState.categories
        : const <CategoryModel>[];
    final categoryName = ParentalControlService.categoryNameFromId(
      movie.categoryId,
      cats,
    );
    if (parental.isAdultMovie(movie, categoryName: categoryName)) {
      final ok = await parental.requestAdultContentAccess(context);
      if (!ok || !mounted) return;
    }
    _persistCurrentVodProgressBeforeSwitch();
    _applyResumeTargetForContentSwitch(
      streamId: movie.streamId?.toString() ?? '',
      fromSeries: false,
    );
    _fvSetState(() {
      _currentMovie = movie;
      _currentPlaybackTitle = movie.name ?? widget.title;
    });
    await _startPlayback(link);
  }

  KeyEventResult _handleKeyDownEvent(LogicalKeyboardKey key) {
    if (_vodLockActive) {
      return KeyEventResult.handled;
    }
    if (!widget.isLive &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp)) {
      final vodNav = _vodVerticalFocusNavigate(key);
      if (vodNav != KeyEventResult.ignored) return vodNav;
    }

    if (widget.isLive &&
        !_showLiveIptvOverlay &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) &&
        !_liveFavoriteFocusNode.hasFocus &&
        !_aspectRatioFocusNode.hasFocus &&
        !_liveAudioFocusNode.hasFocus &&
        !_streamInfoFocusNode.hasFocus &&
        !_settingsGearFocusNode.hasFocus) {
      unawaited(
        _zapLiveChannelByDelta(
          key == LogicalKeyboardKey.arrowRight ? 1 : -1,
        ),
      );
      return KeyEventResult.handled;
    }

    // Live + Ã˜Â³Ã™â€¡Ã™â€¦ Ã˜Â£Ã˜Â³Ã™ÂÃ™â€ž:
    // Ã˜ÂªÃ˜Â¸Ã™â€¡Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â²Ã˜Â±Ã˜Â§Ã˜Â± Ã˜Â¯Ã˜Â§Ã˜Â¦Ã™â€¦Ã˜Â§Ã™â€¹ + Ã˜ÂªÃ˜Â±Ã™Æ’Ã™Å Ã˜Â² Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â²Ã˜Â± Ã˜ÂªÃ˜ÂºÃ™Å Ã™Å Ã˜Â± Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜ÂºÃ™â€ž
    if (widget.isLive &&
        key == LogicalKeyboardKey.arrowUp &&
        !_liveFavoriteFocusNode.hasFocus &&
        !_aspectRatioFocusNode.hasFocus &&
        !_liveAudioFocusNode.hasFocus &&
        !_streamInfoFocusNode.hasFocus &&
        !_settingsGearFocusNode.hasFocus) {
      if (!showControllersVideo) {
        _fvSetState(() => showControllersVideo = true);
        _schedulePlayerControlsHideAfterIdle();
      } else {
        _touchPlayerControlsActivity();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_aspectRatioFocusNode.canRequestFocus) {
          _aspectRatioFocusNode.requestFocus();
        }
      });
      return KeyEventResult.handled;
    }

    if (widget.isLive &&
        !_showLiveIptvOverlay &&
        key == LogicalKeyboardKey.arrowDown) {
      if (_liveTopBarHasFocus()) {
        _liveFavoriteFocusNode.unfocus();
        _aspectRatioFocusNode.unfocus();
        _liveAudioFocusNode.unfocus();
        _streamInfoFocusNode.unfocus();
        _settingsGearFocusNode.unfocus();
        _liveBackFocusNode.unfocus();
        _liveChannelsListFocusNode.unfocus();
        if (_playButtonFocusNode.canRequestFocus) {
          _playButtonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (_playButtonFocusNode.hasFocus ||
          _rootPlayerFocusNode.hasFocus) {
        if (!_playButtonFocusNode.hasFocus) {
          _requestLivePlayButtonFocus();
        }
        _openLiveChannelOverlay();
        return KeyEventResult.handled;
      }
    }

    // Catch-up/VOD Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  channelMovie/channelSerie:
    // Ã˜Â³Ã™â€¡Ã™â€¦ Ã˜Â£Ã˜Â³Ã™ÂÃ™â€ž Ã™Å Ã˜Â¬Ã˜Â¨ Ã˜Â£Ã™â€  Ã™Å Ã˜Â±Ã™Æ’Ã™â€˜Ã˜Â² Ã˜Â²Ã˜Â± aspect ratio Ã™â€¦Ã˜Â¨Ã˜Â§Ã˜Â´Ã˜Â±Ã˜Â©.
    if (!widget.isLive &&
        !_isMovieStyle &&
        !_isSeriesStyle &&
        key == LogicalKeyboardKey.arrowDown) {
      if (_vodSeekBarFocusNode.hasFocus) {
        return KeyEventResult.ignored;
      }
      if (!showControllersVideo) {
        _fvSetState(() => showControllersVideo = true);
        _schedulePlayerControlsHideAfterIdle();
      } else {
        _touchPlayerControlsActivity();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_vodSeekBarFocusNode.canRequestFocus) {
          _vodSeekBarFocusNode.requestFocus();
        } else if (_aspectRatioFocusNode.canRequestFocus) {
          _aspectRatioFocusNode.requestFocus();
        }
      });
      return KeyEventResult.handled;
    }

    // Ã˜Â§Ã˜Â³Ã˜ÂªÃ™Æ’Ã™â€¦Ã˜Â§Ã™â€ž Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜Â§Ã™â€¡Ã˜Â¯Ã˜Â© Ã™â€¦Ã™â€  Catch-up (Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  channelMovie/channelSerie) Ã™Å Ã˜Â¬Ã˜Â¨ Ã˜Â£Ã™â€  Ã™Å Ã˜Â¯Ã˜Â¹Ã™â€¦ Ã˜Â§Ã™â€žÃ˜ÂªÃ™â€šÃ˜Â¯Ã™Å Ã™â€¦ Ã™Ë†Ã˜Â§Ã™â€žÃ˜Â¥Ã˜Â±Ã˜Â¬Ã˜Â§Ã˜Â¹.
    final canSeek = !widget.isLive;
    final now = DateTime.now();
    if (canSeek &&
        (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowLeft)) {
      if (!_vodRemoteSeekAllowed()) {
        return KeyEventResult.handled;
      }
      if (_vodSeekBarFocusNode.hasFocus) {
        return KeyEventResult.ignored;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        if (_lastRightKeyTime != null &&
            now.difference(_lastRightKeyTime!) <
                const Duration(milliseconds: 400)) {
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
          _lastRightKeyTime = null;
          return KeyEventResult.handled;
        }
        _lastRightKeyTime = now;
        // Consume first tap so focus does not jump to toolbar buttons.
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_lastLeftKeyTime != null &&
            now.difference(_lastLeftKeyTime!) <
                const Duration(milliseconds: 400)) {
          _rapidForwardSeekSeconds = 10;
          _lastRemoteForwardSeekAt = null;
          _seekRelative(-10);
          _lastLeftKeyTime = null;
          return KeyEventResult.handled;
        }
        _lastLeftKeyTime = now;
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

}
