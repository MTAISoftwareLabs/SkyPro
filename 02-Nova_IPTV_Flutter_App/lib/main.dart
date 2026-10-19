import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart' hide Transition;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mehdi_iptv/services/activation_guard_service.dart';
import 'package:mehdi_iptv/services/ads_service.dart';
import 'package:mehdi_iptv/services/app_update_service.dart';
import 'package:mehdi_iptv/services/presence_heartbeat_service.dart';
import 'package:mehdi_iptv/services/push_notification_service.dart';
import 'package:mehdi_iptv/core/runtime_seal.dart';
import 'package:mehdi_iptv/repository/api/api.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'helpers/helpers.dart';
import 'helpers/home_bootstrap_loader.dart';
import 'helpers/home_perf_logger.dart';
import 'logic/blocs/auth/auth_bloc.dart';
import 'logic/blocs/categories/channels/channels_bloc.dart';
import 'logic/blocs/categories/live_caty/live_caty_bloc.dart';
import 'logic/blocs/categories/movie_caty/movie_caty_bloc.dart';
import 'logic/blocs/categories/series_caty/series_caty_bloc.dart';
import 'logic/cubits/downloads/downloads_cubit.dart';
import 'logic/cubits/favorites/favorites_cubit.dart';
import 'logic/cubits/home/home_recent_cubit.dart';
import 'logic/cubits/prefetch/prefetch_cubit.dart';
import 'logic/cubits/settings/settings_cubit.dart';
import 'logic/cubits/watch/watching_cubit.dart';
import 'presentation/screens/screens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await GetStorage.init();
    await GetStorage.init("favorites");
  } catch (e) {
    debugPrint('GetStorage init error: $e');
  }
  try {
    await AppPerf.init();
  } catch (e) {
    debugPrint('AppPerf init error: $e');
  }
  try {
    migratePreferredPlayerToVlcPrimary();
  } catch (e) {
    debugPrint('migratePreferredPlayerToVlcPrimary error: $e');
  }
  HomePerfLogger.mark('main_storage_ready');
  try {
    await applyInitialAppOrientation();
  } catch (e) {
    debugPrint('applyInitialAppOrientation error: $e');
  }
  try {
    await applyScreenshotProtection();
  } catch (e) {
    debugPrint('applyScreenshotProtection error: $e');
  }
  try {
    unawaited(AdsService.init());
  } catch (e) {
    debugPrint('AdsService init error: $e');
  }

  runApp(
    MyApp(
      iptv: IpTvApi(),
      authApi: AuthApi(),
      watchingLocale: WatchingLocale(),
      favoriteLocale: FavoriteLocale(),
    ),
  );
}

class MyApp extends StatefulWidget {
  final IpTvApi iptv;
  final AuthApi authApi;
  final WatchingLocale watchingLocale;
  final FavoriteLocale favoriteLocale;
  const MyApp({
    super.key,
    required this.iptv,
    required this.authApi,
    required this.watchingLocale,
    required this.favoriteLocale,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// يُحافظ على مسار التنقل عند إعادة بناء `GetMaterialApp` بعد تغيير الثيم.
  final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // نبضة الحضور تُبدأ من السبلاش بعد نجاح الترخيص (تجنّب سباق أول تثبيت).

    //Enable FullScreen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

    // التطبيق أفقياً دائماً من أول إطار.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(lockHomeScreenLandscape());
    });
  }

  @override
  void dispose() {
    PresenceHeartbeatService.instance.stop();
    PushNotificationService.instance.stop();
    ActivationGuardService.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
    }
  }

  @override
  void didHaveMemoryPressure() {
    AppPerf.onMemoryPressure(isUrgent: true);
  }

  Future<void> _handleAppResumed() async {
    final ctx = _rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    RuntimeSeal.touchQuiet();
    AppUpdateService.instance.onAppResumed(ctx);
    unawaited(ActivationGuardService.instance.enforceOnResume());
    if (LocaleApi.getUserSync() != null) {
      ctx.read<FavoritesCubit>().initialData();
      ctx.read<WatchingCubit>().initialData();
    }
    await HomeBootstrapLoader.ensureHomeDataIfNeeded(ctx);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => AuthBloc(widget.authApi)),
        BlocProvider(create: (context) => LiveCatyBloc(widget.iptv)),
        BlocProvider(create: (context) => MovieCatyBloc(widget.iptv)),
        BlocProvider(create: (context) => SeriesCatyBloc(widget.iptv)),
        BlocProvider(create: (context) => ChannelsBloc(widget.iptv)),
        BlocProvider(
          create: (context) => HomeRecentCubit(context.read<ChannelsBloc>()),
        ),
        BlocProvider(create: (context) => PrefetchCubit()),
      ],
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: widget.iptv),
          RepositoryProvider.value(value: widget.authApi),
          RepositoryProvider.value(value: widget.watchingLocale),
          RepositoryProvider.value(value: widget.favoriteLocale),
        ],
        child: BlocProvider(
          create: (context) => SettingsCubit(),
            child: BlocProvider(
              create: (context) => FavoritesCubit(widget.favoriteLocale),
              child: BlocProvider(
                create: (context) => DownloadsCubit(),
                child: BlocProvider(
                  create: (context) => WatchingCubit(widget.watchingLocale),
                  child: ResponsiveSizer(
                  builder: (context, orient, type) {
                    final localeCode =
                        GetStorage().read(kStorageLocale) as String? ?? 'en';
                    return ValueListenableBuilder<int>(
                      valueListenable: homeThemeRevision,
                      builder: (context, _, _) {
                        return ValueListenableBuilder<int>(
                          valueListenable: appLocaleRevision,
                          builder: (context, _, _) {
                            final activeLocale =
                                GetStorage().read(kStorageLocale) as String? ??
                                localeCode;
                            return GetMaterialApp(
                              navigatorKey: _rootNavigatorKey,
                              navigatorObservers: [kAppRouteObserver],
                              title: appName,
                              theme: MyThemApp.themeData(context),
                              debugShowCheckedModeBanner: false,
                              translations: AppTranslations(),
                              locale: Locale(activeLocale),
                              fallbackLocale: const Locale('en'),
                              builder: (context, child) => Directionality(
                                textDirection: TextDirection.ltr,
                                child: child!,
                              ),
                              initialRoute: "/",
                              getPages: [
                                GetPage(
                                  name: screenSplash,
                                  page: () => const SplashScreen(),
                                ),
                                GetPage(
                                  name: screenLicenseInvalid,
                                  page: () => const LicenseInvalidScreen(),
                                ),
                                GetPage(
                                  name: screenEntry,
                                  page: () => const LoginEntryScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenHomeBootstrap,
                                  page: () => const HomeBootstrapScreen(),
                                ),
                                GetPage(
                                  name: screenWelcome,
                                  page: () => const WelcomeScreen(),
                                  // بلا fade: انتقال التلفاز أحيانًا ما يكملش وتبقى الدائرة على 100%.
                                  transition: Transition.noTransition,
                                  transitionDuration: Duration.zero,
                                ),
                                GetPage(
                                  name: screenLiveCategories,
                                  page: () => const LiveCategoriesScreen(),
                                  transition: Transition.noTransition,
                                ),
                                GetPage(
                                  name: screenRegister,
                                  page: () => const RegisterScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenMovieCategories,
                                  page: () => const MovieCategoriesScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenSeriesCategories,
                                  page: () => const SeriesCategoriesScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenSettings,
                                  page: () => const SettingsScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenManageAccounts,
                                  page: () => const ManageAccountsScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenFavourite,
                                  page: () => const FavouriteScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenCatchUp,
                                  page: () => const CatchUpScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenDownloads,
                                  page: () => const DownloadsScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenNotifications,
                                  page: () => const NotificationsInboxScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenAddPlaylist,
                                  page: () => const AddPlaylistScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                                GetPage(
                                  name: screenPlaylistCode,
                                  page: () => const PlaylistCodeScreen(),
                                  transition: kEntryPageTransition,
                                  transitionDuration:
                                      kEntryPageTransitionDuration,
                                ),
                              ],
                            );
                          },
                        );
                      },
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
