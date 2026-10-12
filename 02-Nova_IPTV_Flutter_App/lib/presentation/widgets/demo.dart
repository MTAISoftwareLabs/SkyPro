part of 'widgets.dart';

void openDemoVideoPlayer() {
  Get.to(
    () => FullVideoScreen(
      title: demoTestTitle(),
      link: kDemoStreamUrl,
    ),
  );
}

class DemoCategoryGrid extends StatelessWidget {
  const DemoCategoryGrid({
    super.key,
    required this.crossAxisCount,
    this.childAspectRatio = 0.72,
    this.scrollController,
    this.padding,
    this.liveStyle = false,
  });

  final int crossAxisCount;
  final double childAspectRatio;
  final ScrollController? scrollController;
  final EdgeInsetsGeometry? padding;
  final bool liveStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ?? const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: GridView.builder(
        controller: scrollController,
        cacheExtent: kCatalogCacheExtent,
        itemCount: kDemoCategoryItemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: childAspectRatio,
        ),
        itemBuilder: (_, i) {
          if (liveStyle) {
            return RepaintBoundary(
              child: CardLiveItem(
                title: demoTestTitle(),
                assetImage: kDemoPosterAsset,
                onTap: openDemoVideoPlayer,
              ),
            );
          }
          return RepaintBoundary(
            child: CardChannelMovieItem(
              title: demoTestTitle(),
              assetImage: kDemoPosterAsset,
              onTap: openDemoVideoPlayer,
            ),
          );
        },
      ),
    );
  }
}

/// قسم القنوات في وضع الديمو: معاينة بث مباشر متكرر + عنصران للاختيار.
class DemoLiveChannelsPanel extends StatefulWidget {
  const DemoLiveChannelsPanel({super.key});

  @override
  State<DemoLiveChannelsPanel> createState() => _DemoLiveChannelsPanelState();
}

class _DemoLiveChannelsPanelState extends State<DemoLiveChannelsPanel> {
  BetterPlayerController? _previewController;

  @override
  void initState() {
    super.initState();
    _previewController = BetterPlayerController(
      const BetterPlayerConfiguration(
        autoPlay: true,
        looping: true,
        fit: BoxFit.cover,
        aspectRatio: 16 / 9,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false,
          enableFullscreen: false,
          enableMute: false,
          enablePlayPause: false,
          enableProgressBar: false,
          enableProgressText: false,
          enableSkips: false,
          enableOverflowMenu: false,
        ),
      ),
    );
    _previewController!.setupDataSource(
      BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        kDemoStreamUrl,
        liveStream: true,
        videoFormat: BetterPlayerVideoFormat.hls,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
          'Accept': '*/*',
        },
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 1500,
          maxBufferMs: 8000,
          bufferForPlaybackMs: 800,
          bufferForPlaybackAfterRebufferMs: 1500,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _previewController?.dispose(forceDispose: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _previewController;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (controller != null)
                    BetterPlayer(controller: controller)
                  else
                    const ColoredBox(color: kColorCardLight),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.5),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'live_badge'.tr,
                        style: Get.textTheme.labelMedium!.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      demoTestTitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Get.textTheme.titleMedium!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: openDemoVideoPlayer,
                        focusColor: kColorFocus.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 13.h.clamp(100.0, 150.0),
            child: Row(
              children: [
                for (var i = 0; i < kDemoCategoryItemCount; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: CardLiveItem(
                      title: demoTestTitle(),
                      assetImage: kDemoPosterAsset,
                      onTap: openDemoVideoPlayer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
