part of '../screens.dart';

/// نتيجة فحص لوحة التفعيل عند الإقلاع.
const int kSplashPanelOk = 0;
const int kSplashPanelOffline = 1;
const int kSplashPanelAuth = 2;
const int kSplashPanelError = 3;
const int kSplashPanelClock = 4;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _activationApi = ActivationApi();
  final _storage = GetStorage();
  final FocusNode _offlineRetryFocus = FocusNode(debugLabel: 'splash_offline_retry');
  String _deviceId = '';
  String _statusKey = 'splash_loading_account';
  bool _navigated = false;
  bool _leaveScheduled = false;
  bool _panelOffline = false;
  bool _offlineRetryBusy = false;
  String? _nextScreen;
  late final DateTime _splashShownAt;

  /// إظهار شعار السبلاش ثوانٍ حتى مع جلسة مسجّلة مسبقاً.
  static const Duration _minSplashVisible = Duration(milliseconds: 1200);

  /// نفس شرط الدخول للرئيسية من [LoginEntryScreen] (جلسة صالحة + تفعيل عند الدخول باليوزر).
  bool _canAutoEnterHome(AuthSuccess state) {
    final user = state.user;
    final serverUrl = (user.serverInfo?.serverUrl ?? '').trim();
    final username = (user.userInfo?.username ?? '').trim();
    final password = (user.userInfo?.password ?? '').trim();
    final hasCreds = username.isNotEmpty && password.isNotEmpty;
    final hasPlaylist = serverUrl.isNotEmpty && !hasCreds;
    if (!hasCreds && !hasPlaylist) return false;
    if (shouldBlockExpiredIptvSession(
      expDate: user.userInfo?.expDate,
      status: user.userInfo?.status,
      username: username,
      password: password,
    )) {
      return false;
    }
    final act = _storage.read('activation_status')?.toString() ?? '';
    return canPassActivationGate(status: act, hasPlaylist: hasPlaylist);
  }

  Future<void> _kickExpiredIptvToLogin() async {
    if (_navigated || _panelOffline) return;
    await _storage.write(kStorageIptvServerExpiredKick, true);
    await _storage.write(kStorageSuppressPlaylistAutoLogin, true);
    try {
      await LocaleApi.logOut();
    } catch (_) {}
    if (mounted) {
      context.read<AuthBloc>().add(AuthClearSession());
    }
    _queueAfterSplash(screenEntry);
  }

  void _queueAfterSplash(String screen) {
    if (_navigated || !mounted || _panelOffline) return;
    _nextScreen = screen;
    unawaited(_leaveWhenReady());
  }

  Future<void> _leaveWhenReady() async {
    if (_leaveScheduled || _panelOffline) return;
    _leaveScheduled = true;
    final remain =
        _minSplashVisible - DateTime.now().difference(_splashShownAt);
    if (remain > Duration.zero) {
      await Future<void>.delayed(remain);
    }
    // نكمّل فحص Play قبل الخروج باش toast التحديث يبان فوراً فـ login/home.
    try {
      await AppUpdateService.instance
          .prefetchAtLaunch()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (_navigated || !mounted || _panelOffline) return;
    final screen = _nextScreen ?? screenEntry;
    _navigated = true;

    if (screen == screenWelcome) {
      unawaited(lockHomeScreenLandscape());
      changeDeviceOrient();
      unawaited(navigateToHomeBootstrap());
      return;
    }
    Get.offAndToNamed(screen);
  }

  /// نتيجة فحص اللوحة عند الإقلاع (ليست كلها «بدون إنترنت»).
  int _panelFailKind = kSplashPanelOffline;
  String _panelFailHint = '';

  bool _reasonLooksOffline(String reason) {
    final r = reason.toLowerCase();
    return r.contains('exception') ||
        r.contains('timeout') ||
        r.contains('timed out') ||
        r.contains('socket') ||
        r.contains('connection') ||
        r.contains('network') ||
        r.contains('failed host lookup') ||
        r.contains('http=599') ||
        r.contains('http=0');
  }

  bool _reasonLooksAuth(String reason) {
    final r = reason.toLowerCase();
    return r.contains('http=401') ||
        r.contains('unauthorized') ||
        r.contains('invalid_signature') ||
        r.contains('missing_or_invalid_signature') ||
        r.contains('missing_or_invalid_nonce') ||
        r.contains('nonce_reused') ||
        r.contains('api_secret_not_configured');
  }

  bool _reasonLooksClock(String reason) {
    final r = reason.toLowerCase();
    return r.contains('timestamp_expired') ||
        r.contains('clock') ||
        r.contains('time skew') ||
        r.contains('date and time');
  }

  /// فحص التفعيل من اللوحة — [kSplashPanelOk] فقط عند رد ناجح (حتى لو Inactive).
  Future<int> _refreshActivationAtLaunch() async {
    try {
      _deviceId = await _activationApi.getDeviceId().timeout(
        const Duration(seconds: 6),
        onTimeout: () => '',
      );
      if (_deviceId.isEmpty) {
        _panelFailHint = 'empty_device_id';
        return kSplashPanelError;
      }
      await _storage.write('device_id', _deviceId);
      final result = await _activationApi
          .checkActivation(_deviceId, allowAutoRegister: true)
          .timeout(const Duration(seconds: 12));
      if (result['_check_failed'] == true) {
        final reason =
            (result['_inactive_reason'] ?? result['_check_failed'] ?? 'unknown')
                .toString();
        _panelFailHint = reason;
        // ساعة الجهاز غالطة (شائع في Android TV Emulator) → 401 timestamp_expired
        if (_reasonLooksClock(reason)) return kSplashPanelClock;
        if (_reasonLooksAuth(reason)) return kSplashPanelAuth;
        if (_reasonLooksOffline(reason)) return kSplashPanelOffline;
        return kSplashPanelError;
      }
      await applyScreenshotProtection();
      ActivationGuardService.instance.markServerChecked();
      unawaited(PushNotificationService.instance.sync(deviceId: _deviceId));
      return kSplashPanelOk;
    } on TimeoutException catch (e) {
      _panelFailHint = 'timeout:$e';
      return kSplashPanelOffline;
    } catch (e) {
      _panelFailHint = 'exception:$e';
      if (_reasonLooksClock(e.toString())) return kSplashPanelClock;
      if (_reasonLooksAuth(e.toString())) return kSplashPanelAuth;
      return kSplashPanelOffline;
    }
  }

  void _showPanelOfflineGate([int kind = kSplashPanelOffline]) {
    if (!mounted || _navigated) return;
    setState(() {
      _panelOffline = true;
      _panelFailKind = kind;
      _offlineRetryBusy = false;
      _statusKey = kind == kSplashPanelClock
          ? 'splash_panel_clock_title'
          : kind == kSplashPanelAuth
          ? 'splash_panel_auth_title'
          : kind == kSplashPanelError
          ? 'splash_panel_error_title'
          : 'splash_panel_offline_title';
    });
    // تلفزيون: ركّز الزر فوراً ثم مرة ثانية بعد الإطار (بعض الأجهزة تتأخر).
    void focusRetry() {
      if (!mounted || _navigated || _offlineRetryBusy) return;
      if (!_offlineRetryFocus.canRequestFocus) return;
      _offlineRetryFocus.requestFocus();
    }

    focusRetry();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusRetry();
      Future<void>.delayed(const Duration(milliseconds: 120), focusRetry);
    });
  }

  Future<void> _retryPanelCheck() async {
    if (_offlineRetryBusy || _navigated) return;
    setState(() {
      _offlineRetryBusy = true;
      _panelOffline = false;
      _statusKey = 'splash_checking_activation';
    });
    final kind = await _refreshActivationAtLaunch();
    if (!mounted || _navigated) return;
    if (kind != kSplashPanelOk) {
      _showPanelOfflineGate(kind);
      return;
    }
    await _proceedAfterPanelOk();
  }

  Future<void> _proceedAfterPanelOk() async {
    if (!mounted || _navigated) return;
    setState(() {
      _panelOffline = false;
      _offlineRetryBusy = false;
      _statusKey = 'splash_loading_account';
    });
    context.read<SettingsCubit>().getSettingsCode();
    context.read<AuthBloc>().add(AuthGetUser());
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (!_navigated && mounted && !_panelOffline) {
        _nextScreen ??= screenEntry;
        unawaited(_leaveWhenReady());
      }
    });
  }

  Future<void> _continueAfterLicense() async {
    PresenceHeartbeatService.instance.start();
    PushNotificationService.instance.start();
    ActivationGuardService.instance.start();
    unawaited(_activationApi.syncNotificationInbox());
    if (!mounted || _navigated) return;
    setState(() {
      _panelOffline = false;
      _statusKey = 'splash_checking_activation';
    });
    final kind = await _refreshActivationAtLaunch();
    if (!mounted || _navigated) return;
    if (kind != kSplashPanelOk) {
      // فشل الفحص → لا ندخل login_entry حتى ينجح (رسالة حسب نوع الفشل).
      _showPanelOfflineGate(kind);
      return;
    }
    await _proceedAfterPanelOk();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;

    // فحص تحديث Play بالتوازي مع الترخيص — النتيجة جاهزة عند login_entry / الرئيسية.
    unawaited(AppUpdateService.instance.prefetchAtLaunch());

    try {
      if (await SellerLicenseService.confirmLocalSeal()) {
        if (await RuntimeSeal.launchFullySealed(LicenseVerifyResult.valid)) {
          RuntimeSeal.startPulse();
          unawaited(
            SellerLicenseService.ensureLicenseForLaunch(
              allowLocalFastPath: false,
            ),
          );
          await _continueAfterLicense();
          return;
        }
      }

      setState(() => _statusKey = 'splash_verifying_license');
      var licenseResult = await RuntimeSeal.primeAtLaunch();
      if (!mounted || _navigated) return;
      if (licenseResult == LicenseVerifyResult.noConnection &&
          await SellerLicenseService.confirmLocalSeal()) {
        licenseResult = LicenseVerifyResult.valid;
      }
      if (!await RuntimeSeal.launchFullySealed(licenseResult)) {
        _navigated = true;
        Get.offAllNamed(
          screenLicenseInvalid,
          arguments:
              licenseResult == LicenseVerifyResult.valid
                  ? LicenseVerifyResult.rejected
                  : licenseResult,
        );
        return;
      }
      RuntimeSeal.startPulse();
      await _continueAfterLicense();
    } catch (_) {
      if (!mounted || _navigated) return;
      if (await SellerLicenseService.confirmLocalSeal()) {
        RuntimeSeal.startPulse();
        PresenceHeartbeatService.instance.start();
        PushNotificationService.instance.start();
        ActivationGuardService.instance.start();
        await _continueAfterLicense();
        return;
      }
      _navigated = true;
      Get.offAllNamed(
        screenLicenseInvalid,
        arguments: LicenseVerifyResult.rejected,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _splashShownAt = DateTime.now();
    // التطبيق أفقياً من أول إطار (هاتف + تلفاز).
    unawaited(lockHomeScreenLandscape());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await syncAndPersistTvDeviceFlag(context);
      if (!mounted) return;
      await lockHomeScreenLandscape();
      await _bootstrap();
    });
  }

  @override
  void dispose() {
    _offlineRetryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OrientationBuilder(
        builder: (context, orientation) {
          return BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              if (_navigated || _panelOffline) return;
              if (state is AuthSuccess) {
                final user = state.user;
                if (shouldBlockExpiredIptvSession(
                  expDate: user.userInfo?.expDate,
                  status: user.userInfo?.status,
                  username: user.userInfo?.username,
                  password: user.userInfo?.password,
                )) {
                  unawaited(_kickExpiredIptvToLogin());
                  return;
                }
                context.read<FavoritesCubit>().initialData();
                if (_canAutoEnterHome(state)) {
                  _queueAfterSplash(screenWelcome);
                } else {
                  _queueAfterSplash(screenEntry);
                }
              } else if (state is AuthFailed) {
                _queueAfterSplash(screenEntry);
              }
            },
            child: _panelOffline
                ? _SplashPanelOfflineGate(
                    busy: _offlineRetryBusy,
                    failKind: _panelFailKind,
                    failHint: _panelFailHint,
                    retryFocus: _offlineRetryFocus,
                    onRetry: _retryPanelCheck,
                  )
                : LoadingWidget(statusKey: _statusKey),
          );
        },
      ),
    );
  }
}

/// بوابة انتظار: لا دخول لـ login_entry قبل فحص ناجح من لوحة التفعيل.
class _SplashPanelOfflineGate extends StatefulWidget {
  const _SplashPanelOfflineGate({
    required this.busy,
    required this.failKind,
    required this.failHint,
    required this.retryFocus,
    required this.onRetry,
  });

  final bool busy;
  final int failKind;
  final String failHint;
  final FocusNode retryFocus;
  final VoidCallback onRetry;

  @override
  State<_SplashPanelOfflineGate> createState() =>
      _SplashPanelOfflineGateState();
}

class _SplashPanelOfflineGateState extends State<_SplashPanelOfflineGate> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.retryFocus.addListener(_onFocusNodeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTvFocus());
  }

  @override
  void didUpdateWidget(covariant _SplashPanelOfflineGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retryFocus != widget.retryFocus) {
      oldWidget.retryFocus.removeListener(_onFocusNodeChanged);
      widget.retryFocus.addListener(_onFocusNodeChanged);
    }
    if (!widget.busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTvFocus());
    }
  }

  @override
  void dispose() {
    widget.retryFocus.removeListener(_onFocusNodeChanged);
    super.dispose();
  }

  void _onFocusNodeChanged() {
    final v = widget.retryFocus.hasFocus;
    if (_focused == v || !mounted) return;
    setState(() => _focused = v);
  }

  void _ensureTvFocus() {
    if (!mounted || widget.busy) return;
    if (!isTv(context)) return;
    if (widget.retryFocus.hasFocus) return;
    widget.retryFocus.requestFocus();
  }

  KeyEventResult _onRetryKey(FocusNode node, KeyEvent event) {
    return settingsTvActivateOnSelect(event, () {
      if (!widget.busy) widget.onRetry();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final focusColor = kColorFocus;
    final btnH = tv ? 54.0 : 48.0;
    final radius = 14.0;
    final scale = kReduceFocusMotion
        ? 1.0
        : (_focused ? (tv ? 1.08 : 1.04) : 1.0);

    final isClock = widget.failKind == kSplashPanelClock;
    final isAuth = widget.failKind == kSplashPanelAuth;
    final isError = widget.failKind == kSplashPanelError;

    final titleKey = isClock
        ? 'splash_panel_clock_title'
        : isAuth
        ? 'splash_panel_auth_title'
        : isError
        ? 'splash_panel_error_title'
        : 'splash_panel_offline_title';
    final subtitleKey = isClock
        ? 'splash_panel_clock_subtitle'
        : isAuth
        ? 'splash_panel_auth_subtitle'
        : isError
        ? 'splash_panel_error_subtitle'
        : 'splash_panel_offline_subtitle';
    final icon = isClock
        ? Icons.schedule_rounded
        : isAuth
        ? Icons.vpn_key_off_rounded
        : isError
        ? Icons.error_outline_rounded
        : Icons.wifi_off_rounded;
    final iconColor = isClock
        ? const Color(0xFF42A5F5)
        : isAuth
        ? const Color(0xFFFF7043)
        : isError
        ? const Color(0xFFEF5350)
        : const Color(0xFFFFA726);

    widget.retryFocus.onKeyEvent = _onRetryKey;

    return Container(
      width: getSize(context).width,
      height: getSize(context).height,
      decoration: kDecorBackground,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: tv ? 520 : 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image(
                    width: getSize(context).height * .16,
                    height: getSize(context).height * .16,
                    image: const AssetImage(kIconSplash),
                  ),
                  const SizedBox(height: 10),
                  Text(appName, style: Get.textTheme.displaySmall),
                  const SizedBox(height: 22),
                  Icon(icon, size: tv ? 48 : 42, color: iconColor),
                  const SizedBox(height: 14),
                  Text(
                    titleKey.tr,
                    textAlign: TextAlign.center,
                    style: Get.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitleKey.tr,
                    textAlign: TextAlign.center,
                    style: Get.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.45,
                    ),
                  ),
                  if (kDebugMode && widget.failHint.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      widget.failHint,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Get.textTheme.bodySmall?.copyWith(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Focus(
                    focusNode: widget.retryFocus,
                    autofocus: tv,
                    canRequestFocus: !widget.busy,
                    descendantsAreFocusable: false,
                    descendantsAreTraversable: false,
                    onKeyEvent: _onRetryKey,
                    onFocusChange: (v) {
                      if (_focused == v) return;
                      setState(() => _focused = v);
                    },
                    child: AnimatedScale(
                      scale: scale,
                      duration: AppPerf.instance.focusAnimDuration,
                      curve: Curves.easeOutCubic,
                      child: AnimatedContainer(
                        duration: AppPerf.instance.focusAnimDuration,
                        curve: Curves.easeOutCubic,
                        width: double.infinity,
                        height: btnH,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(
                            color: _focused
                                ? focusColor
                                : Colors.white.withValues(alpha: 0.22),
                            width: _focused ? 3 : 1.5,
                          ),
                          boxShadow: _focused && !kReduceFocusMotion
                              ? [
                                  BoxShadow(
                                    color: focusColor.withValues(alpha: 0.45),
                                    blurRadius: 18,
                                    spreadRadius: 1,
                                  ),
                                  BoxShadow(
                                    color: focusColor.withValues(alpha: 0.22),
                                    blurRadius: 8,
                                    spreadRadius: 0,
                                  ),
                                ]
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(radius - 1),
                          child: InkWell(
                            onTap: widget.busy ? null : widget.onRetry,
                            canRequestFocus: false,
                            borderRadius: BorderRadius.circular(radius - 1),
                            focusColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            splashColor: focusColor.withValues(alpha: 0.14),
                            child: Ink(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  radius - 1,
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: widget.busy
                                      ? [
                                          kColorPrimary.withValues(alpha: 0.55),
                                          kColorPrimaryDark.withValues(
                                            alpha: 0.55,
                                          ),
                                        ]
                                      : [kColorPrimary, kColorPrimaryDark],
                                ),
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.busy)
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: kColorBack,
                                        ),
                                      )
                                    else
                                      Icon(
                                        Icons.refresh_rounded,
                                        size: tv ? 24 : 22,
                                        color: kColorBack,
                                      ),
                                    const SizedBox(width: 10),
                                    Text(
                                      widget.busy
                                          ? 'splash_checking_activation'.tr
                                          : 'license_invalid_retry'.tr,
                                      style: TextStyle(
                                        fontSize: tv ? 17 : 15,
                                        fontWeight: FontWeight.w800,
                                        color: kColorBack,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key, this.statusKey});

  final String? statusKey;

  @override
  Widget build(BuildContext context) {
    final status = statusKey?.tr ?? '';
    final showStatus = status.isNotEmpty;

    return Container(
      width: getSize(context).width,
      height: getSize(context).height,
      decoration: kDecorBackground,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image(
            width: getSize(context).height * .22,
            height: getSize(context).height * .22,
            image: const AssetImage(kIconSplash),
          ),
          const SizedBox(height: 10),
          Text(appName, style: Get.textTheme.displaySmall),
          const SizedBox(height: 18),
          BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              final loading = state is AuthLoading || showStatus;
              if (!loading) return const SizedBox(height: 48);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: kColorPrimary),
                  if (showStatus) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        status,
                        textAlign: TextAlign.center,
                        style: Get.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
