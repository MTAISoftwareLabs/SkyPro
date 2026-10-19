part of 'helpers.dart';

enum _AppToastKind { warning, error, success, info }

class _AppToastStyle {
  const _AppToastStyle({
    required this.accent,
    required this.icon,
  });

  final Color accent;
  final IconData icon;
}

bool _toastIsRtl() {
  final code =
      Get.locale?.languageCode ??
      GetStorage().read(kStorageLocale) as String? ??
      'en';
  return code == 'ar' || code == 'fa';
}

_AppToastStyle _styleForKind(_AppToastKind kind) {
  switch (kind) {
    case _AppToastKind.warning:
      return const _AppToastStyle(
        accent: Color(0xFFFFB020),
        icon: Icons.warning_amber_rounded,
      );
    case _AppToastKind.error:
      return const _AppToastStyle(
        accent: Color(0xFFFF5C6A),
        icon: Icons.error_rounded,
      );
    case _AppToastKind.success:
      return _AppToastStyle(
        accent: kColorPrimary,
        icon: Icons.check_circle_rounded,
      );
    case _AppToastKind.info:
      return const _AppToastStyle(
        accent: Color(0xFF5BA8FF),
        icon: Icons.info_rounded,
      );
  }
}

/// بطاقة إشعار عائمة — RTL/LTR حسب اللغة، تصميم pill عصري.
class _AppToastCard extends StatelessWidget {
  const _AppToastCard({
    required this.title,
    required this.message,
    required this.kind,
    required this.onClose,
    required this.isRtl,
  });

  final String title;
  final String message;
  final _AppToastKind kind;
  final VoidCallback onClose;
  final bool isRtl;

  @override
  Widget build(BuildContext context) {
    final style = _styleForKind(kind);
    final accent = style.accent;
    final hasMessage = message.trim().isNotEmpty;
    final textDir = isRtl ? TextDirection.rtl : TextDirection.ltr;

    Widget iconBadge = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 10,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Icon(style.icon, color: accent, size: 20),
    );

    Widget textBlock = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.97),
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              height: 1.25,
              letterSpacing: isRtl ? 0 : 0.1,
            ),
          ),
          if (hasMessage) ...[
            const SizedBox(height: 4),
            Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontWeight: FontWeight.w500,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );

    Widget closeBtn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onClose,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            Icons.close_rounded,
            size: 17,
            color: Colors.white.withValues(alpha: 0.42),
          ),
        ),
      ),
    );

    return Directionality(
      textDirection: textDir,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: const Color(0xF014161E),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.09),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.48),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 20,
                spreadRadius: -6,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                // Accent glow on the start edge (right in RTL / left in LTR)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: isRtl ? null : 0,
                  right: isRtl ? 0 : null,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          accent.withValues(alpha: 0.05),
                          accent,
                          accent.withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      iconBadge,
                      const SizedBox(width: 12),
                      textBlock,
                      const SizedBox(width: 4),
                      closeBtn,
                    ],
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

double _toastWidthFor(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 900) return 380;
  if (w >= 600) return 340;
  return (w * 0.78).clamp(248.0, 320.0);
}

EdgeInsets _toastMargin() => const EdgeInsets.fromLTRB(16, 0, 16, 22);

_AppToastKind _resolveWarningKind(String title, String message) {
  final t = '${title.toLowerCase()} ${message.toLowerCase()}';
  const errorHints = [
    'error',
    'failed',
    'fail',
    'invalid',
    'خطأ',
    'فشل',
    'غير صالح',
    'غير صحيح',
  ];
  for (final h in errorHints) {
    if (t.contains(h)) return _AppToastKind.error;
  }
  return _AppToastKind.warning;
}

/// يمنع وميض toast عند استماع أكثر من صفحة لـ AuthFailed في نفس الوقت.
String? _lastAppToastKey;
DateTime? _lastAppToastAt;

bool _shouldSkipDuplicateToast(String title, String message, _AppToastKind kind) {
  final key = '$kind|$title|$message';
  final now = DateTime.now();
  if (_lastAppToastKey == key &&
      _lastAppToastAt != null &&
      now.difference(_lastAppToastAt!) < const Duration(milliseconds: 2000)) {
    return true;
  }
  _lastAppToastKey = key;
  _lastAppToastAt = now;
  return false;
}

void _showAppToast(
  BuildContext context, {
  required String title,
  required String message,
  required _AppToastKind kind,
}) {
  if (_shouldSkipDuplicateToast(title, message, kind)) return;

  final isRtl = _toastIsRtl();
  final messenger = ScaffoldMessenger.maybeOf(context) ??
      (Get.context != null ? ScaffoldMessenger.maybeOf(Get.context!) : null);

  final toastContext = messenger?.context ?? Get.context ?? context;
  final toastWidth = _toastWidthFor(toastContext);
  final style = _styleForKind(kind);

  if (messenger == null) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: const Color(0xF014161E),
      colorText: Colors.white,
      margin: _toastMargin(),
      maxWidth: toastWidth,
      borderRadius: 22,
      borderColor: Colors.white.withValues(alpha: 0.09),
      borderWidth: 1,
      icon: Icon(style.icon, color: style.accent, size: 22),
      shouldIconPulse: false,
      duration: const Duration(seconds: 3),
      isDismissible: true,
    );
    return;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted && Get.context == null) return;

    final card = _AppToastCard(
      title: title,
      message: message,
      kind: kind,
      isRtl: isRtl,
      onClose: messenger.hideCurrentSnackBar,
    );

    final snackBar = SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      width: toastWidth,
      padding: EdgeInsets.zero,
      duration: const Duration(seconds: 3),
      dismissDirection: DismissDirection.horizontal,
      content: card,
    );

    // clear ثم show مرة واحدة — hide+show المزدوج من صفحتين كان يسبب وميض.
    messenger
      ..clearSnackBars()
      ..showSnackBar(snackBar);
  });
}

void showWarningToast(BuildContext context, String title, String message) {
  _showAppToast(
    context,
    title: title,
    message: message,
    kind: _resolveWarningKind(title, message),
  );
}

void showSoftToast(BuildContext context, String title, String message) {
  _showAppToast(
    context,
    title: title,
    message: message,
    kind: _AppToastKind.success,
  );
}

/// Toast above dialogs/modals (uses the root overlay, not ScaffoldMessenger).
void showSoftToastAboveOverlay(
  BuildContext context,
  String title,
  String message,
) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    showSoftToast(context, title, message);
    return;
  }

  final isRtl = _toastIsRtl();
  final toastWidth = _toastWidthFor(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      return SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: _toastMargin(),
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: toastWidth,
                child: _AppToastCard(
                  title: title,
                  message: message,
                  kind: _AppToastKind.success,
                  isRtl: isRtl,
                  onClose: () {
                    if (entry.mounted) entry.remove();
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  Future<void>.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}

void showInfoToast(BuildContext context, String title, String message) {
  _showAppToast(
    context,
    title: title,
    message: message,
    kind: _AppToastKind.info,
  );
}

/// توست مدمج لاستكمال آخر قناة — وسط الشاشة، عدّاد 12ث، تركيز ريموت محبوس، RTL.
void showLastChannelResumeToast(
  BuildContext context, {
  required String channelName,
  String? channelLogoUrl,
  required VoidCallback onContinue,
  VoidCallback? onDismiss,
  VoidCallback? onRestoreHomeFocus,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  final isRtl = _toastIsRtl();
  final toastWidth = _toastWidthFor(context);
  late OverlayEntry entry;
  var closed = false;

  void removeEntry({required bool restoreHomeFocus}) {
    if (closed) return;
    closed = true;
    if (entry.mounted) entry.remove();
    if (restoreHomeFocus) {
      // بعد إزالة الـ overlay حتى لا يتعارض تركيز التوست.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onRestoreHomeFocus?.call();
      });
    }
  }

  entry = OverlayEntry(
    builder: (ctx) {
      return _LastChannelResumeToastHost(
        channelName: channelName,
        channelLogoUrl: channelLogoUrl,
        isRtl: isRtl,
        toastWidth: toastWidth,
        durationSeconds: 12,
        onContinue: () {
          // الانتقال للمشغّل؛ لا نستعيد تركيز الرئيسية.
          removeEntry(restoreHomeFocus: false);
          onContinue();
        },
        onClose: () {
          removeEntry(restoreHomeFocus: true);
          onDismiss?.call();
        },
      );
    },
  );

  overlay.insert(entry);
}

class _LastChannelResumeToastHost extends StatefulWidget {
  const _LastChannelResumeToastHost({
    required this.channelName,
    this.channelLogoUrl,
    required this.isRtl,
    required this.toastWidth,
    required this.durationSeconds,
    required this.onContinue,
    required this.onClose,
  });

  final String channelName;
  final String? channelLogoUrl;
  final bool isRtl;
  final double toastWidth;
  final int durationSeconds;
  final VoidCallback onContinue;
  final VoidCallback onClose;

  @override
  State<_LastChannelResumeToastHost> createState() =>
      _LastChannelResumeToastHostState();
}

class _LastChannelResumeToastHostState
    extends State<_LastChannelResumeToastHost> {
  late int _secondsLeft;
  Timer? _timer;
  late final FocusScopeNode _scope = FocusScopeNode(
    debugLabel: 'last_channel_resume_toast',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  final FocusNode _continueFocus = FocusNode(
    debugLabel: 'last_channel_resume_continue',
  );
  final FocusNode _closeFocus = FocusNode(
    debugLabel: 'last_channel_resume_close',
  );
  FocusNode? _lastInside;
  bool _continueFocused = false;
  bool _closeFocused = false;
  bool _closed = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.durationSeconds;
    _continueFocus.addListener(() {
      if (_continueFocused != _continueFocus.hasFocus) {
        setState(() => _continueFocused = _continueFocus.hasFocus);
      }
    });
    _closeFocus.addListener(() {
      if (_closeFocused != _closeFocus.hasFocus) {
        setState(() => _closeFocused = _closeFocus.hasFocus);
      }
    });
    FocusManager.instance.addListener(_guardFocus);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _closed) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        _finish(widget.onClose);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureFocusInside(preferContinue: true);
      // إطار ثانٍ: الرئيسية قد تستعيد التركيز بعد الإدراج.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _closed) return;
        if (!_isInside(FocusManager.instance.primaryFocus)) {
          _ensureFocusInside(preferContinue: true);
        }
      });
    });
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
    _restoring = true;
    try {
      if (preferContinue &&
          _continueFocus.canRequestFocus &&
          _continueFocus.context != null) {
        _continueFocus.requestFocus();
        _lastInside = _continueFocus;
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
      if (_continueFocus.canRequestFocus && _continueFocus.context != null) {
        _continueFocus.requestFocus();
        _lastInside = _continueFocus;
        return;
      }
      if (_closeFocus.canRequestFocus && _closeFocus.context != null) {
        _closeFocus.requestFocus();
        _lastInside = _closeFocus;
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

  @override
  void dispose() {
    _timer?.cancel();
    FocusManager.instance.removeListener(_guardFocus);
    _continueFocus.dispose();
    _closeFocus.dispose();
    _scope.dispose();
    super.dispose();
  }

  KeyEventResult _onScopeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // يسار/يمين (وبيئتهما) يتنقلان بين الزرّين فقط.
    final toClose =
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.tab;
    if (toClose) {
      final primary = FocusManager.instance.primaryFocus;
      if (primary == _continueFocus) {
        _closeFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (primary == _closeFocus) {
        _continueFocus.requestFocus();
        return KeyEventResult.handled;
      }
      _continueFocus.requestFocus();
      return KeyEventResult.handled;
    }

    // أعلى/أسفل تبقى داخل التوست.
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final accent = kColorPrimary;
    final textDir = widget.isRtl ? TextDirection.rtl : TextDirection.ltr;
    final tv = isTvDevice(context);

    return Material(
      color: Colors.black.withValues(alpha: 0.28),
      child: FocusScope(
        node: _scope,
        autofocus: tv,
        onKeyEvent: tv ? _onScopeKey : null,
        child: SafeArea(
          child: Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: widget.toastWidth,
                child: wrapAppDirectionality(
                  child: Directionality(
                    textDirection: textDir,
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: const Color(0xF014161E),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: accent.withValues(alpha: 0.16),
                              blurRadius: 18,
                              spreadRadius: -4,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Stack(
                            children: [
                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: widget.isRtl ? null : 0,
                                right: widget.isRtl ? 0 : null,
                                child: Container(width: 3, color: accent),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  10,
                                  10,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        _ResumeChannelLogo(
                                          logoUrl: widget.channelLogoUrl,
                                          accent: accent,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'last_channel_resume_title'.tr,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.96),
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                  height: 1.2,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'last_channel_resume_msg'
                                                    .trParams({
                                                      'name':
                                                          widget.channelName,
                                                    }),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.66),
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 11.5,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _ResumeCountdownBadge(
                                          seconds: _secondsLeft,
                                          accent: accent,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FocusTraversalOrder(
                                            order: const NumericFocusOrder(1),
                                            child: _ResumeToastActionButton(
                                              focusNode: _continueFocus,
                                              focused: _continueFocused,
                                              autofocus: tv,
                                              label:
                                                  'last_channel_resume_continue'
                                                      .tr,
                                              icon: Icons.play_arrow_rounded,
                                              filled: true,
                                              accent: accent,
                                              onTap:
                                                  () => _finish(
                                                    widget.onContinue,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: FocusTraversalOrder(
                                            order: const NumericFocusOrder(2),
                                            child: _ResumeToastActionButton(
                                              focusNode: _closeFocus,
                                              focused: _closeFocused,
                                              label:
                                                  'last_channel_resume_dismiss'
                                                      .tr,
                                              icon: Icons.close_rounded,
                                              filled: false,
                                              accent: accent,
                                              onTap:
                                                  () =>
                                                      _finish(widget.onClose),
                                            ),
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
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResumeCountdownBadge extends StatelessWidget {
  const _ResumeCountdownBadge({
    required this.seconds,
    required this.accent,
  });

  final int seconds;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
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
          fontSize: 11.5,
          height: 1,
        ),
      ),
    );
  }
}

class _ResumeChannelLogo extends StatelessWidget {
  const _ResumeChannelLogo({
    required this.logoUrl,
    required this.accent,
  });

  final String? logoUrl;
  final Color accent;

  Widget _fallback() {
    return Icon(Icons.live_tv_rounded, color: accent, size: 18);
  }

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim() ?? '';
    final hasUrl =
        url.isNotEmpty &&
        (url.startsWith('http://') || url.startsWith('https://'));

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.28),
            accent.withValues(alpha: 0.1),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          hasUrl
              ? Image.network(
                url,
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(child: _fallback()),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(child: _fallback());
                },
              )
              : Center(child: _fallback()),
    );
  }
}

class _ResumeToastActionButton extends StatelessWidget {
  const _ResumeToastActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.accent,
    required this.onTap,
    required this.focusNode,
    required this.focused,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final Color accent;
  final VoidCallback onTap;
  final FocusNode focusNode;
  final bool focused;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            onTap();
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: focusNode,
        autofocus: autofocus,
        onKeyEvent: tv
            ? (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.numpadEnter ||
                    key == LogicalKeyboardKey.space) {
                  onTap();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              }
            : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color:
                    filled
                        ? accent.withValues(alpha: focused ? 1 : 0.9)
                        : Colors.white.withValues(alpha: focused ? 0.12 : 0.06),
                border: Border.all(
                  color:
                      focused
                          ? Colors.white.withValues(alpha: 0.85)
                          : filled
                          ? accent.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.12),
                  width: focused ? 1.6 : 1,
                ),
                boxShadow:
                    focused
                        ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: -1,
                          ),
                        ]
                        : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: filled ? Colors.white : Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: filled ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showBlockDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? appName,
}) async {
  final displayMessage = appName != null
      ? message
          .replaceAll('{app_name}', '')
          .trim()
          .replaceAll(RegExp(r':\s*$'), '')
      : message;

  await Get.dialog(
    Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1C1C24), Color(0xFF121218)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFFF6B6B).withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF6B6B).withValues(alpha: 0.14),
                border: Border.all(
                  color: const Color(0xFFFF6B6B).withValues(alpha: 0.45),
                ),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFFF6B6B),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Get.textTheme.titleLarge!.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              displayMessage,
              textAlign: TextAlign.center,
              style: Get.textTheme.bodyMedium!.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
                height: 1.4,
              ),
            ),
            if (appName != null && appName.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                appName,
                textAlign: TextAlign.center,
                style: Get.textTheme.titleMedium!.copyWith(
                  color: const Color(0xFFFF6B6B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Get.back(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ),
                child: Text(
                  'back'.tr,
                  style: Get.textTheme.bodyMedium!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    barrierDismissible: false,
  );
}
