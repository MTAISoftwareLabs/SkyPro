part of '../screens.dart';

/// توست مفضلة احترافي — مستطيل ضيق في وسط الشاشة.
class _FavCenterToast extends StatefulWidget {
  const _FavCenterToast({
    required this.isAdd,
    required this.title,
    required this.message,
    required this.categoryLabel,
    required this.onDismissed,
  });

  final bool isAdd;
  final String title;
  final String message;
  final String categoryLabel;
  final VoidCallback onDismissed;

  @override
  State<_FavCenterToast> createState() => _FavCenterToastState();
}

class _FavCenterToastState extends State<_FavCenterToast>
    with SingleTickerProviderStateMixin {
  static const int _enterMs = 320;
  static const int _holdMs = 1500;
  static const int _exitMs = 360;

  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<double> _slideX;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _messageOpacity;
  late final Animation<double> _categoryOpacity;

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

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.94,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: wEnter,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: wHold),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0.97,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: wExit,
      ),
    ]).animate(_controller);

    _slideX = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 28,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: wEnter,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: wHold),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -18,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: wExit,
      ),
    ]).animate(_controller);

    _titleOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.06, 0.24, curve: Curves.easeOut),
      reverseCurve: const Interval(0.76, 0.94, curve: Curves.easeIn),
    );

    _messageOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.14, 0.32, curve: Curves.easeOut),
      reverseCurve: const Interval(0.7, 0.88, curve: Curves.easeIn),
    );

    _categoryOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.38, curve: Curves.easeOut),
      reverseCurve: const Interval(0.66, 0.84, curve: Curves.easeIn),
    );

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
    final isAdd = widget.isAdd;
    final accent =
        isAdd ? const Color(0xFFE50914) : const Color(0xFF94A3B8);
    final icon =
        isAdd ? FontAwesomeIcons.solidHeart : FontAwesomeIcons.heart;
    final showCategory = widget.categoryLabel.trim().isNotEmpty;

    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final titleAlpha = _titleOpacity.value.clamp(0.0, 1.0);
            final messageAlpha = _messageOpacity.value.clamp(0.0, 1.0);
            final categoryAlpha = _categoryOpacity.value.clamp(0.0, 1.0);

            return Opacity(
              opacity: _opacity.value.clamp(0.0, 1.0),
              child: Center(
                child: Transform.translate(
                  offset: Offset(_slideX.value, 0),
                  child: Transform.scale(
                    scale: _scale.value.clamp(0.9, 1.02),
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: 78.w.clamp(280.0, 460.0),
                        minWidth: 260,
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withValues(alpha: 0.9),
                            Colors.black.withValues(alpha: 0.78),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.18),
                            blurRadius: 18,
                            spreadRadius: 0.5,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Icon(icon, color: accent, size: 17),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Opacity(
                                  opacity: titleAlpha,
                                  child: Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5.sp,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Opacity(
                                  opacity: messageAlpha,
                                  child: Text(
                                    widget.message,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.86,
                                      ),
                                      fontSize: 11.sp,
                                      fontWeight: FontWeight.w500,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                                if (showCategory) ...[
                                  const SizedBox(height: 3),
                                  Opacity(
                                    opacity: categoryAlpha,
                                    child: Text(
                                      widget.categoryLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: accent.withValues(alpha: 0.95),
                                        fontSize: 10.sp,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
