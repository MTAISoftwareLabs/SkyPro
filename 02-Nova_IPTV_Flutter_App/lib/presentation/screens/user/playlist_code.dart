part of '../screens.dart';

/// صفحة Playlist Code — نفس تخطيط M3U (يسار شعار / يمين نموذج) مع خانة واحدة.
class PlaylistCodeScreen extends StatefulWidget {
  const PlaylistCodeScreen({super.key});

  @override
  State<PlaylistCodeScreen> createState() => _PlaylistCodeScreenState();
}

class _PlaylistCodeScreenState extends State<PlaylistCodeScreen>
    with WidgetsBindingObserver {
  final _codeController = TextEditingController();
  final _manualUsernameController = TextEditingController();
  final _manualPasswordController = TextEditingController();
  final _storage = GetStorage();
  final _activationApi = ActivationApi();

  bool _isLoading = false;
  bool _codeEditing = false;
  bool _usernameEditing = false;
  bool _passwordEditing = false;
  String? _pendingHostDomain;
  bool _obscurePassword = true;
  bool _leavingToBootstrap = false;
  bool _tvSideKeyboard = false;
  bool _blockRoutePopForKeyboard = false;
  double _lastKeyboardInset = 0;
  bool _credentialFocusSwitch = false;

  final FocusNode _backFocus = FocusNode();
  final FocusNode _codeFocus = FocusNode();
  final FocusNode _submitFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _passwordEyeFocus = FocusNode();
  final FocusNode _manualLoginFocus = FocusNode();
  final FocusNode _sideKbSeedFocus = FocusNode();
  final ScrollController _formScrollController = ScrollController();

  String get _activationStatus =>
      (_storage.read('activation_status') ?? '').toString();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupFocusTree();
    unawaited(lockHomeScreenLandscape());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await lockHomeScreenLandscape();
      if (!mounted) return;
      await syncAndPersistTvDeviceFlag(context);
      if (!mounted) return;
      _codeFocus.requestFocus();
    });
  }

  void _hideIme() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _showIme() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _stopAllEditing() {
    if (!_codeEditing &&
        !_usernameEditing &&
        !_passwordEditing &&
        !_tvSideKeyboard) {
      return;
    }
    setState(() {
      _codeEditing = false;
      _usernameEditing = false;
      _passwordEditing = false;
      _tvSideKeyboard = false;
    });
    _hideIme();
  }

  bool get _useTvSideKeyboard => isTv(context);

  bool _editingBlocksDpadNav() {
    if (_tvSideKeyboard) return true;
    return MediaQuery.viewInsetsOf(context).bottom > 40;
  }

  bool get _sideKbShowNext => _usernameEditing;

  TextEditingController? get _activeEditController {
    if (_usernameEditing) return _manualUsernameController;
    if (_passwordEditing) return _manualPasswordController;
    return null;
  }

  FocusNode get _activeEditFocus {
    if (_passwordEditing) return _passwordFocus;
    return _usernameFocus;
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

  void _sideKbDismiss() {
    if (!_tvSideKeyboard) return;
    final returnTo = _activeEditFocus;
    setState(() => _blockRoutePopForKeyboard = true);
    _stopAllEditing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      returnTo.requestFocus();
    });
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (_blockRoutePopForKeyboard) {
        setState(() => _blockRoutePopForKeyboard = false);
      }
    });
  }

  void _sideKbPrimary() {
    if (_usernameEditing) {
      _startEditingCredentials(_passwordFocus, (v) => _passwordEditing = v);
      return;
    }
    _stopAllEditing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _manualLoginFocus.requestFocus();
    });
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

  void _startEditing(
    FocusNode node,
    void Function(bool) setFlag, {
    required bool useTvSideKeyboard,
  }) {
    setState(() {
      _codeEditing = false;
      _usernameEditing = false;
      _passwordEditing = false;
      setFlag(true);
      _tvSideKeyboard = useTvSideKeyboard && _useTvSideKeyboard;
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
      if (!useTvSideKeyboard && !isTv(context)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _ensureEditingFieldVisible();
        });
      }
    });
  }

  void _startEditingCredentials(FocusNode node, void Function(bool) setFlag) {
    final switching = _usernameEditing || _passwordEditing;
    if (switching && !_tvSideKeyboard && !isTv(context)) {
      _credentialFocusSwitch = true;
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _credentialFocusSwitch = false;
      });
    }
    _startEditing(node, setFlag, useTvSideKeyboard: _useTvSideKeyboard);
  }

  void _deferCredentialBlurStop({
    required FocusNode node,
    required bool Function() isEditing,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _credentialFocusSwitch) return;
      if (node.hasFocus) return;
      if (_usernameFocus.hasFocus || _passwordFocus.hasFocus) return;
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      if (inset > 40) return;
      if (isEditing()) _stopAllEditing();
    });
  }

  bool _isActivateKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
  }

  void _startEditingCode() {
    if (_pendingHostDomain != null) {
      setState(() {
        _pendingHostDomain = null;
        _manualUsernameController.clear();
        _manualPasswordController.clear();
      });
    }
    _startEditing(_codeFocus, (v) => _codeEditing = v, useTvSideKeyboard: false);
  }

  void _setupFocusTree() {
    void wireField({
      required FocusNode node,
      required bool Function() isEditing,
      required VoidCallback startEdit,
      required FocusNode? up,
      required FocusNode? down,
      FocusNode? left,
      FocusNode? right,
      bool credentialField = false,
    }) {
      node.addListener(() {
        if (!node.hasFocus && isEditing()) {
          if (_tvSideKeyboard || _credentialFocusSwitch) return;
          if (credentialField) {
            _deferCredentialBlurStop(node: node, isEditing: isEditing);
            return;
          }
          final inset = MediaQuery.viewInsetsOf(context).bottom;
          if (inset > 40) return;
          _stopAllEditing();
        }
      });
      node.onKeyEvent = (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (_isActivateKey(key)) {
          if (isEditing() && credentialField && _editingBlocksDpadNav()) {
            if (_tvSideKeyboard) {
              _sideKbSeedFocus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          if (isEditing()) return KeyEventResult.ignored;
          startEdit();
          return KeyEventResult.handled;
        }
        final ctx = n.context;
        final towardEye = ctx != null &&
                Directionality.of(ctx) == TextDirection.rtl
            ? LogicalKeyboardKey.arrowLeft
            : LogicalKeyboardKey.arrowRight;
        if (isEditing()) {
          if (right != null && key == towardEye) {
            right.requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            _stopAllEditing();
            return KeyEventResult.handled;
          }
          if (credentialField && _editingBlocksDpadNav()) {
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
          if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown) {
            _stopAllEditing();
            if (key == LogicalKeyboardKey.arrowUp && up != null) {
              up.requestFocus();
            } else if (key == LogicalKeyboardKey.arrowDown && down != null) {
              down.requestFocus();
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
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
        _stopAllEditing();
        _codeFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (_isActivateKey(key)) {
        Get.back();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    wireField(
      node: _codeFocus,
      isEditing: () => _codeEditing,
      startEdit: _startEditingCode,
      up: _backFocus,
      down: _submitFocus,
    );
    final prevCodeHandler = _codeFocus.onKeyEvent;
    _codeFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (_codeEditing) _stopAllEditing();
        _submitFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return prevCodeHandler?.call(node, event) ?? KeyEventResult.ignored;
    };

    _submitFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _stopAllEditing();
        _codeFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown && _pendingHostDomain != null) {
        _stopAllEditing();
        _usernameFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (_isActivateKey(key)) {
        unawaited(_verifyCode());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    wireField(
      node: _usernameFocus,
      isEditing: () => _usernameEditing,
      startEdit: () =>
          _startEditingCredentials(_usernameFocus, (v) => _usernameEditing = v),
      up: _submitFocus,
      down: _passwordFocus,
      credentialField: true,
    );
    wireField(
      node: _passwordFocus,
      isEditing: () => _passwordEditing,
      startEdit: () =>
          _startEditingCredentials(_passwordFocus, (v) => _passwordEditing = v),
      up: _usernameFocus,
      down: _manualLoginFocus,
      right: _passwordEyeFocus,
      credentialField: true,
    );

    _passwordEyeFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (_isActivateKey(key)) {
        setState(() => _obscurePassword = !_obscurePassword);
        return KeyEventResult.handled;
      }
      final ctx = node.context;
      final backToPassword = ctx != null &&
              Directionality.of(ctx) == TextDirection.rtl
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowLeft;
      if (key == backToPassword) {
        _passwordFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _stopAllEditing();
        _usernameFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _stopAllEditing();
        _manualLoginFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    _manualLoginFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _stopAllEditing();
        _passwordFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (_isActivateKey(key)) {
        unawaited(_loginHostOnly());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  Future<void> _verifyCode() async {
    _stopAllEditing();
    _codeFocus.unfocus();
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    final digits = _codeController.text.trim().replaceAll(RegExp(r'\D'), '');
    if (digits == kDemoAccessCode) {
      await _storage.remove(kStorageAddingNewAccount);
      if (!mounted) return;
      context.read<SettingsCubit>().updateStatusAccount(true);
      _leavingToBootstrap = true;
      await navigateToHomeBootstrap();
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

    setState(() => _isLoading = true);
    final res = await _activationApi.redeemPlaylistCode(digits);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!res.ok || (res.m3uUrl ?? '').isEmpty) {
      final key = res.messageKey ?? 'access_code_not_found';
      showWarningToast(context, 'notice_title'.tr, key.tr);
      return;
    }
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
      setState(() => _pendingHostDomain = null);
      // احفظ للجلسات القادمة دون إطلاق دخول تلقائي موازي على شاشة أخرى
      await persistAutoLoginAsManualXtream(_storage, resolved);
      await _storage.write(kStorageSuppressPlaylistAutoLogin, true);
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthUsePlaylist(resolved));
      return;
    }

    if (isHostOnly) {
      final base = xtreamServerBaseFromUrl(resolved) ?? resolved;
      setState(() => _pendingHostDomain = base);
      await _storage.write('activation_domain', base);
      await _storage.write('activation_auto_domain', base);
      await _storage.write('activation_auto_enabled', false);
      await _storage.remove('activation_auto_username');
      await _storage.remove('activation_auto_password');
      if (!mounted) return;
      _startEditingCredentials(_usernameFocus, (v) => _usernameEditing = v);
      return;
    }

    setState(() => _pendingHostDomain = null);
    context.read<AuthBloc>().add(AuthUsePlaylist(resolved));
  }

  Future<void> _loginHostOnly() async {
    final host = (_pendingHostDomain ?? '').trim();
    if (host.isEmpty) return;
    final user = _manualUsernameController.text.trim();
    final pass = _manualPasswordController.text.trim();
    if (user.isEmpty || pass.isEmpty) {
      showWarningToast(
        context,
        'notice_title'.tr,
        'check_credentials'.tr,
      );
      return;
    }
    if (showActivationLoginDeniedToast(context, _activationStatus)) {
      return;
    }
    context.read<AuthBloc>().add(
      AuthRegister(
        user,
        pass,
        host,
        loginMethod: 'playlist_code',
        serverHostForPanel: host,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeController.dispose();
    _manualUsernameController.dispose();
    _manualPasswordController.dispose();
    _backFocus.dispose();
    _codeFocus.dispose();
    _submitFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _passwordEyeFocus.dispose();
    _manualLoginFocus.dispose();
    _sideKbSeedFocus.dispose();
    _formScrollController.dispose();
    if (!_leavingToBootstrap) {
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
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted || _leavingToBootstrap) return;
    final inset = WidgetsBinding
            .instance.platformDispatcher.views.first.viewInsets.bottom /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    if (_lastKeyboardInset > 40 && inset <= 40) {
      if (!_tvSideKeyboard &&
          (_codeEditing || _usernameEditing || _passwordEditing)) {
        if (_credentialFocusSwitch) {
          setState(() {});
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _credentialFocusSwitch) return;
            final insetNow = MediaQuery.viewInsetsOf(context).bottom;
            if (insetNow > 40) return;
            final focus = FocusManager.instance.primaryFocus;
            if (focus == _usernameFocus ||
                focus == _passwordFocus ||
                focus == _codeFocus) {
              return;
            }
            if (!_codeEditing && !_usernameEditing && !_passwordEditing) {
              return;
            }
            setState(() {
              _codeEditing = false;
              _usernameEditing = false;
              _passwordEditing = false;
            });
          });
        }
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
      child: BlocListener<AuthBloc, AuthState>(
      listener: (context, state) async {
        if (state is AuthFailed) {
          if (state.message == 'LogOut') return;
          if (!mounted || !context.mounted) return;
          if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
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
            _storage.remove(kStorageAddingNewAccount);
            await AppCacheClearer.prepareNewServerSession(context);
            _leavingToBootstrap = true;
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
      child: Scaffold(
        backgroundColor: LoginPremiumColors.bgBottom,
        resizeToAvoidBottomInset: true,
        body: Builder(
          builder: (context) {
            final isTvDevice = isTv(context);
            final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
            final keyboardOpen = !isTvDevice && keyboardInset > 40;
            final sideKb = isTvDevice && _tvSideKeyboard;
            final hostOnly = _pendingHostDomain != null;

            return Stack(
          fit: StackFit.expand,
          children: [
            const _LoginEntryPremiumBackground(),
            SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(
                  bottom: isTvDevice ? 0 : keyboardInset,
                ),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTvDevice ? 28 : 16,
                      vertical: isTvDevice ? 16 : 10,
                    ),
                    child: Column(
                      children: [
                        ExcludeFocus(
                          excluding: isTvDevice && sideKb,
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
                              final compactH = constraints.maxHeight < 420;
                              final brand = _AddPlaylistBrandPane(
                                isTvDevice: isTvDevice,
                                compact: constraints.maxWidth < 720 ||
                                    compactH ||
                                    keyboardOpen ||
                                    sideKb,
                                subtitleKey: 'entry_method_code_desc',
                                hideSubtitle: keyboardOpen,
                              );
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (sideKb)
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        start: 4,
                                        end: 8,
                                      ),
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
                                              height: isTvDevice ? 12 : 8,
                                            ),
                                            _LoginTvSideKeyboard(
                                              seedFocus: _sideKbSeedFocus,
                                              onChar: _sideKbInsert,
                                              onBackspace: _sideKbBackspace,
                                              showNext: _sideKbShowNext,
                                              onPrimary: _sideKbPrimary,
                                              onDismiss: _sideKbDismiss,
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
                                  SizedBox(width: isTvDevice ? 28 : 18),
                                  Expanded(
                                    flex: sideKb ? 55 : 65,
                                    child: ExcludeFocus(
                                      excluding: sideKb,
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: _buildFormCard(
                                          isTvDevice: isTvDevice,
                                          style: style,
                                          maxHeight: constraints.maxHeight,
                                          hideTitle: keyboardOpen,
                                          hostOnly: hostOnly,
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
            if (_isLoading)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: CircularProgressIndicator(color: kColorPrimary),
                  ),
                ),
              ),
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                if (state is! AuthLoading) return const SizedBox.shrink();
                return Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Center(
                      child: CircularProgressIndicator(color: kColorPrimary),
                    ),
                  ),
                );
              },
            ),
          ],
            );
          },
        ),
      ),
    ),
    );
  }

  Widget _buildFormCard({
    required bool isTvDevice,
    required TextStyle style,
    required double maxHeight,
    bool hideTitle = false,
    bool hostOnly = false,
  }) {
    final credentialsOnly = hostOnly && hideTitle && !isTvDevice;
    final compact = maxHeight < 460 || hideTitle;
    final dense = maxHeight < 520 || hideTitle;
    final gap = compact ? 6.0 : (dense ? 8.0 : 10.0);
    final fieldStyle = style.copyWith(
      fontSize: dense
          ? LoginPremiumTypography.input(false) - 1
          : LoginPremiumTypography.input(false),
    );
    final activateHeight = dense ? 42.0 : (isTvDevice ? 52.0 : 48.0);
    final loginHeight = dense ? 40.0 : (isTvDevice ? 48.0 : 44.0);

    final codeSection = <Widget>[
      if (!hideTitle)
        Text(
          'playlist_code_form_title'.tr,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: compact ? 16 : (isTvDevice ? 20 : 17),
          ),
        ),
      if (!hideTitle) SizedBox(height: gap),
      FocusTraversalOrder(
        order: const NumericFocusOrder(2),
        child: TextField(
          controller: _codeController,
          focusNode: _codeFocus,
          readOnly: !_codeEditing,
          showCursor: _codeEditing,
          enableInteractiveSelection: _codeEditing,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: fieldStyle.copyWith(letterSpacing: 4),
          decoration: _loginPremiumFieldDecoration(
            hint: 'access_code_hint'.tr,
            prefixIcon: LucideIcons.shield,
            isTvDevice: isTvDevice,
          ).copyWith(counterText: ''),
          onTap: _startEditingCode,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => unawaited(_verifyCode()),
        ),
      ),
      SizedBox(height: gap),
      FocusTraversalOrder(
        order: const NumericFocusOrder(3),
        child: _AddPlaylistFocusChip(
          focusNode: _submitFocus,
          borderRadius: 16,
          onTap: () => unawaited(_verifyCode()),
          child: Container(
            width: double.infinity,
            height: activateHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  LoginPremiumColors.gold,
                  LoginPremiumColors.goldDark,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: LoginPremiumColors.gold.withValues(alpha: 0.42),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  LucideIcons.shield_check,
                  size: 18,
                  color: Colors.black87,
                ),
                const SizedBox(width: 8),
                Text(
                  'playlist_code_activate'.tr,
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w800,
                    fontSize: LoginPremiumTypography.button(isTvDevice) -
                        (dense ? 1 : 0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];

    final credentialsSection = <Widget>[
      if (hostOnly && !credentialsOnly && !hideTitle) ...[
        SizedBox(height: gap),
        Text(
          'check_credentials'.tr,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w700,
            fontSize: dense ? 12 : 13,
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
      ],
      FocusTraversalOrder(
        order: const NumericFocusOrder(4),
        child: TextField(
          controller: _manualUsernameController,
          focusNode: _usernameFocus,
          readOnly: !_usernameEditing,
          showCursor: _usernameEditing,
          enableInteractiveSelection: _usernameEditing,
          keyboardType: isTvDevice ? TextInputType.none : TextInputType.text,
          decoration: _loginPremiumFieldDecoration(
            hint: 'username'.tr,
            prefixIcon: LucideIcons.user,
            isTvDevice: isTvDevice,
          ),
          style: fieldStyle,
          onTap: () => _startEditingCredentials(
            _usernameFocus,
            (v) => _usernameEditing = v,
          ),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            _startEditingCredentials(
              _passwordFocus,
              (v) => _passwordEditing = v,
            );
          },
        ),
      ),
      SizedBox(height: compact ? 6 : gap),
      FocusTraversalOrder(
        order: const NumericFocusOrder(5),
        child: TextField(
          controller: _manualPasswordController,
          focusNode: _passwordFocus,
          readOnly: !_passwordEditing,
          showCursor: _passwordEditing,
          enableInteractiveSelection: _passwordEditing,
          obscureText: _obscurePassword,
          keyboardType: isTvDevice
              ? TextInputType.none
              : TextInputType.visiblePassword,
          decoration: _loginPremiumFieldDecoration(
            hint: 'password'.tr,
            prefixIcon: LucideIcons.lock,
            isTvDevice: isTvDevice,
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
                color: LoginPremiumColors.gold.withValues(alpha: 0.9),
              ),
            ),
          ),
          style: fieldStyle,
          onTap: () => _startEditingCredentials(
            _passwordFocus,
            (v) => _passwordEditing = v,
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => unawaited(_loginHostOnly()),
        ),
      ),
      SizedBox(height: compact ? 8 : 10),
      FocusTraversalOrder(
        order: const NumericFocusOrder(6),
        child: _AddPlaylistFocusChip(
          focusNode: _manualLoginFocus,
          borderRadius: 16,
          onTap: () => unawaited(_loginHostOnly()),
          child: Container(
            width: double.infinity,
            height: loginHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: kColorPrimary.withValues(alpha: 0.9),
            ),
            child: Center(
              child: Text(
                'login'.tr,
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w800,
                  fontSize: LoginPremiumTypography.button(isTvDevice) -
                      (dense ? 1 : 0),
                ),
              ),
            ),
          ),
        ),
      ),
    ];

    final fields = <Widget>[
      if (!credentialsOnly) ...codeSection,
      if (hostOnly) ...credentialsSection,
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: maxHeight,
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          dense ? 12 : (isTvDevice ? 22 : 16),
          dense ? 10 : (isTvDevice ? 22 : 16),
          dense ? 12 : (isTvDevice ? 22 : 16),
          dense ? 10 : (isTvDevice ? 22 : 16),
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
            children: fields,
          ),
        ),
      ),
    );
  }
}
