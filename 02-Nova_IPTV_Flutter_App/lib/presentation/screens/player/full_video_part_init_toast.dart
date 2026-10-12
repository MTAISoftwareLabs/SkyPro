part of '../screens.dart';

class _PlayerInitToastLayer extends StatefulWidget {
  const _PlayerInitToastLayer({
    required this.text,
    required this.isExo,
    required this.onDismissed,
  });

  final String text;
  final bool isExo;
  final VoidCallback onDismissed;

  @override
  State<_PlayerInitToastLayer> createState() => _PlayerInitToastLayerState();
}

class _PlayerInitToastLayerState extends State<_PlayerInitToastLayer>
    with SingleTickerProviderStateMixin {
  static const int _enterMs = 380;
  static const int _holdMs = 1240;
  static const int _exitMs = 380;
  static int get _totalMs => _enterMs + _holdMs + _exitMs;

  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _dy;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _totalMs),
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
          begin: 22,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: wEnter,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: wHold),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -14,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: wExit,
      ),
    ]).animate(_controller);

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.94,
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
    try {
      _controller.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final o = _opacity.value.clamp(0.0, 1.0);
        final s = _scale.value.clamp(0.85, 1.05);
        return IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.center,
              child: Opacity(
                opacity: o,
                child: Transform.translate(
                  offset: Offset(0, _dy.value),
                  child: Transform.scale(scale: s, child: child),
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              spreadRadius: 1,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.isExo
                  ? FontAwesomeIcons.circlePlay
                  : FontAwesomeIcons.video,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Text(
              widget.text,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
