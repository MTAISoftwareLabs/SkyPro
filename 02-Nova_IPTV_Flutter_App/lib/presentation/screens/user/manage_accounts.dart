part of '../screens.dart';

class ManageAccountsScreen extends StatefulWidget {
  const ManageAccountsScreen({super.key});

  @override
  State<ManageAccountsScreen> createState() => _ManageAccountsScreenState();
}

class _ManageAccountsScreenState extends State<ManageAccountsScreen>
    with WidgetsBindingObserver {
  List<SavedAccount> _accounts = [];
  String? _activeId;
  bool _switching = false;
  bool _fromEntry = false;
  bool _leavingToEntry = false;
  bool _leavingToBootstrap = false;
  Timer? _accountOkLongPressTimer;
  bool _accountOkLongPressTriggered = false;
  SavedAccount? _accountOkLongPressTarget;
  static const Duration _accountOkLongPressDuration =
      Duration(milliseconds: 650);
  final FocusNode _backFocus = FocusNode();
  final FocusNode _addAccountFocus = FocusNode();
  final ScrollController _accountsScroll = ScrollController();
  final List<FocusNode> _accountFocusNodes = [];
  int _lastFocusedAccountIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final args = Get.arguments;
    _fromEntry = args is Map && args['fromEntry'] == true;
    _backFocus.addListener(_onFocusTreeChanged);
    _addAccountFocus.addListener(_onFocusTreeChanged);
    unawaited(_bootstrapAccounts());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await syncAndPersistTvDeviceFlag(context);
      if (!mounted) return;
      if (_fromEntry) {
        unawaited(lockEntryScreenOrientations());
      } else {
        changeDeviceOrient();
      }
      if (!isTv(context)) return;
      _backFocus.requestFocus();
    });
  }

  Future<void> _bootstrapAccounts() async {
    await SavedAccountsRepository.migrateCurrentUserIfNeeded();
    if (!mounted) return;
    await SavedAccountsRepository.dedupeEquivalentAccounts();
    if (mounted) _reload();
    await _syncWebPlaylistsQuietly();
  }

  Future<void> _syncWebPlaylistsQuietly() async {
    try {
      final api = ActivationApi();
      final deviceId = await api.getDeviceId();
      if (deviceId.isEmpty) return;
      // checkActivation يضمّن web_playlists ويقوم بالمزامنة
      await api.checkActivation(deviceId);
      // احتياط: جلب مباشر إن بقيت القائمة فارغة من مصدر ويب
      final hasWeb = SavedAccountsRepository.listAccounts().any(
        (e) => e.source == 'web',
      );
      if (!hasWeb) {
        await api.syncWebPlaylistsToAccounts(deviceId);
      }
      await SavedAccountsRepository.dedupeEquivalentAccounts();
      if (mounted) _reload();
    } catch (_) {}
  }

  @override
  void dispose() {
    _accountOkLongPressTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_leavingToBootstrap) {
      unawaited(lockHomeScreenLandscape());
    } else if (_leavingToEntry) {
      // الاتجاه ضُبط قبل الانتقال لشاشة الدخول.
    } else if (_fromEntry) {
      changeDeviceOrientBack();
    } else {
      unawaited(lockHomeScreenLandscape());
    }
    _backFocus.dispose();
    _addAccountFocus.dispose();
    _accountsScroll.dispose();
    for (final node in _accountFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (_fromEntry) {
      unawaited(lockEntryScreenOrientations());
    } else {
      changeDeviceOrient();
    }
  }

  void _onFocusTreeChanged() {
    if (mounted) setState(() {});
  }

  void _syncAccountFocusNodes(int count) {
    while (_accountFocusNodes.length < count) {
      final node = FocusNode();
      node.addListener(_onFocusTreeChanged);
      _accountFocusNodes.add(node);
    }
    while (_accountFocusNodes.length > count) {
      final removed = _accountFocusNodes.removeLast();
      removed.removeListener(_onFocusTreeChanged);
      removed.dispose();
    }
  }

  void _scrollAccountIntoView(int index) {
    if (!_accountsScroll.hasClients || index < 0) return;
    const step = 130.0;
    final target = (index * step).clamp(
      0.0,
      _accountsScroll.position.maxScrollExtent,
    );
    _accountsScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _reload() {
    final list = SavedAccountsRepository.listAccounts();
    _syncAccountFocusNodes(list.length);
    setState(() {
      _accounts = list;
      _activeId = SavedAccountsRepository.activeAccountId;
    });
  }

  Future<void> _switchTo(SavedAccount account) async {
    if (_switching) return;
    // من شاشة الدخول: الضغط على الحساب الحالي يعيد تسجيل الدخول به.
    if (account.id == _activeId && !_fromEntry) return;
    final activationStatus =
        GetStorage().read('activation_status')?.toString() ?? '';
    if (showActivationLoginDeniedToast(context, activationStatus)) {
      return;
    }
    setState(() => _switching = true);
    context.read<AuthBloc>().add(AuthSwitchAccount(account.id));
  }

  Future<void> _navigateToEntryKeepingOrientation() async {
    _leavingToEntry = true;
    await lockEntryScreenOrientations();
    if (!mounted) return;
    Get.offAllNamed(screenEntry);
  }

  Future<void> _addAccount() async {
    final box = GetStorage();
    await box.write(kStorageAddingNewAccount, true);
    clearQrAwaitNewAccountFlags();
    await box.remove(kStorageForceQrAutoLogin);
    await box.write(kStorageSuppressPlaylistAutoLogin, true);
    await LocaleApi.logOut();
    await box.remove('activation_auto_enabled');
    await box.remove('activation_auto_username');
    await box.remove('activation_auto_password');
    await box.remove('activation_auto_domain');
    await box.remove('activation_domain');
    ParentalControlService.instance.clearSessionAccess();
    if (!mounted) return;
    context.read<AuthBloc>().add(AuthPrepareAddAccount());
    await _navigateToEntryKeepingOrientation();
  }

  bool _isOkSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.numpadEnter;
  }

  void _startAccountOkLongPress(SavedAccount account) {
    _accountOkLongPressTimer?.cancel();
    _accountOkLongPressTriggered = false;
    _accountOkLongPressTarget = account;
    _accountOkLongPressTimer = Timer(_accountOkLongPressDuration, () {
      if (!mounted) return;
      _accountOkLongPressTimer = null;
      _accountOkLongPressTriggered = true;
      final target = _accountOkLongPressTarget;
      if (target != null) _showAccountActionsMenu(target);
    });
  }

  bool _cancelAccountOkLongPressAndCheckTriggered() {
    _accountOkLongPressTimer?.cancel();
    _accountOkLongPressTimer = null;
    _accountOkLongPressTarget = null;
    final wasLong = _accountOkLongPressTriggered;
    if (wasLong) _accountOkLongPressTriggered = false;
    return wasLong;
  }

  KeyEventResult _handleBackKeyEvent(KeyEvent event) {
    if (_switching) return KeyEventResult.ignored;
    return settingsTvActivateOnSelect(event, () => Get.back());
  }

  KeyEventResult _handleAddAccountKeyEvent(KeyEvent event) {
    if (_switching) return KeyEventResult.ignored;
    return settingsTvActivateOnSelect(event, _addAccount);
  }

  int? _focusedAccountIndex() {
    for (var i = 0; i < _accountFocusNodes.length; i++) {
      if (_accountFocusNodes[i].hasFocus) return i;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return null;
    for (var i = 0; i < _accountFocusNodes.length; i++) {
      if (primary == _accountFocusNodes[i]) return i;
    }
    return null;
  }

  bool _isBackFocused() {
    return _backFocus.hasFocus ||
        FocusManager.instance.primaryFocus == _backFocus;
  }

  bool _isAddAccountFocused() {
    return _addAccountFocus.hasFocus ||
        FocusManager.instance.primaryFocus == _addAccountFocus;
  }

  /// شجرة التركيز: 1 رجوع → 2 حسابات → 3 إضافة حساب.
  void _handleManageAccountsDirection(TraversalDirection direction) {
    if (_switching) return;

    final accountIdx = _focusedAccountIndex();
    final onBack = _isBackFocused();
    final onAdd = _isAddAccountFocused();

    switch (direction) {
      case TraversalDirection.down:
        if (onBack) {
          if (_accounts.isNotEmpty && _accountFocusNodes.isNotEmpty) {
            _accountFocusNodes[0].requestFocus();
          } else {
            _addAccountFocus.requestFocus();
          }
        } else if (accountIdx != null) {
          _addAccountFocus.requestFocus();
        }
      case TraversalDirection.up:
        if (onAdd) {
          if (_accounts.isNotEmpty && _accountFocusNodes.isNotEmpty) {
            final idx = _lastFocusedAccountIndex.clamp(
              0,
              _accounts.length - 1,
            );
            _accountFocusNodes[idx].requestFocus();
          } else {
            _backFocus.requestFocus();
          }
        } else if (accountIdx != null) {
          _backFocus.requestFocus();
        }
      case TraversalDirection.left:
        if (accountIdx != null && accountIdx > 0) {
          _accountFocusNodes[accountIdx - 1].requestFocus();
        }
      case TraversalDirection.right:
        if (accountIdx != null && accountIdx < _accounts.length - 1) {
          _accountFocusNodes[accountIdx + 1].requestFocus();
        }
    }
    if (mounted) setState(() {});
  }

  Widget _wrapManageAccountsTvFocusTree(Widget child) {
    return Actions(
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            _handleManageAccountsDirection(intent.direction);
            return null;
          },
        ),
      },
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: child,
      ),
    );
  }

  Widget _buildManageBottomButton({
    required bool loading,
    required VoidCallback onTap,
    required IconData icon,
    required String label,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: loading ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: kColorPrimary, size: 16),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Get.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wrapTvBottomButton({
    required double order,
    required FocusNode focusNode,
    required bool loading,
    required KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent,
    required Widget child,
  }) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: Focus(
        focusNode: focusNode,
        onKeyEvent: (node, event) {
          if (loading) return KeyEventResult.ignored;
          return onKeyEvent(node, event);
        },
        child: _ManageAccountsFocusTile(
          focused: settingsShowFocusDecor(context, focusNode.hasFocus),
          borderRadius: 28,
          child: child,
        ),
      ),
    );
  }

  KeyEventResult _handleAccountCardKeyEvent(
    KeyEvent event,
    SavedAccount account,
    int index,
  ) {
    if (_switching) return KeyEventResult.ignored;

    if (event is KeyDownEvent && _isOkSelectKey(event.logicalKey)) {
      _startAccountOkLongPress(account);
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent && _isOkSelectKey(event.logicalKey)) {
      final wasLong = _cancelAccountOkLongPressAndCheckTriggered();
      if (!wasLong) {
        _switchTo(account);
      }
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.contextMenu) {
      _showAccountActionsMenu(account);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _showAccountActionsMenu(SavedAccount account) {
    if (_switching) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, animation, secondaryAnimation, _) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: AnimatedBuilder(
            animation: curved,
            builder: (context, child) {
              final slide = Tween<double>(begin: 14, end: 0).evaluate(curved);
              final scale = Tween<double>(begin: 0.9, end: 1).evaluate(curved);
              return Transform.translate(
                offset: Offset(0, slide),
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: Center(
              child: _AccountActionsMenuPanel(
                account: account,
                onChangePhoto: () {
                  Navigator.of(ctx).pop();
                  _changeAccountPhoto(account);
                },
                onRename: () {
                  Navigator.of(ctx).pop();
                  _renameAccount(account);
                },
                onDelete: () {
                  Navigator.of(ctx).pop();
                  _deleteAccount(account);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _renameAccount(SavedAccount account) async {
    final newName = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _RenameAccountDialog(initialName: account.displayName),
    );
    if (newName == null || newName.isEmpty) return;
    final ok = await SavedAccountsRepository.renameById(account.id, newName);
    if (!mounted) return;
    if (!ok) {
      showWarningToast(
        context,
        'notice_title'.tr,
        'account_name_required'.tr,
      );
      return;
    }
    _reload();
    showSoftToast(
      context,
      'manage_accounts_btn'.tr,
      'manage_accounts_renamed'.tr,
    );
  }

  Future<void> _changeAccountPhoto(SavedAccount account) async {
    final changed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return SafeArea(
          child: _AccountAvatarPickerDialog(account: account),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (!mounted || changed != true) return;
    _reload();
    showSoftToast(
      context,
      'manage_accounts_btn'.tr,
      'manage_accounts_photo_updated'.tr,
    );
  }

  Future<void> _deleteAccount(SavedAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141820),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: const Color(0xFFFF6B6B).withValues(alpha: 0.35)),
          ),
          title: Text(
            'manage_accounts_delete_title'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'manage_accounts_delete_message'.tr,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'settings_refresh_dialog_cancel'.tr,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'manage_accounts_delete_confirm'.tr,
                style: const TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final wasActive = account.id == _activeId;
    final wasLoggedIn = LocaleApi.getUserSync() != null;

    // إن كانت من موقع Manage Playlist — احذفها من السيرفر أيضاً
    if (account.source == 'web' &&
        (account.remoteId ?? '').trim().isNotEmpty) {
      try {
        final api = ActivationApi();
        final deviceId = await api.getDeviceId();
        if (deviceId.isNotEmpty) {
          await api.deleteWebPlaylist(
            deviceId: deviceId,
            remotePlaylistId: account.remoteId!.trim(),
          );
        }
      } catch (_) {}
    }

    await SavedAccountsRepository.removeById(account.id);
    if (!mounted) return;

    final remaining = SavedAccountsRepository.listAccounts();

    if (remaining.isEmpty) {
      final deviceId = await ActivationApi().getDeviceId();
      if (deviceId.isNotEmpty) {
        await ActivationApi().clearPlaylistUrl(deviceId);
      }
      if (!mounted) return;
      await AppCacheClearer.clearAllWithBlocs(context);
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthLogOut());
      _leavingToEntry = true;
      await _navigateToEntryKeepingOrientation();
      return;
    }

    if (wasActive && wasLoggedIn) {
      HomeBootstrapLoader.resetSession();
      await AppCacheClearer.clearApiAndDisk();
      if (!mounted) return;
      AppCacheClearer.resetSessionBlocs(context);
      context.read<AuthBloc>().add(AuthClearSession());
    }

    _reload();
    showSoftToast(
      context,
      'manage_accounts_btn'.tr,
      'manage_accounts_deleted'.tr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Ink(
        width: 100.w,
        height: 100.h,
        decoration: kDecorBackground,
        child: BlocConsumer<AuthBloc, AuthState>(
          listener: (context, state) async {
            if (state is AuthSuccess) {
              final activationStatus =
                  GetStorage().read('activation_status')?.toString() ?? '';
              if (showActivationLoginDeniedToast(context, activationStatus)) {
                _leavingToBootstrap = false;
                if (_switching && mounted) {
                  setState(() => _switching = false);
                }
                await lockEntryScreenOrientations();
                return;
              }
              _leavingToBootstrap = true;
              await lockHomeScreenLandscape();
              if (!mounted || !context.mounted) return;
              await AppCacheClearer.prepareNewServerSession(context);
              if (!mounted || !context.mounted) return;
              await navigateToHomeBootstrap();
            } else if (state is AuthFailed && state.message != 'LogOut') {
              _leavingToBootstrap = false;
              if (_switching && mounted) {
                setState(() => _switching = false);
                showWarningToast(
                  context,
                  'login_failed'.tr,
                  'check_credentials'.tr,
                );
              }
            }
          },
          builder: (context, state) {
            final loading = _switching || state is AuthLoading;
            final tv = isTv(context);
            Widget body = SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(4.w, 2.h, 4.w, 1.h),
                    child: Row(
                      children: [
                        tv
                            ? FocusTraversalOrder(
                              order: const NumericFocusOrder(1),
                              child: Focus(
                                focusNode: _backFocus,
                                onKeyEvent: (node, event) {
                                  if (loading) {
                                    return KeyEventResult.ignored;
                                  }
                                  return _handleBackKeyEvent(event);
                                },
                                child: _ManageAccountsFocusTile(
                                  focused: settingsShowFocusDecor(
                                    context,
                                    _backFocus.hasFocus,
                                  ),
                                  borderRadius: 12,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap:
                                          loading ? null : () => Get.back(),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Icon(
                                          Directionality.of(context) ==
                                                  TextDirection.rtl
                                              ? FontAwesomeIcons.chevronRight
                                              : FontAwesomeIcons.chevronLeft,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            : IconButton(
                              onPressed: loading ? null : () => Get.back(),
                              icon: Icon(
                                Directionality.of(context) ==
                                        TextDirection.rtl
                                    ? FontAwesomeIcons.chevronRight
                                    : FontAwesomeIcons.chevronLeft,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                        Expanded(
                          child: Column(
                            children: [
                              Image.asset(
                                kIconSplash,
                                width: 52,
                                height: 52,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                appName,
                                style: Get.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: Text(
                      'manage_accounts_title'.tr,
                      textAlign: TextAlign.center,
                      style: Get.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  SizedBox(height: 1.h),
                  Expanded(
                    child:
                        _accounts.isEmpty
                            ? Center(
                              child: Text(
                                'manage_accounts_empty'.tr,
                                style: Get.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white54,
                                ),
                              ),
                            )
                            : tv
                            ? FocusTraversalOrder(
                              order: const NumericFocusOrder(2),
                              child: FocusTraversalGroup(
                                policy: OrderedTraversalPolicy(),
                                child: SingleChildScrollView(
                                  controller: _accountsScroll,
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6.w,
                                  ),
                                  child: Row(
                                    children: [
                                      for (
                                        var i = 0;
                                        i < _accounts.length;
                                        i++
                                      ) ...[
                                        if (i > 0) const SizedBox(width: 22),
                                        FocusTraversalOrder(
                                          order: NumericFocusOrder(
                                            2 + (i + 1) * 0.01,
                                          ),
                                          child: Focus(
                                            focusNode: _accountFocusNodes[i],
                                            onFocusChange: (hasFocus) {
                                              if (hasFocus) {
                                                _lastFocusedAccountIndex = i;
                                                _scrollAccountIntoView(i);
                                              }
                                            },
                                            onKeyEvent: (node, event) {
                                              if (loading) {
                                                return KeyEventResult.ignored;
                                              }
                                              return _handleAccountCardKeyEvent(
                                                event,
                                                _accounts[i],
                                                i,
                                              );
                                            },
                                            child: _AccountAvatarCard(
                                              account: _accounts[i],
                                              isActive:
                                                  _accounts[i].id == _activeId,
                                              isFocused:
                                                  settingsShowFocusDecor(
                                                    context,
                                                    _accountFocusNodes[i]
                                                        .hasFocus,
                                                  ),
                                              onTap:
                                                  loading
                                                      ? null
                                                      : () => _switchTo(
                                                        _accounts[i],
                                                      ),
                                              onLongPress:
                                                  loading
                                                      ? null
                                                      : () =>
                                                          _showAccountActionsMenu(
                                                            _accounts[i],
                                                          ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            )
                            : SingleChildScrollView(
                              controller: _accountsScroll,
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.symmetric(horizontal: 6.w),
                              child: Row(
                                children: [
                                  for (var i = 0; i < _accounts.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 22),
                                    _AccountAvatarCard(
                                      account: _accounts[i],
                                      isActive: _accounts[i].id == _activeId,
                                      onTap:
                                          loading
                                              ? null
                                              : () => _switchTo(_accounts[i]),
                                      onLongPress:
                                          loading
                                              ? null
                                              : () => _showAccountActionsMenu(
                                                _accounts[i],
                                              ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(8.w, 0.5.h, 8.w, 1.5.h),
                    child: Column(
                      children: [
                        tv
                            ? _wrapTvBottomButton(
                              order: 3,
                              focusNode: _addAccountFocus,
                              loading: loading,
                              onKeyEvent: (node, event) =>
                                  _handleAddAccountKeyEvent(event),
                              child: _buildManageBottomButton(
                                loading: loading,
                                onTap: _addAccount,
                                icon: FontAwesomeIcons.userPlus,
                                label: 'manage_accounts_add'.tr,
                              ),
                            )
                            : _buildManageBottomButton(
                              loading: loading,
                              onTap: _addAccount,
                              icon: FontAwesomeIcons.userPlus,
                              label: 'manage_accounts_add'.tr,
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            );
            if (tv) {
              body = _wrapManageAccountsTvFocusTree(body);
            }
            return body;
          },
        ),
      ),
    );
  }
}

class _ManageAccountsFocusTile extends StatelessWidget {
  const _ManageAccountsFocusTile({
    required this.child,
    required this.focused,
    required this.borderRadius,
  });

  final Widget child;
  final bool focused;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border:
            focused
                ? Border.all(color: kColorPrimary, width: 2.5)
                : Border.all(color: Colors.transparent, width: 2.5),
        boxShadow:
            focused
                ? [
                  BoxShadow(
                    color: kColorPrimary.withValues(alpha: 0.35),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
                : null,
      ),
      child: child,
    );
  }
}

class _AccountAvatarCard extends StatelessWidget {
  const _AccountAvatarCard({
    required this.account,
    required this.isActive,
    this.isFocused = false,
    this.onTap,
    this.onLongPress,
  });

  final SavedAccount account;
  final bool isActive;
  final bool isFocused;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  DecorationImage? _accountAvatarDecoration(SavedAccount account) {
    final file = account.avatarFile?.trim() ?? '';
    if (file.isNotEmpty) {
      final f = File(file);
      if (f.existsSync()) {
        return DecorationImage(
          image: FileImage(f),
          fit: BoxFit.cover,
        );
      }
    }
    final asset = account.avatarAsset?.trim() ?? '';
    if (asset.isNotEmpty) {
      return DecorationImage(
        image: AssetImage(ProfileAvatars.assetPath(asset)),
        fit: BoxFit.cover,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = SavedAccountsRepository.avatarGradientFor(account.id);
    return SizedBox(
      width: 118,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isFocused
                        ? kColorPrimary
                        : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 82,
                        height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: account.hasCustomAvatar
                          ? null
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: colors,
                            ),
                      image: _accountAvatarDecoration(account),
                      border: Border.all(
                        color:
                            isActive
                                ? kColorPrimary
                                : Colors.white.withValues(alpha: 0.2),
                        width: isActive ? 3 : 1.5,
                      ),
                      boxShadow: [
                        if (isActive)
                          BoxShadow(
                            color: kColorPrimary.withValues(alpha: 0.35),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                    child: account.hasCustomAvatar
                        ? null
                        : Center(
                            child: Text(
                              account.initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                  ),
                  if (isActive)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: kColorPrimary,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF0D1018), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: kColorPrimary.withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          LucideIcons.check,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                account.displayName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Get.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (isActive) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: kColorPrimary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kColorPrimary.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    'manage_accounts_current'.tr,
                    textAlign: TextAlign.center,
                    style: Get.textTheme.labelSmall?.copyWith(
                      color: kColorPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                account.publicSubtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Get.textTheme.labelSmall?.copyWith(
                  color: Colors.white54,
                  height: 1.25,
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountActionsMenuPanel extends StatelessWidget {
  const _AccountActionsMenuPanel({
    required this.account,
    required this.onChangePhoto,
    required this.onRename,
    required this.onDelete,
  });

  final SavedAccount account;
  final VoidCallback onChangePhoto;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final maxW = (getSize(context).width * 0.78).clamp(240.0, 300.0);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: maxW,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1C2233), Color(0xFF10141E)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kColorPrimary.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: kColorPrimary.withValues(alpha: 0.12),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              account.displayName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Get.textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              account.publicSubtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Get.textTheme.labelSmall?.copyWith(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            _AccountActionTile(
              icon: LucideIcons.image,
              label: 'manage_accounts_change_photo'.tr,
              accent: kColorPrimary,
              onTap: onChangePhoto,
            ),
            const SizedBox(height: 8),
            _AccountActionTile(
              icon: LucideIcons.pencil,
              label: 'manage_accounts_rename'.tr,
              accent: kColorPrimary,
              onTap: onRename,
            ),
            const SizedBox(height: 8),
            _AccountActionTile(
              icon: LucideIcons.trash_2,
              label: 'manage_accounts_delete'.tr,
              accent: const Color(0xFFFF6B6B),
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameAccountDialog extends StatefulWidget {
  const _RenameAccountDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameAccountDialog> createState() => _RenameAccountDialogState();
}

class _RenameAccountDialogState extends State<_RenameAccountDialog>
    with WidgetsBindingObserver {
  late final TextEditingController _controller;
  late final FocusNode _nameFocus;
  late final FocusNode _cancelFocus;
  late final FocusNode _renameFocus;
  bool _cancelFocused = false;
  bool _renameFocused = false;
  bool _wasKeyboardOpen = false;

  bool get _keyboardOpen =>
      isTv(context) && MediaQuery.viewInsetsOf(context).bottom > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = TextEditingController(text: widget.initialName);
    _nameFocus = FocusNode();
    _cancelFocus = FocusNode();
    _renameFocus = FocusNode();
    _nameFocus.onKeyEvent = _handleNameFieldKey;
    _cancelFocus.onKeyEvent = _handleCancelKey;
    _renameFocus.onKeyEvent = _handleRenameKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _nameFocus.dispose();
    _cancelFocus.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted || !isTv(context)) return;
    final open = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (_wasKeyboardOpen && !open) {
      _scheduleRenameButtonFocus();
    }
    _wasKeyboardOpen = open;
  }

  void _scheduleRenameButtonFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _keyboardOpen) return;
      _renameFocus.requestFocus();
      setState(() {
        _renameFocused = true;
        _cancelFocused = false;
      });
    });
  }

  void _dismissKeyboardToRenameButton() {
    _nameFocus.unfocus();
    _scheduleRenameButtonFocus();
  }

  KeyEventResult _handleNameFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !isTv(context)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      if (_keyboardOpen) {
        _dismissKeyboardToRenameButton();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_isSelectKey(key)) {
      if (_keyboardOpen) {
        _dismissKeyboardToRenameButton();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown && !_keyboardOpen) {
      _renameFocus.requestFocus();
      setState(() {
        _renameFocused = true;
        _cancelFocused = false;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCancelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _nameFocus.requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _renameFocus.requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    return settingsTvActivateOnSelect(event, () => Navigator.of(context).pop());
  }

  KeyEventResult _handleRenameKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _nameFocus.requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _cancelFocus.requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    return settingsTvActivateOnSelect(
      event,
      () => Navigator.of(context).pop(_controller.text.trim()),
    );
  }

  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.numpadEnter;
  }

  Widget _dialogButton({
    required FocusNode node,
    required bool focused,
    required ValueChanged<bool> onFocusChanged,
    required VoidCallback onPressed,
    required Widget label,
    required bool primary,
  }) {
    final showFocus = settingsShowFocusDecor(context, focused);
    return Focus(
      focusNode: node,
      onFocusChange: onFocusChanged,
      child: AnimatedScale(
        scale: showFocus ? kTvFocusScale(true, 1.06) : 1.0,
        duration: kFocusAnimDuration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: showFocus ? kColorPrimary : Colors.white.withValues(alpha: 0.14),
              width: showFocus ? 2.5 : 1,
            ),
            boxShadow: settingsThemedFocusGlow(showFocus),
            color:
                primary
                    ? kColorPrimary.withValues(alpha: showFocus ? 0.28 : 0.16)
                    : Colors.white.withValues(alpha: 0.05),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Center(child: label),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    Widget cancelBtn = _dialogButton(
      node: _cancelFocus,
      focused: _cancelFocused,
      onFocusChanged: (v) {
        if (_cancelFocused != v) setState(() => _cancelFocused = v);
      },
      onPressed: () => Navigator.of(context).pop(),
      primary: false,
      label: Text(
        'settings_refresh_dialog_cancel'.tr,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    Widget renameBtn = _dialogButton(
      node: _renameFocus,
      focused: _renameFocused,
      onFocusChanged: (v) {
        if (_renameFocused != v) setState(() => _renameFocused = v);
      },
      onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
      primary: true,
      label: Text(
        'manage_accounts_rename'.tr,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (tv) {
      cancelBtn = FocusTraversalOrder(
        order: const NumericFocusOrder(2),
        child: cancelBtn,
      );
      renameBtn = FocusTraversalOrder(
        order: const NumericFocusOrder(3),
        child: renameBtn,
      );
    }

    Widget nameField = TextField(
      focusNode: _nameFocus,
      controller: _controller,
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.done,
      // هاتف: لا تُغلق الكيبورد تلقائياً عند Done حتى لا تقفز الواجهة
      onSubmitted: (_) {
        if (isTv(context)) {
          _dismissKeyboardToRenameButton();
        }
      },
      decoration: InputDecoration(
        hintText: 'account_name'.tr,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: kColorPrimary, width: 2),
        ),
      ),
    );
    if (tv) {
      nameField = FocusTraversalOrder(
        order: const NumericFocusOrder(1),
        child: nameField,
      );
    }

    final screenW = getSize(context).width;
    final dialogW = (screenW * 0.72).clamp(280.0, 420.0);

    // هيكل ثابت (بدون تبديل Expanded/غير Expanded مع الكيبورد) — يمنع القفز
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Material(
          color: const Color(0xFF141820),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dialogW),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: kColorPrimary.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.manual,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'manage_accounts_rename'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 14),
                    nameField,
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: cancelBtn),
                        const SizedBox(width: 10),
                        Expanded(child: renameBtn),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountActionTile extends StatelessWidget {
  const _AccountActionTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.26)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Get.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountAvatarPickerDialog extends StatefulWidget {
  const _AccountAvatarPickerDialog({required this.account});

  final SavedAccount account;

  @override
  State<_AccountAvatarPickerDialog> createState() =>
      _AccountAvatarPickerDialogState();
}

class _AccountAvatarPickerDialogState extends State<_AccountAvatarPickerDialog> {
  String? _selectedAsset;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final asset = widget.account.avatarAsset?.trim() ?? '';
    if (ProfileAvatars.isPreset(asset)) {
      _selectedAsset = asset;
    }
  }

  Future<void> _applyPreset(String fileName) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _selectedAsset = fileName;
    });
    final ok = await SavedAccountsRepository.setAvatarAssetById(
      widget.account.id,
      fileName,
    );
    if (!mounted) return;
    Navigator.of(context).pop(ok);
  }

  Future<void> _pickFromDevice() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // file_picker 12+: static API (no FilePicker.platform)
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final srcPath = picked.path;
      if (srcPath == null || srcPath.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final src = File(srcPath);
      if (!await src.exists()) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory('${docs.path}/profile_avatars');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      var ext = '.jpg';
      final lower = srcPath.toLowerCase();
      if (lower.endsWith('.png')) {
        ext = '.png';
      } else if (lower.endsWith('.webp')) {
        ext = '.webp';
      } else if (lower.endsWith('.gif')) {
        ext = '.gif';
      } else if (lower.endsWith('.jpeg') || lower.endsWith('.jpg')) {
        ext = '.jpg';
      }
      final dest = File(
        '${folder.path}/${widget.account.id}_avatar$ext',
      );
      await src.copy(dest.path);
      final ok = await SavedAccountsRepository.setAvatarFileById(
        widget.account.id,
        dest.path,
      );
      if (!mounted) return;
      Navigator.of(context).pop(ok);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final isPhone = mq.width < 600;
    final maxW = (mq.width * (isPhone ? 0.92 : 0.88)).clamp(280.0, 520.0);
    final crossAxis = mq.width < 520 ? 3 : 4;
    final gridGap = isPhone ? 10.0 : 14.0;
    final screenH = mq.height > 0 ? mq.height : 700.0;
    final preferred = screenH * (isPhone ? 0.72 : 0.78);
    final maxAllowed = screenH * 0.9;
    final dialogH = preferred > maxAllowed
        ? maxAllowed
        : (preferred < 280 ? (maxAllowed < 280 ? maxAllowed : 280.0) : preferred);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: maxW,
          height: dialogH,
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: isPhone ? 12 : 16),
            padding: EdgeInsets.fromLTRB(
              isPhone ? 14 : 18,
              isPhone ? 14 : 18,
              isPhone ? 14 : 18,
              8,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF222938), Color(0xFF12161F)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kColorPrimary.withValues(alpha: 0.28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'manage_accounts_change_photo'.tr,
                  textAlign: TextAlign.center,
                  style: Get.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: isPhone ? 18 : 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.account.displayName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Get.textTheme.labelMedium?.copyWith(
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'manage_accounts_choose_avatar'.tr,
                  textAlign: TextAlign.center,
                  style: Get.textTheme.labelMedium?.copyWith(
                    color: Colors.white38,
                    height: 1.35,
                    fontSize: isPhone ? 12 : null,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: ProfileAvatars.presets.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxis,
                      mainAxisSpacing: gridGap,
                      crossAxisSpacing: gridGap,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, index) {
                      final name = ProfileAvatars.presets[index];
                      final selected = _selectedAsset == name;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _busy ? null : () => _applyPreset(name),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: EdgeInsets.all(isPhone ? 3 : 5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? kColorPrimary
                                    : Colors.white.withValues(alpha: 0.16),
                                width: selected ? 3 : 1.5,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: kColorPrimary.withValues(
                                          alpha: 0.32,
                                        ),
                                        blurRadius: 12,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                ProfileAvatars.assetPath(name),
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(
                                    LucideIcons.image_off,
                                    color: Colors.white38,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _AccountActionTile(
                    icon: LucideIcons.upload,
                    label: 'manage_accounts_pick_from_device'.tr,
                    accent: kColorPrimary,
                    onTap: _busy ? () {} : _pickFromDevice,
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: Text(
                    'settings_refresh_dialog_cancel'.tr,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

