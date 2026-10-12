part of '../screens.dart';

class MovieContent extends StatefulWidget {
  const MovieContent(
      {super.key,
      required this.videoId,
      required this.channelMovie,
      this.preloadedDetail});
  final String videoId;
  final ChannelMovie channelMovie;
  final MovieDetail? preloadedDetail;

  @override
  State<MovieContent> createState() => _MovieContentState();
}

class _MovieContentState extends State<MovieContent>
    with LandscapeMainAppStateMixin<MovieContent>, ParentalSectionGateMixin {
  @override
  ParentalSection get parentalGateSection => ParentalSection.movies;

  late Future<MovieDetail?> future;

  @override
  void initState() {
    super.initState();
    future = _loadDetail();
  }

  Future<MovieDetail?> _loadDetail() async {
    final preloaded = widget.preloadedDetail;
    if (preloaded != null && preloaded.movieData != null) {
      return _withMovieListFallback(preloaded);
    }
    final id = validIptvContentId(widget.videoId);
    if (id == null) return _movieFromListOnly();
    final prefetch = context.read<PrefetchCubit>();
    final detail = await prefetch.getMovieDetailCached(id);
    if (!mounted) return null;
    if (detail == null || detail.movieData == null) {
      return _movieFromListOnly();
    }
    return _withMovieListFallback(detail);
  }

  MovieDetail _movieFromListOnly() {
    final ch = widget.channelMovie;
    return MovieDetail(
      info: Info(
        movieImage: ch.streamIcon,
        rating: ch.rating,
        plot: '',
      ),
      movieData: MovieData(
        streamId: ch.streamId ?? widget.videoId,
        name: ch.name ?? 'Movie',
        categoryId: ch.categoryId,
        containerExtension: ch.containerExtension ?? 'mp4',
        directSource: ch.directSource,
      ),
    );
  }

  MovieDetail _withMovieListFallback(MovieDetail detail) {
    final ch = widget.channelMovie;
    final info = detail.info;
    if (info == null) {
      return MovieDetail(
        info: Info(
          movieImage: ch.streamIcon,
          rating: ch.rating,
          plot: '',
        ),
        movieData: detail.movieData,
      );
    }

    final image = pickMeta(info.movieImage, ch.streamIcon);
    final rating = pickMeta(info.rating, ch.rating);
    final backdrops = detailBackdropImages(
      backdropPath: info.backdropPath,
      backdrop: info.backdrop,
      poster: image,
      listFallback: ch.streamIcon,
    );

    final needsMerge = isBlankMeta(info.movieImage) ||
        isBlankMeta(info.rating) ||
        (info.backdropPath == null || info.backdropPath!.isEmpty) &&
            backdrops.isNotEmpty;

    if (!needsMerge) return detail;

    return MovieDetail(
      info: Info(
        movieImage: image,
        tmdbId: info.tmdbId,
        backdrop: pickMeta(info.backdrop, backdrops.isNotEmpty ? backdrops.first : null),
        youtubeTrailer: info.youtubeTrailer,
        genre: info.genre,
        plot: info.plot,
        cast: info.cast,
        rating: rating,
        director: info.director,
        releasedate: info.releasedate,
        backdropPath: backdrops.isNotEmpty ? backdrops : info.backdropPath,
        durationSecs: info.durationSecs,
        duration: info.duration,
        video: info.video,
        bitrate: info.bitrate,
      ),
      movieData: detail.movieData,
    );
  }

  String _moviePlayLink(UserModel userAuth, MovieDetail movie) {
    final sid = movie.movieData?.streamId?.toString() ??
        widget.channelMovie.streamId?.toString() ??
        '';
    if (sid.startsWith('http://') || sid.startsWith('https://')) return sid;
    final chSid = widget.channelMovie.streamId?.toString() ?? '';
    if (chSid.startsWith('http://') || chSid.startsWith('https://')) {
      return chSid;
    }
    final ext = movie.movieData?.containerExtension ??
        widget.channelMovie.containerExtension ??
        'mp4';
    return "${userAuth.serverInfo!.serverUrl}/movie/${userAuth.userInfo!.username}/${userAuth.userInfo!.password}/$sid.$ext";
  }

  void _retryLoad() {
    final id = validIptvContentId(widget.videoId);
    if (id == null) {
      setState(() {
        future = Future.value(_movieFromListOnly());
      });
      return;
    }
    final prefetch = context.read<PrefetchCubit>();
    setState(() {
      future = () async {
        final detail =
            await prefetch.getMovieDetailCached(id, forceRefresh: true);
        if (!mounted) return null;
        if (detail == null || detail.movieData == null) {
          return _movieFromListOnly();
        }
        return _withMovieListFallback(detail);
      }();
    });
  }

  @override
  Widget build(BuildContext context) {
    return buildWithParentalGate(_buildMovie(context));
  }

  Widget _buildMovie(BuildContext context) {
    return Scaffold(
      body: Ink(
        decoration: kDecorBackground,
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            if (state is AuthSuccess) {
              final userAuth = state.user;
              return Stack(
                children: [
                  FutureBuilder<MovieDetail?>(
                    future: future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snapshot.hasError ||
                          snapshot.data == null ||
                          snapshot.data?.movieData == null ||
                          snapshot.data?.info == null) {
                        return buildContentDetailLoadFailed(
                          onRetry: _retryLoad,
                        );
                      }

                      final movie = snapshot.data!;
                      final info = movie.info!;

                      final serverUrl = userAuth.serverInfo?.serverUrl;
                      return Stack(
                        children: [
                          CardMovieImagesBackground(
                            listImages: detailBackdropImages(
                              backdropPath: info.backdropPath,
                              backdrop: info.backdrop,
                              poster: info.movieImage,
                              listFallback: widget.channelMovie.streamIcon,
                            ),
                            serverUrl: serverUrl,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 70, left: 10, right: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TmdbResolvedRatingCard(
                                  image: info.movieImage ?? "",
                                  iptvRating: info.rating,
                                  serverUrl: serverUrl,
                                  tmdbId: info.tmdbId,
                                  contentKey:
                                      'movie:${widget.channelMovie.streamId}',
                                  title: movie.movieData!.name ?? "",
                                  year: extractReleaseYear(
                                    info.releasedate,
                                  ),
                                  ratingCardBuilder: (rate) => CardMovieImageRate(
                                    image: info.movieImage ?? "",
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
                                          movie.movieData!.name ?? "",
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
                                              title: info.director ?? "",
                                            ),
                                            CardInfoMovie(
                                              icon:
                                                  FontAwesomeIcons.calendarDay,
                                              hint: 'release_date'.tr,
                                              title: formatVodReleaseDate(
                                                info.releasedate,
                                              ),
                                            ),
                                            CardInfoMovie(
                                              icon: FontAwesomeIcons.clock,
                                              hint: 'duration'.tr,
                                              title: info.duration ?? "",
                                            ),
                                            CardInfoMovie(
                                              icon: FontAwesomeIcons.users,
                                              hint: 'cast'.tr,
                                              isShowMore: true,
                                              title: info.cast ?? "",
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 15),
                                        CardInfoMovie(
                                          icon: FontAwesomeIcons.film,
                                          hint: '${'genre'.tr}:',
                                          title: info.genre ?? "",
                                        ),
                                        const SizedBox(height: 15),
                                        CardInfoMovie(
                                          icon: FontAwesomeIcons
                                              .solidClosedCaptioning,
                                          hint: '${'plot'.tr}:',
                                          title: info.plot ?? "",
                                          isShowMore: true,
                                        ),
                                        const SizedBox(height: 15),
                                        Row(
                                          children: [
                                            if (!isBlankMeta(info.youtubeTrailer))
                                              CardButtonWatchMovie(
                                                title: 'watch_trailer'.tr,
                                                onTap: () {
                                                  final imgs = detailBackdropImages(
                                                    backdropPath: info.backdropPath,
                                                    backdrop: info.backdrop,
                                                    poster: info.movieImage,
                                                    listFallback: widget.channelMovie.streamIcon,
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
                                                              trailer: info.youtubeTrailer ?? ""),
                                                    );
                                                },
                                              ),
                                            SizedBox(width: 3.w),
                                            CardButtonWatchMovie(
                                              title: 'watch_now'.tr,
                                              isFocused: true,
                                              onTap: () async {
                                                final link = _moviePlayLink(
                                                  userAuth,
                                                  movie,
                                                );

                                                final streamId = widget
                                                    .channelMovie.streamId
                                                    .toString();
                                                WatchingModel? saved;
                                                for (final w in context
                                                    .read<WatchingCubit>()
                                                    .state
                                                    .movies) {
                                                  if (w.streamId == streamId) {
                                                    saved = w;
                                                    break;
                                                  }
                                                }
                                                final resumeSec =
                                                    (saved != null &&
                                                            saved.sliderValue >
                                                                0)
                                                        ? saved.sliderValue
                                                        : null;

                                                if (!context.mounted) return;

                                                Get.to(
                                                  () => FullVideoScreen(
                                                    link: link,
                                                    title: movie.movieData!
                                                            .name ??
                                                        "",
                                                    channelMovie:
                                                        widget.channelMovie,
                                                    initialPositionSeconds:
                                                        resumeSec,
                                                  ),
                                                )!
                                                    .then((slider) {
                                                  unawaited(
                                                    AdsService
                                                        .showInterstitialIfReady(),
                                                  );
                                                  if (!context.mounted) return;
                                                  if (!watchingPopMatchesOpenedStream(
                                                    slider,
                                                    streamId,
                                                  )) {
                                                    return;
                                                  }
                                                  var model = WatchingModel(
                                                      sliderValue:
                                                          (slider[0] as num)
                                                              .toDouble(),
                                                      durationStrm:
                                                          (slider[1] as num)
                                                              .toDouble(),
                                                      stream: link,
                                                      title: widget
                                                              .channelMovie
                                                              .name ??
                                                          "",
                                                      image: widget
                                                              .channelMovie
                                                              .streamIcon ??
                                                          "",
                                                      streamId: streamId,
                                                      rating: widget
                                                          .channelMovie
                                                          .rating,
                                                      rating5based: widget
                                                          .channelMovie
                                                          .rating5based,
                                                      categoryId: widget
                                                          .channelMovie
                                                          .categoryId,
                                                    );
                                                    context
                                                        .read<WatchingCubit>()
                                                        .addMovie(model);
                                                });
                                              },
                                            ),
                                            SizedBox(width: 3.w),
                                              BlocBuilder<DownloadsCubit,
                                                  DownloadsState>(
                                                builder: (context, dlState) {
                                                  final streamId = widget
                                                      .channelMovie.streamId
                                                      .toString();
                                                  final downloading =
                                                      dlState.isDownloading(
                                                    streamId,
                                                  );
                                                  final downloaded =
                                                      dlState.isDownloaded(
                                                    streamId,
                                                  );
                                                  final progress =
                                                      dlState.progressOf(
                                                    streamId,
                                                  );
                                                  String title;
                                                  if (downloaded) {
                                                    title = 'downloaded'.tr;
                                                  } else if (downloading) {
                                                    title =
                                                        '${'downloading'.tr} ${(progress * 100).toStringAsFixed(0)}%';
                                                  } else {
                                                    title = 'download'.tr;
                                                  }
                                                  return CardButtonWatchMovie(
                                                    title: title,
                                                    onTap: () async {
                                                      if (downloaded) {
                                                        Get.toNamed(
                                                          screenDownloads,
                                                        );
                                                        return;
                                                      }
                                                      if (downloading) {
                                                        final stop =
                                                            await AppActionConfirmDialog.show(
                                                          context,
                                                          icon: Icons
                                                              .stop_circle_outlined,
                                                          accent: const Color(
                                                            0xFFFF9800,
                                                          ),
                                                          title:
                                                              'cancel_download_title'
                                                                  .tr,
                                                          message:
                                                              'cancel_download_message'
                                                                  .tr,
                                                          highlight: movie
                                                                  .movieData!
                                                                  .name ??
                                                              widget
                                                                  .channelMovie
                                                                  .name,
                                                          confirmLabel:
                                                              'yes'.tr,
                                                          cancelLabel: 'no'.tr,
                                                          confirmIcon:
                                                              LucideIcons.check,
                                                          cancelIcon:
                                                              LucideIcons.x,
                                                        );
                                                        if (stop == true &&
                                                            context.mounted) {
                                                          await context
                                                              .read<
                                                                  DownloadsCubit>()
                                                              .cancelDownload(
                                                                streamId,
                                                              );
                                                          if (context.mounted) {
                                                            showInfoToast(
                                                              context,
                                                              'downloads'.tr,
                                                              'download_cancelled'
                                                                  .tr,
                                                            );
                                                          }
                                                        }
                                                        return;
                                                      }
                                                      final link =
                                                          _moviePlayLink(
                                                        userAuth,
                                                        movie,
                                                      );
                                                      final err = await context
                                                          .read<
                                                              DownloadsCubit>()
                                                          .enqueueMovieDownload(
                                                            streamId: streamId,
                                                            name: movie
                                                                    .movieData!
                                                                    .name ??
                                                                widget
                                                                    .channelMovie
                                                                    .name ??
                                                                '',
                                                            streamIcon: resolveImageUrl(
                                                              widget
                                                                  .channelMovie
                                                                  .streamIcon,
                                                              userAuth
                                                                  .serverInfo
                                                                  ?.serverUrl,
                                                            ),
                                                            videoUrl: link,
                                                            containerExtension:
                                                                movie.movieData!
                                                                        .containerExtension ??
                                                                    'mp4',
                                                          );
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      if (err ==
                                                          'already_download') {
                                                        showInfoToast(
                                                          context,
                                                          'downloads'.tr,
                                                          'already_download'
                                                              .tr,
                                                        );
                                                      } else if (err != null) {
                                                        showInfoToast(
                                                          context,
                                                          'downloads'.tr,
                                                          err.tr,
                                                        );
                                                      } else {
                                                        showInfoToast(
                                                          context,
                                                          'downloads'.tr,
                                                          'downloaded'.tr,
                                                        );
                                                      }
                                                    },
                                                  );
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
                      final isLiked = state.movies
                          .where((movie) =>
                              movie.streamId == widget.channelMovie.streamId)
                          .isNotEmpty;
                      return AppBarMovie(
                        isLiked: isLiked,
                        top: 15,
                        onFavorite: () {
                          context
                              .read<FavoritesCubit>()
                              .addMovie(widget.channelMovie, isAdd: !isLiked);
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
