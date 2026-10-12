part of '../screens.dart';

class SerieContent extends StatefulWidget {
  const SerieContent(
      {super.key,
      required this.videoId,
      required this.channelSerie,
      this.preloadedDetail});
  final String videoId;
  final ChannelSerie channelSerie;
  final SerieDetails? preloadedDetail;

  @override
  State<SerieContent> createState() => _SerieContentState();
}

class _SerieContentState extends State<SerieContent>
    with LandscapeMainAppStateMixin<SerieContent>, ParentalSectionGateMixin {
  @override
  ParentalSection get parentalGateSection => ParentalSection.series;

  late Future<SerieDetails?> future;

  @override
  void initState() {
    super.initState();
    future = _loadDetail();
  }

  Future<SerieDetails?> _loadDetail() async {
    final preloaded = widget.preloadedDetail;
    if (preloaded != null && preloaded.info != null) {
      return _withSerieListFallback(preloaded);
    }
    final id = validIptvContentId(widget.videoId);
    if (id == null) return _serieFromListOnly();
    final prefetch = context.read<PrefetchCubit>();
    final detail = await prefetch.getSerieDetailCached(id);
    if (!mounted) return null;
    if (detail == null || detail.info == null) {
      return _withSerieListFallback(detail ?? SerieDetails());
    }
    return _withSerieListFallback(detail);
  }

  SerieDetails _serieFromListOnly() {
    final ch = widget.channelSerie;
    return SerieDetails(
      info: InfoSerie(
        name: ch.name ?? 'Series',
        cover: ch.cover,
        plot: ch.plot,
        rating: ch.rating,
        categoryId: ch.categoryId,
      ),
    );
  }

  SerieDetails _withSerieListFallback(SerieDetails detail) {
    final ch = widget.channelSerie;
    final info = detail.info;
    if (info == null) {
      return SerieDetails(
        seasons: detail.seasons,
        episodes: detail.episodes,
        info: InfoSerie(
          name: ch.name ?? 'Series',
          cover: ch.cover,
          plot: ch.plot,
          rating: ch.rating,
          categoryId: ch.categoryId,
        ),
      );
    }

    final cover = pickMeta(info.cover, ch.cover);
    final plot = pickMeta(info.plot, ch.plot);
    final rating = pickMeta(info.rating, ch.rating);
    final backdrops = detailBackdropImages(
      backdropPath: info.backdropPath,
      poster: cover,
      listFallback: ch.cover,
    );

    final needsMerge = isBlankMeta(info.cover) ||
        isBlankMeta(info.plot) ||
        isBlankMeta(info.rating) ||
        isBlankMeta(info.name) ||
        (info.backdropPath == null || info.backdropPath!.isEmpty) &&
            backdrops.isNotEmpty;

    if (!needsMerge) return detail;

    return SerieDetails(
      seasons: detail.seasons,
      episodes: detail.episodes,
      info: InfoSerie(
        name: pickMeta(info.name, ch.name),
        cover: cover,
        plot: plot,
        cast: info.cast,
        director: info.director,
        genre: info.genre,
        releaseDate: info.releaseDate,
        lastModified: info.lastModified,
        rating: rating,
        rating5based: info.rating5based ?? ch.rating5based,
        tmdbId: info.tmdbId,
        backdropPath: backdrops.isNotEmpty ? backdrops : info.backdropPath,
        youtubeTrailer: info.youtubeTrailer,
        episodeRunTime: info.episodeRunTime,
        categoryId: info.categoryId ?? ch.categoryId,
      ),
    );
  }

  void _retryLoad() {
    final id = validIptvContentId(widget.videoId);
    if (id == null) {
      setState(() {
        future = Future.value(_serieFromListOnly());
      });
      return;
    }
    final prefetch = context.read<PrefetchCubit>();
    setState(() {
      future = () async {
        final detail =
            await prefetch.getSerieDetailCached(id, forceRefresh: true);
        if (!mounted) return null;
        if (detail == null || detail.info == null) {
          return _withSerieListFallback(detail ?? SerieDetails());
        }
        return _withSerieListFallback(detail);
      }();
    });
  }

  @override
  Widget build(BuildContext context) {
    return buildWithParentalGate(_buildSerie(context));
  }

  Widget _buildSerie(BuildContext context) {
    return Scaffold(
      body: Ink(
        decoration: kDecorBackground,
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            if (state is AuthSuccess) {
              //  final userAuth = state.user;
              return Stack(
                children: [
                  FutureBuilder<SerieDetails?>(
                    future: future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snapshot.hasError ||
                          snapshot.data == null ||
                          snapshot.data?.info == null) {
                        return buildContentDetailLoadFailed(
                          onRetry: _retryLoad,
                        );
                      }

                      final movie = snapshot.data;
                      final userAuth = (context.read<AuthBloc>().state as AuthSuccess).user;
                      final serverUrl = userAuth.serverInfo?.serverUrl;

                      return Stack(
                        children: [
                          CardMovieImagesBackground(
                            listImages: detailBackdropImages(
                              backdropPath: movie!.info!.backdropPath,
                              poster: movie.info!.cover,
                              listFallback: widget.channelSerie.cover,
                            ),
                            serverUrl: serverUrl,
                          ),
                          Padding(
                            padding: EdgeInsets.only(
                              top: 20.h,
                              left: 10,
                              right: 10,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TmdbResolvedRatingCard(
                                  image: movie.info!.cover ?? "",
                                  iptvRating: movie.info!.rating,
                                  serverUrl: serverUrl,
                                  isSeries: true,
                                  contentKey: 'series:${widget.videoId}',
                                  title: movie.info!.name ?? "",
                                  year: extractReleaseYear(
                                    movie.info!.releaseDate,
                                  ),
                                  tmdbId: movie.info!.tmdbId,
                                  ratingCardBuilder: (rate) => CardMovieImageRate(
                                    image: movie.info!.cover ?? "",
                                    rate: rate,
                                    serverUrl: serverUrl,
                                  ),
                                ),
                                SizedBox(width: 3.w),
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.only(bottom: 15),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        Text(
                                          movie.info!.name ?? "",
                                          style: Get.textTheme.displaySmall,
                                        ),
                                        const SizedBox(height: 15),
                                        Wrap(
                                          // crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            CardInfoMovie(
                                              icon:
                                                  FontAwesomeIcons.clapperboard,
                                              hint: 'director'.tr,
                                              title: movie.info!.director ?? "",
                                            ),
                                            CardInfoMovie(
                                              icon:
                                                  FontAwesomeIcons.calendarDay,
                                              hint: 'release_date'.tr,
                                              title: formatVodReleaseDate(
                                                movie.info!.releaseDate,
                                              ),
                                            ),
                                            CardInfoMovie(
                                              icon: FontAwesomeIcons.users,
                                              hint: 'cast'.tr,
                                              isShowMore: true,
                                              title: movie.info!.cast ?? "",
                                            ),
                                            CardInfoMovie(
                                              icon: FontAwesomeIcons.film,
                                              hint: '${'genre'.tr}:',
                                              isShowMore: true,
                                              title: movie.info!.genre ?? "",
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 15),
                                        CardInfoMovie(
                                          icon: FontAwesomeIcons
                                              .solidClosedCaptioning,
                                          hint: '${'plot'.tr}:',
                                          title: movie.info!.plot ?? "",
                                          isShowMore: true,
                                        ),
                                        const SizedBox(height: 15),
                                        Row(
                                          children: [
                                            if (!isBlankMeta(
                                              movie.info!.youtubeTrailer,
                                            ))
                                              CardButtonWatchMovie(
                                                title: 'watch_trailer'.tr,
                                                onTap: () {
                                                  final imgs =
                                                      detailBackdropImages(
                                                    backdropPath: movie
                                                        .info!.backdropPath,
                                                    poster: movie.info!.cover,
                                                    listFallback: widget
                                                        .channelSerie.cover,
                                                  );
                                                  showDialog(
                                                      context: context,
                                                      builder: (builder) =>
                                                          DialogTrailerYoutube(
                                                              thumb: imgs.isEmpty
                                                                  ? null
                                                                  : resolveImageUrl(
                                                                      imgs.first,
                                                                      serverUrl,
                                                                    ),
                                                              trailer: movie
                                                                      .info!
                                                                      .youtubeTrailer ??
                                                                  ""));
                                                },
                                              ),
                                            if (!isBlankMeta(
                                              movie.info!.youtubeTrailer,
                                            ))
                                              SizedBox(width: 3.w),
                                            CardButtonWatchMovie(
                                              title: 'watch_now'.tr,
                                              isFocused: true,
                                              onTap: () {
                                                Get.to(() => SerieSeasons(
                                                  serieDetails: movie,
                                                  seriesId: widget.videoId,
                                                  seriesName: widget.channelSerie.name,
                                                  seriesCover: widget.channelSerie.cover,
                                                ));
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  BlocBuilder<FavoritesCubit, FavoritesState>(
                    builder: (context, state) {
                      final isLiked = state.series
                          .where((movie) =>
                              movie.seriesId == widget.channelSerie.seriesId)
                          .isNotEmpty;
                      return AppBarSeries(
                        isLiked: isLiked,
                        top: 3.h,
                        onFavorite: () {
                          context
                              .read<FavoritesCubit>()
                              .addSerie(widget.channelSerie, isAdd: !isLiked);
                        },
                      );
                    },
                  ),
                ],
              );
            }

            return const SizedBox();
          },
        ),
      ),
    );
  }
}
