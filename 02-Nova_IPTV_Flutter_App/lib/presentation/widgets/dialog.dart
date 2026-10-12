part of 'widgets.dart';

class DialogTrailerYoutube extends StatefulWidget {
  const DialogTrailerYoutube({super.key, required this.trailer, this.thumb});
  final String trailer;
  final String? thumb;

  @override
  State<DialogTrailerYoutube> createState() => _DialogTrailerYoutubeState();
}

class _DialogTrailerYoutubeState extends State<DialogTrailerYoutube> {
  late final PodPlayerController controller;

  @override
  void initState() {
    super.initState();
    controller = PodPlayerController(
      playVideoFrom: PlayVideoFrom.youtube(
        () {
          final id = normalizeYoutubeTrailerRef(widget.trailer) ?? widget.trailer.trim();
          if (id.startsWith('http://') || id.startsWith('https://')) {
            return id;
          }
          return 'https://youtu.be/$id';
        }(),
      ),
      podPlayerConfig: const PodPlayerConfig(autoPlay: false, isLooping: false),
    )..initialise();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.all(0),
      content: Ink(
        decoration: kDecorBackground,
        padding: const EdgeInsets.all(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PodVideoPlayer(
                controller: controller,
                //onToggleFullScreen: (value) async {},
                alwaysShowProgressBar: false,
                onToggleFullScreen: (value) async {
                  if (!value) {
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]);
                  }
                  return;
                },
                podProgressBarConfig: PodProgressBarConfig(
                  alwaysVisibleCircleHandler: false,
                  circleHandlerColor: kColorPrimary,
                  playingBarColor: kColorPrimary,
                ),
                videoThumbnail:
                    widget.thumb == null
                        ? null
                        : DecorationImage(
                          image: NetworkImage(widget.thumb ?? ""),
                          fit: BoxFit.cover,
                        ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CardButtonWatchMovie(
                  isFocused: true,
                  title: 'exit'.tr,
                  onTap: () => Get.back(),
                ),
                const SizedBox(width: 15),
                CardButtonWatchMovie(
                  title: controller.isVideoPlaying ? 'pause'.tr : 'play'.tr,
                  onTap: () {
                    setState(() {
                      if (controller.isVideoPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 5),
          ],
        ),
      ),
    );
  }
}

/// حوار تأكيد الخروج من التطبيق (قابل للتركيز بالريموت، هالة صفراء، تكبير)
class AppExitConfirmDialog extends StatefulWidget {
  const AppExitConfirmDialog({
    super.key,
    required this.onExit,
    required this.onStay,
  });

  final VoidCallback onExit;
  final VoidCallback onStay;

  @override
  State<AppExitConfirmDialog> createState() => _AppExitConfirmDialogState();
}

class _AppExitConfirmDialogState extends State<AppExitConfirmDialog> {
  late final FocusNode _stayFocusNode;
  late final FocusNode _exitFocusNode;

  @override
  void initState() {
    super.initState();
    _stayFocusNode = FocusNode();
    _exitFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // تركيز الريموت للتلفاز فقط — الهاتف بدون تركيز/تكبير.
      if (isTvDevice(context)) {
        _stayFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _stayFocusNode.dispose();
    _exitFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvFocus = isTvDevice(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: kColorCardLight,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.28),
                    ),
                    alignment: Alignment.center,
                    child: Image.asset(
                      kIconExit,
                      width: 34,
                      height: 34,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (_, _, _) => Icon(
                            Icons.exit_to_app_rounded,
                            size: 30,
                            color: kColorFocus.withValues(alpha: 0.95),
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'exit_confirm_title'.tr,
                  style: Get.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'exit_confirm_message'.tr,
                  style: Get.textTheme.bodyMedium?.copyWith(color: kColorHint),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _FocusableExitButton(
                        focusNode: _stayFocusNode,
                        label: 'exit_confirm_no'.tr,
                        icon: Icons.close_rounded,
                        onPressed: widget.onStay,
                        enableFocus: tvFocus,
                        enlargeOnFocus: false,
                        expanded: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FocusableExitButton(
                        focusNode: _exitFocusNode,
                        label: 'exit_confirm_yes'.tr,
                        icon: Icons.exit_to_app_rounded,
                        onPressed: widget.onExit,
                        isPrimary: true,
                        enableFocus: tvFocus,
                        enlargeOnFocus: false,
                        expanded: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// حوار تأكيد مضغوط (حذف / إيقاف تحميل) — أعرض قليلاً من حوار الخروج.
class AppActionConfirmDialog extends StatefulWidget {
  const AppActionConfirmDialog({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.message,
    this.highlight,
    required this.confirmLabel,
    required this.cancelLabel,
    this.confirmIcon,
    this.cancelIcon,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String message;
  final String? highlight;
  final String confirmLabel;
  final String cancelLabel;
  final IconData? confirmIcon;
  final IconData? cancelIcon;

  static Future<bool?> show(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    required String message,
    String? highlight,
    required String confirmLabel,
    required String cancelLabel,
    IconData? confirmIcon,
    IconData? cancelIcon,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (ctx) => AppActionConfirmDialog(
        icon: icon,
        accent: accent,
        title: title,
        message: message,
        highlight: highlight,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        confirmIcon: confirmIcon,
        cancelIcon: cancelIcon,
      ),
    );
  }

  @override
  State<AppActionConfirmDialog> createState() =>
      _AppActionConfirmDialogState();
}

class _AppActionConfirmDialogState extends State<AppActionConfirmDialog> {
  late final FocusNode _cancelFocusNode;
  late final FocusNode _confirmFocusNode;

  @override
  void initState() {
    super.initState();
    _cancelFocusNode = FocusNode(debugLabel: 'action_confirm_cancel');
    _confirmFocusNode = FocusNode(debugLabel: 'action_confirm_ok');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isTvDevice(context)) {
        _cancelFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _cancelFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvFocus = isTvDevice(context);
    final highlight = widget.highlight;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF151C2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, color: widget.accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.message,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13.5,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (highlight != null && highlight.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  highlight,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: kColorPrimary.withValues(alpha: 0.95),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _FocusableExitButton(
                      focusNode: _cancelFocusNode,
                      label: widget.cancelLabel,
                      icon: widget.cancelIcon ?? LucideIcons.x,
                      onPressed: () => Navigator.of(context).pop(false),
                      enableFocus: tvFocus,
                      enlargeOnFocus: false,
                      expanded: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FocusableExitButton(
                      focusNode: _confirmFocusNode,
                      label: widget.confirmLabel,
                      icon: widget.confirmIcon ?? LucideIcons.check,
                      onPressed: () => Navigator.of(context).pop(true),
                      isPrimary: true,
                      accentColor: widget.accent,
                      enableFocus: tvFocus,
                      enlargeOnFocus: false,
                      expanded: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حوار تأكيد إعادة التشغيل بعد تغيير وضع الأداء (نفس شكل خروج التطبيق، عرض مضغوط).
class AppRestartConfirmDialog extends StatefulWidget {
  const AppRestartConfirmDialog({
    super.key,
    required this.onRestart,
    required this.onLater,
    this.titleKey = 'settings_perf_restart_title',
    this.messageKey = 'settings_perf_restart_message',
  });

  final VoidCallback onRestart;
  final VoidCallback onLater;
  final String titleKey;
  final String messageKey;

  @override
  State<AppRestartConfirmDialog> createState() =>
      _AppRestartConfirmDialogState();
}

class _AppRestartConfirmDialogState extends State<AppRestartConfirmDialog> {
  late final FocusScopeNode _scope;
  late final FocusNode _laterFocusNode;
  late final FocusNode _restartFocusNode;

  @override
  void initState() {
    super.initState();
    _scope = FocusScopeNode(
      debugLabel: 'perf_restart_dialog',
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    );
    _laterFocusNode = FocusNode(debugLabel: 'perf_restart_later');
    _restartFocusNode = FocusNode(debugLabel: 'perf_restart_now');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isTvDevice(context)) {
        _restartFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _laterFocusNode.dispose();
    _restartFocusNode.dispose();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvFocus = isTvDevice(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: FocusScope(
        node: _scope,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: IntrinsicWidth(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                decoration: BoxDecoration(
                  color: kColorCardLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.28),
                        ),
                        alignment: Alignment.center,
                        child: FaIcon(
                          FontAwesomeIcons.arrowsRotate,
                          size: 20,
                          color: kColorPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.titleKey.tr,
                      style: Get.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.messageKey.tr,
                      style: Get.textTheme.bodySmall?.copyWith(
                        color: kColorHint,
                        height: 1.35,
                        fontSize: 12.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: _FocusableExitButton(
                              focusNode: _laterFocusNode,
                              label: 'settings_perf_restart_later'.tr,
                              icon: Icons.schedule_rounded,
                              onPressed: widget.onLater,
                              enableFocus: tvFocus,
                              enlargeOnFocus: false,
                              expanded: true,
                              dense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(2),
                            child: _FocusableExitButton(
                              focusNode: _restartFocusNode,
                              label: 'settings_perf_restart_now'.tr,
                              icon: Icons.restart_alt_rounded,
                              onPressed: widget.onRestart,
                              isPrimary: true,
                              enableFocus: tvFocus,
                              enlargeOnFocus: false,
                              expanded: true,
                              dense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableExitButton extends StatelessWidget {
  const _FocusableExitButton({
    required this.focusNode,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.icon,
    this.enableFocus = true,
    this.enlargeOnFocus = true,
    this.dense = false,
    this.expanded = false,
    this.accentColor,
  });

  final FocusNode focusNode;
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;
  final IconData? icon;
  final bool enableFocus;

  /// تكبير الزر عند التركيز (للتليفاز فقط عادةً).
  final bool enlargeOnFocus;

  /// زر أصغر لصف واحد (حوار استكمال المشاهدة).
  final bool dense;

  /// يملأ عرض الخلية داخل [Row]/Expanded].
  final bool expanded;

  /// لون الزر الأساسي (حذف / إيقاف…) — وإلا تدرج الخروج الافتراضي.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final radius = dense ? 10.0 : 12.0;
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final hasFocus = enableFocus && focusNode.hasFocus;
        final scale = kTvFocusScale(
          hasFocus && enlargeOnFocus,
          dense ? 1.05 : 1.08,
        );
        final solidAccent = accentColor;
        return Focus(
          focusNode: focusNode,
          canRequestFocus: enableFocus,
          skipTraversal: !enableFocus,
          onKeyEvent: (_, event) {
            if (!enableFocus) return KeyEventResult.ignored;
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              onPressed();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: AnimatedScale(
            scale: scale,
            duration: kFocusAnimDuration,
            child: AnimatedContainer(
              duration: kFocusAnimDuration,
              width: expanded ? double.infinity : null,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border:
                    hasFocus
                        ? Border.all(
                          color: kColorFocus,
                          width: dense ? 2 : 2.5,
                        )
                        : null,
                boxShadow: kTvFocusGlow(
                  focused: hasFocus,
                  blur: dense ? 8 : 10,
                  alpha: 0.5,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(radius),
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: BorderRadius.circular(radius),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      gradient: isPrimary && solidAccent == null
                          ? const LinearGradient(
                              colors: [
                                Color(0xFFD32F2F),
                                Color(0xFFE91E63),
                              ],
                            )
                          : null,
                      color: isPrimary
                          ? solidAccent
                          : kColorCardDark.withValues(alpha: 0.92),
                      border: isPrimary
                          ? null
                          : Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1.2,
                            ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: dense ? 10 : 14,
                        vertical: dense ? 8 : 11,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize:
                            expanded ? MainAxisSize.max : MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(
                              icon,
                              size: dense ? 14 : 17,
                              color: Colors.white,
                            ),
                            SizedBox(width: dense ? 5 : 7),
                          ],
                          if (expanded)
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: (dense
                                        ? Get.textTheme.labelMedium
                                        : Get.textTheme.labelLarge)
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: dense ? 12.5 : null,
                                    ),
                              ),
                            )
                          else
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Get.textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
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
        );
      },
    );
  }
}

/// حوار استكمال المشاهدة داخل المشغّل (قابل للتركيز بالريموت).
class ResumePlaybackDialog extends StatefulWidget {
  const ResumePlaybackDialog({
    super.key,
    required this.positionSeconds,
    required this.onContinue,
    required this.onRestart,
  });

  final double positionSeconds;
  final VoidCallback onContinue;
  final VoidCallback onRestart;

  @override
  State<ResumePlaybackDialog> createState() => _ResumePlaybackDialogState();
}

class _ResumePlaybackDialogState extends State<ResumePlaybackDialog> {
  static const int _autoContinueSeconds = 15;

  late final FocusScopeNode _scope;
  late final FocusNode _continueFocusNode;
  late final FocusNode _restartFocusNode;
  FocusNode? _lastInside;
  late int _secondsLeft;
  Timer? _timer;
  bool _closed = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _autoContinueSeconds;
    _scope = FocusScopeNode(
      debugLabel: 'resume_playback_dialog',
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    );
    _continueFocusNode = FocusNode(debugLabel: 'resume_playback_continue');
    _restartFocusNode = FocusNode(debugLabel: 'resume_playback_restart');
    FocusManager.instance.addListener(_guardFocus);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _closed) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        // انتهاء العداد بدون تفاعل = استكمال المشاهدة
        _finish(widget.onContinue);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed) return;
      _ensureFocusInside(preferContinue: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    FocusManager.instance.removeListener(_guardFocus);
    _continueFocusNode.dispose();
    _restartFocusNode.dispose();
    _scope.dispose();
    super.dispose();
  }

  bool _isInside(FocusNode? node) {
    if (node == null) return false;
    if (node == _scope) return true;
    return node.enclosingScope == _scope;
  }

  void _guardFocus() {
    if (!mounted || _restoring || _closed) return;
    if (!isTvDevice(context)) return;

    final primary = FocusManager.instance.primaryFocus;
    if (_isInside(primary)) {
      if (primary != null && primary != _scope) _lastInside = primary;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _restoring || _closed) return;
      if (_isInside(FocusManager.instance.primaryFocus)) return;
      _ensureFocusInside();
    });
  }

  void _ensureFocusInside({bool preferContinue = false}) {
    if (!mounted || _closed) return;
    if (!isTvDevice(context) && !isTv(context)) return;
    _restoring = true;
    try {
      if (preferContinue &&
          _continueFocusNode.canRequestFocus &&
          _continueFocusNode.context != null) {
        _continueFocusNode.requestFocus();
        _lastInside = _continueFocusNode;
        return;
      }
      final last = _lastInside;
      if (last != null &&
          last.canRequestFocus &&
          !last.skipTraversal &&
          last.context != null &&
          _isInside(last)) {
        last.requestFocus();
        return;
      }
      if (_continueFocusNode.canRequestFocus &&
          _continueFocusNode.context != null) {
        _continueFocusNode.requestFocus();
        _lastInside = _continueFocusNode;
        return;
      }
      if (_restartFocusNode.canRequestFocus &&
          _restartFocusNode.context != null) {
        _restartFocusNode.requestFocus();
        _lastInside = _restartFocusNode;
        return;
      }
      _scope.requestFocus();
    } finally {
      _restoring = false;
    }
  }

  void _finish(VoidCallback action) {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    FocusManager.instance.removeListener(_guardFocus);
    action();
  }

  KeyEventResult _onScopeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    // أسر الأسهم/Tab داخل الزرّين فقط — لا يخرج التركيز للمشغّل.
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.tab) {
      final primary = FocusManager.instance.primaryFocus;
      if (primary == _continueFocusNode) {
        _restartFocusNode.requestFocus();
        _lastInside = _restartFocusNode;
      } else {
        _continueFocusNode.requestFocus();
        _lastInside = _continueFocusNode;
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel = formatWatchPositionSeconds(widget.positionSeconds);
    final message =
        'resume_playback_message'.tr.replaceAll('@time', timeLabel);
    final textTheme = Theme.of(context).textTheme;
    final compact = !isTv(context);
    final maxWidth = compact ? 340.0 : 520.0;
    final marginH = compact ? 28.0 : 40.0;
    final padH = compact ? 18.0 : 28.0;
    final padVTop = compact ? 16.0 : 26.0;
    final padVBottom = compact ? 14.0 : 22.0;
    final iconBox = compact ? 44.0 : 64.0;
    final iconSize = compact ? 20.0 : 28.0;
    final radius = compact ? 14.0 : 20.0;
    final accent = kColorPrimary;
    final titleStyle = (compact ? textTheme.titleMedium : textTheme.titleLarge)
        ?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        );
    final bodyStyle = (compact ? textTheme.bodyMedium : textTheme.bodyLarge)
        ?.copyWith(
          color: kColorHint,
          height: 1.35,
        );

    return Material(
      type: MaterialType.transparency,
      child: FocusScope(
        node: _scope,
        autofocus: true,
        onKeyEvent: _onScopeKey,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                margin: EdgeInsets.symmetric(horizontal: marginH),
                padding: EdgeInsets.fromLTRB(padH, padVTop, padH, padVBottom),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kColorCardLight,
                      kColorCardDark.withValues(alpha: 0.95),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: kColorHint.withValues(alpha: 0.25),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: compact ? 18 : 28,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: kColorPrimary.withValues(alpha: 0.18),
                      blurRadius: compact ? 14 : 22,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: iconBox,
                      height: iconBox,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kColorPrimary.withValues(alpha: 0.18),
                        border: Border.all(
                          color: kColorPrimary.withValues(alpha: 0.45),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        FontAwesomeIcons.clockRotateLeft,
                        color: kColorFocus,
                        size: iconSize,
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Row(
                      children: [
                        // موازنة بصرية ليبقى العنوان في الوسط
                        SizedBox(width: compact ? 28 : 32),
                        Expanded(
                          child: Text(
                            'resume_playback_title'.tr,
                            style: titleStyle,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        _ResumeDialogCountdownBadge(
                          seconds: _secondsLeft,
                          accent: accent,
                          compact: compact,
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 6 : 10),
                    Text(
                      message,
                      style: bodyStyle,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: compact ? 6 : 8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 14,
                        vertical: compact ? 6 : 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(compact ? 8 : 10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            FontAwesomeIcons.play,
                            size: compact ? 10 : 12,
                            color: kColorFocus,
                          ),
                          SizedBox(width: compact ? 6 : 8),
                          Text(
                            timeLabel,
                            style: (compact
                                    ? textTheme.titleSmall
                                    : textTheme.titleMedium)
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 14 : 22),
                    Row(
                      children: [
                        Expanded(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: _FocusableExitButton(
                              focusNode: _continueFocusNode,
                              label: 'resume_playback_continue'.tr,
                              icon: FontAwesomeIcons.circlePlay,
                              onPressed: () => _finish(widget.onContinue),
                              isPrimary: true,
                              enableFocus: !compact,
                              dense: true,
                              expanded: true,
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 8),
                        Expanded(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(2),
                            child: _FocusableExitButton(
                              focusNode: _restartFocusNode,
                              label: 'resume_playback_restart'.tr,
                              icon: FontAwesomeIcons.rotateLeft,
                              onPressed: () => _finish(widget.onRestart),
                              enableFocus: !compact,
                              dense: true,
                              expanded: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شارة العدّاد — نفس شكل توست استكمال قناة البث.
class _ResumeDialogCountdownBadge extends StatelessWidget {
  const _ResumeDialogCountdownBadge({
    required this.seconds,
    required this.accent,
    required this.compact,
  });

  final int seconds;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 28.0 : 32.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.14),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$seconds',
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 11.5 : 13,
          height: 1,
        ),
      ),
    );
  }
}
