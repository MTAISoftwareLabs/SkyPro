part of '../screens.dart';

class CatchUpScreen extends StatefulWidget {
  const CatchUpScreen({super.key});

  @override
  State<CatchUpScreen> createState() => _CatchUpScreenState();
}

class _CatchUpScreenState extends State<CatchUpScreen>
    with LandscapeMainAppStateMixin<CatchUpScreen> {
  int _selectedCategory = 0;

  late final FocusNode _backFocusNode;
  late final List<FocusNode> _tabFocusNodes;
  late final FocusNode _firstContentFocusNode;
  late final FocusScopeNode _contentScope;

  static const _tabs = [
    (key: 'fav_movies', icon: Icons.movie_filter_rounded),
    (key: 'fav_series', icon: Icons.video_library_rounded),
  ];

  static bool _isKeyDown(KeyEvent event) =>
      event is KeyDownEvent || event is KeyRepeatEvent;

  @override
  void initState() {
    super.initState();

    _backFocusNode = FocusNode(
      debugLabel: 'catchup_back',
      onKeyEvent: (n, e) => _onBackKey(n, e),
    );
    _tabFocusNodes = List.generate(
      _tabs.length,
      (i) => FocusNode(debugLabel: 'catchup_tab_$i'),
    );
    _firstContentFocusNode = FocusNode(debugLabel: 'catchup_first_content');
    _contentScope = FocusScopeNode(debugLabel: 'catchup_content');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _backFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _backFocusNode.dispose();
    for (final n in _tabFocusNodes) {
      n.dispose();
    }
    _firstContentFocusNode.dispose();
    _contentScope.dispose();
    super.dispose();
  }

  void _selectCategory(int index) {
    if (_selectedCategory == index) return;
    setState(() => _selectedCategory = index);
  }

  void _focusTabs() {
    final i = _selectedCategory.clamp(0, _tabFocusNodes.length - 1);
    _tabFocusNodes[i].requestFocus();
  }

  bool _isContentEmpty() {
    final state = context.read<WatchingCubit>().state;
    return _selectedCategory == 0
        ? state.movies.isEmpty
        : state.series.isEmpty;
  }

  /// الشجرة #3: أول كارت في المحتوى (إن وُجد).
  void _focusContent() {
    if (!mounted) return;
    if (_isContentEmpty()) return;

    void tryFocus() {
      if (!mounted) return;
      if (_firstContentFocusNode.context != null) {
        _firstContentFocusNode.requestFocus();
      }
    }

    tryFocus();
    if (_firstContentFocusNode.context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => tryFocus());
    }
  }

  KeyEventResult _onBackKey(FocusNode node, KeyEvent event) {
    if (!_isKeyDown(event)) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _focusContent();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _focusTabs();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onTabKey(int index, FocusNode node, KeyEvent event) {
    if (!_isKeyDown(event)) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _selectCategory(index);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusContent();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      // التبويبات في نفس شريط الرجوع — الأعلى يبقى على التبويب.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _selectCategory(index - 1);
        _tabFocusNodes[index - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < _tabFocusNodes.length - 1) {
        _selectCategory(index + 1);
        _tabFocusNodes[index + 1].requestFocus();
      } else {
        _backFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final size = getSize(context);
    final tv = isTv(context);

    return Scaffold(
      body: Container(
        width: size.width,
        height: size.height,
        decoration: kDecorBackground,
        child: SafeArea(
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: BlocBuilder<WatchingCubit, WatchingState>(
                    builder: (context, state) {
                      return _CatchUpHeroHeader(
                        movieCount: state.movies.length,
                        seriesCount: state.series.length,
                        isTv: tv,
                        backFocusNode: _backFocusNode,
                        tabs: _tabs,
                        selectedIndex: _selectedCategory,
                        tabFocusNodes: _tabFocusNodes,
                        onSelected: _selectCategory,
                        onTabKey: _onTabKey,
                      );
                    },
                  ),
                ),
                Expanded(
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(2),
                    child: _GridNavScope(
                      focusTabs: _focusTabs,
                      child: FocusScope(
                        node: _contentScope,
                        child: AnimatedSwitcher(
                          duration: kTvSnapFocusScroll
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              alignment: Alignment.center,
                              fit: StackFit.expand,
                              children: [
                                ...previousChildren,
                                ?currentChild,
                              ],
                            );
                          },
                          transitionBuilder: (child, animation) {
                            if (kTvSnapFocusScroll) return child;
                            final slide = Tween<Offset>(
                              begin: const Offset(0, 0.03),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: KeyedSubtree(
                            key: ValueKey<int>(_selectedCategory),
                            child: _selectedCategory == 0
                                ? _CatchUpMoviesPage(
                                    firstContentFocusNode:
                                        _firstContentFocusNode,
                                  )
                                : _CatchUpSeriesPage(
                                    firstContentFocusNode:
                                        _firstContentFocusNode,
                                  ),
                          ),
                        ),
                      ),
                    ),
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

class _CatchUpHeroHeader extends StatelessWidget {
  const _CatchUpHeroHeader({
    required this.movieCount,
    required this.seriesCount,
    required this.isTv,
    required this.backFocusNode,
    required this.tabs,
    required this.selectedIndex,
    required this.tabFocusNodes,
    required this.onSelected,
    required this.onTabKey,
  });

  final int movieCount;
  final int seriesCount;
  final bool isTv;
  final FocusNode backFocusNode;
  final List<({String key, IconData icon})> tabs;
  final int selectedIndex;
  final List<FocusNode> tabFocusNodes;
  final ValueChanged<int> onSelected;
  final KeyEventResult Function(int index, FocusNode node, KeyEvent event)
      onTabKey;

  @override
  Widget build(BuildContext context) {
    final padH = isTv ? 28.0 : 16.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(padH, isTv ? 10 : 8, padH, isTv ? 10 : 8),
      decoration: BoxDecoration(
        color: kColorAppBar,
        border: Border(
          bottom: BorderSide(color: kColorHint.withValues(alpha: 0.35)),
        ),
      ),
      child: SizedBox(
        height: isTv ? 56 : 48,
        child: Row(
          children: [
            // يسار: أيقونة + عنوان (مساحة متساوية مع اليمين حتى يبقى الوسط في المركز)
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: isTv ? 44 : 38,
                    height: isTv ? 44 : 38,
                    decoration: kDecorIconCircle,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.history_rounded,
                      size: isTv ? 22 : 18,
                      color: kColorBack,
                    ),
                  ),
                  SizedBox(width: isTv ? 12 : 8),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'catch_up'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isTv ? 18 : 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _CatchUpCountChip(
                              icon: Icons.movie_filter_rounded,
                              label: 'fav_movies'.tr,
                              count: movieCount,
                              compact: true,
                            ),
                            _CatchUpCountChip(
                              icon: Icons.video_library_rounded,
                              label: 'fav_series'.tr,
                              count: seriesCount,
                              compact: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // الوسط تماماً
            _CatchUpSegmentedTabs(
              tabs: tabs,
              selectedIndex: selectedIndex,
              focusNodes: tabFocusNodes,
              isTv: isTv,
              compact: true,
              onSelected: onSelected,
              onTabKey: onTabKey,
            ),
            // يمين: زر الرجوع بنفس عرض الجانب الأيسر
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  focusNode: backFocusNode,
                  focusColor: kColorFocus,
                  tooltip: 'back'.tr,
                  onPressed: () => Get.back(),
                  icon: Icon(
                    FontAwesomeIcons.chevronRight,
                    color: Colors.white,
                    size: isTv ? 20 : 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatchUpCountChip extends StatelessWidget {
  const _CatchUpCountChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: kColorCardLight.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: kColorPrimary),
          const SizedBox(width: 5),
          if (!compact) ...[
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '$count',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CatchUpSegmentedTabs extends StatelessWidget {
  const _CatchUpSegmentedTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.focusNodes,
    required this.isTv,
    required this.onSelected,
    required this.onTabKey,
    this.compact = false,
  });

  final List<({String key, IconData icon})> tabs;
  final int selectedIndex;
  final List<FocusNode> focusNodes;
  final bool isTv;
  final bool compact;
  final ValueChanged<int> onSelected;
  final KeyEventResult Function(int index, FocusNode node, KeyEvent event)
      onTabKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0) SizedBox(width: isTv ? (compact ? 8 : 12) : 8),
              _CatchUpTabChip(
                focusNode: focusNodes[i],
                selected: selectedIndex == i,
                label: tabs[i].key.tr,
                icon: tabs[i].icon,
                isTv: isTv,
                compact: compact,
                onTap: () => onSelected(i),
                onKeyEvent: (node, event) => onTabKey(i, node, event),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CatchUpTabChip extends StatelessWidget {
  const _CatchUpTabChip({
    required this.focusNode,
    required this.selected,
    required this.label,
    required this.icon,
    required this.isTv,
    required this.onTap,
    required this.onKeyEvent,
    this.compact = false,
  });

  final FocusNode focusNode;
  final bool selected;
  final String label;
  final IconData icon;
  final bool isTv;
  final bool compact;
  final VoidCallback onTap;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          final borderColor = focused
              ? kColorFocus
              : selected
                  ? kColorPrimary.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08);
          final padH = compact
              ? (isTv ? 16.0 : 12.0)
              : (isTv ? 22.0 : 14.0);
          final padV = compact
              ? (isTv ? 10.0 : 8.0)
              : (isTv ? 14.0 : 11.0);

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              canRequestFocus: false,
              focusColor: kColorFocus.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: kFocusAnimDuration,
                padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                decoration: BoxDecoration(
                  color: selected
                      ? kColorPrimary.withValues(alpha: 0.22)
                      : kColorCardLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: borderColor,
                    width: focused ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: compact
                          ? (isTv ? 16 : 14)
                          : (isTv ? 22 : 18),
                      color: selected || focused
                          ? Colors.white
                          : Colors.white70,
                    ),
                    SizedBox(width: compact ? 6 : (isTv ? 10 : 8)),
                    Text(
                      label,
                      style: TextStyle(
                        color: selected || focused
                            ? Colors.white
                            : Colors.white70,
                        fontSize: compact
                            ? (isTv ? 13 : 12)
                            : (isTv ? 16 : 13.5),
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CatchUpEmptyState extends StatelessWidget {
  const _CatchUpEmptyState({
    required this.icon,
    required this.titleKey,
  });

  final IconData icon;
  final String titleKey;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: tv ? 110 : 88,
              height: tv ? 110 : 88,
              decoration: BoxDecoration(
                color: kColorCardLight,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: tv ? 44 : 36, color: kColorHint),
            ),
            SizedBox(height: tv ? 22 : 18),
            Text(
              titleKey.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: tv ? 20 : 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'catch_up_empty_hint'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: tv ? 15 : 13.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatchUpMoviesPage extends StatelessWidget {
  const _CatchUpMoviesPage({required this.firstContentFocusNode});

  final FocusNode firstContentFocusNode;
  static String? _posterPrecacheKey;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WatchingCubit, WatchingState>(
      builder: (context, state) {
        final watching = state.movies;

        if (watching.isEmpty) {
          return const _CatchUpEmptyState(
            icon: Icons.movie_filter_outlined,
            titleKey: 'no_movies',
          );
        }

        final authState = context.read<AuthBloc>().state;
        final serverUrl = authState is AuthSuccess
            ? authState.user.serverInfo?.serverUrl
            : null;
        final precacheKey = 'catchup_movies:${watching.length}';
        if (_posterPrecacheKey != precacheKey) {
          _posterPrecacheKey = precacheKey;
          final urls = <String>[];
          for (final m in watching.take(20)) {
            final u = resolveImageUrl(m.image, serverUrl);
            if (u.isNotEmpty) urls.add(u);
          }
          unawaited(precacheIptvPosters(context, urls));
        }

        final tv = isTv(context);
        final crossAxisCount = _favPosterCrossAxisCount(context);

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            tv ? 20 : 12,
            2,
            tv ? 20 : 12,
            tv ? 20 : 12,
          ),
          cacheExtent: tv ? kCatalogCacheExtent : null,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: _kFavPosterGridGap,
            mainAxisSpacing: _kFavPosterGridGap,
            childAspectRatio: 0.65,
          ),
          itemCount: watching.length,
          itemBuilder: (_, i) {
            final model = watching[i];
            final watchingCubit = context.read<WatchingCubit>();
            Future<void> openMovie() async {
              final mid = model.streamId.trim();
              String? movieCategoryId =
                  (model.categoryId ?? '').trim().isNotEmpty
                      ? model.categoryId
                      : null;
              final prefetch = context.read<PrefetchCubit>();
              MovieDetail? movieDetail;
              if (mid.isNotEmpty) {
                movieDetail = prefetch.peekMovieDetail(mid);
                if (movieDetail == null ||
                    (movieCategoryId ?? '').trim().isEmpty) {
                  movieDetail = await prefetch.getMovieDetailCached(mid);
                }
              }
              movieCategoryId ??=
                  (movieDetail?.movieData?.categoryId ?? '').trim().isNotEmpty
                      ? movieDetail!.movieData!.categoryId
                      : null;
              if (!context.mounted) return;

              Get.to(
                () => FullVideoScreen(
                  link: model.stream,
                  title: model.title,
                  channelMovie: ChannelMovie(
                    streamId: model.streamId,
                    name: model.title,
                    streamIcon: model.image,
                    rating: model.rating,
                    rating5based: model.rating5based,
                    categoryId: movieCategoryId,
                  ),
                  initialPositionSeconds:
                      model.sliderValue > 0 ? model.sliderValue : null,
                ),
              )!.then((slider) {
                if (!watchingPopMatchesOpenedStream(slider, model.streamId)) {
                  return;
                }
                final newMod = WatchingModel(
                  streamId: model.streamId,
                  image: model.image,
                  title: model.title,
                  stream: model.stream,
                  sliderValue: (slider[0] as num).toDouble(),
                  durationStrm: slider.length > 1
                      ? (slider[1] as num).toDouble()
                      : model.durationStrm,
                  rating: model.rating,
                  rating5based: model.rating5based,
                  categoryId: model.categoryId ?? movieCategoryId,
                );
                watchingCubit.addMovie(newMod);
              });
            }

            return TvCardFocus(
              focusNode: i == 0 ? firstContentFocusNode : null,
              onTvActivate: openMovie,
              child: CardMovieContinueWatch(
                model: model,
                onTap: openMovie,
                boldTitle: true,
                expandToCell: true,
              ),
            );
          },
        );
      },
    );
  }
}

class _CatchUpSeriesPage extends StatelessWidget {
  const _CatchUpSeriesPage({required this.firstContentFocusNode});

  final FocusNode firstContentFocusNode;
  static String? _posterPrecacheKey;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WatchingCubit, WatchingState>(
      builder: (context, state) {
        final watching = state.series;

        if (watching.isEmpty) {
          return const _CatchUpEmptyState(
            icon: Icons.video_library_outlined,
            titleKey: 'no_series',
          );
        }

        final authState = context.read<AuthBloc>().state;
        final serverUrl = authState is AuthSuccess
            ? authState.user.serverInfo?.serverUrl
            : null;
        final precacheKey = 'catchup_series:${watching.length}';
        if (_posterPrecacheKey != precacheKey) {
          _posterPrecacheKey = precacheKey;
          final urls = <String>[];
          for (final s in watching.take(20)) {
            final u = resolveImageUrl(s.image, serverUrl);
            if (u.isNotEmpty) urls.add(u);
          }
          unawaited(precacheIptvPosters(context, urls));
        }

        final tv = isTv(context);
        final crossAxisCount = _favPosterCrossAxisCount(context);

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            tv ? 20 : 12,
            2,
            tv ? 20 : 12,
            tv ? 20 : 12,
          ),
          cacheExtent: tv ? kCatalogCacheExtent : null,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: _kFavPosterGridGap,
            mainAxisSpacing: _kFavPosterGridGap,
            childAspectRatio: 0.65,
          ),
          itemCount: watching.length,
          itemBuilder: (_, i) {
            final model = watching[i];
            final watchingCubit = context.read<WatchingCubit>();
            Future<void> openEpisode() async {
              final seriesId = (model.seriesId ?? '').trim();
              UserModel? serieUserAuth;
              List<Episode?>? serieSeasonEpisodes;
              final authState = context.read<AuthBloc>().state;
              if (authState is AuthSuccess) {
                serieUserAuth = authState.user;
              }
              SerieDetails? details;
              if (seriesId.isNotEmpty) {
                details = await context
                    .read<PrefetchCubit>()
                    .getSerieDetailCached(seriesId);
              }
              serieSeasonEpisodes =
                  details?.episodesInSameSeasonAs(model.streamId);
              if (!context.mounted) return;

              Get.to(
                () => FullVideoScreen(
                  link: model.stream,
                  title: model.title,
                  channelSerie: ChannelSerie(
                    seriesId: model.seriesId,
                    name:
                        (model.seriesName ?? '').trim().isNotEmpty
                            ? model.seriesName
                            : model.title,
                    cover:
                        (model.seriesCover ?? '').trim().isNotEmpty
                            ? model.seriesCover
                            : model.image,
                    rating: details?.info?.rating ?? model.rating,
                    rating5based:
                        details?.info?.rating5based ?? model.rating5based,
                    categoryId: details?.info?.categoryId,
                  ),
                  serieEpisodes: serieSeasonEpisodes,
                  serieCurrentEpisodeId: model.streamId,
                  serieUserAuth: serieUserAuth,
                  initialPositionSeconds:
                      model.sliderValue > 0 ? model.sliderValue : null,
                ),
              )!.then((slider) {
                if (!watchingPopMatchesOpenedStream(slider, model.streamId)) {
                  return;
                }
                final newMod = WatchingModel(
                  streamId: model.streamId,
                  image: model.image,
                  title: model.title,
                  stream: model.stream,
                  sliderValue: (slider[0] as num).toDouble(),
                  durationStrm: slider.length > 1
                      ? (slider[1] as num).toDouble()
                      : model.durationStrm,
                  seriesId: model.seriesId,
                  seriesName: model.seriesName,
                  seriesCover: model.seriesCover,
                  rating: model.rating ?? details?.info?.rating,
                  rating5based:
                      model.rating5based ?? details?.info?.rating5based,
                );
                watchingCubit.addSerie(newMod);
              });
            }

            return TvCardFocus(
              focusNode: i == 0 ? firstContentFocusNode : null,
              onTvActivate: openEpisode,
              child: CardMovieContinueWatch(
                model: model,
                onTap: openEpisode,
                boldTitle: true,
                expandToCell: true,
              ),
            );
          },
        );
      },
    );
  }
}

/// يُستخدم من تفاصيل الأفلام/المسلسلات والحوارات.
class CardButtonWatchMovie extends StatefulWidget {
  const CardButtonWatchMovie({
    super.key,
    required this.title,
    required this.onTap,
    this.isFocused = false,
    this.hideBorder = false,
    this.isSelected = false,
    this.index,
    this.onFocusChanged,
  });
  final String title;
  final Function() onTap;
  final bool isFocused;
  final bool hideBorder;
  final bool isSelected;
  final int? index;
  final Function(int?)? onFocusChanged;

  @override
  State<CardButtonWatchMovie> createState() => _CardButtonWatchMovieState();
}

class _CardButtonWatchMovieState extends State<CardButtonWatchMovie> {
  bool isFocused = false;

  bool get _active => isFocused || widget.isSelected;

  @override
  Widget build(BuildContext context) {
    final radius = widget.hideBorder ? 0.0 : (1.2.w).clamp(6.0, 14.0);
    final vPad = (1.h).clamp(6.0, 12.0);
    final hPad = (1.5.w).clamp(8.0, 18.0);
    final activeFontSize = (1.8.h).clamp(12.0, 18.0);
    final normalFontSize = (1.6.h).clamp(11.0, 16.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        autofocus: widget.isFocused,
        borderRadius: BorderRadius.circular(radius),
        focusColor: Colors.transparent,
        splashColor: kColorPrimary.withValues(alpha: 0.15),
        highlightColor: Colors.transparent,
        onFocusChange: (bool value) {
          widget.onFocusChanged?.call(value ? widget.index : null);
          setState(() => isFocused = value);
        },
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: _active
                ? LinearGradient(
                    colors: [kColorPrimary, kColorPrimaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [
                      kColorPrimary.withValues(alpha: 0.15),
                      kColorPrimaryDark.withValues(alpha: 0.15),
                    ],
                  ),
            border: _active
                ? null
                : Border.all(
                    color: kColorPrimary.withValues(alpha: 0.2),
                    width: 1,
                  ),
            boxShadow: _active && !kReduceFocusMotion
                ? [
                    BoxShadow(
                      color: kColorPrimary.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: kFocusAnimDuration,
              style: TextStyle(
                fontSize: _active ? activeFontSize : normalFontSize,
                fontWeight: _active ? FontWeight.w700 : FontWeight.w400,
                color: _active
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.55),
                letterSpacing: _active ? 1.3 : 0.6,
              ),
              child: Text(widget.title.toUpperCase()),
            ),
          ),
        ),
      ),
    );
  }
}
