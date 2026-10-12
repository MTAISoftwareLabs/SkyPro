part of '../screens.dart';

/// Poster slot inside suggestion list items (itemExtent minus card padding).
const double _kSuggestionItemWidth = 112.0;
const double _kSuggestionItemHeight = 172.0;
const double _kSuggestionCardPadH = 5.0;
const double _kSuggestionCardPadV = 4.0;
const double _kSuggestionPosterWidth =
    _kSuggestionItemWidth - _kSuggestionCardPadH * 2;
const double _kSuggestionPosterHeight =
    _kSuggestionItemHeight - _kSuggestionCardPadV * 2;

// ---------------------------------------------------------------------------
// قائمة الأفلام المقترحة – تظهر أسفل الشاشة بالعرض عند ضغط سهم الأسفل
// ---------------------------------------------------------------------------
class _MovieSuggestionsOverlay extends StatefulWidget {
  const _MovieSuggestionsOverlay({
    super.key,
    required this.focusNode,
    required this.isVisible,
    required this.currentMovie,
    this.userAuth,
    this.topClipPadding = 0.0,
    required this.onMovieSelected,
    required this.onDismiss,
  });

  final FocusNode focusNode;
  final bool isVisible;
  final ChannelMovie? currentMovie;
  final UserModel? userAuth;
  final double topClipPadding;
  final void Function(ChannelMovie movie, String link) onMovieSelected;
  final VoidCallback onDismiss;

  @override
  State<_MovieSuggestionsOverlay> createState() =>
      _MovieSuggestionsOverlayState();
}

class _MovieSuggestionsOverlayState extends State<_MovieSuggestionsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  final ScrollController _scrollCtrl = ScrollController();
  late final ValueNotifier<int> _selectedIndexVN;
  // نخزن الأفلام محلياً حتى لا نعيد البناء عند كل تحديث
  List<ChannelMovie> _movies = [];
  UserModel? _userAuth;
  bool _initialScrollDone = false;
  bool _loadDispatched = false;

  static const double _kItemWidth = _kSuggestionItemWidth;
  static const double _kItemHeight = _kSuggestionItemHeight;
  static const double _kOverlayHeight = 210.0;
  static const int _kItemsBeforeFocused = 3;

  @override
  void initState() {
    super.initState();
    _userAuth = widget.userAuth;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);

    _selectedIndexVN = ValueNotifier<int>(0);

    // تحميل الأفلام مرة واحدة عند أول بناء
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadMovies();
    });
  }

  @override
  void didUpdateWidget(_MovieSuggestionsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userAuth != null) _userAuth ??= widget.userAuth;
    // عند كل مرة تصبح القائمة مرئية نُشغّل الأنيميشن ونطلب الـ Focus
    if (widget.isVisible && !oldWidget.isVisible) {
      _initialScrollDone = false;
      _animController.forward(from: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && isTvDevice(context)) {
          widget.focusNode.requestFocus();
        }
      });
    }
  }

  void _loadMovies() {
    if (_loadDispatched) return;
    _userAuth ??= widget.userAuth;
    if (_userAuth == null) {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthSuccess) _userAuth = authState.user;
    }
    final catId = widget.currentMovie?.categoryId ?? '';
    if (catId.isNotEmpty) {
      _loadDispatched = true;
      context.read<ChannelsBloc>().add(
        GetLiveChannelsEvent(typeCategory: TypeCategory.movies, catyId: catId),
      );
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollCtrl.dispose();
    _selectedIndexVN.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final maxExtent = pos.maxScrollExtent;
    final leftIndex =
        index >= _kItemsBeforeFocused ? index - _kItemsBeforeFocused : 0;
    final offset = (leftIndex * _kItemWidth).clamp(0.0, maxExtent);
    _scrollCtrl.jumpTo(offset);
  }

  String _buildMovieLink(ChannelMovie movie, UserModel userAuth) {
    final sid = movie.streamId?.toString() ?? '';
    // إذا كان الـ streamId رابطاً كاملاً نرجعه مباشرة
    if (sid.startsWith('http://') || sid.startsWith('https://')) return sid;
    final base =
        userAuth.serverInfo?.serverUrl ?? userAuth.serverInfo?.url ?? '';
    final user = userAuth.userInfo?.username ?? '';
    final pass = userAuth.userInfo?.password ?? '';
    // رابط الفيلم القياسي في Xtream Codes:
    // serverUrl/movie/username/password/streamId.ext
    final ext = movie.containerExtension;
    if (ext != null && ext.isNotEmpty) {
      return '$base/movie/$user/$pass/$sid.$ext';
    }
    return '$base/movie/$user/$pass/$sid';
  }

  void _selectCurrent() {
    if (_movies.isEmpty) return;
    final idx = _selectedIndexVN.value;
    if (idx < 0 || idx >= _movies.length) return;
    final movie = _movies[idx];
    if (_userAuth == null) return;
    final link = _buildMovieLink(movie, _userAuth!);
    widget.onMovieSelected(movie, link);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Focus(
              focusNode: widget.focusNode,
              canRequestFocus: isTvDevice(context),
              skipTraversal: !widget.isVisible || !isTvDevice(context),
              onKeyEvent: (node, event) {
                if (!widget.isVisible) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (event is KeyRepeatEvent &&
                    key == LogicalKeyboardKey.arrowDown) {
                  return KeyEventResult.handled;
                }
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.arrowUp ||
                    key == LogicalKeyboardKey.browserBack) {
                  widget.onDismiss();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowLeft) {
                  final idx = _selectedIndexVN.value;
                  if (idx > 0) {
                    _selectedIndexVN.value = idx - 1;
                    _scrollToIndex(idx - 1);
                  }
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight) {
                  final idx = _selectedIndexVN.value;
                  if (_movies.isNotEmpty && idx < _movies.length - 1) {
                    _selectedIndexVN.value = idx + 1;
                    _scrollToIndex(idx + 1);
                  }
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.numpadEnter ||
                    key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.space) {
                  _selectCurrent();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                height: _kOverlayHeight,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xDD000000),
                      Color(0x88000000),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                ),
                child: BlocBuilder<ChannelsBloc, ChannelsState>(
                  builder: (context, channelsState) {
                    final authState = context.read<AuthBloc>().state;
                    if (authState is AuthSuccess) _userAuth = authState.user;

                    final movies =
                        channelsState is ChannelsMovieSuccess
                            ? channelsState.channels
                            : <ChannelMovie>[];
                    _movies = movies;

                    if (movies.isNotEmpty && !_initialScrollDone) {
                      _initialScrollDone = true;
                      final idx = movies.indexWhere(
                        (m) => m.streamId == widget.currentMovie?.streamId,
                      );
                      final target = idx >= 0 ? idx : 0;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _selectedIndexVN.value = target;
                          _scrollToIndex(target);
                        }
                      });
                    }

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            bottom: 8,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: kColorPrimary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'movie_suggestions_title'.tr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 6),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'movie_suggestions_close_hint'.tr,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragUpdate: (details) {
                            if (movies.isEmpty || !_scrollCtrl.hasClients) {
                              return;
                            }
                            final current = _scrollCtrl.offset;
                            final delta =
                                -details.delta.dx; // سحب لليمين → عنصر سابق
                            final target = (current + delta).clamp(
                              0.0,
                              _scrollCtrl.position.maxScrollExtent,
                            );
                            _scrollCtrl.jumpTo(target);
                          },
                          child: SizedBox(
                            height: _kItemHeight,
                            child:
                                (channelsState is ChannelsLoading ||
                                        !_loadDispatched)
                                    ? Center(
                                      child: CircularProgressIndicator(
                                        color: kColorPrimary,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                    : movies.isEmpty
                                    ? Center(
                                      child: Text(
                                        'movie_suggestions_empty'.tr,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                    : ListView.builder(
                                      controller: _scrollCtrl,
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      itemCount: movies.length,
                                      itemExtent: _kItemWidth,
                                      itemBuilder: (ctx, i) {
                                        final movie = movies[i];
                                        final isCurrent =
                                            movie.streamId ==
                                            widget.currentMovie?.streamId;
                                        return ValueListenableBuilder<int>(
                                          valueListenable: _selectedIndexVN,
                                          builder:
                                              (ctx, sel, _) =>
                                                  _MovieSuggestionCard(
                                                    key: ValueKey(
                                                      movie.streamId ??
                                                          'movie_$i',
                                                    ),
                                                    movie: movie,
                                                    isFocused: sel == i,
                                                    isCurrent: isCurrent,
                                                    serverUrl:
                                                        _userAuth
                                                            ?.serverInfo
                                                            ?.serverUrl,
                                                    onTap: () {
                                                      _selectedIndexVN.value =
                                                          i;
                                                      _selectCurrent();
                                                    },
                                                  ),
                                        );
                                      },
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// قائمة حلقات المسلسل – نفس نمط _MovieSuggestionsOverlay تماماً
// ---------------------------------------------------------------------------
class _EpisodeSuggestionsOverlay extends StatefulWidget {
  const _EpisodeSuggestionsOverlay({
    super.key,
    required this.focusNode,
    required this.isVisible,
    required this.episodes,
    required this.currentEpisodeId,
    required this.userAuth,
    required this.channelSerie,
    this.topClipPadding = 0.0,
    required this.onEpisodeSelected,
    required this.onDismiss,
  });

  final FocusNode focusNode;
  final bool isVisible;
  final List<Episode?> episodes;
  final String? currentEpisodeId;
  final UserModel? userAuth;
  final ChannelSerie? channelSerie;
  final double topClipPadding;
  final void Function(Episode episode, String link) onEpisodeSelected;
  final VoidCallback onDismiss;

  @override
  State<_EpisodeSuggestionsOverlay> createState() =>
      _EpisodeSuggestionsOverlayState();
}

class _EpisodeSuggestionsOverlayState extends State<_EpisodeSuggestionsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  final ScrollController _scrollCtrl = ScrollController();
  late final ValueNotifier<int> _selectedIndexVN;
  bool _initialScrollDone = false;

  static const double _kItemWidth = _kSuggestionItemWidth;
  static const double _kItemHeight = _kSuggestionItemHeight;
  static const double _kOverlayHeight = 210.0;
  static const int _kItemsBeforeFocused = 3;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _selectedIndexVN = ValueNotifier<int>(0);
  }

  @override
  void didUpdateWidget(_EpisodeSuggestionsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _initialScrollDone = false;
      _animController.forward(from: 0);
      // تمرير للحلقة الحالية
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (isTvDevice(context)) widget.focusNode.requestFocus();
        if (!_initialScrollDone) {
          _initialScrollDone = true;
          final idx = widget.episodes.indexWhere(
            (e) => e?.id?.toString() == widget.currentEpisodeId,
          );
          final target = idx >= 0 ? idx : 0;
          _selectedIndexVN.value = target;
          _scrollToIndex(target);
        }
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollCtrl.dispose();
    _selectedIndexVN.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final maxExtent = pos.maxScrollExtent;
    final leftIndex =
        index >= _kItemsBeforeFocused ? index - _kItemsBeforeFocused : 0;
    _scrollCtrl.jumpTo((leftIndex * _kItemWidth).clamp(0.0, maxExtent));
  }

  String _buildEpisodeLink(Episode episode) {
    final userAuth = widget.userAuth;
    if (userAuth == null) return '';
    final base = userAuth.serverInfo?.serverUrl ?? '';
    final user = userAuth.userInfo?.username ?? '';
    final pass = userAuth.userInfo?.password ?? '';
    return '$base/series/$user/$pass/${episode.id}.${episode.containerExtension}';
  }

  void _selectCurrent() {
    final idx = _selectedIndexVN.value;
    final episodes = widget.episodes;
    if (idx < 0 || idx >= episodes.length) return;
    final ep = episodes[idx];
    if (ep == null) return;
    // لا نُشغّل نفس الحلقة مرة أخرى
    if (ep.id?.toString() == widget.currentEpisodeId) {
      widget.onDismiss();
      return;
    }
    final link = _buildEpisodeLink(ep);
    if (link.isEmpty) return;
    widget.onEpisodeSelected(ep, link);
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.episodes;
    return Padding(
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Focus(
              focusNode: widget.focusNode,
              canRequestFocus: isTvDevice(context),
              skipTraversal: !widget.isVisible || !isTvDevice(context),
              onKeyEvent: (node, event) {
                if (!widget.isVisible) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (event is KeyRepeatEvent &&
                    key == LogicalKeyboardKey.arrowDown) {
                  return KeyEventResult.handled;
                }
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.arrowUp ||
                    key == LogicalKeyboardKey.browserBack) {
                  widget.onDismiss();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowLeft) {
                  final idx = _selectedIndexVN.value;
                  if (idx > 0) {
                    _selectedIndexVN.value = idx - 1;
                    _scrollToIndex(idx - 1);
                  }
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight) {
                  final idx = _selectedIndexVN.value;
                  if (idx < episodes.length - 1) {
                    _selectedIndexVN.value = idx + 1;
                    _scrollToIndex(idx + 1);
                  }
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.numpadEnter ||
                    key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.space) {
                  _selectCurrent();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                height: _kOverlayHeight,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xDD000000),
                      Color(0x88000000),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 18,
                            decoration: BoxDecoration(
                              color: kColorPrimary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'episode_suggestions_title'.tr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 6),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'movie_suggestions_close_hint'.tr,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        if (episodes.isEmpty || !_scrollCtrl.hasClients) return;
                        final current = _scrollCtrl.offset;
                        final delta = -details.delta.dx;
                        final target = (current + delta).clamp(
                          0.0,
                          _scrollCtrl.position.maxScrollExtent,
                        );
                        _scrollCtrl.jumpTo(target);
                      },
                      child: SizedBox(
                        height: _kItemHeight,
                        child:
                            episodes.isEmpty
                                ? Center(
                                  child: Text(
                                    'episode_suggestions_empty'.tr,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                                : ListView.builder(
                                  controller: _scrollCtrl,
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  itemCount: episodes.length,
                                  itemExtent: _kItemWidth,
                                  itemBuilder: (ctx, i) {
                                    final ep = episodes[i];
                                    final isCurrent =
                                        ep?.id?.toString() ==
                                        widget.currentEpisodeId;
                                    final serverUrl =
                                        widget.userAuth?.serverInfo?.serverUrl;
                                    final seriesCover =
                                        widget.channelSerie?.cover
                                                        ?.trim()
                                                        .isNotEmpty ==
                                                    true &&
                                                widget.channelSerie?.cover !=
                                                    'null'
                                            ? widget.channelSerie!.cover
                                            : null;
                                    return ValueListenableBuilder<int>(
                                      valueListenable: _selectedIndexVN,
                                      builder:
                                          (ctx, sel, _) => _EpisodeCard(
                                            key: ValueKey(
                                              ep?.id?.toString() ?? 'ep_$i',
                                            ),
                                            episode: ep,
                                            index: i + 1,
                                            isFocused: sel == i,
                                            isCurrent: isCurrent,
                                            serverUrl: serverUrl,
                                            fallbackImageUrl: seriesCover,
                                            onTap: () {
                                              _selectedIndexVN.value = i;
                                              _selectCurrent();
                                            },
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
          ),
        ),
      ),
    );
  }
}

class _EpisodeCard extends StatefulWidget {
  const _EpisodeCard({
    super.key,
    required this.episode,
    required this.index,
    required this.isFocused,
    required this.isCurrent,
    required this.onTap,
    this.serverUrl,
    this.fallbackImageUrl,
  });

  final Episode? episode;
  final int index;
  final bool isFocused;
  final bool isCurrent;
  final VoidCallback onTap;
  final String? serverUrl;
  final String? fallbackImageUrl;

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _useFallbackImage = false;

  @override
  Widget build(BuildContext context) {
    final focused = widget.isFocused && isTvDevice(context);
    final primaryUrl = resolveImageUrl(
      widget.episode?.info?.movieImage,
      widget.serverUrl,
    );
    final fallbackUrl =
        (widget.fallbackImageUrl != null &&
                widget.fallbackImageUrl!.trim().isNotEmpty &&
                widget.fallbackImageUrl!.trim() != 'null')
            ? resolveImageUrl(widget.fallbackImageUrl, widget.serverUrl)
            : '';

    String imageUrl = primaryUrl;
    if (imageUrl.isEmpty && fallbackUrl.isNotEmpty) imageUrl = fallbackUrl;
    if (_useFallbackImage && fallbackUrl.isNotEmpty) imageUrl = fallbackUrl;

    final title =
        widget.episode?.title?.isNotEmpty == true
            ? widget.episode!.title!
            : 'Ep ${widget.index}';

    return GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _kSuggestionCardPadH,
          vertical: _kSuggestionCardPadV,
        ),
        child: SizedBox(
          width: _kSuggestionPosterWidth,
          height: _kSuggestionPosterHeight,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border:
                  focused
                      ? Border.all(color: kColorPrimary, width: 2.5)
                      : widget.isCurrent
                      ? Border.all(color: Colors.amber, width: 1.8)
                      : Border.all(color: Colors.white12, width: 1),
              boxShadow:
                  focused
                      ? [
                        BoxShadow(
                          color: kColorPrimary.withValues(alpha: 0.55),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ]
                      : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: _EpisodeCardPoster(
                      imageUrl: imageUrl,
                      fallbackUrl: fallbackUrl,
                      useFallbackImage: _useFallbackImage,
                      index: widget.index,
                      onNeedFallback: () {
                        if (!_useFallbackImage && mounted) {
                          setState(() => _useFallbackImage = true);
                        }
                      },
                    ),
                  ),
                // تدرج أسفل الكارت للعنوان
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 5,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xDD000000), Colors.transparent],
                      ),
                    ),
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight:
                            focused
                                ? FontWeight.bold
                                : FontWeight.w500,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),

                // رقم الحلقة في الأعلى
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${widget.index}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // مؤشر "يُشغَّل الآن"
                if (widget.isCurrent)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kColorPrimary.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '▶',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // هالة التركيز
                if (focused)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _SuggestionPosterImage extends StatelessWidget {
  const _SuggestionPosterImage({
    required this.imageUrl,
    this.cacheKey,
    this.errorLabel,
    this.onRetry,
  });

  final String imageUrl;
  final String? cacheKey;
  final String? errorLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      if (errorLabel != null) {
        return ColoredBox(
          color: Colors.grey.shade900,
          child: Center(
            child: Text(
              errorLabel!,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }
      return noPosterImage();
    }

    final mem = iptvMemCachePx(
      context,
      _kSuggestionPosterWidth,
      _kSuggestionPosterHeight,
    );

    return CachedNetworkImage(
      key: cacheKey != null ? ValueKey<String>(cacheKey!) : null,
      imageUrl: imageUrl,
      cacheManager: iptvImageCacheManager,
      memCacheWidth: mem.$1,
      memCacheHeight: mem.$2,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder:
          (_, _) => posterCardImageLoadingPlaceholder(
            backgroundColor: Colors.grey.shade900,
            size: 20,
          ),
      errorWidget: (_, _, _) {
        onRetry?.call();
        return ColoredBox(
          color: Colors.grey.shade900,
          child: errorLabel != null
              ? Center(
                  child: Text(
                    errorLabel!,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : noPosterImage(),
        );
      },
    );
  }
}

class _EpisodeCardPoster extends StatelessWidget {
  const _EpisodeCardPoster({
    required this.imageUrl,
    required this.fallbackUrl,
    required this.useFallbackImage,
    required this.index,
    required this.onNeedFallback,
  });

  final String imageUrl;
  final String fallbackUrl;
  final bool useFallbackImage;
  final int index;
  final VoidCallback onNeedFallback;

  @override
  Widget build(BuildContext context) {
    return _SuggestionPosterImage(
      imageUrl: imageUrl,
      cacheKey: 'ep_$index',
      errorLabel: 'EP $index',
      onRetry:
          fallbackUrl.isNotEmpty && !useFallbackImage ? onNeedFallback : null,
    );
  }
}

class _MovieSuggestionCard extends StatefulWidget {
  const _MovieSuggestionCard({
    super.key,
    required this.movie,
    required this.isFocused,
    required this.isCurrent,
    required this.onTap,
    this.serverUrl,
  });

  final ChannelMovie movie;
  final bool isFocused;
  final bool isCurrent;
  final VoidCallback onTap;
  final String? serverUrl;

  @override
  State<_MovieSuggestionCard> createState() => _MovieSuggestionCardState();
}

class _MovieSuggestionCardState extends State<_MovieSuggestionCard> {
  int _retryCount = 0;

  @override
  Widget build(BuildContext context) {
    final focused = widget.isFocused && isTvDevice(context);
    final imageUrl = resolveImageUrl(widget.movie.streamIcon, widget.serverUrl);
    final urlToLoad =
        imageUrl.isEmpty
            ? ''
            : (_retryCount > 0
                ? '$imageUrl${imageUrl.contains('?') ? '&' : '?'}retry=1'
                : imageUrl);
    return GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _kSuggestionCardPadH,
          vertical: _kSuggestionCardPadV,
        ),
        child: SizedBox(
          width: _kSuggestionPosterWidth,
          height: _kSuggestionPosterHeight,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border:
                  focused
                      ? Border.all(color: kColorPrimary, width: 2.5)
                      : widget.isCurrent
                      ? Border.all(color: Colors.amber, width: 1.8)
                      : Border.all(color: Colors.white12, width: 1),
              boxShadow:
                  focused
                      ? [
                        BoxShadow(
                          color: kColorPrimary.withValues(alpha: 0.55),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ]
                      : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: _SuggestionPosterImage(
                      imageUrl: urlToLoad,
                      cacheKey: widget.movie.streamId?.toString(),
                      onRetry:
                          _retryCount == 0
                              ? () {
                                if (mounted) {
                                  setState(() => _retryCount = 1);
                                }
                              }
                              : null,
                    ),
                  ),

                // تدرج أسفل الكارت للنص
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 5,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xDD000000), Colors.transparent],
                      ),
                    ),
                    child: Text(
                      sanitizeDisplayTitle(widget.movie.name ?? ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight:
                            focused
                                ? FontWeight.bold
                                : FontWeight.w500,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),

                // مؤشر "يُشغَّل الآن"
                if (widget.isCurrent)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kColorPrimary.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '▶',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // هالة التركيز
                if (focused)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// قائمة القنوات المقترحة (نفس الفئة) – Live TV
// ---------------------------------------------------------------------------
class _LiveChannelSuggestionsOverlay extends StatefulWidget {
  const _LiveChannelSuggestionsOverlay({
    super.key,
    required this.focusNode,
    required this.isVisible,
    required this.channelsProvider,
    required this.currentChannel,
    required this.focusIndex,
    required this.onChannelSelected,
    required this.onDismiss,
  });

  final FocusNode focusNode;
  final bool isVisible;
  final List<ChannelLive> Function() channelsProvider;
  final ChannelLive? currentChannel;
  final int focusIndex;
  final void Function(ChannelLive channel) onChannelSelected;
  final VoidCallback onDismiss;

  @override
  State<_LiveChannelSuggestionsOverlay> createState() =>
      _LiveChannelSuggestionsOverlayState();
}

class _LiveChannelSuggestionsOverlayState
    extends State<_LiveChannelSuggestionsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  final ScrollController _scrollCtrl = ScrollController();
  late final ValueNotifier<int> _selectedIndexVN;
  List<ChannelLive> _channels = const [];
  bool _initialScrollDone = false;

  static const double _kItemWidth = 108.0;
  static const double _kItemGap = 10.0;
  static const double _kOverlayHeight = 190.0;
  static const int _kItemsBeforeFocused = 3;

  double get _itemStride => _kItemWidth + _kItemGap;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _selectedIndexVN = ValueNotifier<int>(0);
  }

  @override
  void didUpdateWidget(_LiveChannelSuggestionsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _initialScrollDone = false;
      _animController.forward(from: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.isVisible) return;
        widget.focusNode.requestFocus();
        _focusCurrentChannel();
      });
    } else if (widget.isVisible) {
      final prev = oldWidget.currentChannel;
      final next = widget.currentChannel;
      final channelChanged =
          (prev == null) != (next == null) ||
          (prev != null &&
              next != null &&
              !liveChannelsMatch(prev, next)) ||
          oldWidget.focusIndex != widget.focusIndex;
      if (channelChanged) {
        _initialScrollDone = false;
        _focusCurrentChannel();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollCtrl.dispose();
    _selectedIndexVN.dispose();
    super.dispose();
  }

  void _refreshChannels() {
    _channels = widget.channelsProvider();
  }

  int _initialFocusIndex() {
    final zapIdx = widget.focusIndex;
    if (zapIdx >= 0 && zapIdx < _channels.length) {
      return zapIdx;
    }
    final current = widget.currentChannel;
    if (current == null || _channels.isEmpty) return 0;
    final idx = _channels.indexWhere((c) => liveChannelsMatch(c, current));
    return idx >= 0 ? idx : 0;
  }

  void _focusCurrentChannel() {
    _refreshChannels();
    if (_channels.isEmpty) return;
    final target = _initialFocusIndex();
    _initialScrollDone = true;
    _selectedIndexVN.value = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToIndex(target);
    });
  }

  void _scrollToIndex(int index) {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final leftIndex =
        index >= _kItemsBeforeFocused ? index - _kItemsBeforeFocused : 0;
    final offset = (leftIndex * _itemStride).clamp(0.0, pos.maxScrollExtent);
    _scrollCtrl.jumpTo(offset);
  }

  void _selectCurrent() {
    if (_channels.isEmpty) return;
    final idx = _selectedIndexVN.value;
    if (idx < 0 || idx >= _channels.length) return;
    widget.onChannelSelected(_channels[idx]);
  }

  @override
  Widget build(BuildContext context) {
    _refreshChannels();
    if (widget.isVisible && _channels.isNotEmpty && !_initialScrollDone) {
      _focusCurrentChannel();
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Focus(
            focusNode: widget.focusNode,
            skipTraversal: !widget.isVisible,
            onKeyEvent: (node, event) {
              if (!widget.isVisible) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (event is KeyRepeatEvent &&
                  key == LogicalKeyboardKey.arrowDown) {
                return KeyEventResult.handled;
              }
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.arrowUp ||
                  key == LogicalKeyboardKey.browserBack) {
                widget.onDismiss();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowDown) {
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowLeft) {
                final idx = _selectedIndexVN.value;
                if (idx > 0) {
                  _selectedIndexVN.value = idx - 1;
                  _scrollToIndex(idx - 1);
                }
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowRight) {
                final idx = _selectedIndexVN.value;
                if (_channels.isNotEmpty && idx < _channels.length - 1) {
                  _selectedIndexVN.value = idx + 1;
                  _scrollToIndex(idx + 1);
                }
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.numpadEnter ||
                  key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.space) {
                _selectCurrent();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Container(
              height: _kOverlayHeight,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xDD000000),
                    Color(0x88000000),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.6, 1.0],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 18,
                          decoration: BoxDecoration(
                            color: kColorPrimary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'live_suggestions_title'.tr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'live_suggestions_close_hint'.tr,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_channels.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        'live_suggestions_empty'.tr,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    )
                  else
                    SizedBox(
                      height: 118,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _selectedIndexVN,
                        builder: (context, selected, _) {
                          return ListView.separated(
                            controller: _scrollCtrl,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            itemCount: _channels.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final ch = _channels[index];
                              final focused = index == selected;
                              return GestureDetector(
                                onTap: () => widget.onChannelSelected(ch),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  width: _kItemWidth,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: focused
                                        ? Colors.white.withValues(alpha: 0.12)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: focused
                                          ? kColorFocus
                                          : Colors.white.withValues(alpha: 0.12),
                                      width: focused ? 2.2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 64,
                                          height: 64,
                                          child: ch.streamIcon != null &&
                                                  ch.streamIcon!.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: ch.streamIcon!,
                                                  cacheManager: iptvImageCacheManager,
                                                  memCacheWidth: iptvMemCachePx(context, 64, 64).$1,
                                                  memCacheHeight: iptvMemCachePx(context, 64, 64).$2,
                                                  fit: BoxFit.contain,
                                                  fadeInDuration: Duration.zero,
                                                  fadeOutDuration: Duration.zero,
                                                  errorWidget:
                                                      (context, url, error) =>
                                                          const Icon(
                                                    LucideIcons.tv,
                                                    color: Colors.white54,
                                                  ),
                                                )
                                              : const Icon(
                                                  LucideIcons.tv,
                                                  color: Colors.white54,
                                                  size: 28,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        ch.name ?? '—',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: focused ? 1 : 0.88,
                                          ),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          height: 1.15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
      ),
    );
  }
}

/// قائمة الأصناف والقنوات الشفافة فوق المشغّل أثناء البث المباشر
