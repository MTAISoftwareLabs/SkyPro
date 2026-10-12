part of 'widgets.dart';

// ── حسابات الحجم المشتركة ──────────────────────────────────
// عرض الكارت: ~28% من عرض الشاشة، بحد أدنى 140 وأقصى 260
double _cardWidth(BuildContext context) => (28.w).clamp(140.0, 260.0);

// ارتفاع الكارت: ~28% من ارتفاع الشاشة، بحد أدنى 130 وأقصى 200
double _cardHeight(BuildContext context) => (28.h).clamp(130.0, 200.0);

// ارتفاع منطقة الاسم أسفل الكارت
const double _titleHeight = 28.0;

class CardMovieContinueWatch extends StatelessWidget {
  const CardMovieContinueWatch({
    super.key,
    required this.onTap,
    required this.model,
    this.boldTitle = false,
    this.expandToCell = false,
  });

  final Function() onTap;
  final WatchingModel model;

  /// عناوين أوضح وأعرض (مثل المفضلة / Catch Up).
  final bool boldTitle;

  /// يملأ خلية الشبكة (Favourites / Catch Up) بدل العرض الثابت الصغير.
  final bool expandToCell;

  @override
  Widget build(BuildContext context) {
    if (expandToCell) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final titleH = boldTitle ? _titleHeight + 2.0 : _titleHeight - 5.0;
          final gap = 5.0;
          final cardW = constraints.maxWidth;
          final cardH = (constraints.maxHeight - titleH - gap)
              .clamp(72.0, constraints.maxHeight);
          return _buildCard(
            context,
            cardW: cardW,
            cardH: cardH,
            titleH: titleH,
          );
        },
      );
    }

    final cardW = _cardWidth(context);
    final cardH = _cardHeight(context);
    final titleH = boldTitle ? _titleHeight + 2.0 : _titleHeight - 5.0;
    return _buildCard(
      context,
      cardW: cardW,
      cardH: cardH,
      titleH: titleH,
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required double cardW,
    required double cardH,
    required double titleH,
  }) {
    final iconSize = expandToCell
        ? (cardH * 0.22).clamp(22.0, 42.0)
        : (3.5.h).clamp(18.0, 30.0);
    final fontSize = boldTitle
        ? (expandToCell ? (cardW * 0.09).clamp(12.0, 16.0) : (2.1.h).clamp(13.0, 17.0))
        : (1.5.h).clamp(10.0, 14.0);
    final radius = (1.w).clamp(6.0, 12.0);
    final authState = context.read<AuthBloc>().state;
    final serverUrl = authState is AuthSuccess
        ? authState.user.serverInfo?.serverUrl
        : null;
    final imageUrl = resolveImageUrl(model.image, serverUrl);

    return SizedBox(
      width: cardW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── صورة + زر تشغيل + شريط التقدم ──────────────────
          SizedBox(
            width: cardW,
            height: cardH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Ink(
                decoration: BoxDecoration(
                  color: kColorCardDark,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Stack(
                  children: [
                    // الصورة
                    Positioned.fill(
                      child: imageUrl.isEmpty
                          ? const CardNoImage()
                          : Builder(
                              builder: (context) {
                                final mem = iptvMemCachePx(context, cardW, cardH);
                                return CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  cacheManager: iptvImageCacheManager,
                                  memCacheWidth: mem.$1,
                                  memCacheHeight: mem.$2,
                                  fit: BoxFit.cover,
                                  fadeInDuration: Duration.zero,
                                  fadeOutDuration: Duration.zero,
                                  placeholderFadeInDuration: Duration.zero,
                                  useOldImageOnUrlChange: true,
                                  placeholder:
                                      (_, _) => const ColoredBox(
                                        color: kColorCardDark,
                                      ),
                                  errorWidget:
                                      (_, _, _) => const CardNoImage(),
                                );
                              },
                            ),
                    ),

                    // طبقة شفافة قابلة للضغط (تحافظ على التركيز)
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onTap,
                          focusColor: kColorFocus.withValues(alpha: 0.3),
                          child: Ink(color: kColorCardDark.withValues(alpha: .45)),
                        ),
                      ),
                    ),

                    // أيقونة التشغيل
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: onTap,
                        child: Center(
                          child: Icon(
                            FontAwesomeIcons.circlePlay,
                            size: iconSize,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    // شريط تقدّم المشاهدة بلون الثيم
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: WatchProgressBar(
                        progress: model.durationStrm > 0 && model.sliderValue > 0
                            ? (model.sliderValue / model.durationStrm)
                                .clamp(0.0, 1.0)
                            : 0.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 5),

          // ── اسم الفيلم ───────────────────────────────────────
          SizedBox(
            width: cardW,
            height: titleH,
            child: Text(
              model.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                color: Colors.white,
                fontWeight: boldTitle ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// أبعاد كارت [CardMovieContinueWatch] — لإعادة الاستخدام (مثل تبويب القنوات في المفضلة).
double continueWatchCardWidth(BuildContext context) => _cardWidth(context);

double continueWatchCardHeight(BuildContext context) => _cardHeight(context);

const double continueWatchTitleHeight = _titleHeight;

class CardNoImage extends StatelessWidget {
  const CardNoImage({super.key});

  @override
  Widget build(BuildContext context) {
    return noPosterImage();
  }
}
