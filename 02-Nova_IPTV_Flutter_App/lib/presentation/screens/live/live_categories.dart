part of '../screens.dart';

String _liveBrowserAccountIdForOrder(BuildContext context) {
  final active = SavedAccountsRepository.activeAccountId?.trim();
  if (active != null && active.isNotEmpty) return active;
  try {
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthSuccess) {
      final url = auth.user.serverInfo?.serverUrl ?? '';
      final user = auth.user.userInfo?.username ?? '';
      if (url.isNotEmpty && user.isNotEmpty) {
        return SavedAccountsRepository.accountIdFor(url, user);
      }
    }
  } catch (_) {}
  return 'default';
}

/// أول فئة مستخدم (بعد الترتيب المحفوظ)، مش أول فئة خام من السيرفر.
String _firstOrderedLiveCategoryId(
  BuildContext context,
  List<CategoryModel> raw,
) {
  final filtered = ParentalControlService.instance.filterAdultCategories(raw);
  if (filtered.isEmpty) return '';
  final order = LiveCategoryOrderStore.load(_liveBrowserAccountIdForOrder(context));
  final ordered = LiveCategoryOrderStore.apply(filtered, order);
  for (final c in ordered) {
    final id = (c.categoryId ?? '').trim();
    if (id.isNotEmpty && !isIptvPinnedLiveCategory(id)) return id;
  }
  return (filtered.first.categoryId ?? '').trim();
}

Future<void> openLiveIptvBrowser() async {
  final ctx = Get.context;
  if (ctx == null) return;
  if (ctx.read<SettingsCubit>().state.isDemo) {
    await Get.toNamed(screenLiveCategories);
    return;
  }

  String firstId = '';
  final catState = ctx.read<LiveCatyBloc>().state;
  if (catState is LiveCatySuccess) {
    firstId = _firstOrderedLiveCategoryId(ctx, catState.categories);
  }

  if (firstId.isEmpty) {
    await Get.toNamed(screenLiveCategories);
    return;
  }

  await Get.to(
    () => FullVideoScreen(
      title: 'home_nav_channels'.tr,
      link: '',
      isLive: true,
      channelLive: null,
      initialLiveCategoryId: firstId,
      startInIptvBrowser: true,
    ),
    routeName: '/full-video-live-browser',
    transition: Transition.noTransition,
    duration: Duration.zero,
    preventDuplicates: true,
  );
}

/// بوابة Live TV: تفتح واجهة القائمة مباشرة من الكاش دون صفحة فارغة.
class LiveCategoriesScreen extends StatefulWidget {
  const LiveCategoriesScreen({super.key});

  @override
  State<LiveCategoriesScreen> createState() => _LiveCategoriesScreenState();
}

class _LiveCategoriesScreenState extends State<LiveCategoriesScreen>
    with
        LandscapeMainAppStateMixin<LiveCategoriesScreen>,
        ParentalSectionGateMixin {
  @override
  ParentalSection get parentalGateSection => ParentalSection.live;

  bool _launching = false;
  String? _errorKey;

  Future<void> _bootstrapAndOpenBrowser() async {
    if (!mounted || _launching) return;
    _launching = true;

    try {
      final settings = context.read<SettingsCubit>().state;
      if (settings.isDemo) {
        _launching = false;
        return;
      }

      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthSuccess) {
        setState(() => _errorKey = 'please_login_first');
        _launching = false;
        return;
      }

      final liveCaty = context.read<LiveCatyBloc>();
      var catState = liveCaty.state;
      if (catState is! LiveCatySuccess) {
        liveCaty.add(GetLiveCategories());
        for (var i = 0; i < 40 && mounted; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          catState = liveCaty.state;
          if (catState is LiveCatySuccess) break;
        }
      }

      if (!mounted) return;
      catState = liveCaty.state;
      if (catState is! LiveCatySuccess) {
        setState(() => _errorKey = 'no_categories');
        _launching = false;
        return;
      }

      final categories = ParentalControlService.instance.filterAdultCategories(
        catState.categories,
      );
      if (categories.isEmpty) {
        setState(() => _errorKey = 'no_categories');
        _launching = false;
        return;
      }

      final firstId = _firstOrderedLiveCategoryId(context, catState.categories);
      if (firstId.isEmpty) {
        setState(() => _errorKey = 'no_categories');
        _launching = false;
        return;
      }

      final channelsBloc = context.read<ChannelsBloc>();
      if (!channelsBloc.hasLiveCategoryCached(firstId)) {
        await channelsBloc.ensureLiveCategoryCached(firstId).timeout(
          const Duration(seconds: 8),
          onTimeout: () => const [],
        );
      }
      if (!mounted) return;

      _launching = false;
      await Get.off(
        () => FullVideoScreen(
          title: 'home_nav_channels'.tr,
          link: '',
          isLive: true,
          channelLive: null,
          initialLiveCategoryId: firstId,
          startInIptvBrowser: true,
        ),
        routeName: '/full-video-live-browser',
        transition: Transition.noTransition,
        duration: Duration.zero,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Live bootstrap error: $e');
      if (mounted) {
        setState(() => _errorKey = 'live_channel_open_error');
      }
      _launching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildWithParentalGate(_buildBody(context));
  }

  Widget _buildBody(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: (prev, curr) => prev.isDemo != curr.isDemo,
      builder: (context, settings) {
        if (settings.isDemo) {
          return Scaffold(
            body: Ink(
              width: 100.w,
              height: 100.h,
              decoration: kDecorBackground,
              child: const SafeArea(child: DemoLiveChannelsPanel()),
            ),
          );
        }

        if (_errorKey == null && !_launching) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(_bootstrapAndOpenBrowser());
          });
        }

        if (_errorKey != null) {
          return Scaffold(
            backgroundColor: const Color(0xFF141824),
            body: Ink(
              width: 100.w,
              height: 100.h,
              decoration: const BoxDecoration(color: Color(0xFF141824)),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorKey!.tr,
                        textAlign: TextAlign.center,
                        style: Get.textTheme.titleMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _errorKey = null;
                            _launching = false;
                          });
                          unawaited(_bootstrapAndOpenBrowser());
                        },
                        child: Text('license_invalid_retry'.tr),
                      ),
                      TextButton(
                        onPressed: () => Get.back(),
                        child: Text('back'.tr),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
