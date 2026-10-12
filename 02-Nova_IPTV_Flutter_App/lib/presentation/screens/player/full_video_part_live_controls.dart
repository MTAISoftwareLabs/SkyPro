part of '../screens.dart';

/// لون شريط تقدّم برنامج EPG (بنفسجي أنيق كالمرجع).
const Color _kLiveEpgProgressColor = Color(0xFF8E44AD);

extension _LivePlayerControls on _FullVideoScreenState {
  double _liveEpgProgress() {
    final p = _currentProgram;
    if (p == null) return 0;
    final now = DateTime.now();
    if (now.isBefore(p.start)) return 0;
    if (now.isAfter(p.end)) return 1;
    final total = p.end.difference(p.start).inMilliseconds;
    if (total <= 0) return 0;
    return (now.difference(p.start).inMilliseconds / total).clamp(0.0, 1.0);
  }

  Widget _liveEpgLabeledLine({
    required String label,
    required String body,
    required TextStyle baseStyle,
    int maxLines = 1,
  }) {
    final baseSize = baseStyle.fontSize ?? 12;
    final labelStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w900,
      fontSize: baseSize + 1.5,
      letterSpacing: 0.35,
      height: 1.2,
    );
    final bodyStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: baseSize,
      height: 1.2,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label, style: labelStyle),
          TextSpan(text: '  ', style: bodyStyle),
          TextSpan(text: body, style: bodyStyle),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// بعض السيرفرات كيكتبوا Now/Next داخل العنوان — نحيدوهم باش ما يتكرروش.
  String _epgCleanTitle(String raw) {
    var t = raw.trim();
    t = t.replaceFirst(
      RegExp(r'^(now|next)\s*[:：\-–]\s*', caseSensitive: false),
      '',
    );
    return t.trim();
  }

  String _epgProgramBody(EpgProgram? p) {
    if (p == null) return 'epg_no_info'.tr;
    final start = DateFormat.Hm().format(p.start);
    final end = DateFormat.Hm().format(p.end);
    final title = _epgCleanTitle(p.title);
    if (title.isEmpty) return '$start - $end';
    return '$title  $start - $end';
  }

  ({String label, String body}) _liveEpgNowParts() {
    return (
      label: 'epg_label_now'.tr,
      body: _epgProgramBody(_currentProgram),
    );
  }

  ({String label, String body})? _liveEpgNextParts() {
    final p = _nextProgram;
    if (p == null) return null;
    return (
      label: 'epg_label_next'.tr,
      body: _epgProgramBody(p),
    );
  }

  List<Widget> _liveEpgNowNextTexts({
    required TextStyle nowStyle,
    TextStyle? nextStyle,
    int nowMaxLines = 1,
    int nextMaxLines = 1,
  }) {
    final now = _liveEpgNowParts();
    final next = _liveEpgNextParts();
    return [
      _liveEpgLabeledLine(
        label: now.label,
        body: now.body,
        baseStyle: nowStyle,
        maxLines: nowMaxLines,
      ),
      if (next != null) ...[
        const SizedBox(height: 2),
        _liveEpgLabeledLine(
          label: next.label,
          body: next.body,
          baseStyle: nextStyle ?? nowStyle,
          maxLines: nextMaxLines,
        ),
      ],
    ];
  }

  String _liveEpgEndClockText() {
    final p = _currentProgram;
    if (p == null) return '--:--:--';
    return DateFormat('HH:mm:ss').format(p.end);
  }

  Widget _buildLivePlayerControlsOverlay({
    required String liveName,
  }) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final topPad = MediaQuery.of(context).padding.top;
    final epgProgress = _liveEpgProgress();

    final controlsVisible = showControllersVideo && !_showLiveIptvOverlay;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _onBvVerticalDragStart,
      onVerticalDragUpdate: _onBvVerticalDragUpdate,
      onVerticalDragCancel: _onBvVerticalDragCancel,
      onVerticalDragEnd: _onBvVerticalDragEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: !controlsVisible,
            child: AnimatedOpacity(
          opacity: controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: Stack(
            fit: StackFit.expand,
            children: [
            // تدرج سفلي لقراءة النص
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
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // زر الرجوع + قائمة القنوات/الفئات
            Positioned(
              top: topPad + 10,
              left: 16,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LiveBackButton(
                    focusNode: _liveBackFocusNode,
                    onTap: widget.startInIptvBrowser
                        ? _openLiveIptvOverlay
                        : _popWithResult,
                    onKeyEvent: (node, event) {
                      if (event is KeyUpEvent && _isOkLogicalKey(event.logicalKey)) {
                        return KeyEventResult.handled;
                      }
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;
                      if (_isOkLogicalKey(key)) {
                        if (widget.startInIptvBrowser) {
                          _openLiveIptvOverlay();
                        } else {
                          _popWithResult();
                        }
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowRight) {
                        _liveChannelsListFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowDown) {
                        node.unfocus();
                        _liveChannelsListFocusNode.unfocus();
                        _liveFavoriteFocusNode.unfocus();
                        _aspectRatioFocusNode.unfocus();
                        _settingsGearFocusNode.unfocus();
                        if (_playButtonFocusNode.canRequestFocus) {
                          _playButtonFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                  ),
                  const SizedBox(width: 8),
                  _LiveChannelsListButton(
                    focusNode: _liveChannelsListFocusNode,
                    onTap: _openLiveIptvOverlay,
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;
                      if (_isOkLogicalKey(key)) {
                        _openLiveIptvOverlay();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowLeft) {
                        _liveBackFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowRight) {
                        _liveFavoriteFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowDown) {
                        node.unfocus();
                        _liveBackFocusNode.unfocus();
                        _liveFavoriteFocusNode.unfocus();
                        _aspectRatioFocusNode.unfocus();
                        _settingsGearFocusNode.unfocus();
                        if (_playButtonFocusNode.canRequestFocus) {
                          _playButtonFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                  ),
                ],
              ),
            ),

            // شريط علوي: مفضلة + aspect + تبديل المشغل + معلومات القناة + الساعة
            Positioned(
              top: topPad + 10,
              right: 16,
              child: BlocBuilder<FavoritesCubit, FavoritesState>(
                builder: (context, favState) {
                  final ch = _currentLiveChannel ?? widget.channelLive;
                  final isFavorite =
                      ch != null &&
                      favState.lives.any((l) => liveChannelsMatch(l, ch));
                  return _LiveTopActionPill(
                    favoriteFocusNode: _liveFavoriteFocusNode,
                    isFavorite: isFavorite,
                    showPlayerSwitch: !Platform.isIOS,
                    infoFocusNode: _streamInfoFocusNode,
                    audioFocusNode: _liveAudioFocusNode,
                    onAudioTap: () => unawaited(_showLiveAudioTracksPicker()),
                    onAudioKey: (node, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;
                      if (_isOkLogicalKey(key)) {
                        unawaited(_showLiveAudioTracksPicker());
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowLeft) {
                        if (!Platform.isIOS) {
                          _settingsGearFocusNode.requestFocus();
                        } else {
                          _aspectRatioFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowRight) {
                        _streamInfoFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowDown) {
                        _liveFavoriteFocusNode.unfocus();
                        _aspectRatioFocusNode.unfocus();
                        _liveAudioFocusNode.unfocus();
                        _streamInfoFocusNode.unfocus();
                        _settingsGearFocusNode.unfocus();
                        if (_playButtonFocusNode.canRequestFocus) {
                          _playButtonFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    onInfoTap: _showStreamInfoDialog,
                    onInfoKey: (node, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;
                      if (_isOkLogicalKey(key)) {
                        _showStreamInfoDialog();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowLeft) {
                        _liveAudioFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowDown) {
                        _liveFavoriteFocusNode.unfocus();
                        _aspectRatioFocusNode.unfocus();
                        _liveAudioFocusNode.unfocus();
                        _streamInfoFocusNode.unfocus();
                        _settingsGearFocusNode.unfocus();
                        if (_playButtonFocusNode.canRequestFocus) {
                          _playButtonFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    onFavoriteTap: () {
                      if (ch != null) _toggleFavoriteForChannel(ch);
                    },
                    onFavoriteKey: (node, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;
                      if (_isOkLogicalKey(key)) {
                        if (ch != null) _toggleFavoriteForChannel(ch);
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowLeft) {
                        _liveChannelsListFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowRight) {
                        _aspectRatioFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowDown) {
                        _liveFavoriteFocusNode.unfocus();
                        _aspectRatioFocusNode.unfocus();
                        _liveAudioFocusNode.unfocus();
                        _streamInfoFocusNode.unfocus();
                        _settingsGearFocusNode.unfocus();
                        if (_playButtonFocusNode.canRequestFocus) {
                          _playButtonFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    aspectFocusNode: _aspectRatioFocusNode,
                    playerFocusNode: _settingsGearFocusNode,
                    onAspectTap: _cycleAspectRatio,
                    onAspectKey: (node, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;
                      if (_isOkLogicalKey(key)) {
                        _cycleAspectRatio();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowDown) {
                        _liveFavoriteFocusNode.unfocus();
                        _aspectRatioFocusNode.unfocus();
                        _liveAudioFocusNode.unfocus();
                        _streamInfoFocusNode.unfocus();
                        _settingsGearFocusNode.unfocus();
                        if (_playButtonFocusNode.canRequestFocus) {
                          _playButtonFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowLeft) {
                        _liveFavoriteFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowRight) {
                        if (!Platform.isIOS) {
                          _settingsGearFocusNode.requestFocus();
                        } else {
                          _liveAudioFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    onPlayerKey: (node, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;
                      if (key == LogicalKeyboardKey.arrowLeft) {
                        _aspectRatioFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowRight) {
                        _liveAudioFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.arrowDown) {
                        _liveFavoriteFocusNode.unfocus();
                        _aspectRatioFocusNode.unfocus();
                        _liveAudioFocusNode.unfocus();
                        _streamInfoFocusNode.unfocus();
                        _settingsGearFocusNode.unfocus();
                        if (_playButtonFocusNode.canRequestFocus) {
                          _playButtonFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      if (_isOkLogicalKey(key)) {
                        _showChangePlayerDialog();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    onPlayerTap: _showChangePlayerDialog,
                  );
                },
              ),
            ),

            // عناصر التحكم المركزية
            Center(
              child: _LiveCenterControls(
                isPlaying: _isVlcBuffering || isPlayed,
                playFocusNode: _playButtonFocusNode,
                onPlayPause: _togglePlayPause,
                onPlayKey: (node, event) {
                  if (event is KeyDownEvent) {
                    final key = event.logicalKey;
                    if (key == LogicalKeyboardKey.arrowDown &&
                        !_showLiveIptvOverlay) {
                      _openLiveChannelOverlay();
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowUp &&
                        !_showLiveIptvOverlay) {
                      if (_liveFavoriteFocusNode.canRequestFocus) {
                        _liveFavoriteFocusNode.requestFocus();
                      }
                      return KeyEventResult.handled;
                    }
                    if (_isOkLogicalKey(key)) {
                      _startOkLongPressTimer();
                      _togglePlayPause();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  }
                  if (event is KeyUpEvent && _isOkLogicalKey(event.logicalKey)) {
                    _cancelOkLongPressAndCheckTriggered();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                canGoPrevious: _liveZapCanMove(-1),
                canGoNext: _liveZapCanMove(1),
                onRewind: () => unawaited(_zapLiveChannelByDelta(-1)),
                onForward: () => unawaited(_zapLiveChannelByDelta(1)),
              ),
            ),

            // معلومات البرنامج + شريط EPG
            Positioned(
              left: 18,
              right: 18,
              bottom: bottomPad + 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'live_badge'.tr.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 10.sp,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    liveName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Get.textTheme.headlineSmall!.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18.sp,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ..._liveEpgNowNextTexts(
                    nowStyle: Get.textTheme.bodyMedium!.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w500,
                      fontSize: 12.sp,
                    ),
                    nextStyle: Get.textTheme.bodyMedium!.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w500,
                      fontSize: 12.sp,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 4,
                              child: LinearProgressIndicator(
                                value: epgProgress > 0 ? epgProgress : null,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.18),
                                valueColor: const AlwaysStoppedAnimation(
                                  _kLiveEpgProgressColor,
                                ),
                              ),
                            ),
                          ),
                          if (epgProgress > 0 && epgProgress < 1)
                            Positioned(
                              left: (w * epgProgress).clamp(0.0, w - 2) - 1,
                              top: -3,
                              child: Container(
                                width: 2,
                                height: 10,
                                color: Colors.white,
                              ),
                            ),
                          Positioned(
                            right: 0,
                            top: -18,
                            child: Text(
                              'live_badge'.tr.toUpperCase(),
                              style: TextStyle(
                                color: _kLiveEpgProgressColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 9.sp,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _LiveClockText(
                        pattern: 'HH:mm:ss',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 11.sp,
                        ),
                      ),
                      Text(
                        _liveEpgEndClockText(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 11.sp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
          ),
          _buildLiveStreamInfoBar(),
        ],
      ),
    );
  }
}

class _LiveTopActionPill extends StatelessWidget {
  const _LiveTopActionPill({
    required this.favoriteFocusNode,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.onFavoriteKey,
    required this.aspectFocusNode,
    required this.infoFocusNode,
    required this.onInfoTap,
    required this.onInfoKey,
    required this.audioFocusNode,
    required this.onAudioTap,
    required this.onAudioKey,
    required this.playerFocusNode,
    required this.onAspectTap,
    required this.onAspectKey,
    required this.onPlayerKey,
    required this.onPlayerTap,
    this.showPlayerSwitch = true,
  });

  final FocusNode favoriteFocusNode;
  final bool isFavorite;
  final VoidCallback onFavoriteTap;
  final FocusOnKeyEventCallback onFavoriteKey;
  final FocusNode aspectFocusNode;
  final FocusNode infoFocusNode;
  final VoidCallback onInfoTap;
  final FocusOnKeyEventCallback onInfoKey;
  final FocusNode audioFocusNode;
  final VoidCallback onAudioTap;
  final FocusOnKeyEventCallback onAudioKey;
  final FocusNode playerFocusNode;
  final VoidCallback onAspectTap;
  final FocusOnKeyEventCallback onAspectKey;
  final FocusOnKeyEventCallback onPlayerKey;
  final VoidCallback onPlayerTap;
  final bool showPlayerSwitch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LivePillIconButton(
            icon:
                isFavorite
                    ? FontAwesomeIcons.solidHeart
                    : FontAwesomeIcons.heart,
            iconColor: isFavorite ? const Color(0xFFE50914) : Colors.white,
            focusNode: favoriteFocusNode,
            onTap: onFavoriteTap,
            onKeyEvent: onFavoriteKey,
            tooltip: 'fav_title'.tr,
          ),
          _LivePillDivider(),
          _LivePillIconButton(
            imageAsset: kIconAspectRatio,
            focusNode: aspectFocusNode,
            onTap: onAspectTap,
            onKeyEvent: onAspectKey,
            tooltip: 'Aspect ratio',
          ),
          if (showPlayerSwitch) ...[
            _LivePillDivider(),
            _LivePillIconButton(
              imageAsset: kIconPlayerSwitch,
              focusNode: playerFocusNode,
              onTap: onPlayerTap,
              onKeyEvent: onPlayerKey,
              tooltip: 'change_player'.tr,
            ),
          ],
          _LivePillDivider(),
          _LivePillIconButton(
            icon: LucideIcons.audio_lines,
            focusNode: audioFocusNode,
            onTap: onAudioTap,
            onKeyEvent: onAudioKey,
            tooltip: 'player_audio_tracks'.tr,
          ),
          _LivePillDivider(),
          _LivePillIconButton(
            icon: LucideIcons.info,
            focusNode: infoFocusNode,
            onTap: onInfoTap,
            onKeyEvent: onInfoKey,
            tooltip: 'stream_info_title'.tr,
          ),
          _LivePillDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _LiveClockText(
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13.sp,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePillDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Colors.white.withValues(alpha: 0.22),
    );
  }
}

class _LivePillIconButton extends StatelessWidget {
  const _LivePillIconButton({
    this.icon,
    this.imageAsset,
    this.iconColor,
    required this.focusNode,
    required this.onTap,
    required this.onKeyEvent,
    this.tooltip,
  }) : assert(icon != null || imageAsset != null);

  final IconData? icon;
  final String? imageAsset;
  final Color? iconColor;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final FocusOnKeyEventCallback onKeyEvent;
  final String? tooltip;

  static const double _iconSize = 20;

  Widget _buildIconContent() {
    if (imageAsset != null) {
      return Image.asset(
        imageAsset!,
        width: _iconSize,
        height: _iconSize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }
    return Icon(
      icon,
      size: _iconSize,
      color: iconColor ?? Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final hasFocus = focusNode.hasFocus;
        return Focus(
          focusNode: focusNode,
          onKeyEvent: onKeyEvent,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    hasFocus
                        ? Colors.black.withValues(alpha: 0.55)
                        : Colors.transparent,
                border: Border.all(
                  color:
                      hasFocus
                          ? kColorFocus
                          : Colors.white.withValues(alpha: 0.18),
                  width: hasFocus ? 2.4 : 1,
                ),
                boxShadow:
                    hasFocus
                        ? [
                          BoxShadow(
                            color: kColorFocus.withValues(alpha: 0.45),
                            blurRadius: 10,
                            spreadRadius: 0.5,
                          ),
                        ]
                        : null,
              ),
              child: _buildIconContent(),
            ),
          ),
        );
      },
    );
  }
}

class _LiveCenterControls extends StatelessWidget {
  const _LiveCenterControls({
    required this.isPlaying,
    required this.playFocusNode,
    required this.onPlayPause,
    required this.onPlayKey,
    required this.onRewind,
    required this.onForward,
    this.canGoPrevious = true,
    this.canGoNext = true,
    this.seekStyle = false,
    this.allowFocus = true,
  });

  final bool isPlaying;
  final FocusNode playFocusNode;
  final VoidCallback onPlayPause;
  final FocusOnKeyEventCallback onPlayKey;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool seekStyle;
  final bool allowFocus;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: [
        _LiveSkipCircleButton(
          icon: seekStyle ? LucideIcons.rotate_ccw : LucideIcons.chevron_left,
          label: seekStyle ? '10' : null,
          caption: seekStyle ? null : 'live_zap_previous'.tr,
          enabled: canGoPrevious,
          onTap: onRewind,
        ),
        const SizedBox(width: 28),
        Focus(
          focusNode: playFocusNode,
          canRequestFocus: allowFocus,
          skipTraversal: true,
          onKeyEvent: onPlayKey,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPlayPause,
              canRequestFocus: false,
              // No focus halo — focus is silent on play/pause.
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              customBorder: const CircleBorder(),
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.92),
                    width: 2.2,
                  ),
                  color: Colors.black.withValues(alpha: 0.25),
                ),
                child: Icon(
                  isPlaying ? LucideIcons.pause : LucideIcons.play,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 28),
        _LiveSkipCircleButton(
          icon: seekStyle ? LucideIcons.rotate_cw : LucideIcons.chevron_right,
          label: seekStyle ? '10' : null,
          caption: seekStyle ? null : 'live_zap_next'.tr,
          enabled: canGoNext,
          onTap: onForward,
        ),
      ],
    );
  }
}

class _LiveSkipCircleButton extends StatelessWidget {
  const _LiveSkipCircleButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.caption,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final String? caption;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              canRequestFocus: false,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      icon,
                      color: Colors.white.withValues(
                        alpha: enabled ? 0.92 : 0.28,
                      ),
                      size: 38,
                    ),
                    if (label != null)
                      Text(
                        label!,
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: enabled ? 1 : 0.4,
                          ),
                          fontWeight: FontWeight.w800,
                          fontSize: 11.sp,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (caption != null)
            Positioned(
              top: 50,
              left: -28,
              right: -28,
              child: IgnorePointer(
                child: Text(
                  caption!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: enabled ? 0.96 : 0.32,
                    ),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.sp,
                    height: 1.1,
                    letterSpacing: 0.2,
                    shadows: const [
                      Shadow(
                        color: Color(0xE6000000),
                        blurRadius: 8,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveClockText extends StatefulWidget {
  const _LiveClockText({
    required this.style,
    this.pattern = 'HH:mm',
  });

  final TextStyle style;
  final String pattern;

  @override
  State<_LiveClockText> createState() => _LiveClockTextState();
}

class _LiveClockTextState extends State<_LiveClockText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      DateFormat(widget.pattern).format(DateTime.now()),
      style: widget.style,
    );
  }
}

class _LiveBackButton extends StatefulWidget {
  const _LiveBackButton({
    required this.onTap,
    required this.focusNode,
    this.onKeyEvent,
  });

  final VoidCallback onTap;
  final FocusNode focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<_LiveBackButton> createState() => _LiveBackButtonState();
}

class _LiveBackButtonState extends State<_LiveBackButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: widget.onKeyEvent,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      child: Material(
        color: Colors.black.withValues(alpha: _focused ? 0.78 : 0.62),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: widget.onTap,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(24),
          focusColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _focused
                    ? kColorFocus
                    : Colors.white.withValues(alpha: 0.12),
                width: _focused ? 1.6 : 1,
              ),
            ),
            child: Icon(
              LucideIcons.arrow_left,
              color: _focused ? kColorFocus : Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChannelsListButton extends StatefulWidget {
  const _LiveChannelsListButton({
    required this.onTap,
    required this.focusNode,
    this.onKeyEvent,
  });

  final VoidCallback onTap;
  final FocusNode focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<_LiveChannelsListButton> createState() =>
      _LiveChannelsListButtonState();
}

class _LiveChannelsListButtonState extends State<_LiveChannelsListButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: widget.onKeyEvent,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      child: Material(
        color: Colors.black.withValues(alpha: _focused ? 0.78 : 0.62),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: widget.onTap,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(24),
          focusColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _focused
                    ? kColorFocus
                    : Colors.white.withValues(alpha: 0.12),
                width: _focused ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.list_video,
                  color: _focused ? kColorFocus : Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 7),
                Text(
                  'live_channels_list'.tr,
                  style: TextStyle(
                    color: _focused ? kColorFocus : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    letterSpacing: 0.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
