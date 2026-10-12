part of '../screens.dart';

enum _BvGestureKind { brightness, volume }

const double _kBvEdgeFraction = 0.38;
const double _kBvDragSensitivity = 0.65;
const Duration _kBvOverlayHideDelay = Duration(milliseconds: 850);
const double _kSuggestionSwipeUpVelocity = -180;
const double _kSuggestionSwipeDownVelocity = 180;
const double _kSuggestionMinDragFraction = 0.06;
/// Ignore tiny finger jitter so a tap does not open/close suggestions.
const double _kSuggestionClickSlopPx = 22;
/// Inset from screen edge — slightly inward toward seek controls.
const double _kBvPillSideInset = 58;
/// Max black veil when brightness is at 0 (keeps UI faintly readable).
const double _kBvMaxDimOpacity = 0.78;

extension _FullVideoBrightnessVolume on _FullVideoScreenState {
  bool _isInBvEdgeZone(double dx, double width) {
    if (width <= 0) return false;
    return dx <= width * _kBvEdgeFraction ||
        dx >= width * (1 - _kBvEdgeFraction);
  }

  bool _canHandleBrightnessVolumeGestures() {
    if (!mounted) return false;
    if (isTvDevice(context)) return false;
    if (_vodLockActive) return false;
    if (_showLiveIptvOverlay) return false;
    if (_showMovieSuggestionsOverlay ||
        _showEpisodeSuggestionsOverlay ||
        _showLiveChannelSuggestionsOverlay) {
      return false;
    }
    if (_awaitingResumeChoice) return false;
    return true;
  }

  bool get _bvShowIntroPills {
    if (!_bvIntroPending) return false;
    if (!showControllersVideo) return false;
    if (!mounted || isTvDevice(context)) return false;
    if (_awaitingResumeChoice) return false;
    if (_vodLockActive) return false;
    if (_showLiveIptvOverlay) return false;
    if (_showMovieSuggestionsOverlay ||
        _showEpisodeSuggestionsOverlay ||
        _showLiveChannelSuggestionsOverlay) {
      return false;
    }
    return true;
  }

  /// Dim veil opacity for in-player brightness (avoids ScreenBrightness +
  /// platform-view black screens when the IPTV mini-player resizes).
  double get _bvDimOpacity =>
      ((1.0 - _bvBrightness) * _kBvMaxDimOpacity).clamp(0.0, _kBvMaxDimOpacity);

  Future<void> _initBrightnessVolumeLevels() async {
    try {
      VolumeController.instance.showSystemUI = false;
    } catch (_) {}

    // Start from a readable mid level; we dim with a veil (not system brightness)
    // so Exo/VLC surfaces stay stable when the side panel opens.
    _bvBrightness = 1.0;

    try {
      final volume = await VolumeController.instance.getVolume();
      if (!mounted) return;
      _bvVolume = volume.clamp(0.0, 1.0);
    } catch (_) {
      // Device volume APIs can throw on some OEM builds.
    }
  }

  void _disposeBrightnessVolume() {
    _bvHideTimer?.cancel();
    _bvHideTimer = null;
    _suggestionSwipeTapGuardTimer?.cancel();
    _suggestionSwipeTapGuardTimer = null;
    _suggestionSwipeJustHandled = false;
    try {
      VolumeController.instance.showSystemUI = true;
    } catch (_) {}
    // Ensure any previous app-brightness override from older builds is cleared.
    try {
      ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  }

  /// Hide brightness/volume UI and freeze gestures while the IPTV panel is open.
  void _clearBvUiForIptvOverlay() {
    _bvHideTimer?.cancel();
    _bvHideTimer = null;
    _bvActiveKind = null;
    _bvDragAccumulated = 0;
    _bvGestureConsumed = false;
    _bvOverlayVisible = false;
    _dismissBvIntro();
  }

  /// Called when player chrome hides — ends the one-time intro for this visit.
  void _dismissBvIntro() {
    if (!_bvIntroPending) return;
    _bvIntroPending = false;
  }

  void _scheduleBvOverlayHide() {
    _bvHideTimer?.cancel();
    _bvHideTimer = Timer(_kBvOverlayHideDelay, () {
      if (!mounted) return;
      _fvSetState(() => _bvOverlayVisible = false);
    });
  }

  void _showBvOverlay({required bool isBrightness}) {
    _bvHideTimer?.cancel();
    _fvSetState(() {
      _bvIntroPending = false;
      _bvIsBrightness = isBrightness;
      _bvOverlayVisible = true;
    });
  }

  Future<void> _applyBvVolume(double value) async {
    final next = value.clamp(0.0, 1.0);
    _bvVolume = next;
    try {
      await VolumeController.instance.setVolume(next);
    } catch (_) {
      // Ignore setVolume failures on restricted devices.
    }
  }

  void _onBvVerticalDragStart(DragStartDetails details) {
    _bvGestureConsumed = false;
    _bvActiveKind = null;
    _bvDragAccumulated = 0;
    _swipeDragStartDx = details.localPosition.dx;
    _swipeDragAccumulatedDy = 0;
    _swipeDragAbsDy = 0;
    if (!_canHandleBrightnessVolumeGestures()) return;

    final width = MediaQuery.sizeOf(context).width;
    final dx = details.localPosition.dx;
    if (dx <= width * _kBvEdgeFraction) {
      _bvActiveKind = _BvGestureKind.brightness;
      _bvGestureStartValue = _bvBrightness;
    } else if (dx >= width * (1 - _kBvEdgeFraction)) {
      _bvActiveKind = _BvGestureKind.volume;
      _bvGestureStartValue = _bvVolume;
    }
  }

  void _onBvVerticalDragUpdate(DragUpdateDetails details) {
    // Always track vertical travel so a swipe above the toolbar can open
    // suggestions even if the touch started near a brightness/volume edge
    // (as long as B/V was not actually consumed).
    _swipeDragAccumulatedDy += details.delta.dy;
    _swipeDragAbsDy += details.delta.dy.abs();
    final kind = _bvActiveKind;
    if (kind == null) return;
    if (!_canHandleBrightnessVolumeGestures()) return;

    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;

    _bvDragAccumulated += -details.delta.dy / (height * _kBvDragSensitivity);
    final next =
        (_bvGestureStartValue + _bvDragAccumulated).clamp(0.0, 1.0);
    if (!_bvGestureConsumed && (_bvDragAccumulated).abs() < 0.015) {
      return;
    }

    _bvGestureConsumed = true;
    if (kind == _BvGestureKind.brightness) {
      _showBvOverlay(isBrightness: true);
      _fvSetState(() => _bvBrightness = next);
    } else {
      _showBvOverlay(isBrightness: false);
      _fvSetState(() => _bvVolume = next);
      unawaited(_applyBvVolume(next));
    }
  }

  void _onBvVerticalDragEnd(DragEndDetails details) {
    final consumed = _bvGestureConsumed;
    _bvActiveKind = null;
    _bvDragAccumulated = 0;
    if (consumed) {
      _scheduleBvOverlayHide();
    }
    if (!consumed) {
      _handleSuggestionsVerticalSwipe(
        details,
        startDx: _swipeDragStartDx,
        dragDy: _swipeDragAccumulatedDy,
        absDragDy: _swipeDragAbsDy,
      );
    }
    _swipeDragStartDx = 0;
    _swipeDragAccumulatedDy = 0;
    _swipeDragAbsDy = 0;
  }

  void _onBvVerticalDragCancel() {
    _bvActiveKind = null;
    _bvDragAccumulated = 0;
    _swipeDragStartDx = 0;
    _swipeDragAccumulatedDy = 0;
    _swipeDragAbsDy = 0;
    if (_bvGestureConsumed) {
      _scheduleBvOverlayHide();
    }
    _bvGestureConsumed = false;
  }

  Widget _bvPillFor({required bool isBrightness}) {
    final value = isBrightness ? _bvBrightness : _bvVolume;
    final label = '${(value * 100).round()}%';
    final icon = isBrightness
        ? (value <= 0.01
            ? Icons.brightness_2_rounded
            : Icons.wb_sunny_rounded)
        : (value <= 0.01
            ? Icons.volume_off_rounded
            : value < 0.4
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded);

    return _BvLevelPill(
      value: value,
      icon: icon,
      label: label,
    );
  }

  /// Black veil above the video (not used while IPTV side panel is open).
  Widget _buildBrightnessDimOverlay() {
    if (!mounted || isTvDevice(context)) return const SizedBox.shrink();
    if (_showLiveIptvOverlay) return const SizedBox.shrink();
    final dim = _bvDimOpacity;
    if (dim <= 0.001) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(color: Colors.black.withValues(alpha: dim)),
      ),
    );
  }

  Widget _buildBrightnessVolumeOverlay() {
    if (!mounted || isTvDevice(context)) {
      return const SizedBox.shrink();
    }
    if (_showLiveIptvOverlay) {
      return const SizedBox.shrink();
    }

    final showIntro = _bvShowIntroPills;
    final showGesture = _bvOverlayVisible && !showIntro;

    if (!showIntro && !showGesture) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            if (showIntro) ...[
              Positioned(
                left: _kBvPillSideInset,
                top: 0,
                bottom: 0,
                child: Center(child: _bvPillFor(isBrightness: true)),
              ),
              Positioned(
                right: _kBvPillSideInset,
                top: 0,
                bottom: 0,
                child: Center(child: _bvPillFor(isBrightness: false)),
              ),
            ] else
              Positioned(
                left: _bvIsBrightness ? _kBvPillSideInset : null,
                right: _bvIsBrightness ? null : _kBvPillSideInset,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _bvPillFor(isBrightness: _bvIsBrightness),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BvLevelPill extends StatelessWidget {
  const _BvLevelPill({
    required this.value,
    required this.icon,
    required this.label,
  });

  final double value;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final level = value.clamp(0.0, 1.0);
    final onFill = level >= 0.28;

    return SizedBox(
      width: 42,
      height: 168,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: level,
                widthFactor: 1,
                child: const ColoredBox(color: Colors.white),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: onFill ? Colors.black87 : Colors.white,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: onFill ? Colors.black87 : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
