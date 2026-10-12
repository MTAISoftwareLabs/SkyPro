part of '../screens.dart';

enum _AddPlaylistSource { file, url }

/// صفحة M3U URL — نفس هيكل وتصميم Xtream Code (RegisterScreen).
class AddPlaylistScreen extends StatefulWidget {
  const AddPlaylistScreen({super.key});

  @override
  State<AddPlaylistScreen> createState() => _AddPlaylistScreenState();
}

class _AddPlaylistScreenState extends State<AddPlaylistScreen>
    with WidgetsBindingObserver {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _storage = GetStorage();
  final _activationApi = ActivationApi();

  bool _isLoading = false;
  bool _awaitingLogin = false;
  bool _leavingToBootstrap = false;

  _AddPlaylistSource _source = _AddPlaylistSource.url;
  String? _pickedFilePath;
  String? _pickedFileName;

  bool _nameEditing = false;
  bool _urlEditing = false;
  bool _tvSideKeyboard = false;
  bool _blockRoutePopForKeyboard = false;

  final FocusNode _backFocus = FocusNode();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _fileSourceFocus = FocusNode();
  final FocusNode _urlSourceFocus = FocusNode();
  final FocusNode _browseFocus = FocusNode();
  final FocusNode _urlFieldFocus = FocusNode();
  final FocusNode _submitFocus = FocusNode();
  final FocusNode _sideKbSeedFocus = FocusNode();
  final ScrollController _formScrollController = ScrollController();

  double _lastKeyboardInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupM3uFocusTree();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(lockHomeScreenLandscape());
      if (!mounted) return;
      await syncAndPersistTvDeviceFlag(context);
      if (!mounted) return;
      if (isTv(context)) {
        _nameFocus.requestFocus();
      }
    });
  }

  bool get _useTvSideKeyboard => isTv(context);

  TextEditingController? get _activeEditController {
    if (_nameEditing) return _nameController;
    if (_urlEditing) return _urlController;
    return null;
  }

  FocusNode get _activeEditFocus =>
      _urlEditing ? _urlFieldFocus : _nameFocus;

  bool get _sideKbShowNext => _nameEditing;

  String get _playlistDisplayName {
    final typed = _nameController.text.trim();
    if (typed.isNotEmpty) return typed;
    final fileName = (_pickedFileName ?? '').trim();
    if (fileName.isNotEmpty) {
      return fileName.replaceAll(RegExp(r'\.(m3u8?|M3U8?)$'), '');
    }
    return 'Playlist';
  }

  FocusNode _focusAfterSourceRadios() =>
      _source == _AddPlaylistSource.file ? _browseFocus : _urlFieldFocus;

  void _hideIme() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _showIme() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _stopAllFieldEditing() {
    if (!_nameEditing && !_urlEditing && !_tvSideKeyboard) return;
    setState(() {
      _nameEditing = false;
      _urlEditing = false;
      _tvSideKeyboard = false;
    });
    _hideIme();
  }

  bool _editingBlocksDpadNav() {
    if (_tvSideKeyboard) return true;
    return MediaQuery.viewInsetsOf(context).bottom > 40;
  }

  bool _isActivateKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
  }

  void _startEditing(FocusNode node, void Function(bool) setEditing) {
    setState(() {
      _nameEditing = false;
      _urlEditing = false;
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
    _stopAllFieldEditing();
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
    if (_nameEditing) {
      if (_source == _AddPlaylistSource.url) {
        _startEditing(_urlFieldFocus, (v) => _urlEditing = v);
      } else {
        _stopAllFieldEditing();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _fileSourceFocus.requestFocus();
        });
      }
      return;
    }
    _stopAllFieldEditing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _submitFocus.requestFocus();
    });
  }

  void _setupM3uFocusTree() {
    void wireField({
      required FocusNode node,
      required bool Function() isEditing,
      required VoidCallback startEdit,
      required FocusNode? up,
      required FocusNode? down,
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
        _nameFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (_isActivateKey(key)) {
        Get.back();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    wireField(
      node: _nameFocus,
      isEditing: () => _nameEditing,
      startEdit: () => _startEditing(_nameFocus, (v) => _nameEditing = v),
      up: _backFocus,
      down: _fileSourceFocus,
    );

    _fileSourceFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _stopAllFieldEditing();
        _nameFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _stopAllFieldEditing();
        _focusAfterSourceRadios().requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _urlSourceFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        return KeyEventResult.handled;
      }
      if (_isActivateKey(key)) {
        setState(() => _source = _AddPlaylistSource.file);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    _urlSourceFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _stopAllFieldEditing();
        _nameFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _stopAllFieldEditing();
        _focusAfterSourceRadios().requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _fileSourceFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.handled;
      }
      if (_isActivateKey(key)) {
        setState(() => _source = _AddPlaylistSource.url);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    wireField(
      node: _urlFieldFocus,
      isEditing: () => _urlEditing,
      startEdit: () => _startEditing(_urlFieldFocus, (v) => _urlEditing = v),
      up: _urlSourceFocus,
      down: _submitFocus,
    );

    _browseFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _fileSourceFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _submitFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (_isActivateKey(key)) {
        unawaited(_pickLocalPlaylist());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    _submitFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _stopAllFieldEditing();
        _focusAfterSourceRadios().requestFocus();
        return KeyEventResult.handled;
      }
      if (_isActivateKey(key)) {
        if (!_isLoading) unawaited(_submit());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    _nameController.dispose();
    _backFocus.dispose();
    _nameFocus.dispose();
    _fileSourceFocus.dispose();
    _urlSourceFocus.dispose();
    _browseFocus.dispose();
    _urlFieldFocus.dispose();
    _submitFocus.dispose();
    _sideKbSeedFocus.dispose();
    _formScrollController.dispose();
    if (_leavingToBootstrap) {
      unawaited(lockHomeScreenLandscape());
    } else {
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
      if (!_tvSideKeyboard && (_nameEditing || _urlEditing)) {
        setState(() {
          _nameEditing = false;
          _urlEditing = false;
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

  Future<void> _prepareLandscapeLoading() async {
    _leavingToBootstrap = true;
    await lockHomeScreenLandscape();
  }

  Future<void> _loginLikeManualUsernamePassword(
    XtreamUrlCredentials creds, {
    required String originalUrl,
  }) async {
    final domain = SavedAccountsRepository.normalizeServerUrl(creds.serverBase);
    final playlistUrl = originalUrl.trim().isNotEmpty ? originalUrl.trim() : (
      '${creds.serverBase}/get.php?username=${Uri.encodeQueryComponent(creds.username)}&password=${Uri.encodeQueryComponent(creds.password)}&type=m3u_plus'
    );
    await persistAutoLoginAsManualXtream(_storage, playlistUrl);
    await _storage.write('saved_login_username', creds.username);
    await _storage.write('saved_login_password', creds.password);
    await _storage.write('activation_domain', domain);
    await _storage.write('activation_auto_domain', domain);
    await _storage.write('activation_auto_username', creds.username);
    await _storage.write('activation_auto_password', creds.password);
    await _storage.write('activation_auto_enabled', true);
    await _storage.write(kStorageFillManualFromM3u, true);
    await _storage.remove(kStorageSuppressPlaylistAutoLogin);
    await _storage.remove('activation_just_added_playlist');

    var deviceId = await _activationApi.getDeviceId();
    if (deviceId.isNotEmpty) {
      await _activationApi.bindAccountToDevice(
        deviceId: deviceId,
        username: creds.username,
        password: creds.password,
        serverHost: domain,
        displayName: _playlistDisplayName,
      );
    }

    if (!mounted) return;
    _awaitingLogin = true;
    // يجب أن ينجح player_api / جلب M3U — وإلا AuthFailed + toast check_credentials.
    context.read<AuthBloc>().add(
      AuthUsePlaylist(playlistUrl, displayName: _playlistDisplayName),
    );
  }

  Future<void> _pickLocalPlaylist() async {
    if (_isLoading) return;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['m3u', 'm3u8'],
      );
      if (!mounted) return;
      if (file == null) return;
      var path = (file.path ?? '').trim();
      if (path.isEmpty) {
        final bytes = await file.readAsBytes();
        final dir = await getTemporaryDirectory();
        final safeName = file.name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
        final out = File(
          '${dir.path}/playlist_${DateTime.now().millisecondsSinceEpoch}_$safeName',
        );
        await out.writeAsBytes(bytes, flush: true);
        path = out.path;
      }
      if (!mounted) return;
      setState(() {
        _pickedFilePath = path;
        _pickedFileName = file.name;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text =
              file.name.replaceAll(RegExp(r'\.(m3u8?|M3U8?)$'), '');
        }
      });
    } catch (_) {
      if (!mounted) return;
      showWarningToast(
        context,
        'add_playlist_page_title'.tr,
        'add_playlist_file_unavailable'.tr,
      );
    }
  }

  Future<void> _submit() async {
    final activationStatus =
        (_storage.read('activation_status') ?? '').toString();
    if (showActivationLoginDeniedToast(context, activationStatus)) {
      return;
    }

    late final String url;
    final isLocalFile = _source == _AddPlaylistSource.file;

    if (isLocalFile) {
      final path = (_pickedFilePath ?? '').trim();
      if (path.isEmpty) {
        showWarningToast(
          context,
          'add_playlist_page_title'.tr,
          'add_playlist_pick_file'.tr,
        );
        return;
      }
      url = Uri.file(path).toString();
    } else {
      url = _urlController.text.trim();
    if (url.isEmpty) {
      showWarningToast(
        context,
        'add_playlist_page_title'.tr,
        'add_playlist_invalid_url'.tr,
      );
      return;
    }
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      showWarningToast(
        context,
        'add_playlist_page_title'.tr,
        'add_playlist_invalid_url'.tr,
      );
      return;
    }
    }

    setState(() => _isLoading = true);

    final deviceId = await _activationApi.getDeviceId();
    if (deviceId.isEmpty) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showWarningToast(
        context,
        'add_playlist_page_title'.tr,
        'add_playlist_try_again'.tr,
      );
      return;
    }

    if (!isLocalFile) {
    final result = await _activationApi.savePlaylistUrl(deviceId, url);
    final success = result['success'] == true;
    if (!success) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final message = (result['message'] as String?) ?? '';
      if (message.contains('Max devices')) {
        showWarningToast(
          context,
          'max_devices_reached_title'.tr,
          'add_playlist_max_devices'.trParams({
            'max': '${result['max_devices'] ?? 1}',
          }),
        );
      } else {
        showWarningToast(
          context,
          'add_playlist_page_title'.tr,
          'add_playlist_try_again'.tr,
        );
      }
      return;
      }
    }

    if (!mounted) return;
    await _prepareLandscapeLoading();
    if (!mounted) return;

    if (!isLocalFile) {
    final creds = parseXtreamCredentialsFromUrl(url);
    if (creds != null) {
        await _loginLikeManualUsernamePassword(creds, originalUrl: url);
      return;
      }
    }

    await _storage.write('activation_auto_enabled', true);
    await _storage.write('activation_auto_domain', url);
    await _storage.write('activation_domain', url);
    await _storage.remove('activation_auto_username');
    await _storage.remove('activation_auto_password');
    await _storage.remove('activation_just_added_playlist');
    await _storage.remove(kStorageSuppressPlaylistAutoLogin);

    if (!mounted) return;
    _awaitingLogin = true;
    context.read<AuthBloc>().add(
      AuthUsePlaylist(url, displayName: _playlistDisplayName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = Get.textTheme.bodyMedium!.copyWith(
      color: Colors.white,
      fontSize: LoginPremiumTypography.input(false),
      fontWeight: FontWeight.bold,
    );

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) async {
        if (!_awaitingLogin) return;
        if (state is AuthLoading) {
          unawaited(lockHomeScreenLandscape());
          return;
        }
        if (state is AuthSuccess) {
          _awaitingLogin = false;
          _leavingToBootstrap = true;
          if (mounted) setState(() => _isLoading = false);
          await lockHomeScreenLandscape();
          await navigateToHomeBootstrap();
          return;
        }
        if (state is AuthFailed) {
          _awaitingLogin = false;
          _leavingToBootstrap = false;
          if (!mounted) return;
          setState(() => _isLoading = false);
          await lockHomeScreenLandscape();
          var deviceId = await _activationApi.getDeviceId();
          await clearLocalFailedPlaylistAutoLogin(_storage);
          if (deviceId.isNotEmpty) {
            await _activationApi.clearPlaylistUrl(deviceId);
          }
          if (!mounted || !context.mounted) return;
          showWarningToast(
            context,
            'add_playlist_page_title'.tr,
            'check_credentials'.tr,
          );
        }
      },
      child: PopScope(
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
          body: Builder(
            builder: (context) {
              final isTvDevice = isTv(context);
              final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
              final keyboardOpen = !isTvDevice && keyboardInset > 40;

              return Stack(
                fit: StackFit.expand,
                children: [
                  const _LoginEntryPremiumBackground(),
                  SafeArea(
                    child: IgnorePointer(
                      ignoring: _isLoading,
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
                                      final brand = _AddPlaylistBrandPane(
                                        isTvDevice: isTvDevice,
                                        compact: constraints.maxWidth < 720 ||
                                            compactH ||
                                            keyboardOpen ||
                                            sideKb,
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
                                          SizedBox(
                                            width: isTvDevice ? 28 : 18,
                                          ),
                                          Expanded(
                                            flex: sideKb ? 55 : 65,
                                            child: ExcludeFocus(
                                              excluding: sideKb,
                                              child: Align(
                                                alignment: Alignment.center,
                                                child: _buildM3uFormCard(
                                                  isTvDevice: isTvDevice,
                                                  isLoading: _isLoading,
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
                  ),
                  if (_isLoading)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: kColorPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildM3uFormCard({
    required bool isTvDevice,
    required bool isLoading,
    required TextStyle style,
    required double maxHeight,
    bool hideTitle = false,
  }) {
    final fileMode = _source == _AddPlaylistSource.file;
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
          'add_playlist_form_title'.tr,
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
          controller: _nameController,
          focusNode: _nameFocus,
          readOnly: !_nameEditing,
          showCursor: _nameEditing,
          enableInteractiveSelection: _nameEditing,
          keyboardType: isTvDevice ? TextInputType.none : TextInputType.text,
          decoration: _addPlaylistFieldDecoration(
            hint: 'add_playlist_name_hint'.tr,
            icon: LucideIcons.badge_check,
            isTvDevice: isTvDevice,
            dense: dense,
            highlighted: _nameEditing,
          ),
          style: fieldStyle,
          onTap: () => _startEditing(_nameFocus, (v) => _nameEditing = v),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            _stopAllFieldEditing();
            _fileSourceFocus.requestFocus();
          },
        ),
      ),
      SizedBox(height: gap),
      Row(
        children: [
                Expanded(
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: _AddPlaylistSourceRadio(
                focusNode: _fileSourceFocus,
                selected: fileMode,
                label: 'add_playlist_source_file'.tr,
                isTvDevice: isTvDevice,
                onTap: () => setState(() => _source = _AddPlaylistSource.file),
              ),
            ),
          ),
          SizedBox(width: isTvDevice ? 18 : 12),
          Expanded(
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: _AddPlaylistSourceRadio(
                focusNode: _urlSourceFocus,
                selected: !fileMode,
                label: 'add_playlist_source_url'.tr,
                isTvDevice: isTvDevice,
                onTap: () => setState(() => _source = _AddPlaylistSource.url),
              ),
            ),
          ),
        ],
      ),
      SizedBox(height: gap),
      if (fileMode) ...[
        FocusTraversalOrder(
          order: const NumericFocusOrder(5),
          child: _AddPlaylistFocusChip(
            focusNode: _browseFocus,
            borderRadius: 14,
            onTap: _isLoading ? null : _pickLocalPlaylist,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                vertical: isTvDevice ? 14 : 12,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [kColorPrimaryDark, kColorPrimary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kColorPrimary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                  Icon(
                    LucideIcons.folder_open,
                    color: Colors.black87,
                    size: isTvDevice ? 18 : 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'add_playlist_browse'.tr,
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                      fontSize: isTvDevice ? 15 : 14,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if ((_pickedFileName ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            _pickedFileName!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: isTvDevice ? 13 : 12,
            ),
          ),
        ],
      ] else
        FocusTraversalOrder(
          order: const NumericFocusOrder(5),
          child: TextField(
            controller: _urlController,
            focusNode: _urlFieldFocus,
            readOnly: !_urlEditing,
            showCursor: _urlEditing,
            enableInteractiveSelection: _urlEditing,
            keyboardType: isTvDevice ? TextInputType.none : TextInputType.url,
            autocorrect: false,
            decoration: _addPlaylistFieldDecoration(
              hint: 'add_playlist_hint'.tr,
              icon: LucideIcons.link_2,
              isTvDevice: isTvDevice,
              dense: dense,
              highlighted: _urlEditing,
            ),
            style: fieldStyle,
            onTap: () => _startEditing(_urlFieldFocus, (v) => _urlEditing = v),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              _stopAllFieldEditing();
              _submitFocus.requestFocus();
            },
          ),
        ),
    ];

    final submitBtn = FocusTraversalOrder(
      order: const NumericFocusOrder(6),
      child: _AddPlaylistFocusChip(
        focusNode: _submitFocus,
        borderRadius: 14,
        onTap: isLoading ? null : _submit,
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
                    LucideIcons.plus,
                    size: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'add_playlist_add_btn'.tr.toUpperCase(),
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
              submitBtn,
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _addPlaylistFieldDecoration({
  required String hint,
  required IconData icon,
  required bool isTvDevice,
  Widget? suffixIcon,
  bool dense = false,
  bool highlighted = false,
}) {
  final vPad = dense
      ? (isTvDevice ? 11.0 : 9.0)
      : (isTvDevice ? 16.0 : 14.0);
  final activeBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(dense ? 12 : 14),
    borderSide: BorderSide(color: kColorFocus, width: highlighted ? 2.2 : 1.6),
  );
  return InputDecoration(
    isDense: dense,
    hintText: hint,
    hintStyle: TextStyle(
      color: Colors.white.withValues(alpha: 0.42),
      fontSize: dense
          ? (isTvDevice ? 13.5 : 12.5)
          : (isTvDevice ? 15 : 13),
    ),
    prefixIcon: Icon(
      icon,
      color: highlighted ? kColorFocus : kColorPrimary,
      size: dense ? (isTvDevice ? 18 : 16) : (isTvDevice ? 20 : 18),
    ),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: highlighted
        ? kColorFocus.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.28),
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: vPad),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(dense ? 12 : 14),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    ),
    enabledBorder: highlighted
        ? activeBorder
        : OutlineInputBorder(
            borderRadius: BorderRadius.circular(dense ? 12 : 14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
    focusedBorder: activeBorder,
  );
}

class _AddPlaylistBrandPane extends StatelessWidget {
  const _AddPlaylistBrandPane({
    required this.isTvDevice,
    required this.compact,
    this.subtitleKey = 'add_playlist_sub',
    this.hideSubtitle = false,
  });

  final bool isTvDevice;
  final bool compact;
  final String subtitleKey;
  final bool hideSubtitle;

  @override
  Widget build(BuildContext context) {
    final logo = hideSubtitle
        ? (isTvDevice ? 72.0 : 56.0)
        : (isTvDevice ? 92.0 : (compact ? 64.0 : 78.0));
    return Column(
      mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
          width: logo,
          height: logo,
                                    decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: kColorPrimary.withValues(alpha: 0.28),
                blurRadius: 28,
                spreadRadius: 1,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image(
            image: const AssetImage(kIconSplash),
            fit: BoxFit.cover,
            width: logo,
            height: logo,
          ),
        ),
        SizedBox(height: hideSubtitle ? 10 : (isTvDevice ? 16 : 10)),
        Text(
          kAppName.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: hideSubtitle
                ? (isTvDevice ? 16 : 14)
                : (isTvDevice ? 20 : 16),
          ),
        ),
        if (!hideSubtitle) ...[
          SizedBox(height: isTvDevice ? 8 : 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24),
            child: Text(
              subtitleKey.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: isTvDevice ? 14 : 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AddPlaylistSourceRadio extends StatelessWidget {
  const _AddPlaylistSourceRadio({
    required this.focusNode,
    required this.selected,
    required this.label,
    required this.isTvDevice,
    required this.onTap,
  });

  final FocusNode focusNode;
  final bool selected;
  final String label;
  final bool isTvDevice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _AddPlaylistFocusChip(
      focusNode: focusNode,
      borderRadius: 12,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: isTvDevice ? 10 : 8,
          horizontal: 4,
        ),
        child: Row(
          children: [
            Container(
              width: isTvDevice ? 22 : 18,
              height: isTvDevice ? 22 : 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? kColorPrimary : Colors.white70,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: isTvDevice ? 10 : 8,
                        height: isTvDevice ? 10 : 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                                      color: kColorPrimary,
                                    ),
                                  ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: isTvDevice ? 14 : 13,
                  letterSpacing: 0.3,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
      ),
    );
  }
}

class _AddPlaylistFocusChip extends StatefulWidget {
  const _AddPlaylistFocusChip({
    required this.child,
    required this.focusNode,
    this.onTap,
    this.borderRadius = 12,
  });

  final Widget child;
  final FocusNode focusNode;
  final VoidCallback? onTap;
  final double borderRadius;

  @override
  State<_AddPlaylistFocusChip> createState() => _AddPlaylistFocusChipState();
}

class _AddPlaylistFocusChipState extends State<_AddPlaylistFocusChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: kColorFocus.withValues(alpha: 0.1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _focused ? kColorFocus : Colors.transparent,
                width: 2.2,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: kColorFocus.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// كlavier TV على يسار الشاشة (بدل IME النظام).
class _LoginTvSideKeyboard extends StatefulWidget {
  const _LoginTvSideKeyboard({
    required this.seedFocus,
    required this.onChar,
    required this.onBackspace,
    required this.onPrimary,
    required this.onDismiss,
    this.showNext = false,
  });

  final FocusNode seedFocus;
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onPrimary;
  final VoidCallback onDismiss;
  final bool showNext;

  @override
  State<_LoginTvSideKeyboard> createState() => _LoginTvSideKeyboardState();
}

class _LoginTvSideKeyboardState extends State<_LoginTvSideKeyboard> {
  int _page = 0;
  bool _shift = false;

  static const _letterRows = <List<String>>[
    ['a', 'z', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['q', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'm'],
    ['w', 'x', 'c', 'v', 'b', 'n'],
  ];

  static const _symbolRows1 = <List<String>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['@', '#', r'$', '_', '&', '-', '+', '(', ')', '/'],
    ['*', '"', "'", ':', ';', '!', '?', '\\', '%', '='],
  ];

  static const _symbolRows2 = <List<String>>[
    ['~', '`', '|', '•', '√', 'π', '÷', '×', '¶', '∆'],
    ['£', '€', '¥', '¢', '^', '°', '=', '{', '}', '\\'],
    ['©', '®', '™', '✓', '[', ']', '<', '>', '«', '»'],
  ];

  List<List<String>> get _rows {
    switch (_page) {
      case 1:
        return _symbolRows1;
      case 2:
        return _symbolRows2;
      default:
        return _letterRows;
    }
  }

  String get _modeToggleLabel {
    switch (_page) {
      case 1:
        return r'=\<';
      case 2:
        return 'ABC';
      default:
        return '?123';
    }
  }

  void _cycleMode() {
    setState(() {
      if (_page == 0) {
        _page = 1;
      } else if (_page == 1) {
        _page = 2;
      } else {
        _page = 0;
      }
      _shift = false;
    });
  }

  Widget _key({
    required String label,
    required VoidCallback onTap,
    FocusNode? focusNode,
    int flex = 1,
    bool accent = false,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: Focus(
          focusNode: focusNode,
          onKeyEvent: (node, event) {
            if (event is KeyUpEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack ||
                    event.logicalKey == LogicalKeyboardKey.browserBack)) {
              return KeyEventResult.handled;
            }
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter) {
              onTap();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.escape ||
                key == LogicalKeyboardKey.goBack ||
                key == LogicalKeyboardKey.browserBack) {
              widget.onDismiss();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              final bg = focused
                  ? kColorPrimary.withValues(alpha: 0.95)
                  : accent
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.07);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    alignment: Alignment.center,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: bg,
                      border: Border.all(
                        color: focused
                            ? kColorPrimary
                            : kColorPrimary.withValues(alpha: 0.35),
                        width: focused ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: focused ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: label.length > 3 ? 11 : 13,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final primaryLabel =
        widget.showNext ? 'tv_kb_next'.tr : 'tv_kb_done'.tr;
    return FocusScope(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF0E1118).withValues(alpha: 0.92),
          border: Border.all(
            color: kColorPrimary.withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows.length; r++)
                Row(
                  children: [
                    if (_page == 0 && r == 2)
                      _key(
                        label: '⇧',
                        accent: _shift,
                        onTap: () => setState(() => _shift = !_shift),
                      ),
                    for (var i = 0; i < rows[r].length; i++)
                      _key(
                        focusNode: r == 0 && i == 0 ? widget.seedFocus : null,
                        label: _page == 0 && _shift
                            ? rows[r][i].toUpperCase()
                            : rows[r][i],
                        onTap: () {
                          final ch = rows[r][i];
                          widget.onChar(
                            _page == 0 && _shift ? ch.toUpperCase() : ch,
                          );
                          if (_shift) setState(() => _shift = false);
                        },
                      ),
                    if (_page == 0 && r == 2)
                      _key(
                        label: '⌫',
                        accent: true,
                        onTap: widget.onBackspace,
                              ),
                            ],
                          ),
              if (_page != 0)
                Row(
                  children: [
                    for (final ch in ['.', ',', '?', '!', "'", '"', '-', '@'])
                      _key(
                        label: ch,
                        onTap: () => widget.onChar(ch),
                        ),
                      ],
                    ),
              Row(
                children: [
                  _key(
                    label: _modeToggleLabel,
                    accent: true,
                    flex: 2,
                    onTap: _cycleMode,
                  ),
                  if (_page != 0)
                    _key(
                      label: 'ABC',
                      accent: true,
                      flex: 2,
                      onTap: () => setState(() {
                        _page = 0;
                        _shift = false;
                      }),
                    ),
                  if (_page == 0)
                    _key(
                      label: ',',
                      onTap: () => widget.onChar(','),
                    ),
                  _key(
                    label: 'tv_kb_space'.tr,
                    flex: _page == 0 ? 5 : 4,
                    onTap: () => widget.onChar(' '),
                  ),
                  if (_page == 0)
                    _key(
                      label: '.',
                      onTap: () => widget.onChar('.'),
                    ),
                  if (_page != 0)
                    _key(
                      label: '⌫',
                      accent: true,
                      flex: 2,
                      onTap: widget.onBackspace,
                    ),
                  _key(
                    label: primaryLabel,
                    accent: true,
                    flex: 2,
                    onTap: widget.onPrimary,
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }
}
