part of '../screens.dart';

extension _FullVideoIptvOverlayUi on _FullVideoScreenState {
  bool _iptvIsFavoritesCategory(String? id) =>
      id == kIptvFavoritesCategoryId;

  bool _iptvIsRecentlyWatchedCategory(String? id) =>
      id == kIptvRecentlyWatchedCategoryId;

  bool _iptvIsPinnedLiveCategory(String? id) => isIptvPinnedLiveCategory(id);

  int get _iptvPinnedLiveCategoryCount => 2;

  /// Category that owns the currently playing live channel.
  String? _iptvPlayingCategoryId() {
    if (_iptvIsFavoritesCategory(_iptvPickCategoryId)) {
      return kIptvFavoritesCategoryId;
    }
    if (_iptvIsRecentlyWatchedCategory(_iptvPickCategoryId)) {
      return kIptvRecentlyWatchedCategoryId;
    }
    final playing = _currentLiveChannel ?? widget.channelLive;
    if (playing == null) return _iptvActiveCategoryId;
    final catId = playing.categoryId?.trim();
    if (catId != null && catId.isNotEmpty) return catId;
    final sid = playing.streamId?.trim();
    if (sid != null && sid.isNotEmpty) {
      final inFav = context.read<FavoritesCubit>().state.lives.any(
        (l) => l.streamId?.trim() == sid,
      );
      if (inFav) return kIptvFavoritesCategoryId;
      _iptvEnsureRecentlyWatchedLoaded();
      if (_iptvRecentlyWatched.any((l) => l.streamId?.trim() == sid)) {
        return kIptvRecentlyWatchedCategoryId;
      }
    }
    return _iptvActiveCategoryId;
  }

  int _iptvCategoryIndexForId(String? id, List<CategoryModel> displayCats) {
    if (id == null || id.isEmpty || displayCats.isEmpty) return 0;
    final i = displayCats.indexWhere((c) => c.categoryId == id);
    return i >= 0 ? i : 0;
  }

  bool get _iptvIsTvCategoryReordering => _iptvTvReorderIndex != null;

  List<CategoryModel> _iptvFilterCategoriesForSearch(
    List<CategoryModel> display,
  ) {
    final q = _iptvCategorySearch.trim().toLowerCase();
    if (q.isEmpty) return display;
    return display
        .where((c) => (c.categoryName ?? '').toLowerCase().contains(q))
        .toList();
  }

  /// القائمة الظاهرة حالياً (بعد البحث). فهارس التركيز تشير لهنا، ليس للقائمة الكاملة.
  List<CategoryModel> _iptvVisibleCategories([List<CategoryModel>? raw]) {
    final List<CategoryModel> rawCats;
    if (raw != null) {
      rawCats = raw;
    } else {
      final st = context.read<LiveCatyBloc>().state;
      rawCats = st is LiveCatySuccess ? st.categories : <CategoryModel>[];
    }
    return _iptvFilterCategoriesForSearch(_iptvDisplayCategories(rawCats));
  }

  void _iptvFocusFirstVisibleCategory() {
    if (_iptvCategorySearchHasFocus() &&
        _iptvCategorySearchEditFocus.hasFocus &&
        MediaQuery.viewInsetsOf(context).bottom > 40) {
      return;
    }
    if (_iptvCategoryFocusNodes.isEmpty) return;
    _iptvRequestFocusNow(_iptvCategoryFocusNodes[0]);
  }

  /// من أول فئة → خانة البحث (خارج FocusScope ديال اللائحة كان كيمنع التركيز).
  void _iptvFocusCategorySearch() {
    if (!mounted || !_showLiveIptvOverlay) return;
    if (_iptvIsTvCategoryReordering) return;
    _iptvFocusMoveToChannelsPending = false;
    _iptvOverlayFocusOnChannelsColumn = false;
    _iptvOverlayFocusOnMiniPlayer = false;
    _iptvCancelChannelFocusSchedules();
    _iptvRestoreFocusTimer?.cancel();
    _iptvRestoreFocusTimer = null;
    _iptvCategorySearchNavFocus.canRequestFocus = true;
    try {
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {}
    _iptvRequestFocusNow(_iptvCategorySearchNavFocus);
  }

  String _liveCategoryOrderAccountId() {
    final active = SavedAccountsRepository.activeAccountId?.trim();
    if (active != null && active.isNotEmpty) return active;
    if (!mounted) return 'default';
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

  void _iptvEnsureCategoryOrderLoaded() {
    if (_iptvCatOrderLoaded) return;
    _iptvCatOrderLoaded = true;
    _iptvPersistedCatOrder = LiveCategoryOrderStore.load(
      _liveCategoryOrderAccountId(),
    );
  }

  void _iptvEnsureRecentlyWatchedLoaded() {
    if (_iptvRecentlyWatchedLoaded) return;
    _iptvRecentlyWatchedLoaded = true;
    _iptvRecentlyWatched = LiveRecentlyWatchedStore.load(
      _liveCategoryOrderAccountId(),
    );
  }

  List<CategoryModel> _iptvDisplayCategories(List<CategoryModel> raw) {
    _iptvEnsureCategoryOrderLoaded();
    _iptvEnsureRecentlyWatchedLoaded();
    final order = _iptvTvReorderWorkingIds ?? _iptvPersistedCatOrder;
    final filtered = ParentalControlService.instance.filterAdultCategories(raw);
    final ordered = LiveCategoryOrderStore.apply(filtered, order);
    return [
      CategoryModel(
        categoryId: kIptvFavoritesCategoryId,
        categoryName: 'favourites'.tr,
      ),
      CategoryModel(
        categoryId: kIptvRecentlyWatchedCategoryId,
        categoryName: 'recently_watched'.tr,
      ),
      ...ordered,
    ];
  }

  int _iptvCategoryCountFor(
    String? id,
    FavoritesState favState,
    ChannelsBloc channelsBloc,
  ) {
    if (_iptvIsFavoritesCategory(id)) return favState.lives.length;
    if (_iptvIsRecentlyWatchedCategory(id)) {
      _iptvEnsureRecentlyWatchedLoaded();
      return _iptvRecentlyWatched.length;
    }
    if (id == null || id.isEmpty) return 0;
    // الكاش الحي أولاً — حتى تظهر أعداد أول الفئات فور اكتمال تدفئتها.
    final list = channelsBloc.liveListForCategoryId(id);
    if (list != null) return list.length;
    final cached = _iptvCategoryChannelCounts[id];
    if (cached != null && cached > 0) return cached;
    return 0;
  }

  String? _iptvCategoryThumbFor(String? id, ChannelsBloc channelsBloc) {
    if (_iptvIsPinnedLiveCategory(id)) return null;
    if (id == null || id.isEmpty) return null;
    final stored = _iptvCategoryThumbUrls[id];
    if (stored != null && stored.isNotEmpty) return stored;
    final list = channelsBloc.liveListForCategoryId(id);
    if (list == null || list.isEmpty) return null;
    for (final ch in list) {
      final icon = ch.streamIcon?.trim();
      if (icon != null && icon.isNotEmpty && icon.toLowerCase() != 'null') {
        return icon;
      }
    }
    return null;
  }

  String? _iptvParentalCategoryName(String? categoryId) {
    final st = context.read<LiveCatyBloc>().state;
    final cats = st is LiveCatySuccess ? st.categories : const <CategoryModel>[];
    return ParentalControlService.categoryNameFromId(categoryId, cats);
  }

  List<ChannelLive> _iptvFilterAdultChannels(List<ChannelLive> channels) {
    return ParentalControlService.instance.filterAdultLiveChannels(
      channels,
      categoryNameForId: _iptvParentalCategoryName,
    );
  }

  List<ChannelLive> _iptvResolveChannelsForActive(
    ChannelsBloc channelsBloc,
    ChannelsState chState,
    FavoritesState favState,
  ) {
    final activeId = _iptvActiveCategoryId ?? '';
    if (_iptvIsFavoritesCategory(activeId)) {
      return _iptvFilterAdultChannels(favState.lives);
    }
    if (_iptvIsRecentlyWatchedCategory(activeId)) {
      _iptvEnsureRecentlyWatchedLoaded();
      return _iptvFilterAdultChannels(_iptvRecentlyWatched);
    }
    final cached = channelsBloc.liveListForCategoryId(activeId);
    if (cached != null) return _iptvFilterAdultChannels(cached);
    // لا تُرجع قنوات فئة أخرى بالخطأ.
    if (chState is ChannelsLiveSuccess && chState.categoryId == activeId) {
      return _iptvFilterAdultChannels(chState.channels);
    }
    return const [];
  }

  bool _iptvIsChannelsLoadingForActive(
    ChannelsBloc channelsBloc,
    ChannelsState chState,
  ) {
    final activeId = _iptvActiveCategoryId ?? '';
    if (_iptvIsPinnedLiveCategory(activeId)) return false;
    final cached = channelsBloc.liveListForCategoryId(activeId);
    if (cached != null && cached.isNotEmpty) return false;
    // فقط جلب هذه الفئة — لا تعتمد على ChannelsLoading العام (فئة أخرى).
    if (channelsBloc.isLiveFetchInFlight(activeId)) return true;
    if (chState is ChannelsLiveSuccess && chState.categoryId == activeId) {
      return false;
    }
    if (cached != null) return false;
    return true;
  }

  void _iptvSeedCategoryMetaFromCache() {
    final liveState = context.read<LiveCatyBloc>().state;
    if (liveState is! LiveCatySuccess) return;
    final channelsBloc = context.read<ChannelsBloc>();
    var changed = false;
    for (final cat in liveState.categories) {
      final id = cat.categoryId;
      if (id == null || id.isEmpty) continue;
      final list = channelsBloc.liveListForCategoryId(id);
      if (list == null) continue;
      // حتى القائمة الفارغة المخزّنة تُسجَّل حتى لا تُعاد محاولة بلا نهاية.
      if ((_iptvCategoryChannelCounts[id] ?? -1) != list.length) {
        _iptvCategoryChannelCounts[id] = list.length;
        changed = true;
      }
      if (list.isEmpty) continue;
      for (final ch in list) {
        final icon = ch.streamIcon?.trim();
        if (icon == null || icon.isEmpty || icon.toLowerCase() == 'null') {
          continue;
        }
        if (_iptvCategoryThumbUrls[id] != icon) {
          _iptvCategoryThumbUrls[id] = icon;
          changed = true;
        }
        break;
      }
    }
    if (changed && mounted) _iptvScheduleCategoryMetaRebuild();
  }

  Future<void> _iptvPrefetchUncachedCategoryMeta() async {
    if (_iptvMetaPrefetchStarted) return;
    _iptvMetaPrefetchStarted = true;

    // نفس مسار التدفئة الهادئ بعد الرئيسية — لا يجلب بقوة من هنا.
    LiveCatalogWarmService.instance.ensureStarted(
      channels: context.read<ChannelsBloc>(),
      liveCaty: context.read<LiveCatyBloc>(),
    );

    // حدّث الصور/العدد من الكاش كلما امتلأ — بدون طلبات شبكة إضافية.
    // أول ثوانٍ أسرع حتى تظهر أعداد أول ~11 فئة فور جهوزيتها.
    for (var i = 0; i < 160; i++) {
      if (!mounted || !_showLiveIptvOverlay) return;
      _iptvSeedCategoryMetaFromCache();
      if (LiveCatalogWarmService.instance.hasCompletedOnce &&
          !LiveCatalogWarmService.instance.isRunning) {
        _iptvSeedCategoryMetaFromCache();
        return;
      }
      if (LiveCatalogWarmService.instance.hasPriorityDone) {
        _iptvSeedCategoryMetaFromCache();
      }
      final delayMs = i < 20 ? 250 : 700;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }

  String _iptvActiveCategoryTitle(List<CategoryModel> displayCats) {
    if (_iptvIsFavoritesCategory(_iptvActiveCategoryId)) {
      return 'favourites'.tr;
    }
    for (final c in displayCats) {
      if (c.categoryId == _iptvActiveCategoryId) {
        return sanitizeDisplayTitle(c.categoryName);
      }
    }
    return '';
  }

  void _iptvRememberCategoryCount(String? id, int count) {
    if (id == null || id.isEmpty || _iptvIsPinnedLiveCategory(id)) return;
    if (_iptvCategoryChannelCounts[id] == count) return;
    _iptvCategoryChannelCounts[id] = count;
    _iptvScheduleCategoryMetaRebuild();
  }

  void _iptvScheduleCategoryMetaRebuild() {
    if (!_showLiveIptvOverlay) return;
    _iptvMetaSetStateTimer?.cancel();
    _iptvMetaSetStateTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _showLiveIptvOverlay) _scheduleFullVideoRebuild();
    });
  }

  void _iptvRememberCategoryThumb(String? id, List<ChannelLive> channels) {
    if (id == null || id.isEmpty || _iptvIsPinnedLiveCategory(id)) return;
    if (channels.isEmpty) return;
    for (final ch in channels) {
      final icon = ch.streamIcon?.trim();
      if (icon == null || icon.isEmpty || icon.toLowerCase() == 'null') {
        continue;
      }
      if (_iptvCategoryThumbUrls[id] == icon) return;
      _iptvCategoryThumbUrls[id] = icon;
      _iptvScheduleCategoryMetaRebuild();
      return;
    }
  }

  Widget _buildIptvCategoryPanelColumn() {
    return BlocBuilder<FavoritesCubit, FavoritesState>(
      builder: (context, favState) {
        return BlocBuilder<ChannelsBloc, ChannelsState>(
          builder: (context, _) {
            final channelsBloc = context.read<ChannelsBloc>();
            return BlocBuilder<LiveCatyBloc, LiveCatyState>(
              builder: (context, state) {
            if (state is LiveCatyLoading || state is LiveCatyInitial) {
              return LiveBrowserPanelShell(
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: kColorPrimary,
                    ),
                  ),
                ),
              );
            }

            final rawCats =
                state is LiveCatySuccess ? state.categories : <CategoryModel>[];
            final categories = _iptvFilterCategoriesForSearch(
              _iptvDisplayCategories(rawCats),
            );
            final n = categories.length;

            // أثناء البناء: وسّع عقد التركيز إن لزم حتى تظهر كل الفئات
            // (لا تقطع اللائحة بـ usableN < n — كان يخفي الفئات التحتية).
            if (n > _iptvCategoryFocusNodes.length) {
              final old = _iptvCategoryFocusNodes;
              _iptvCategoryFocusNodes = List.generate(n, (i) {
                if (i < old.length) return old[i];
                final node = FocusNode(debugLabel: 'iptv_cat_$i');
                node.addListener(() => _onIptvCategoryNodeFocused(i));
                return node;
              });
            } else if (n != _iptvCategoryFocusNodes.length) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (categories.length != n) return;
                _iptvResyncCategoryFocusNodes(n);
              });
            }

            final usableN = n;

            final authState = context.read<AuthBloc>().state;
            final serverUrl = authState is AuthSuccess
                ? authState.user.serverInfo?.serverUrl
                : null;

            final tvLayout = isTvDevice(context);
            return LiveBrowserPanelShell(
              header: LiveBrowserCategoriesHeader(
                onBack: _exitLiveBrowserToHome,
                backFocusNode: tvLayout ? _iptvCategoriesBackFocusNode : null,
                onBackKeyEvent: tvLayout
                    ? (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        final key = event.logicalKey;
                        _touchLiveIptvOverlayActivity();
                        if (key == LogicalKeyboardKey.enter ||
                            key == LogicalKeyboardKey.numpadEnter ||
                            key == LogicalKeyboardKey.select ||
                            key == LogicalKeyboardKey.space) {
                          _exitLiveBrowserToHome();
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowDown) {
                          _iptvCategorySearchNavFocus.canRequestFocus = true;
                          _iptvRequestFocusNow(_iptvCategorySearchNavFocus);
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowRight) {
                          if (_iptvCategoryFocusNodes.isNotEmpty) {
                            final ix = _iptvLastCategoryFocusIndex.clamp(
                              0,
                              _iptvCategoryFocusNodes.length - 1,
                            );
                            _iptvRequestFocusNow(_iptvCategoryFocusNodes[ix]);
                          } else {
                            _iptvCategorySearchNavFocus.canRequestFocus = true;
                            _iptvRequestFocusNow(_iptvCategorySearchNavFocus);
                          }
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      }
                    : null,
                statusText: _iptvIsTvCategoryReordering
                    ? 'live_cat_reorder_hint_tv'.tr
                    : null,
              ),
              // البحث خارج FocusScope (مثل الأفلام) حتى لا يُسرق تركيز TextField.
              child: _buildIptvCategoryList(
                categories: categories,
                n: usableN,
                favState: favState,
                channelsBloc: channelsBloc,
                serverUrl: serverUrl,
                tvLayout: tvLayout,
              ),
            );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildIptvCategoryList({
    required List<CategoryModel> categories,
    required int n,
    required FavoritesState favState,
    required ChannelsBloc channelsBloc,
    required String? serverUrl,
    required bool tvLayout,
  }) {
    Widget itemBuilder(BuildContext context, int i) {
      return _buildIptvCategoryRowItem(
        i: i,
        n: n,
        c: categories[i],
        node: _iptvCategoryFocusNodes[i],
        favState: favState,
        channelsBloc: channelsBloc,
        serverUrl: serverUrl,
        enablePhoneDrag: !tvLayout,
      );
    }

    final list = tvLayout
        ? ListView.builder(
            controller: _iptvCategoryScrollController,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            clipBehavior: Clip.hardEdge,
            cacheExtent: kListCacheExtent,
            itemExtent: _kIptvCatRowHeight,
            itemCount: n,
            itemBuilder: itemBuilder,
          )
        : ReorderableListView.builder(
            scrollController: _iptvCategoryScrollController,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            clipBehavior: Clip.hardEdge,
            cacheExtent: kListCacheExtent,
            itemExtent: _kIptvCatRowHeight,
            itemCount: n,
            buildDefaultDragHandles: false,
            onReorder: _iptvOnPhoneCategoriesReorder,
            onReorderStart: (_) {
              if (_iptvCategorySearch.trim().isNotEmpty) return;
              _touchLiveIptvOverlayActivity();
              try {
                HapticFeedback.mediumImpact();
              } catch (_) {}
            },
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final t = Curves.easeOutCubic.transform(animation.value);
                  return Material(
                    color: Colors.transparent,
                    elevation: 10 * t,
                    shadowColor: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(9),
                    child: Transform.scale(scale: 1 + 0.035 * t, child: child),
                  );
                },
              );
            },
            itemBuilder: itemBuilder,
          );

    if (_iptvIsTvCategoryReordering) {
      return list;
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: CategorySidebarSearchField(
            compact: true,
            navFocusNode: tvLayout ? _iptvCategorySearchNavFocus : null,
            editFocusNode: _iptvCategorySearchEditFocus,
            onChanged: (value) {
              _fvSetState(() {
                _iptvCategorySearch = value;
              });
              _iptvLastCategoryFocusIndex = 0;
              _iptvJumpScrollToStart(_iptvCategoryScrollController);
            },
            onBecameEmpty: () {
              if (_iptvCategorySearchEditFocus.hasFocus) return;
              if (MediaQuery.viewInsetsOf(context).bottom > 40) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_iptvCategorySearchEditFocus.hasFocus) return;
                _iptvFocusFirstVisibleCategory();
              });
            },
            onNavArrowDown: _iptvFocusFirstVisibleCategory,
            onNavArrowUp: () {
              _iptvCategoriesBackFocusNode.canRequestFocus = true;
              _iptvRequestFocusNow(_iptvCategoriesBackFocusNode);
            },
            onTvKeyboardOpenChanged: (open) {
              _iptvTvSearchKeyboardOpen = open;
              if (open) {
                _iptvRestoreFocusTimer?.cancel();
                _iptvRestoreFocusTimer = null;
              }
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: list),
      ],
    );
    // نفس النطاق: بحث + فئات — وإلا السهم لفوق ما يخرجش من اللائحة.
    if (tvLayout) return FocusScope(child: column);
    return column;
  }

  Widget _buildIptvCategoryRowItem({
    required int i,
    required int n,
    required CategoryModel c,
    required FocusNode node,
    required FavoritesState favState,
    required ChannelsBloc channelsBloc,
    required String? serverUrl,
    required bool enablePhoneDrag,
  }) {
    final isFav = _iptvIsFavoritesCategory(c.categoryId);
    final isRecent = _iptvIsRecentlyWatchedCategory(c.categoryId);
    final isPinned = isFav || isRecent;
    final count = _iptvCategoryCountFor(c.categoryId, favState, channelsBloc);
    final thumbUrl = _iptvCategoryThumbFor(c.categoryId, channelsBloc);
    Widget row = RepaintBoundary(
      child: Focus(
        focusNode: node,
        onKeyEvent: (fn, ev) => _iptvCategoryItemOnKey(i, n, ev),
        child: ListenableBuilder(
          listenable: node,
          builder: (context, _) {
            final focused = node.hasFocus;
            final isActive =
                (_iptvActiveCategoryId ?? '') ==
                (c.categoryId ?? '').toString();
            return LiveBrowserCategoryRow(
              title: sanitizeDisplayTitle(c.categoryName),
              count: count,
              isFavorites: isFav,
              isRecentlyWatched: isRecent,
              isActive: isActive,
              focused: focused,
              isReorderTarget: _iptvTvReorderIndex == i,
              showDragHandle: !isPinned,
              serverUrl: serverUrl,
              thumbUrl: thumbUrl,
              flatOnPage: true,
              onTap: () {
                _touchLiveIptvOverlayActivity();
                if (_iptvIsTvCategoryReordering) {
                  if (_iptvTvReorderIndex == i) {
                    _iptvCommitTvCategoryReorder();
                  }
                  return;
                }
                _iptvUserSelectCategory(c.categoryId);
                node.requestFocus();
              },
            );
          },
        ),
      ),
    );
    if (enablePhoneDrag) {
      row = ReorderableDelayedDragStartListener(
        index: i,
        enabled: !isPinned && _iptvCategorySearch.trim().isEmpty,
        child: row,
      );
    }
    return KeyedSubtree(
      key: ValueKey('live_cat_${c.categoryId ?? i}'),
      child: row,
    );
  }

  Widget _buildIptvChannelsPanelColumn(UserModel userAuth) {
    final authState = context.read<AuthBloc>().state;
    final serverUrl = authState is AuthSuccess
        ? authState.user.serverInfo?.serverUrl
        : null;

    return BlocBuilder<FavoritesCubit, FavoritesState>(
      builder: (context, favState) {
        return BlocBuilder<LiveCatyBloc, LiveCatyState>(
          builder: (context, catState) {
            final rawCats = catState is LiveCatySuccess
                ? catState.categories
                : <CategoryModel>[];
            final displayCats = _iptvDisplayCategories(rawCats);

            return BlocBuilder<ChannelsBloc, ChannelsState>(
              builder: (context, chState) {
                final channelsBloc = context.read<ChannelsBloc>();
                final channels = _iptvResolveChannelsForActive(
                  channelsBloc,
                  chState,
                  favState,
                );
                final listFetching = _iptvIsChannelsLoadingForActive(
                  channelsBloc,
                  chState,
                );

                if (channels.isNotEmpty &&
                    _iptvActiveCategoryId != null &&
                    !_iptvIsFavoritesCategory(_iptvActiveCategoryId)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _iptvRememberCategoryCount(
                      _iptvActiveCategoryId,
                      channels.length,
                    );
                    _iptvRememberCategoryThumb(
                      _iptvActiveCategoryId,
                      channels,
                    );
                  });
                }

                return _buildIptvChannelsListBody(
                  userAuth: userAuth,
                  serverUrl: serverUrl,
                  channels: channels,
                  listFetching: listFetching,
                  displayCats: displayCats,
                  favState: favState,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildIptvChannelsListBody({
    required UserModel userAuth,
    required String? serverUrl,
    required List<ChannelLive> channels,
    required bool listFetching,
    required List<CategoryModel> displayCats,
    required FavoritesState favState,
  }) {
    final catKey = _iptvActiveCategoryId ?? '';
    final channelSyncReady =
        channels.length == _iptvChannelFocusNodes.length &&
        catKey == _iptvChannelFocusBoundCategoryId;

    if (!channelSyncReady) {
      if (channels.isNotEmpty) {
        // جهّز عقد التركيز فوراً حتى تظهر القائمة بدون spinner.
        _iptvEnsureChannelFocusNodesSynced(channels, catKey);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _iptvResyncChannelFocusNodes(channels, categoryKey: catKey);
        });
        return LiveBrowserPanelShell(
          header: LiveBrowserChannelPanelHeader(
            title: _iptvActiveCategoryTitle(displayCats),
            count: channels.length,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (listFetching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: kColorPrimary,
                    backgroundColor: Colors.white10,
                  ),
                ),
              const Expanded(
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    if (listFetching && channels.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showLiveIptvOverlay) return;
        if (!context.read<ChannelsBloc>().isLiveFetchInFlight(
              _iptvActiveCategoryId ?? '',
            )) {
          return;
        }
        _iptvRefocusCategoryWhileChannelsEmptyLoading();
      });
    }

    if (channels.isEmpty) {
      return LiveBrowserPanelShell(
        header: LiveBrowserChannelPanelHeader(
          title: _iptvActiveCategoryTitle(displayCats),
          count: 0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (listFetching)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: kColorPrimary,
                  backgroundColor: Colors.white10,
                ),
              ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    listFetching
                        ? 'loading'.tr
                        : (_iptvIsFavoritesCategory(_iptvActiveCategoryId)
                            ? 'fav_no_channels'.tr
                            : (_iptvIsRecentlyWatchedCategory(
                                  _iptvActiveCategoryId,
                                )
                                ? 'recently_watched_empty'.tr
                                : 'no_channels'.tr)),
                    textAlign: TextAlign.center,
                    style: Get.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final n = channels.length;
    return LiveBrowserPanelShell(
      header: LiveBrowserChannelPanelHeader(
        title: _iptvActiveCategoryTitle(displayCats),
        count: n,
      ),
      child: ListView.builder(
        controller: _iptvChannelScrollController,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        clipBehavior: Clip.none,
        cacheExtent: kListCacheExtent,
        itemExtent: _kIptvChRowHeight,
        itemCount: n,
        itemBuilder: (context, i) {
          final ch = channels[i];
          final node = _iptvChannelFocusNodes[i];
          final isPlaying = _iptvIsSameChannelAsPlaying(ch);
          final isFavorite =
              favState.lives.any((l) => liveChannelsMatch(l, ch));
          return RepaintBoundary(
            child: Focus(
              focusNode: node,
              onKeyEvent:
                  (fn, ev) => _iptvChannelItemOnKey(i, n, userAuth, ch, ev),
              child: ListenableBuilder(
                listenable: node,
                builder: (context, _) {
                  final focused = node.hasFocus;
                  return LiveBrowserChannelRow(
                      title: sanitizeDisplayTitle(ch.name),
                      imageUrl: resolveImageUrl(ch.streamIcon, serverUrl),
                      quality: liveBrowserQualityLabel(ch.name),
                      isPlaying: isPlaying,
                      isFavorite: isFavorite,
                      focused: focused,
                      flatList: true,
                      onTap: () {
                        _touchLiveIptvOverlayActivity();
                        node.requestFocus();
                        final link = _buildLiveStreamLink(ch, userAuth);
                        if (link.isEmpty) return;
                        _channelSwitchDebounce?.cancel();
                        _channelSwitchDebounce = null;
                        if (_iptvIsSameChannelAsPlaying(ch)) {
                          _closeLiveIptvOverlay();
                          return;
                        }
                        // نفس آلية المشروع القديم: zap داخل اللوحة دون إغلاق فوري.
                        _touchPlayerControlsActivity();
                        unawaited(_switchToLiveChannel(ch, link));
                      },
                    );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIptvMiniPlayerPanel({
    required String liveName,
    required String? channelIconUrl,
  }) {
    return ListenableBuilder(
      listenable: _iptvMiniPlayerFocusNode,
      builder: (context, _) {
        final focused = _iptvMiniPlayerFocusNode.hasFocus;
        final showLiveBanner =
            AdsService.shouldShowBanner(AppBannerPlacement.liveEpg);
        final hasChannel =
            (_currentLiveChannel ?? widget.channelLive) != null;
        final title = sanitizeDisplayTitle(liveName).trim();
        final showTitleChip = hasChannel || title.isNotEmpty;
        // Compact banner ≈50 + small gap above it.
        const bannerBlockH = 56.0;
        const epgReserveH = 118.0;
        // Outer focus ring must sit OUTSIDE the native video slot, otherwise
        // Exo/VLC PlatformView paints over the border.
        const focusRingPad = 3.0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final maxH = constraints.maxHeight;
            // First frames / tight flex can pass 0 or unbounded → FittedBox
            // would build an invalid TransformLayer matrix.
            if (!maxW.isFinite ||
                !maxH.isFinite ||
                maxW <= 1 ||
                maxH <= 1) {
              return const SizedBox.shrink();
            }

            final bottomReserve =
                epgReserveH + (showLiveBanner ? bannerBlockH : 0);
            final rawAvail = maxH - bottomReserve;
            final playerAvailH = rawAvail > 48
                ? rawAvail
                : (maxH * 0.42).clamp(1.0, maxH);
            final idealH = maxW * 9 / 16;
            final boxH = (idealH <= playerAvailH ? idealH : playerAvailH)
                .clamp(1.0, maxH);

            final hasIcon = channelIconUrl != null &&
                channelIconUrl.isNotEmpty &&
                channelIconUrl.toLowerCase() != 'null';

            Widget channelChip() {
              return Align(
                alignment: AlignmentDirectional.topStart,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 26,
                              height: 20,
                              child: hasIcon
                                  ? Builder(
                                      builder: (context) {
                                        final mem =
                                            iptvMemCachePx(context, 36, 28);
                                        return CachedNetworkImage(
                                          imageUrl: channelIconUrl,
                                          cacheManager: iptvImageCacheManager,
                                          memCacheWidth: mem.$1,
                                          memCacheHeight: mem.$2,
                                          fit: BoxFit.contain,
                                          fadeInDuration: Duration.zero,
                                          fadeOutDuration: Duration.zero,
                                          errorWidget: (_, _, _) =>
                                              const LiveBrowserChannelLogoFallback(),
                                          placeholder: (_, _) =>
                                              const LiveBrowserChannelLogoFallback(),
                                        );
                                      },
                                    )
                                  : const LiveBrowserChannelLogoFallback(),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              title.isEmpty ? '—' : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Get.textTheme.titleSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: maxW,
                    height: boxH,
                    child: Focus(
                      focusNode: _iptvMiniPlayerFocusNode,
                      onKeyEvent: _iptvMiniPlayerOnKey,
                      child: GestureDetector(
                        onTap: () {
                          _touchLiveIptvOverlayActivity();
                          _iptvMiniPlayerFocusNode.requestFocus();
                          final hasLivePlayback =
                              (_currentLiveChannel ?? widget.channelLive) !=
                                  null &&
                              _currentPlaybackUrl.trim().isNotEmpty;
                          if (!hasLivePlayback) return;
                          _closeLiveIptvOverlay();
                        },
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: focused
                                  ? kColorFocus
                                  : Colors.transparent,
                              width: focusRingPad,
                            ),
                            boxShadow: focused
                                ? [
                                  BoxShadow(
                                    color: kColorFocus.withValues(
                                      alpha: 0.55,
                                    ),
                                    blurRadius: 16,
                                    spreadRadius: 1,
                                  ),
                                ]
                                : null,
                          ),
                          // Always pad so the ring stays outside PlatformView.
                          child: Padding(
                            padding: const EdgeInsets.all(focusRingPad),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ColoredBox(
                                color: Colors.black,
                                // Title chip sits in the Flutter layer ABOVE the
                                // video slot (Column), so PlatformView cannot
                                // cover logo/name while they still look inside.
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showTitleChip) channelChip(),
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ColoredBox(
                                            key: _iptvMiniPlayerSlotKey,
                                            color: Colors.black,
                                          ),
                                          if (!hasChannel)
                                            Center(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.live_tv_rounded,
                                                    size: 40,
                                                    color: Colors.white
                                                        .withValues(
                                                      alpha: 0.28,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'select_a_channel'.tr,
                                                    textAlign:
                                                        TextAlign.center,
                                                    style: Get
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                      color: Colors.white
                                                          .withValues(
                                                        alpha: 0.55,
                                                      ),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else if (!_useExo &&
                                              (_vlcZapParkOffscreen ||
                                                  _videoPlayerController ==
                                                      null ||
                                                  _isSwitchingLiveChannel))
                                            const ColoredBox(
                                              color: Colors.black,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Avoid FittedBox here: zero remaining height → invalid matrix.
                Flexible(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ExcludeFocus(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: _buildIptvMiniEpgCard(),
                      ),
                    ),
                  ),
                ),
                if (showLiveBanner)
                  const Center(
                    child: AppBannerAd(
                      placement: AppBannerPlacement.liveEpg,
                      compact: true,
                      showOnTv: true,
                      excludeFocus: true,
                      reserveHeight: true,
                      padding: EdgeInsets.only(bottom: 2),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildIptvMiniEpgCard() {
    final now = _currentProgram;
    final next = _nextProgram;
    final progress = _liveEpgProgress();
    String dateLabel;
    try {
      dateLabel = DateFormat('EEE, d MMM y').format(DateTime.now());
    } catch (_) {
      final n = DateTime.now();
      dateLabel = '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    }

    String titleOf(EpgProgram? p) {
      if (p == null) return 'epg_no_info'.tr;
      final t = _epgCleanTitle(p.title);
      return t.isEmpty ? 'epg_no_info'.tr : t;
    }

    String timeOf(EpgProgram? p) {
      if (p == null) return '';
      return '${DateFormat.Hm().format(p.start)} – ${DateFormat.Hm().format(p.end)}';
    }

    return Padding(
      padding: EdgeInsets.zero,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF161B28),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 11,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            dateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _iptvEpgBlock(
                      label: 'epg_label_now'.tr,
                      title: titleOf(now),
                      time: timeOf(now),
                      emphasize: true,
                      progress: now != null ? progress : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    _iptvEpgBlock(
                      label: 'epg_label_next'.tr,
                      title: next == null ? '—' : titleOf(next),
                      time: timeOf(next),
                      emphasize: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: -7,
            child: ColoredBox(
              color: const Color(0xFF141824),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Text(
                  'epg_panel_title'.tr,
                  style: TextStyle(
                    color: kColorFocus,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iptvEpgBlock({
    required String label,
    required String title,
    required String time,
    required bool emphasize,
    double? progress,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: emphasize
                    ? kColorFocus.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: emphasize
                      ? kColorFocus
                      : Colors.white.withValues(alpha: 0.55),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  height: 1,
                ),
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: emphasize
                        ? kColorFocus.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.42),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: emphasize ? 0.96 : 0.82),
            fontSize: emphasize ? 13 : 12,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            height: 1.15,
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 2.5,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                kColorFocus.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLiveIptvSplitLayout({required String liveName}) {
    if (!widget.isLive || !_showLiveIptvOverlay) {
      return const SizedBox.shrink();
    }
    final auth = context.read<AuthBloc>().state;
    final userAuth = auth is AuthSuccess ? auth.user : null;
    final serverUrl = auth is AuthSuccess
        ? auth.user.serverInfo?.serverUrl
        : null;
    final effectiveChannel = _currentLiveChannel ?? widget.channelLive;
    final channelIconUrl = resolveImageUrl(
      effectiveChannel?.streamIcon,
      serverUrl,
    );
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Positioned.fill(
      child: Focus(
        focusNode: _iptvOverlayFocusNode,
        onKeyEvent: _onLiveIptvOverlayShellKey,
        // بدون Tween/Opacity على اللوحة — إعادة البناء كل إطار كانت تُحرّك قياس
        // خانة المصغّر وتوقف Exo (المشروع القديم ثابت بدون أنيميشن هنا).
        child: ColoredBox(
          color: const Color(0xFF141824),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, topPad + 8, 10, bottomPad + 8),
            child: userAuth == null
                ? LiveBrowserPanelShell(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'please_login_first'.tr,
                          textAlign: TextAlign.center,
                          style: Get.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 18,
                          child: RepaintBoundary(
                            child: _buildIptvCategoryPanelColumn(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 22,
                          child: RepaintBoundary(
                            child: _buildIptvChannelsPanelColumn(userAuth),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 40,
                          child: Padding(
                            // Tighter bottom so live banner sits near screen edge.
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                            child: _buildIptvMiniPlayerPanel(
                              liveName: liveName,
                              channelIconUrl: channelIconUrl,
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


