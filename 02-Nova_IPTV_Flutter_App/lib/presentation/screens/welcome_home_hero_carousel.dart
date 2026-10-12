part of 'screens.dart';

/// لون التمييز للهيرو = لون الثيم النشط (ماشي أزرق ثابت).
Color get _kHeroAccent => kColorPrimary;
const Color _kHeroNavy = Color(0xFF0A0E1A);
const Duration _kHeroAutoInterval = Duration(seconds: 5);
const Duration _kHeroAnimDuration = Duration(milliseconds: 650);

/// بانر هيرو بأسلوب OTT — فوق صفوف الرئيسية (TV + موبايل).
class _HomeHeroCarousel extends StatefulWidget {
  const _HomeHeroCarousel({
    required this.movies,
    required this.series,
    required this.serverUrl,
    required this.tvFocusRow,
    required this.height,
    this.isDemo = false,
    this.onDemoTap,
    this.autofocusWatch = true,
  });

  final List<ChannelMovie> movies;
  final List<ChannelSerie> series;
  final String? serverUrl;
  final int tvFocusRow;
  final double height;
  final bool isDemo;
  final VoidCallback? onDemoTap;
  final bool autofocusWatch;

  @override
  State<_HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<_HomeHeroCarousel>
    with WidgetsBindingObserver {
  Timer? _autoTimer;
  int _index = 0;
  bool _loading = true;
  bool _paused = false;
  bool _watchBusy = false;
  List<HomeHeroSlide> _slides = const [];
  final GlobalKey _heroAnchorKey = GlobalKey(debugLabel: 'tv_home_hero');

  late final FocusNode _watchFocus;
  late final FocusNode _moreFocus;
  String _parentalFp = '';

  List<CategoryModel> _movieCategories() {
    final st = context.read<MovieCatyBloc>().state;
    return st is MovieCatySuccess ? st.categories : const <CategoryModel>[];
  }

  List<CategoryModel> _seriesCategories() {
    final st = context.read<SeriesCatyBloc>().state;
    return st is SeriesCatySuccess ? st.categories : const <CategoryModel>[];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _parentalFp = ParentalControlService.instance.homeSurfaceFingerprint();
    _watchFocus = FocusNode(
      debugLabel: _stvPosterLabel(widget.tvFocusRow, 0),
    );
    _moreFocus = FocusNode(
      debugLabel: _stvPosterLabel(widget.tvFocusRow, 1),
    );
    _stvBindFocusLabel(_watchFocus, _stvPosterLabel(widget.tvFocusRow, 0));
    _stvBindFocusLabel(_moreFocus, _stvPosterLabel(widget.tvFocusRow, 1));
    _hydrateFromCacheOrInstant();
    unawaited(_loadSlides(enrichOnly: _slides.isNotEmpty));
  }

  /// من bootstrap أو بوستر فوري — بلا شاشة فارغة.
  void _hydrateFromCacheOrInstant() {
    final movieCats = _movieCategories();
    final seriesCats = _seriesCategories();
    final cached = HomeHeroCache.takeIfMatches(
      movies: widget.movies,
      series: widget.series,
      serverUrl: widget.serverUrl,
      movieCategories: movieCats,
      seriesCategories: seriesCats,
    );
    if (cached != null && cached.isNotEmpty) {
      _slides = cached;
      _loading = false;
      return;
    }
    final instant = HomeHeroCache.buildInstant(
      movies: widget.movies,
      series: widget.series,
      serverUrl: widget.serverUrl,
      isDemo: widget.isDemo,
      movieCategories: movieCats,
      seriesCategories: seriesCats,
    );
    if (instant.isNotEmpty) {
      _slides = instant;
      _loading = false;
    } else {
      _slides = const [];
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant _HomeHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tvFocusRow != widget.tvFocusRow) {
      _stvBindFocusLabel(_watchFocus, _stvPosterLabel(widget.tvFocusRow, 0));
      _stvBindFocusLabel(_moreFocus, _stvPosterLabel(widget.tvFocusRow, 1));
    }
    final sameMovies = identical(oldWidget.movies, widget.movies) ||
        (oldWidget.movies.length == widget.movies.length &&
            oldWidget.movies.every(
              (m) => widget.movies.any((n) => n.streamId == m.streamId),
            ));
    final sameSeries = identical(oldWidget.series, widget.series) ||
        (oldWidget.series.length == widget.series.length &&
            oldWidget.series.every(
              (s) => widget.series.any((n) => n.seriesId == s.seriesId),
            ));
    if (!sameMovies ||
        !sameSeries ||
        oldWidget.serverUrl != widget.serverUrl ||
        oldWidget.isDemo != widget.isDemo ||
        ParentalControlService.instance.homeSurfaceFingerprint() !=
            _parentalFp) {
      _parentalFp =
          ParentalControlService.instance.homeSurfaceFingerprint();
      _hydrateFromCacheOrInstant();
      unawaited(_loadSlides(enrichOnly: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAuto();
    _stvBindFocusLabel(_watchFocus, null);
    _stvBindFocusLabel(_moreFocus, null);
    _watchFocus.dispose();
    _moreFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeAuto();
    } else {
      _pauseAuto();
    }
  }

  void _pauseAuto() {
    _paused = true;
    _stopAuto();
  }

  void _resumeAuto() {
    _paused = false;
    _armAuto();
  }

  void _stopAuto() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  void _armAuto() {
    _stopAuto();
    if (!mounted || _paused || _slides.length < 2) return;
    _autoTimer = Timer.periodic(_kHeroAutoInterval, (_) {
      if (!mounted || _paused || _slides.length < 2) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      final next = (_index + 1) % _slides.length;
      _goTo(next, animate: true);
    });
  }

  void _goTo(int i, {required bool animate}) {
    if (!mounted || _slides.isEmpty) return;
    final target = i.clamp(0, _slides.length - 1);
    if (target == _index) return;
    setState(() => _index = target);
    final slide = _slides[target];
    if (slide.isPromo && _watchFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moreFocus.requestFocus();
      });
    }
  }

  void _prev() {
    if (_slides.length < 2) return;
    final next = (_index - 1 + _slides.length) % _slides.length;
    _goTo(next, animate: true);
    _armAuto();
  }

  void _next() {
    if (_slides.length < 2) return;
    final next = (_index + 1) % _slides.length;
    _goTo(next, animate: true);
    _armAuto();
  }

  void _ensureHeroVisible() {
    final ctx = _heroAnchorKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.0,
      duration: kTvEnsureVisibleDuration,
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadSlides({required bool enrichOnly}) async {
    final hasPromo = HomeHeroPanel.hasPromoSlide;
    if (widget.movies.isEmpty && widget.series.isEmpty && !hasPromo) {
      if (!mounted) return;
      setState(() {
        _slides = const [];
        _loading = false;
        _index = 0;
      });
      _stopAuto();
      return;
    }

    if (enrichOnly) {
      final cached = HomeHeroCache.takeIfMatches(
        movies: widget.movies,
        series: widget.series,
        serverUrl: widget.serverUrl,
        movieCategories: _movieCategories(),
        seriesCategories: _seriesCategories(),
      );
      if (cached != null && cached.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _slides = cached;
          _loading = false;
        });
        _armAuto();
        final warm = cached
            .map((s) => s.imageUrl)
            .where((u) => u.isNotEmpty)
            .take(3)
            .toList();
        if (warm.isNotEmpty) {
          unawaited(precacheIptvPosters(context, warm));
        }
        return;
      }
    }

    if (!enrichOnly && _slides.isEmpty && mounted) {
      setState(() => _loading = true);
    }

    try {
      final built = await HomeHeroCache.buildFull(
        movies: widget.movies,
        series: widget.series,
        prefetch: context.read<PrefetchCubit>(),
        serverUrl: widget.serverUrl,
        isDemo: widget.isDemo,
        movieCategories: _movieCategories(),
        seriesCategories: _seriesCategories(),
      );
      if (!mounted) return;
      setState(() {
        _slides = built;
        _loading = false;
        if (_index >= built.length) _index = 0;
      });
      _armAuto();
      final warm = built
          .map((s) => s.imageUrl)
          .where((u) => u.isNotEmpty)
          .take(3)
          .toList();
      if (warm.isNotEmpty) {
        unawaited(precacheIptvPosters(context, warm));
      }
    } catch (_) {
      if (!mounted) return;
      if (_slides.isEmpty) {
        final instant = HomeHeroCache.buildInstant(
          movies: widget.movies,
          series: widget.series,
          serverUrl: widget.serverUrl,
          isDemo: widget.isDemo,
          movieCategories: _movieCategories(),
          seriesCategories: _seriesCategories(),
        );
        setState(() {
          _slides = instant;
          _loading = false;
        });
        _armAuto();
      }
    }
  }

  void _openMoreInfo(HomeHeroSlide slide) {
    if (widget.isDemo) {
      widget.onDemoTap?.call();
      return;
    }
    if (slide.isPromo) {
      unawaited(_openPromoLink(slide));
      return;
    }
    unawaited(_openSlideProtected(slide, watchMovie: false));
  }

  Future<void> _openPromoLink(HomeHeroSlide slide) async {
    final raw = (slide.linkUrl ?? '').trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _watchNow(HomeHeroSlide slide) async {
    if (slide.isPromo) {
      await _openPromoLink(slide);
      return;
    }
    if (widget.isDemo) {
      widget.onDemoTap?.call();
      return;
    }
    if (slide.isSeries) {
      await _openSlideProtected(slide, watchMovie: false);
      return;
    }
    await _openSlideProtected(slide, watchMovie: true);
  }

  Future<void> _openSlideProtected(
    HomeHeroSlide slide, {
    required bool watchMovie,
  }) async {
    final parental = ParentalControlService.instance;
    final section =
        slide.isSeries ? ParentalSection.series : ParentalSection.movies;
    if (!await parental.requestSectionAccess(context, section)) return;
    if (!mounted) return;

    if (slide.isSeries) {
      final model = slide.serie;
      if (model == null) return;
      if (parental.isAdultSerie(
        model,
        categoryName: ParentalControlService.categoryNameFromId(
          model.categoryId,
          _seriesCategories(),
        ),
      )) {
        final ok = await parental.requestAdultContentAccess(context);
        if (!ok || !mounted) return;
      }
      final id = model.seriesId ?? '';
      if (id.isNotEmpty) {
        context.read<PrefetchCubit>().getSerieDetailCached(id);
      }
      await Get.to(
        () => SerieContent(channelSerie: model, videoId: id),
      );
      return;
    }

    final model = slide.movie;
    if (model == null) return;
    if (parental.isAdultMovie(
      model,
      categoryName: ParentalControlService.categoryNameFromId(
        model.categoryId,
        _movieCategories(),
      ),
    )) {
      final ok = await parental.requestAdultContentAccess(context);
      if (!ok || !mounted) return;
    }
    if (!watchMovie) {
      final id = model.streamId ?? '';
      if (id.isNotEmpty) {
        context.read<PrefetchCubit>().getMovieDetailCached(id);
      }
      await Get.to(
        () => MovieContent(channelMovie: model, videoId: id),
      );
      return;
    }

    if (_watchBusy) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthSuccess) return;
    final userAuth = authState.user;
    final id = validIptvContentId(model.streamId);
    if (id == null) return;

    setState(() => _watchBusy = true);
    try {
      final detail =
          await context.read<PrefetchCubit>().getMovieDetailCached(id);
      if (!mounted) return;
      final sid = detail?.movieData?.streamId?.toString() ??
          model.streamId?.toString() ??
          '';
      String link;
      if (sid.startsWith('http://') || sid.startsWith('https://')) {
        link = sid;
      } else {
        final chSid = model.streamId?.toString() ?? '';
        if (chSid.startsWith('http://') || chSid.startsWith('https://')) {
          link = chSid;
        } else {
          final ext = detail?.movieData?.containerExtension ??
              model.containerExtension ??
              'mp4';
          link =
              "${userAuth.serverInfo!.serverUrl}/movie/${userAuth.userInfo!.username}/${userAuth.userInfo!.password}/$sid.$ext";
        }
      }

      final streamId = model.streamId.toString();
      WatchingModel? saved;
      for (final w in context.read<WatchingCubit>().state.movies) {
        if (w.streamId == streamId) {
          saved = w;
          break;
        }
      }
      final resumeSec =
          (saved != null && saved.sliderValue > 0) ? saved.sliderValue : null;

      if (!mounted) return;
      await Get.to(
        () => FullVideoScreen(
          link: link,
          title: detail?.movieData?.name ?? model.name ?? '',
          channelMovie: model,
          initialPositionSeconds: resumeSec,
        ),
      )?.then((slider) {
        unawaited(AdsService.showInterstitialIfReady());
        if (!mounted) return;
        if (!watchingPopMatchesOpenedStream(slider, streamId)) return;
        if (slider is! List || slider.length < 2) return;
        final updated = WatchingModel(
          sliderValue: (slider[0] as num).toDouble(),
          durationStrm: (slider[1] as num).toDouble(),
          stream: link,
          title: model.name ?? '',
          image: model.streamIcon ?? '',
          streamId: streamId,
          rating: model.rating,
          rating5based: model.rating5based,
          categoryId: model.categoryId,
        );
        context.read<WatchingCubit>().addMovie(updated);
      });
    } finally {
      if (mounted) setState(() => _watchBusy = false);
    }
  }

  KeyEventResult _onHeroActionKey(
    FocusNode node,
    KeyEvent event, {
    required bool isWatch,
    required VoidCallback onActivate,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final slide =
        _slides.isEmpty ? null : _slides[_index.clamp(0, _slides.length - 1)];
    final promoOnly = slide?.isPromo == true;

    // إعلان الهيرو: زر واحد — يسار/يمين يقلبان الشرائح.
    if (promoOnly) {
      if (key == LogicalKeyboardKey.arrowLeft && _slides.length > 1) {
        _prev();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight && _slides.length > 1) {
        _next();
        return KeyEventResult.handled;
      }
      return _homeRowHorizontalKey(
        node,
        event,
        isFirstInRow: true,
        isLastInRow: true,
        onActivate: onActivate,
      );
    }

    if (key == LogicalKeyboardKey.arrowLeft && isWatch) {
      if (_slides.length > 1) {
        _prev();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowRight && !isWatch) {
      if (_slides.length > 1) {
        _next();
        return KeyEventResult.handled;
      }
    }
    return _homeRowHorizontalKey(
      node,
      event,
      isFirstInRow: isWatch,
      isLastInRow: !isWatch,
      onActivate: onActivate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final parentalNow =
        ParentalControlService.instance.homeSurfaceFingerprint();
    if (parentalNow != _parentalFp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ParentalControlService.instance.homeSurfaceFingerprint() ==
            _parentalFp) {
          return;
        }
        _parentalFp =
            ParentalControlService.instance.homeSurfaceFingerprint();
        _hydrateFromCacheOrInstant();
        unawaited(_loadSlides(enrichOnly: false));
        setState(() {});
      });
    }

    if (_loading && _slides.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF121826),
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      );
    }
    if (_slides.isEmpty) {
      return const SizedBox.shrink();
    }

    final slide = _slides[_index.clamp(0, _slides.length - 1)];

    return SizedBox(
      key: _heroAnchorKey,
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: MouseRegion(
          onEnter: (_) => _pauseAuto(),
          onExit: (_) => _resumeAuto(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v <= -180) {
                _next();
              } else if (v >= 180) {
                _prev();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: _kHeroNavy),
                AnimatedSwitcher(
                  duration: _kHeroAnimDuration,
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ...previousChildren,
                        ?currentChild,
                      ],
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_index),
                    child: _HeroBackdrop(imageUrl: slide.imageUrl),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xF2000A12),
                        Color(0xCC0A0E1A),
                        Color(0x660A0E1A),
                        Color(0x140A0E1A),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.28, 0.48, 0.68, 1.0],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color(0x990A0E1A),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.45],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isTv(context) ? 28 : 16,
                      isTv(context) ? 20 : 14,
                      isTv(context) ? 72 : 48,
                      isTv(context) ? 22 : 14,
                    ),
                    child: _HeroSlideOverlay(
                      slide: slide,
                      watchFocus: _watchFocus,
                      moreFocus: _moreFocus,
                      autofocusWatch:
                          widget.autofocusWatch &&
                          !slide.isPromo &&
                          isTv(context),
                      busy: _watchBusy,
                      onFocused: _ensureHeroVisible,
                      onWatchKey: (n, e) => _onHeroActionKey(
                        n,
                        e,
                        isWatch: true,
                        onActivate: () => unawaited(_watchNow(slide)),
                      ),
                      onMoreKey: (n, e) => _onHeroActionKey(
                        n,
                        e,
                        isWatch: false,
                        onActivate: () => _openMoreInfo(slide),
                      ),
                      onWatch: () => unawaited(_watchNow(slide)),
                      onMore: () => _openMoreInfo(slide),
                    ),
                  ),
                ),
                if (_slides.length > 1) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: _HeroNavArrow(
                        icon: Icons.chevron_left_rounded,
                        onTap: _prev,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _HeroNavArrow(
                        icon: Icons.chevron_right_rounded,
                        onTap: _next,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 22,
                    bottom: 16,
                    child: _HeroDots(
                      count: _slides.length,
                      index: _index,
                      onTap: (i) {
                        _goTo(i, animate: true);
                        _armAuto();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const ColoredBox(color: _kHeroNavy);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final lw = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 1280.0;
        final lh = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : 420.0;
        final mem = iptvMemCachePx(context, lw, lh);
        return SizedBox.expand(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            cacheManager: iptvImageCacheManager,
            memCacheWidth: mem.$1,
            memCacheHeight: mem.$2,
            filterQuality: AppPerf.instance.useLowFilterQuality
                ? FilterQuality.low
                : FilterQuality.medium,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: const Alignment(0.15, 0),
            fadeInDuration: const Duration(milliseconds: 180),
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
            useOldImageOnUrlChange: true,
            placeholder: (_, _) => const ColoredBox(color: Color(0xFF121826)),
            errorWidget: (_, _, _) => const ColoredBox(color: _kHeroNavy),
          ),
        );
      },
    );
  }
}

class _HeroSlideOverlay extends StatelessWidget {
  const _HeroSlideOverlay({
    required this.slide,
    required this.watchFocus,
    required this.moreFocus,
    required this.autofocusWatch,
    required this.busy,
    required this.onWatchKey,
    required this.onMoreKey,
    required this.onWatch,
    required this.onMore,
    required this.onFocused,
  });

  final HomeHeroSlide slide;
  final FocusNode watchFocus;
  final FocusNode moreFocus;
  final bool autofocusWatch;
  final bool busy;
  final KeyEventResult Function(FocusNode, KeyEvent) onWatchKey;
  final KeyEventResult Function(FocusNode, KeyEvent) onMoreKey;
  final VoidCallback onWatch;
  final VoidCallback onMore;
  final VoidCallback onFocused;

  @override
  Widget build(BuildContext context) {
    final rating = formatContentRating(slide.rating, slide.rating5based);
    final plot = (slide.plot ?? '').trim();
    final phone = !isTv(context);
    final titleSize = phone ? 26.0 : 34.0;
    final maxW = phone ? 420.0 : 560.0;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: Column(
                key: ValueKey<String>(slide.contentKey),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isBlankMeta(slide.tagline))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        slide.tagline!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: phone ? 11 : 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  Text(
                    slide.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: 0.2,
                      shadows: const [
                        Shadow(
                          color: Color(0x99000000),
                          blurRadius: 12,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: phone ? 8 : 10),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      if (rating != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFFC107),
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rating,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      if (slide.year != null)
                        Text(
                          '${slide.year}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      for (final g in slide.genres)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            g,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (plot.isNotEmpty) ...[
                    SizedBox(height: phone ? 8 : 12),
                    Text(
                      plot,
                      maxLines: phone ? 2 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: phone ? 13 : 14,
                        height: 1.35,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: phone ? 12 : 16),
            Row(
              children: [
                if (!slide.isPromo) ...[
                  _HeroActionButton(
                    focusNode: watchFocus,
                    autofocus: autofocusWatch,
                    label: 'watch_now'.tr,
                    primary: true,
                    busy: busy,
                    icon: Icons.play_arrow_rounded,
                    onKeyEvent: onWatchKey,
                    onTap: onWatch,
                    onFocused: onFocused,
                  ),
                  const SizedBox(width: 12),
                ],
                _HeroActionButton(
                  focusNode: moreFocus,
                  autofocus: slide.isPromo || !autofocusWatch,
                  label: 'more_info'.tr,
                  primary: slide.isPromo,
                  busy: false,
                  icon: Icons.info_outline_rounded,
                  onKeyEvent: onMoreKey,
                  onTap: onMore,
                  onFocused: onFocused,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroActionButton extends StatefulWidget {
  const _HeroActionButton({
    required this.focusNode,
    required this.autofocus,
    required this.label,
    required this.primary,
    required this.busy,
    required this.icon,
    required this.onKeyEvent,
    required this.onTap,
    required this.onFocused,
  });

  final FocusNode focusNode;
  final bool autofocus;
  final String label;
  final bool primary;
  final bool busy;
  final IconData icon;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback onTap;
  final VoidCallback onFocused;

  @override
  State<_HeroActionButton> createState() => _HeroActionButtonState();
}

class _HeroActionButtonState extends State<_HeroActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    final bg = widget.primary
        ? Colors.white
        : Colors.black.withValues(alpha: 0.45);
    final fg = widget.primary ? _kHeroAccent : Colors.white;
    final border = focused
        ? _kHeroAccent
        : (widget.primary
            ? Colors.transparent
            : Colors.white.withValues(alpha: 0.28));

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
        if (v) widget.onFocused();
      },
      onKeyEvent: widget.onKeyEvent,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.busy ? null : widget.onTap,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: kFocusAnimDuration,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border, width: focused ? 2.5 : 1),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: _kHeroAccent.withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  )
                else
                  Icon(widget.icon, size: 22, color: fg),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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

class _HeroNavArrow extends StatefulWidget {
  const _HeroNavArrow({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HeroNavArrow> createState() => _HeroNavArrowState();
}

class _HeroNavArrowState extends State<_HeroNavArrow> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
    return Focus(
      canRequestFocus: true,
      skipTraversal: true,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      onKeyEvent: (node, event) {
        return settingsTvActivateOnSelect(event, widget.onTap);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            canRequestFocus: false,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: kFocusAnimDuration,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: active ? 0.62 : 0.42),
                border: Border.all(
                  color: active
                      ? _kHeroAccent
                      : Colors.white.withValues(alpha: 0.28),
                  width: active ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroDots extends StatelessWidget {
  const _HeroDots({
    required this.count,
    required this.index,
    required this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == index;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: active ? 11 : 7,
              height: active ? 11 : 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? _kHeroAccent
                    : Colors.white.withValues(alpha: 0.28),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: _kHeroAccent.withValues(alpha: 0.45),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      }),
    );
  }
}
