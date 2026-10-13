part of 'screens.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  static String? homePosterPrecacheKey;
  static int? continuePosterPrecacheKey;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();

  static void _showAppExitConfirm(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => AppExitConfirmDialog(
        onExit: () {
          Navigator.of(ctx).pop();
          SystemNavigator.pop();
        },
        onStay: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    FocusNode? firstMovieFocusNode,
    bool hideTvTopBar = false,
  }) {
    return _welcomeBuildHomeContent(
      context,
      firstMovieFocusNode: firstMovieFocusNode,
      hideTvTopBar: hideTvTopBar,
    );
  }
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with
        WidgetsBindingObserver,
        RouteAware,
        HomeLandscapeLockMixin<WelcomeScreen> {
  /// يمنع تكرار نفس عرض الاستكمال في الجلسة الحالية.
  static String? _lastChannelResumePromptKey;

  final FocusNode _firstMovieFocusNode = FocusNode(
    debugLabel: 'home_first_movie',
  );

  /// شلّ التلفزيون: Home / Movies / Series / Favourites تحت شريط واحد.
  SmartTvShellTab _tvShellTab = SmartTvShellTab.home;

  /// ما نبنيش تبويبات ثقيلة مع أول إطار ديال Home — هادا اللي كيعلّق bootstrap على 100%.
  final Set<SmartTvShellTab> _tvBuiltPanes = {SmartTvShellTab.home};
  final GlobalKey<MovieCategoriesScreenState> _tvMoviesKey =
      GlobalKey<MovieCategoriesScreenState>();
  final GlobalKey<SeriesCategoriesScreenState> _tvSeriesKey =
      GlobalKey<SeriesCategoriesScreenState>();
  final GlobalKey<FavouriteScreenState> _tvFavKey =
      GlobalKey<FavouriteScreenState>();

  Future<void> _selectTvShellTab(SmartTvShellTab tab) async {
    if (tab == SmartTvShellTab.live) {
      kSmartTvClearTopSearch();
      _stvSetActiveShellTab(SmartTvShellTab.live);
      await ParentalControlService.instance.navigateToProtectedAction(
        ParentalSection.live,
        openLiveIptvBrowser,
      );
      if (mounted) _stvSetActiveShellTab(_tvShellTab);
      return;
    }
    if (tab == _tvShellTab) {
      _focusTvShellContent();
      return;
    }
    kSmartTvClearTopSearch();
    if (tab == SmartTvShellTab.home || tab == SmartTvShellTab.favourites) {
      if (!mounted) return;
      setState(() {
        _tvShellTab = tab;
        _tvBuiltPanes.add(tab);
      });
      _stvSetActiveShellTab(tab);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusTvShellContent();
      });
      return;
    }
    final section = tab == SmartTvShellTab.movies
        ? ParentalSection.movies
        : ParentalSection.series;
    await ParentalControlService.instance.navigateToProtectedAction(
      section,
      () async {
        if (!mounted) return;
        setState(() {
          _tvShellTab = tab;
          _tvBuiltPanes.add(tab);
        });
        _stvSetActiveShellTab(tab);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusTvShellContent();
        });
      },
    );
  }

  void _focusTvShellContent() {
    if (!mounted || !isTv(context)) return;
    switch (_tvShellTab) {
      case SmartTvShellTab.home:
        _restoreFocusToFirstMovie();
        return;
      case SmartTvShellTab.movies:
        final ok = _tvMoviesKey.currentState?.focusPrimaryCategory() ?? false;
        if (!ok) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tvMoviesKey.currentState?.focusPrimaryCategory();
          });
        }
        return;
      case SmartTvShellTab.series:
        final ok = _tvSeriesKey.currentState?.focusPrimaryCategory() ?? false;
        if (!ok) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tvSeriesKey.currentState?.focusPrimaryCategory();
          });
        }
        return;
      case SmartTvShellTab.favourites:
        _tvFavKey.currentState?.focusPrimaryContent();
        return;
      case SmartTvShellTab.live:
        return;
    }
  }

  /// بعد Done على كlavier البحث العلوي.
  void _focusAfterTopSearchDismiss() {
    if (!mounted || !isTv(context)) return;
    switch (_tvShellTab) {
      case SmartTvShellTab.home:
        _restoreFocusToFirstMovie();
        return;
      case SmartTvShellTab.movies:
        _tvMoviesKey.currentState?.focusAfterTopSearch();
        return;
      case SmartTvShellTab.series:
        _tvSeriesKey.currentState?.focusAfterTopSearch();
        return;
      case SmartTvShellTab.favourites:
        _tvFavKey.currentState?.focusAfterTopSearch();
        return;
      case SmartTvShellTab.live:
        return;
    }
  }

  void _onPendingTvShellTab() {
    final tab = kPendingTvShellTab.value;
    if (tab == null) return;
    kPendingTvShellTab.value = null;
    if (!mounted) return;
    if (tab == SmartTvShellTab.live) return;
    // فوري قبل أي await — يمنع وميض Home بعد الرجوع من Live.
    unawaited(_selectTvShellTabAfterLive(tab));
  }

  /// من شريط Live: طبّق التبويب فوراً ثم تحقق الأبوة إن لزم.
  Future<void> _selectTvShellTabAfterLive(SmartTvShellTab tab) async {
    if (!mounted) return;
    final previous = _tvShellTab;
    kSmartTvClearTopSearch();
    setState(() {
      _tvShellTab = tab;
      _tvBuiltPanes.add(tab);
    });
    _stvSetActiveShellTab(tab);

    if (tab == SmartTvShellTab.movies || tab == SmartTvShellTab.series) {
      final section = tab == SmartTvShellTab.movies
          ? ParentalSection.movies
          : ParentalSection.series;
      var allowed = false;
      await ParentalControlService.instance.navigateToProtectedAction(
        section,
        () async {
          allowed = true;
        },
      );
      if (!mounted) return;
      if (!allowed) {
        setState(() => _tvShellTab = previous);
        _stvSetActiveShellTab(previous);
        return;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusTvShellContent();
    });
  }

  @override
  void initState() {
    super.initState();
    HomePerfLogger.mark('welcome_init');
    kPendingTvShellTab.addListener(_onPendingTvShellTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeShowLastChannelResumeToast();
      AppUpdateService.instance.scheduleCheckForHome(context);
      // سخّن banners مبكراً على TV (AdMob بطيء / ضعيف على التلفاز).
      if (isTv(context) &&
          AdsService.shouldShowBanner(AppBannerPlacement.catalog)) {
        unawaited(AdsService.init());
        unawaited(AdsService.preloadCompactBanners(count: 3));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      kAppRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    kPendingTvShellTab.removeListener(_onPendingTvShellTab);
    kAppRouteObserver.unsubscribe(this);
    _firstMovieFocusNode.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    // رجوع من فيلم/مسلسل/لايف → عاود سخن ملصقات الرئيسية من الكاش.
    if (!mounted) return;
    unawaited(HomeBootstrapLoader.warmHomePosters(context));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeShowLastChannelResumeToast();
      unawaited(HomeBootstrapLoader.warmHomePosters(context));
    });
  }

  void _restoreFocusToFirstMovie() {
    if (!mounted || !isTv(context)) return;
    void request() {
      if (!mounted) return;
      // أول عنصر محتوى: Hero (Watch Now) إن وُجد، وإلا صف المتابعة/الأفلام.
      final scope = FocusScope.of(context);
      FocusNode? bestPoster;
      var bestRow = 1 << 30;
      var bestCol = 1 << 30;
      for (final node in scope.traversalDescendants) {
        if (!node.canRequestFocus || node.skipTraversal) continue;
        if (node.context == null) continue;
        final parsed = _stvParsePosterLabel(_stvLabelOf(node));
        if (parsed == null) continue;
        final row = parsed.$1;
        final col = parsed.$2;
        if (row < bestRow || (row == bestRow && col < bestCol)) {
          bestPoster = node;
          bestRow = row;
          bestCol = col;
        }
      }
      if (bestPoster != null) {
        bestPoster.requestFocus();
        return;
      }
      if (_firstMovieFocusNode.canRequestFocus &&
          _firstMovieFocusNode.context != null) {
        _firstMovieFocusNode.requestFocus();
        return;
      }
      // احتياطي إن لم تُحمَّل الأفلام بعد.
      for (final node in scope.traversalDescendants) {
        if (!node.canRequestFocus || node.skipTraversal) continue;
        if (node.context == null) continue;
        node.requestFocus();
        break;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      request();
      WidgetsBinding.instance.addPostFrameCallback((_) => request());
    });
  }

  void _maybeShowLastChannelResumeToast() {
    if (!mounted) return;
    // لا تظهر فوق مشغّل أو شاشات أخرى فوق الرئيسية.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final settings = context.read<SettingsCubit>().state;
    if (settings.isDemo) return;

    final resume = LastLiveChannelService.peekResume();
    if (resume == null) return;

    final promptKey =
        '${resume.channel.streamId}|${resume.savedAt.millisecondsSinceEpoch}';
    if (_lastChannelResumePromptKey == promptKey) return;
    _lastChannelResumePromptKey = promptKey;

    final authState = context.read<AuthBloc>().state;
    final serverUrl = authState is AuthSuccess
        ? authState.user.serverInfo?.serverUrl
        : null;
    final logoUrl = resolveImageUrl(resume.channel.streamIcon, serverUrl);

    showLastChannelResumeToast(
      context,
      channelName: resume.title,
      channelLogoUrl: logoUrl.isEmpty ? null : logoUrl,
      onContinue: () {
        // استكمال = لا نحذف السجل؛ المشغّل سيحدّث آخر قناة.
        if (!mounted) return;
        Get.to(
          () => FullVideoScreen(
            title: resume.title,
            link: resume.link,
            isLive: true,
            channelLive: resume.channel,
            initialLiveCategoryId: resume.categoryId,
          ),
        );
      },
      onDismiss: () {
        // إغلاق أو انتهاء العدّاد بدون استكمال — لا تظهر مجدداً بعد إعادة فتح التطبيق.
        LastLiveChannelService.markResumeDismissed();
      },
      onRestoreHomeFocus: _restoreFocusToFirstMovie,
    );
  }

  @override
  Widget build(BuildContext context) {
    HomePerfLogger.logBuildStart('welcome_screen');
    final homeBody = ValueListenableBuilder<int>(
      valueListenable: homeThemeRevision,
      builder: (context, _, _) {
        return KeyedSubtree(
          key: ValueKey(getActiveHomeThemeKey()),
          child: widget._buildContent(
            context,
            firstMovieFocusNode: _firstMovieFocusNode,
            hideTvTopBar: isTv(context),
          ),
        );
      },
    );

    final Widget child;
    if (!isTv(context)) {
      child = homeBody;
    } else {
      // شلّ Smart TV: شريط علوي ثابت + تبويبات بدون شكل هاتف.
      child = PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, dynamic result) {
          if (didPop) return;
          if (_tvShellTab != SmartTvShellTab.home) {
            setState(() => _tvShellTab = SmartTvShellTab.home);
            return;
          }
          WelcomeScreen._showAppExitConfirm(Get.context!);
        },
        child: Scaffold(
          backgroundColor: kSkyProBlack,
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SmartTvHomeTopBar(
                sideRail: true,
                selected: _tvShellTab,
                onSelectTab: (tab) {
                  unawaited(_selectTvShellTab(tab));
                },
                onArrowRightToContent: _focusTvShellContent,
              ),
              Expanded(
                child: Column(
                  children: [
                    _SmartTvHomeTopBar(
                      utilitiesOnly: true,
                      selected: _tvShellTab,
                      onArrowDownToContent: _focusTvShellContent,
                      onSearchClosed: _focusAfterTopSearchDismiss,
                    ),
                    Expanded(
                      child: IndexedStack(
                        sizing: StackFit.expand,
                        index: switch (_tvShellTab) {
                          SmartTvShellTab.home || SmartTvShellTab.live => 0,
                          SmartTvShellTab.movies => 1,
                          SmartTvShellTab.series => 2,
                          SmartTvShellTab.favourites => 3,
                        },
                        children: [
                          ExcludeFocus(
                            excluding: _tvShellTab != SmartTvShellTab.home,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: smartTvHomeSideInset(context),
                              ),
                              child: homeBody,
                            ),
                          ),
                          ExcludeFocus(
                            excluding: _tvShellTab != SmartTvShellTab.movies,
                            child:
                                _tvBuiltPanes.contains(SmartTvShellTab.movies)
                                ? MovieCategoriesScreen(
                                    key: _tvMoviesKey,
                                    embeddedInTvShell: true,
                                  )
                                : const SizedBox.expand(),
                          ),
                          ExcludeFocus(
                            excluding: _tvShellTab != SmartTvShellTab.series,
                            child:
                                _tvBuiltPanes.contains(SmartTvShellTab.series)
                                ? SeriesCategoriesScreen(
                                    key: _tvSeriesKey,
                                    embeddedInTvShell: true,
                                  )
                                : const SizedBox.expand(),
                          ),
                          ExcludeFocus(
                            excluding:
                                _tvShellTab != SmartTvShellTab.favourites,
                            child:
                                _tvBuiltPanes.contains(
                                  SmartTvShellTab.favourites,
                                )
                                ? FavouriteScreen(
                                    key: _tvFavKey,
                                    embeddedInTvShell: true,
                                  )
                                : const SizedBox.expand(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    HomePerfLogger.logBuildEnd('welcome_screen');
    return child;
  }
}
