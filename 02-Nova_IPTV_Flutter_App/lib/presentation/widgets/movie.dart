part of 'widgets.dart';

/// بوستر grid — decode عبر [iptvDecodePosterForDisplay] + gate visible.
class _IptvPosterCachedImage extends StatefulWidget {
  const _IptvPosterCachedImage({
    required this.imageUrl,
    required this.memCacheWidth,
    required this.memCacheHeight,
    required this.placeholder,
    required this.errorPlaceholder,
  });

  final String imageUrl;
  final int memCacheWidth;
  final int memCacheHeight;
  final Widget Function() placeholder;
  final Widget Function() errorPlaceholder;

  @override
  State<_IptvPosterCachedImage> createState() => _IptvPosterCachedImageState();
}

class _IptvPosterCachedImageState extends State<_IptvPosterCachedImage> {
  ImageProvider? _imageProvider;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadPoster();
  }

  @override
  void didUpdateWidget(covariant _IptvPosterCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.memCacheWidth != widget.memCacheWidth ||
        oldWidget.memCacheHeight != widget.memCacheHeight) {
      _imageProvider = null;
      _failed = false;
      _loadPoster();
    }
  }

  ImageProvider _resolvedProvider() => iptvPosterImageProvider(
    widget.imageUrl,
    memCacheWidth: widget.memCacheWidth,
    memCacheHeight: widget.memCacheHeight,
  );

  Future<void> _loadPoster() async {
    if (isIptvImageMemoryWarm(widget.imageUrl)) {
      if (!mounted) return;
      setState(() => _imageProvider = _resolvedProvider());
      return;
    }
    try {
      await iptvDecodePosterForDisplay(
        context,
        widget.imageUrl,
        memCacheWidth: widget.memCacheWidth,
        memCacheHeight: widget.memCacheHeight,
      );
      if (!mounted) return;
      setState(() => _imageProvider = _resolvedProvider());
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.errorPlaceholder();
    final provider = _imageProvider;
    if (provider == null) return widget.placeholder();
    return Image(
      image: provider,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      filterQuality: AppPerf.instance.useLowFilterQuality
          ? FilterQuality.low
          : FilterQuality.medium,
      gaplessPlayback: true,
    );
  }
}

class CardChannelMovieItem extends StatelessWidget {
  const CardChannelMovieItem({
    super.key,
    required this.onTap,
    this.title,
    this.image,
    this.serverUrl,
    this.assetImage,
    this.rating,
    this.rating5based,
    this.contentKey,
    this.tmdbId,
    this.isSeries = false,
    this.boldTitle = false,
    this.focusNode,
  });
  final Function() onTap;
  final String? title;
  final String? image;

  /// عنوان السيرفر لتحويل الروابط النسبية لصور الأفلام/المسلسلات إلى روابط كاملة
  final String? serverUrl;
  final String? assetImage;
  final String? rating;
  final String? rating5based;
  final String? contentKey;
  final String? tmdbId;
  final bool isSeries;

  /// عنوان أوضح وأعرض (مثل المفضلة / Catch Up).
  final bool boldTitle;
  final FocusNode? focusNode;

  static Widget _buildPlaceholder() => noPosterImage();

  String? _watchLookupId() {
    final key = contentKey;
    if (key == null || key.isEmpty) return null;
    final idx = key.indexOf(':');
    if (idx < 0 || idx >= key.length - 1) return key;
    return key.substring(idx + 1);
  }

  double? _resolveWatchProgress(BuildContext context) {
    final id = _watchLookupId()?.trim();
    if (id == null || id.isEmpty) return null;
    final watch = context.watch<WatchingCubit>().state;
    WatchingModel? match;
    if (isSeries) {
      for (final w in watch.series) {
        if ((w.seriesId ?? '').trim() == id) {
          match = w;
          break;
        }
      }
    } else {
      for (final w in watch.movies) {
        if (w.streamId.trim() == id) {
          match = w;
          break;
        }
      }
    }
    if (match == null) return null;
    return watchProgressRatio(match.sliderValue, match.durationStrm);
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = resolveImageUrl(image, serverUrl);
    final progress = _resolveWatchProgress(context);
    return InkWell(
      onTap: onTap,
      focusNode: focusNode,
      focusColor: kColorFocus,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        decoration: BoxDecoration(
          color: kColorCardLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        assetImage != null
                            ? Image.asset(
                              assetImage!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                            )
                            : imageUrl.isEmpty
                            ? _buildPlaceholder()
                            : LayoutBuilder(
                              builder: (context, constraints) {
                                final lw =
                                    constraints.maxWidth.isFinite &&
                                            constraints.maxWidth > 0
                                        ? constraints.maxWidth
                                        : 160.0;
                                final lh =
                                    constraints.maxHeight.isFinite &&
                                            constraints.maxHeight > 0
                                        ? constraints.maxHeight
                                        : lw * 1.5;
                                final mem = iptvMemCachePx(context, lw, lh);
                                return _IptvPosterCachedImage(
                                  imageUrl: imageUrl,
                                  memCacheWidth: mem.$1,
                                  memCacheHeight: mem.$2,
                                  placeholder: posterCardImageLoadingPlaceholder,
                                  errorPlaceholder: _buildPlaceholder,
                                );
                              },
                            ),
                        TmdbPosterRatingBadge(
                          rating: rating,
                          rating5based: rating5based,
                          contentKey: contentKey,
                          title: title,
                          year: extractReleaseYear(title),
                          tmdbId: tmdbId,
                          isSeries: isSeries,
                        ),
                        if (!isSeries)
                          MovieDownloadProgressOverlay(contentKey: contentKey),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    10,
                    10,
                    progress != null ? 14 : 10,
                  ),
                  child: Text(
                    title ?? 'null',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (Get.textTheme.titleLarge ?? const TextStyle()).copyWith(
                      fontWeight: boldTitle ? FontWeight.bold : null,
                      fontSize: boldTitle
                          ? ((Get.textTheme.titleLarge?.fontSize ?? 14) + 2)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            // أسفل الكرت تماماً — نفس أسلوب الصفحة الرئيسية
            if (progress != null && progress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                  child: WatchProgressBar(progress: progress),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        autofocus: widget.isFocused,
        borderRadius: BorderRadius.circular(10),
        onFocusChange: (bool value) {
          if (widget.onFocusChanged != null) {
            widget.onFocusChanged!(widget.index);
          }

          setState(() {
            isFocused = value;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: widget.hideBorder ? null : BorderRadius.circular(10),
            gradient:
                isFocused || widget.isSelected
                    ? LinearGradient(
                      colors: [kColorPrimary, kColorPrimaryDark],
                    )
                    : LinearGradient(
                      colors: [
                        kColorPrimary.withValues(alpha: .4),
                        kColorPrimaryDark.withValues(alpha: .4),
                      ],
                    ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: Center(
            child: Text(
              widget.title.toUpperCase(),
              style:
                  isFocused
                      ? Get.textTheme.headlineMedium
                      : Get.textTheme.headlineSmall,
            ),
          ),
        ),
      ),
    );
  }
}

class CardInfoMovie extends StatelessWidget {
  const CardInfoMovie({
    super.key,
    required this.hint,
    required this.title,
    required this.icon,
    this.isShowMore = false,
  });
  final String hint;
  final String title;
  final IconData icon;
  final bool isShowMore;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18.w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15.sp),
              const SizedBox(width: 5),
              Text(hint, style: Get.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 3),
          !isShowMore
              ? Text(
                title,
                style: Get.textTheme.titleSmall!.copyWith(
                  fontWeight: FontWeight.w100,
                  color: Colors.white,
                ),
              )
              : ReadMoreText(
                title,
                trimLines: 2,
                colorClickableText: kColorFocus,
                trimMode: TrimMode.Line,
                trimCollapsedText: 'more'.tr,
                trimExpandedText: 'less'.tr,
                style: TextStyle(
                  fontWeight: FontWeight.w100,
                  color: Colors.white,
                ),
                moreStyle: Get.textTheme.headlineSmall!.copyWith(
                  color: kColorFocus,
                ),
                lessStyle: Get.textTheme.headlineSmall!.copyWith(
                  color: kColorFocus,
                ),
              ),
        ],
      ),
    );
  }
}

class CardMovieImageRate extends StatelessWidget {
  const CardMovieImageRate({
    super.key,
    required this.image,
    required this.rate,
    this.serverUrl,
  });
  final String image;
  final String rate;
  final String? serverUrl;

  @override
  Widget build(BuildContext context) {
    final imageUrl = resolveImageUrl(image, serverUrl);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child:
              imageUrl.isEmpty
                  ? CardChannelMovieItem._buildPlaceholder()
                  : Builder(
                    builder: (context) {
                      final mem = iptvMemCachePx(context, 18.w, 55.h);
                      return CachedNetworkImage(
                        imageUrl: imageUrl,
                        cacheManager: iptvImageCacheManager,
                        memCacheWidth: mem.$1,
                        memCacheHeight: mem.$2,
                        width: 18.w,
                        height: 55.h,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder:
                            (_, _) =>
                                posterCardImageLoadingPlaceholder(size: 20),
                        errorWidget:
                            (_, i, e) =>
                                CardChannelMovieItem._buildPlaceholder(),
                      );
                    },
                  ),
        ),
        const SizedBox(height: 10),
        RatingBarIndicator(
          rating: double.tryParse(rate.toString()) ?? 0,
          itemBuilder:
              (context, index) =>
                  const Icon(FontAwesomeIcons.solidStar, color: Colors.amber),
          itemCount: 5,
          itemSize: 18.sp,
          direction: Axis.horizontal,
        ),
      ],
    );
  }
}

class CardMovieImagesBackground extends StatefulWidget {
  const CardMovieImagesBackground({
    super.key,
    required this.listImages,
    this.serverUrl,
  });
  final List<String> listImages;
  final String? serverUrl;

  @override
  State<CardMovieImagesBackground> createState() =>
      _CardMovieImagesBackgroundState();
}

class _CardMovieImagesBackgroundState extends State<CardMovieImagesBackground> {
  late bool isNotEmpty;
  late int sizeList;
  int indexImage = 0;

  Future<void> _runAnimation() async {
    await Future.delayed(const Duration(seconds: 5));

    if (mounted) {
      setState(() {
        if ((indexImage + 1) >= sizeList) {
          indexImage = 0;
        } else {
          indexImage = indexImage + 1;
        }
      });
      _runAnimation();
    }
  }

  @override
  void initState() {
    final cleaned = widget.listImages
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
        .toList();
    isNotEmpty = cleaned.isNotEmpty;
    // Keep widget.listImages indices aligned by filtering in build via cleaned copy.
    _images = cleaned;

    if (isNotEmpty) {
      sizeList = _images.length;
      _runAnimation();
    }

    super.initState();
  }

  List<String> _images = const [];

  @override
  void didUpdateWidget(covariant CardMovieImagesBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listImages != widget.listImages) {
      final cleaned = widget.listImages
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
          .toList();
      setState(() {
        _images = cleaned;
        isNotEmpty = cleaned.isNotEmpty;
        sizeList = cleaned.length;
        if (indexImage >= sizeList) indexImage = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isNotEmpty || _images.isEmpty) {
      return const SizedBox();
    }

    final resolvedUrl = resolveImageUrl(
      _images[indexImage.clamp(0, _images.length - 1)],
      widget.serverUrl,
    );
    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(seconds: 3),
          switchInCurve: Curves.easeIn,
          child:
              resolvedUrl.isEmpty
                  ? CardChannelMovieItem._buildPlaceholder()
                  : Builder(
                    builder: (context) {
                      final mem = iptvMemCachePx(context, 100.w, 100.h);
                      return CachedNetworkImage(
                        width: 100.w,
                        height: 100.h,
                        fit: BoxFit.cover,
                        imageUrl: resolvedUrl,
                        cacheManager: iptvImageCacheManager,
                        memCacheWidth: mem.$1,
                        memCacheHeight: mem.$2,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder:
                            (_, _) => posterCardImageLoadingPlaceholder(
                              backgroundColor: kColorBackDark,
                            ),
                        errorWidget:
                            (_, _, _) =>
                                CardChannelMovieItem._buildPlaceholder(),
                      );
                    },
                  ),
        ),
        Container(
          width: 100.w,
          height: 100.h,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              end: Alignment.topCenter,
              begin: Alignment.bottomCenter,
              colors: [
                kColorBackDark.withValues(alpha: 1),
                kColorBack.withValues(alpha: .5),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

///Serie
class CardEpisodeItem extends StatefulWidget {
  const CardEpisodeItem({
    super.key,
    required this.episode,
    required this.isSelected,
    required this.onFocused,
    required this.onTap,
    required this.index,
    this.serverUrl,

    /// عند عدم توفر صورة الحلقة تُعرض صورة المسلسل بدلاً منها
    this.fallbackImageUrl,
  });
  final Episode? episode;
  final bool isSelected;
  final int index;
  final Function(bool) onFocused;
  final Function() onTap;
  final String? serverUrl;
  final String? fallbackImageUrl;

  @override
  State<CardEpisodeItem> createState() => _CardEpisodeItemState();
}

class _CardEpisodeItemState extends State<CardEpisodeItem> {
  bool _useFallbackImage = false;

  @override
  Widget build(BuildContext context) {
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

    final bool highlighted = widget.isSelected;
    final info = widget.episode?.info;
    final episodeTitle = (info?.name?.trim().isNotEmpty == true)
        ? info!.name!
        : (widget.episode?.title?.trim().isNotEmpty == true
            ? widget.episode!.title!
            : "${'episode'.tr} ${widget.index}");
    final episodePlot = info?.plot ?? '';
    final episodeDuration = getDurationMovie(info?.duration);

    WatchingModel? episodeWatch;
    final episodeId = widget.episode?.id?.toString();
    if (episodeId != null && episodeId.isNotEmpty) {
      final seriesWatch = context.watch<WatchingCubit>().state.series;
      for (final w in seriesWatch) {
        if (w.streamId == episodeId) {
          episodeWatch = w;
          break;
        }
      }
    }
    final episodeProgress = episodeWatch == null
        ? null
        : watchProgressRatio(
            episodeWatch.sliderValue,
            episodeWatch.durationStrm,
          );

    return AnimatedContainer(
      duration: kFocusAnimDuration,
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: highlighted ? const EdgeInsets.all(3) : EdgeInsets.zero,
      decoration:
          highlighted
              ? BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kColorFocus, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: kColorFocus.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              )
              : null,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: widget.onFocused,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: SizedBox(
                width: widget.isSelected ? 26.w : 25.w,
                height: widget.isSelected ? 35.h : 34.h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imageUrl.isEmpty
                        ? CardChannelMovieItem._buildPlaceholder()
                        : Builder(
                          builder: (context) {
                            final w =
                                widget.isSelected ? 26.w : 25.w;
                            final h =
                                widget.isSelected ? 35.h : 34.h;
                            final mem = iptvMemCachePx(context, w, h);
                            return CachedNetworkImage(
                              width: double.infinity,
                              height: double.infinity,
                              imageUrl: imageUrl,
                              cacheManager: iptvImageCacheManager,
                              memCacheWidth: mem.$1,
                              memCacheHeight: mem.$2,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder:
                                  (_, _) =>
                                      posterCardImageLoadingPlaceholder(),
                              errorWidget: (_, i, e) {
                                if (fallbackUrl.isNotEmpty &&
                                    !_useFallbackImage &&
                                    mounted) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (mounted) {
                                      setState(
                                        () => _useFallbackImage = true,
                                      );
                                    }
                                  });
                                }
                                return Opacity(
                                  opacity: .7,
                                  child: noPosterImage(),
                                );
                              },
                            );
                          },
                        ),
                    if (episodeProgress != null && episodeProgress > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: WatchProgressBar(
                          progress: episodeProgress,
                          height: 3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episodeTitle,
                    maxLines: 1,
                    style: Get.textTheme.headlineMedium!.copyWith(
                      fontSize: widget.isSelected ? 18.sp : 17.sp,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    episodePlot,
                    maxLines: 3,
                    style: Get.textTheme.titleMedium!.copyWith(
                      color: Colors.grey.shade400,
                      fontSize: 15.sp,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        FontAwesomeIcons.clock,
                        color: Colors.grey.shade400,
                        size: 16.sp,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        episodeDuration,
                        maxLines: 3,
                        style: Get.textTheme.titleMedium!.copyWith(
                          color: Colors.grey.shade400,
                          fontSize: 15.sp,
                        ),
                      ),
                      const Spacer(flex: 2),
                      Icon(
                        FontAwesomeIcons.circlePlay,
                        color:
                            widget.isSelected
                                ? Colors.white
                                : Colors.grey.shade400,
                        size: widget.isSelected ? 17.sp : 16.sp,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'play'.tr,
                        maxLines: 3,
                        style: Get.textTheme.titleMedium!.copyWith(
                          color:
                              widget.isSelected
                                  ? Colors.white
                                  : Colors.grey.shade400,
                          fontSize: widget.isSelected ? 16.sp : 15.sp,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CardSeasonItem extends StatelessWidget {
  const CardSeasonItem({
    super.key,
    required this.number,
    required this.isSelected,
    required this.onFocused,
    required this.onTap,
  });
  final String number;
  final bool isSelected;
  final Function(bool) onFocused;
  final Function() onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: kFocusAnimDuration,
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding:
          isSelected
              ? const EdgeInsets.symmetric(vertical: 4)
              : EdgeInsets.zero,
      decoration:
          isSelected
              ? BoxDecoration(
                color: kColorFocus.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kColorFocus, width: 1.6),
                boxShadow: kTvFocusGlow(
                  focused: true,
                  blur: 14,
                  alpha: 0.35,
                ),
              )
              : null,
      child: InkWell(
        onTap: onTap,
        onFocusChange: onFocused,
        child: Row(
          children: [
            Container(
              width: 3,
              height: 8.5.h,
              decoration: BoxDecoration(
                color: isSelected ? kColorFocus : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            SizedBox(width: isSelected ? 16 : 10),
            Text(
              '$number ${'seasons'.tr}',
              style:
                  isSelected
                      ? Get.textTheme.headlineMedium
                      : Get.textTheme.titleMedium!.copyWith(
                        color: Colors.grey.shade500,
                        fontSize: 17.sp,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
