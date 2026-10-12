part of '../screens.dart';

const Duration _kVodLockUnlockHold = Duration(seconds: 2);
const Duration _kVodLockHintMinDisplay = Duration(seconds: 3);
const Duration _kVodLockBackUnlockGrace = Duration(milliseconds: 1500);

extension _VodPlayerLock on _FullVideoScreenState {
  bool get _vodLockActive => !widget.isLive && _vodControlsLocked;

  bool get _vodLockOnTv => isTv(context) || isAndroidTv(context);

  bool _vodLockWithinBackUnlockGrace() {
    final at = _vodLockBackUnlockedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < _kVodLockBackUnlockGrace;
  }

  bool _vodLockIsBackKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.goBack;
  }

  void _registerVodLockHardwareHandler() {
    if (_vodLockHardwareHandlerAttached || !_vodLockOnTv) return;
    HardwareKeyboard.instance.addHandler(_vodLockHardwareKeyHandler);
    _vodLockHardwareHandlerAttached = true;
  }

  void _unregisterVodLockHardwareHandler() {
    if (!_vodLockHardwareHandlerAttached) return;
    HardwareKeyboard.instance.removeHandler(_vodLockHardwareKeyHandler);
    _vodLockHardwareHandlerAttached = false;
  }

  bool _vodLockHardwareKeyHandler(KeyEvent event) {
    final key = event.logicalKey;

    if (_vodLockOnTv && _vodLockIsBackKey(key) && _vodLockWithinBackUnlockGrace()) {
      if (event is KeyDownEvent || event is KeyUpEvent) {
        return true;
      }
    }

    if (!_vodControlsLocked || widget.isLive || !_vodLockOnTv) {
      return false;
    }

    if (_vodLockIsBackKey(key)) {
      if (event is KeyDownEvent) {
        _beginVodLockUnlockHold(showHoldHint: true);
        return true;
      }
      if (event is KeyUpEvent) {
        _cancelVodLockUnlockTimerOnly();
        _showVodLockHoldHint();
        return true;
      }
    }

    return true;
  }

  void _cancelVodLockUnlockTimerOnly() {
    _vodLockUnlockTimer?.cancel();
    _vodLockUnlockTimer = null;
  }

  void _showVodLockHoldHint() {
    _vodLockHintShownAt = DateTime.now();
    if (!_vodLockHoldHintVisible) {
      _scheduleFullVideoRebuild(() => _vodLockHoldHintVisible = true);
    }
    _scheduleVodLockHintDismiss();
  }

  void _scheduleVodLockHintDismiss() {
    _vodLockHintDismissTimer?.cancel();
    final shownAt = _vodLockHintShownAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(shownAt);
    final remaining = _kVodLockHintMinDisplay - elapsed;
    final delay = remaining.isNegative ? Duration.zero : remaining;
    _vodLockHintDismissTimer = Timer(delay, () {
      if (!mounted) return;
      if (_vodLockUnlockTimer != null) return;
      _scheduleFullVideoRebuild(() => _vodLockHoldHintVisible = false);
      _vodLockHintShownAt = null;
    });
  }

  void _onVodLockTvBackPressed() {
    if (!_vodControlsLocked || !_vodLockOnTv) return;
    _showVodLockHoldHint();
  }

  void _scheduleVodLockBackGraceEnd() {
    _vodLockBackGraceTimer?.cancel();
    _vodLockBackGraceTimer = Timer(_kVodLockBackUnlockGrace, () {
      _vodLockBackGraceTimer = null;
      if (!mounted) return;
      _vodLockConsumeNextBack = false;
      _vodLockBackUnlockedAt = null;
      _vodLockUnlockViaBackHold = false;
      _unregisterVodLockHardwareHandler();
      if (_vodLockHoldHintVisible) {
        _scheduleFullVideoRebuild(() => _vodLockHoldHintVisible = false);
        _vodLockHintShownAt = null;
      }
    });
  }

  void _cancelVodLockUnlockHold({bool hideHint = true}) {
    _cancelVodLockUnlockTimerOnly();
    _vodLockHintDismissTimer?.cancel();
    _vodLockHintDismissTimer = null;
    if (hideHint && _vodLockHoldHintVisible) {
      _scheduleFullVideoRebuild(() => _vodLockHoldHintVisible = false);
    }
  }

  void _beginVodLockUnlockHold({required bool showHoldHint}) {
    _cancelVodLockUnlockTimerOnly();
    if (showHoldHint) {
      _showVodLockHoldHint();
    }
    _vodLockUnlockTimer = Timer(_kVodLockUnlockHold, () {
      _vodLockUnlockTimer = null;
      if (!mounted || !_vodControlsLocked) return;
      _vodLockUnlockViaBackHold = true;
      _vodLockConsumeNextBack = true;
      _vodLockBackUnlockedAt = DateTime.now();
      _vodLockSuppressNextTap = true;
      _unlockVodControls(haptic: true);
      _scheduleVodLockBackGraceEnd();
    });
  }

  void _enableVodControlsLock() {
    if (_vodControlsLocked) return;
    _vodLockUnlockViaBackHold = false;
    _vodLockConsumeNextBack = false;
    _vodLockBackUnlockedAt = null;
    _vodLockBackGraceTimer?.cancel();
    _vodLockBackGraceTimer = null;
    _cancelVodLockUnlockHold();
    _scheduleFullVideoRebuild(() {
      _vodControlsLocked = true;
      showControllersVideo = false;
      _dismissBvIntro();
    });
    _cancelPlayerControlsHideTimer();
    _registerVodLockHardwareHandler();
    if (_vodLockOnTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _vodControlsLocked && _vodLockFocusNode.canRequestFocus) {
          _vodLockFocusNode.requestFocus();
        }
      });
    }
    _showVodLockStatusToast(locked: true);
  }

  void _unlockVodControls({bool haptic = false}) {
    if (!_vodControlsLocked) return;
    _cancelVodLockUnlockTimerOnly();
    final viaBackHold = _vodLockUnlockViaBackHold;
    if (!viaBackHold) {
      _unregisterVodLockHardwareHandler();
      _vodLockHintDismissTimer?.cancel();
      _vodLockHintDismissTimer = null;
      _vodLockHintShownAt = null;
      if (_vodLockHoldHintVisible) {
        _scheduleFullVideoRebuild(() => _vodLockHoldHintVisible = false);
      }
    }
    _scheduleFullVideoRebuild(() {
      _vodControlsLocked = false;
      showControllersVideo = true;
    });
    _schedulePlayerControlsHideAfterIdle();
    _showVodLockStatusToast(locked: false);
    if (haptic) {
      HapticFeedback.mediumImpact();
    }
  }

  void _onVodLockBadgeTap() {
    if (_vodLockSuppressNextTap) {
      _vodLockSuppressNextTap = false;
      return;
    }
    _showVodLockHintToast('player_lock_hold_to_unlock'.tr);
  }

  void _hideVodLockToast() {
    try {
      _vodLockToastEntry?.remove();
    } catch (_) {}
    _vodLockToastEntry = null;
  }

  void _showVodLockStatusToast({required bool locked}) {
    if (!mounted) return;
    _hideVodLockToast();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlay =
          Overlay.maybeOf(context) ??
          Navigator.maybeOf(context, rootNavigator: true)?.overlay;
      if (overlay == null) return;

      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) {
          return _PlayerLockStatusToast(
            locked: locked,
            onDismissed: () {
              try {
                entry.remove();
              } catch (_) {}
              if (identical(_vodLockToastEntry, entry)) {
                _vodLockToastEntry = null;
              }
            },
          );
        },
      );
      _vodLockToastEntry = entry;
      overlay.insert(entry);
    });
  }

  void _showVodLockHintToast(String message) {
    if (!mounted) return;
    _hideVodLockToast();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlay =
          Overlay.maybeOf(context) ??
          Navigator.maybeOf(context, rootNavigator: true)?.overlay;
      if (overlay == null) return;

      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) {
          return _PlayerLockHintToast(
            message: message,
            onDismissed: () {
              try {
                entry.remove();
              } catch (_) {}
              if (identical(_vodLockToastEntry, entry)) {
                _vodLockToastEntry = null;
              }
            },
          );
        },
      );
      _vodLockToastEntry = entry;
      overlay.insert(entry);
    });
  }

  Widget _buildVodLockedOverlay() {
    final topPad = MediaQuery.of(context).padding.top;
    final tv = _vodLockOnTv;
    final hintMessage =
        tv
            ? 'player_lock_hold_back_to_unlock'.tr
            : 'player_lock_hold_to_unlock'.tr;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            onDoubleTap: () {},
            onVerticalDragStart: (_) {},
            onHorizontalDragStart: (_) {},
            child: const SizedBox.expand(),
          ),
        ),
        if (_vodLockHoldHintVisible)
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: _VodLockHoldHintBanner(message: hintMessage),
            ),
          ),
        Positioned(
          top: topPad + 14,
          right: 14,
          child: Focus(
            focusNode: _vodLockFocusNode,
            onKeyEvent: (node, event) {
              if (!tv) return KeyEventResult.ignored;
              if (_vodLockIsBackKey(event.logicalKey)) {
                return KeyEventResult.ignored;
              }
              if (event is KeyDownEvent && _isOkLogicalKey(event.logicalKey)) {
                _onVodLockTvBackPressed();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: _VodLockCornerBadge(
              onTap: tv ? _onVodLockTvBackPressed : _onVodLockBadgeTap,
              onHoldStart: () => _beginVodLockUnlockHold(showHoldHint: true),
              onHoldEnd: () {
                if (tv) {
                  _cancelVodLockUnlockTimerOnly();
                  _showVodLockHoldHint();
                } else {
                  _cancelVodLockUnlockHold();
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _VodLockCornerBadge extends StatelessWidget {
  const _VodLockCornerBadge({
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onTapDown: (_) => onHoldStart(),
      onTapUp: (_) => onHoldEnd(),
      onTapCancel: onHoldEnd,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          LucideIcons.lock,
          color: Colors.white.withValues(alpha: 0.88),
          size: 20,
        ),
      ),
    );
  }
}

class _VodLockHoldHintBanner extends StatelessWidget {
  const _VodLockHoldHintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.lock,
              color: LoginPremiumColors.gold,
              size: 20,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerLockStatusToast extends StatefulWidget {
  const _PlayerLockStatusToast({
    required this.locked,
    required this.onDismissed,
  });

  final bool locked;
  final VoidCallback onDismissed;

  @override
  State<_PlayerLockStatusToast> createState() => _PlayerLockStatusToastState();
}

class _PlayerLockStatusToastState extends State<_PlayerLockStatusToast>
    with SingleTickerProviderStateMixin {
  static const int _enterMs = 340;
  static const int _holdMs = 1480;
  static const int _exitMs = 340;

  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _dy;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    final totalMs = _enterMs + _holdMs + _exitMs;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );

    final wEnter = _enterMs.toDouble();
    final wHold = _holdMs.toDouble();
    final wExit = _exitMs.toDouble();

    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: wEnter,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: wHold),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: wExit,
      ),
    ]).animate(_controller);

    _dy = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 18,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: wEnter,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: wHold),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -12,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: wExit,
      ),
    ]).animate(_controller);

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.92,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: wEnter,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: wHold),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0.96,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: wExit,
      ),
    ]).animate(_controller);

    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _controller.removeStatusListener(onStatus);
        if (mounted) widget.onDismissed();
      }
    }

    _controller.addStatusListener(onStatus);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked;
    final message =
        locked
            ? 'player_lock_controls_locked'.tr
            : 'player_lock_controls_unlocked'.tr;
    final icon = locked ? LucideIcons.lock : LucideIcons.lock_open;
    final accent =
        locked ? LoginPremiumColors.gold : const Color(0xFF4ADE80);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + 18,
                ),
                child: Opacity(
                  opacity: _opacity.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, _dy.value),
                    child: Transform.scale(
                      scale: _scale.value.clamp(0.85, 1.05),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        constraints: BoxConstraints(maxWidth: 88.w),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.82),
              Colors.black.withValues(alpha: 0.68),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.18),
              blurRadius: 22,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.5.sp,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerLockHintToast extends StatefulWidget {
  const _PlayerLockHintToast({
    required this.message,
    required this.onDismissed,
  });

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_PlayerLockHintToast> createState() => _PlayerLockHintToastState();
}

class _PlayerLockHintToastState extends State<_PlayerLockHintToast>
    with SingleTickerProviderStateMixin {
  static const int _enterMs = 280;
  static const int _holdMs = 2200;
  static const int _exitMs = 280;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _enterMs + _holdMs + _exitMs),
    )..forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onDismissed();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.12, curve: Curves.easeOut),
        reverseCurve: const Interval(0.88, 1, curve: Curves.easeIn),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0, 0.12, curve: Curves.easeOutCubic),
          ),
        ),
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 96,
                  left: 24,
                  right: 24,
                ),
                child: _VodLockHoldHintBanner(message: widget.message),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
