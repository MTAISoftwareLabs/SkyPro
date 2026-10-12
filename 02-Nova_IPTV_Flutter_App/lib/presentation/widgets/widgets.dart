import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:pod_player/pod_player.dart';
import 'package:readmore/readmore.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:better_player_plus/better_player_plus.dart';

import '../../helpers/helpers.dart';
import '../../logic/blocs/auth/auth_bloc.dart';
import '../../repository/models/category.dart';
import '../../logic/cubits/downloads/downloads_cubit.dart';
import '../../logic/cubits/watch/watching_cubit.dart';
import '../../repository/models/serie_details.dart';
import '../../repository/models/watching.dart';
import '../../services/iptv_image_cache.dart';
import '../screens/screens.dart';
import '../../services/tmdb_rating_service.dart';
import 'tmdb_resolved_rating.dart';

part 'dialog.dart';
part 'live.dart';
part 'movie.dart';
part 'watching.dart';
part 'demo.dart';
part 'all_catalog_sort_bar.dart';
part 'category_sidebar_search.dart';
part 'app_tv_side_keyboard.dart';
part 'live_browser.dart';

/// شريط تقدّم المشاهدة بلون الثيم المختار.
class WatchProgressBar extends StatelessWidget {
  const WatchProgressBar({
    super.key,
    required this.progress,
    this.height = 4,
  });

  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ratio = progress.clamp(0.0, 1.0);
    if (ratio <= 0) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.grey.shade800),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: ratio,
              heightFactor: 1,
              child: ColoredBox(color: kColorPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// دائرة داخل الكارت ريثما تصل الصورة.
Widget posterCardImageLoadingPlaceholder({
  Color? backgroundColor,
  Color? indicatorColor,
  double size = 22,
  double strokeWidth = 2.2,
}) {
  return ColoredBox(
    color: backgroundColor ?? kColorCardLight,
    child: Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          color: indicatorColor ?? kColorPrimary,
        ),
      ),
    ),
  );
}

/// بوستر افتراضي عند غياب/فشل صورة الفيلم أو المسلسل من السيرفر.
Widget noPosterImage({BoxFit fit = BoxFit.cover}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final lw =
          constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 160.0;
      final lh =
          constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? constraints.maxHeight
              : lw * 1.5;
      final cw = (lw * dpr).round().clamp(1, 720);
      final ch = (lh * dpr).round().clamp(1, 1080);
      return Image.asset(
        kNoPosterAsset,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        filterQuality: FilterQuality.low,
        cacheWidth: cw,
        cacheHeight: ch,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => ColoredBox(
          color: kColorCardLight,
          child: Center(
            child: Icon(
              FontAwesomeIcons.image,
              color: Colors.white.withValues(alpha: 0.25),
              size: 28,
            ),
          ),
        ),
      );
    },
  );
}

String? movieStreamIdFromContentKey(String? contentKey) {
  final key = contentKey?.trim() ?? '';
  if (key.startsWith('movie:')) {
    final id = key.substring(6).trim();
    return id.isEmpty ? null : id;
  }
  return null;
}

/// دائرة تقدم التحميل فوق بوستر الفيلم (أثناء التحميل في الخلفية).
class MovieDownloadProgressOverlay extends StatelessWidget {
  const MovieDownloadProgressOverlay({super.key, this.contentKey});

  final String? contentKey;

  @override
  Widget build(BuildContext context) {
    final id = movieStreamIdFromContentKey(contentKey);
    if (id == null || id.isEmpty) return const SizedBox.shrink();

    return BlocBuilder<DownloadsCubit, DownloadsState>(
      buildWhen: (p, c) =>
          p.isDownloading(id) != c.isDownloading(id) ||
          p.progressOf(id) != c.progressOf(id) ||
          p.isDownloaded(id) != c.isDownloaded(id),
      builder: (context, state) {
        if (!state.isDownloading(id)) return const SizedBox.shrink();
        final p = state.progressOf(id).clamp(0.0, 1.0);
        final pct = (p * 100).round();
        return Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.55),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: p > 0.02 ? p : null,
                          strokeWidth: 3.2,
                          color: kColorPrimary,
                          backgroundColor: Colors.white24,
                        ),
                        Icon(
                          LucideIcons.download,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$pct%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// هيكل الشبكة + دائرة معزولة فوق الصفحة (لا تعوّض المحتوى).
class CatalogGridBusyPanel extends StatelessWidget {
  const CatalogGridBusyPanel({super.key, this.crossAxisCount = 5});

  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: crossAxisCount * 2,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: .72,
            ),
            itemBuilder: (_, _) {
              return const DecoratedBox(
                decoration: BoxDecoration(
                  color: kColorCardLight,
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              );
            },
          ),
        ),
        IgnorePointer(
          child: RepaintBoundary(
            child: ColoredBox(
              color: const Color(0x5505070D),
              child: Center(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: kColorPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
