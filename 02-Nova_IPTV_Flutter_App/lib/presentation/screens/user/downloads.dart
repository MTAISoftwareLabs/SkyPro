part of '../screens.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with LandscapeMainAppStateMixin<DownloadsScreen> {
  late final FocusNode _backFocusNode;
  late final FocusNode _firstContentFocusNode;
  bool _backFocused = false;

  static bool _isKeyDown(KeyEvent event) =>
      event is KeyDownEvent || event is KeyRepeatEvent;

  @override
  void initState() {
    super.initState();
    _backFocusNode = FocusNode(
      debugLabel: 'downloads_back',
      onKeyEvent: (n, e) {
        if (!_isKeyDown(e)) return KeyEventResult.ignored;
        final key = e.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.browserBack) {
          Get.back();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowRight) {
          if (_firstContentFocusNode.canRequestFocus) {
            _firstContentFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
    _backFocusNode.addListener(_onBackFocusChanged);
    _firstContentFocusNode = FocusNode(debugLabel: 'downloads_first');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DownloadsCubit>().refresh();
      _backFocusNode.requestFocus();
    });
  }

  void _onBackFocusChanged() {
    if (!mounted) return;
    final has = _backFocusNode.hasFocus;
    if (_backFocused != has) setState(() => _backFocused = has);
  }

  @override
  void dispose() {
    _backFocusNode.removeListener(_onBackFocusChanged);
    _backFocusNode.dispose();
    _firstContentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(DownloadedMovie item) async {
    final ok = await AppActionConfirmDialog.show(
      context,
      icon: LucideIcons.trash_2,
      accent: const Color(0xFFD32F2F),
      title: 'delete'.tr,
      message: 'sure_delete'.tr,
      highlight: item.name,
      confirmLabel: 'delete'.tr,
      cancelLabel: 'no'.tr,
      confirmIcon: LucideIcons.trash_2,
      cancelIcon: LucideIcons.x,
    );
    if (ok != true || !mounted) return;
    await context.read<DownloadsCubit>().deleteItem(item);
    if (!mounted) return;
    showInfoToast(context, 'delete'.tr, 'file_deleted'.tr);
  }

  void _play(DownloadedMovie item) {
    final cubit = context.read<DownloadsCubit>();
    final link = cubit.playablePath(item);
    if (link.isEmpty) return;
    Get.to(
      () => FullVideoScreen(
        link: link,
        title: item.name,
        isLive: false,
      ),
    );
  }

  int _crossAxisCount(BuildContext context) {
    final tv = isTv(context);
    final w = MediaQuery.sizeOf(context).width;
    if (tv) return w >= 1600 ? 12 : 10;
    if (w >= 1000) return 9;
    if (w >= 700) return 7;
    return 5;
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
          child: Padding(
            padding: EdgeInsets.fromLTRB(tv ? 28 : 16, 10, tv ? 28 : 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Focus(
                      focusNode: _backFocusNode,
                      child: Builder(
                        builder: (ctx) {
                          final showFocus =
                              settingsShowFocusDecor(ctx, _backFocused);
                          return AnimatedScale(
                            scale: kTvFocusScale(showFocus, 1.08),
                            duration: kFocusAnimDuration,
                            curve: Curves.easeOut,
                            child: AnimatedContainer(
                              duration: kFocusAnimDuration,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: showFocus
                                      ? kColorFocus
                                      : Colors.transparent,
                                  width: showFocus ? 2.5 : 0,
                                ),
                                boxShadow: kTvFocusGlow(
                                  focused: showFocus,
                                ),
                              ),
                              child: Material(
                                color: showFocus
                                    ? kColorFocus.withValues(alpha: 0.18)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => Get.back(),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      color: Colors.white,
                                      size: tv ? 22 : 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Icon(
                      LucideIcons.download,
                      color: kColorPrimary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'downloads'.tr,
                      style: Get.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    BlocBuilder<DownloadsCubit, DownloadsState>(
                      buildWhen: (p, c) =>
                          p.availableGb != c.availableGb ||
                          p.totalGb != c.totalGb ||
                          p.storageKnown != c.storageKnown ||
                          p.items != c.items,
                      builder: (context, state) {
                        if (state.totalGb <= 0 && state.items.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final usedRatio = state.storageKnown && state.totalGb > 0
                            ? (1 - (state.availableGb / state.totalGb))
                                .clamp(0.0, 1.0)
                            : 0.35;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: kColorCardDark.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.sd_storage_rounded,
                                size: 18,
                                color: kColorPrimary,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.storageKnown
                                        ? 'download_storage_available'.trParams({
                                            'gb': state.availableGb
                                                .toStringAsFixed(2),
                                          })
                                        : 'download_storage_used'.trParams({
                                            'gb': state.availableGb
                                                .toStringAsFixed(2),
                                          }),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 140,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: usedRatio,
                                        minHeight: 5,
                                        backgroundColor: Colors.white24,
                                        color: kColorPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    state.storageKnown
                                        ? 'download_storage_total'.trParams({
                                            'gb': state.totalGb
                                                .toStringAsFixed(2),
                                          })
                                        : 'download_storage_internal'.tr,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: BlocBuilder<DownloadsCubit, DownloadsState>(
                    builder: (context, state) {
                      if (state.loading) {
                        return Center(
                          child: CircularProgressIndicator(color: kColorPrimary),
                        );
                      }
                      if (state.items.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.download,
                                size: 42,
                                color: Colors.white.withValues(alpha: 0.28),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'no_downloads'.tr,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final count = _crossAxisCount(context);
                      return GridView.builder(
                        padding: const EdgeInsets.only(bottom: 20),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: 0.62,
                        ),
                        itemCount: state.items.length,
                        itemBuilder: (context, i) {
                          final item = state.items[i];
                          final focus = i == 0 ? _firstContentFocusNode : null;
                          return _DownloadPosterCard(
                            item: item,
                            focusNode: focus,
                            onPlay: () => _play(item),
                            onDelete: () => unawaited(_confirmDelete(item)),
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
      ),
    );
  }
}

class _DownloadPosterCard extends StatefulWidget {
  const _DownloadPosterCard({
    required this.item,
    required this.onPlay,
    required this.onDelete,
    this.focusNode,
  });

  final DownloadedMovie item;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final FocusNode? focusNode;

  @override
  State<_DownloadPosterCard> createState() => _DownloadPosterCardState();
}

class _DownloadPosterCardState extends State<_DownloadPosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final poster = widget.item.localPosterPath;
    final hasLocalPoster = poster.isNotEmpty && File(poster).existsSync();
    final remote = resolveImageUrl(widget.item.streamIcon, null);

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space) {
          widget.onPlay();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPlay,
          onLongPress: widget.onDelete,
          borderRadius: BorderRadius.circular(10),
          focusColor: Colors.transparent,
          canRequestFocus: widget.focusNode == null,
          child: AnimatedContainer(
            duration: kFocusAnimDuration,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focused ? kColorFocus : Colors.transparent,
                width: _focused ? 2.2 : 0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: hasLocalPoster
                        ? Image.file(
                            File(poster),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, _, _) => noPosterImage(),
                          )
                        : remote.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: remote,
                                cacheManager: iptvImageCacheManager,
                                fit: BoxFit.cover,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, _) =>
                                    posterCardImageLoadingPlaceholder(),
                                errorWidget: (_, _, _) => noPosterImage(),
                              )
                            : noPosterImage(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                  child: Text(
                  widget.item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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
