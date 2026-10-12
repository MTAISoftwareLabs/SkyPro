part of 'screens.dart';

class _HomePosterCard extends StatefulWidget {
  const _HomePosterCard({
    required this.title,
    required this.onTap,
    this.imageUrl = '',
    this.assetImage,
    this.rating,
    this.rating5based,
    this.contentKey,
    this.isSeries = false,
    this.showContentTypeBadge = false,
    this.autofocus = false,
    this.focusNode,
    this.isFirstInRow = false,
    this.isLastInRow = false,
    this.tvLarge = false,
    this.posterWidth,
    this.focusDebugLabel,
  });

  final String title;
  final String imageUrl;
  final String? assetImage;
  final String? rating;
  final String? rating5based;
  final String? contentKey;
  final bool isSeries;
  /// شارة حمراء أعلى اليمين: فيلم / مسلسل — لصف متابعة المشاهدة فقط.
  final bool showContentTypeBadge;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool isFirstInRow;
  final bool isLastInRow;
  /// واجهة تلفزيون بحجم Smart TV (بوستر كبير + فوكس الثيم + scale).
  final bool tvLarge;
  final double? posterWidth;
  /// تسمية فوكس Smart TV (`stv_poster_row_col`).
  final String? focusDebugLabel;

  @override
  State<_HomePosterCard> createState() => _HomePosterCardState();
}

class _HomePosterCardState extends State<_HomePosterCard> {
  bool _focused = false;
  FocusNode? _localFocus;

  FocusNode get _focusNode => widget.focusNode ?? _localFocus!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _localFocus = FocusNode(debugLabel: widget.focusDebugLabel);
    }
    _stvBindFocusLabel(_focusNode, widget.focusDebugLabel);
  }

  @override
  void didUpdateWidget(covariant _HomePosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode ||
        oldWidget.focusDebugLabel != widget.focusDebugLabel) {
      if (oldWidget.focusNode != null) {
        _stvBindFocusLabel(oldWidget.focusNode, null);
      }
      if (widget.focusNode == null && _localFocus == null) {
        _localFocus = FocusNode(debugLabel: widget.focusDebugLabel);
      }
      _stvBindFocusLabel(_focusNode, widget.focusDebugLabel);
    }
  }

  @override
  void dispose() {
    _stvBindFocusLabel(_focusNode, null);
    _localFocus?.dispose();
    super.dispose();
  }

  double? _homeWatchProgress(BuildContext context) {
    final key = widget.contentKey;
    if (key == null || key.isEmpty) return null;
    final idx = key.indexOf(':');
    final id =
        ((idx < 0 || idx >= key.length - 1) ? key : key.substring(idx + 1))
            .trim();
    if (id.isEmpty) return null;
    final watch = context.watch<WatchingCubit>().state;
    WatchingModel? match;
    if (widget.isSeries) {
      for (final w in watch.series) {
        if ((w.seriesId ?? '').trim() == id) {
          match = w;
          break;
        }
      }
    } else {
      for (final w in watch.movies) {
        if (w.streamId.trim() == id) {
          match = w;
          break;
        }
      }
    }
    if (match == null) return null;
    return watchProgressRatio(match.sliderValue, match.durationStrm);
  }

  @override
  Widget build(BuildContext context) {
    final watchProgress = _homeWatchProgress(context);
    final tvLarge = widget.tvLarge;
    final accent = kColorFocus;
    final radius = tvLarge ? 16.0 : _kHomePosterRadius;
    final width = widget.posterWidth ??
        (tvLarge ? 168.0 : 11.5.w.clamp(72.0, 110.0));
    final tvScale = MediaQuery.sizeOf(context).width / 1920.0;
    final titleSize = tvLarge ? 16.0 * tvScale : 12.sp;

    Widget card = Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
        if (v) {
          Scrollable.ensureVisible(
            context,
            // Smart TV يبقي الصف كاملاً مرئياً قدر الإمكان.
            alignment: tvLarge ? 0.2 : 0.5,
            duration: kTvEnsureVisibleDuration,
            curve: Curves.easeOut,
          );
        }
      },
      onKeyEvent: (node, event) => _homeRowHorizontalKey(
        node,
        event,
        isFirstInRow: widget.isFirstInRow,
        isLastInRow: widget.isLastInRow,
        onActivate: widget.onTap,
      ),
      child: InkWell(
        onTap: widget.onTap,
        canRequestFocus: false,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          height: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            // عرض ثابت حتى لا يقفز التخطيط عند الفوكس
            border: Border.all(
              color: _focused ? accent : Colors.transparent,
              width: tvLarge ? 2.0 : (_focused ? 2.4 : 0),
            ),
            boxShadow: !_focused
                ? null
                : [
                    // حلقة خارجية مثل Smart TV: 0 0 0 2px rgba(245,194,66,.45)
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 0,
                      spreadRadius: tvLarge ? 2.5 : 1.5,
                    ),
                    if (!kReduceFocusMotion && !tvLarge)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 8),
                      ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - (tvLarge ? 2 : 1)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _homePosterImage(
                  assetImage: widget.assetImage,
                  imageUrl: widget.imageUrl,
                ),
                TmdbPosterRatingBadge(
                  rating: widget.rating,
                  rating5based: widget.rating5based,
                  contentKey: widget.contentKey,
                  title: widget.title,
                  year: extractReleaseYear(widget.title),
                  isSeries: widget.isSeries,
                ),
                if (!widget.isSeries)
                  MovieDownloadProgressOverlay(contentKey: widget.contentKey),
                if (widget.showContentTypeBadge)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53935),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(8),
                        ),
                      ),
                      child: Text(
                        widget.isSeries
                            ? 'content_type_series'.tr
                            : 'content_type_movie'.tr,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: tvLarge ? 12 : 11.sp,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        4,
                        tvLarge ? 10 : 14,
                        4,
                        watchProgress != null ? 8 : 5,
                      ),
                      child: Text(
                        widget.title,
                        maxLines: tvLarge ? 2 : 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Get.textTheme.bodySmall!.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: titleSize,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                ),
                if (watchProgress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: WatchProgressBar(progress: watchProgress),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tvLarge && !kReduceFocusMotion) {
      card = AnimatedScale(
        scale: _focused ? 1.04 : 1.0,
        duration: kFocusAnimDuration,
        curve: Curves.easeOut,
        alignment: Alignment.center,
        child: card,
      );
    }

    return RepaintBoundary(child: SizedBox(width: width, child: card));
  }
}

class _HomeShowMoreCard extends StatefulWidget {
  const _HomeShowMoreCard({
    required this.onTap,
    this.isFirstInRow = false,
    this.isLastInRow = true,
    this.tvLarge = false,
    this.posterWidth,
    this.focusDebugLabel,
  });

  final VoidCallback onTap;
  final bool isFirstInRow;
  final bool isLastInRow;
  final bool tvLarge;
  final double? posterWidth;
  final String? focusDebugLabel;

  @override
  State<_HomeShowMoreCard> createState() => _HomeShowMoreCardState();
}

class _HomeShowMoreCardState extends State<_HomeShowMoreCard> {
  bool _focused = false;
  late final FocusNode _focusNode = FocusNode(debugLabel: widget.focusDebugLabel);

  @override
  void initState() {
    super.initState();
    _stvBindFocusLabel(_focusNode, widget.focusDebugLabel);
  }

  @override
  void didUpdateWidget(covariant _HomeShowMoreCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusDebugLabel != widget.focusDebugLabel) {
      _stvBindFocusLabel(_focusNode, widget.focusDebugLabel);
    }
  }

  @override
  void dispose() {
    _stvBindFocusLabel(_focusNode, null);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvLarge = widget.tvLarge;
    final accent = kColorFocus;
    final radius = tvLarge ? 16.0 : _kHomePosterRadius;
    final width = widget.posterWidth ??
        (tvLarge ? 168.0 : 11.5.w.clamp(72.0, 110.0));

    Widget card = Focus(
      focusNode: _focusNode,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
        if (v) {
          Scrollable.ensureVisible(
            context,
            alignment: tvLarge ? 0.2 : 0.5,
            duration: kTvEnsureVisibleDuration,
            curve: Curves.easeOut,
          );
        }
      },
      onKeyEvent: (node, event) => _homeRowHorizontalKey(
        node,
        event,
        isFirstInRow: widget.isFirstInRow,
        isLastInRow: widget.isLastInRow,
        onActivate: widget.onTap,
      ),
      child: InkWell(
        onTap: widget.onTap,
        canRequestFocus: false,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: tvLarge ? const Color(0xFF141820) : kColorCardLight,
            border: Border.all(
              color: _focused
                  ? accent
                  : Colors.white.withValues(alpha: 0.18),
              width: tvLarge ? 2.0 : (_focused ? 2.4 : 1.2),
            ),
            boxShadow: !_focused
                ? null
                : [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 0,
                      spreadRadius: tvLarge ? 2.5 : 1.5,
                    ),
                    if (!kReduceFocusMotion && !tvLarge)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 8),
                      ),
                  ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.arrow_right,
                color: _focused ? accent : Colors.white70,
                size: tvLarge ? 28.0 * (MediaQuery.sizeOf(context).width / 1920.0) : 22,
              ),
              SizedBox(height: tvLarge ? 12 : 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'home_show_more'.tr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Get.textTheme.bodySmall!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: tvLarge
                        ? 14.0 * (MediaQuery.sizeOf(context).width / 1920.0)
                        : 10.sp,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tvLarge && !kReduceFocusMotion) {
      card = AnimatedScale(
        scale: _focused ? 1.04 : 1.0,
        duration: kFocusAnimDuration,
        curve: Curves.easeOut,
        child: card,
      );
    }

    return RepaintBoundary(child: SizedBox(width: width, child: card));
  }
}

class _HomePosterSkeleton extends StatelessWidget {
  const _HomePosterSkeleton();

  @override
  Widget build(BuildContext context) {
    final slide = _HomeShimmerScope.slideOf(context);
    return SizedBox(
      width: 11.5.w.clamp(72.0, 110.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kHomePosterRadius),
              child: _HomeShimmerBox(
                slide: slide,
                borderRadius: _kHomePosterRadius,
              ),
            ),
          ),
          const SizedBox(height: 5),
          _HomeShimmerBox(slide: slide, height: 20, borderRadius: 4),
        ],
      ),
    );
  }
}

/// مؤشر تحميل مركزي عند عدم وجود كاش (أول تشغيل).
class _HomeCenteredLoader extends StatelessWidget {
  const _HomeCenteredLoader();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: kColorPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// متحكم shimmer واحد لكل صفوف الرئيسية (أخف على Android TV).
class _HomeShimmerScope extends StatefulWidget {
  const _HomeShimmerScope({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  static double slideOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_HomeShimmerInherited>()
            ?.slide ??
        0;
  }

  @override
  State<_HomeShimmerScope> createState() => _HomeShimmerScopeState();
}

class _HomeShimmerScopeState extends State<_HomeShimmerScope>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _start();
  }

  @override
  void didUpdateWidget(covariant _HomeShimmerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _start();
    } else if (!widget.enabled && oldWidget.enabled) {
      _stop();
    }
  }

  void _start() {
    // TV / lite: هيكل ثابت بلا أنيميشن مستمر.
    if (AppPerf.instance.isLite || AppPerf.instance.isTelevisionLike) {
      return;
    }
    _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  void _stop() {
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    if (_controller == null) {
      // هيكل ثابت على الأجهزة الضعيفة — بدون تكرار الإطارات.
      return _HomeShimmerInherited(slide: 0.35, child: widget.child);
    }
    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, child) {
        return _HomeShimmerInherited(slide: _controller!.value, child: child!);
      },
      child: widget.child,
    );
  }
}

class _HomeShimmerInherited extends InheritedWidget {
  const _HomeShimmerInherited({required this.slide, required super.child});

  final double slide;

  @override
  bool updateShouldNotify(covariant _HomeShimmerInherited oldWidget) {
    return oldWidget.slide != slide;
  }
}

class _HomeShimmerBox extends StatelessWidget {
  const _HomeShimmerBox({
    required this.slide,
    this.height,
    this.borderRadius = 8,
  });

  final double slide;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final base = Color.lerp(kColorCardLight, const Color(0xFF3A3A3A), 0.35)!;
    final highlight = Color.lerp(kColorCardLight, Colors.white, 0.12)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: height,
        width: height != null ? double.infinity : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.2 + slide * 2.4, 0),
              end: Alignment(-0.2 + slide * 2.4, 0),
              colors: [base, highlight, base],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeContentRow extends StatelessWidget {
  const _HomeContentRow({
    required this.title,
    required this.itemCount,
    required this.isLoading,
    required this.itemBuilder,
    this.onShowMore,
    this.showNoContent = false,
    this.tvStyle = false,
    this.posterWidth,
    this.tvFocusRow,
  });

  final String title;
  final int itemCount;
  final bool isLoading;
  final bool showNoContent;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final VoidCallback? onShowMore;
  final bool tvStyle;
  final double? posterWidth;
  /// رقم الصف لفوكس Smart TV (null = هاتف / بدون تسمية).
  final int? tvFocusRow;

  @override
  Widget build(BuildContext context) {
    final showMoreTile = !isLoading && itemCount > 0 && onShowMore != null;
    final contentCount = isLoading
        ? kHomeShimmerPlaceholderCount
        : itemCount + (showMoreTile ? 1 : 0);
    final scale = MediaQuery.sizeOf(context).width / 1920.0;
    final gap = tvStyle ? 18.0 * scale : 8.0;
    final titleSize = tvStyle ? 22.0 * scale : (isTv(context) ? 17.5 : 16).sp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tvStyle ? 4 : 20,
            0,
            tvStyle ? 4 : 20,
            tvStyle ? 14.0 * scale : 8,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              title,
              style: Get.textTheme.titleMedium!.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: titleSize,
                letterSpacing: 0.15,
                height: 1.15,
              ),
            ),
          ),
        ),
        Expanded(
          child: showNoContent
              ? Center(
                  child: Text(
                    'home_no_content'.tr,
                    style: Get.textTheme.bodyMedium!.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                )
              : FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    physics: tvStyle
                        ? const ClampingScrollPhysics()
                        : const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                    addAutomaticKeepAlives: false,
                    addSemanticIndexes: false,
                    // مساحة للحلقة الذهبية حتى لا تُقصّ
                    clipBehavior: Clip.hardEdge,
                    padding: EdgeInsets.fromLTRB(
                      tvStyle ? 6 : 16,
                      tvStyle ? 8.0 * scale : 0,
                      tvStyle ? 6 : 16,
                      tvStyle ? 18.0 * scale : 0,
                    ),
                    cacheExtent: tvStyle
                        ? (AppPerf.instance.isTelevisionLike ? 64 : 120)
                        : 80,
                    itemCount: contentCount,
                    separatorBuilder: (_, _) => SizedBox(width: gap),
                    itemBuilder: (context, index) {
                      if (isLoading) {
                        return RepaintBoundary(
                          child: SizedBox(
                            width: posterWidth ??
                                (tvStyle
                                    ? 168.0
                                    : 11.5.w.clamp(72.0, 110.0)),
                            child: const _HomePosterSkeleton(),
                          ),
                        );
                      }
                      if (showMoreTile && index == itemCount) {
                        return _HomeShowMoreCard(
                          isFirstInRow: itemCount == 0,
                          isLastInRow: true,
                          tvLarge: tvStyle,
                          posterWidth: posterWidth,
                          focusDebugLabel: tvFocusRow != null
                              ? _stvPosterLabel(tvFocusRow!, itemCount)
                              : null,
                          onTap: onShowMore!,
                        );
                      }
                      return itemBuilder(context, index);
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

