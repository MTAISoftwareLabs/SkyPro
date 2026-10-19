part of 'screens.dart';

/// تبويبات الشلّ على التلفزيون (مثل Smart TV mode-home / catalog).
enum SmartTvShellTab { home, movies, series, favourites, live }

/// هامش يمين/يسار موحّد: الشريط العلوي وبوسترات Home.
double smartTvHomeSideInset(BuildContext context) {
  return (MediaQuery.sizeOf(context).width * 0.018).clamp(20.0, 40.0);
}

/// هامش فوق الشريط العلوي باش ما يلصقش بحافة الشاشة.
double smartTvHomeTopInset(BuildContext context) {
  return (MediaQuery.sizeOf(context).height * 0.022).clamp(16.0, 32.0);
}

/// طلب تبويب من Live browser — يُضبط قبل Get.back لتفادي وميض Home.
final ValueNotifier<SmartTvShellTab?> kPendingTvShellTab =
    ValueNotifier<SmartTvShellTab?>(null);

/// بحث شريط التنقل العلوي — نفس `in-search` في Smart TV.
final ValueNotifier<String> kSmartTvTopSearchQuery = ValueNotifier<String>('');

/// كlavier بحث الشريط مفتوح — يمنع Live من سرقة التركيز للفئات.
final ValueNotifier<bool> kSmartTvTopSearchKeyboardOpen = ValueNotifier<bool>(
  false,
);

void kSmartTvClearTopSearch() {
  if (kSmartTvTopSearchQuery.value.isEmpty) return;
  kSmartTvTopSearchQuery.value = '';
}

String _stvTopSearchPlaceholder(SmartTvShellTab tab) {
  return switch (tab) {
    SmartTvShellTab.movies => 'search_movies'.tr,
    SmartTvShellTab.series => 'search_series'.tr,
    SmartTvShellTab.favourites => 'search_favorites'.tr,
    SmartTvShellTab.live => 'search_channels'.tr,
    SmartTvShellTab.home => 'search'.tr,
  };
}

List<T> _stvMatchTopSearchTitles<T>(
  List<T> items,
  String? Function(T item) titleOf,
) {
  final q = kSmartTvTopSearchQuery.value.trim().toLowerCase();
  if (q.isEmpty) return items;
  return items
      .where((e) => (titleOf(e) ?? '').toLowerCase().contains(q))
      .toList();
}

/// شريط Home العلوي على التلفزيون — مطابق لـ Smart TV (تبويبات + أيقونات PNG).
class _SmartTvHomeTopBar extends StatelessWidget {
  const _SmartTvHomeTopBar({
    this.selected = SmartTvShellTab.home,
    this.onSelectTab,
    this.onArrowDownToContent,
    this.onArrowRightToContent,
    this.onSearchClosed,
    this.sideRail = false,
    this.utilitiesOnly = false,
  });

  final SmartTvShellTab selected;
  final ValueChanged<SmartTvShellTab>? onSelectTab;

  /// ↓ من الشريط → محتوى الصفحة (فئة أولى / بوستر).
  final VoidCallback? onArrowDownToContent;

  /// → من شريط الجانب → محتوى الصفحة.
  final VoidCallback? onArrowRightToContent;

  /// بعد إغلاق كlavier البحث العلوي → أول نتيجة / أول فئة.
  final VoidCallback? onSearchClosed;
  final bool sideRail;
  final bool utilitiesOnly;

  static void _openLive() {
    ParentalControlService.instance.navigateToProtectedAction(
      ParentalSection.live,
      openLiveIptvBrowser,
    );
  }

  static void _openSettings() {
    ParentalControlService.instance.navigateToProtectedRoute(
      ParentalSection.settings,
      screenSettings,
    );
  }

  void _select(SmartTvShellTab tab) {
    kSmartTvClearTopSearch();
    final cb = onSelectTab;
    if (cb != null) {
      cb(tab);
      return;
    }
    if (tab == SmartTvShellTab.live) {
      _openLive();
      return;
    }
    if (tab == SmartTvShellTab.movies) {
      ParentalControlService.instance.navigateToProtectedRoute(
        ParentalSection.movies,
        screenMovieCategories,
      );
    } else if (tab == SmartTvShellTab.series) {
      ParentalControlService.instance.navigateToProtectedRoute(
        ParentalSection.series,
        screenSeriesCategories,
      );
    } else if (tab == SmartTvShellTab.favourites) {
      Get.toNamed(screenFavourite);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sideRail) return _buildTvSideRail(context);
    if (utilitiesOnly) return _buildTvUtilitiesBar(context);
    final phone = !isTv(context);
    if (phone) {
      return _buildPhoneBar(context);
    }
    return _buildTvBar(context);
  }

  /// شريط موبايل: سطر واحد فقط — لوغو + تبويبات + أدوات بنفس الارتفاع.
  Widget _buildPhoneBar(BuildContext context) {
    const barBg = kSkyProBlack;
    const iconBox = 32.0;
    final side = (MediaQuery.sizeOf(context).width * 0.03).clamp(10.0, 14.0);

    return Material(
      color: barBg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(side, 6, side, 6),
        child: SizedBox(
          height: iconBox,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  kIconSplash,
                  width: iconBox,
                  height: iconBox,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) =>
                      const SizedBox(width: iconBox, height: iconBox),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _SmartTvHomeTab(
                      label: 'home_nav_home'.tr,
                      iconAsset: kSmartTvNavHome,
                      selected: selected == SmartTvShellTab.home,
                      onTap: () => _select(SmartTvShellTab.home),
                      isFirstInRow: true,
                      focusDebugLabel: _stvTopLabel('home'),
                      onArrowDownToContent: onArrowDownToContent,
                      mobile: true,
                    ),
                    const SizedBox(width: 5),
                    _SmartTvHomeTab(
                      label: 'home_nav_channels'.tr,
                      iconAsset: kSmartTvNavLive,
                      selected: selected == SmartTvShellTab.live,
                      onTap: () => _select(SmartTvShellTab.live),
                      focusDebugLabel: _stvTopLabel('live'),
                      onArrowDownToContent: onArrowDownToContent,
                      mobile: true,
                    ),
                    const SizedBox(width: 5),
                    _SmartTvHomeTab(
                      label: 'movies'.tr,
                      iconAsset: kSmartTvNavMovies,
                      selected: selected == SmartTvShellTab.movies,
                      onTap: () => _select(SmartTvShellTab.movies),
                      focusDebugLabel: _stvTopLabel('movies'),
                      onArrowDownToContent: onArrowDownToContent,
                      mobile: true,
                    ),
                    const SizedBox(width: 5),
                    _SmartTvHomeTab(
                      label: 'series'.tr,
                      iconAsset: kSmartTvNavSeries,
                      selected: selected == SmartTvShellTab.series,
                      onTap: () => _select(SmartTvShellTab.series),
                      focusDebugLabel: _stvTopLabel('series'),
                      onArrowDownToContent: onArrowDownToContent,
                      mobile: true,
                    ),
                    const SizedBox(width: 5),
                    _SmartTvHomeTab(
                      label: 'favourites'.tr,
                      iconAsset: kSmartTvNavFav,
                      selected: selected == SmartTvShellTab.favourites,
                      onTap: () => _select(SmartTvShellTab.favourites),
                      focusDebugLabel: _stvTopLabel('fav'),
                      onArrowDownToContent: onArrowDownToContent,
                      mobile: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _SmartTvSearchPill(
                selected: selected,
                onArrowDownToContent: onArrowDownToContent,
                onSearchClosed: onSearchClosed,
                compact: true,
              ),
              const SizedBox(width: 3),
              const _SmartTvLiveClock(compact: true),
              const SizedBox(width: 3),
              const _SmartTvWifiIcon(compact: true, boxSize: iconBox),
              const SizedBox(width: 3),
              _SmartTvProfileBtn(
                onArrowDownToContent: onArrowDownToContent,
                compact: true,
                boxSize: iconBox,
              ),
              const SizedBox(width: 3),
              _SmartTvNotificationsBtn(
                onArrowDownToContent: onArrowDownToContent,
                compact: true,
                boxSize: iconBox,
              ),
              const SizedBox(width: 3),
              _SmartTvCircleIconBtn(
                asset: kSmartTvNavSettings,
                tooltip: 'settings'.tr,
                onTap: _openSettings,
                isLastInRow: true,
                focusDebugLabel: _stvTopLabel('settings'),
                onArrowDownToContent: onArrowDownToContent,
                compact: true,
                boxSize: iconBox,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvBar(BuildContext context) {
    // أحجام متوازنة: كل التبويبات ظاهرة + مساحة للمحتوى (مثل Smart TV).
    final side = smartTvHomeSideInset(context);
    final top = smartTvHomeTopInset(context);
    const logoSize = 38.0;
    const tabGap = 8.0;

    Widget tabs = FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SmartTvHomeTab(
            label: 'home_nav_home'.tr,
            iconAsset: kSmartTvNavHome,
            selected: selected == SmartTvShellTab.home,
            onTap: () => _select(SmartTvShellTab.home),
            isFirstInRow: true,
            focusDebugLabel: _stvTopLabel('home'),
            onArrowDownToContent: onArrowDownToContent,
          ),
          const SizedBox(width: tabGap),
          _SmartTvHomeTab(
            label: 'home_nav_channels'.tr,
            iconAsset: kSmartTvNavLive,
            selected: selected == SmartTvShellTab.live,
            onTap: () => _select(SmartTvShellTab.live),
            focusDebugLabel: _stvTopLabel('live'),
            onArrowDownToContent: onArrowDownToContent,
          ),
          const SizedBox(width: tabGap),
          _SmartTvHomeTab(
            label: 'movies'.tr,
            iconAsset: kSmartTvNavMovies,
            selected: selected == SmartTvShellTab.movies,
            onTap: () => _select(SmartTvShellTab.movies),
            focusDebugLabel: _stvTopLabel('movies'),
            onArrowDownToContent: onArrowDownToContent,
          ),
          const SizedBox(width: tabGap),
          _SmartTvHomeTab(
            label: 'series'.tr,
            iconAsset: kSmartTvNavSeries,
            selected: selected == SmartTvShellTab.series,
            onTap: () => _select(SmartTvShellTab.series),
            focusDebugLabel: _stvTopLabel('series'),
            onArrowDownToContent: onArrowDownToContent,
          ),
          const SizedBox(width: tabGap),
          _SmartTvHomeTab(
            label: 'favourites'.tr,
            iconAsset: kSmartTvNavFav,
            selected: selected == SmartTvShellTab.favourites,
            onTap: () => _select(SmartTvShellTab.favourites),
            focusDebugLabel: _stvTopLabel('fav'),
            onArrowDownToContent: onArrowDownToContent,
          ),
        ],
      ),
    );

    return Material(
      color: kSkyProBlack,
      child: Padding(
        padding: EdgeInsets.fromLTRB(side, top, side, 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                kIconSplash,
                width: logoSize,
                height: logoSize,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: logoSize, height: logoSize),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: tabs,
              ),
            ),
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SmartTvSearchPill(
                  selected: selected,
                  onArrowDownToContent: onArrowDownToContent,
                  onSearchClosed: onSearchClosed,
                ),
                const SizedBox(width: 8),
                const _SmartTvLiveClock(),
                const SizedBox(width: 8),
                const _SmartTvWifiIcon(),
                const SizedBox(width: 6),
                _SmartTvProfileBtn(onArrowDownToContent: onArrowDownToContent),
                const SizedBox(width: 6),
                _SmartTvNotificationsBtn(
                  onArrowDownToContent: onArrowDownToContent,
                ),
                const SizedBox(width: 6),
                _SmartTvCircleIconBtn(
                  asset: kSmartTvNavSettings,
                  tooltip: 'settings'.tr,
                  onTap: _openSettings,
                  isLastInRow: true,
                  focusDebugLabel: _stvTopLabel('settings'),
                  onArrowDownToContent: onArrowDownToContent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTvSideRail(BuildContext context) {
    const railWidth = 112.0;
    final tabs = <({SmartTvShellTab tab, String label, String icon})>[
      (
        tab: SmartTvShellTab.home,
        label: 'home_nav_home'.tr,
        icon: kSmartTvNavHome,
      ),
      (
        tab: SmartTvShellTab.live,
        label: 'home_nav_channels'.tr,
        icon: kSmartTvNavLive,
      ),
      (
        tab: SmartTvShellTab.movies,
        label: 'movies'.tr,
        icon: kSmartTvNavMovies,
      ),
      (
        tab: SmartTvShellTab.series,
        label: 'series'.tr,
        icon: kSmartTvNavSeries,
      ),
      (
        tab: SmartTvShellTab.favourites,
        label: 'favourites'.tr,
        icon: kSmartTvNavFav,
      ),
    ];

    return Material(
      color: kSkyProBlack,
      child: Container(
        width: railWidth,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0x55007BFF), width: 1)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        kSkyProLogo,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.live_tv,
                            color: kSkyProBlue,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'SKYPRO',
                      maxLines: 1,
                      style: TextStyle(
                        color: kSkyProSilver,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0x33007BFF)),
              const SizedBox(height: 12),
              Expanded(
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: tabs.length,
                    itemBuilder: (context, index) {
                      final item = tabs[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SkyProTvRailItem(
                          label: item.label,
                          iconAsset: item.icon,
                          selected: selected == item.tab,
                          order: index + 1,
                          onTap: () => _select(item.tab),
                          onArrowRight: onArrowRightToContent,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvUtilitiesBar(BuildContext context) {
    final side = smartTvHomeSideInset(context);
    final top = smartTvHomeTopInset(context);
    return Material(
      color: kSkyProBlack,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, top, side, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _SmartTvSearchPill(
              selected: selected,
              onArrowDownToContent: onArrowDownToContent,
              onSearchClosed: onSearchClosed,
            ),
            const SizedBox(width: 8),
            const _SmartTvLiveClock(),
            const SizedBox(width: 8),
            const _SmartTvWifiIcon(),
            const SizedBox(width: 6),
            _SmartTvProfileBtn(onArrowDownToContent: onArrowDownToContent),
            const SizedBox(width: 6),
            _SmartTvNotificationsBtn(
              onArrowDownToContent: onArrowDownToContent,
            ),
            const SizedBox(width: 6),
            _SmartTvCircleIconBtn(
              asset: kSmartTvNavSettings,
              tooltip: 'settings'.tr,
              onTap: _openSettings,
              isLastInRow: true,
              focusDebugLabel: _stvTopLabel('settings'),
              onArrowDownToContent: onArrowDownToContent,
            ),
          ],
        ),
      ),
    );
  }
}

class _SkyProTvRailItem extends StatefulWidget {
  const _SkyProTvRailItem({
    required this.label,
    required this.iconAsset,
    required this.selected,
    required this.order,
    required this.onTap,
    this.onArrowRight,
  });

  final String label;
  final String iconAsset;
  final bool selected;
  final int order;
  final VoidCallback onTap;
  final VoidCallback? onArrowRight;

  @override
  State<_SkyProTvRailItem> createState() => _SkyProTvRailItemState();
}

class _SkyProTvRailItemState extends State<_SkyProTvRailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.order.toDouble()),
      child: Focus(
        autofocus: widget.selected,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onArrowRight?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: double.infinity,
              height: 66,
              decoration: BoxDecoration(
                color: widget.selected
                    ? kSkyProBlue.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _focused
                      ? kSkyProSilver
                      : widget.selected
                      ? kSkyProBlue
                      : Colors.transparent,
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Semantics(
                button: true,
                selected: widget.selected,
                label: widget.label,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      widget.iconAsset,
                      width: 22,
                      height: 22,
                      color: kSkyProSilver,
                      colorBlendMode: BlendMode.srcIn,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.live_tv,
                        size: 22,
                        color: kSkyProSilver,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kSkyProSilver,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ساعة + تاريخ مثل شريط Smart TV.
class _SmartTvLiveClock extends StatefulWidget {
  const _SmartTvLiveClock({this.compact = false});

  final bool compact;

  @override
  State<_SmartTvLiveClock> createState() => _SmartTvLiveClockState();
}

class _SmartTvLiveClockState extends State<_SmartTvLiveClock> {
  late DateTime _now;
  Timer? _timer;

  static const _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final date = '${_now.day} ${_months[_now.month - 1]}';
    final compact = widget.compact;
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          '$h:$m',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            height: 1,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$h:$m',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              height: 1.05,
            ),
          ),
          Text(
            date,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

KeyEventResult _smartTvTopBarKey(
  FocusNode node,
  KeyEvent event, {
  required bool isFirstInRow,
  required bool isLastInRow,
  required VoidCallback onActivate,
  VoidCallback? onArrowDownToContent,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.arrowRight) {
    if (isLastInRow) return KeyEventResult.handled;
    final next = _homePickHorizontalNeighbor(node, toRight: true);
    if (next != null) next.requestFocus();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    if (isFirstInRow) return KeyEventResult.handled;
    final next = _homePickHorizontalNeighbor(node, toRight: false);
    if (next != null) next.requestFocus();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    final next = _homePickVerticalNeighbor(node, down: true);
    if (next != null) {
      next.requestFocus();
      return KeyEventResult.handled;
    }
    onArrowDownToContent?.call();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    final next = _homePickVerticalNeighbor(node, down: false);
    if (next != null) next.requestFocus();
    return KeyEventResult.handled;
  }
  return settingsTvActivateOnSelect(event, onActivate);
}

class _SmartTvHomeTab extends StatefulWidget {
  const _SmartTvHomeTab({
    required this.label,
    required this.iconAsset,
    required this.onTap,
    this.selected = false,
    this.isFirstInRow = false,
    this.focusDebugLabel,
    this.onArrowDownToContent,
    this.mobile = false,
  });

  final String label;
  final String iconAsset;
  final VoidCallback onTap;
  final bool selected;
  final bool isFirstInRow;
  final String? focusDebugLabel;
  final VoidCallback? onArrowDownToContent;

  /// تبويبات الموبايل: حجم موحّد أنيق.
  final bool mobile;

  @override
  State<_SmartTvHomeTab> createState() => _SmartTvHomeTabState();
}

class _SmartTvHomeTabState extends State<_SmartTvHomeTab> {
  bool _focused = false;
  late final FocusNode _focusNode = FocusNode(
    debugLabel: widget.focusDebugLabel,
  );

  @override
  void initState() {
    super.initState();
    _stvBindFocusLabel(_focusNode, widget.focusDebugLabel);
  }

  @override
  void dispose() {
    _stvBindFocusLabel(_focusNode, null);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final focused = _focused;
    final bg = selected ? Colors.white : const Color(0xFF2A2D34);
    final fg = selected ? const Color(0xFF111827) : Colors.white;
    final borderColor = focused ? kColorFocus : Colors.transparent;
    final mobile = widget.mobile;
    final padH = mobile ? 10.0 : 10.0;
    final padV = mobile ? 0.0 : 7.0;
    final iconSize = mobile ? 15.0 : 20.0;
    final fontSize = mobile ? 12.0 : 13.0;
    final gap = mobile ? 5.0 : 6.0;

    return Focus(
      focusNode: _focusNode,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      onKeyEvent: (node, event) => _smartTvTopBarKey(
        node,
        event,
        isFirstInRow: widget.isFirstInRow,
        isLastInRow: false,
        onActivate: widget.onTap,
        onArrowDownToContent: widget.onArrowDownToContent,
      ),
      child: InkWell(
        onTap: widget.onTap,
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          height: mobile ? 32 : null,
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: focused ? 2 : 0),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: kColorFocus.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                widget.iconAsset,
                width: iconSize,
                height: iconSize,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.circle, size: iconSize * 0.8, color: fg),
              ),
              SizedBox(width: gap),
              Text(
                widget.label,
                style: TextStyle(
                  color: selected ? const Color(0xFF111827) : Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmartTvSearchPill extends StatefulWidget {
  const _SmartTvSearchPill({
    required this.selected,
    this.onArrowDownToContent,
    this.onSearchClosed,
    this.compact = false,
  });

  final SmartTvShellTab selected;
  final VoidCallback? onArrowDownToContent;
  final VoidCallback? onSearchClosed;
  final bool compact;

  @override
  State<_SmartTvSearchPill> createState() => _SmartTvSearchPillState();
}

class _SmartTvSearchPillState extends State<_SmartTvSearchPill> {
  bool _focused = false;
  bool _kbOpen = false;
  late final FocusNode _focusNode = FocusNode(
    debugLabel: _stvTopLabel('search'),
  );
  final FocusNode _kbSeedFocus = FocusNode(debugLabel: 'stv_top_search_kb');
  final FocusNode _textFocus = FocusNode(debugLabel: 'stv_top_search_text');
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  OverlayEntry? _kbOverlay;

  @override
  void initState() {
    super.initState();
    _stvBindFocusLabel(_focusNode, _stvTopLabel('search'));
    _controller.text = kSmartTvTopSearchQuery.value;
    kSmartTvTopSearchQuery.addListener(_syncFromNotifier);
  }

  @override
  void didUpdateWidget(covariant _SmartTvSearchPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      // مثل Smart TV: تفريغ البحث عند تبديل التبويب.
      _applyQuery('', immediate: true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    kSmartTvTopSearchQuery.removeListener(_syncFromNotifier);
    if (_kbOpen) kSmartTvTopSearchKeyboardOpen.value = false;
    _removeKeyboard(restoreNav: false);
    _stvBindFocusLabel(_focusNode, null);
    _focusNode.dispose();
    _kbSeedFocus.dispose();
    _textFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncFromNotifier() {
    final q = kSmartTvTopSearchQuery.value;
    if (_controller.text == q) return;
    _controller.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    if (mounted) setState(() {});
  }

  void _applyQuery(String raw, {bool immediate = false}) {
    final q = raw.trim();
    void commit() {
      if (_controller.text != raw && raw.isEmpty) {
        _controller.clear();
      }
      if (kSmartTvTopSearchQuery.value != q) {
        kSmartTvTopSearchQuery.value = q;
      }
      if (mounted) setState(() {});
    }

    _debounce?.cancel();
    if (immediate) {
      if (_controller.text != raw) {
        _controller.value = TextEditingValue(
          text: raw,
          selection: TextSelection.collapsed(offset: raw.length),
        );
      }
      commit();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), commit);
    if (mounted) setState(() {});
  }

  void _insertChar(String ch) {
    final t = _controller.text;
    _controller.value = TextEditingValue(
      text: '$t$ch',
      selection: TextSelection.collapsed(offset: t.length + ch.length),
    );
    _applyQuery(_controller.text);
  }

  void _backspace() {
    final t = _controller.text;
    if (t.isEmpty) return;
    _controller.value = TextEditingValue(
      text: t.substring(0, t.length - 1),
      selection: TextSelection.collapsed(offset: t.length - 1),
    );
    _applyQuery(_controller.text);
  }

  void _removeKeyboard({required bool restoreNav}) {
    final wasOpen = _kbOpen;
    // ثبّت الاستعلام قبل إغلاق الكلافيي (مثل debounce Smart TV).
    _debounce?.cancel();
    final q = _controller.text.trim();
    if (kSmartTvTopSearchQuery.value != q) {
      kSmartTvTopSearchQuery.value = q;
    }
    _kbOverlay?.remove();
    _kbOverlay = null;
    _kbOpen = false;
    kSmartTvTopSearchKeyboardOpen.value = false;
    if (wasOpen && mounted) setState(() {});
    try {
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {}
    if (!restoreNav || !mounted) return;
    // بعد Done: نتائج البحث أولاً، وإلا أول فئة — ليس خانة البحث.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cb = widget.onSearchClosed;
      if (cb != null) {
        cb();
        return;
      }
      if (_focusNode.canRequestFocus) _focusNode.requestFocus();
    });
  }

  void _openKeyboard() {
    if (!isTv(context)) {
      _textFocus.requestFocus();
      return;
    }
    if (_kbOpen) return;
    try {
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {}
    _kbOpen = true;
    kSmartTvTopSearchKeyboardOpen.value = true;
    setState(() {});
    _kbOverlay = OverlayEntry(
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Positioned(
          left: 16,
          right: 16,
          bottom: bottom + 12,
          child: Material(
            color: Colors.transparent,
            child: AppTvSideKeyboard(
              seedFocus: _kbSeedFocus,
              onChar: _insertChar,
              onBackspace: _backspace,
              onPrimary: () => _removeKeyboard(restoreNav: true),
              onDismiss: () => _removeKeyboard(restoreNav: true),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_kbOverlay!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_kbOpen) return;
      if (_kbSeedFocus.canRequestFocus) _kbSeedFocus.requestFocus();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      _openKeyboard();
      return KeyEventResult.handled;
    }
    return _smartTvTopBarKey(
      node,
      event,
      isFirstInRow: false,
      isLastInRow: false,
      onActivate: _openKeyboard,
      onArrowDownToContent: widget.onArrowDownToContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focused || _kbOpen || _textFocus.hasFocus;
    final query = _controller.text;
    final hint = _stvTopSearchPlaceholder(widget.selected);
    final compact = widget.compact;
    final phone = !isTv(context);
    // نفس شكل التلفاز؛ على الموبايل أصغر ومتوازن مع أيقونات 32px.
    final pillW = compact ? 108.0 : 168.0;
    final pillH = compact ? 32.0 : 38.0;
    final iconSz = compact ? 15.0 : 16.0;
    final fontSz = compact ? 11.5 : 12.0;
    final padH = compact ? 8.0 : 10.0;

    return Focus(
      focusNode: _focusNode,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openKeyboard,
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          width: pillW,
          height: pillH,
          padding: EdgeInsets.symmetric(horizontal: padH),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2D34),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused ? kColorFocus : Colors.white24,
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: kColorFocus.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: iconSz,
                color: focused ? kColorFocus : Colors.white70,
              ),
              SizedBox(width: compact ? 5 : 6),
              Expanded(
                child: phone
                    ? TextField(
                        focusNode: _textFocus,
                        controller: _controller,
                        onChanged: (v) => _applyQuery(v),
                        onTap: () => setState(() {}),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSz,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                        cursorColor: kColorFocus,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: hint,
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: fontSz,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      )
                    : Text(
                        query.isEmpty ? hint : query,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: query.isEmpty
                              ? Colors.white.withValues(alpha: 0.55)
                              : Colors.white,
                          fontSize: fontSz,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              if (query.isNotEmpty)
                GestureDetector(
                  onTap: () => _applyQuery('', immediate: true),
                  child: Icon(
                    Icons.close_rounded,
                    size: compact ? 13 : 14,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmartTvNotificationsBtn extends StatefulWidget {
  const _SmartTvNotificationsBtn({
    this.onArrowDownToContent,
    this.compact = false,
    this.boxSize,
  });

  final VoidCallback? onArrowDownToContent;
  final bool compact;
  final double? boxSize;

  @override
  State<_SmartTvNotificationsBtn> createState() =>
      _SmartTvNotificationsBtnState();
}

class _SmartTvNotificationsBtnState extends State<_SmartTvNotificationsBtn> {
  bool _focused = false;
  late final FocusNode _focusNode = FocusNode(
    debugLabel: _stvTopLabel('notifications'),
  );

  @override
  void initState() {
    super.initState();
    NotificationInboxService.instance.ensureLoaded();
    _stvBindFocusLabel(_focusNode, _stvTopLabel('notifications'));
  }

  @override
  void dispose() {
    _stvBindFocusLabel(_focusNode, null);
    _focusNode.dispose();
    super.dispose();
  }

  void _open() => Get.toNamed(screenNotifications);

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    final size = widget.boxSize ?? (widget.compact ? 30.0 : 42.0);
    final iconSize = size * 0.42;
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      onKeyEvent: (node, event) => _smartTvTopBarKey(
        node,
        event,
        isFirstInRow: false,
        isLastInRow: false,
        onActivate: _open,
        onArrowDownToContent: widget.onArrowDownToContent,
      ),
      child: Tooltip(
        message: 'notifications_inbox_title'.tr,
        child: InkWell(
          onTap: _open,
          canRequestFocus: false,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: kFocusAnimDuration,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2A2D34),
              border: Border.all(
                color: focused ? kColorFocus : Colors.white24,
                width: focused ? 2 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: kColorFocus.withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: ValueListenableBuilder<int>(
              valueListenable: NotificationInboxService.instance.unreadCount,
              builder: (context, unread, _) {
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      FontAwesomeIcons.bell,
                      size: iconSize,
                      color: focused ? kColorFocus : Colors.white70,
                    ),
                    if (unread > 0)
                      Positioned(
                        right: widget.compact ? -4 : -6,
                        top: widget.compact ? -4 : -6,
                        child: Container(
                          constraints: BoxConstraints(
                            minWidth: widget.compact ? 12 : 16,
                            minHeight: widget.compact ? 12 : 16,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: kColorPrimary,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFF2A2D34),
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: widget.compact ? 8 : 9,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SmartTvCircleIconBtn extends StatefulWidget {
  const _SmartTvCircleIconBtn({
    required this.asset,
    required this.onTap,
    this.tooltip = '',
    this.isLastInRow = false,
    this.focusDebugLabel,
    this.onArrowDownToContent,
    this.compact = false,
    this.boxSize,
  });

  final String asset;
  final VoidCallback onTap;
  final String tooltip;
  final bool isLastInRow;
  final String? focusDebugLabel;
  final VoidCallback? onArrowDownToContent;
  final bool compact;
  final double? boxSize;

  @override
  State<_SmartTvCircleIconBtn> createState() => _SmartTvCircleIconBtnState();
}

class _SmartTvCircleIconBtnState extends State<_SmartTvCircleIconBtn> {
  bool _focused = false;
  late final FocusNode _focusNode = FocusNode(
    debugLabel: widget.focusDebugLabel,
  );

  @override
  void initState() {
    super.initState();
    _stvBindFocusLabel(_focusNode, widget.focusDebugLabel);
  }

  @override
  void dispose() {
    _stvBindFocusLabel(_focusNode, null);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    final size = widget.boxSize ?? (widget.compact ? 30.0 : 42.0);
    final iconSize = size * 0.48;
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      onKeyEvent: (node, event) => _smartTvTopBarKey(
        node,
        event,
        isFirstInRow: false,
        isLastInRow: widget.isLastInRow,
        onActivate: widget.onTap,
        onArrowDownToContent: widget.onArrowDownToContent,
      ),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          onTap: widget.onTap,
          canRequestFocus: false,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: kFocusAnimDuration,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2A2D34),
              border: Border.all(
                color: focused ? kColorFocus : Colors.white24,
                width: focused ? 2 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: kColorFocus.withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Image.asset(
              widget.asset,
              width: iconSize,
              height: iconSize,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => Icon(
                Icons.circle,
                color: Colors.white70,
                size: iconSize * 0.9,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmartTvProfileBtn extends StatefulWidget {
  const _SmartTvProfileBtn({
    this.onArrowDownToContent,
    this.compact = false,
    this.boxSize,
  });

  final VoidCallback? onArrowDownToContent;
  final bool compact;
  final double? boxSize;

  @override
  State<_SmartTvProfileBtn> createState() => _SmartTvProfileBtnState();
}

class _SmartTvProfileBtnState extends State<_SmartTvProfileBtn>
    with WidgetsBindingObserver {
  bool _focused = false;
  late final FocusNode _focusNode = FocusNode(
    debugLabel: _stvTopLabel('profile'),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stvBindFocusLabel(_focusNode, _stvTopLabel('profile'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stvBindFocusLabel(_focusNode, null);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  Future<void> _open() async {
    await Get.toNamed(screenManageAccounts);
    if (mounted) setState(() {});
  }

  Widget _avatarImage() {
    final account = SavedAccountsRepository.getActiveAccount();
    if (account != null) {
      final file = account.avatarFile?.trim() ?? '';
      if (file.isNotEmpty && File(file).existsSync()) {
        return Image.file(
          File(file),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              Image.asset(kSmartTvNavProfile, fit: BoxFit.cover),
        );
      }
      final asset = account.avatarAsset?.trim() ?? '';
      if (asset.isNotEmpty && ProfileAvatars.isPreset(asset)) {
        return Image.asset(
          ProfileAvatars.assetPath(asset),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              Image.asset(kSmartTvNavProfile, fit: BoxFit.cover),
        );
      }
    }
    return Image.asset(
      kSmartTvNavProfile,
      width: 20,
      height: 20,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.person, color: Colors.white70, size: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    final size = widget.boxSize ?? (widget.compact ? 30.0 : 42.0);
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      onKeyEvent: (node, event) => _smartTvTopBarKey(
        node,
        event,
        isFirstInRow: false,
        isLastInRow: false,
        onActivate: _open,
        onArrowDownToContent: widget.onArrowDownToContent,
      ),
      child: Tooltip(
        message: 'manage_accounts_title'.tr,
        child: InkWell(
          onTap: _open,
          canRequestFocus: false,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: kFocusAnimDuration,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2A2D34),
              border: Border.all(
                color: focused ? kColorFocus : Colors.white24,
                width: focused ? 2 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: kColorFocus.withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: _avatarImage(),
          ),
        ),
      ),
    );
  }
}

class _SmartTvWifiIcon extends StatefulWidget {
  const _SmartTvWifiIcon({this.compact = false, this.boxSize});

  final bool compact;
  final double? boxSize;
  @override
  State<_SmartTvWifiIcon> createState() => _SmartTvWifiIconState();
}

class _SmartTvWifiIconState extends State<_SmartTvWifiIcon>
    with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = true;

  static bool _resultsOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final online = _resultsOnline(results);
      if (!mounted || online == _online) return;
      setState(() => _online = online);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final online = _resultsOnline(results);
      if (!mounted || online == _online) return;
      setState(() => _online = online);
    } catch (_) {
      if (!mounted || _online) return;
      setState(() => _online = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.boxSize ?? (widget.compact ? 30.0 : 42.0);
    final iconSize = size * 0.48;
    // مؤشر فقط — غير قابل للفوكس حتى لا يقطع مسار الريموت.
    return ExcludeFocus(
      child: Tooltip(
        message: _online ? 'wifi_online'.tr : 'wifi_offline'.tr,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2A2D34),
            border: Border.all(
              color: _online
                  ? Colors.white24
                  : const Color(0xFFE53935).withValues(alpha: 0.65),
            ),
          ),
          alignment: Alignment.center,
          child: Image.asset(
            _online ? kSmartTvNavWifi : kSmartTvNavNoWifi,
            width: iconSize,
            height: iconSize,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => Icon(
              _online ? Icons.wifi : Icons.wifi_off,
              color: _online ? Colors.white70 : const Color(0xFFFF8A80),
              size: iconSize * 0.9,
            ),
          ),
        ),
      ),
    );
  }
}
