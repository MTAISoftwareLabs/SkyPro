part of '../screens.dart';

class HomeBootstrapScreen extends StatefulWidget {
  const HomeBootstrapScreen({super.key});

  @override
  State<HomeBootstrapScreen> createState() => _HomeBootstrapScreenState();
}

class _HomeBootstrapScreenState extends State<HomeBootstrapScreen>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        HomeLandscapeLockMixin {
  late final AnimationController _fadeOutController;
  late final ValueNotifier<double> _progress;
  bool _bootstrapStarted = false;
  bool _leftNotified = false;
  bool _leaveRequested = false;
  Timer? _leaveWatchdog;
  ChannelsBloc? _channels;
  LiveCatyBloc? _liveCaty;
  MovieCatyBloc? _movieCaty;
  SeriesCatyBloc? _seriesCaty;
  bool _isDemo = false;

  @override
  void initState() {
    unawaited(lockHomeScreenLandscape());
    super.initState();
    unawaited(AppUpdateService.instance.prefetchAtLaunch());
    _progress = ValueNotifier<double>(0);
    _progress.addListener(_onProgress);
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleBootstrapStart();
    });
  }

  void _scheduleBootstrapStart() {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;

    // إطاران للـ spinner ثم التحميل — بدون تأخير زمني إضافي.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_startBootstrap());
      });
    });
  }

  void _onProgress() {
    if (_progress.value < 0.999) return;
    // 100% = البيانات واجدة. الخروج هنا، بلا ما نستناو fade ولا استكمال الـ future.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openHomeNow());
  }

  @override
  void dispose() {
    _leaveWatchdog?.cancel();
    _fadeOutController.dispose();
    _progress.removeListener(_onProgress);
    _progress.dispose();
    super.dispose();
  }

  Future<void> _startBootstrap() async {
    if (!mounted) return;
    _isDemo = context.read<SettingsCubit>().state.isDemo;
    _channels = context.read<ChannelsBloc>();
    _liveCaty = context.read<LiveCatyBloc>();
    _movieCaty = context.read<MovieCatyBloc>();
    _seriesCaty = context.read<SeriesCatyBloc>();

    // سقف مطلق: حتى لو التحميل ما رجّعش، ما نبقاوش على الدائرة.
    _armLeaveWatchdog(const Duration(seconds: 36));

    await HomeBootstrapLoader.run(
      context,
      isDemo: _isDemo,
      progress: _progress,
    );
    _progress.value = 1;
    _openHomeNow();
  }

  /// البيانات سالاو (أو السقف تزاد). الخروج فوري بلا fade — الأنيميشن هو اللي كيخلّي 100% عالقة.
  void _openHomeNow() {
    if (Get.currentRoute == screenWelcome) {
      _leaveWatchdog?.cancel();
      _notifyLeftAfterPaint();
      return;
    }
    if (_leaveRequested) return;
    _leaveRequested = true;
    _forceReplaceWithHome(allowNavigatorFallback: false);
    _armLeaveWatchdog(const Duration(milliseconds: 280));
    _notifyLeftAfterPaint();
  }

  void _armLeaveWatchdog(Duration firstDelay) {
    _leaveWatchdog?.cancel();
    var attempts = 0;
    _leaveWatchdog = Timer(firstDelay, () {
      _leaveWatchdog = Timer.periodic(const Duration(milliseconds: 350), (t) {
        attempts++;
        if (Get.currentRoute == screenWelcome) {
          t.cancel();
          return;
        }
        _forceReplaceWithHome(allowNavigatorFallback: true);
        if (attempts >= 10) t.cancel();
      });
      if (Get.currentRoute != screenWelcome) {
        _forceReplaceWithHome(allowNavigatorFallback: true);
      }
    });
  }

  void _forceReplaceWithHome({required bool allowNavigatorFallback}) {
    if (Get.currentRoute == screenWelcome) return;
    try {
      Get.offAll(
        () => const WelcomeScreen(),
        routeName: screenWelcome,
        transition: Transition.noTransition,
        duration: Duration.zero,
      );
    } catch (_) {}
    if (!allowNavigatorFallback || Get.currentRoute == screenWelcome) return;

    final nav = Get.key.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: screenWelcome),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const WelcomeScreen(),
      ),
      (_) => false,
    );
  }

  void _notifyLeftAfterPaint() {
    if (_leftNotified || _isDemo) return;
    final channels = _channels;
    final liveCaty = _liveCaty;
    final movieCaty = _movieCaty;
    final seriesCaty = _seriesCaty;
    if (channels == null ||
        liveCaty == null ||
        movieCaty == null ||
        seriesCaty == null) {
      return;
    }
    _leftNotified = true;
    // بعد أول إطار ديال Home، باش الشغل الثقيل ما يحبسش تبديل الصفحة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (Get.currentRoute != screenWelcome) {
          _leftNotified = false;
          return;
        }
        HomeBootstrapLoader.onLeftLoadingScreen(
          channels: channels,
          liveCaty: liveCaty,
          movieCaty: movieCaty,
          seriesCaty: seriesCaty,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF05070D),
        body: Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0).animate(
                CurvedAnimation(
                  parent: _fadeOutController,
                  curve: Curves.easeOut,
                ),
              ),
              child: const _BootstrapBackground(),
            ),
            Center(
              child: RepaintBoundary(
                child: _BootstrapLoadingIndicator(progress: _progress),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// خلفية ثابتة — لا setState أثناء التحميل.
class _BootstrapBackground extends StatelessWidget {
  const _BootstrapBackground();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.5);
    final cacheW = (mq.width * dpr).round().clamp(480, 960);
    final cacheH = (mq.height * dpr).round().clamp(270, 540);

    return Image.asset(
      kLoadingBackground,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: cacheW,
      cacheHeight: cacheH,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) =>
          const ColoredBox(color: Color(0xFF05070D)),
    );
  }
}

/// دائرة دوّارة كما السابق + نسبة مئوية مستقلة تحتها.
class _BootstrapLoadingIndicator extends StatefulWidget {
  const _BootstrapLoadingIndicator({required this.progress});

  final ValueNotifier<double> progress;

  @override
  State<_BootstrapLoadingIndicator> createState() =>
      _BootstrapLoadingIndicatorState();
}

class _BootstrapLoadingIndicatorState extends State<_BootstrapLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final ValueNotifier<double> _angle;

  /// خطوة ثابتة لكل إطار (~دورة كل 1.6 ث عند 60fps) — بلا لحاق بعد التجمّد.
  static const _step = 0.06544984694978735;

  @override
  void initState() {
    super.initState();
    _angle = ValueNotifier<double>(0);
    _ticker = createTicker((_) {
      var a = _angle.value + _step;
      if (a >= 6.283185307179586) a -= 6.283185307179586;
      _angle.value = a;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringSize =
        (MediaQuery.sizeOf(context).height * 0.17).clamp(96.0, 132.0);
    final logoSize = ringSize * 0.44;

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RepaintBoundary(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _angle,
                    builder: (context, angle, child) {
                      return Transform.rotate(
                        angle: angle,
                        child: child,
                      );
                    },
                    child: CustomPaint(
                      size: Size(ringSize, ringSize),
                      painter: _BootstrapRingPainter(),
                      isComplex: false,
                      willChange: true,
                    ),
                  ),
                ),
                Image.asset(
                  kIconSplash,
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  cacheWidth: (logoSize * 2).round(),
                  cacheHeight: (logoSize * 2).round(),
                ),
              ],
            ),
          ),
          SizedBox(height: ringSize * 0.18),
          ValueListenableBuilder<double>(
            valueListenable: widget.progress,
            builder: (context, value, _) {
              return TweenAnimationBuilder<double>(
                tween: Tween<double>(end: value.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, animated, _) {
                  final pct = (animated * 100).round().clamp(0, 100);
                  return Text(
                    '$pct%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (ringSize * 0.18).clamp(16.0, 24.0),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      height: 1,
                      shadows: const [
                        Shadow(color: Color(0xCC000000), blurRadius: 10),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          SizedBox(height: ringSize * 0.16),
          Text(
            'home_bootstrap_title'.tr,
            style: Get.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              shadows: const [
                Shadow(color: Color(0xAA000000), blurRadius: 8),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: (ringSize * 1.55).clamp(160.0, 220.0),
            child: ValueListenableBuilder<double>(
              valueListenable: widget.progress,
              builder: (context, value, _) {
                return TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: value.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (context, animated, _) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 4,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: Color(0x33FFFFFF)),
                            FractionallySizedBox(
                              alignment: AlignmentDirectional.centerStart,
                              widthFactor: animated,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF38BDF8),
                                      Color(0xFF6366F1),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'home_bootstrap_subtitle'.tr,
            style: Get.textTheme.bodySmall?.copyWith(
              color: const Color(0xCCFFFFFF),
              shadows: const [
                Shadow(color: Color(0x88000000), blurRadius: 6),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BootstrapRingPainter extends CustomPainter {
  _BootstrapRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final radius = size.width * 0.5 - 4;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x33FFFFFF)
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = kColorPrimary
      ..isAntiAlias = true;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5707963267948966,
      2.15,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _BootstrapRingPainter oldDelegate) => false;
}
