part of 'widgets.dart';

class AppBarMovie extends StatefulWidget {
  const AppBarMovie({
    super.key,
    this.onSearch,
    this.onFavorite,
    this.top,
    this.isLiked = false,
    this.opaque = false,
  });

  final Function()? onFavorite;
  final Function(String)? onSearch;
  final double? top;
  final bool isLiked;
  final bool opaque;

  @override
  State<AppBarMovie> createState() => AppBarMovieState();
}

class AppBarMovieState extends State<AppBarMovie> {
  bool showSearch = false;
  final _search = TextEditingController();
  final FocusNode _searchFieldFocus = FocusNode();

  /// يطوي شريط البحث دون مسح النص (تبقى نتائج البحث في الشبكة).
  void collapseSearchKeepQuery() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted || !showSearch) return;
    setState(() => showSearch = false);
  }

  @override
  void dispose() {
    _searchFieldFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100.w,
      color: widget.opaque
          ? kColorAppBar
          : Colors.transparent,
      margin: EdgeInsets.symmetric(
        horizontal: widget.opaque ? 0 : 10,
        vertical: widget.opaque ? 0 : (widget.top ?? 15),
      ),
      child: Material(
        color: widget.opaque ? kColorAppBar : Colors.transparent,
        child: Row(
          children: [
            const Image(width: 40, height: 40, image: AssetImage(kIconSplash)),
            const SizedBox(width: 5),
            Text(appName, style: Get.textTheme.headlineMedium),
            Container(
              width: 1,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 13),
              color: kColorHint,
            ),
            const Image(height: 40, image: AssetImage(kIconMovies)),
            const Spacer(),
            showSearch
                ? Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(left: 15),
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFieldFocus,
                      autofocus: false,
                      onChanged: widget.onSearch,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'search'.tr,
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white54),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                )
                : const Spacer(),
            if (showSearch)
              IconButton(
                icon: const Icon(FontAwesomeIcons.xmark, color: Colors.white),
                focusColor: kColorPrimary,
                onPressed: () {
                  if (widget.onSearch != null) {
                    widget.onSearch!("");
                  }

                  setState(() {
                    showSearch = false;
                    _search.clear();
                  });
                },
              ),
            if (widget.onSearch != null)
              if (!showSearch)
                IconButton(
                  focusColor: kColorFocus,
                  onPressed: () {
                    setState(() {
                      showSearch = true;
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _searchFieldFocus.requestFocus();
                    });
                  },
                  icon: const Icon(
                    FontAwesomeIcons.magnifyingGlass,
                    color: Colors.white,
                  ),
                ),
            if (widget.onFavorite != null)
              IconButton(
                focusColor: kColorFocus,
                onPressed: widget.onFavorite,
                icon: Icon(
                  widget.isLiked
                      ? FontAwesomeIcons.solidHeart
                      : FontAwesomeIcons.heart,
                  color: Colors.white,
                ),
              ),
            IconButton(
              focusColor: kColorFocus,
              onPressed: () {
                Get.back();
              },
              icon: const Icon(
                FontAwesomeIcons.chevronRight,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppBarSeries extends StatefulWidget {
  const AppBarSeries({
    super.key,
    this.onSearch,
    this.onFavorite,
    this.top,
    this.isLiked = false,
    this.opaque = false,
  });

  final Function()? onFavorite;
  final Function(String)? onSearch;
  final double? top;
  final bool isLiked;
  final bool opaque;

  @override
  State<AppBarSeries> createState() => AppBarSeriesState();
}

class AppBarSeriesState extends State<AppBarSeries> {
  bool showSearch = false;
  final _search = TextEditingController();
  final FocusNode _searchFieldFocus = FocusNode();

  void collapseSearchKeepQuery() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted || !showSearch) return;
    setState(() => showSearch = false);
  }

  @override
  void dispose() {
    _searchFieldFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.opaque
          ? kColorAppBar
          : Colors.transparent,
      margin: EdgeInsets.only(
        top: widget.opaque ? 0 : (widget.top ?? 4.h),
        left: widget.opaque ? 0 : 10,
        right: widget.opaque ? 0 : 10,
      ),
      child: Material(
        color: widget.opaque
            ? kColorAppBar
            : Colors.transparent,
        child: Row(
          children: [
            Image(
              width: 0.3.dp,
              height: 0.3.dp,
              image: const AssetImage(kIconSplash),
            ),
            const SizedBox(width: 5),
            Text(appName, style: Get.textTheme.headlineMedium),
            Container(
              width: 1,
              height: 8.h,
              margin: const EdgeInsets.symmetric(horizontal: 13),
              color: kColorHint,
            ),
            Image(height: 9.h, image: const AssetImage(kIconSeries)),
            const Spacer(),
            showSearch
                ? Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(left: 15),
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFieldFocus,
                      autofocus: false,
                      onChanged: widget.onSearch,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'search'.tr,
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white54),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                )
                : const Spacer(),
            if (showSearch)
              IconButton(
                icon: const Icon(FontAwesomeIcons.xmark, color: Colors.white),
                focusColor: kColorPrimary,
                onPressed: () {
                  if (widget.onSearch != null) {
                    widget.onSearch!("");
                  }

                  setState(() {
                    showSearch = false;
                    _search.clear();
                  });
                },
              ),
            if (widget.onSearch != null)
              if (!showSearch)
                IconButton(
                  focusColor: kColorFocus,
                  onPressed: () {
                    setState(() {
                      showSearch = true;
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _searchFieldFocus.requestFocus();
                    });
                  },
                  icon: const Icon(
                    FontAwesomeIcons.magnifyingGlass,
                    color: Colors.white,
                  ),
                ),
            if (widget.onFavorite != null)
              IconButton(
                focusColor: kColorFocus,
                onPressed: widget.onFavorite,
                icon: Icon(
                  widget.isLiked
                      ? FontAwesomeIcons.solidHeart
                      : FontAwesomeIcons.heart,
                  color: Colors.white,
                ),
              ),
            IconButton(
              focusColor: kColorFocus,
              onPressed: () {
                Get.back();
              },
              icon: const Icon(
                FontAwesomeIcons.chevronRight,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppBarSettings extends StatelessWidget {
  const AppBarSettings({super.key, this.tvBackFocusOrder});

  /// ترتيب زر الرجوع في التنقل بالريموت (إعدادات).
  final double? tvBackFocusOrder;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    Widget backButton = ValueListenableBuilder<int>(
      valueListenable: homeThemeRevision,
      builder: (context, revision, _) {
        return _SettingsTvBackButton(
          key: ValueKey('settings_back_$revision'),
          autofocusOnOpen: tv && settingsInitialBackFocusPending,
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Get.back();
          },
        );
      },
    );
    if (tv && tvBackFocusOrder != null) {
      backButton = FocusTraversalOrder(
        order: NumericFocusOrder(tvBackFocusOrder!),
        child: backButton,
      );
    }
    return SizedBox(
      width: 100.w,
      height: 44,
      child: Row(
        children: [
          Image(
            width: 28,
            height: 28,
            image: const AssetImage(kIconSplash),
          ),
          const SizedBox(width: 8),
          Text(
            'settings'.tr,
            style: Get.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: Colors.white24,
          ),
          Icon(FontAwesomeIcons.gear, size: 15, color: kColorPrimary),
          const Spacer(),
          backButton,
        ],
      ),
    );
  }
}

class _SettingsTvBackButton extends StatefulWidget {
  const _SettingsTvBackButton({
    super.key,
    required this.onPressed,
    this.autofocusOnOpen = false,
  });

  final VoidCallback onPressed;
  final bool autofocusOnOpen;

  @override
  State<_SettingsTvBackButton> createState() => _SettingsTvBackButtonState();
}

class _SettingsTvBackButtonState extends State<_SettingsTvBackButton> {
  final FocusNode _focus = FocusNode(debugLabel: 'settings_back');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      settingsTryInitialBackFocus(context, _focus);
    });
  }

  void _onFocusChanged() {
    if (!mounted) return;
    final has = _focus.hasFocus;
    if (_focused != has) setState(() => _focused = has);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showFocus = settingsShowFocusDecor(context, _focused);
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocusOnOpen && isTv(context),
      onKeyEvent: (node, event) {
        return settingsTvActivateOnSelect(event, widget.onPressed);
      },
      child: AnimatedContainer(
        duration: kFocusAnimDuration,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: showFocus ? kColorFocus : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: settingsThemedFocusGlow(showFocus),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? FontAwesomeIcons.chevronLeft
                    : FontAwesomeIcons.chevronRight,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CardLiveItem extends StatelessWidget {
  const CardLiveItem({
    super.key,
    required this.title,
    required this.onTap,
    this.onLongPress,
    this.link,
    this.image,
    this.assetImage,
  });
  final String title;
  final Function() onTap;
  final VoidCallback? onLongPress;
  final String? link;
  final String? image;
  final String? assetImage;

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final serverUrl = authState is AuthSuccess
        ? authState.user.serverInfo?.serverUrl
        : null;
    final img = resolveImageUrl(image, serverUrl);
    final hasImage = img.isNotEmpty && img.toLowerCase() != 'null';
    // نفس سلوك كروت الأفلام (CardChannelMovieItem): InkWell يستقبل التركيز مباشرة + focusColor
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      focusColor: kColorFocus,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        decoration: BoxDecoration(
          color: kColorCardLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
                child:
                    assetImage != null
                        ? Image.asset(
                          assetImage!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        )
                        : hasImage
                        ? LayoutBuilder(
                          builder: (context, constraints) {
                            final lw =
                                constraints.maxWidth.isFinite &&
                                        constraints.maxWidth > 0
                                    ? constraints.maxWidth
                                    : 120.0;
                            final lh =
                                constraints.maxHeight.isFinite &&
                                        constraints.maxHeight > 0
                                    ? constraints.maxHeight
                                    : lw;
                            final mem = iptvMemCachePx(context, lw, lh);
                            return CachedNetworkImage(
                              imageUrl: img,
                              cacheManager: iptvImageCacheManager,
                              memCacheWidth: mem.$1,
                              memCacheHeight: mem.$2,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              errorWidget:
                                  (_, _, _) => Container(
                                    color: kColorCardLight,
                                    alignment: Alignment.center,
                                    child: Icon(
                                      FontAwesomeIcons.tv,
                                      size: 22.sp,
                                      color: Colors.white,
                                    ),
                                  ),
                              placeholder:
                                  (_, _) =>
                                      posterCardImageLoadingPlaceholder(),
                            );
                          },
                        )
                        : Container(
                          color: kColorCardLight,
                          alignment: Alignment.center,
                          child: Icon(
                            FontAwesomeIcons.tv,
                            size: 22.sp,
                            color: Colors.white,
                          ),
                        ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Text(
                sanitizeDisplayTitle(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Get.textTheme.titleLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

