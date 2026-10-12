part of '../screens.dart';

class FavouriteScreen extends StatefulWidget {
  const FavouriteScreen({super.key, this.embeddedInTvShell = false});

  final bool embeddedInTvShell;

  @override
  State createState() => FavouriteScreenState();
}

class FavouriteScreenState extends State<FavouriteScreen>
    with LandscapeMainAppStateMixin<FavouriteScreen> {
  int selectedCategory = 0;

  late final FocusNode _backFocusNode;
  late final List<FocusNode> _tabFocusNodes;
  late final FocusNode _firstContentFocusNode;
  late final FocusScopeNode _contentScope;

  static const _tabs = [
    (key: 'fav_live', icon: Icons.live_tv_rounded),
    (key: 'fav_movies', icon: Icons.movie_filter_rounded),
    (key: 'fav_series', icon: Icons.video_library_rounded),
  ];

  /// تركيز ريموت على تبويبات المفضلة (شلّ التلفزيون).
  void focusPrimaryContent() {
    if (widget.embeddedInTvShell) {
      _focusTabs();
    } else {
      _backFocusNode.requestFocus();
    }
  }

  /// بعد إغلاق كlavier البحث: أول عنصر ظاهر، وإلا التبويبات.
  void focusAfterTopSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_firstContentFocusNode.canRequestFocus &&
          _firstContentFocusNode.context != null) {
        _firstContentFocusNode.requestFocus();
        return;
      }
      _focusContent();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_firstContentFocusNode.canRequestFocus &&
            _firstContentFocusNode.context != null) {
          _firstContentFocusNode.requestFocus();
          return;
        }
        _focusTabs();
      });
    });
  }

  static bool _isKeyDown(KeyEvent event) =>
      event is KeyDownEvent || event is KeyRepeatEvent;

  @override
  void initState() {
    super.initState();

    _backFocusNode = FocusNode(
      debugLabel: 'fav_back',
      onKeyEvent: (n, e) => _onBackKey(n, e),
    );
    _tabFocusNodes = List.generate(
      _tabs.length,
      (i) => FocusNode(debugLabel: 'fav_tab_$i'),
    );
    _firstContentFocusNode = FocusNode(debugLabel: 'fav_first_content');
    _contentScope = FocusScopeNode(debugLabel: 'fav_content');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FavoritesCubit>().initialData();
      if (widget.embeddedInTvShell) {
        _focusTabs();
      } else {
        _backFocusNode.requestFocus();
      }
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
    if (selectedCategory == index) return;
    setState(() => selectedCategory = index);
  }

  void _focusTabs() {
    final i = selectedCategory.clamp(0, _tabFocusNodes.length - 1);
    _tabFocusNodes[i].requestFocus();
  }

  bool _isContentEmpty() {
    final state = context.read<FavoritesCubit>().state;
    return switch (selectedCategory) {
      0 => state.lives.isEmpty,
      1 => state.movies.isEmpty,
      _ => state.series.isEmpty,
    };
  }

  /// الشجرة #3: أول عنصر في المحتوى إن وُجد.
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

    // تفعيل التبويب
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
      if (widget.embeddedInTvShell) {
        _stvSetActiveShellTab(SmartTvShellTab.favourites);
        _stvFocusShellTab(SmartTvShellTab.favourites);
      }
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
      } else if (!widget.embeddedInTvShell) {
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
    final embedded = widget.embeddedInTvShell;

    return Scaffold(
      backgroundColor: embedded ? Colors.transparent : null,
      body: Container(
        width: size.width,
        height: embedded ? double.infinity : size.height,
        decoration: kDecorBackground,
        child: SafeArea(
          top: !embedded,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: BlocBuilder<FavoritesCubit, FavoritesState>(
                    builder: (context, state) {
                      return _FavHeroHeader(
                        liveCount: state.lives.length,
                        movieCount: state.movies.length,
                        seriesCount: state.series.length,
                        isTv: tv,
                        hideBack: embedded,
                        backFocusNode: _backFocusNode,
                        tabs: _tabs,
                        selectedIndex: selectedCategory,
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
                            key: ValueKey<int>(selectedCategory),
                            child: switch (selectedCategory) {
                              0 => _FavLivePage(
                                  firstContentFocusNode:
                                      _firstContentFocusNode,
                                ),
                              1 => _FavMoviesPage(
                                  firstContentFocusNode:
                                      _firstContentFocusNode,
                                ),
                              _ => _FavSeriesPage(
                                  firstContentFocusNode:
                                      _firstContentFocusNode,
                                ),
                            },
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

class _FavHeroHeader extends StatelessWidget {
  const _FavHeroHeader({
    required this.liveCount,
    required this.movieCount,
    required this.seriesCount,
    required this.isTv,
    required this.backFocusNode,
    required this.tabs,
    required this.selectedIndex,
    required this.tabFocusNodes,
    required this.onSelected,
    required this.onTabKey,
    this.hideBack = false,
  });

  final int liveCount;
  final int movieCount;
  final int seriesCount;
  final bool isTv;
  final bool hideBack;
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
    final iconSize = isTv ? 22.0 : 18.0;

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
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: isTv ? 44 : 38,
                    height: isTv ? 44 : 38,
                    decoration: kDecorIconCircle,
                    alignment: Alignment.center,
                    child: Icon(
                      FontAwesomeIcons.solidHeart,
                      size: iconSize * 0.72,
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
                          'favourites'.tr,
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
                            _FavCountChip(
                              icon: Icons.live_tv_rounded,
                              label: 'fav_live'.tr,
                              count: liveCount,
                              compact: true,
                            ),
                            _FavCountChip(
                              icon: Icons.movie_filter_rounded,
                              label: 'fav_movies'.tr,
                              count: movieCount,
                              compact: true,
                            ),
                            _FavCountChip(
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
            _FavSegmentedTabs(
              tabs: tabs,
              selectedIndex: selectedIndex,
              focusNodes: tabFocusNodes,
              isTv: isTv,
              compact: true,
              onSelected: onSelected,
              onTabKey: onTabKey,
            ),
            if (!hideBack)
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
              )
            else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _FavCountChip extends StatelessWidget {
  const _FavCountChip({
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
              style: TextStyle(
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

class _FavSegmentedTabs extends StatelessWidget {
  const _FavSegmentedTabs({
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
              _FavTabChip(
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

class _FavTabChip extends StatelessWidget {
  const _FavTabChip({
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
              ? (isTv ? 14.0 : 10.0)
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

class _FavEmptyState extends StatelessWidget {
  const _FavEmptyState({
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
              child: Icon(
                icon,
                size: tv ? 44 : 36,
                color: kColorHint,
              ),
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
              'fav_empty_hint'.tr,
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

/// نطاق تنقل الشبكة (مفضلة / Catch Up): من الصف الأول ↑ يعود للتبويبات.
class _GridNavScope extends InheritedWidget {
  const _GridNavScope({
    required this.focusTabs,
    required super.child,
  });

  final VoidCallback focusTabs;

  static _GridNavScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_GridNavScope>();

  @override
  bool updateShouldNotify(_GridNavScope oldWidget) =>
      focusTabs != oldWidget.focusTabs;
}

/// نصف حجم كارت المتابعة في الرئيسية + مسافات ضيقة.
const double _kFavCardScale = 0.5;
const double _kFavGridGap = 4.0;

double _favScaledContinueWidth(BuildContext context) =>
    continueWatchCardWidth(context) * _kFavCardScale;

double _favScaledContinueHeight(BuildContext context) =>
    (continueWatchCardHeight(context) + continueWatchTitleHeight + 8) *
    _kFavCardScale;

Widget _favScaledContinueWatch({
  required BuildContext context,
  required Widget child,
}) {
  final fullW = continueWatchCardWidth(context);
  final fullH =
      continueWatchCardHeight(context) + continueWatchTitleHeight + 8;
  return SizedBox(
    width: fullW * _kFavCardScale,
    height: fullH * _kFavCardScale,
    child: FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(width: fullW, height: fullH, child: child),
    ),
  );
}

/// شبكة ملصقات الأفلام/المسلسلات: كروت أكبر، صف جديد عند حافة الشاشة (بدون تمرير أفقي).
const double _kFavPosterGridGap = 10.0;

int _favPosterCrossAxisCount(BuildContext context) {
  final tv = isTv(context);
  final w = MediaQuery.sizeOf(context).width;
  final pad = tv ? 40.0 : 24.0;
  // عرض مستهدف للكارت — أقل أعمدة = كروت أكبر، ويلتف للصف التالي تلقائياً.
  final targetW = tv ? 168.0 : 118.0;
  final n = ((w - pad + _kFavPosterGridGap) / (targetW + _kFavPosterGridGap))
      .floor();
  if (tv) return n.clamp(5, 8);
  if (w >= 900) return n.clamp(5, 7);
  if (w >= 600) return n.clamp(4, 5);
  return n.clamp(3, 4);
}

int _favLiveCrossAxisCount(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final pad = isTv(context) ? 40.0 : 24.0;
  final cardW = _favScaledContinueWidth(context);
  final n = ((w - pad + _kFavGridGap) / (cardW + _kFavGridGap)).floor();
  return n.clamp(4, 12);
}

/// يُستخدم أيضاً في صفحة Catch Up — تركيز خفيف بلون الثيم.
class TvCardFocus extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTvActivate;
  final FocusNode? focusNode;

  const TvCardFocus({
    super.key,
    required this.child,
    this.onTvActivate,
    this.focusNode,
  });

  @override
  State createState() => _TvCardFocusState();
}

class _TvCardFocusState extends State<TvCardFocus> {
  bool focused = false;

  static bool _isKeyDown(KeyEvent event) =>
      event is KeyDownEvent || event is KeyRepeatEvent;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      // يمنع InkWell الداخلي من سرقة التركيز — التركيز على الغلاف فقط
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      onFocusChange: (value) => setState(() => focused = value),
      onKeyEvent: (node, event) {
        if (!_isKeyDown(event)) return KeyEventResult.ignored;
        final k = event.logicalKey;

        if (k == LogicalKeyboardKey.arrowUp) {
          final moved = node.focusInDirection(TraversalDirection.up);
          if (!moved) {
            final escape = _GridNavScope.maybeOf(context);
            if (escape != null) {
              escape.focusTabs();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown) {
          final moved = node.focusInDirection(TraversalDirection.down);
          return moved ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (k == LogicalKeyboardKey.arrowLeft) {
          final moved = node.focusInDirection(TraversalDirection.left);
          return moved ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (k == LogicalKeyboardKey.arrowRight) {
          final moved = node.focusInDirection(TraversalDirection.right);
          return moved ? KeyEventResult.handled : KeyEventResult.ignored;
        }

        if (widget.onTvActivate == null) return KeyEventResult.ignored;
        if (k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter) {
          widget.onTvActivate!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: kTvFocusScale(focused, 1.04),
        duration: kFocusAnimDuration,
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused ? kColorFocus : Colors.transparent,
              width: focused ? 2.5 : 1,
            ),
            boxShadow: kTvFocusGlow(
              focused: focused,
              blur: 14,
              alpha: 0.35,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _FavLivePage extends StatelessWidget {
  const _FavLivePage({
    required this.firstContentFocusNode,
  });

  final FocusNode firstContentFocusNode;
  static String? _posterPrecacheKey;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, stateAuth) {
        if (stateAuth is! AuthSuccess) {
          return Center(
            child: CircularProgressIndicator(color: kColorPrimary),
          );
        }

        final userAuth = stateAuth.user;
        return BlocBuilder<FavoritesCubit, FavoritesState>(
          builder: (context, state) {
            final catState = context.read<LiveCatyBloc>().state;
            final cats = catState is LiveCatySuccess
                ? catState.categories
                : const <CategoryModel>[];
            String? categoryName(String? id) =>
                ParentalControlService.categoryNameFromId(id, cats);
            final livesAll = ParentalControlService.instance.filterAdultLiveChannels(
              state.lives,
              categoryNameForId: categoryName,
            );
            return ValueListenableBuilder<String>(
              valueListenable: kSmartTvTopSearchQuery,
              builder: (context, rawQ, _) {
                final q = rawQ.trim().toLowerCase();
                final lives = q.isEmpty
                    ? livesAll
                    : livesAll
                        .where(
                          (c) =>
                              (c.name ?? '').toLowerCase().contains(q),
                        )
                        .toList();
            if (lives.isEmpty) {
              return const _FavEmptyState(
                icon: Icons.live_tv_outlined,
                titleKey: 'fav_no_channels',
              );
            }

            final serverUrl = userAuth.serverInfo?.serverUrl;
            final precacheKey = 'fav_live:${lives.length}';
            if (_posterPrecacheKey != precacheKey) {
              _posterPrecacheKey = precacheKey;
              final urls = <String>[];
              for (final c in lives.take(20)) {
                final u = resolveImageUrl(c.streamIcon, serverUrl);
                if (u.isNotEmpty) urls.add(u);
              }
              unawaited(precacheIptvPosters(context, urls));
            }

            final tv = isTv(context);
            final cardW = _favScaledContinueWidth(context);
            final cardH = _favScaledContinueHeight(context);
            final crossAxisCount = _favLiveCrossAxisCount(context);

            return RefreshIndicator(
              onRefresh: () async {
                context.read<FavoritesCubit>().initialData();
              },
              color: kColorPrimary,
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  tv ? 20 : 12,
                  2,
                  tv ? 20 : 12,
                  tv ? 20 : 12,
                ),
                cacheExtent: tv ? kCatalogCacheExtent : null,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: _kFavGridGap,
                  mainAxisSpacing: _kFavGridGap,
                  childAspectRatio: cardW / cardH,
                ),
                itemCount: lives.length,
                itemBuilder: (_, i) {
                  final live = lives[i];
                  final serverUrl = userAuth.serverInfo!.serverUrl ?? '';
                  final username = userAuth.userInfo!.username ?? '';
                  final password = userAuth.userInfo!.password ?? '';
                  final streamId = live.streamId ?? '';
                  final link = preferredVideoPlayer == AppVideoPlayer.vlc
                      ? buildXtreamLiveStreamUrlShort(
                          serverUrl: serverUrl,
                          username: username,
                          password: password,
                          streamId: streamId,
                        )
                      : buildXtreamLiveStreamUrl(
                          serverUrl: serverUrl,
                          username: username,
                          password: password,
                          streamId: streamId,
                        );
                  final model = WatchingModel(
                    streamId: live.streamId ?? '',
                    image: live.streamIcon ?? '',
                    title: live.name ?? '',
                    stream: link,
                    sliderValue: 0,
                    durationStrm: 1,
                  );

                  Future<void> openLive() async {
                    final parental = ParentalControlService.instance;
                    if (parental.isAdultLiveChannel(
                      live,
                      categoryName: categoryName(live.categoryId),
                    )) {
                      final ok = await parental.requestAdultContentAccess(
                        context,
                      );
                      if (!ok || !context.mounted) return;
                    }
                    await Get.to(
                      () => FullVideoScreen(
                        isLive: true,
                        link: link,
                        title: live.name ?? "",
                        channelLive: live,
                      ),
                    );
                  }

                  return Align(
                    alignment: Alignment.topCenter,
                    child: TvCardFocus(
                      focusNode: i == 0 ? firstContentFocusNode : null,
                      onTvActivate: () => unawaited(openLive()),
                      child: _favScaledContinueWatch(
                        context: context,
                        child: CardMovieContinueWatch(
                          model: model,
                          onTap: () => unawaited(openLive()),
                          boldTitle: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
              },
            );
          },
        );
      },
    );
  }
}

class _FavMoviesPage extends StatelessWidget {
  const _FavMoviesPage({
    required this.firstContentFocusNode,
  });

  final FocusNode firstContentFocusNode;
  static String? _posterPrecacheKey;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FavoritesCubit, FavoritesState>(
      builder: (context, state) {
        final moviesAll = state.movies;
        if (moviesAll.isEmpty) {
          return const _FavEmptyState(
            icon: Icons.movie_filter_outlined,
            titleKey: 'fav_no_movies',
          );
        }

        return ValueListenableBuilder<String>(
          valueListenable: kSmartTvTopSearchQuery,
          builder: (context, rawQ, _) {
            final q = rawQ.trim().toLowerCase();
            final movies = q.isEmpty
                ? moviesAll
                : moviesAll
                    .where((m) => (m.name ?? '').toLowerCase().contains(q))
                    .toList();
            if (movies.isEmpty) {
              return const _FavEmptyState(
                icon: Icons.movie_filter_outlined,
                titleKey: 'fav_no_movies',
              );
            }

        final authState = context.read<AuthBloc>().state;
        final serverUrl = authState is AuthSuccess
            ? authState.user.serverInfo?.serverUrl
            : null;
        final precacheKey = 'fav_movies:${movies.length}:$q';
        if (_posterPrecacheKey != precacheKey) {
          _posterPrecacheKey = precacheKey;
          final urls = <String>[];
          for (final m in movies.take(20)) {
            final u = resolveImageUrl(m.streamIcon, serverUrl);
            if (u.isNotEmpty) urls.add(u);
          }
          unawaited(precacheIptvPosters(context, urls));
        }

        final tv = isTv(context);
        final crossAxisCount = _favPosterCrossAxisCount(context);
        return RefreshIndicator(
          onRefresh: () async {
            context.read<FavoritesCubit>().initialData();
          },
          color: kColorPrimary,
          child: GridView.builder(
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
            itemCount: movies.length,
            itemBuilder: (_, i) {
              final movie = movies[i];
              final authState = context.read<AuthBloc>().state;
              final serverUrl = authState is AuthSuccess
                  ? authState.user.serverInfo?.serverUrl
                  : null;

              void openMovie() {
                final id = movie.streamId ?? '';
                if (id.isNotEmpty) {
                  context.read<PrefetchCubit>().getMovieDetailCached(id);
                }
                Get.to(
                  () => MovieContent(
                    channelMovie: movie,
                    videoId: id,
                  ),
                );
              }

              return TvCardFocus(
                focusNode: i == 0 ? firstContentFocusNode : null,
                onTvActivate: openMovie,
                child: CardChannelMovieItem(
                  title: movie.name ?? "",
                  image: movie.streamIcon,
                  serverUrl: serverUrl,
                  rating: movie.rating,
                  rating5based: movie.rating5based,
                  contentKey: 'movie:${movie.streamId ?? ''}',
                  onTap: openMovie,
                  boldTitle: true,
                ),
              );
            },
          ),
        );
          },
        );
      },
    );
  }
}

class _FavSeriesPage extends StatelessWidget {
  const _FavSeriesPage({
    required this.firstContentFocusNode,
  });

  final FocusNode firstContentFocusNode;
  static String? _posterPrecacheKey;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FavoritesCubit, FavoritesState>(
      builder: (context, state) {
        final seriesAll = state.series;
        if (seriesAll.isEmpty) {
          return const _FavEmptyState(
            icon: Icons.video_library_outlined,
            titleKey: 'fav_no_series',
          );
        }

        return ValueListenableBuilder<String>(
          valueListenable: kSmartTvTopSearchQuery,
          builder: (context, rawQ, _) {
            final q = rawQ.trim().toLowerCase();
            final series = q.isEmpty
                ? seriesAll
                : seriesAll
                    .where((s) => (s.name ?? '').toLowerCase().contains(q))
                    .toList();
            if (series.isEmpty) {
              return const _FavEmptyState(
                icon: Icons.video_library_outlined,
                titleKey: 'fav_no_series',
              );
            }

        final authState = context.read<AuthBloc>().state;
        final serverUrl = authState is AuthSuccess
            ? authState.user.serverInfo?.serverUrl
            : null;
        final precacheKey = 'fav_series:${series.length}:$q';
        if (_posterPrecacheKey != precacheKey) {
          _posterPrecacheKey = precacheKey;
          final urls = <String>[];
          for (final s in series.take(20)) {
            final u = resolveImageUrl(s.cover, serverUrl);
            if (u.isNotEmpty) urls.add(u);
          }
          unawaited(precacheIptvPosters(context, urls));
        }

        final tv = isTv(context);
        final crossAxisCount = _favPosterCrossAxisCount(context);
        return RefreshIndicator(
          onRefresh: () async {
            context.read<FavoritesCubit>().initialData();
          },
          color: kColorPrimary,
          child: GridView.builder(
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
            itemCount: series.length,
            itemBuilder: (_, i) {
              final serie = series[i];
              final authState = context.read<AuthBloc>().state;
              final serverUrl = authState is AuthSuccess
                  ? authState.user.serverInfo?.serverUrl
                  : null;

              void openSerie() {
                final id = serie.seriesId ?? '';
                if (id.isNotEmpty) {
                  context.read<PrefetchCubit>().getSerieDetailCached(id);
                }
                Get.to(
                  () => SerieContent(
                    channelSerie: serie,
                    videoId: id,
                  ),
                );
              }

              return TvCardFocus(
                focusNode: i == 0 ? firstContentFocusNode : null,
                onTvActivate: openSerie,
                child: CardChannelMovieItem(
                  title: serie.name ?? "",
                  image: serie.cover,
                  serverUrl: serverUrl,
                  rating: serie.rating,
                  rating5based: serie.rating5based,
                  contentKey: 'series:${serie.seriesId ?? ''}',
                  isSeries: true,
                  onTap: openSerie,
                  boldTitle: true,
                ),
              );
            },
          ),
        );
          },
        );
      },
    );
  }
}
