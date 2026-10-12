part of '../screens.dart';

class SeriesCategoriesScreen extends StatefulWidget {
  const SeriesCategoriesScreen({super.key, this.embeddedInTvShell = false});

  /// داخل شلّ التلفزيون: بدون AppBar هاتف، تحت الشريط الثابت.
  final bool embeddedInTvShell;

  @override
  State<SeriesCategoriesScreen> createState() => SeriesCategoriesScreenState();
}

class SeriesCategoriesScreenState extends State<SeriesCategoriesScreen>
    with LandscapeMainAppStateMixin<SeriesCategoriesScreen>, ParentalSectionGateMixin {
  @override
  ParentalSection get parentalGateSection => ParentalSection.series;

  @override
  bool get skipParentalGateOnInit => widget.embeddedInTvShell;

  /// تركيز ريموت على الفئة المحددة / الأولى (شلّ التلفزيون).
  bool focusPrimaryCategory() {
    return _categoryListKey.currentState?.focusSelected() ?? false;
  }

  /// بعد إغلاق كlavier البحث العلوي: أول نتيجة، وإلا أول فئة.
  void focusAfterTopSearch() {
    void go() {
      if (!mounted) return;
      if (keySearch.isNotEmpty && _hasGlobalSearchHits()) {
        _lastGlobalSearchFocusIndex = 0;
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_searchResultFocusNode.canRequestFocus) {
            _searchResultFocusNode.requestFocus();
          }
        });
        return;
      }
      focusPrimaryCategory();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    });
  }

  bool _hasGlobalSearchHits() {
    if (keySearch.isEmpty) return false;
    final catalog = _globalSearchCatalog ?? const <ChannelSerie>[];
    final list = _filterAdultSeries(
      catalog
          .where(
            (e) =>
                validIptvContentId(e.seriesId) != null &&
                (e.name ?? '').toLowerCase().contains(keySearch),
          )
          .toList(),
    );
    return list.isNotEmpty;
  }

  final ScrollController _gridScrollController = ScrollController();
  final FocusNode _categoriesListFocusNode = FocusNode();
  final FocusNode _categorySearchNavFocus = FocusNode();
  final FocusNode _searchResultFocusNode = FocusNode();
  final GlobalKey<AppBarSeriesState> _seriesAppBarKey =
      GlobalKey<AppBarSeriesState>();
  final GlobalKey<CatalogCategoryListState> _categoryListKey =
      GlobalKey<CatalogCategoryListState>();
  bool _hideButton = true;
  String keySearch = "";
  int? _lastGlobalSearchFocusIndex;
  String _categorySearch = "";
  String? _selectedCategoryId;
  /// عرض مجزّأ لفئة «الكل» فقط — أول 25 ثم المزيد عند الاقتراب من النهاية.
  static const int _allPageSize = 25;
  int _allVisibleCount = _allPageSize;
  List<String> _persistedCatOrder = const [];
  bool _catOrderLoaded = false;
  AllCatalogSort _allSort = AllCatalogSort.all;
  List<ChannelSerie>? _allSortedCache;
  List<ChannelSerie>? _allSortedSource;
  AllCatalogSort? _allSortedMode;
  final Map<AllCatalogSort, List<ChannelSerie>> _allSortPrefetch = {};
  List<ChannelSerie>? _allSortPrefetchSource;
  int _allSortPrefetchGen = 0;
  int _catalogSoftRetryGen = 0;
  int _catalogSoftRetryCount = 0;
  bool _catalogSoftRetryInFlight = false;
  bool _seriesEmptyCatsRefetchQueued = false;
  bool _tvInitialCategoryFocusDone = false;

  /// بحث عام عبر كل الفئات (كتالوج `__all__`).
  List<ChannelSerie>? _globalSearchCatalog;
  bool _globalSearchLoading = false;
  int _globalSearchVisibleCount = _allPageSize;
  String? _posterPrecacheKey;
  static int get _posterPrecacheLimit =>
      AppPerf.instance.isTelevisionLike ? 8 : 16;

  void _maybePrecacheSeriesPosters(
    List<ChannelSerie> list,
    String? serverUrl,
  ) {
    final key = '$_selectedCategoryId:${list.length}';
    if (_posterPrecacheKey == key || list.isEmpty) return;
    _posterPrecacheKey = key;
    final urls = <String>[];
    for (final s in list.take(_posterPrecacheLimit)) {
      final u = resolveImageUrl(s.cover, serverUrl);
      if (u.isNotEmpty) urls.add(u);
    }
    unawaited(
      precacheIptvPosters(
        context,
        urls,
        limit: _posterPrecacheLimit,
        decodeIntoMemory: false,
        concurrency: AppPerf.instance.imageConcurrentFetches.clamp(2, 6),
      ),
    );
  }

  void _resetCatalogSoftRetry() {
    _catalogSoftRetryGen++;
    _catalogSoftRetryCount = 0;
    _catalogSoftRetryInFlight = false;
  }

  /// أول فتح لـ All قد يصل Success فارغ قبل اكتمال الشبكة — أبقِ التحميل وأعد المحاولة.
  void _softRetryAllIfEmpty({required String allId}) {
    if (_selectedCategoryId != allId) return;
    if (_catalogSoftRetryInFlight || _catalogSoftRetryCount >= 2) return;
    final selected = _selectedCategoryId;
    if (selected == null) return;
    final gen = _catalogSoftRetryGen;
    _catalogSoftRetryInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted || gen != _catalogSoftRetryGen) return;
        if (_selectedCategoryId != selected) return;
        final bloc = context.read<ChannelsBloc>();
        final cached = bloc.seriesListForCategoryId(allId);
        if (cached != null && cached.isNotEmpty) {
          setState(() {});
          return;
        }
        if (bloc.isFullSeriesCatalogLoading) {
          _catalogSoftRetryCount++;
          final warmed = await bloc.ensureFullSeriesCatalog();
          if (!mounted || gen != _catalogSoftRetryGen) return;
          if (_selectedCategoryId != selected) return;
          if (warmed.isNotEmpty) {
            bloc.add(
              GetLiveChannelsEvent(
                typeCategory: TypeCategory.series,
                catyId: selected,
              ),
            );
          }
          return;
        }
        _catalogSoftRetryCount++;
        final warmed = await bloc.ensureFullSeriesCatalog();
        if (!mounted || gen != _catalogSoftRetryGen) return;
        if (_selectedCategoryId != selected) return;
        if (warmed.isNotEmpty) {
          bloc.add(
            GetLiveChannelsEvent(
              typeCategory: TypeCategory.series,
              catyId: selected,
            ),
          );
          return;
        }
        if (_catalogSoftRetryCount < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (!mounted || gen != _catalogSoftRetryGen) return;
          if (_selectedCategoryId != selected) return;
          bloc.add(
            GetLiveChannelsEvent(
              typeCategory: TypeCategory.series,
              catyId: selected,
            ),
          );
        }
      } finally {
        if (gen == _catalogSoftRetryGen) {
          _catalogSoftRetryInFlight = false;
        }
      }
    });
  }

  List<ChannelSerie> _sortedAllSeries(List<ChannelSerie> source) {
    // فلتر «الكل»: بدون أي فرز — ترتيب الجلب كما هو (ليس newest).
    if (_allSort == AllCatalogSort.all) {
      _allSortedCache = null;
      _allSortedMode = null;
      _kickAllSortPrefetch(source);
      return source;
    }
    if (identical(_allSortPrefetchSource, source)) {
      final prefetched = _allSortPrefetch[_allSort];
      if (prefetched != null) return prefetched;
    }
    if (identical(_allSortedSource, source) &&
        _allSortedMode == _allSort &&
        _allSortedCache != null) {
      return _allSortedCache!;
    }
    final sorted = sortAllCatalogList<ChannelSerie>(
      source: source,
      sort: _allSort,
      nameOf: (s) => s.name,
      timestampOf: (s) => s.sortTimestamp,
      ratingOf: (s) => allCatalogParseRating(s.rating, s.rating5based),
    );
    _allSortedSource = source;
    _allSortedMode = _allSort;
    _allSortedCache = sorted;
    _allSortPrefetch[_allSort] = sorted;
    _kickAllSortPrefetch(source);
    return sorted;
  }

  void _kickAllSortPrefetch(List<ChannelSerie> source) {
    if (identical(_allSortPrefetchSource, source) &&
        _allSortPrefetch.length >= AllCatalogSort.values.length - 1) {
      return;
    }
    final alreadyForSource = identical(_allSortPrefetchSource, source);
    if (!alreadyForSource) {
      _allSortPrefetch.clear();
      _allSortPrefetchSource = source;
    }
    final gen = ++_allSortPrefetchGen;
    Future<void>(() async {
      for (final sort in AllCatalogSort.values) {
        if (sort == AllCatalogSort.all) continue;
        if (!mounted || gen != _allSortPrefetchGen) return;
        if (_allSortPrefetch.containsKey(sort) &&
            identical(_allSortPrefetchSource, source)) {
          continue;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (!mounted || gen != _allSortPrefetchGen) return;
        if (!identical(_allSortPrefetchSource, source)) return;
        final sorted = sortAllCatalogList<ChannelSerie>(
          source: source,
          sort: sort,
          nameOf: (s) => s.name,
          timestampOf: (s) => s.sortTimestamp,
          ratingOf: (s) => allCatalogParseRating(s.rating, s.rating5based),
        );
        if (!mounted || gen != _allSortPrefetchGen) return;
        if (!identical(_allSortPrefetchSource, source)) return;
        _allSortPrefetch[sort] = sorted;
      }
    });
  }

  void _onAllSortChanged(AllCatalogSort sort) {
    if (_allSort == sort) return;
    setState(() {
      _allSort = sort;
      _allSortedCache = null;
      _allSortedMode = null;
      _allVisibleCount = _allPageSize;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_gridScrollController.hasClients) {
        _gridScrollController.jumpTo(0);
      }
    });
  }

  String _catalogOrderAccountId() {
    final active = SavedAccountsRepository.activeAccountId?.trim();
    if (active != null && active.isNotEmpty) return active;
    try {
      final auth = context.read<AuthBloc>().state;
      if (auth is AuthSuccess) {
        final url = auth.user.serverInfo?.serverUrl ?? '';
        final user = auth.user.userInfo?.username ?? '';
        if (url.isNotEmpty && user.isNotEmpty) {
          return SavedAccountsRepository.accountIdFor(url, user);
        }
      }
    } catch (_) {}
    return 'default';
  }

  void _ensureSeriesCatOrderLoaded() {
    if (_catOrderLoaded) return;
    _catOrderLoaded = true;
    _persistedCatOrder = CatalogCategoryOrderStore.load(
      CatalogOrderKind.series,
      _catalogOrderAccountId(),
    );
  }

  void _persistSeriesCatOrder(List<String> ids) {
    _persistedCatOrder = List<String>.from(ids);
    CatalogCategoryOrderStore.save(
      CatalogOrderKind.series,
      _catalogOrderAccountId(),
      ids,
    );
    setState(() {});
  }

  Future<void> _ensureGlobalSeriesSearchCatalog() async {
    if (_globalSearchCatalog != null && _globalSearchCatalog!.isNotEmpty) {
      return;
    }
    final cached =
        context.read<ChannelsBloc>().seriesListForCategoryId('__all__');
    if (cached != null && cached.isNotEmpty) {
      if (!mounted) return;
      setState(() => _globalSearchCatalog = cached);
      return;
    }
    if (_globalSearchLoading) return;
    setState(() => _globalSearchLoading = true);
    try {
      final list =
          await context.read<ChannelsBloc>().ensureFullSeriesCatalog();
      if (!mounted) return;
      setState(() {
        _globalSearchCatalog = list;
        _globalSearchLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _globalSearchLoading = false);
    }
  }

  int _seriesCategoryCount(
    String? id,
    ChannelsBloc bloc,
    WatchingState watch,
  ) {
    if (id == '__watched__') {
      final seen = <String>{};
      var n = 0;
      for (final w in watch.series) {
        final sid = (w.seriesId ?? '').trim();
        if (sid.isEmpty || !seen.add(sid)) continue;
        n++;
      }
      return n;
    }
    if (id == null || id.isEmpty) return 0;
    return bloc.seriesCountForCategoryId(id);
  }

  void _selectSeriesCategory({
    required CategoryModel cat,
    required String allId,
    required String watchedId,
  }) {
    final id = cat.categoryId ?? '';
    if (id.isEmpty || id == _selectedCategoryId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_gridScrollController.hasClients) {
        _gridScrollController.jumpTo(0);
      }
    });
    setState(() {
      _selectedCategoryId = id;
      _allVisibleCount = _allPageSize;
      if (id == allId) _resetCatalogSoftRetry();
    });
    if (id == watchedId) return;
    final bloc = context.read<ChannelsBloc>();
    final cached = bloc.seriesListForCategoryId(id);
    if (cached != null && cached.isNotEmpty) return;
    bloc.add(
      GetLiveChannelsEvent(
        typeCategory: TypeCategory.series,
        catyId: id,
      ),
    );
  }

  void _onSeriesAppBarSearch(String value) {
    final q = value.toLowerCase().trim();
    setState(() {
      keySearch = q;
      if (q.isNotEmpty) {
        _globalSearchVisibleCount = _allPageSize;
      }
    });
    if (q.isNotEmpty) {
      unawaited(_ensureGlobalSeriesSearchCatalog());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_gridScrollController.hasClients) {
        _gridScrollController.jumpTo(0);
      }
    });
  }

  void _onTopNavSearch() {
    if (!mounted || !widget.embeddedInTvShell) return;
    _onSeriesAppBarSearch(kSmartTvTopSearchQuery.value);
  }

  List<CategoryModel> _seriesParentalCategories() {
    final st = context.read<SeriesCatyBloc>().state;
    return st is SeriesCatySuccess ? st.categories : const <CategoryModel>[];
  }

  String? _seriesParentalCategoryName(String? categoryId) {
    return ParentalControlService.categoryNameFromId(
      categoryId,
      _seriesParentalCategories(),
    );
  }

  List<ChannelSerie> _filterAdultSeries(List<ChannelSerie> series) {
    return ParentalControlService.instance.filterAdultSeries(
      series,
      categoryNameForId: _seriesParentalCategoryName,
    );
  }

  Future<void> _openSerieContent(
    ChannelSerie model, {
    int? searchIndex,
  }) async {
    final fromSearch = searchIndex != null && keySearch.isNotEmpty;
    if (fromSearch) {
      _lastGlobalSearchFocusIndex = searchIndex;
      _seriesAppBarKey.currentState?.collapseSearchKeepQuery();
    }
    final parental = ParentalControlService.instance;
    if (parental.isAdultSerie(
      model,
      categoryName: _seriesParentalCategoryName(model.categoryId),
    )) {
      final ok = await parental.requestAdultContentAccess(context);
      if (!ok || !mounted) return;
    }
    final id = validIptvContentId(model.seriesId);
    if (id == null) return;
    final detail =
        await context.read<PrefetchCubit>().getSerieDetailCached(id);
    if (!mounted) return;
    await Get.to(
      () => SerieContent(
        channelSerie: model,
        videoId: id,
        preloadedDetail: detail,
      ),
    );
    if (!mounted || !fromSearch) return;
    _scheduleGlobalSearchFocusRestore();
  }

  void _scheduleGlobalSearchFocusRestore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_searchResultFocusNode.canRequestFocus) {
        _searchResultFocusNode.requestFocus();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchResultFocusNode.requestFocus();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.embeddedInTvShell) {
      kSmartTvTopSearchQuery.addListener(_onTopNavSearch);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WatchingCubit>().initialData();
      context.read<ChannelsBloc>().ensureCatalogCounts();
      if (widget.embeddedInTvShell &&
          kSmartTvTopSearchQuery.value.trim().isNotEmpty) {
        _onSeriesAppBarSearch(kSmartTvTopSearchQuery.value);
      }
    });
    _gridScrollController.addListener(() {
      if (!_gridScrollController.hasClients || !mounted) return;
      final dir = _gridScrollController.position.userScrollDirection;
      final next =
          dir == ScrollDirection.reverse
              ? false
              : dir == ScrollDirection.forward
              ? true
              : _hideButton;
      if (next != _hideButton) {
        setState(() => _hideButton = next);
      }
    });
  }

  @override
  void dispose() {
    if (widget.embeddedInTvShell) {
      kSmartTvTopSearchQuery.removeListener(_onTopNavSearch);
    }
    _gridScrollController.dispose();
    _categoriesListFocusNode.dispose();
    _categorySearchNavFocus.dispose();
    _searchResultFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embeddedInTvShell) {
      return _buildScreen(context);
    }
    return buildWithParentalGate(_buildScreen(context));
  }

  Widget _buildScreen(BuildContext context) {
    final embedded = widget.embeddedInTvShell;
    return Scaffold(
      backgroundColor: embedded ? Colors.transparent : null,
      floatingActionButton: Visibility(
        visible: !_hideButton,
        child: FloatingActionButton(
          onPressed: () {
            _gridScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.ease,
            );
            setState(() => _hideButton = true);
          },
          backgroundColor: kColorPrimaryDark,
          child: const Icon(FontAwesomeIcons.chevronUp, color: Colors.white),
        ),
      ),
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Ink(
            width: double.infinity,
            height: embedded ? double.infinity : 100.h,
            decoration: kDecorBackground,
            child: SafeArea(
              top: false,
              bottom: false,
              left: false,
              right: false,
              child: Column(
                children: [
                  if (!embedded)
                    AppBarSeries(
                      key: _seriesAppBarKey,
                      top: 3.h,
                      onSearch: _onSeriesAppBarSearch,
                      opaque: true,
                    ),
                  Expanded(
                    child: BlocBuilder<SettingsCubit, SettingsState>(
                      buildWhen: (prev, curr) => prev.isDemo != curr.isDemo,
                      builder: (context, stateSett) {
                        return BlocBuilder<SeriesCatyBloc, SeriesCatyState>(
                          buildWhen: (prev, curr) {
                            if (prev.runtimeType != curr.runtimeType) {
                              return true;
                            }
                            if (prev is SeriesCatySuccess &&
                                curr is SeriesCatySuccess) {
                              return !identical(
                                prev.categories,
                                curr.categories,
                              );
                            }
                            return prev != curr;
                          },
                          builder: (context, state) {
                            if (!stateSett.isDemo &&
                                state is SeriesCatyInitial) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                context.read<SeriesCatyBloc>().add(
                                  GetSeriesCategories(),
                                );
                              });
                              return const CatalogGridBusyPanel();
                            }

                            if (!stateSett.isDemo &&
                                state is SeriesCatySuccess &&
                                state.categories.isEmpty &&
                                !_seriesEmptyCatsRefetchQueued) {
                              _seriesEmptyCatsRefetchQueued = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                context.read<SeriesCatyBloc>().add(
                                  GetSeriesCategories(),
                                );
                              });
                            }

                            if (state is SeriesCatyLoading) {
                              return const CatalogGridBusyPanel();
                            }

                            final List<CategoryModel> apiCategories =
                                ParentalControlService.instance
                                    .filterAdultCategories(
                                  state is SeriesCatySuccess
                                      ? state.categories
                                      : [
                                        if (stateSett.isDemo)
                                          CategoryModel(
                                            categoryId: kDemoCategoryId,
                                            categoryName: demoSidebarTitle(),
                                          ),
                                      ],
                                );

                            const watchedId = kCatalogWatchedCategoryId;
                            const allId = kCatalogAllCategoryId;
                            const recentId = kRecentlyAddedCategoryId;
                            _ensureSeriesCatOrderLoaded();
                            final orderedApi = CatalogCategoryOrderStore.apply(
                              apiCategories,
                              _persistedCatOrder,
                            );
                            final leftList =
                                stateSett.isDemo
                                    ? <CategoryModel>[
                                      CategoryModel(
                                        categoryName: demoSidebarTitle(),
                                        categoryId: kDemoCategoryId,
                                      ),
                                    ]
                                    : <CategoryModel>[
                                      CategoryModel(
                                        categoryName: 'category_all'.tr,
                                        categoryId: allId,
                                      ),
                                      CategoryModel(
                                        categoryName: 'watched'.tr,
                                        categoryId: watchedId,
                                      ),
                                      CategoryModel(
                                        categoryName: 'recently_added'.tr,
                                        categoryId: recentId,
                                      ),
                                      ...orderedApi,
                                    ];

                            // التركيز الابتدائي على أول فئة حقيقية من السيرفر
                            if (stateSett.isDemo && _selectedCategoryId == null) {
                              _selectedCategoryId = kDemoCategoryId;
                            } else if (!stateSett.isDemo &&
                                _selectedCategoryId == null) {
                              if (apiCategories.isNotEmpty) {
                                final firstReal = apiCategories.first;
                                final firstId = firstReal.categoryId ?? '';
                                _selectedCategoryId = firstId;
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (!mounted || firstId.isEmpty) return;
                                  context.read<ChannelsBloc>().add(
                                    GetLiveChannelsEvent(
                                      typeCategory: TypeCategory.series,
                                      catyId: firstId,
                                    ),
                                  );
                                });
                              } else {
                                _selectedCategoryId = allId;
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (!mounted) return;
                                  context.read<ChannelsBloc>().add(
                                    GetLiveChannelsEvent(
                                      typeCategory: TypeCategory.series,
                                      catyId: allId,
                                    ),
                                  );
                                });
                              }
                            }

                            final filteredCategories =
                                _categorySearch.isEmpty
                                    ? leftList
                                    : leftList
                                        .where(
                                          (c) => (c.categoryName ?? '')
                                              .toLowerCase()
                                              .contains(_categorySearch),
                                        )
                                        .toList();

                            if (!_tvInitialCategoryFocusDone &&
                                filteredCategories.isNotEmpty &&
                                _selectedCategoryId != null) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted || _tvInitialCategoryFocusDone) {
                                  return;
                                }
                                if (!isTv(context)) {
                                  _tvInitialCategoryFocusDone = true;
                                  return;
                                }
                                final ok =
                                    _categoryListKey.currentState
                                        ?.focusSelected() ??
                                    false;
                                if (ok) {
                                  _tvInitialCategoryFocusDone = true;
                                } else {
                                  // عقد التركيز لم تُبنَ بعد — أعد المحاولة مرة
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (!mounted ||
                                        _tvInitialCategoryFocusDone) {
                                      return;
                                    }
                                    if (_categoryListKey.currentState
                                            ?.focusSelected() ==
                                        true) {
                                      _tvInitialCategoryFocusDone = true;
                                    }
                                  });
                                }
                              });
                            }

                            final width = MediaQuery.of(context).size.width;
                            final crossAxisCount = width >= 1200 ? 6 : 5;

                            return Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    6,
                                    8,
                                    10,
                                  ),
                                  child: SizedBox(
                                    width: 320,
                                    child: CatalogCategoryPane(
                                      search: CategorySidebarSearchField(
                                        compact: true,
                                        navFocusNode: _categorySearchNavFocus,
                                        onNavArrowDown: () {
                                          _categoryListKey.currentState
                                              ?.focusFirst();
                                        },
                                        onNavArrowUp: () {
                                          if (widget.embeddedInTvShell) {
                                            _stvSetActiveShellTab(
                                              SmartTvShellTab.series,
                                            );
                                            _stvFocusShellTab(
                                              SmartTvShellTab.series,
                                            );
                                          }
                                        },
                                        onChanged: (value) {
                                          setState(() {
                                            _categorySearch = value;
                                          });
                                        },
                                        onBecameEmpty: () {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                if (!mounted) return;
                                                _categoryListKey.currentState
                                                    ?.focusFirst();
                                              });
                                        },
                                      ),
                                      list: BlocBuilder<
                                        ChannelsBloc,
                                        ChannelsState
                                      >(
                                        builder: (context, _) {
                                          return BlocBuilder<
                                            WatchingCubit,
                                            WatchingState
                                          >(
                                            builder: (context, watchState) {
                                              final channelsBloc = context
                                                  .read<ChannelsBloc>();
                                              return CatalogCategoryList(
                                                key: _categoryListKey,
                                                categories:
                                                    filteredCategories,
                                                selectedId: _selectedCategoryId,
                                                listFocusNode:
                                                    _categoriesListFocusNode,
                                                pinnedCount: stateSett.isDemo
                                                    ? 0
                                                    : 3,
                                                enableReorder:
                                                    !stateSett.isDemo &&
                                                    _categorySearch.isEmpty,
                                                onPersistOrder:
                                                    _persistSeriesCatOrder,
                                                onArrowUpFromFirst: () {
                                                  _categorySearchNavFocus
                                                      .requestFocus();
                                                },
                                                countsListenable:
                                                    channelsBloc.catalogCounts,
                                                countOf: (id) =>
                                                    _seriesCategoryCount(
                                                      id,
                                                      channelsBloc,
                                                      watchState,
                                                    ),
                                                onCommit: (cat) =>
                                                    _selectSeriesCategory(
                                                      cat: cat,
                                                      allId: allId,
                                                      watchedId: watchedId,
                                                    ),
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child:
                                      stateSett.isDemo
                                          ? DemoCategoryGrid(
                                            crossAxisCount: crossAxisCount,
                                            childAspectRatio: 0.7,
                                            scrollController:
                                                _gridScrollController,
                                          )
                                          : keySearch.isNotEmpty
                                          ? _buildGlobalSeriesSearchPanel(
                                            crossAxisCount: crossAxisCount,
                                          )
                                          : _selectedCategoryId == watchedId
                                          ? BlocBuilder<
                                            WatchingCubit,
                                            WatchingState
                                          >(
                                            buildWhen: (prev, curr) =>
                                                !identical(
                                                  prev.series,
                                                  curr.series,
                                                ),
                                            builder: (context, watchState) {
                                              final watchedSeries =
                                                  watchState.series
                                                      .where(
                                                        (w) =>
                                                            (w.seriesId ?? '')
                                                                .isNotEmpty,
                                                      )
                                                      .toList();
                                              final seenIds = <String>{};
                                              final list = <ChannelSerie>[];
                                              for (final w in watchedSeries) {
                                                final sid = w.seriesId!;
                                                if (seenIds.contains(sid)) {
                                                  continue;
                                                }
                                                seenIds.add(sid);
                                                list.add(
                                                  ChannelSerie(
                                                    seriesId: sid,
                                                    name:
                                                        w.seriesName ?? w.title,
                                                    cover:
                                                        w.seriesCover ??
                                                        w.image,
                                                  ),
                                                );
                                              }
                                              final filteredList =
                                                  _filterAdultSeries(list);
                                              if (filteredList.isEmpty) {
                                                return Center(
                                                  child: Text(
                                                    'no_series'.tr,
                                                    style: Get
                                                        .textTheme
                                                        .titleMedium!
                                                        .copyWith(
                                                          color: Colors.white70,
                                                        ),
                                                  ),
                                                );
                                              }
                                              return Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      10,
                                                      6,
                                                      10,
                                                      10,
                                                    ),
                                                child: GridView.builder(
                                                  controller:
                                                      _gridScrollController,
                                                  cacheExtent: kCatalogCacheExtent,
                                                  addAutomaticKeepAlives: false,
                                                  addSemanticIndexes: false,
                                                  itemCount: filteredList.length,
                                                  gridDelegate:
                                                      SliverGridDelegateWithFixedCrossAxisCount(
                                                        crossAxisCount:
                                                            crossAxisCount,
                                                        crossAxisSpacing: 10,
                                                        mainAxisSpacing: 10,
                                                        childAspectRatio: .7,
                                                      ),
                                                  itemBuilder: (_, i) {
                                                    final model = filteredList[i];
                                                    final authState = context.read<AuthBloc>().state;
                                                    final serverUrl = authState is AuthSuccess
                                                        ? authState.user.serverInfo?.serverUrl
                                                        : null;
                                                    return RepaintBoundary(
                                                      child: CardChannelMovieItem(
                                                        title: model.name,
                                                        image: model.cover,
                                                        serverUrl: serverUrl,
                                                        rating: model.rating,
                                                        rating5based: model.rating5based,
                                                        contentKey: 'series:${model.seriesId ?? ''}',
                                                        isSeries: true,
                                                        onTap: () =>
                                                            unawaited(
                                                          _openSerieContent(
                                                            model,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              );
                                            },
                                          )
                                          : BlocBuilder<
                                            ChannelsBloc,
                                            ChannelsState
                                          >(
                                            buildWhen: (prev, curr) {
                                              if (prev.runtimeType !=
                                                  curr.runtimeType) {
                                                return true;
                                              }
                                              if (prev
                                                      is ChannelsSeriesSuccess &&
                                                  curr
                                                      is ChannelsSeriesSuccess) {
                                                return prev.categoryId !=
                                                        curr.categoryId ||
                                                    !identical(
                                                      prev.channels,
                                                      curr.channels,
                                                    );
                                              }
                                              return prev != curr;
                                            },
                                            builder: (context, state) {
                                              final isAllSelected =
                                                  _selectedCategoryId == allId;
                                              final selectedId =
                                                  _selectedCategoryId ?? '';
                                              final bloc = context
                                                  .read<ChannelsBloc>();
                                              List<ChannelSerie> channels =
                                                  const [];
                                              if (selectedId.isNotEmpty &&
                                                  selectedId != watchedId) {
                                                final cached = bloc
                                                    .seriesListForCategoryId(
                                                      selectedId,
                                                    );
                                                if (cached != null &&
                                                    cached.isNotEmpty) {
                                                  channels = cached;
                                                }
                                              }

                                              if (channels.isEmpty) {
                                                if (state is ChannelsLoading) {
                                                  return CatalogGridBusyPanel(
                                                    crossAxisCount:
                                                        crossAxisCount,
                                                  );
                                                }
                                                if (state
                                                    is ChannelsSeriesSuccess) {
                                                  if (isAllSelected) {
                                                    if (state.categoryId ==
                                                        allId) {
                                                      channels = state.channels;
                                                    } else {
                                                      final cached = bloc
                                                          .seriesListForCategoryId(
                                                            allId,
                                                          );
                                                      if (cached != null &&
                                                          cached.isNotEmpty) {
                                                        channels = cached;
                                                      } else {
                                                        return CatalogGridBusyPanel(
                                                          crossAxisCount:
                                                              crossAxisCount,
                                                        );
                                                      }
                                                    }
                                                  } else if (state.categoryId ==
                                                          selectedId ||
                                                      selectedId.isEmpty) {
                                                    channels = state.channels;
                                                  } else {
                                                    final cached = bloc
                                                        .seriesListForCategoryId(
                                                          selectedId,
                                                        );
                                                    if (cached != null) {
                                                      channels = cached;
                                                    } else {
                                                      return CatalogGridBusyPanel(
                                                        crossAxisCount:
                                                            crossAxisCount,
                                                      );
                                                    }
                                                  }
                                                } else if (isAllSelected) {
                                                  final cached = bloc
                                                      .seriesListForCategoryId(
                                                        allId,
                                                      );
                                                  if (cached != null &&
                                                      cached.isNotEmpty) {
                                                    channels = cached;
                                                  } else {
                                                    WidgetsBinding.instance
                                                        .addPostFrameCallback((
                                                          _,
                                                        ) {
                                                      if (!mounted) return;
                                                      if (_selectedCategoryId !=
                                                          allId) {
                                                        return;
                                                      }
                                                      bloc.add(
                                                        GetLiveChannelsEvent(
                                                          typeCategory:
                                                              TypeCategory
                                                                  .series,
                                                          catyId: allId,
                                                        ),
                                                      );
                                                    });
                                                    return CatalogGridBusyPanel(
                                                      crossAxisCount:
                                                          crossAxisCount,
                                                    );
                                                  }
                                                } else if (selectedId
                                                        .isNotEmpty &&
                                                    selectedId != watchedId) {
                                                  final cached = bloc
                                                      .seriesListForCategoryId(
                                                        selectedId,
                                                      );
                                                  if (cached != null) {
                                                    channels = cached;
                                                  } else {
                                                    WidgetsBinding.instance
                                                        .addPostFrameCallback((
                                                          _,
                                                        ) {
                                                      if (!mounted) return;
                                                      if (_selectedCategoryId !=
                                                          selectedId) {
                                                        return;
                                                      }
                                                      bloc.add(
                                                        GetLiveChannelsEvent(
                                                          typeCategory:
                                                              TypeCategory
                                                                  .series,
                                                          catyId: selectedId,
                                                        ),
                                                      );
                                                    });
                                                    return CatalogGridBusyPanel(
                                                      crossAxisCount:
                                                          crossAxisCount,
                                                    );
                                                  }
                                                }
                                              }

                                              final list = _filterAdultSeries(
                                                isAllSelected
                                                    ? _sortedAllSeries(
                                                      channels,
                                                    )
                                                    : channels,
                                              );

                                              if (list.isEmpty) {
                                                if (isAllSelected &&
                                                    _catalogSoftRetryCount <
                                                        2) {
                                                  _softRetryAllIfEmpty(
                                                    allId: allId,
                                                  );
                                                  return CatalogGridBusyPanel(
                                                    crossAxisCount:
                                                        crossAxisCount,
                                                  );
                                                }
                                                return Center(
                                                  child: Text(
                                                    'no_series_in_category'.tr,
                                                    style: Get
                                                        .textTheme
                                                        .titleMedium!
                                                        .copyWith(
                                                          color: Colors.white70,
                                                        ),
                                                  ),
                                                );
                                              }

                                              final visibleCount =
                                                  isAllSelected
                                                      ? (_allVisibleCount >
                                                              list.length
                                                          ? list.length
                                                          : _allVisibleCount)
                                                      : list.length;

                                              final authState =
                                                  context.read<AuthBloc>().state;
                                              final serverUrl =
                                                  authState is AuthSuccess
                                                      ? authState
                                                          .user
                                                          .serverInfo
                                                          ?.serverUrl
                                                      : null;
                                              _maybePrecacheSeriesPosters(
                                                list,
                                                serverUrl,
                                              );

                                              return Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      10,
                                                      6,
                                                      10,
                                                      10,
                                                    ),
                                                child: Column(
                                                  children: [
                                                    if (isAllSelected)
                                                      AllCatalogSortBar(
                                                        value: _allSort,
                                                        onChanged:
                                                            _onAllSortChanged,
                                                      ),
                                                    Expanded(
                                                      child: NotificationListener<
                                                        ScrollNotification
                                                      >(
                                                        onNotification: (n) {
                                                          if (!isAllSelected) {
                                                            return false;
                                                          }
                                                          if (n
                                                                  is! ScrollUpdateNotification &&
                                                              n
                                                                  is! OverscrollNotification) {
                                                            return false;
                                                          }
                                                          final m = n.metrics;
                                                          if (m.extentAfter <
                                                                  800 &&
                                                              _allVisibleCount <
                                                                  list.length) {
                                                            setState(() {
                                                              final next =
                                                                  _allVisibleCount +
                                                                  _allPageSize;
                                                              _allVisibleCount =
                                                                  next >
                                                                          list.length
                                                                      ? list.length
                                                                      : next;
                                                            });
                                                          }
                                                          return false;
                                                        },
                                                        child: CatalogGridWithAds(
                                                          controller:
                                                              _gridScrollController,
                                                          cacheExtent:
                                                              kCatalogCacheExtent,
                                                          itemCount:
                                                              visibleCount,
                                                          crossAxisCount:
                                                              crossAxisCount,
                                                          crossAxisSpacing: 10,
                                                          mainAxisSpacing: 10,
                                                          childAspectRatio: .7,
                                                          firstRowsPerBanner: 5,
                                                          rowsStep: 1,
                                                          itemBuilder: (_, i) {
                                                            final model =
                                                                list[i];
                                                            final authState =
                                                                context
                                                                    .read<
                                                                      AuthBloc
                                                                    >()
                                                                    .state;
                                                            final serverUrl =
                                                                authState
                                                                        is AuthSuccess
                                                                    ? authState
                                                                        .user
                                                                        .serverInfo
                                                                        ?.serverUrl
                                                                    : null;
                                                            return RepaintBoundary(
                                                              child: CardChannelMovieItem(
                                                                title:
                                                                    model.name,
                                                                image:
                                                                    model.cover,
                                                                serverUrl:
                                                                    serverUrl,
                                                                rating:
                                                                    model
                                                                        .rating,
                                                                rating5based:
                                                                    model
                                                                        .rating5based,
                                                                contentKey:
                                                                    'series:${model.seriesId ?? ''}',
                                                                isSeries: true,
                                                                onTap: () =>
                                                                    unawaited(
                                                                  _openSerieContent(
                                                                    model,
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalSeriesSearchPanel({required int crossAxisCount}) {
    if (_globalSearchLoading &&
        (_globalSearchCatalog == null || _globalSearchCatalog!.isEmpty)) {
      return CatalogGridBusyPanel(crossAxisCount: crossAxisCount);
    }

    final catalog = _globalSearchCatalog ?? const <ChannelSerie>[];
    final list = _filterAdultSeries(
      catalog
          .where(
            (e) =>
                validIptvContentId(e.seriesId) != null &&
                (e.name ?? '').toLowerCase().contains(keySearch),
          )
          .toList(),
    );

    if (list.isEmpty) {
      return Center(
        child: Text(
          'no_series'.tr,
          style: Get.textTheme.titleMedium!.copyWith(color: Colors.white70),
        ),
      );
    }

    final visibleCount =
        _globalSearchVisibleCount > list.length
            ? list.length
            : _globalSearchVisibleCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is! ScrollUpdateNotification &&
              n is! OverscrollNotification) {
            return false;
          }
          final m = n.metrics;
          if (m.extentAfter < 800 &&
              _globalSearchVisibleCount < list.length) {
            setState(() {
              final next = _globalSearchVisibleCount + _allPageSize;
              _globalSearchVisibleCount =
                  next > list.length ? list.length : next;
            });
          }
          return false;
        },
        child: GridView.builder(
          controller: _gridScrollController,
          cacheExtent: kCatalogCacheExtent,
          addAutomaticKeepAlives: false,
          addSemanticIndexes: false,
          itemCount: visibleCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: .7,
          ),
          itemBuilder: (_, i) {
            final model = list[i];
            final authState = context.read<AuthBloc>().state;
            final serverUrl =
                authState is AuthSuccess
                    ? authState.user.serverInfo?.serverUrl
                    : null;
            return RepaintBoundary(
              child: CardChannelMovieItem(
                title: model.name,
                image: model.cover,
                serverUrl: serverUrl,
                rating: model.rating,
                rating5based: model.rating5based,
                contentKey: 'series:${model.seriesId ?? ''}',
                isSeries: true,
                focusNode:
                    i == (_lastGlobalSearchFocusIndex ?? 0)
                        ? _searchResultFocusNode
                        : null,
                onTap:
                    () => unawaited(
                      _openSerieContent(model, searchIndex: i),
                    ),
              ),
            );
          },
        ),
      ),
    );
  }
}
