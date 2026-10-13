part of 'screens.dart';

BoxDecoration get _homeScreenDecoration {
  return const BoxDecoration(color: kSkyProBlack);
}

Widget _homePosterImage({
  required String? assetImage,
  required String imageUrl,
}) {
  if (assetImage != null) {
    return Image.asset(
      assetImage,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
  if (imageUrl.isEmpty) {
    return noPosterImage();
  }
  return RepaintBoundary(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final lw = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 100.0;
        final lh = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : lw * 1.5;
        final mem = iptvMemCachePx(context, lw, lh);
        return CachedNetworkImage(
          imageUrl: imageUrl,
          cacheManager: iptvImageCacheManager,
          memCacheWidth: mem.$1,
          memCacheHeight: mem.$2,
          filterQuality: AppPerf.instance.useLowFilterQuality
              ? FilterQuality.low
              : FilterQuality.medium,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholderFadeInDuration: Duration.zero,
          useOldImageOnUrlChange: true,
          placeholder: (_, _) => const ColoredBox(color: kColorCardLight),
          errorWidget: (_, _, _) => noPosterImage(),
        );
      },
    ),
  );
}

class _HomeExpiryFooter extends StatelessWidget {
  const _HomeExpiryFooter();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (prev, curr) {
        if (prev.runtimeType != curr.runtimeType) return true;
        if (prev is AuthSuccess && curr is AuthSuccess) {
          return prev.user.userInfo?.expDate != curr.user.userInfo?.expDate;
        }
        return false;
      },
      builder: (context, authState) {
        if (authState is! AuthSuccess) return const SizedBox.shrink();
        final expDate = authState.user.userInfo?.expDate;
        final rem = iptvSubscriptionRemaining(expDate);
        if (rem == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              'not_available'.tr,
              textAlign: TextAlign.center,
              style: Get.textTheme.bodyMedium!.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w600,
                fontSize: 11.5.sp,
              ),
            ),
          );
        }
        if (rem.isLifetime) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              'activation_lifetime'.tr,
              textAlign: TextAlign.center,
              style: Get.textTheme.bodyMedium!.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w600,
                fontSize: 11.5.sp,
              ),
            ),
          );
        }
        if (rem.expired) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              'subscription_expired'.tr,
              textAlign: TextAlign.center,
              style: Get.textTheme.bodyMedium!.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w600,
                fontSize: 11.5.sp,
              ),
            ),
          );
        }

        final String prefix;
        final String suffix;
        switch (rem.unit) {
          case IptvRemainingUnit.days:
            prefix = 'subscription_ends_in_prefix'.tr;
            suffix = 'subscription_ends_in_suffix'.tr;
            break;
          case IptvRemainingUnit.hours:
            prefix = 'subscription_ends_in_hours_prefix'.tr;
            suffix = 'subscription_ends_in_hours_suffix'.tr;
            break;
          case IptvRemainingUnit.minutes:
            prefix = 'subscription_ends_in_minutes_prefix'.tr;
            suffix = 'subscription_ends_in_minutes_suffix'.tr;
            break;
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: RichText(
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: Get.textTheme.bodyMedium!.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w600,
                fontSize: 11.5.sp,
                letterSpacing: 0.2,
                height: 1.15,
              ),
              children: [
                TextSpan(text: prefix),
                TextSpan(
                  text: '${rem.value}',
                  style: TextStyle(
                    color: kColorPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(text: suffix),
              ],
            ),
          ),
        );
      },
    );
  }
}
