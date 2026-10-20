part of 'screens.dart';

/// جسم Home (صفوف + شريط) — مستخرج من WelcomeScreen لتقليل حجم الملف.

Widget _welcomeBuildHomeContent(
  BuildContext context, {
  FocusNode? firstMovieFocusNode,
  bool hideTvTopBar = false,
}) {
  final tv = isTv(context);
  final phoneNoFocus = !tv;
  final body = ValueListenableBuilder<String>(
    valueListenable: kSmartTvTopSearchQuery,
    builder: (context, _, _) {
      return ExcludeFocus(
    excluding: phoneNoFocus,
    child: Scaffold(
      backgroundColor: tv ? kSkyProBlack : null,
      body: DecoratedBox(
        decoration: tv
            ? const BoxDecoration(color: kSkyProBlack)
            : _homeScreenDecoration,
        child: SafeArea(
          top: false,
          bottom: false,
          left: false,
          right: false,
          child: BlocBuilder<SettingsCubit, SettingsState>(
            buildWhen: (prev, curr) => prev.isDemo != curr.isDemo,
            builder: (context, settingsState) {
              final isDemo = settingsState.isDemo;
              return BlocBuilder<HomeRecentCubit, HomeRecentState>(
                buildWhen: (prev, curr) {
                  if (prev is HomeRecentSuccess &&
                      curr is HomeRecentSuccess) {
                    return prev.movies != curr.movies ||
                        prev.series != curr.series ||
                        prev.recentMovies != curr.recentMovies ||
                        prev.recentSeries != curr.recentSeries ||
                        prev.isComplete != curr.isComplete ||
                        prev.fromCache != curr.fromCache ||
                        prev.isRefreshing != curr.isRefreshing;
                  }
                    return prev.runtimeType != curr.runtimeType;
                  },
                  builder: (context, recentState) {
                    final moviesRaw = isDemo
                        ? List<ChannelMovie>.generate(
                            kHomeRecentLimit,
                            (i) => ChannelMovie(
                              streamId: 'demo_movie_$i',
                              name: demoTestTitle(),
                              streamIcon: kDemoPosterAsset,
                            ),
                          )
                        : recentState is HomeRecentSuccess
                        ? recentState.movies
                        : const <ChannelMovie>[];
                    final seriesRaw = isDemo
                        ? List<ChannelSerie>.generate(
                            kHomeRecentLimit,
                            (i) => ChannelSerie(
                              seriesId: 'demo_series_$i',
                              name: demoTestTitle(),
                              cover: kDemoPosterAsset,
                            ),
                          )
                        : recentState is HomeRecentSuccess
                        ? recentState.series
                        : const <ChannelSerie>[];

                    // فلترة ترويج/تواصل — للصفحة الرئيسية فقط
                    // ثم الرقابة الأبوية (إخفاء +18 / أقسام مقفلة بدون جلسة PIN)
                    final movieCatyState = context.read<MovieCatyBloc>().state;
                    final seriesCatyState =
                        context.read<SeriesCatyBloc>().state;
                    final movieCats = movieCatyState is MovieCatySuccess
                        ? movieCatyState.categories
                        : const <CategoryModel>[];
                    final seriesCats = seriesCatyState is SeriesCatySuccess
                        ? seriesCatyState.categories
                        : const <CategoryModel>[];
                    final parental = ParentalControlService.instance;
                    final movies = parental.filterMoviesForHomeSurface(
                      _stvMatchTopSearchTitles(
                        isDemo
                            ? moviesRaw
                            : filterHomeContentTitles(
                                moviesRaw,
                                (m) => m.name,
                              ),
                        (m) => m.name,
                      ),
                      categoryNameForId: (id) =>
                          ParentalControlService.categoryNameFromId(
                            id,
                            movieCats,
                          ),
                      // صفوف الرئيسية تبقى ظاهرة؛ القفل يُفرض عند الفتح / Show more.
                      // الهيرو يخفي القسم المقفول عبر HomeHeroCache.pickCandidates.
                      hideLockedSection: false,
                    );
                    final series = parental.filterSeriesForHomeSurface(
                      _stvMatchTopSearchTitles(
                        isDemo
                            ? seriesRaw
                            : filterHomeContentTitles(
                                seriesRaw,
                                (s) => s.name,
                              ),
                        (s) => s.name,
                      ),
                      categoryNameForId: (id) =>
                          ParentalControlService.categoryNameFromId(
                            id,
                            seriesCats,
                          ),
                      hideLockedSection: false,
                    );

                    final recentMoviesRaw =
                        !isDemo && recentState is HomeRecentSuccess
                        ? recentState.recentMovies
                        : const <ChannelMovie>[];
                    final recentSeriesRaw =
                        !isDemo && recentState is HomeRecentSuccess
                        ? recentState.recentSeries
                        : const <ChannelSerie>[];
                    final recentMovies = parental.filterMoviesForHomeSurface(
                      _stvMatchTopSearchTitles(
                        filterHomeContentTitles(
                          recentMoviesRaw,
                          (m) => m.name,
                        ),
                        (m) => m.name,
                      ),
                      categoryNameForId: (id) =>
                          ParentalControlService.categoryNameFromId(
                            id,
                            movieCats,
                          ),
                      hideLockedSection: false,
                    );
                    final recentSeries = parental.filterSeriesForHomeSurface(
                      _stvMatchTopSearchTitles(
                        filterHomeContentTitles(
                          recentSeriesRaw,
                          (s) => s.name,
                        ),
                        (s) => s.name,
                      ),
                      categoryNameForId: (id) =>
                          ParentalControlService.categoryNameFromId(
                            id,
                            seriesCats,
                          ),
                      hideLockedSection: false,
                    );

                    final fetchComplete =
                        recentState is HomeRecentSuccess &&
                        recentState.isComplete;
                    final showColdStartLoader =
                        !isDemo &&
                        (recentState is HomeRecentInitial ||
                            recentState is HomeRecentLoading);
                    final shimmerActive =
                        !isDemo &&
                        (showColdStartLoader ||
                            (!fetchComplete &&
                                (movies.isEmpty || series.isEmpty)));
                    final moviesLoading =
                        !isDemo &&
                        (showColdStartLoader ||
                            (movies.isEmpty && !fetchComplete));
                    final seriesLoading =
                        !isDemo &&
                        (showColdStartLoader ||
                            (series.isEmpty && !fetchComplete));
                    final moviesShowNoContent =
                        !isDemo && fetchComplete && movies.isEmpty;
                    final seriesShowNoContent =
                        !isDemo && fetchComplete && series.isEmpty;

                    final authState = context.read<AuthBloc>().state;
                    final serverUrl = authState is AuthSuccess
                        ? authState.user.serverInfo?.serverUrl
                        : null;

                    final homePrecacheKey =
                        'home:${movies.length}:${series.length}:'
                        '${recentState is HomeRecentSuccess && recentState.isComplete}';
                    if (WelcomeScreen.homePosterPrecacheKey !=
                        homePrecacheKey) {
                      WelcomeScreen.homePosterPrecacheKey = homePrecacheKey;
                      final urls = <String>[];
                      final warmCount = isTv(context) ? 8 : 12;
                      for (final m in movies.take(warmCount)) {
                        final u = resolveImageUrl(m.streamIcon, serverUrl);
                        if (u.isNotEmpty) urls.add(u);
                      }
                      for (final s in series.take(warmCount)) {
                        final u = resolveImageUrl(s.cover, serverUrl);
                        if (u.isNotEmpty) urls.add(u);
                      }
                      unawaited(precacheIptvPosters(context, urls));
                    }

                    void onDemoTap() => openDemoVideoPlayer();

                    return BlocBuilder<WatchingCubit, WatchingState>(
                      builder: (context, watchState) {
                        final continueAll = <WatchingModel>[
                          ...watchState.movies,
                          ...watchState.series,
                        ];
                        final continueItems = _stvMatchTopSearchTitles(
                          continueAll,
                          (m) => m.seriesName ?? m.title,
                        );
                        if (WelcomeScreen.continuePosterPrecacheKey !=
                            continueItems.length) {
                          WelcomeScreen.continuePosterPrecacheKey =
                              continueItems.length;
                          if (continueItems.isNotEmpty) {
                            final cUrls = <String>[];
                            for (final m in continueItems.take(isTv(context) ? 8 : 12)) {
                              final u =
                                  resolveImageUrl(m.image, serverUrl);
                              if (u.isNotEmpty) cUrls.add(u);
                            }
                            unawaited(precacheIptvPosters(context, cUrls));
                          }
                        }
                        const continueRowLimit = 13;
                        final hasContinue =
                            !isDemo && continueItems.isNotEmpty;
                        final continueVisibleCount = hasContinue
                            ? continueItems.length.clamp(0, continueRowLimit)
                            : 0;
                        final continueShowMore =
                            hasContinue &&
                            continueItems.length > continueRowLimit;
                        final tv = isTv(context);
                        final searchingHome =
                            kSmartTvTopSearchQuery.value.trim().isNotEmpty;
                        final homeSearchNoHits = searchingHome &&
                            !moviesLoading &&
                            !seriesLoading &&
                            !hasContinue &&
                            movies.isEmpty &&
                            series.isEmpty &&
                            recentMovies.isEmpty &&
                            recentSeries.isEmpty;
                        return Column(
                          children: [
                            if (tv && !hideTvTopBar)
                              const _SmartTvHomeTopBar()
                            else if (!tv)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: MediaQuery.paddingOf(context).top,
                                ),
                                child: const _SmartTvHomeTopBar(),
                              ),
                            Expanded(
                              flex: 92,
                              child: homeSearchNoHits
                                  ? const _HomeTopSearchEmptyPanel()
                                  : _HomeShimmerScope(
                                enabled: shimmerActive,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    const titleBlock = 36.0;
                                    final double gap;
                                    double? posterW;
                                    final double rowHeight;
                                    final double tvBottomPad;
                                    // نفس هيرو التلفاز على الموبايل أيضاً.
                                    final showHero = !searchingHome &&
                                        (movies.isNotEmpty ||
                                            series.isNotEmpty ||
                                            isDemo ||
                                            HomeHeroPanel.hasPromoSlide);
                                    double heroHeight = 0;
                                    if (tv) {
                                      // كنبنيو المقاس على "الطول" الحقيقي المتوفر فهاد الشاشة
                                      // بالضبط (نسبة مئوية من constraints.maxHeight)، باش يتأقلم
                                      // تلقائياً مع أي دقة أو حجم تلفزة، بلا ما يبقى فراغ كبير
                                      // تحت آخر صف باين.
                                      const bottomMargin = 4.0;
                                      final usable =
                                          (constraints.maxHeight - bottomMargin)
                                              .clamp(240.0, constraints.maxHeight);
                                      gap = 8.0;
                                      // نفس مقاس الملصقات قبل إضافة الهيرو (ما كنكبّروش ولا كنصغّروش).
                                      const visible = 2.42;
                                      rowHeight = (usable - gap * 2) / visible;
                                      final posterH =
                                          (rowHeight - titleBlock)
                                              .clamp(130.0, 260.0);
                                      posterW = posterH / 1.5;
                                      if (showHero) {
                                        heroHeight =
                                            (constraints.maxHeight * 0.42)
                                                .clamp(280.0, 420.0);
                                      }
                                      tvBottomPad = 0;
                                    } else {
                                      // مقاس البوسترات كما هو — الهيرو فوق فقط، ما كيأثرش على الصفوف.
                                      gap = 0.8.h;
                                      posterW = null;
                                      rowHeight =
                                          (constraints.maxHeight - gap) / 2;
                                      tvBottomPad = 0;
                                      if (showHero) {
                                        heroHeight =
                                            (constraints.maxHeight * 0.42)
                                                .clamp(220.0, 320.0);
                                      }
                                    }
                                    // أرقام صفوف الفوكس (Smart TV column-lock).
                                    var stvRow = 0;
                                    final heroRow =
                                        showHero ? stvRow++ : null;
                                    final continueRow =
                                        hasContinue ? stvRow++ : null;
                                    final moviesRow = stvRow++;
                                    final seriesRow = stvRow++;
                                    final recentMoviesRow =
                                        tv ? stvRow++ : null;
                                    final recentSeriesRow =
                                        tv ? stvRow++ : null;
                                    return Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        SingleChildScrollView(
                                          primary: true,
                                          physics: const BouncingScrollPhysics(
                                            parent:
                                                AlwaysScrollableScrollPhysics(),
                                          ),
                                          keyboardDismissBehavior:
                                              ScrollViewKeyboardDismissBehavior
                                                  .onDrag,
                                          child: Column(
                                            children: [
                                              if (showHero &&
                                                  heroRow != null) ...[
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                                  child: RepaintBoundary(
                                                    child: _HomeHeroCarousel(
                                                      movies: movies,
                                                      series: series,
                                                      serverUrl: serverUrl,
                                                      tvFocusRow: heroRow,
                                                      height: heroHeight,
                                                      isDemo: isDemo,
                                                      onDemoTap: onDemoTap,
                                                      autofocusWatch: tv,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: gap),
                                              ],
                                              if (hasContinue) ...[
                                                SizedBox(
                                                  height: rowHeight,
                                                    child: _HomeContentRow(
                                                      title:
                                                          'home_continue_watching'
                                                              .tr,
                                                      isLoading: false,
                                                      tvStyle: tv,
                                                      posterWidth: posterW,
                                                      tvFocusRow: continueRow,
                                                      itemCount:
                                                          continueVisibleCount,
                                                    onShowMore:
                                                        continueShowMore
                                                        ? () {
                                                            Get.toNamed(
                                                              screenCatchUp,
                                                            );
                                                          }
                                                        : null,
                                                    itemBuilder: (ctx, i) {
                                                      final model =
                                                          continueItems[i];
                                                      final isSeries =
                                                          (model.seriesId ??
                                                                  '')
                                                              .trim()
                                                              .isNotEmpty;
                                                      final displayTitle =
                                                          (model.seriesName ??
                                                                  '')
                                                              .trim()
                                                              .isNotEmpty
                                                          ? model.seriesName!
                                                          : model.title;
                                                      final displayImage =
                                                          (model.seriesCover ??
                                                                  '')
                                                              .trim()
                                                              .isNotEmpty
                                                          ? model.seriesCover!
                                                          : model.image;

                                                      var continueRating =
                                                          model.rating;
                                                      var continueRating5 =
                                                          model.rating5based;
                                                      if (formatContentRating(
                                                            continueRating,
                                                            continueRating5,
                                                          ) ==
                                                          null) {
                                                        if (isSeries) {
                                                          final sid =
                                                              (model.seriesId ??
                                                                      '')
                                                                  .trim();
                                                          if (sid
                                                              .isNotEmpty) {
                                                            for (final s
                                                                in series) {
                                                              if ((s.seriesId ??
                                                                          '')
                                                                      .trim() ==
                                                                  sid) {
                                                                continueRating =
                                                                    s.rating;
                                                                continueRating5 =
                                                                    s.rating5based;
                                                                break;
                                                              }
                                                            }
                                                          }
                                                        } else {
                                                          final mid = model
                                                              .streamId
                                                              .trim();
                                                          if (mid
                                                              .isNotEmpty) {
                                                            for (final m
                                                                in movies) {
                                                              if ((m.streamId ??
                                                                          '')
                                                                      .trim() ==
                                                                  mid) {
                                                                continueRating =
                                                                    m.rating;
                                                                continueRating5 =
                                                                    m.rating5based;
                                                                break;
                                                              }
                                                            }
                                                            if (formatContentRating(
                                                                  continueRating,
                                                                  continueRating5,
                                                                ) ==
                                                                null) {
                                                              final detail =
                                                                  context
                                                                      .read<
                                                                        PrefetchCubit
                                                                      >()
                                                                      .peekMovieDetail(
                                                                        mid,
                                                                      );
                                                              if (detail !=
                                                                  null) {
                                                                continueRating =
                                                                    detail
                                                                        .info
                                                                        ?.rating;
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }

                                                      Future<void>
                                                      openContinue() async {
                                                        final watchingCubit =
                                                            context
                                                                .read<
                                                                  WatchingCubit
                                                                >();
                                                        final prefetch =
                                                            context
                                                                .read<
                                                                  PrefetchCubit
                                                                >();
                                                        UserModel?
                                                        serieUserAuth;
                                                        List<Episode?>?
                                                        serieSeasonEpisodes;
                                                        ChannelSerie?
                                                        channelSerie;
                                                        ChannelMovie?
                                                        channelMovie;

                                                        if (isSeries) {
                                                          final seriesId =
                                                              (model.seriesId ??
                                                                      '')
                                                                  .trim();
                                                          final authState =
                                                              context
                                                                  .read<
                                                                    AuthBloc
                                                                  >()
                                                                  .state;
                                                          if (authState
                                                              is AuthSuccess) {
                                                            serieUserAuth =
                                                                authState
                                                                    .user;
                                                          }
                                                          SerieDetails?
                                                          details;
                                                          if (seriesId
                                                              .isNotEmpty) {
                                                            details =
                                                                await prefetch
                                                                    .getSerieDetailCached(
                                                                      seriesId,
                                                                    );
                                                          }
                                                          serieSeasonEpisodes =
                                                              details
                                                                  ?.episodesInSameSeasonAs(
                                                                    model
                                                                        .streamId,
                                                                  );
                                                          channelSerie =
                                                              ChannelSerie(
                                                                seriesId:
                                                                    model
                                                                        .seriesId,
                                                                name:
                                                                    (model.seriesName ??
                                                                            '')
                                                                        .trim()
                                                                        .isNotEmpty
                                                                    ? model
                                                                        .seriesName
                                                                    : model
                                                                        .title,
                                                                cover:
                                                                    (model.seriesCover ??
                                                                            '')
                                                                        .trim()
                                                                        .isNotEmpty
                                                                    ? model
                                                                        .seriesCover
                                                                    : model
                                                                        .image,
                                                                rating:
                                                                    details
                                                                        ?.info
                                                                        ?.rating ??
                                                                    continueRating,
                                                                rating5based:
                                                                    details
                                                                        ?.info
                                                                        ?.rating5based ??
                                                                    continueRating5,
                                                                categoryId:
                                                                    details
                                                                        ?.info
                                                                        ?.categoryId,
                                                              );
                                                        } else {
                                                          final mid = model
                                                              .streamId
                                                              .trim();
                                                          String? movieCategoryId =
                                                              (model.categoryId ??
                                                                      '')
                                                                  .trim()
                                                                  .isNotEmpty
                                                              ? model
                                                                  .categoryId
                                                              : null;
                                                          ChannelMovie?
                                                          matchedRecent;
                                                          if (mid
                                                              .isNotEmpty) {
                                                            for (final m
                                                                in movies) {
                                                              if ((m.streamId ??
                                                                          '')
                                                                      .trim() ==
                                                                  mid) {
                                                                matchedRecent =
                                                                    m;
                                                                break;
                                                              }
                                                            }
                                                          }
                                                          movieCategoryId ??=
                                                              (matchedRecent
                                                                          ?.categoryId ??
                                                                      '')
                                                                  .trim()
                                                                  .isNotEmpty
                                                              ? matchedRecent!
                                                                  .categoryId
                                                              : null;

                                                          MovieDetail?
                                                          movieDetail;
                                                          if (mid
                                                              .isNotEmpty) {
                                                            movieDetail =
                                                                prefetch
                                                                    .peekMovieDetail(
                                                                      mid,
                                                                    );
                                                            if (movieDetail ==
                                                                    null ||
                                                                (movieCategoryId ??
                                                                        '')
                                                                    .trim()
                                                                    .isEmpty) {
                                                              movieDetail =
                                                                  await prefetch
                                                                      .getMovieDetailCached(
                                                                        mid,
                                                                      );
                                                            }
                                                          }
                                                          movieCategoryId ??=
                                                              (movieDetail
                                                                          ?.movieData
                                                                          ?.categoryId ??
                                                                      '')
                                                                  .trim()
                                                                  .isNotEmpty
                                                              ? movieDetail!
                                                                  .movieData!
                                                                  .categoryId
                                                              : null;

                                                          channelMovie =
                                                              ChannelMovie(
                                                                streamId:
                                                                    model
                                                                        .streamId,
                                                                name:
                                                                    matchedRecent
                                                                        ?.name ??
                                                                    model
                                                                        .title,
                                                                streamIcon:
                                                                    matchedRecent
                                                                        ?.streamIcon ??
                                                                    model
                                                                        .image,
                                                                rating:
                                                                    matchedRecent
                                                                        ?.rating ??
                                                                    continueRating,
                                                                rating5based:
                                                                    matchedRecent
                                                                        ?.rating5based ??
                                                                    continueRating5,
                                                                categoryId:
                                                                    movieCategoryId,
                                                                containerExtension:
                                                                    matchedRecent
                                                                        ?.containerExtension,
                                                                streamType:
                                                                    matchedRecent
                                                                        ?.streamType,
                                                              );
                                                        }

                                                        if (!context
                                                            .mounted) {
                                                          return;
                                                        }

                                                        final resolvedCategoryId =
                                                            channelMovie
                                                                ?.categoryId;

                                                        Get.to(
                                                          () => FullVideoScreen(
                                                            link:
                                                                model.stream,
                                                            title: isSeries
                                                                ? model.title
                                                                : displayTitle,
                                                            channelMovie:
                                                                channelMovie,
                                                            channelSerie:
                                                                channelSerie,
                                                            serieEpisodes:
                                                                serieSeasonEpisodes,
                                                            serieCurrentEpisodeId:
                                                                isSeries
                                                                    ? model
                                                                        .streamId
                                                                    : null,
                                                            serieUserAuth:
                                                                serieUserAuth,
                                                            initialPositionSeconds:
                                                                model.sliderValue >
                                                                        0
                                                                    ? model
                                                                        .sliderValue
                                                                    : null,
                                                            autoResume: true,
                                                          ),
                                                        )!.then((slider) {
                                                          if (!watchingPopMatchesOpenedStream(
                                                            slider,
                                                            model.streamId,
                                                          )) {
                                                            return;
                                                          }
                                                          final updated =
                                                              WatchingModel(
                                                            streamId: model
                                                                .streamId,
                                                            image:
                                                                model.image,
                                                            title:
                                                                model.title,
                                                            stream:
                                                                model.stream,
                                                            sliderValue:
                                                                (slider[0]
                                                                        as num)
                                                                    .toDouble(),
                                                            durationStrm:
                                                                slider.length >
                                                                        1
                                                                    ? (slider[1]
                                                                            as num)
                                                                        .toDouble()
                                                                    : model
                                                                        .durationStrm,
                                                            seriesId: model
                                                                .seriesId,
                                                            seriesName: model
                                                                .seriesName,
                                                            seriesCover: model
                                                                .seriesCover,
                                                            rating:
                                                                (model.rating ??
                                                                            '')
                                                                        .trim()
                                                                        .isNotEmpty
                                                                    ? model
                                                                        .rating
                                                                    : continueRating,
                                                            rating5based:
                                                                (model.rating5based ??
                                                                            '')
                                                                        .trim()
                                                                        .isNotEmpty
                                                                    ? model
                                                                        .rating5based
                                                                    : continueRating5,
                                                            categoryId:
                                                                (model.categoryId ??
                                                                            '')
                                                                        .trim()
                                                                        .isNotEmpty
                                                                    ? model
                                                                        .categoryId
                                                                    : resolvedCategoryId,
                                                          );
                                                          if (isSeries) {
                                                            watchingCubit
                                                                .addSerie(
                                                                  updated,
                                                                );
                                                          } else {
                                                            watchingCubit
                                                                .addMovie(
                                                                  updated,
                                                                );
                                                          }
                                                        });
                                                      }

                                                      return _HomePosterCard(
                                                        autofocus:
                                                            i == 0 &&
                                                            tv &&
                                                            heroRow == null,
                                                        isFirstInRow: i == 0,
                                                        isLastInRow:
                                                            !continueShowMore &&
                                                            i ==
                                                                continueVisibleCount -
                                                                    1,
                                                        tvLarge: tv,
                                                        posterWidth: posterW,
                                                        focusDebugLabel:
                                                            continueRow != null
                                                            ? _stvPosterLabel(
                                                                continueRow,
                                                                i,
                                                              )
                                                            : null,
                                                        title: displayTitle,
                                                        rating:
                                                            continueRating,
                                                        rating5based:
                                                            continueRating5,
                                                        contentKey: isSeries
                                                            ? 'series:${model.seriesId}'
                                                            : 'movie:${model.streamId}',
                                                        isSeries: isSeries,
                                                        showContentTypeBadge:
                                                            true,
                                                        imageUrl:
                                                            resolveImageUrl(
                                                              displayImage,
                                                              serverUrl,
                                                            ),
                                                        onTap: openContinue,
                                                      );
                                                    },
                                                  ),
                                                ),
                                                SizedBox(height: gap),
                                              ],
                                              if (!searchingHome ||
                                                  movies.isNotEmpty ||
                                                  moviesLoading)
                                              SizedBox(
                                                height: rowHeight,
                                                  child: _HomeContentRow(
                                                    title:
                                                        'home_latest_movies'.tr,
                                                    isLoading: moviesLoading,
                                                    showNoContent: searchingHome
                                                        ? false
                                                        : moviesShowNoContent,
                                                    tvStyle: tv,
                                                    posterWidth: posterW,
                                                    tvFocusRow: moviesRow,
                                                    itemCount: movies.length,
                                                  onShowMore: isDemo
                                                      ? null
                                                      : () => ParentalControlService
                                                            .instance
                                                            .navigateToProtectedRoute(
                                                              ParentalSection
                                                                  .movies,
                                                              screenMovieCategories,
                                                            ),
                                                  itemBuilder: (ctx, i) {
                                                    final model = movies[i];
                                                      return _HomePosterCard(
                                                        autofocus:
                                                            i == 0 &&
                                                            tv &&
                                                            !hasContinue &&
                                                            heroRow == null,
                                                        focusNode: i == 0
                                                            ? firstMovieFocusNode
                                                            : null,
                                                        isFirstInRow: i == 0,
                                                        isLastInRow: false,
                                                        tvLarge: tv,
                                                        posterWidth: posterW,
                                                        focusDebugLabel:
                                                            _stvPosterLabel(
                                                              moviesRow,
                                                              i,
                                                            ),
                                                        title: model.name ?? '',
                                                      rating: model.rating,
                                                      rating5based:
                                                          model.rating5based,
                                                      contentKey: isDemo
                                                          ? null
                                                          : 'movie:${model.streamId ?? ''}',
                                                      assetImage: isDemo
                                                          ? kDemoPosterAsset
                                                          : null,
                                                      imageUrl: isDemo
                                                          ? ''
                                                          : resolveImageUrl(
                                                              model
                                                                  .streamIcon,
                                                              serverUrl,
                                                            ),
                                                      onTap: isDemo
                                                          ? onDemoTap
                                                          : () {
                                                              final id =
                                                                  model
                                                                      .streamId ??
                                                                  '';
                                                              if (id
                                                                  .isNotEmpty) {
                                                                context
                                                                    .read<
                                                                      PrefetchCubit
                                                                    >()
                                                                    .getMovieDetailCached(
                                                                      id,
                                                                    );
                                                              }
                                                              Get.to(
                                                                () => MovieContent(
                                                                  channelMovie:
                                                                      model,
                                                                  videoId: id,
                                                                ),
                                                              );
                                                            },
                                                    );
                                                  },
                                                ),
                                              ),
                                              if (!searchingHome ||
                                                  series.isNotEmpty ||
                                                  seriesLoading) ...[
                                              SizedBox(height: gap),
                                              SizedBox(
                                                height: rowHeight,
                                                  child: _HomeContentRow(
                                                    title:
                                                        'home_latest_series'.tr,
                                                    isLoading: seriesLoading,
                                                    showNoContent: searchingHome
                                                        ? false
                                                        : seriesShowNoContent,
                                                    tvStyle: tv,
                                                    posterWidth: posterW,
                                                    tvFocusRow: seriesRow,
                                                    itemCount: series.length,
                                                  onShowMore: isDemo
                                                      ? null
                                                      : () => ParentalControlService
                                                            .instance
                                                            .navigateToProtectedRoute(
                                                              ParentalSection
                                                                  .series,
                                                              screenSeriesCategories,
                                                            ),
                                                  itemBuilder: (ctx, i) {
                                                    final model = series[i];
                                                      return _HomePosterCard(
                                                        isFirstInRow: i == 0,
                                                        isLastInRow: false,
                                                        tvLarge: tv,
                                                        posterWidth: posterW,
                                                        focusDebugLabel:
                                                            _stvPosterLabel(
                                                              seriesRow,
                                                              i,
                                                            ),
                                                        title: model.name ?? '',
                                                        rating: model.rating,
                                                        rating5based:
                                                            model.rating5based,
                                                        contentKey: isDemo
                                                            ? null
                                                            : 'series:${model.seriesId ?? ''}',
                                                        isSeries: !isDemo,
                                                      assetImage: isDemo
                                                          ? kDemoPosterAsset
                                                          : null,
                                                      imageUrl: isDemo
                                                          ? ''
                                                          : resolveImageUrl(
                                                              model.cover,
                                                              serverUrl,
                                                            ),
                                                      onTap: isDemo
                                                          ? onDemoTap
                                                          : () {
                                                              final id =
                                                                  model
                                                                      .seriesId ??
                                                                  '';
                                                              if (id
                                                                  .isNotEmpty) {
                                                                context
                                                                    .read<
                                                                      PrefetchCubit
                                                                    >()
                                                                    .getSerieDetailCached(
                                                                      id,
                                                                    );
                                                              }
                                                              Get.to(
                                                                () => SerieContent(
                                                                  channelSerie:
                                                                      model,
                                                                  videoId: id,
                                                                ),
                                                              );
                                                            },
                                                    );
                                                  },
                                                ),
                                              ),
                                              ],
                                              if (tv) ...[
                                                if (!searchingHome ||
                                                    recentMovies.isNotEmpty ||
                                                    moviesLoading) ...[
                                                SizedBox(height: gap),
                                                SizedBox(
                                                  height: rowHeight,
                                                    child: _HomeContentRow(
                                                      title:
                                                          'recently_added_movies'
                                                              .tr,
                                                      isLoading: moviesLoading,
                                                      showNoContent:
                                                          searchingHome
                                                          ? false
                                                          : (fetchComplete &&
                                                              recentMovies
                                                                  .isEmpty),
                                                      tvStyle: true,
                                                      posterWidth: posterW,
                                                      tvFocusRow:
                                                          recentMoviesRow,
                                                      itemCount:
                                                          recentMovies.length,
                                                    onShowMore: isDemo
                                                        ? null
                                                        : () => ParentalControlService
                                                              .instance
                                                              .navigateToProtectedRoute(
                                                                ParentalSection
                                                                    .movies,
                                                                screenMovieCategories,
                                                              ),
                                                    itemBuilder: (ctx, i) {
                                                      final model =
                                                          recentMovies[i];
                                                        return _HomePosterCard(
                                                          isFirstInRow: i == 0,
                                                          isLastInRow: false,
                                                          tvLarge: true,
                                                          posterWidth: posterW,
                                                          focusDebugLabel:
                                                              recentMoviesRow !=
                                                                      null
                                                              ? _stvPosterLabel(
                                                                  recentMoviesRow,
                                                                  i,
                                                                )
                                                              : null,
                                                          title:
                                                              model.name ?? '',
                                                          rating: model.rating,
                                                          rating5based: model
                                                              .rating5based,
                                                          contentKey:
                                                              'movie:${model.streamId ?? ''}',
                                                          imageUrl:
                                                              resolveImageUrl(
                                                                model
                                                                    .streamIcon,
                                                                serverUrl,
                                                              ),
                                                          onTap: () {
                                                            final id =
                                                                model.streamId ??
                                                                '';
                                                            if (id
                                                                .isNotEmpty) {
                                                              context
                                                                  .read<
                                                                    PrefetchCubit
                                                                  >()
                                                                  .getMovieDetailCached(
                                                                    id,
                                                                  );
                                                            }
                                                            Get.to(
                                                              () => MovieContent(
                                                                channelMovie:
                                                                    model,
                                                                videoId: id,
                                                              ),
                                                            );
                                                          },
                                                        );
                                                    },
                                                  ),
                                                ),
                                                ],
                                                if (!searchingHome ||
                                                    recentSeries.isNotEmpty ||
                                                    seriesLoading) ...[
                                                SizedBox(height: gap),
                                                SizedBox(
                                                  height: rowHeight,
                                                    child: _HomeContentRow(
                                                      title:
                                                          'recently_added_series'
                                                              .tr,
                                                      isLoading: seriesLoading,
                                                      showNoContent:
                                                          searchingHome
                                                          ? false
                                                          : (fetchComplete &&
                                                              recentSeries
                                                                  .isEmpty),
                                                      tvStyle: true,
                                                      posterWidth: posterW,
                                                      tvFocusRow:
                                                          recentSeriesRow,
                                                      itemCount:
                                                          recentSeries.length,
                                                    onShowMore: isDemo
                                                        ? null
                                                        : () => ParentalControlService
                                                              .instance
                                                              .navigateToProtectedRoute(
                                                                ParentalSection
                                                                    .series,
                                                                screenSeriesCategories,
                                                              ),
                                                    itemBuilder: (ctx, i) {
                                                      final model =
                                                          recentSeries[i];
                                                        return _HomePosterCard(
                                                          isFirstInRow: i == 0,
                                                          isLastInRow: false,
                                                          tvLarge: true,
                                                          posterWidth: posterW,
                                                          focusDebugLabel:
                                                              recentSeriesRow !=
                                                                      null
                                                              ? _stvPosterLabel(
                                                                  recentSeriesRow,
                                                                  i,
                                                                )
                                                              : null,
                                                          title:
                                                              model.name ?? '',
                                                          rating: model.rating,
                                                          rating5based: model
                                                              .rating5based,
                                                          contentKey:
                                                              'series:${model.seriesId ?? ''}',
                                                          isSeries: true,
                                                          imageUrl:
                                                              resolveImageUrl(
                                                                model.cover,
                                                                serverUrl,
                                                              ),
                                                          onTap: () {
                                                            final id =
                                                                model.seriesId ??
                                                                '';
                                                            if (id
                                                                .isNotEmpty) {
                                                              context
                                                                  .read<
                                                                    PrefetchCubit
                                                                  >()
                                                                  .getSerieDetailCached(
                                                                    id,
                                                                  );
                                                            }
                                                            Get.to(
                                                              () => SerieContent(
                                                                channelSerie:
                                                                    model,
                                                                videoId: id,
                                                              ),
                                                            );
                                                          },
                                                        );
                                                    },
                                                  ),
                                                ),
                                                ],
                                              ],
                                              if (tv && tvBottomPad > 0)
                                                SizedBox(height: tvBottomPad),
                                            ],
                                          ),
                                        ),
                                        if (showColdStartLoader)
                                          const _HomeCenteredLoader(),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            if (!tv && !isDemo) const _HomeExpiryFooter(),
                            if (!tv) SizedBox(height: 0.6.h),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    },
  );

  if (hideTvTopBar) return body;
  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (bool didPop, dynamic result) {
      if (!didPop) WelcomeScreen._showAppExitConfirm(Get.context!);
    },
    child: body,
  );
}

/// صفحة فارغة خاصة ببحث الرئيسية (مثل Smart TV home-feed-empty).
class _HomeTopSearchEmptyPanel extends StatelessWidget {
  const _HomeTopSearchEmptyPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: Colors.white.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              'empty'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'home_search_empty_hint'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
