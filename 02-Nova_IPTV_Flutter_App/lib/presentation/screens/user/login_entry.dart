part of '../screens.dart';

/// Ø´Ø§Ø´Ø© Ø§Ù„Ø¯Ø®ÙˆÙ„ Ø§Ù„Ø£ÙˆÙ„Ù‰ Ø¨Ø¹Ø¯ Ø§Ù„Ø³Ø¨Ù„Ø§Ø´: ØªÙØ¹ÙŠÙ„ØŒ ØªØ³Ø¬ÙŠÙ„ Ø¯Ø®ÙˆÙ„ ØªÙ‚Ù„ÙŠØ¯ÙŠØŒ Ø£Ùˆ Ø±Ù…Ø² Ù‚Ø§Ø¦Ù…Ø© Ù…Ù† Ù„ÙˆØ­Ø© Ø§Ù„ØªØ­ÙƒÙ….
class LoginEntryScreen extends StatefulWidget {
  const LoginEntryScreen({super.key});

  @override
  State<LoginEntryScreen> createState() => _LoginEntryScreenState();
}

class _LoginEntryScreenState extends State<LoginEntryScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final GetStorage _storage = GetStorage();
  final ActivationApi _activationApi = ActivationApi();
  String _deviceId = '';
  String _activationStatus = '';
  String _activationExpiryDate = '';
  bool _activationUiEnforced = true;
  bool _isActivatingDevice = false;
  bool _activationPullInFlight = false;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _manualUsernameController =
      TextEditingController();
  final TextEditingController _manualPasswordController =
      TextEditingController();
  bool _codeVerifyLoading = false;
  bool _showTvCodeKeypad = false;
  String? _pendingHostDomainFromCode = kHardcodedStreamingServerUrl;
  Timer? _activationPoll;
  bool _autoLoginTried = false;

  /// يمنع حلقة login failed كل ثانيتين دون تعطيل دخول QR عند رابط جديد
  bool _playlistAutoLoginBlocked = false;
  String? _lastAutoDomainSeen;

  final FocusNode _languageFocusNode = FocusNode();
  final FocusNode _legalFocusNode = FocusNode();
  final FocusNode _manageAccountsFocus = FocusNode();
  final FocusNode _supportFocus = FocusNode();
  final FocusNode _activationButtonFocus = FocusNode();
  String _supportContactUrl = '';
  final FocusNode _codeFieldFocus = FocusNode();
  final FocusNode _loginRouteFocus = FocusNode();
  final FocusNode _m3uMethodFocus = FocusNode();
  final FocusNode _codeMethodFocus = FocusNode();
  final FocusNode _qrMethodFocus = FocusNode();
  final FocusNode _webMethodFocus = FocusNode();
  final FocusNode _downloadsMethodFocus = FocusNode();
  final FocusNode _manualUsernameFocus = FocusNode();
  final FocusNode _manualPasswordFocus = FocusNode();
  final FocusNode _manualLoginFocus = FocusNode();
  late final AnimationController _manualCredsShakeController;
  late final Animation<double> _manualCredsShakeOffset;
  bool _isPasswordObscured = true;
  bool _isNavigatingHome = false;
  void _togglePasswordVisibility() {
    setState(() => _isPasswordObscured = !_isPasswordObscured);
  }

  Future<void> _persistActivationToStorage(Map<String, dynamic> result) async {
    if (result['_check_failed'] == true) {
      return;
    }
    await _storage.write('activation_status', result['status'] ?? 'غير مفعل');
    final expiryDate = (result['expiry_date'] as String? ?? '').trim();
    _activationExpiryDate = expiryDate;
    await _storage.write('activation_expiry_date', expiryDate);
    final parsed = parseActivationRemaining(expiryDate);
    final lifetime =
        result['lifetime'] == true || (parsed?.isLifetime ?? false);
    await _storage.write('activation_lifetime', lifetime);
    if (result.containsKey('trial')) {
      await _storage.write(
        'activation_is_trial',
        !lifetime &&
            (result['trial'] == true ||
                result['trial'] == 1 ||
                result['trial'] == '1'),
      );
    } else if (lifetime) {
      await _storage.write('activation_is_trial', false);
    }
    final remoteAppName = result['app_name'] as String? ?? '';
    await _storage.write('app_name', kAppName);
    if (remoteAppName.trim().isNotEmpty && remoteAppName.trim() != kAppName) {
      await _storage.write('panel_app_name', remoteAppName.trim());
    }
    final supportUrl = (result['support_contact_url'] as String? ?? '').trim();
    if (supportUrl.isNotEmpty) {
      _supportContactUrl = supportUrl;
      await _storage.write('support_contact_url', supportUrl);
    }
    final activationUrl = (result['app_activation_url'] as String? ?? '')
        .trim();
    if (activationUrl.isNotEmpty) {
      await _storage.write('app_activation_url', activationUrl);
    }
    final domain = result['domain'] as String? ?? '';
    final addingAccount = _storage.read(kStorageAddingNewAccount) == true;
    final awaitQrNew = _storage.read(kStorageQrAwaitNewAccount) == true;
    final suppressAuto =
        _storage.read(kStorageSuppressPlaylistAutoLogin) == true && !awaitQrNew;
    // أثناء إضافة حساب عبر QR نحتاج حفظ playlist لاكتشاف الحساب الجديد بعد المسح
    if (!suppressAuto &&
        (!_playlistAutoLoginBlocked) &&
        (!addingAccount || awaitQrNew) &&
        domain.isNotEmpty) {
      try {
        final uri = Uri.parse(domain);
        final playlistUsername = uri.queryParameters['username'] ?? '';
        final playlistPassword = uri.queryParameters['password'] ?? '';
        final baseDomain = uri.hasScheme && uri.host.isNotEmpty
            ? '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'
            : domain;
        // get.php مع يوزر/باس → مثل الدخول اليدوي (لا نحذف الاعتمادات)
        final asManual = await persistAutoLoginAsManualXtream(_storage, domain);
        if (!asManual &&
            playlistUsername.isNotEmpty &&
            playlistPassword.isNotEmpty) {
          final cleanBase =
              parseXtreamCredentialsFromUrl(
                '$baseDomain/?username=$playlistUsername&password=$playlistPassword',
              )?.serverBase ??
              baseDomain;
          await _storage.write('activation_domain', cleanBase);
          await _storage.write('activation_auto_enabled', true);
          await _storage.write('activation_auto_username', playlistUsername);
          await _storage.write('activation_auto_password', playlistPassword);
          await _storage.write('activation_auto_domain', cleanBase);
        } else if (!asManual) {
          final playlistUrl = domain.trim();
          // سيرفر فقط بدون يوزر/باس: احفظ الدومين ولا تفعّل دخول قائمة تلقائي فارغ
          if (isXtreamHostOnlyUrl(playlistUrl)) {
            await _storage.write('activation_domain', baseDomain);
            await _storage.write('activation_auto_domain', baseDomain);
            final savedUsername =
                _storage.read('activation_auto_username') as String?;
            final savedPassword =
                _storage.read('activation_auto_password') as String?;
            if (savedUsername != null &&
                savedPassword != null &&
                savedUsername.isNotEmpty &&
                savedPassword.isNotEmpty) {
              await _storage.write('activation_auto_enabled', true);
            } else {
              await _storage.write('activation_auto_enabled', false);
              await _storage.remove('activation_auto_username');
              await _storage.remove('activation_auto_password');
            }
          } else {
            await _storage.write('activation_domain', playlistUrl);
            await _storage.write('activation_auto_domain', playlistUrl);
            final savedUsername =
                _storage.read('activation_auto_username') as String?;
            final savedPassword =
                _storage.read('activation_auto_password') as String?;
            if (savedUsername != null &&
                savedPassword != null &&
                savedUsername.isNotEmpty &&
                savedPassword.isNotEmpty) {
              await _storage.write('activation_auto_enabled', true);
              await _storage.write('activation_auto_domain', baseDomain);
              await _storage.write('activation_domain', baseDomain);
            } else {
              await _storage.write('activation_auto_enabled', true);
              await _storage.remove('activation_auto_username');
              await _storage.remove('activation_auto_password');
            }
          }
        }
      } catch (_) {
        await _storage.remove('activation_auto_enabled');
        await _storage.remove('activation_auto_username');
        await _storage.remove('activation_auto_password');
        await _storage.remove('activation_auto_domain');
      }
    } else if (!addingAccount && !suppressAuto) {
      final hasPlaylist = result['has_playlist'] == true;
      final keepLocal =
          hasPlaylist ||
          (_storage.read('activation_auto_enabled') == true &&
              ((_storage.read('activation_auto_domain') as String?) ?? '')
                  .trim()
                  .isNotEmpty);
      if (!keepLocal) {
        await _storage.remove('activation_auto_enabled');
        await _storage.remove('activation_auto_username');
        await _storage.remove('activation_auto_password');
        await _storage.remove('activation_auto_domain');
      }
    }

    // Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª Ø§Ù„Ø¥Ø¹Ù„Ø§Ù†Ø§Øª ÙˆØ§Ù„ÙˆØ§Ø¬Ù‡Ø© Ù…Ù† Ù„ÙˆØ­Ø© Ø§Ù„ØªØ­ÙƒÙ… (Ù†ÙØ³ Ù…Ù†Ø·Ù‚ Ø´Ø§Ø´Ø© Ø§Ù„ØªØ³Ø¬ÙŠÙ„)
    final adsEnabled = result['ads_enabled'] as bool? ?? true;
    final bannerHomeOnly = result['banner_home_only'] as bool? ?? true;
    final bannerAndroid = result['banner_ad_unit_android'] as String? ?? '';
    final bannerIos = result['banner_ad_unit_ios'] as String? ?? '';
    final interAndroid =
        result['interstitial_ad_unit_android'] as String? ?? '';
    final interIos = result['interstitial_ad_unit_ios'] as String? ?? '';

    if (result.containsKey('activation_enforced')) {
      await _storage.write(
        'activation_enforced',
        parseActivationEnforcedFlag(result['activation_enforced']),
      );
    }
    if (result.containsKey('block_screenshots')) {
      await _storage.write(
        'block_screenshots',
        parseActivationEnforcedFlag(result['block_screenshots']),
      );
    }
    await applyScreenshotProtection();
    await _storage.write('ads_enabled', adsEnabled);
    await _storage.write('banner_home_only', bannerHomeOnly);
    if (bannerAndroid.isNotEmpty) {
      await _storage.write('banner_ad_unit_android', bannerAndroid);
    }
    if (bannerIos.isNotEmpty) {
      await _storage.write('banner_ad_unit_ios', bannerIos);
    }
    if (interAndroid.isNotEmpty) {
      await _storage.write('interstitial_ad_unit_android', interAndroid);
    }
    if (interIos.isNotEmpty) {
      await _storage.write('interstitial_ad_unit_ios', interIos);
    }
    AdsService.persistFromPanel(result);
  }

  /// قفل الاتجاه: أفقي دائماً على كل الأجهزة (هاتف + تلفاز).
  void _applyEntryScreenOrientations() {
    if (!mounted) return;
    unawaited(lockHomeScreenLandscape());
  }

  bool _isDefinitiveActivationStatus(String status) {
    final t = status.trim();
    return t == 'نشط' || t == 'منتهي' || t == 'محظور' || t == 'غير مفعل';
  }

  bool _isCheckingUiStatus(String status) {
    final t = status.trim();
    return t == 'checking' || t == 'جاري التحقق...' || t.isEmpty;
  }

  String _activationStatusFromStorage() {
    final stored = (_storage.read('activation_status') ?? '').toString().trim();
    return _isDefinitiveActivationStatus(stored) ? stored : '';
  }

  /// فشل الشبكة / timeout: أبقِ آخر حالة حقيقية من اللوحة.
  /// لا نخترع «غير مفعل» — Inactive فقط بعد رد ناجح من الـ panel.
  String _statusAfterFailedPull() {
    final current = _activationStatus.trim();
    if (current == 'نشط' || current == 'منتهي' || current == 'محظور') {
      return current;
    }
    final stored = _activationStatusFromStorage();
    if (stored.isNotEmpty) return stored;
    return 'checking';
  }

  void _applyActivationStatusUi(String next, {required bool silent}) {
    final checkingUi = _isCheckingUiStatus(_activationStatus);
    if (!mounted) {
      _activationStatus = next;
      return;
    }
    if (!silent || next != _activationStatus || checkingUi) {
      setState(() => _activationStatus = next);
    } else {
      _activationStatus = next;
    }
  }

  Future<void> _pullActivation({required bool silent}) async {
    if (_activationPullInFlight) return;
    _activationPullInFlight = true;
    try {
      final justAddedPlaylist =
          _storage.read('activation_just_added_playlist') == true;
      final pendingLocalUrl =
          (_storage.read('activation_auto_domain') as String?)?.trim() ?? '';
      final pendingLocalUser =
          (_storage.read('activation_auto_username') as String?)?.trim() ?? '';
      final pendingLocalPass =
          (_storage.read('activation_auto_password') as String?)?.trim() ?? '';

      _deviceId = await _activationApi.getDeviceId().timeout(
        const Duration(seconds: 6),
        onTimeout: () => '',
      );
      if (_deviceId.isNotEmpty) {
        await _storage.write('device_id', _deviceId);
      }
      final raw = await _activationApi
          .checkActivation(_deviceId)
          .timeout(const Duration(seconds: 12));
      final result = Map<String, dynamic>.from(raw);
      await _persistActivationToStorage(result);

      if (justAddedPlaylist) {
        await _storage.remove('activation_just_added_playlist');
        // لا تمسح اليوزر/الباس — رابط get.php يُعامل كدخول يدوي
        if (pendingLocalUser.isNotEmpty && pendingLocalPass.isNotEmpty) {
          var domain = pendingLocalUrl;
          final fromUrl = parseXtreamCredentialsFromUrl(domain);
          if (fromUrl != null) {
            domain = fromUrl.serverBase;
          } else if (isM3uStylePlaylistUrl(domain)) {
            domain = '';
          }
          if (domain.isEmpty) {
            domain =
                (_storage.read('activation_auto_domain') as String?)?.trim() ??
                '';
            final again = parseXtreamCredentialsFromUrl(domain);
            if (again != null) domain = again.serverBase;
          }
          await _storage.write('activation_auto_enabled', true);
          await _storage.write('activation_auto_username', pendingLocalUser);
          await _storage.write('activation_auto_password', pendingLocalPass);
          if (domain.isNotEmpty && !isM3uStylePlaylistUrl(domain)) {
            await _storage.write('activation_auto_domain', domain);
            await _storage.write('activation_domain', domain);
          }
        } else if (pendingLocalUrl.isNotEmpty) {
          final asManual = await persistAutoLoginAsManualXtream(
            _storage,
            pendingLocalUrl,
          );
          if (!asManual) {
            await _storage.write('activation_auto_enabled', true);
            await _storage.write('activation_auto_domain', pendingLocalUrl);
            await _storage.write('activation_domain', pendingLocalUrl);
            await _storage.remove('activation_auto_username');
            await _storage.remove('activation_auto_password');
          }
        }
        _lastAutoDomainSeen = null;
        if (!_playlistAutoLoginBlocked) {
          _autoLoginTried = false;
        }
      }

      final st = result['status']?.toString().trim().isNotEmpty == true
          ? result['status'].toString().trim()
          : 'غير مفعل';
      final failedCheck = result['_check_failed'] == true;
      final enforced = result.containsKey('activation_enforced')
          ? parseActivationEnforcedFlag(result['activation_enforced'])
          : activationEnforcedFromStorage();
      final enforcedChanged = enforced != _activationUiEnforced;
      _activationUiEnforced = enforced;
      if (_deviceId.isNotEmpty) {
        unawaited(_activationApi.sendHeartbeat(_deviceId));
      }

      // QR: إعادة السماح بالدخول التلقائي (العلم يبقى طالما نافذة QR مفتوحة)
      final forceQrLogin = _storage.read(kStorageForceQrAutoLogin) == true;
      final awaitQrNew = _storage.read(kStorageQrAwaitNewAccount) == true;
      if (forceQrLogin || awaitQrNew) {
        _lastAutoDomainSeen = null;
        _playlistAutoLoginBlocked = false;
        _autoLoginTried = false;
      }
      final currentAutoDomain =
          (_storage.read('activation_auto_domain') as String?)?.trim();
      // بعد فشل الدخول لا تُعد المحاولة لنفس رابط اللوحة
      // وأثناء انتظار اليوزر/الباس لكود host-only لا تُعدّ تشغيل الدخول التلقائي
      if (!_playlistAutoLoginBlocked &&
          _pendingHostDomainFromCode == null &&
          currentAutoDomain != null &&
          currentAutoDomain.isNotEmpty &&
          currentAutoDomain != _lastAutoDomainSeen) {
        _lastAutoDomainSeen = currentAutoDomain;
        _autoLoginTried = false;
      }

      if (failedCheck) {
        // خطأ مؤقت من اللوحة: لا تُظهر Inactive نهائي، ولا تُسقط نشط/تجربة.
        _applyActivationStatusUi(_statusAfterFailedPull(), silent: silent);
      } else if (enforcedChanged ||
          !silent ||
          st != _activationStatus ||
          _isCheckingUiStatus(_activationStatus)) {
        // Inactive / نشط / منتهي / محظور فقط من رد ناجح (_check_failed != true).
        _applyActivationStatusUi(st, silent: silent);
      } else {
        _activationStatus = st;
      }

      bool blockedByVpn = false;
      if (st == 'نشط' && result['block_vpn'] == true) {
        try {
          blockedByVpn = await VpnConnectionDetector.isVpnActive();
        } catch (_) {}
      }

      final waitingQr = forceQrLogin || awaitQrNew;
      // محظور / منتهي: ممنوع الدخول التلقائي حتى أثناء انتظار QR.
      final allowAuto =
          st != 'محظور' &&
          st != 'منتهي' &&
          (waitingQr
              ? true
              : (canAttemptPlaylistAutoLogin(st) &&
                  (st == 'نشط' || !activationEnforcedFromStorage())));
      if (allowAuto && !blockedByVpn) {
        await _autoLoginIfPossible();
      } else if (blockedByVpn && !silent) {
        if (!mounted) return;
        await showBlockDialog(
          context,
          title: 'not_allowed'.tr,
          message: 'vpn_not_allowed'.tr,
          appName: null,
        );
      }
    } catch (_) {
      // شبكة/timeout: حافظ على نشط/تجربة المخزّنة — بلا Inactive مخترع.
      _applyActivationStatusUi(_statusAfterFailedPull(), silent: silent);
    } finally {
      _activationPullInFlight = false;
    }
  }

  Future<void> _autoLoginIfPossible() async {
    if (_autoLoginTried || _isNavigatingHome || _playlistAutoLoginBlocked) {
      return;
    }
    // شاشة إدخال اليوزر/الباس مفتوحة: لا تُنشئ AuthRegister ثاني بدون displayName
    final route = Get.currentRoute;
    if (route == screenRegister) return;
    // أثناء انتظار اليوزر/الباس لكود host-only: لا تدخل تلقائياً كقائمة فارغة
    if (_pendingHostDomainFromCode != null) return;
    if (!shouldAllowPlaylistAutoLogin()) return;
    final waitingQr =
        _storage.read(kStorageForceQrAutoLogin) == true ||
        _storage.read(kStorageQrAwaitNewAccount) == true;
    if (_activationStatus == 'محظور' || _activationStatus == 'منتهي') {
      return;
    }
    if (!waitingQr && !canAttemptPlaylistAutoLogin(_activationStatus)) {
      return;
    }

    final enabled = _storage.read('activation_auto_enabled') == true;
    if (!enabled) return;

    var savedUsername = (_storage.read('activation_auto_username') as String?)
        ?.trim();
    var savedPassword = (_storage.read('activation_auto_password') as String?)
        ?.trim();
    var savedDomain = (_storage.read('activation_auto_domain') as String?)
        ?.trim();

    // إن وُجد رابط get.php كاملاً: استخرج الخانات كدخول يدوي
    final fromUrl = parseXtreamCredentialsFromUrl(savedDomain ?? '');
    if (fromUrl != null) {
      savedUsername = fromUrl.username;
      savedPassword = fromUrl.password;
      savedDomain = fromUrl.serverBase;
      await _storage.write('activation_auto_enabled', true);
      await _storage.write('activation_auto_username', fromUrl.username);
      await _storage.write('activation_auto_password', fromUrl.password);
      await _storage.write('activation_auto_domain', fromUrl.serverBase);
      await _storage.write('activation_domain', fromUrl.serverBase);
    }

    // أولوية: دخول يدوي (AuthRegister) مثل إدخال اليوزر/الباس يدوياً
    if (savedUsername != null &&
        savedPassword != null &&
        savedUsername.isNotEmpty &&
        savedPassword.isNotEmpty) {
      if (_deviceId.isEmpty) {
        _deviceId = await _activationApi.getDeviceId();
      }
      final domain = (savedDomain != null && savedDomain.isNotEmpty)
          ? savedDomain
          : (_storage.read('activation_domain') as String? ?? '');
      final bindRes = await _activationApi.bindAccountToDevice(
        deviceId: _deviceId,
        username: savedUsername,
        password: savedPassword,
        serverHost: domain,
      );
      if (!mounted) return;
      final okBind = bindRes['success'] == true;
      final msg = (bindRes['message'] as String?) ?? '';
      if (!okBind && msg.contains('Max devices')) {
        _playlistAutoLoginBlocked = true;
        _autoLoginTried = true;
        signalDeviceQrLinkFailed();
        showWarningToast(
          context,
          'max_devices_reached_title'.tr,
          'max_devices_reached_msg'.trParams({
            'max': '${bindRes['max_devices'] ?? 1}',
          }),
        );
        return;
      }
      _autoLoginTried = true;
      await signalDeviceQrLinkSuccess();
      await _storage.remove(kStorageForceQrAutoLogin);
      clearQrAwaitNewAccountFlags();
      if (Get.isDialogOpen == true) Get.back();
      if (!mounted) return;
      context.read<AuthBloc>().add(
        AuthRegister(savedUsername, savedPassword, domain),
      );
    } else if (savedDomain != null && savedDomain.isNotEmpty) {
      // سيرفر فقط بدون اعتمادات ≠ قائمة M3U — انتظر إدخال اليوزر/الباس
      if (isXtreamHostOnlyUrl(savedDomain)) {
        final base = xtreamServerBaseFromUrl(savedDomain) ?? savedDomain;
        if (_pendingHostDomainFromCode == null && mounted) {
          setState(() => _pendingHostDomainFromCode = base);
        }
        return;
      }
      _autoLoginTried = true;
      await signalDeviceQrLinkSuccess();
      await _storage.remove(kStorageForceQrAutoLogin);
      clearQrAwaitNewAccountFlags();
      if (Get.isDialogOpen == true) Get.back();
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthUsePlaylist(savedDomain));
    }
  }

  Future<void> _activateDeviceFromApp() async {
    if (_isActivatingDevice) return;
    try {
      setState(() => _isActivatingDevice = true);
      if (_deviceId.isEmpty) {
        _deviceId = await _activationApi.getDeviceId();
      }
      final id = _deviceId.trim();
      if (id.isNotEmpty) {
        await _storage.write('device_id', id);
      }
      final opened = await openAppActivationPage(deviceId: id);
      if (!mounted) return;
      if (!opened) {
        showWarningToast(
          context,
          'notice_title'.tr,
          'activation_page_not_configured'.tr,
        );
      }
    } finally {
      if (mounted) setState(() => _isActivatingDevice = false);
    }
  }

  Future<void> _tryNavigateHome(AuthSuccess state) async {
    if (!mounted) return;
    final user = state.user;
    final serverUrl = (user.serverInfo?.serverUrl ?? '').trim();
    final username = (user.userInfo?.username ?? '').trim();
    final password = (user.userInfo?.password ?? '').trim();
    final hasCreds = username.isNotEmpty && password.isNotEmpty;
    final hasPlaylist = serverUrl.isNotEmpty && !hasCreds;
    if (!hasCreds && !hasPlaylist) return;
    if (shouldBlockExpiredIptvSession(
      expDate: user.userInfo?.expDate,
      status: user.userInfo?.status,
      username: username,
      password: password,
    )) {
      await _storage.write(kStorageIptvServerExpiredKick, true);
      await _storage.write(kStorageSuppressPlaylistAutoLogin, true);
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthClearSession());
      if (mounted) showIptvServerExpiredToast(context);
      return;
    }
    if (isActivationLoginDenied(_activationStatus)) {
      final alreadyNotified =
          _storage.read('activation_kick_notified') == true;
      if (alreadyNotified) {
        await _storage.remove('activation_kick_notified');
      } else {
        showActivationLoginDeniedToast(context, _activationStatus);
      }
      return;
    }
    if (canPassActivationGate(
      status: _activationStatus,
      hasPlaylist: hasPlaylist,
    )) {
      _isNavigatingHome = true;
      await _storage.remove(kStorageAddingNewAccount);
      if (!mounted) return;
      context.read<SettingsCubit>().updateStatusAccount(false);
      await AppCacheClearer.prepareNewServerSession(context);
      if (!mounted) return;
      await navigateToHomeBootstrap();
    } else if (activationEnforcedFromStorage() &&
        _activationStatus.trim() != 'نشط') {
      showWarningToast(
        context,
        'app_not_activated'.tr,
        'please_activate_first'.tr,
      );
    }
  }

  Future<void> _verifyAccessCode() async {
    _codeFieldFocus.unfocus();
    if (_showTvCodeKeypad) {
      _closeTvCodeKeypad();
    }
    final raw = _codeController.text.trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits == kDemoAccessCode) {
      if (showActivationLoginDeniedToast(context, _activationStatus)) {
        return;
      }
      await _storage.remove(kStorageAddingNewAccount);
      if (!mounted) return;
      context.read<SettingsCubit>().updateStatusAccount(true);
      await navigateToHomeBootstrap();
      return;
    }
    // منع محاولة الدخول أصلاً إن كان التفعيل منتهياً أو الجهاز محظوراً
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    if (digits.length < 5 || digits.length > 6) {
      showWarningToast(
        context,
        'notice_title'.tr,
        'access_code_invalid_len'.tr,
      );
      return;
    }
    setState(() => _codeVerifyLoading = true);
    final res = await _activationApi.redeemPlaylistCode(digits);
    if (!mounted) return;
    setState(() => _codeVerifyLoading = false);
    if (res.ok && (res.m3uUrl ?? '').isNotEmpty) {
      // إعادة التحقق بعد الاسترداد (قد تتغيّر الحالة من اللوحة)
      if (showActivationLoginDeniedToast(context, _activationStatus)) {
        return;
      }
      final resolved = res.m3uUrl!.trim();
      final uri = Uri.tryParse(resolved);
      final u = uri != null
          ? (uriQueryParamIgnoreCase(uri, 'username') ?? '')
          : '';
      final p = uri != null
          ? (uriQueryParamIgnoreCase(uri, 'password') ?? '')
          : '';
      final hasQueryCreds = u.isNotEmpty && p.isNotEmpty;
      final isHostOnly = isXtreamHostOnlyUrl(resolved);

      if (hasQueryCreds) {
        final creds = parseXtreamCredentialsFromUrl(resolved)!;
        setState(() {
          _pendingHostDomainFromCode = null;
          _manualUsernameController.clear();
          _manualPasswordController.clear();
        });
        await persistAutoLoginAsManualXtream(_storage, resolved);
        if (!mounted) return;
        context.read<AuthBloc>().add(
          AuthRegister(
            creds.username,
            creds.password,
            creds.serverBase,
            loginMethod: 'playlist_code',
            serverHostForPanel: creds.serverBase,
          ),
        );
        return;
      }

      // كود يحتوي على السيرفر فقط (مثل http://host:port) بدون يوزر/باس:
      // أظهر حقول الإدخال اليدوي على نفس الشاشة — ولا تدخل كقائمة فارغة.
      if (isHostOnly) {
        final base = xtreamServerBaseFromUrl(resolved) ?? resolved;
        setState(() {
          _pendingHostDomainFromCode = base;
          _showTvCodeKeypad = false;
        });
        // امنع الدخول التلقائي من الـ poll بعد كتابة custom_domain في اللوحة
        _autoLoginTried = true;
        await _storage.write('activation_domain', base);
        await _storage.write('activation_auto_domain', base);
        await _storage.write('activation_auto_enabled', false);
        await _storage.remove('activation_auto_username');
        await _storage.remove('activation_auto_password');
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _manualUsernameFocus.requestFocus();
        });
        return;
      }

      setState(() {
        _pendingHostDomainFromCode = null;
        _manualUsernameController.clear();
        _manualPasswordController.clear();
      });
      context.read<AuthBloc>().add(AuthUsePlaylist(resolved));
    } else {
      final key = res.messageKey ?? 'access_code_not_found';
      showWarningToast(context, 'notice_title'.tr, key.tr);
    }
  }

  // ---------------- TV Access Code (in-app keypad) ----------------
  void _tvAppendDigit(int digit) {
    if (digit < 0 || digit > 9) return;
    final current = _codeController.text;
    if (current.length >= 6) return;
    final next = '$current$digit';
    _codeController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  void _tvBackspace() {
    final current = _codeController.text;
    if (current.isEmpty) return;
    final next = current.substring(0, current.length - 1);
    _codeController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  void _openTvCodeKeypad() {
    if (!mounted) return;
    setState(() => _showTvCodeKeypad = true);
  }

  void _closeTvCodeKeypad() {
    if (!mounted) return;
    setState(() => _showTvCodeKeypad = false);
  }

  bool _tvNodeFocusable(FocusNode node) {
    return node.context != null && node.canRequestFocus;
  }

  void _tvRequestFocus(FocusNode node) {
    if (!_tvNodeFocusable(node)) return;
    // بدون setState — إعادة البناء كانت تقطع primary focus وتخلي OK يموت أحياناً.
    node.requestFocus();
  }

  /// صف الأزرار العلوي: Legal ← Language ← Manage ← Support
  FocusNode _tvPreferredTopChipFocus() {
    if (_tvNodeFocusable(_manageAccountsFocus)) return _manageAccountsFocus;
    if (_tvNodeFocusable(_languageFocusNode)) return _languageFocusNode;
    if (_tvNodeFocusable(_legalFocusNode)) return _legalFocusNode;
    if (_tvNodeFocusable(_supportFocus)) return _supportFocus;
    return _languageFocusNode;
  }

  /// العنصر فوق منطقة النموذج (كود / يوزر).
  FocusNode _tvFocusAboveCodeField() {
    if (_tvNodeFocusable(_codeMethodFocus)) return _codeMethodFocus;
    if (_pendingHostDomainFromCode == null &&
        showUsernameLogin &&
        _tvNodeFocusable(_loginRouteFocus)) {
      return _loginRouteFocus;
    }
    if (_activationUiEnforced && _tvNodeFocusable(_activationButtonFocus)) {
      return _activationButtonFocus;
    }
    return _tvPreferredTopChipFocus();
  }

  /// أول عنصر قابل للتركيز في النموذج تحت الشريط العلوي.
  FocusNode _tvFocusFirstFormNode() {
    if (_pendingHostDomainFromCode != null &&
        _tvNodeFocusable(_manualUsernameFocus)) {
      return _manualUsernameFocus;
    }
    if (_pendingHostDomainFromCode == null &&
        showUsernameLogin &&
        _tvNodeFocusable(_loginRouteFocus)) {
      return _loginRouteFocus;
    }
    if (_tvNodeFocusable(_m3uMethodFocus)) return _m3uMethodFocus;
    if (_tvNodeFocusable(_codeMethodFocus)) return _codeMethodFocus;
    if (_tvNodeFocusable(_qrMethodFocus)) return _qrMethodFocus;
    if (_tvNodeFocusable(_codeFieldFocus)) return _codeFieldFocus;
    return _languageFocusNode;
  }

  /// تنقل ريموت لصف الأزرار العلوي (يُستدعى من _LoginFocusShell.onKeyEvent).
  KeyEventResult _tvTopChipKeyEvent(
    KeyEvent event, {
    FocusNode? left,
    FocusNode? right,
    required VoidCallback onTap,
  }) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // في RTL الأسهم تُعكس لتطابق الاتجاه البصري
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final toLeft = rtl ? right : left;
    final toRight = rtl ? left : right;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (toLeft != null && _tvNodeFocusable(toLeft)) {
        _tvRequestFocus(toLeft);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (toRight != null && _tvNodeFocusable(toRight)) {
        _tvRequestFocus(toRight);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final next = _tvFocusFirstFormNode();
      if (!identical(next, _languageFocusNode) && _tvNodeFocusable(next)) {
        _tvRequestFocus(next);
      } else if (showUsernameLogin && _tvNodeFocusable(_loginRouteFocus)) {
        _tvRequestFocus(_loginRouteFocus);
      } else if (_tvNodeFocusable(_m3uMethodFocus)) {
        _tvRequestFocus(_m3uMethodFocus);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return settingsTvActivateOnSelect(event, onTap);
  }

  KeyEventResult _tvActivationKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return settingsTvActivateOnSelect(event, _activateDeviceFromApp);
    }
    final key = event.logicalKey;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _tvRequestFocus(rtl ? _languageFocusNode : _legalFocusNode);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _tvRequestFocus(rtl ? _legalFocusNode : _languageFocusNode);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final next = _tvFocusFirstFormNode();
      if (!identical(next, _languageFocusNode) && _tvNodeFocusable(next)) {
        _tvRequestFocus(next);
      } else if (showUsernameLogin && _tvNodeFocusable(_loginRouteFocus)) {
        _tvRequestFocus(_loginRouteFocus);
      } else if (_tvNodeFocusable(_m3uMethodFocus)) {
        _tvRequestFocus(_m3uMethodFocus);
      }
      return KeyEventResult.handled;
    }
    return settingsTvActivateOnSelect(event, _activateDeviceFromApp);
  }

  KeyEventResult _tvLoginRouteKeyEvent(FocusNode node, KeyEvent event) {
    return _tvMethodCardKeyEvent(
      node,
      event,
      onTap: _openCredentialsLogin,
      right: _m3uMethodFocus,
      down: _codeMethodFocus,
    );
  }

  KeyEventResult _tvM3uMethodKeyEvent(FocusNode node, KeyEvent event) {
    return _tvMethodCardKeyEvent(
      node,
      event,
      onTap: _openM3uLogin,
      left: showUsernameLogin ? _loginRouteFocus : null,
      down: _qrMethodFocus,
    );
  }

  KeyEventResult _tvCodeMethodKeyEvent(FocusNode node, KeyEvent event) {
    return _tvMethodCardKeyEvent(
      node,
      event,
      onTap: _openPlaylistCodeEntry,
      up: showUsernameLogin ? _loginRouteFocus : _m3uMethodFocus,
      right: _qrMethodFocus,
      down: _webMethodFocus,
    );
  }

  KeyEventResult _tvQrMethodKeyEvent(FocusNode node, KeyEvent event) {
    return _tvMethodCardKeyEvent(
      node,
      event,
      onTap: () {
        unawaited(_openDeviceQrFromEntry());
      },
      left: _codeMethodFocus,
      up: _m3uMethodFocus,
      down: _downloadsMethodFocus,
    );
  }

  KeyEventResult _tvWebMethodKeyEvent(FocusNode node, KeyEvent event) {
    return _tvMethodCardKeyEvent(
      node,
      event,
      onTap: () {
        unawaited(_openWebPlaylistsFromEntry());
      },
      up: _codeMethodFocus,
      right: _downloadsMethodFocus,
    );
  }

  KeyEventResult _tvDownloadsMethodKeyEvent(FocusNode node, KeyEvent event) {
    return _tvMethodCardKeyEvent(
      node,
      event,
      onTap: () {
        Get.toNamed(screenDownloads);
      },
      up: _qrMethodFocus,
      left: _webMethodFocus,
    );
  }

  KeyEventResult _tvMethodCardKeyEvent(
    FocusNode node,
    KeyEvent event, {
    required VoidCallback onTap,
    FocusNode? left,
    FocusNode? right,
    FocusNode? up,
    FocusNode? down,
  }) {
    if (event is! KeyDownEvent) {
      return settingsTvActivateOnSelect(event, onTap);
    }
    final key = event.logicalKey;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final toLeft = rtl ? right : left;
    final toRight = rtl ? left : right;
    if (key == LogicalKeyboardKey.arrowLeft &&
        toLeft != null &&
        _tvNodeFocusable(toLeft)) {
      _tvRequestFocus(toLeft);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        toRight != null &&
        _tvNodeFocusable(toRight)) {
      _tvRequestFocus(toRight);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (up != null && _tvNodeFocusable(up)) {
        _tvRequestFocus(up);
      } else if (_activationUiEnforced &&
          _tvNodeFocusable(_activationButtonFocus)) {
        _tvRequestFocus(_activationButtonFocus);
      } else {
        _tvRequestFocus(_tvPreferredTopChipFocus());
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (down != null && _tvNodeFocusable(down)) {
        _tvRequestFocus(down);
        return KeyEventResult.handled;
      }
    }
    return settingsTvActivateOnSelect(event, onTap);
  }

  KeyEventResult _tvManualLoginKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return settingsTvActivateOnSelect(event, _submitManualCredsAfterCode);
    }
    if (!isTv(context) || _pendingHostDomainFromCode == null) {
      return settingsTvActivateOnSelect(event, _submitManualCredsAfterCode);
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _tvRequestFocus(_manualPasswordFocus);
      return KeyEventResult.handled;
    }
    return settingsTvActivateOnSelect(event, _submitManualCredsAfterCode);
  }

  void _setupTvFocusTree() {
    // حقول النص + أزرار النموذج: FocusNode.onKeyEvent يعمل معها بشكل موثوق
    _manualUsernameFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (!isTv(context)) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        _tvRequestFocus(_manualPasswordFocus);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _tvRequestFocus(_codeFieldFocus);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    _manualPasswordFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (!isTv(context)) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _tvRequestFocus(_manualUsernameFocus);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _tvRequestFocus(_manualLoginFocus);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    _codeFieldFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (!isTv(context)) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.numpadEnter) {
        _openTvCodeKeypad();
        return KeyEventResult.handled;
      }
      if (_showTvCodeKeypad) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.arrowDown) {
        if (_pendingHostDomainFromCode != null) {
          _tvRequestFocus(_manualUsernameFocus);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        // شجرة: كود → (زر يوزر إن وُجد) / تفعيل / أزرار الأعلى
        _tvRequestFocus(_tvFocusAboveCodeField());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  /// بعد إغلاق لوحة الأرقام بزر «أعلى»: التركيز مباشرة على خانة الكود.
  void _tvFocusExitKeypadUpward() {
    _closeTvCodeKeypad();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _codeFieldFocus.requestFocus();
      setState(() {});
    });
  }

  Future<void> _submitManualCredsAfterCode() async {
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    final domain = _pendingHostDomainFromCode?.trim() ?? '';
    final username = _manualUsernameController.text.trim();
    final password = _manualPasswordController.text.trim();
    if (domain.isEmpty) return;
    if (username.isEmpty || password.isEmpty) {
      _manualCredsShakeController
        ..stop()
        ..forward(from: 0);
      showWarningToast(context, 'notice_title'.tr, 'check_credentials'.tr);
      return;
    }
    if (_deviceId.isEmpty) {
      _deviceId = await _activationApi.getDeviceId();
    }
    final bindRes = await _activationApi.bindAccountToDevice(
      deviceId: _deviceId,
      username: username,
      password: password,
      serverHost: domain,
    );
    if (!mounted) return;
    final okBind = bindRes['success'] == true;
    final msg = (bindRes['message'] as String?) ?? '';
    if (!okBind && msg.contains('Max devices')) {
      showWarningToast(
        context,
        'max_devices_reached_title'.tr,
        'max_devices_reached_msg'.trParams({
          'max': '${bindRes['max_devices'] ?? 1}',
        }),
      );
      return;
    }
    if (!mounted) return;
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    // احفظ الاعتمادات للدخول التلقائي لاحقاً — الدخول عبر player_api مثل اليدوي
    await _storage.write('activation_auto_enabled', true);
    await _storage.write('activation_auto_username', username);
    await _storage.write('activation_auto_password', password);
    await _storage.write('activation_auto_domain', domain);
    await _storage.write('activation_domain', domain);
    await _storage.write(kStorageLoginMethod, 'username_password');
    _playlistAutoLoginBlocked = false;
    if (!mounted) return;
    context.read<AuthBloc>().add(AuthRegister(username, password, domain));
  }

  void _showEntryExitConfirm() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => AppExitConfirmDialog(
        onExit: () {
          Navigator.of(ctx).pop();
          SystemNavigator.pop();
        },
        onStay: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  void _openCredentialsLogin() {
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
      Get.toNamed(screenRegister);
  }

  void _openM3uLogin() {
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    Get.toNamed(screenAddPlaylist);
  }

  Future<void> _openWebPlaylistsFromEntry() async {
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    var id = _deviceId.trim();
    if (id.isEmpty) {
      id = await _activationApi.getDeviceId();
      _deviceId = id;
    }
    if (!mounted) return;
    final opened = await openAppActivationPage(deviceId: id);
    if (!mounted) return;
    if (!opened) {
      showWarningToast(
        context,
        'notice_title'.tr,
        'activation_page_not_configured'.tr,
      );
    }
  }

  void _openPlaylistCodeEntry() {
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    Get.toNamed(screenPlaylistCode);
  }

  Future<void> _openDeviceQrFromEntry() async {
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    if (_deviceId.isEmpty) {
      _deviceId = await _activationApi.getDeviceId();
    }
    if (!mounted || _deviceId.isEmpty) return;
    _showDeviceQrDialog(
      deviceId: _deviceId,
      onPoll: () => _pullActivation(silent: true),
    );
  }

  void _showLanguageDialog() {
    final currentLang = currentAppLanguageCode();
    final tv = isTv(context);
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 24,
          ),
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: kColorPrimary.withValues(alpha: 0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 40),
                        Expanded(
                          child: Text(
                            'language'.tr,
                            style: Get.textTheme.titleMedium!.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: _LoginFocusShell(
                            borderRadius: 999,
                            onTap: () => Navigator.of(ctx).pop(),
                            child: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.06),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                              ),
                              child: Icon(
                                LucideIcons.x,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: kAppUiLanguages.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final lang = kAppUiLanguages[index];
                          return FocusTraversalOrder(
                            order: NumericFocusOrder(2.0 + index),
                            child: _EntryLanguageOption(
                              code: lang.code,
                              label: lang.nativeName,
                              selected: currentLang == lang.code,
                              autofocus: tv && index == 0,
                              onTap: () {
                                if (currentLang == lang.code) {
                                  Navigator.of(ctx).pop();
                                  return;
                                }
                                setAppLocale(lang.code);
                                Navigator.of(ctx).pop();
                                if (mounted) setState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openManageAccounts() {
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    Get.toNamed(screenManageAccounts, arguments: const {'fromEntry': true});
  }

  Future<void> _openSupportContact() async {
    var link = _supportContactUrl.trim();
    if (link.isEmpty) {
      link = (_storage.read('support_contact_url') ?? '').toString().trim();
    }
    if (link.isEmpty) {
      showWarningToast(context, 'notice_title'.tr, 'contact_not_configured'.tr);
      return;
    }
    if (!link.contains('://')) {
      link = 'https://$link';
    }
    final uri = Uri.tryParse(link);
    if (uri == null || uri.host.isEmpty) {
      showWarningToast(context, 'notice_title'.tr, 'contact_not_configured'.tr);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openLegalMenu() {
    showLoginLegalMenuDialog(context, returnFocus: _legalFocusNode);
  }

  @override
  void initState() {
    super.initState();
    _manualCredsShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _manualCredsShakeOffset =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 10, end: -7), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -7, end: 7), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 7, end: 0), weight: 2),
        ]).animate(
          CurvedAnimation(
            parent: _manualCredsShakeController,
            curve: Curves.easeOut,
          ),
        );
    _setupTvFocusTree();
    WidgetsBinding.instance.addObserver(this);
    // السبلاش غالباً فحصت التفعيل مسبقاً — اعرض الحالة المخزّنة فوراً (بما فيها غير مفعل).
    final storedAtOpen = _activationStatusFromStorage();
    _activationStatus =
        storedAtOpen.isNotEmpty ? storedAtOpen : 'checking';
    _activationExpiryDate = (_storage.read('activation_expiry_date') ?? '')
        .toString();
    _supportContactUrl = (_storage.read('support_contact_url') ?? '')
        .toString()
        .trim();
    _activationUiEnforced = activationEnforcedFromStorage();
    final addingAccount = _storage.read(kStorageAddingNewAccount) == true;
    if (addingAccount) {
      _codeController.clear();
      _manualUsernameController.clear();
      _manualPasswordController.clear();
      _pendingHostDomainFromCode = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // التحديث فوراً مع أول رسم لـ login_entry — قبل TV sync / سحب التفعيل.
      final authStateEarly = context.read<AuthBloc>().state;
      if (authStateEarly is! AuthSuccess || addingAccount) {
        AppUpdateService.instance.scheduleCheckForLoginEntry(context);
      }
      if (!await RuntimeSeal.denyBrokenSession()) return;
      if (!mounted) return;
      await syncAndPersistTvDeviceFlag(context);
      if (!mounted) return;
      _applyEntryScreenOrientations();
      if (_storage.read(kStorageIptvServerExpiredKick) == true) {
        await _storage.remove(kStorageIptvServerExpiredKick);
        if (mounted) showIptvServerExpiredToast(context);
      }
      // إن كانت السبلاش حفظت الحالة: حدّث بصمت بدون وميض Checking.
      await _pullActivation(silent: storedAtOpen.isNotEmpty);
      if (!mounted) return;
      if (isTv(context)) {
        final showActivationAction =
            _activationUiEnforced &&
            (_activationStatus.trim() != 'نشط' ||
                shouldOfferActivationRenewal(_activationExpiryDate));
        if (showActivationAction && _tvNodeFocusable(_activationButtonFocus)) {
          _activationButtonFocus.requestFocus();
        } else {
          _tvRequestFocus(_tvPreferredTopChipFocus());
        }
      }
      if (!mounted) return;
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthSuccess && !addingAccount) {
        _tryNavigateHome(authState);
      }
      final pollSec = 2;
      _activationPoll?.cancel();
      _activationPoll = Timer.periodic(Duration(seconds: pollSec), (_) {
        if (!mounted || _isNavigatingHome) return;
        _pullActivation(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _activationPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _manualCredsShakeController.dispose();
    _codeController.dispose();
    _manualUsernameController.dispose();
    _manualPasswordController.dispose();
    _languageFocusNode.dispose();
    _legalFocusNode.dispose();
    _manageAccountsFocus.dispose();
    _supportFocus.dispose();
    _activationButtonFocus.dispose();
    _codeFieldFocus.dispose();
    _loginRouteFocus.dispose();
    _m3uMethodFocus.dispose();
    _codeMethodFocus.dispose();
    _qrMethodFocus.dispose();
    _webMethodFocus.dispose();
    _downloadsMethodFocus.dispose();
    _manualUsernameFocus.dispose();
    _manualPasswordFocus.dispose();
    _manualLoginFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // `didChangeMetrics` ÙŠØªÙ… Ø§Ø³ØªØ¯Ø¹Ø§Ø¤Ù‡ Ø£ÙŠØ¶Ø§Ù‹ Ø¹Ù†Ø¯ ÙØªØ­ Ù„ÙˆØ­Ø© Ø§Ù„Ù…ÙØ§ØªÙŠØ­ (keyboard).
    // ØªØ¬Ù†Ù‘Ø¨ Ø¥Ø¹Ø§Ø¯Ø© Ø¶Ø¨Ø· Ø§Ù„Ø§ØªØ¬Ø§Ù‡ Ø£Ø«Ù†Ø§Ø¡ ØªÙØ§Ø¹Ù„ Ø§Ù„Ù€ keyboard Ø­ØªÙ‰ Ù„Ø§ Ù†ÙÙ‚Ø¯ focus Ø¹Ù„Ù‰ Ø¨Ø¹Ø¶ Ø§Ù„Ø£Ø¬Ù‡Ø²Ø©.
    if (!mounted) return;
    if (_isNavigatingHome) return;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardOpen) return;
    _applyEntryScreenOrientations();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isNavigatingHome) return;
      _applyEntryScreenOrientations();
      unawaited(_pullActivation(silent: true));
    }
  }

  /// ارتفاع تقريبي للوحة الأرقام + هامش سفلي (لا نستخدم padding على الجذر حتى لا تبقى فراغات سوداء تحت اللوحة).
  static const double _tvKeypadReserveHeight = 272;

  @override
  Widget build(BuildContext context) => buildPremiumLoginUi(context);
}

class _TvAccessCodeKeypad extends StatefulWidget {
  const _TvAccessCodeKeypad({
    required this.visible,
    required this.codeLength,
    required this.onDigit,
    required this.onBackspace,
    required this.onOk,
    required this.onExitUp,
  });

  final bool visible;
  final int codeLength;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onOk;
  final VoidCallback onExitUp;

  @override
  State<_TvAccessCodeKeypad> createState() => _TvAccessCodeKeypadState();
}

class _TvAccessCodeKeypadState extends State<_TvAccessCodeKeypad> {
  // order:
  // 0..8 digits 1..9, 9 backspace, 10 digit 0, 11 ok
  final List<FocusNode> _focusNodes = List<FocusNode>.generate(
    12,
    (_) => FocusNode(),
    growable: false,
  );

  int _focusedIndex = 0;

  bool get _isCodeFull => widget.codeLength >= 6;
  bool get _isOkEnabled => widget.onOk != null && widget.codeLength >= 5;

  void _requestInitialFocus() {
    if (!mounted || !widget.visible) return;
    setState(() => _focusedIndex = 0);
    _focusNodes[0].requestFocus();
  }

  @override
  void initState() {
    super.initState();

    for (var i = 0; i < _focusNodes.length; i++) {
      _focusNodes[i].onKeyEvent = (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        bool requestMoveTo(int target) {
          if (target < 0 || target >= _focusNodes.length) {
            return false;
          }
          if (_focusedIndex == target) return true;
          setState(() => _focusedIndex = target);
          _focusNodes[target].requestFocus();
          return true;
        }

        if (key == LogicalKeyboardKey.arrowUp) {
          final row = i <= 8 ? (i ~/ 3) : 3;
          final col = i <= 8 ? (i % 3) : (i - 9);
          if (row <= 0) {
            widget.onExitUp();
            return KeyEventResult.handled;
          }
          final newRow = row - 1;
          final newCol = col;
          final target = (newRow < 3)
              ? (newRow * 3 + newCol)
              : (newCol == 0 ? 9 : (newCol == 1 ? 10 : 11));
          return requestMoveTo(target)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.arrowDown) {
          final row = i <= 8 ? (i ~/ 3) : 3;
          final col = i <= 8 ? (i % 3) : (i - 9);
          if (row >= 3) return KeyEventResult.handled;
          final newRow = row + 1;
          final newCol = col;
          final target = (newRow < 3)
              ? (newRow * 3 + newCol)
              : (newCol == 0 ? 9 : (newCol == 1 ? 10 : 11));
          return requestMoveTo(target)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.arrowLeft) {
          final row = i <= 8 ? (i ~/ 3) : 3;
          final col = i <= 8 ? (i % 3) : (i - 9);
          final newCol = col - 1;
          if (newCol < 0) return KeyEventResult.handled;
          final newRow = row;
          final target = (newRow < 3)
              ? (newRow * 3 + newCol)
              : (newCol == 0 ? 9 : (newCol == 1 ? 10 : 11));
          return requestMoveTo(target)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.arrowRight) {
          final row = i <= 8 ? (i ~/ 3) : 3;
          final col = i <= 8 ? (i % 3) : (i - 9);
          final newCol = col + 1;
          if (newCol > 2) return KeyEventResult.handled;
          final newRow = row;
          final target = (newRow < 3)
              ? (newRow * 3 + newCol)
              : (newCol == 0 ? 9 : (newCol == 1 ? 10 : 11));
          return requestMoveTo(target)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.numpadEnter) {
          switch (i) {
            case 0:
            case 1:
            case 2:
            case 3:
            case 4:
            case 5:
            case 6:
            case 7:
            case 8:
              widget.onDigit(i + 1);
              return KeyEventResult.handled;
            case 9:
              widget.onBackspace();
              return KeyEventResult.handled;
            case 10:
              if (!_isCodeFull) widget.onDigit(0);
              return KeyEventResult.handled;
            case 11:
              if (_isOkEnabled) widget.onOk?.call();
              return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      };
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _requestInitialFocus());
  }

  @override
  void didUpdateWidget(covariant _TvAccessCodeKeypad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.visible && widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _requestInitialFocus(),
      );
    }
  }

  @override
  void dispose() {
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Widget _buildButton({
    required int index,
    required Widget child,
    required bool enabled,
    required VoidCallback? onPressed,
    bool successBlackFill = false,
  }) {
    final isFocused = _focusedIndex == index;
    final Color fillColor;
    final Color borderColor;
    final double borderWidth;
    if (successBlackFill && enabled) {
      fillColor = isFocused ? Colors.black87 : Colors.black;
      borderColor = isFocused
          ? kColorPrimary.withValues(alpha: 0.95)
          : const Color(0xFF2E7D32).withValues(alpha: 0.85);
      borderWidth = isFocused ? 2 : 1.5;
    } else {
      fillColor = isFocused
          ? kColorPrimary.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.06);
      borderColor = isFocused
          ? kColorPrimary.withValues(alpha: 0.95)
          : Colors.white.withValues(alpha: 0.18);
      borderWidth = isFocused ? 2 : 1;
    }
    return Focus(
      focusNode: _focusNodes[index],
      onFocusChange: (v) {
        if (!mounted) return;
        if (v) setState(() => _focusedIndex = index);
      },
      child: SizedBox(
        height: 56,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: fillColor,
                border: Border.all(color: borderColor, width: borderWidth),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final digitTextStyle = Get.textTheme.titleLarge!.copyWith(
      color: Colors.black87,
      fontWeight: FontWeight.w800,
      fontSize: 22,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 2),
        for (final List<int> row in [
          const [1, 2, 3],
          const [4, 5, 6],
          const [7, 8, 9],
        ])
          Row(
            children: List.generate(row.length, (col) {
              final int digit = row[col];
              final int index = digit - 1; // 1..9 => 0..8
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: col == 0 ? 0 : 8,
                    right: col == 2 ? 0 : 8,
                  ),
                  child: _buildButton(
                    index: index,
                    enabled: !_isCodeFull,
                    onPressed: () => widget.onDigit(digit),
                    child: Center(child: Text('$digit', style: digitTextStyle)),
                  ),
                ),
              );
            }),
          ),
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildButton(
                  index: 9,
                  enabled: true,
                  onPressed: widget.onBackspace,
                  child: Icon(
                    FontAwesomeIcons.deleteLeft,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildButton(
                  index: 10,
                  enabled: !_isCodeFull,
                  onPressed: () => widget.onDigit(0),
                  child: Center(child: Text('0', style: digitTextStyle)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _buildButton(
                  index: 11,
                  enabled: _isOkEnabled,
                  successBlackFill: _isOkEnabled,
                  onPressed: _isOkEnabled ? (widget.onOk ?? () {}) : null,
                  child: Icon(
                    FontAwesomeIcons.circleCheck,
                    size: 26,
                    color: _isOkEnabled
                        ? const Color(0xFF2E7D32)
                        : Colors.black38,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EntryLanguageOption extends StatelessWidget {
  const _EntryLanguageOption({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return _LoginFocusShell(
      borderRadius: 12,
      autofocus: autofocus,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? kColorPrimary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: selected
                ? kColorPrimary.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            AppLangFlagIcon(code: code, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Get.textTheme.titleSmall!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (selected)
              Icon(
                FontAwesomeIcons.circleCheck,
                color: kColorPrimary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
