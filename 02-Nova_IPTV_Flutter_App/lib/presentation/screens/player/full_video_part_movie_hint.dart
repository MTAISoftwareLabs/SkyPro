part of '../screens.dart';

// ---------------------------------------------------------------------------
// تلميح فتح قائمة الأفلام/الحلقات – يظهر مرة واحدة فقط
// هاتف: اسحب من الأسفل إلى الأعلى | تلفاز/ريموت: اضغط سهم الأسفل
// ---------------------------------------------------------------------------
class _MovieDownHintWidget extends StatefulWidget {
  const _MovieDownHintWidget({
    required this.onDismiss,
    this.forEpisodes = false,
    this.forLive = false,
  });
  final VoidCallback onDismiss;
  final bool forEpisodes;
  final bool forLive;

  @override
  State<_MovieDownHintWidget> createState() => _MovieDownHintWidgetState();
}

class _MovieDownHintWidgetState extends State<_MovieDownHintWidget>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _bounceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _bounceAnim;

  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();

    // fade in/out
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _fadeCtrl.forward();

    // bounce للسهم والأيقونة
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _bounceAnim = Tween<double>(
      begin: 0,
      end: 8,
    ).animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeInOut));

    // إخفاء بعد 5 ثوانٍ - مع إمكانية الإلغاء عند dispose
    _dismissTimer = Timer(const Duration(milliseconds: 4400), () {
      if (mounted) {
        _fadeCtrl.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _fadeCtrl.dispose();
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = !isTvDevice(context);
    final titleKey = widget.forLive
        ? (phone ? 'live_hint_title_phone' : 'live_hint_title')
        : widget.forEpisodes
        ? (phone ? 'episode_hint_title_phone' : 'episode_hint_title')
        : (phone ? 'movie_hint_title_phone' : 'movie_hint_title');
    final descKey = widget.forLive
        ? 'live_hint_desc'
        : widget.forEpisodes
        ? 'episode_hint_desc'
        : 'movie_hint_desc';
    final leadIcon =
        phone ? Icons.swipe_up_alt_rounded : Icons.keyboard_arrow_down_rounded;

    return wrapAppDirectionality(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.75),
                  Colors.black.withValues(alpha: 0.60),
                ],
              ),
              border: Border.all(
                color: kColorPrimary.withValues(alpha: 0.45),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: kColorPrimary.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _bounceAnim,
                  builder: (_, _) {
                    return Transform.translate(
                      offset: Offset(0, _bounceAnim.value),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kColorPrimary.withValues(alpha: 0.18),
                        ),
                        child: Icon(
                          leadIcon,
                          color: kColorPrimary,
                          size: phone ? 26 : 30,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleKey.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        descKey.tr,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                AnimatedBuilder(
                  animation: _bounceAnim,
                  builder: (_, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final opacity = ((_bounceAnim.value / 8) * (i + 1) / 3)
                            .clamp(0.2, 1.0);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: kColorPrimary.withValues(alpha: opacity),
                            size: 14 - i * 2.0,
                          ),
                        );
                      }),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
