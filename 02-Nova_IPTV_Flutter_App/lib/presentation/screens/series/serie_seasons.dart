part of '../screens.dart';

class SerieSeasons extends StatefulWidget {
  const SerieSeasons({
    super.key,
    required this.serieDetails,
    this.seriesId,
    this.seriesName,
    this.seriesCover,
  });
  final SerieDetails serieDetails;
  final String? seriesId;
  final String? seriesName;
  final String? seriesCover;

  @override
  State<SerieSeasons> createState() => _SerieSeasonsState();
}

class _SerieSeasonsState extends State<SerieSeasons>
    with LandscapeMainAppStateMixin<SerieSeasons> {
  late SerieDetails serieDetails;
  String selectedSeasonKey = '';
  int selectedEpisode = -1;
  bool _focusOnSeasons = true;

  List<String> seasons = [];
  final FocusNode _seasonsFocusNode = FocusNode();
  final FocusNode _episodesFocusNode = FocusNode();
  final ScrollController _seasonScrollController = ScrollController();
  final ScrollController _episodeScrollController = ScrollController();
  final GlobalKey _focusedSeasonKey = GlobalKey();
  final GlobalKey _focusedEpisodeKey = GlobalKey();

  static const double _kSeasonItemHeight = 72.0;
  static const double _kEpisodeItemHeight = 120.0;

  List<Episode?> _episodesForSelectedSeason() {
    if (selectedSeasonKey.isEmpty) return const [];
    return serieDetails.episodes?[selectedSeasonKey] ?? const [];
  }

  @override
  void initState() {
    serieDetails = widget.serieDetails;
    super.initState();

    final episodesMap = serieDetails.episodes;
    if (episodesMap != null && episodesMap.isNotEmpty) {
      seasons = episodesMap.keys.map((k) => k.toString()).toList();
      selectedSeasonKey = seasons.first;
      setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _seasonsFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _seasonsFocusNode.dispose();
    _episodesFocusNode.dispose();
    _seasonScrollController.dispose();
    _episodeScrollController.dispose();
    super.dispose();
  }

  void _scrollToSeason(int index) {
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_seasonScrollController.hasClients) return;
      final ctx = _focusedSeasonKey.currentContext;
      final anim = kTvEnsureVisibleDuration;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: anim,
          curve: Curves.easeOut,
        );
      } else {
        final offset = (index * _kSeasonItemHeight).clamp(
          0.0,
          _seasonScrollController.position.maxScrollExtent,
        );
        if (kTvSnapFocusScroll) {
          _seasonScrollController.jumpTo(offset);
        } else {
          _seasonScrollController.animateTo(
            offset,
            duration: anim,
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _scrollToEpisode(int index) {
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_episodeScrollController.hasClients) return;
      final ctx = _focusedEpisodeKey.currentContext;
      final anim = kTvEnsureVisibleDuration;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.25,
          duration: anim,
          curve: Curves.easeOut,
        );
      } else {
        final offset = (index * _kEpisodeItemHeight).clamp(
          0.0,
          _episodeScrollController.position.maxScrollExtent,
        );
        if (kTvSnapFocusScroll) {
          _episodeScrollController.jumpTo(offset);
        } else {
          _episodeScrollController.animateTo(
            offset,
            duration: anim,
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Future<void> _playEpisode(UserModel userAuth, Episode episode) async {
    final eid = episode.id?.toString() ?? '';
    final link = (eid.startsWith('http://') || eid.startsWith('https://'))
        ? eid
        : "${userAuth.serverInfo!.serverUrl}/series/${userAuth.userInfo!.username}/${userAuth.userInfo!.password}/${episode.id}.${episode.containerExtension}";

    final episodeId = episode.id.toString();
    WatchingModel? saved;
    for (final w in context.read<WatchingCubit>().state.series) {
      if (w.streamId == episodeId) {
        saved = w;
        break;
      }
    }
    final resumeSec =
        (saved != null && saved.sliderValue > 0) ? saved.sliderValue : null;

    if (!mounted) return;

    Get.to(
      () => FullVideoScreen(
        link: link,
        title: episode.title ?? "",
        channelSerie: ChannelSerie(
          num: null,
          name: widget.seriesName ?? episode.title ?? "",
          seriesId: widget.seriesId ?? episode.id.toString(),
          cover: widget.seriesCover ?? serieDetails.info?.cover,
          plot: null,
          rating: serieDetails.info?.rating,
          rating5based: serieDetails.info?.rating5based,
          categoryId: widget.serieDetails.info?.categoryId,
          added: null,
        ),
        serieEpisodes: _episodesForSelectedSeason(),
        serieCurrentEpisodeId: episode.id?.toString(),
        serieUserAuth: userAuth,
        initialPositionSeconds: resumeSec,
      ),
    )!.then((slider) {
      unawaited(AdsService.showInterstitialIfReady());
      if (!mounted) return;
      if (!watchingPopMatchesOpenedStream(slider, episodeId)) return;

      final modell = WatchingModel(
        sliderValue: (slider[0] as num).toDouble(),
        durationStrm: (slider[1] as num).toDouble(),
        stream: link,
        title: episode.title ?? "",
        image: episode.info?.movieImage ??
            widget.serieDetails.info?.cover ??
            "",
        streamId: episodeId,
        seriesId: widget.seriesId,
        seriesName: widget.seriesName ?? serieDetails.info?.name,
        seriesCover: widget.seriesCover ?? serieDetails.info?.cover,
        rating: serieDetails.info?.rating,
        rating5based: serieDetails.info?.rating5based,
      );

      context.read<WatchingCubit>().addSerie(modell);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Ink(
        decoration: kDecorBackground,
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            if (state is AuthSuccess) {
              final userAuth = state.user;
              final serverUrl = userAuth.serverInfo?.serverUrl;
              final episodesForSeason = _episodesForSelectedSeason();
              return Stack(
                children: [
                  CardMovieImagesBackground(
                    listImages: detailBackdropImages(
                      backdropPath: serieDetails.info?.backdropPath,
                      poster: serieDetails.info?.cover,
                      listFallback: widget.seriesCover,
                    ),
                    serverUrl: serverUrl,
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 20.h, left: 10, right: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          height: 100.w,
                          width: 22.w,
                          child: Focus(
                            focusNode: _seasonsFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) {
                                return KeyEventResult.ignored;
                              }
                              if (seasons.isEmpty) {
                                return KeyEventResult.ignored;
                              }

                              final currentIndex = seasons
                                  .indexOf(selectedSeasonKey)
                                  .clamp(0, seasons.length - 1);

                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                final next = (currentIndex + 1)
                                    .clamp(0, seasons.length - 1);
                                setState(() {
                                  selectedSeasonKey = seasons[next];
                                  _focusOnSeasons = true;
                                  selectedEpisode = -1;
                                });
                                _scrollToSeason(next);
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                final prev = (currentIndex - 1)
                                    .clamp(0, seasons.length - 1);
                                setState(() {
                                  selectedSeasonKey = seasons[prev];
                                  _focusOnSeasons = true;
                                  selectedEpisode = -1;
                                });
                                _scrollToSeason(prev);
                                return KeyEventResult.handled;
                              }

                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowRight) {
                                if (episodesForSeason.isNotEmpty &&
                                    selectedEpisode < 0) {
                                  setState(() {
                                    selectedEpisode = 0;
                                    _focusOnSeasons = false;
                                  });
                                  _scrollToEpisode(0);
                                } else {
                                  setState(() {
                                    _focusOnSeasons = false;
                                  });
                                  if (selectedEpisode >= 0) {
                                    _scrollToEpisode(selectedEpisode);
                                  }
                                }
                                _episodesFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }

                              return KeyEventResult.ignored;
                            },
                            child: ListView.builder(
                              controller: _seasonScrollController,
                              itemCount: seasons.length,
                              padding: EdgeInsets.only(
                                top: 2.h,
                                bottom: 8.h,
                              ),
                              physics: const ClampingScrollPhysics(),
                              itemBuilder: (_, i) {
                                final isThisSeason =
                                    seasons[i] == selectedSeasonKey;
                                return Focus(
                                  key: isThisSeason
                                      ? _focusedSeasonKey
                                      : null,
                                  skipTraversal: true,
                                  child: CardSeasonItem(
                                    isSelected:
                                        _focusOnSeasons && isThisSeason,
                                    number: seasons[i],
                                    onTap: () {
                                      setState(() {
                                        selectedSeasonKey = seasons[i];
                                        _focusOnSeasons = true;
                                        selectedEpisode = -1;
                                      });
                                      _scrollToSeason(i);
                                    },
                                    onFocused: (val) {
                                      if (val) {
                                        setState(() {
                                          selectedSeasonKey = seasons[i];
                                          _focusOnSeasons = true;
                                          selectedEpisode = -1;
                                        });
                                        _scrollToSeason(i);
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          child: Focus(
                            focusNode: _episodesFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) {
                                return KeyEventResult.ignored;
                              }
                              final seasonEpisodes =
                                  _episodesForSelectedSeason();
                              if (seasonEpisodes.isEmpty) {
                                return KeyEventResult.ignored;
                              }

                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                final maxIndex = seasonEpisodes.length - 1;
                                final current =
                                    selectedEpisode < 0 ? 0 : selectedEpisode;
                                final next =
                                    (current + 1).clamp(0, maxIndex);
                                setState(() {
                                  selectedEpisode = next;
                                  _focusOnSeasons = false;
                                });
                                _scrollToEpisode(next);
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                final maxIndex = seasonEpisodes.length - 1;
                                final current =
                                    selectedEpisode < 0 ? 0 : selectedEpisode;
                                final prev =
                                    (current - 1).clamp(0, maxIndex);
                                setState(() {
                                  selectedEpisode = prev;
                                  _focusOnSeasons = false;
                                });
                                _scrollToEpisode(prev);
                                return KeyEventResult.handled;
                              }

                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowLeft) {
                                setState(() {
                                  _focusOnSeasons = true;
                                });
                                _seasonsFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }

                              if (event.logicalKey == LogicalKeyboardKey.select ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.numpadEnter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.space ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.enter) {
                                final maxIndex = seasonEpisodes.length - 1;
                                final current =
                                    selectedEpisode < 0 ? 0 : selectedEpisode;
                                final idx = current.clamp(0, maxIndex);
                                final episode = seasonEpisodes[idx];
                                if (episode == null) {
                                  return KeyEventResult.ignored;
                                }

                                setState(() {
                                  selectedEpisode = idx;
                                  _focusOnSeasons = false;
                                });
                                _playEpisode(userAuth, episode);
                                return KeyEventResult.handled;
                              }

                              return KeyEventResult.ignored;
                            },
                            child: ListView.builder(
                              controller: _episodeScrollController,
                              itemCount: episodesForSeason.length,
                              itemBuilder: (_, i) {
                                final model = episodesForSeason[i];

                                final seriesCover =
                                    widget.seriesCover?.trim().isNotEmpty ==
                                                true &&
                                            widget.seriesCover != 'null'
                                        ? widget.seriesCover
                                        : (serieDetails.info?.cover
                                                        ?.trim()
                                                        .isNotEmpty ==
                                                    true &&
                                                serieDetails.info?.cover !=
                                                    'null'
                                            ? serieDetails.info?.cover
                                            : serieDetails
                                                        .info
                                                        ?.backdropPath
                                                        ?.isNotEmpty ==
                                                    true
                                                ? serieDetails
                                                    .info
                                                    ?.backdropPath!
                                                    .first
                                                : null);
                                final isThisEpisode = selectedEpisode == i;
                                return Focus(
                                  skipTraversal: true,
                                  child: CardEpisodeItem(
                                    key: isThisEpisode
                                        ? _focusedEpisodeKey
                                        : null,
                                    isSelected:
                                        !_focusOnSeasons && isThisEpisode,
                                    index: i + 1,
                                    episode: model,
                                    serverUrl: serverUrl,
                                    fallbackImageUrl: seriesCover,
                                    onTap: () async {
                                      if (model == null) return;
                                      setState(() {
                                        selectedEpisode = i;
                                      });
                                      await _playEpisode(userAuth, model);
                                    },
                                    onFocused: (val) {
                                      if (val) {
                                        setState(() {
                                          selectedEpisode = i;
                                          _focusOnSeasons = false;
                                        });
                                        _scrollToEpisode(i);
                                      }
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
                  Focus(
                    skipTraversal: true,
                    child: AppBarSeries(top: 3.h),
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
