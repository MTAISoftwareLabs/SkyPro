part of '../screens.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with WidgetsBindingObserver {
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _serverUrl = TextEditingController();
  String _url = '';
  final _activationApi = ActivationApi();
  String _activationStatus = 'جاري التحقق...';
  String _deviceId = '';
  final _storage = GetStorage();
  bool _blockedByVpn = false;
  String _blockMessage = '';
  bool _autoLoginTried = false;
  /// يمنع تكرار login failed كل ثانيتين؛ يُعاد فتحه عند QR برابط جديد فقط
  bool _playlistAutoLoginBlocked = false;
  String? _lastAutoDomainSeen;
  bool _playlistNotFoundFromPanel = false;
  bool _obscurePassword = true;
  bool _navigatedToWelcome = false;
  Timer? _activationTimer;
  String _selectedLoginServerKey = kLoginServerExternalKey;

  /// يمنع تداخل طلبات checkActivation دون إجبار إعادة بناء الواجهة.
  bool _activationCheckInFlight = false;

  static const _keySavedUsername = 'saved_login_username';
  static const _keySavedPassword = 'saved_login_password';

  final FocusNode _backFocus = FocusNode();
  final FocusNode _displayNameFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _passwordEyeFocus = FocusNode(skipTraversal: true);
  final FocusNode _serverChoiceFocus = FocusNode();
  final FocusNode _serverUrlFocus = FocusNode();
  final FocusNode _loginFocus = FocusNode();
  bool _displayNameEditing = false;
  bool _usernameEditing = false;
  bool _passwordEditing = false;
  bool _serverUrlEditing = false;
  bool _tvSideKeyboard = false;
  /// يمنع إغلاق الصفحة فوراً بعد Back اللي سكّر الكلافيي (سباق TV).
  bool _blockRoutePopForKeyboard = false;
  final FocusNode _sideKbSeedFocus = FocusNode();
  final ScrollController _formScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupRegisterFocusTree();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(lockHomeScreenLandscape());
      if (mounted && isTv(context)) {
        _displayNameFocus.requestFocus();
      }
    });
    _activationStatus = _storage.read('activation_status') ?? 'جاري التحقق...';
    final addingAccount = _storage.read(kStorageAddingNewAccount) == true;
    final justAddedPlaylist =
        _storage.read('activation_just_added_playlist') == true;
    final fillFromM3u = _storage.read(kStorageFillManualFromM3u) == true;
    final autoUser = _storage.read('activation_auto_username') as String?;
    final autoPass = _storage.read('activation_auto_password') as String?;
    // لا تملأ الخانات من اللوحة/التخزين إلا بعد Add/Change Playlist
    if (addingAccount) {
      _displayName.clear();
      _username.clear();
      _password.clear();
      _serverUrl.clear();
      _url = '';
    } else if (fillFromM3u &&
        autoUser != null &&
        autoPass != null &&
        autoUser.isNotEmpty &&
        autoPass.isNotEmpty) {
      // Account name stays empty so the user can set any label; username is
      // used as display name only on login if the field is still blank.
      _username.text = autoUser;
      _password.text = autoPass;
      final domainRaw =
          _storage.read('activation_domain') as String? ??
          _storage.read('activation_auto_domain') as String?;
      final domain = serverUrlForManualFields(domainRaw);
      if (domain != null && domain.isNotEmpty) {
        _url = domain;
        _serverUrl.text = domain;
      }
      unawaited(_storage.remove(kStorageFillManualFromM3u));
    } else {
      _displayName.clear();
      _username.clear();
      _password.clear();
      _serverUrl.clear();
      _url = '';
    }
    // الاختيار والتركيز الافتراضي دائماً على External، حتى مع وجود سيرفرات من اللوحة.
    _selectedLoginServerKey = kLoginServerExternalKey;
    if (justAddedPlaylist) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _checkActivation();
      });
    } else {
      _checkActivation();
    }
    // استطلاع دوري لاكتشاف ربط QR من الهاتف — يستمر حتى مغادرة الصفحة
    _activationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || _navigatedToWelcome) {
        timer.cancel();
        return;
      }
      _checkActivation(silentPoll: true);
    });
  }

  Future<void> _checkActivation({bool silentPoll = false}) async {
    if (_activationCheckInFlight) return;
    _activationCheckInFlight = true;

    final justAddedPlaylist =
        _storage.read('activation_just_added_playlist') == true;
    if (justAddedPlaylist) {
      await _storage.remove('activation_just_added_playlist');
    }

    try {
      if (!silentPoll) {
        setState(() {
          _activationStatus =
              justAddedPlaylist
                  ? 'fetching_playlist_from_panel'.tr
                  : 'جاري التحقق...';
        });
      }

      var panelPlaylistMissing = false;
      final previousDeviceId = _deviceId;
      _deviceId = await _activationApi.getDeviceId();
      final result = await _activationApi.checkActivation(_deviceId);

      final remoteAppName = result['app_name'] as String? ?? '';
      await _storage.write('app_name', kAppName);
      if (remoteAppName.trim().isNotEmpty &&
          remoteAppName.trim() != kAppName) {
        await _storage.write('panel_app_name', remoteAppName.trim());
      }
      final supportUrl =
          (result['support_contact_url'] as String? ?? '').trim();
      await _storage.write('support_contact_url', supportUrl);
      final expiryDate = (result['expiry_date'] as String? ?? '').trim();
      await _storage.write('activation_expiry_date', expiryDate);
      final lifetime = result['lifetime'] == true ||
          result['lifetime'] == 1 ||
          result['lifetime'] == '1';
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

      final domain = result['domain'] as String? ?? '';
      final addingAccountEarly =
          _storage.read(kStorageAddingNewAccount) == true;
      final awaitQrNew = _storage.read(kStorageQrAwaitNewAccount) == true;
      final forceQrLoginEarly =
          _storage.read(kStorageForceQrAutoLogin) == true;
      final fillFromM3u = _storage.read(kStorageFillManualFromM3u) == true;
      final allowApplyPanelPlaylist =
          !_playlistAutoLoginBlocked ||
          forceQrLoginEarly ||
          awaitQrNew ||
          fillFromM3u ||
          justAddedPlaylist;

      if (allowApplyPanelPlaylist &&
          (!addingAccountEarly || awaitQrNew) &&
          domain.isNotEmpty) {
        try {
          final asManual = await persistAutoLoginAsManualXtream(
            _storage,
            domain,
            markFillFromM3u: fillFromM3u || justAddedPlaylist,
          );
          if (asManual) {
            final creds = parseXtreamCredentialsFromUrl(domain);
            if (creds != null &&
                (fillFromM3u || justAddedPlaylist || forceQrLoginEarly)) {
              _username.text = creds.username;
              _password.text = creds.password;
              _url = creds.serverBase;
              _serverUrl.text = creds.serverBase;
            }
          } else {
            final uri = Uri.parse(domain);
            final playlistUsername = uri.queryParameters['username'] ?? '';
            final playlistPassword = uri.queryParameters['password'] ?? '';
            final baseDomain =
                uri.hasScheme && uri.host.isNotEmpty
                    ? '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'
                    : domain;
            await _storage.write('activation_domain', baseDomain);
            if (playlistUsername.isNotEmpty && playlistPassword.isNotEmpty) {
              await _storage.write('activation_auto_enabled', true);
              await _storage.write('activation_auto_username', playlistUsername);
              await _storage.write('activation_auto_password', playlistPassword);
              await _storage.write('activation_auto_domain', baseDomain);
              if (fillFromM3u || justAddedPlaylist || forceQrLoginEarly) {
                _username.text = playlistUsername;
                _password.text = playlistPassword;
                _url = baseDomain;
                _serverUrl.text = baseDomain;
              }
            } else {
              final playlistUrl = domain.trim();
              await _storage.write('activation_auto_domain', playlistUrl);
              await _storage.write('activation_auto_enabled', true);
              await _storage.remove('activation_auto_username');
              await _storage.remove('activation_auto_password');
            }
          }
        } catch (_) {
          await _storage.remove('activation_auto_enabled');
          await _storage.remove('activation_auto_username');
          await _storage.remove('activation_auto_password');
          await _storage.remove('activation_auto_domain');
        }
      } else if (!addingAccountEarly &&
          !allowApplyPanelPlaylist &&
          domain.isNotEmpty) {
        // فشل سابق: لا تُعد تطبيق رابط اللوحة على الخانات/الدخول التلقائي
      } else if (!addingAccountEarly && domain.isEmpty) {
        await _storage.remove('activation_auto_enabled');
        await _storage.remove('activation_auto_username');
        await _storage.remove('activation_auto_password');
        await _storage.remove('activation_auto_domain');
        if (justAddedPlaylist) {
          panelPlaylistMissing = true;
        }
      } else if (justAddedPlaylist && domain.isEmpty) {
        panelPlaylistMissing = true;
      }

      // playlist جديد من مسح QR → أعد السماح بالدخول التلقائي
      // (لا نحذف forceQr هنا — نافذة QR تبقيه كل ثانيتين حتى الدخول أو الإغلاق)
      final forceQrLogin = forceQrLoginEarly;
      if (forceQrLogin || awaitQrNew) {
        _lastAutoDomainSeen = null;
        _playlistAutoLoginBlocked = false;
        _autoLoginTried = false;
      }
      final currentAutoDomain =
          (_storage.read('activation_auto_domain') as String?)?.trim();
      // لا تُعد فتح المحاولة عند نفس رابط اللوحة بعد فشل — فقط QR / M3U جديد
      if (!_playlistAutoLoginBlocked &&
          (forceQrLogin ||
              awaitQrNew ||
              fillFromM3u ||
              justAddedPlaylist) &&
          currentAutoDomain != null &&
          currentAutoDomain.isNotEmpty &&
          currentAutoDomain != _lastAutoDomainSeen) {
        _lastAutoDomainSeen = currentAutoDomain;
        _autoLoginTried = false;
      }

      bool blockedByVpn = false;
      String blockMessage = '';
      if (result['status'] == 'نشط') {
        final blockVpn = result['block_vpn'] == true;
        if (blockVpn) {
          try {
            final isVpnActive = await VpnConnectionDetector.isVpnActive();
            if (isVpnActive) {
              blockedByVpn = true;
              blockMessage = 'vpn_not_allowed'.tr;
            }
          } catch (_) {}
        }
      }

      if (!mounted) return;

      final newStatus = result['status'] ?? 'غير مفعل';

      var nextUser = _username.text;
      var nextPass = _password.text;
      var nextUrl = '';
      var syncedServerFromAuto = false;
      final maySyncFields =
          !_playlistAutoLoginBlocked &&
          (_storage.read(kStorageFillManualFromM3u) == true ||
              justAddedPlaylist ||
              forceQrLogin);
      if (maySyncFields && _storage.read('activation_auto_enabled') == true) {
        final u = _storage.read('activation_auto_username') as String?;
        final p = _storage.read('activation_auto_password') as String?;
        final d =
            _storage.read('activation_domain') as String? ??
            _storage.read('activation_auto_domain') as String?;
        if (u != null && p != null && u.isNotEmpty && p.isNotEmpty) {
          nextUser = u;
          nextPass = p;
          final server = serverUrlForManualFields(d);
          if (server != null && server.isNotEmpty) {
            nextUrl = server;
            syncedServerFromAuto = true;
          }
        }
      }

      final playlistFlagChanged =
          panelPlaylistMissing && !_playlistNotFoundFromPanel;
      final addingAccount = _storage.read(kStorageAddingNewAccount) == true;
      final stateChanged =
          newStatus != _activationStatus ||
          blockedByVpn != _blockedByVpn ||
          blockMessage != _blockMessage ||
          (!addingAccount &&
              maySyncFields &&
              (nextUser != _username.text ||
                  nextPass != _password.text ||
                  (syncedServerFromAuto && nextUrl != _serverUrl.text))) ||
          (maySyncFields && syncedServerFromAuto && nextUrl != _url) ||
          _deviceId != previousDeviceId ||
          playlistFlagChanged;

      _activationStatus = newStatus;
      _blockedByVpn = blockedByVpn;
      _blockMessage = blockMessage;
      if (maySyncFields && syncedServerFromAuto) {
        _url = nextUrl;
      }
      if (!addingAccount && maySyncFields) {
        _username.text = nextUser;
        _password.text = nextPass;
        if (syncedServerFromAuto &&
            nextUrl.isNotEmpty &&
            !isM3uStylePlaylistUrl(nextUrl)) {
          _serverUrl.text = nextUrl;
          _selectedLoginServerKey = kLoginServerExternalKey;
        }
      }
      if (panelPlaylistMissing) {
        _playlistNotFoundFromPanel = true;
      }

      if (!silentPoll || stateChanged) {
        setState(() {});
      }

      await _storage.write('activation_status', _activationStatus);

      // حفظ إعدادات الإعلانات القادمة من لوحة التحكم (إن وُجدت)
      final adsEnabled = result['ads_enabled'] as bool? ?? true;
      final bannerHomeOnly = result['banner_home_only'] as bool? ?? true;
      final bannerAndroid = result['banner_ad_unit_android'] as String? ?? '';
      final bannerIos = result['banner_ad_unit_ios'] as String? ?? '';
      final interAndroid =
          result['interstitial_ad_unit_android'] as String? ?? '';
      final interIos = result['interstitial_ad_unit_ios'] as String? ?? '';

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

      // نبضة تواجد بغض النظر عن حالة التفعيل (نشط/منتهي/محظور)
      if (_deviceId.isNotEmpty) {
        await _activationApi.sendHeartbeat(_deviceId);
      }

      if (_activationStatus != 'محظور' &&
          _activationStatus != 'منتهي' &&
          !blockedByVpn &&
          (_activationStatus == 'نشط' ||
              forceQrLoginEarly ||
              awaitQrNew)) {
        await _autoLoginIfPossible();
      } else if (blockedByVpn) {
        // في الاستطلاع الصامت: اعرض الحوار فقط عند تغيّر حالة الحظر (لا تكرار كل 2 ث)
        if (!silentPoll || stateChanged) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showBlockDialog(
              context,
              title: 'not_allowed'.tr,
              message: blockMessage,
              appName: null,
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final unchanged = silentPoll && _activationStatus == 'غير مفعل';
        _activationStatus = 'غير مفعل';
        if (!unchanged) {
          setState(() {});
        }
      }
      await _storage.write('activation_status', 'غير مفعل');
      await _storage.write('activation_expiry_date', '');
      await _storage.write('activation_is_trial', false);
    } finally {
      _activationCheckInFlight = false;
    }
  }

  Future<void> _autoLoginIfPossible() async {
    if (_autoLoginTried || _playlistAutoLoginBlocked) return;
    if (!shouldAllowPlaylistAutoLogin()) return;
    // على شاشة register: دخول تلقائي فقط بعد M3U أو QR وليس من بقايا اللوحة
    final fillFromM3u = _storage.read(kStorageFillManualFromM3u) == true;
    final forceQr = _storage.read(kStorageForceQrAutoLogin) == true;
    final awaitQr = _storage.read(kStorageQrAwaitNewAccount) == true;
    final justAdded =
        _storage.read('activation_just_added_playlist') == true;
    if (!fillFromM3u && !forceQr && !awaitQr && !justAdded) return;
    if (_activationStatus == 'محظور' || _activationStatus == 'منتهي') return;

    final enabled = _storage.read('activation_auto_enabled') == true;
    if (!enabled) return;

    var savedUsername =
        (_storage.read('activation_auto_username') as String?)?.trim();
    var savedPassword =
        (_storage.read('activation_auto_password') as String?)?.trim();
    var savedDomain =
        (_storage.read('activation_auto_domain') as String?)?.trim();

    final fromUrl = parseXtreamCredentialsFromUrl(savedDomain ?? '');
    if (fromUrl != null) {
      savedUsername = fromUrl.username;
      savedPassword = fromUrl.password;
      savedDomain = fromUrl.serverBase;
      await persistAutoLoginAsManualXtream(_storage, 
          '${fromUrl.serverBase}/get.php?username=${Uri.encodeQueryComponent(fromUrl.username)}&password=${Uri.encodeQueryComponent(fromUrl.password)}');
    }

    if (savedUsername != null &&
        savedPassword != null &&
        savedUsername.isNotEmpty &&
        savedPassword.isNotEmpty) {
      // منع قبل محاولة تسجيل الدخول (حسب حد الأجهزة لنفس الحساب)
      final ok = await _precheckAccountLimit(
        username: savedUsername,
        password: savedPassword,
      );
      if (!ok) return;
      if (!mounted) return;
      _autoLoginTried = true;
      await signalDeviceQrLinkSuccess();
      await _storage.remove(kStorageForceQrAutoLogin);
      clearQrAwaitNewAccountFlags();
      if (Get.isDialogOpen == true) Get.back();
      if (!mounted) return;
      final domain =
          (savedDomain != null && savedDomain.isNotEmpty) ? savedDomain : _url;
      context.read<AuthBloc>().add(
        AuthRegister(savedUsername, savedPassword, domain),
      );
    } else if (savedDomain != null && savedDomain.isNotEmpty) {
      _autoLoginTried = true;
      await signalDeviceQrLinkSuccess();
      await _storage.remove(kStorageForceQrAutoLogin);
      clearQrAwaitNewAccountFlags();
      if (Get.isDialogOpen == true) Get.back();
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthUsePlaylist(savedDomain));
    }
  }

  Future<void> _login() async {
    if (_blockedByVpn) {
      await showBlockDialog(
        context,
        title: 'not_allowed'.tr,
        message: _blockMessage,
        appName: null,
      );
      return;
    }
    // منتهي/محظور: لا محاولة دخول أبداً
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    final activationStatus =
        _storage.read('activation_status')?.toString() ?? 'غير مفعل';

    if (activationEnforcedFromStorage()) {
      if (activationStatus != 'نشط') {
        await _checkActivation();
        if (!mounted) return;
        if (showActivationLoginDeniedToast(context, _activationStatus)) {
          return;
        }
        if (_activationStatus != 'نشط') {
          showWarningToast(
            context,
            'app_not_activated'.tr,
            'please_activate_first'.tr,
          );
          return;
        }
        if (_blockedByVpn) {
          await showBlockDialog(
            context,
            title: 'not_allowed'.tr,
            message: _blockMessage,
            appName: null,
          );
          return;
        }
      }
    }

    String username = _username.text.trim();
    String password = _password.text.trim();
    final typedDisplayName = _displayName.text.trim();
    final rawServer = selectedLoginServerRawUrl(
      _selectedLoginServerKey,
      _serverUrl.text,
    );
    if (rawServer == null) {
      showWarningToast(
        context,
        'notice_title'.tr,
        'server_url_required_msg'.tr,
      );
      return;
    }
    final domain = SavedAccountsRepository.normalizeServerUrl(rawServer);

    // إذا لم يُدخل المستخدم بيانات الدخول، نحاول استخدام البيانات القادمة من لوحة التحكم (Playlist)
    if (username.isEmpty || password.isEmpty) {
      final addingAccount = _storage.read(kStorageAddingNewAccount) == true;
      if (addingAccount) {
        final savedUsername =
            _storage.read('activation_auto_username') as String?;
        final savedPassword =
            _storage.read('activation_auto_password') as String?;

        if (savedUsername != null &&
            savedPassword != null &&
            savedUsername.isNotEmpty &&
            savedPassword.isNotEmpty) {
          username = savedUsername;
          password = savedPassword;
        }
      } else {
        final lastUser = _storage.read(_keySavedUsername) as String?;
        final lastPass = _storage.read(_keySavedPassword) as String?;
        final savedUsername =
            lastUser?.isNotEmpty == true
                ? lastUser
                : _storage.read('activation_auto_username') as String?;
        final savedPassword =
            lastPass?.isNotEmpty == true
                ? lastPass
                : _storage.read('activation_auto_password') as String?;

        if (savedUsername != null &&
            savedPassword != null &&
            savedUsername.isNotEmpty &&
            savedPassword.isNotEmpty) {
          username = savedUsername;
          password = savedPassword;
        }
      }
    }

    if (username.isNotEmpty && password.isNotEmpty) {
      // Empty account name → use username in Manage accounts after login.
      final displayName =
          typedDisplayName.isNotEmpty ? typedDisplayName : username;
      // منع قبل محاولة تسجيل الدخول (حسب حد الأجهزة لنفس الحساب)
      final ok = await _precheckAccountLimit(
        username: username,
        password: password,
        serverHost: domain,
        displayName: displayName,
      );
      if (!ok) return;
      if (!mounted) return;
      context.read<AuthBloc>().add(
        AuthRegister(
          username,
          password,
          domain,
          displayName: displayName,
          serverHostForPanel: domain,
        ),
      );
    } else if (_storage.read(kStorageAddingNewAccount) == true) {
      final savedDomain =
          _storage.read('activation_auto_domain') as String? ??
          _storage.read('activation_domain') as String?;
      if (savedDomain != null && savedDomain.trim().isNotEmpty) {
        if (!mounted) return;
        context.read<AuthBloc>().add(AuthUsePlaylist(savedDomain.trim()));
      }
    }
  }

  Future<bool> _precheckAccountLimit({
    required String username,
    required String password,
    String? serverHost,
    String? displayName,
  }) async {
    try {
      if (_deviceId.isEmpty) {
        _deviceId = await _activationApi.getDeviceId();
      }
      final r = await _activationApi.bindAccountToDevice(
        deviceId: _deviceId,
        username: username,
        password: password,
        serverHost: serverHost,
        displayName: displayName,
      );
      final ok = r['success'] == true;
      final msg = (r['message'] as String?) ?? '';
      if (!ok && msg.contains('Max devices')) {
        if (!mounted) return false;
        signalDeviceQrLinkFailed();
        showWarningToast(
          context,
          'max_devices_reached_title'.tr,
          'max_devices_reached_msg'.trParams({
            'max': '${r['max_devices'] ?? 1}',
          }),
        );
        return false;
      }
      return true;
    } catch (_) {
      // إذا فشل التحقق لأي سبب، لا نمنع الدخول (حتى لا نكسر التدفق)
      return true;
    }
  }

  void _hideIme() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _showIme() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _stopAllFieldEditing() {
    if (!_displayNameEditing &&
        !_usernameEditing &&
        !_passwordEditing &&
        !_serverUrlEditing &&
        !_tvSideKeyboard) {
      return;
    }
    setState(() {
      _displayNameEditing = false;
      _usernameEditing = false;
      _passwordEditing = false;
      _serverUrlEditing = false;
      _tvSideKeyboard = false;
    });
    _hideIme();
  }

  bool get _useTvSideKeyboard => isTv(context);

  bool _editingBlocksDpadNav() {
    if (_tvSideKeyboard) return true;
    return MediaQuery.viewInsetsOf(context).bottom > 40;
  }

  bool get _sideKbShowNext {
    if (_displayNameEditing || _usernameEditing) return true;
    if (_passwordEditing &&
        _selectedLoginServerKey == kLoginServerExternalKey) {
      return true;
    }
    return false;
  }

  void _sideKbDismiss() {
    if (!_tvSideKeyboard) return;
    // احفظ الخانة قبل الإيقاف — وإلا _activeEditFocus يرجع لأول خانة
    final returnTo = _activeEditFocus;
    setState(() => _blockRoutePopForKeyboard = true);
    _stopAllFieldEditing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      returnTo.requestFocus();
    });
    // أبقِ منع الـ pop لفترة قصيرة بعد Back (على TV كيتعاود يوصل pop بعد dismiss)
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (_blockRoutePopForKeyboard) {
        setState(() => _blockRoutePopForKeyboard = false);
      }
    });
  }

  void _sideKbPrimary() {
    if (_displayNameEditing) {
      _startEditing(_usernameFocus, (v) => _usernameEditing = v);
      return;
    }
    if (_usernameEditing) {
      _startEditing(_passwordFocus, (v) => _passwordEditing = v);
      return;
    }
    if (_passwordEditing &&
        _selectedLoginServerKey == kLoginServerExternalKey) {
      _startEditing(_serverUrlFocus, (v) => _serverUrlEditing = v);
      return;
    }
    // تم → خانة السيرفر (بعد إزالة ExcludeFocus)
    _stopAllFieldEditing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _serverChoiceFocus.requestFocus();
    });
  }

  TextEditingController? get _activeEditController {
    if (_displayNameEditing) return _displayName;
    if (_usernameEditing) return _username;
    if (_passwordEditing) return _password;
    if (_serverUrlEditing) return _serverUrl;
    return null;
  }

  FocusNode get _activeEditFocus {
    if (_usernameEditing) return _usernameFocus;
    if (_passwordEditing) return _passwordFocus;
    if (_serverUrlEditing) return _serverUrlFocus;
    return _displayNameFocus;
  }

  void _sideKbInsert(String char) {
    final c = _activeEditController;
    if (c == null) return;
    final t = c.text;
    final sel = c.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    final next = t.replaceRange(start, end, char);
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + char.length),
    );
  }

  void _sideKbBackspace() {
    final c = _activeEditController;
    if (c == null) return;
    final t = c.text;
    if (t.isEmpty) return;
    final sel = c.selection;
    if (sel.isValid && sel.start != sel.end) {
      final next = t.replaceRange(sel.start, sel.end, '');
      c.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: sel.start),
      );
      return;
    }
    final offset = sel.isValid ? sel.start : t.length;
    if (offset <= 0) return;
    final next = t.replaceRange(offset - 1, offset, '');
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset - 1),
    );
  }

  bool _isActivateKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
  }

  void _startEditing(FocusNode node, void Function(bool) setEditing) {
    setState(() {
      _displayNameEditing = false;
      _usernameEditing = false;
      _passwordEditing = false;
      _serverUrlEditing = false;
      setEditing(true);
      _tvSideKeyboard = _useTvSideKeyboard;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tvSideKeyboard) {
        _hideIme();
        _sideKbSeedFocus.requestFocus();
      } else {
        node.requestFocus();
        _showIme();
      }
      _ensureFieldNodeVisible(node);
    });
  }

  void _ensureFieldNodeVisible(FocusNode node) {
    final ctx = node.context;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.15,
      duration: kTvEnsureVisibleDuration,
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  void _ensureEditingFieldVisible({bool preferTop = false}) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: preferTop ? 0.05 : 0.12,
      duration: kTvEnsureVisibleDuration,
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  double _lastKeyboardInset = 0;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final inset = WidgetsBinding
            .instance.platformDispatcher.views.first.viewInsets.bottom /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    if (_lastKeyboardInset > 40 && inset <= 40) {
      if (!_tvSideKeyboard &&
          (_displayNameEditing ||
              _usernameEditing ||
              _passwordEditing ||
              _serverUrlEditing)) {
        setState(() {
          _displayNameEditing = false;
          _usernameEditing = false;
          _passwordEditing = false;
          _serverUrlEditing = false;
        });
      } else {
        setState(() {});
      }
    } else if ((_lastKeyboardInset - inset).abs() > 8) {
      setState(() {});
    }
    _lastKeyboardInset = inset;
    if (inset > 40 && !_tvSideKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureEditingFieldVisible(preferTop: false);
      });
    }
  }

  void _setupRegisterFocusTree() {
    void wireField({
      required FocusNode node,
      required bool Function() isEditing,
      required VoidCallback startEdit,
      required FocusNode? up,
      required FocusNode? down,
      FocusNode? left,
      FocusNode? right,
    }) {
      node.addListener(() {
        if (!node.hasFocus && isEditing()) {
          if (_tvSideKeyboard) return;
          final inset = MediaQuery.viewInsetsOf(context).bottom;
          if (inset > 40) return;
          _stopAllFieldEditing();
        }
      });
      node.onKeyEvent = (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (_isActivateKey(key)) {
          if (isEditing() && _editingBlocksDpadNav()) {
            if (_tvSideKeyboard) {
              _sideKbSeedFocus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          startEdit();
          return KeyEventResult.handled;
        }
        if (isEditing()) {
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            _stopAllFieldEditing();
            return KeyEventResult.handled;
          }
          if (_editingBlocksDpadNav()) {
            if (_tvSideKeyboard &&
                (key == LogicalKeyboardKey.arrowLeft ||
                    key == LogicalKeyboardKey.arrowRight ||
                    key == LogicalKeyboardKey.arrowUp ||
                    key == LogicalKeyboardKey.arrowDown)) {
              _sideKbSeedFocus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          _stopAllFieldEditing();
        }
        if (key == LogicalKeyboardKey.arrowUp && up != null) {
          up.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown && down != null) {
          down.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft && left != null) {
          left.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight && right != null) {
          right.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }

    _backFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        _stopAllFieldEditing();
        _displayNameFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (_isActivateKey(key)) {
        Get.back();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    wireField(
      node: _displayNameFocus,
      isEditing: () => _displayNameEditing,
      startEdit: () => _startEditing(
        _displayNameFocus,
        (v) => _displayNameEditing = v,
      ),
      up: _backFocus,
      down: _usernameFocus,
    );
    wireField(
      node: _usernameFocus,
      isEditing: () => _usernameEditing,
      startEdit: () =>
          _startEditing(_usernameFocus, (v) => _usernameEditing = v),
      up: _displayNameFocus,
      down: _passwordFocus,
    );
    wireField(
      node: _passwordFocus,
      isEditing: () => _passwordEditing,
      startEdit: () =>
          _startEditing(_passwordFocus, (v) => _passwordEditing = v),
      up: _usernameFocus,
      down: _serverChoiceFocus,
      right: _passwordEyeFocus,
    );

    _passwordEyeFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (_isActivateKey(key)) {
        setState(() => _obscurePassword = !_obscurePassword);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _passwordFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _stopAllFieldEditing();
        _usernameFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _stopAllFieldEditing();
        _serverChoiceFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // تنقّل السيرفرات (يسار/يمين) يُعالَج داخل _loginServerChoiceBar.
    // هنا فقط نربط التركيز؛ onKeyEvent يُمرَّر من بطاقة النموذج.

    wireField(
      node: _serverUrlFocus,
      isEditing: () => _serverUrlEditing,
      startEdit: () =>
          _startEditing(_serverUrlFocus, (v) => _serverUrlEditing = v),
      up: _serverChoiceFocus,
      down: _loginFocus,
    );

    _loginFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _stopAllFieldEditing();
        if (_selectedLoginServerKey == kLoginServerExternalKey) {
          _serverUrlFocus.requestFocus();
        } else {
          _serverChoiceFocus.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (_isActivateKey(key)) {
        unawaited(_login());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _activationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _displayName.dispose();
    _username.dispose();
    _password.dispose();
    _serverUrl.dispose();
    _backFocus.dispose();
    _displayNameFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _passwordEyeFocus.dispose();
    _serverChoiceFocus.dispose();
    _serverUrlFocus.dispose();
    _loginFocus.dispose();
    _sideKbSeedFocus.dispose();
    _formScrollController.dispose();
    if (!_navigatedToWelcome) {
      changeDeviceOrientBack();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(lockHomeScreenLandscape());
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = Get.textTheme.bodyMedium!.copyWith(
      color: Colors.white,
      fontSize: LoginPremiumTypography.input(false),
      fontWeight: FontWeight.bold,
    );

    return PopScope(
      canPop: !_tvSideKeyboard && !_blockRoutePopForKeyboard,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tvSideKeyboard) {
          _sideKbDismiss();
        }
      },
      child: Scaffold(
      backgroundColor: LoginPremiumColors.bgBottom,
      resizeToAvoidBottomInset: true,
      body: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, stateSetting) {
          return BlocConsumer<AuthBloc, AuthState>(
                listener: (context, state) async {
                  if (state is AuthFailed) {
                    _playlistAutoLoginBlocked = true;
                    _autoLoginTried = true;
                    if (state.message == 'LogOut') return;
                    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
                    if (_deviceId.isEmpty) {
                      _deviceId = await _activationApi.getDeviceId();
                    }
                    await clearLocalFailedPlaylistAutoLogin(_storage);
                    if (_deviceId.isNotEmpty) {
                      await _activationApi.clearPlaylistUrl(_deviceId);
                    }
                    if (!mounted) return;
                    if (!context.mounted) return;
                    showWarningToast(
                      context,
                      'login_failed'.tr,
                      'check_credentials'.tr,
                    );
                  } else if (state is AuthSuccess) {
                    final user = state.user;
                    final serverUrl = (user.serverInfo?.serverUrl ?? '').trim();
                    final username = (user.userInfo?.username ?? '').trim();
                    final password = (user.userInfo?.password ?? '').trim();
                    final hasCreds = username.isNotEmpty && password.isNotEmpty;
                    final hasPlaylist = serverUrl.isNotEmpty && !hasCreds;

                    if (!hasCreds && !hasPlaylist) return;

                    if (canPassActivationGate(
                      status: _activationStatus,
                      hasPlaylist: hasPlaylist,
                    )) {
                      if (!hasPlaylist) {
                    _storage.write(_keySavedUsername, _username.text.trim());
                    _storage.write(_keySavedPassword, _password.text.trim());
                      }
                      _storage.remove(kStorageAddingNewAccount);
                      await AppCacheClearer.prepareNewServerSession(context);
                      _navigatedToWelcome = true;
                      await navigateToHomeBootstrap();
                    } else if (!showActivationLoginDeniedToast(
                      context,
                      _activationStatus,
                    )) {
                      showWarningToast(
                        context,
                        'app_not_activated'.tr,
                        'please_activate_first'.tr,
                      );
                    }
                  }
                },
                builder: (context, state) {
                  final isLoading = state is AuthLoading;
              final isTvDevice = isTv(context);
              final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

              return Stack(
                fit: StackFit.expand,
                    children: [
                  const _LoginEntryPremiumBackground(),
                  SafeArea(
                    child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: AnimatedPadding(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.only(
                            bottom: isTvDevice ? 0 : keyboardInset,
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isTvDevice ? 28 : 16,
                              vertical: isTvDevice ? 16 : 10,
                            ),
                            child: Column(
                              children: [
                                ExcludeFocus(
                                  excluding: isTvDevice && _tvSideKeyboard,
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: FocusTraversalOrder(
                                      order: const NumericFocusOrder(1),
                                      child: _AddPlaylistFocusChip(
                                        focusNode: _backFocus,
                                        onTap: () => Get.back(),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              LucideIcons.arrow_left,
                                              color: Colors.white.withValues(
                                                alpha: 0.9,
                                              ),
                                              size: isTvDevice ? 20 : 18,
                          ),
                          const SizedBox(width: 8),
                                            Text(
                                              'back'.tr,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.9,
                                                ),
                                                fontWeight: FontWeight.w700,
                                                fontSize: isTvDevice ? 15 : 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: isTvDevice ? 8 : 6),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final compactH =
                                          constraints.maxHeight < 420;
                                      final sideKb =
                                          isTvDevice && _tvSideKeyboard;
                                      final keyboardOpen =
                                          !isTvDevice && keyboardInset > 40;
                                      final brand = _AddPlaylistBrandPane(
                                        isTvDevice: isTvDevice,
                                        compact:
                                            constraints.maxWidth < 720 ||
                                            compactH ||
                                            keyboardOpen ||
                                            sideKb,
                                        subtitleKey: 'entry_method_xtream_desc',
                                        hideSubtitle: keyboardOpen,
                                      );
                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                      children: [
                                          if (sideKb)
                        Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .only(start: 4, end: 8),
                                              child: SizedBox(
                                                width: math.min(
                                                  430,
                                                  constraints.maxWidth * 0.46,
                                                ),
                            child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                              children: [
                                                    brand,
                                  SizedBox(
                                                      height: isTvDevice
                                                          ? 12
                                                          : 8,
                                                    ),
                                                    _LoginTvSideKeyboard(
                                                      seedFocus:
                                                          _sideKbSeedFocus,
                                                      onChar: _sideKbInsert,
                                                      onBackspace:
                                                          _sideKbBackspace,
                                                      showNext:
                                                          _sideKbShowNext,
                                                      onPrimary:
                                                          _sideKbPrimary,
                                                      onDismiss:
                                                          _sideKbDismiss,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          else
                                            Expanded(
                                              flex: 35,
                                              child: Align(
                                                alignment: Alignment.center,
                                                child: brand,
                                              ),
                                            ),
                                        SizedBox(
                                            width: isTvDevice ? 28 : 18,
                                          ),
                                          Expanded(
                                            flex: sideKb ? 55 : 65,
                                            child: ExcludeFocus(
                                              excluding: sideKb,
                                              child: Align(
                                                alignment: Alignment.center,
                                                child: _buildXtreamFormCard(
                                                  isTvDevice: isTvDevice,
                                                  isLoading: isLoading,
                                                  style: style,
                                                  maxHeight:
                                                      constraints.maxHeight,
                                                  hideTitle: keyboardOpen,
                                                ),
                                              ),
                                          ),
                                        ),
                                      ],
                                      );
                                    },
                                    ),
                                  ),
                                ],
                            ),
                          ),
                        ),
                      ),
                  ),
                  if (isLoading)
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: isTvDevice ? 28 : 20,
                      child: IgnorePointer(
                        child: Material(
                          color: Colors.transparent,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xE61A1D24),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: kColorPrimary.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: kColorPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      'loading'.tr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.92,
                                        ),
                                        fontWeight: FontWeight.w600,
                                        fontSize: isTvDevice ? 14 : 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
                                          );
                                        },
                                      ),
                                    ),
    );
  }

  Widget _buildXtreamFormCard({
    required bool isTvDevice,
    required bool isLoading,
    required TextStyle style,
    required double maxHeight,
    bool hideTitle = false,
  }) {
    final compact = maxHeight < 460 || hideTitle;
    final dense = maxHeight < 520 || hideTitle;
    final gap = compact ? 6.0 : (dense ? 8.0 : 10.0);
    final fieldStyle = style.copyWith(
      fontSize: dense
          ? LoginPremiumTypography.input(false) - 1
          : LoginPremiumTypography.input(false),
    );

    final fields = <Widget>[
      if (!hideTitle)
        Text(
          'xtream_form_title'.tr,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: compact ? 16 : (isTvDevice ? 20 : 17),
          ),
        ),
      if (_playlistNotFoundFromPanel) ...[
        if (!hideTitle) SizedBox(height: gap),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
          ),
          child: Text(
            'add_playlist_not_available'.tr,
            textAlign: TextAlign.center,
            style: Get.textTheme.bodyMedium!.copyWith(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ),
      ],
      if (!hideTitle || _playlistNotFoundFromPanel) SizedBox(height: gap),
      FocusTraversalOrder(
        order: const NumericFocusOrder(2),
        child: TextField(
                                        controller: _displayName,
          focusNode: _displayNameFocus,
          readOnly: !_displayNameEditing,
          showCursor: _displayNameEditing,
          enableInteractiveSelection: _displayNameEditing,
          keyboardType:
              isTvDevice ? TextInputType.none : TextInputType.text,
          decoration: _addPlaylistFieldDecoration(
                                              hint: 'account_name'.tr,
            icon: LucideIcons.badge_check,
            isTvDevice: isTvDevice,
            dense: dense,
            highlighted: _displayNameEditing,
          ),
          style: fieldStyle,
          onTap: () =>
              _startEditing(_displayNameFocus, (v) => _displayNameEditing = v),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            _stopAllFieldEditing();
            _usernameFocus.requestFocus();
          },
        ),
      ),
      SizedBox(height: gap),
      FocusTraversalOrder(
        order: const NumericFocusOrder(3),
        child: TextField(
                                        controller: _username,
          focusNode: _usernameFocus,
          readOnly: !_usernameEditing,
          showCursor: _usernameEditing,
          enableInteractiveSelection: _usernameEditing,
          keyboardType:
              isTvDevice ? TextInputType.none : TextInputType.text,
          decoration: _addPlaylistFieldDecoration(
                                              hint: 'username'.tr,
            icon: LucideIcons.user,
            isTvDevice: isTvDevice,
            dense: dense,
            highlighted: _usernameEditing,
          ),
          style: fieldStyle,
          onTap: () =>
              _startEditing(_usernameFocus, (v) => _usernameEditing = v),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            _stopAllFieldEditing();
            _passwordFocus.requestFocus();
          },
        ),
      ),
      SizedBox(height: gap),
      FocusTraversalOrder(
        order: const NumericFocusOrder(4),
        child: TextField(
                                        controller: _password,
          focusNode: _passwordFocus,
          readOnly: !_passwordEditing,
          showCursor: _passwordEditing,
          enableInteractiveSelection: _passwordEditing,
                                        obscureText: _obscurePassword,
          keyboardType:
              isTvDevice ? TextInputType.none : TextInputType.visiblePassword,
          decoration: _addPlaylistFieldDecoration(
                                              hint: 'password'.tr,
            icon: LucideIcons.lock,
            isTvDevice: isTvDevice,
            dense: dense,
            highlighted: _passwordEditing,
                                              suffixIcon: IconButton(
              focusNode: _passwordEyeFocus,
              focusColor: kColorFocus.withValues(alpha: 0.28),
              hoverColor: kColorFocus.withValues(alpha: 0.16),
                                                onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
                                                },
                                                icon: Icon(
                _obscurePassword ? LucideIcons.eye_off : LucideIcons.eye,
                                                  size: 16,
                color: kColorPrimary.withValues(alpha: 0.9),
                                                ),
                                              ),
                                            ),
          style: fieldStyle,
          onTap: () =>
              _startEditing(_passwordFocus, (v) => _passwordEditing = v),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            _stopAllFieldEditing();
            _serverChoiceFocus.requestFocus();
          },
        ),
      ),
      SizedBox(height: gap),
      FocusTraversalOrder(
        order: const NumericFocusOrder(5),
        child: _loginServerChoiceBar(
          servers: panelLoginServers(),
          selectedKey: _selectedLoginServerKey,
          isTvDevice: isTvDevice,
          focusNode: _serverChoiceFocus,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.arrowUp) {
              _stopAllFieldEditing();
              _passwordFocus.requestFocus();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowDown) {
              _stopAllFieldEditing();
              if (_selectedLoginServerKey == kLoginServerExternalKey) {
                _serverUrlFocus.requestFocus();
              } else {
                _loginFocus.requestFocus();
              }
              return KeyEventResult.handled;
            }
            if (_isActivateKey(key)) return KeyEventResult.handled;
            return KeyEventResult.ignored;
          },
          showPickHint: !compact,
          compact: dense,
          onSelected: (key) {
            setState(() => _selectedLoginServerKey = key);
          },
        ),
      ),
      if (_selectedLoginServerKey == kLoginServerExternalKey) ...[
        SizedBox(height: gap),
        FocusTraversalOrder(
          order: const NumericFocusOrder(6),
          child: TextField(
                                        controller: _serverUrl,
            focusNode: _serverUrlFocus,
            readOnly: !_serverUrlEditing,
            showCursor: _serverUrlEditing,
            enableInteractiveSelection: _serverUrlEditing,
            keyboardType:
                isTvDevice ? TextInputType.none : TextInputType.url,
            decoration: _addPlaylistFieldDecoration(
              hint: 'server_url_required'.tr,
              icon: LucideIcons.link,
              isTvDevice: isTvDevice,
              dense: dense,
              highlighted: _serverUrlEditing,
            ),
            style: fieldStyle,
            onTap: () =>
                _startEditing(_serverUrlFocus, (v) => _serverUrlEditing = v),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              _stopAllFieldEditing();
              _loginFocus.requestFocus();
            },
          ),
        ),
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(top: 4),
                                        child: Text(
              'server_url_required_hint'.tr,
                                          textAlign: TextAlign.center,
              style: Get.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.55),
                height: 1.25,
                fontSize: 11,
              ),
            ),
          ),
      ],
    ];

    final loginBtn = FocusTraversalOrder(
      order: const NumericFocusOrder(7),
      child: _AddPlaylistFocusChip(
        focusNode: _loginFocus,
        borderRadius: 14,
        onTap: isLoading ? null : _login,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: compact ? 10 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [kColorPrimary, kColorPrimaryDark],
            ),
            boxShadow: [
              BoxShadow(
                color: kColorPrimary.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.black87,
                  ),
                )
              else ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black87, width: 1.4),
                  ),
                  child: const Icon(
                    LucideIcons.log_in,
                    size: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 10),
                                Text(
                  'login'.tr.toUpperCase(),
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 14 : 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: maxHeight,
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          dense ? 12 : 16,
          dense ? 10 : 14,
          dense ? 12 : 16,
          dense ? 10 : 14,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: kColorPrimary.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          controller: _formScrollController,
          physics: const ClampingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...fields,
              SizedBox(height: compact ? 8 : 12),
              loginBtn,
            ],
          ),
        ),
      ),
    );
  }
}
