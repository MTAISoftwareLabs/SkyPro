part of '../screens.dart';

/// هالة تركيز موحّدة بألوان الثيم (إعدادات — هاتف وتلفاز).
List<BoxShadow> settingsThemedFocusGlow(bool focused) {
  if (!focused || kReduceFocusMotion) return const [];
  return [
    BoxShadow(
      color: kColorPrimary.withValues(alpha: 0.55),
      blurRadius: 22,
      spreadRadius: 2,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: kColorPrimary.withValues(alpha: 0.3),
      blurRadius: 34,
      spreadRadius: 5,
      offset: const Offset(0, 4),
    ),
  ];
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with LandscapeMainAppStateMixin<SettingsScreen>, ParentalSectionGateMixin {
  @override
  ParentalSection get parentalGateSection => ParentalSection.settings;

  @override
  void initState() {
    super.initState();
    settingsArmInitialBackFocus();
    FocusManager.instance.addListener(_onGlobalFocusChanged);
  }

  @override
  void dispose() {
    settingsDisarmInitialBackFocus();
    FocusManager.instance.removeListener(_onGlobalFocusChanged);
    super.dispose();
  }

  void _onGlobalFocusChanged() {
    if (!mounted || !isTv(context)) return;
    settingsEnsureFocusedVisible();
  }

  @override
  Widget build(BuildContext context) {
    return buildWithParentalGate(_buildSettings(context));
  }

  Widget _buildSettings(BuildContext context) {
    // زر الرجوع للنظام: لا نمنع الرجوع لمجرد وجود تركيز على عنصر (ذلك كان يعطّل الرجوع
    // على الهاتف). نمنع الخروج فقط عندما تكون لوحة المفاتيح مفتوحة — الضغطة الأولى تغلقها.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return wrapAppDirectionality(
      child: PopScope(
        canPop: !keyboardOpen,
        onPopInvokedWithResult: (bool didPop, dynamic result) {
          if (!didPop) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
        },
        child: Scaffold(
          body: Ink(
            width: 100.w,
            height: 100.h,
            decoration: kDecorBackground,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(3.5.w, 0.8.h, 3.5.w, 1.h),
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final UserModel? userInfo =
                        state is AuthSuccess ? state.user : null;

                    // مجموعة تركيز واحدة لكل الصفحة: رجوع + محتوى + تسجيل خروج.
                    return wrapSettingsTvFocusTraversal(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AppBarSettings(tvBackFocusOrder: 0),
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: _SettingsContent(
                                userInfo: userInfo,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          settingsTvTraversalOrder(
                            context,
                            order: 100,
                            child: _LogoutButton(),
                          ),
                        ],
                      ),
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

class _SettingsContent extends StatefulWidget {
  const _SettingsContent({this.userInfo});

  final UserModel? userInfo;

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent> {
  final FocusNode _privacyFocusNode = FocusNode();
  final FocusNode _aboutFocusNode = FocusNode();
  final FocusNode _contactFocusNode = FocusNode();
  final FocusNode _autoPlayNextFocusNode = FocusNode();
  final FocusNode _subtitleLangFocusNode = FocusNode();
  final FocusNode _subtitleStyleFocusNode = FocusNode();
  final FocusNode _rememberLastChannelFocusNode = FocusNode();
  final FocusNode _pushNotificationsFocusNode = FocusNode();
  final FocusNode _themePickerFocusNode = FocusNode();
  final FocusNode _perfModeFocusNode = FocusNode();
  final FocusNode _exoSoftwareFocusNode = FocusNode();
  final FocusNode _streamFormatFocusNode = FocusNode();
  final FocusNode _feedbackFocusNode = FocusNode();
  bool _privacyFocused = false;
  bool _aboutFocused = false;
  bool _contactFocused = false;
  bool _autoPlayNextFocused = false;
  bool _subtitleLangFocused = false;
  bool _subtitleStyleFocused = false;
  bool _rememberLastChannelFocused = false;
  bool _pushNotificationsFocused = false;
  bool _themePickerFocused = false;
  bool _perfModeFocused = false;
  bool _feedbackFocused = false;
  bool _epgUpdating = false;
  double _epgProgress = 0;

  Future<void> _openSupportContact() async {
    final link =
        (GetStorage().read('support_contact_url') ?? '').toString().trim();
    if (link.isEmpty) {
      if (!mounted) return;
      showWarningToast(context, 'notice_title'.tr, 'contact_not_configured'.tr);
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) {
      if (!mounted) return;
      showWarningToast(context, 'notice_title'.tr, 'contact_not_configured'.tr);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openPrivacyPolicy() async {
    final box = GetStorage();
    final mode =
        (box.read('privacy_policy_mode') ?? 'url').toString().toLowerCase();
    String? html;
    String? url;

    if (mode == 'html') {
      html = (box.read('privacy_policy_html') ?? '').toString().trim();
      if (html.isEmpty) {
        showWarningToast(context, 'notice_title'.tr, 'legal_not_configured'.tr);
        return;
      }
    } else {
      url = (box.read('privacy_policy_url') ?? '').toString().trim();
      if (url.isEmpty) {
        showWarningToast(context, 'notice_title'.tr, 'legal_not_configured'.tr);
        return;
      }
      final uri = Uri.tryParse(url);
      final urlOk =
          uri != null &&
          uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https');
      if (!urlOk) {
        html = '<p>${'legal_invalid_link'.tr}</p>';
        url = null;
      }
    }

    // نفس نافذة «من نحن» — على التلفاز والهاتف.
    await showLegalContentDialog(
      context,
      title: 'privacy_policy_title'.tr,
      html: html,
      url: url,
    );
    if (!mounted) return;
    settingsRestoreFocusIfTv(context, _privacyFocusNode);
  }

  Future<void> _openAboutUs() async {
    final html = (GetStorage().read('about_us_html') ?? '').toString().trim();
    if (html.isEmpty) {
      showWarningToast(context, 'notice_title'.tr, 'about_not_configured'.tr);
      return;
    }
    await showAboutUsDialog(context, html: html);
    if (!mounted) return;
    settingsRestoreFocusIfTv(context, _aboutFocusNode);
  }

  VoidCallback _legalTapHandler(FocusNode focusNode, VoidCallback action) {
    return () {
      settingsReleaseTouchFocus(context);
      focusNode.unfocus();
      action();
    };
  }

  Future<void> _openFeedbackDialog() async {
    final String? note;
    if (isTv(context)) {
      note = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => const _SettingsFeedbackDialog(),
      );
    } else {
      // هاتف (أفقي): ورقة سفلية تبقى فوق الكيبورد بدل Dialog يخرج من الشاشة.
      note = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useSafeArea: true,
        builder: (ctx) => const _SettingsFeedbackSheet(),
      );
    }
    if (note == null || note.trim().isEmpty || !mounted) return;
    try {
      final activationApi = ActivationApi();
      final user = widget.userInfo;
      final playlistUrl = user?.m3uPlaylistUrl;
      final ok = await activationApi.sendClientFeedback(
        note: note.trim(),
        deviceUrl:
            (playlistUrl != null && playlistUrl.isNotEmpty)
                ? playlistUrl
                : user?.serverInfo?.serverUrl,
      );
      if (!mounted) return;
      if (ok) {
        showSoftToast(context, 'settings'.tr, 'feedback_sent_success'.tr);
      } else {
        showWarningToast(context, 'settings'.tr, 'feedback_sent_error'.tr);
      }
    } catch (_) {
      if (!mounted) return;
      showWarningToast(context, 'settings'.tr, 'feedback_sent_error'.tr);
    } finally {
      if (mounted) {
        settingsRestoreFocusIfTv(context, _feedbackFocusNode);
      }
    }
  }

  Future<void> _refreshContentIncremental() async {
    await AppCacheClearer.clearApiAndDisk();
    if (!mounted) return;
    AppCacheClearer.resetSessionBlocs(context);
    AppCacheClearer.prefetchServerCatalog(context);
    showSoftToast(context, 'settings'.tr, 'settings_refresh_content_done'.tr);
  }

  Future<void> _confirmAndRefreshContent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const _RefreshContentConfirmDialog(),
    );
    if (confirmed == true) {
      await _refreshContentIncremental();
    }
  }

  Future<void> _updateEpgFromServer() async {
    if (_epgUpdating) return;
    setState(() {
      _epgUpdating = true;
      _epgProgress = 0.02;
    });

    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthSuccess) {
        if (!mounted) return;
        showWarningToast(
          context,
          'settings_update_epg_failed_title'.tr,
          'settings_update_epg_failed_msg'.tr,
        );
        return;
      }

      final liveCaty = context.read<LiveCatyBloc>();
      var catyState = liveCaty.state;
      if (catyState is! LiveCatySuccess) {
        liveCaty.add(GetLiveCategories());
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (!mounted) return;
          catyState = liveCaty.state;
          if (catyState is LiveCatySuccess || catyState is! LiveCatyLoading) {
            break;
          }
          if (mounted) {
            setState(() => _epgProgress = (0.02 + i * 0.002).clamp(0.0, 0.08));
          }
        }
      }

      final categories =
          catyState is LiveCatySuccess
              ? catyState.categories
              : const <CategoryModel>[];

      final priorityIds = <String>[];
      final favLives = context.read<FavoritesCubit>().state.lives;
      for (final ch in favLives) {
        final id = ch.streamId?.trim() ?? '';
        if (id.isNotEmpty) priorityIds.add(id);
      }
      final watchLives = context.read<WatchingCubit>().state.live;
      for (final w in watchLives) {
        final id = w.streamId.trim();
        if (id.isNotEmpty) priorityIds.add(id);
      }
      final last = LastLiveChannelService.peekResume();
      final lastId = last?.channel.streamId?.trim() ?? '';
      if (lastId.isNotEmpty) priorityIds.add(lastId);

      if (mounted) setState(() => _epgProgress = 0.1);

      final result = await EpgRefreshService.refreshFromServer(
        api: liveCaty.api,
        user: authState.user,
        categories: categories,
        priorityStreamIds: priorityIds,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _epgProgress = p);
        },
      );

      if (!mounted) return;
      if (result.playlistMode) {
        showInfoToast(
          context,
          'settings_update_epg_playlist_title'.tr,
          'settings_update_epg_playlist_msg'.tr,
        );
      } else if (result.hasData) {
        showSoftToast(
          context,
          'settings_update_epg_done_title'.tr,
          'settings_update_epg_done_msg'.trParams({
            'count': '${result.successCount}',
          }),
        );
      } else {
        showWarningToast(
          context,
          'settings_update_epg_empty_title'.tr,
          'settings_update_epg_empty_msg'.tr,
        );
      }
    } catch (_) {
      if (!mounted) return;
      showWarningToast(
        context,
        'settings_update_epg_failed_title'.tr,
        'settings_update_epg_failed_msg'.tr,
      );
    } finally {
      if (mounted) {
        setState(() {
          _epgProgress = 1;
          _epgUpdating = false;
        });
        Future<void>.delayed(const Duration(milliseconds: 320), () {
          if (!mounted || _epgUpdating) return;
          setState(() => _epgProgress = 0);
        });
      }
    }
  }

  Future<void> _showLanguageDialog() async {
    final current = currentAppLanguageCode();
    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => _SettingsChoiceDialog(
            title: 'language'.tr,
            titleIcon: FontAwesomeIcons.language,
            selectedId: current,
            compactItems: true,
            items: [
              for (final lang in kAppUiLanguages)
                _SettingsChoiceItem(
                  id: lang.code,
                  label: lang.nativeName,
                  leading: AppLangFlagIcon(code: lang.code, size: 32),
                ),
            ],
          ),
    );
    if (picked != null && picked != current) {
      setAppLocale(picked);
      if (mounted) setState(() {});
    }
  }

  Future<void> _showDefaultSubtitleLanguageDialog() async {
    final current = SubtitleService.instance.defaultLanguageCode;
    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => _SettingsChoiceDialog(
            title: 'settings_default_subtitle_lang_title'.tr,
            titleIcon: LucideIcons.captions,
            selectedId: current,
            compactItems: true,
            items: [
              for (final lang in SubtitleService.supportedUiLanguages)
                _SettingsChoiceItem(
                  id: lang.key,
                  label: lang.value,
                  leading: _SubtitleLangFlagIcon(code: lang.key),
                ),
            ],
          ),
    );
    if (!mounted) return;
    settingsRestoreFocusIfTv(context, _subtitleLangFocusNode);
    if (picked == null || picked == current) return;
    await SubtitleService.instance.setDefaultLanguageCode(picked);
    if (!mounted) return;
    setState(() {});
    showSoftToast(
      context,
      'settings_default_subtitle_lang_saved'.tr,
      SubtitleService.labelForLanguageCode(picked),
    );
  }

  Future<void> _showSubtitleAppearanceDialog() async {
    final current = SubtitleAppearanceService.instance.load();
    final picked = await showDialog<SubtitleAppearance>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _SubtitleAppearanceDialog(initial: current),
    );
    if (!mounted) return;
    settingsRestoreFocusIfTv(context, _subtitleStyleFocusNode);
    if (picked == null) return;
    await SubtitleAppearanceService.instance.save(picked);
    if (!mounted) return;
    setState(() {});
    showSoftToast(
      context,
      'settings_subtitle_appearance_saved'.tr,
      'settings_subtitle_appearance_saved_msg'.tr,
    );
  }

  Future<void> _showPlayerDialog() async {
    // iOS: المشغّل الوحيد VLC — لا حوار اختيار.
    if (Platform.isIOS) return;
    final current = preferredVideoPlayer == AppVideoPlayer.exo ? 'exo' : 'vlc';
    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => _SettingsChoiceDialog(
            title: 'video_player'.tr,
            titleIcon: FontAwesomeIcons.tv,
            selectedId: current,
            items: [
              _SettingsChoiceItem(
                id: 'vlc',
                label: 'player_vlc'.tr,
                leading: Image.asset(
                  'assets/images/vlc_icon.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
              _SettingsChoiceItem(
                id: 'exo',
                label: 'player_exo'.tr,
                leading: Image.asset(
                  'assets/images/exo_icon.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
    );
    if (picked == null) return;
    if (picked == 'exo') {
      setPreferredVideoPlayer(AppVideoPlayer.exo);
      if (mounted) setState(() {});
    } else if (picked == 'vlc') {
      setPreferredVideoPlayer(AppVideoPlayer.vlc);
      if (mounted) setState(() {});
    }
  }

  String _exoSoftwareDecoderLabel() {
    switch (exoSoftwareDecoderUserChoice()) {
      case 'software':
        return 'software_decoding'.tr;
      case 'hardware':
        return 'hardware_decoding'.tr;
      default:
        return 'exo_software_auto'.trParams({
          'mode': _exoResolvedDecoderModeLabel(),
        });
    }
  }

  String _exoResolvedDecoderModeLabel() {
    return preferExoSoftwareDecoder
        ? 'software_decoding'.tr
        : 'hardware_decoding'.tr;
  }

  IconData _exoSoftwareDecoderValueIcon() {
    switch (exoSoftwareDecoderUserChoice()) {
      case 'software':
        return FontAwesomeIcons.gears;
      case 'hardware':
        return FontAwesomeIcons.microchip;
      default:
        return preferExoSoftwareDecoder
            ? FontAwesomeIcons.gears
            : FontAwesomeIcons.microchip;
    }
  }

  Future<void> _showExoSoftwareDecoderDialog() async {
    if (Platform.isIOS) return;
    final current = exoSoftwareDecoderUserChoice();
    final autoMode = _exoResolvedDecoderModeLabel();

    Widget leadingIcon(IconData icon) {
      return Icon(icon, size: 20, color: kColorPrimary);
    }

    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => _SettingsChoiceDialog(
            title: 'player_setting'.tr,
            titleIcon: FontAwesomeIcons.microchip,
            selectedId: current,
            items: [
              _SettingsChoiceItem(
                id: 'auto',
                label: 'exo_software_auto'.trParams({'mode': autoMode}),
                subtitle: 'exo_software_auto_desc',
                leading: leadingIcon(FontAwesomeIcons.wandMagicSparkles),
              ),
              _SettingsChoiceItem(
                id: 'hardware',
                label: 'hardware_decoding'.tr,
                subtitle: 'exo_software_off_desc',
                leading: leadingIcon(FontAwesomeIcons.microchip),
              ),
              _SettingsChoiceItem(
                id: 'software',
                label: 'software_decoding'.tr,
                subtitle: 'exo_software_on_desc',
                leading: leadingIcon(FontAwesomeIcons.gears),
              ),
            ],
          ),
    );
    if (picked == null || !mounted) return;
    if (picked == current) {
      settingsRestoreFocusIfTv(context, _exoSoftwareFocusNode);
      return;
    }
    setExoSoftwareDecoderUserChoice(picked);
    setState(() {});
    await _promptRestartToApplySetting(_exoSoftwareFocusNode);
  }

  String _streamFormatLabel() {
    switch (preferredXtreamLiveStreamFormat) {
      case XtreamLiveStreamFormat.mpegTs:
        return 'stream_format_mpegts'.tr;
      case XtreamLiveStreamFormat.hls:
        return 'stream_format_hls'.tr;
      case XtreamLiveStreamFormat.defaultFmt:
        return 'stream_format_default'.tr;
    }
  }

  Future<void> _showStreamFormatDialog() async {
    if (Platform.isIOS) return;
    final current = xtreamLiveFormatStorageKey(preferredXtreamLiveStreamFormat);
    Widget leadingIcon(IconData icon) {
      return Icon(icon, size: 20, color: kColorPrimary);
    }

    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => _SettingsChoiceDialog(
            title: 'stream_format'.tr,
            titleIcon: FontAwesomeIcons.film,
            selectedId: current,
            items: [
              _SettingsChoiceItem(
                id: 'default',
                label: 'stream_format_default'.tr,
                subtitle: 'stream_format_default_desc',
                leading: leadingIcon(FontAwesomeIcons.circleDot),
              ),
              _SettingsChoiceItem(
                id: 'ts',
                label: 'stream_format_mpegts'.tr,
                subtitle: 'stream_format_mpegts_desc',
                leading: leadingIcon(FontAwesomeIcons.fileVideo),
              ),
              _SettingsChoiceItem(
                id: 'hls',
                label: 'stream_format_hls'.tr,
                subtitle: 'stream_format_hls_desc',
                leading: leadingIcon(FontAwesomeIcons.water),
              ),
            ],
          ),
    );
    if (picked == null || !mounted) return;
    if (picked == current) {
      settingsRestoreFocusIfTv(context, _streamFormatFocusNode);
      return;
    }
    final format =
        parseXtreamLiveFormatStorage(picked) ?? XtreamLiveStreamFormat.defaultFmt;
    setPreferredXtreamLiveStreamFormat(format);
    setState(() {});
    await _promptRestartToApplySetting(_streamFormatFocusNode);
  }

  /// بعد تغيير Decoder / Stream Format: حوار صغير Restart / Later (TV + هاتف).
  Future<void> _promptRestartToApplySetting(FocusNode restoreFocus) async {
    if (!mounted) return;
    final restart = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => AppRestartConfirmDialog(
            titleKey: 'settings_player_restart_title',
            messageKey: 'settings_player_restart_message',
            onLater: () => Navigator.of(ctx).pop(false),
            onRestart: () => Navigator.of(ctx).pop(true),
          ),
    );
    if (!mounted) return;
    settingsRestoreFocusIfTv(context, restoreFocus);
    if (restart == true) {
      await forceRelaunchApp();
      return;
    }
    showSoftToast(
      context,
      'settings_player_restart_saved'.tr,
      'settings_perf_restart_later_hint'.tr,
    );
  }

  Future<void> _showThemeDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => _ThemeGridDialog(
            selectedId: getActiveHomeThemeKey(),
            themeKeys: _availableThemeKeys(),
            onPick: (key) {
              setActiveHomeThemeKey(key);
              if (mounted) setState(() {});
            },
          ),
    );
    if (!mounted) return;
    settingsRestoreFocusIfTv(context, _themePickerFocusNode);
  }

  Future<void> _showPerfModeDialog() async {
    final current = AppPerf.currentUserChoice();
    final autoLevel = appPerfLevelShortLabel(AppPerf.autoDetectedLevel);
    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => _SettingsChoiceDialog(
            title: 'settings_perf_mode_title'.tr,
            titleIcon: FontAwesomeIcons.gaugeHigh,
            selectedId: current,
            items: [
              _SettingsChoiceItem(
                id: 'auto',
                label: 'settings_perf_mode_auto'.trParams({'level': autoLevel}),
                subtitle: 'settings_perf_mode_auto_desc',
                leading: Icon(FontAwesomeIcons.wandMagicSparkles, color: kColorPrimary, size: 22),
              ),
              _SettingsChoiceItem(
                id: 'lite',
                label: 'settings_perf_mode_lite'.tr,
                subtitle: 'settings_perf_mode_lite_desc',
                leading: Icon(FontAwesomeIcons.leaf, color: kColorPrimary, size: 22),
              ),
              _SettingsChoiceItem(
                id: 'mid',
                label: 'settings_perf_mode_mid'.tr,
                subtitle: 'settings_perf_mode_mid_desc',
                leading: Icon(FontAwesomeIcons.sliders, color: kColorPrimary, size: 22),
              ),
              _SettingsChoiceItem(
                id: 'full',
                label: 'settings_perf_mode_full'.tr,
                subtitle: 'settings_perf_mode_full_desc',
                leading: Icon(FontAwesomeIcons.bolt, color: kColorPrimary, size: 22),
              ),
            ],
          ),
    );
    if (!mounted) return;
    settingsRestoreFocusIfTv(context, _perfModeFocusNode);
    if (picked == null || picked == current) return;
    await applyUserAppPerfChoice(picked);
    if (!mounted) return;
    setState(() {});
    final restart = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => AppRestartConfirmDialog(
            onLater: () => Navigator.of(ctx).pop(false),
            onRestart: () => Navigator.of(ctx).pop(true),
          ),
    );
    if (!mounted) return;
    settingsRestoreFocusIfTv(context, _perfModeFocusNode);
    if (restart == true) {
      await forceRelaunchApp();
      return;
    }
    showSoftToast(
      context,
      'settings_perf_mode_saved'.tr,
      'settings_perf_restart_later_hint'.tr,
    );
  }

  Future<void> _clearAppCache() async {
    try {
      await iptvImageCacheManager.emptyCache();
      clearIptvImageWarmRegistry();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (!mounted) return;
      showSoftToast(context, 'settings'.tr, 'settings_clear_cache_done'.tr);
    } catch (_) {
      if (!mounted) return;
      showWarningToast(
        context,
        'settings'.tr,
        'settings_clear_cache_failed'.tr,
      );
    }
  }

  Widget _preferencesGroup(BuildContext context) {
    final tv = isTv(context);
    return _SettingsGroup(
      titleIcon: FontAwesomeIcons.sliders,
      title: 'settings'.tr,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: _SettingsMiniPicker(
                  icon: FontAwesomeIcons.language,
                  label: 'language'.tr,
                  value: currentAppUiLanguage().nativeName,
                  valueIcon: AppLangFlagIcon(
                    code: currentAppLanguageCode(),
                    size: 16,
                  ),
                  tvFocusOrder: tv ? 2 : null,
                  onTap: _showLanguageDialog,
                ),
              ),
              if (!Platform.isIOS) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _SettingsMiniPicker(
                    icon: FontAwesomeIcons.tv,
                    label: 'video_player'.tr,
                    value:
                        preferredVideoPlayer == AppVideoPlayer.exo
                            ? 'player_exo'.tr
                            : 'player_vlc'.tr,
                    valueIcon: Image.asset(
                      preferredVideoPlayer == AppVideoPlayer.exo
                          ? 'assets/images/exo_icon.png'
                          : 'assets/images/vlc_icon.png',
                      width: 16,
                      height: 16,
                      fit: BoxFit.cover,
                    ),
                    tvFocusOrder: tv ? 3 : null,
                    onTap: _showPlayerDialog,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!Platform.isIOS)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: _SettingsMiniPicker(
                    icon: FontAwesomeIcons.microchip,
                    label: 'player_setting'.tr,
                    value: _exoSoftwareDecoderLabel(),
                    valueIcon: Icon(
                      _exoSoftwareDecoderValueIcon(),
                      size: 16,
                      color: kColorPrimary,
                    ),
                    tvFocusOrder: tv ? 3.5 : null,
                    onTap: _showExoSoftwareDecoderDialog,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SettingsMiniPicker(
                    icon: FontAwesomeIcons.film,
                    label: 'stream_format'.tr,
                    value: _streamFormatLabel(),
                    valueIcon: Icon(
                      FontAwesomeIcons.fileVideo,
                      size: 16,
                      color: kColorPrimary,
                    ),
                    tvFocusOrder: tv ? 3.6 : null,
                    onTap: _showStreamFormatDialog,
                  ),
                ),
              ],
            ),
          ),
        _SettingsPickerTile(
          icon: FontAwesomeIcons.palette,
          label: 'theme_selector_label'.tr,
          value: _themeLabelForKey(getActiveHomeThemeKey()),
          valueIcon: Icon(
            _themeIconForKey(getActiveHomeThemeKey()),
            size: 16,
            color: _themeAccentForKey(getActiveHomeThemeKey()),
          ),
          focusNode: _themePickerFocusNode,
          onFocusChange: (v) {
            if (_themePickerFocused != v) {
              setState(() => _themePickerFocused = v);
            }
          },
          tvFocusOrder: tv ? 4 : null,
          onTap: _showThemeDialog,
        ),
        _SettingsPickerTile(
          icon: FontAwesomeIcons.gaugeHigh,
          label: 'settings_perf_mode'.tr,
          value: appPerfEffectiveLabel(),
          valueIcon: Icon(
            FontAwesomeIcons.gaugeHigh,
            size: 16,
            color: kColorPrimary,
          ),
          focusNode: _perfModeFocusNode,
          onFocusChange: (v) {
            if (_perfModeFocused != v) {
              setState(() => _perfModeFocused = v);
            }
          },
          tvFocusOrder: tv ? 4.5 : null,
          onTap: _showPerfModeDialog,
        ),
        if (pushNotificationsSettingAvailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
            child: Row(
              children: [
                Expanded(
                  child: _CompactAutoPlayTile(
                    focusNode: _autoPlayNextFocusNode,
                    focused: _autoPlayNextFocused,
                    onFocusChange: (v) {
                      if (_autoPlayNextFocused != v) {
                        setState(() => _autoPlayNextFocused = v);
                      }
                    },
                    tvFocusOrder: tv ? 5 : null,
                    value: autoPlayNextEnabled,
                    onChanged: (v) {
                      setAutoPlayNextEnabled(v);
                      setState(() {});
                      if (v) {
                        showSoftToast(
                          context,
                          'settings_auto_play_next_enabled_title'.tr,
                          'settings_auto_play_next_enabled_msg'.tr,
                        );
                      } else {
                        showInfoToast(
                          context,
                          'settings_auto_play_next_disabled_title'.tr,
                          'settings_auto_play_next_disabled_msg'.tr,
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _CompactPushTile(
                    focusNode: _pushNotificationsFocusNode,
                    focused: _pushNotificationsFocused,
                    onFocusChange: (v) {
                      if (_pushNotificationsFocused != v) {
                        setState(() => _pushNotificationsFocused = v);
                      }
                    },
                    tvFocusOrder: tv ? 6 : null,
                    value:
                        PushNotificationService.instance.userNotificationsEnabled,
                    onChanged: (v) async {
                      final osGranted = await PushNotificationService.instance
                          .setUserNotificationsEnabled(v);
                      if (!context.mounted) return;
                      setState(() {});
                      if (!v) {
                        showInfoToast(
                          context,
                          'settings_push_notifications_disabled_title'.tr,
                          'settings_push_notifications_disabled_msg'.tr,
                        );
                        return;
                      }
                      if (osGranted) {
                        showSoftToast(
                          context,
                          'settings_push_notifications_enabled_title'.tr,
                          'settings_push_notifications_enabled_msg'.tr,
                        );
                      } else {
                        // رفض النظام: التطبيق يكمل بلا إشعارات — بدون فتح Settings.
                        showInfoToast(
                          context,
                          'settings_push_notifications_os_denied_title'.tr,
                          'settings_push_notifications_os_denied_msg'.tr,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
            child: _CompactAutoPlayTile(
              focusNode: _autoPlayNextFocusNode,
              focused: _autoPlayNextFocused,
              onFocusChange: (v) {
                if (_autoPlayNextFocused != v) {
                  setState(() => _autoPlayNextFocused = v);
                }
              },
              tvFocusOrder: tv ? 5 : null,
              value: autoPlayNextEnabled,
              onChanged: (v) {
                setAutoPlayNextEnabled(v);
                setState(() {});
                if (v) {
                  showSoftToast(
                    context,
                    'settings_auto_play_next_enabled_title'.tr,
                    'settings_auto_play_next_enabled_msg'.tr,
                  );
                } else {
                  showInfoToast(
                    context,
                    'settings_auto_play_next_disabled_title'.tr,
                    'settings_auto_play_next_disabled_msg'.tr,
                  );
                }
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          child: Row(
            children: [
              Expanded(
                child: _CompactSubtitleLangTile(
                  focusNode: _subtitleLangFocusNode,
                  focused: _subtitleLangFocused,
                  onFocusChange: (v) {
                    if (_subtitleLangFocused != v) {
                      setState(() => _subtitleLangFocused = v);
                    }
                  },
                  tvFocusOrder: tv ? 7 : null,
                  languageCode: SubtitleService.instance.defaultLanguageCode,
                  onTap: _showDefaultSubtitleLanguageDialog,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactSubtitleStyleTile(
                  focusNode: _subtitleStyleFocusNode,
                  focused: _subtitleStyleFocused,
                  onFocusChange: (v) {
                    if (_subtitleStyleFocused != v) {
                      setState(() => _subtitleStyleFocused = v);
                    }
                  },
                  tvFocusOrder: tv ? 7.5 : null,
                  appearance: SubtitleAppearanceService.instance.load(),
                  onTap: _showSubtitleAppearanceDialog,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          child: Row(
            children: [
              Expanded(
                child: _EpgUpdateChip(
                  progress: _epgProgress,
                  loading: _epgUpdating,
                  tvFocusOrder: tv ? 8 : null,
                  onTap: _updateEpgFromServer,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactRememberLastChannelTile(
                  focusNode: _rememberLastChannelFocusNode,
                  focused: _rememberLastChannelFocused,
                  onFocusChange: (v) {
                    if (_rememberLastChannelFocused != v) {
                      setState(() => _rememberLastChannelFocused = v);
                    }
                  },
                  tvFocusOrder: tv ? 9 : null,
                  value: rememberLastChannelEnabled,
                  onChanged: (v) {
                    LastLiveChannelService.setEnabled(v);
                    setState(() {});
                    if (v) {
                      showSoftToast(
                        context,
                        'settings_remember_last_channel_enabled_title'.tr,
                        'settings_remember_last_channel_enabled_msg'.tr,
                      );
                    } else {
                      showInfoToast(
                        context,
                        'settings_remember_last_channel_disabled_title'.tr,
                        'settings_remember_last_channel_disabled_msg'.tr,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: _OptionChip(
                  icon: FontAwesomeIcons.arrowsRotate,
                  label: 'settings_refresh_content'.tr,
                  isSelected: false,
                  tvFocusOrder: tv ? 10 : null,
                  onTap: _confirmAndRefreshContent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OptionChip(
                  icon: FontAwesomeIcons.broomBall,
                  label: 'settings_clear_cache'.tr,
                  isSelected: false,
                  tvFocusOrder: tv ? 11 : null,
                  onTap: _clearAppCache,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: _OptionChip(
            icon: FontAwesomeIcons.gaugeHigh,
            label: 'settings_speed_test'.tr,
            isSelected: false,
            tvFocusOrder: tv ? 12 : null,
            onTap: () {
              showDialog<void>(
                context: context,
                barrierDismissible: true,
                builder: (_) => const _SpeedTestDialog(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _legalButtonsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: _LegalCompactButton(
              tvTraversalOrder: 40,
              focusNode: _privacyFocusNode,
              focused: _privacyFocused,
              onFocusChange: (v) {
                if (_privacyFocused != v) {
                  setState(() => _privacyFocused = v);
                }
              },
              icon: FontAwesomeIcons.fileShield,
              label: 'privacy_policy_title'.tr,
              onTap: _legalTapHandler(_privacyFocusNode, _openPrivacyPolicy),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LegalCompactButton(
              tvTraversalOrder: 41,
              focusNode: _aboutFocusNode,
              focused: _aboutFocused,
              onFocusChange: (v) {
                if (_aboutFocused != v) {
                  setState(() => _aboutFocused = v);
                }
              },
              icon: FontAwesomeIcons.circleInfo,
              label: 'about_us_title'.tr,
              onTap: _legalTapHandler(_aboutFocusNode, _openAboutUs),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LegalCompactButton(
              tvTraversalOrder: 42,
              focusNode: _contactFocusNode,
              focused: _contactFocused,
              onFocusChange: (v) {
                if (_contactFocused != v) {
                  setState(() => _contactFocused = v);
                }
              },
              icon: FontAwesomeIcons.headset,
              label: 'contact_support'.tr,
              onTap: _legalTapHandler(_contactFocusNode, _openSupportContact),
            ),
          ),
        ],
      ),
    );
  }

  /// زر ربط جهاز مستقل تحت مجموعة الإعدادات (هاتف فقط) لملء المساحة الفارغة.
  Widget _phoneLinkDeviceButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            settingsReleaseTouchFocus(context);
            Get.to(() => const AddDeviceScreen());
          },
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  kColorPrimary.withValues(alpha: 0.22),
                  kColorPrimary.withValues(alpha: 0.10),
                ],
              ),
              border: Border.all(color: kColorPrimary.withValues(alpha: 0.42)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: kColorPrimary.withValues(alpha: 0.2),
                      border: Border.all(
                        color: kColorPrimary.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Icon(
                      FontAwesomeIcons.qrcode,
                      size: 15,
                      color: kColorPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'settings_tv_add_device_btn'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Get.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'settings_tv_login_title'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Get.textTheme.bodySmall?.copyWith(
                            color: Colors.white60,
                            fontWeight: FontWeight.w500,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? FontAwesomeIcons.chevronLeft
                        : FontAwesomeIcons.chevronRight,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _moreGroup(BuildContext context, {required bool includeFeedback}) {
    return _SettingsGroup(
      titleIcon: FontAwesomeIcons.ellipsis,
      title: 'settings_legal_section'.tr,
      children: [
        if (includeFeedback)
          _SettingsActionTile(
            icon: FontAwesomeIcons.commentDots,
            label: 'feedback_section_title'.tr,
            subtitle: 'feedback_section_desc'.tr,
            focusNode: _feedbackFocusNode,
            onFocusChange: (v) {
              if (_feedbackFocused != v) {
                setState(() => _feedbackFocused = v);
              }
            },
            onTap: _openFeedbackDialog,
          ),
        _legalButtonsRow(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final wide = MediaQuery.sizeOf(context).width >= 900 || tv;
    final showPhoneLinkDevice = !tv;

    // التركيز يُدار من الحاوية الخارجية في SettingsScreen (ريموت سلس لكل الصفحة).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccountCard(userInfo: widget.userInfo),
        const SizedBox(height: 10),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _preferencesGroup(context),
                    if (showPhoneLinkDevice) ...[
                      const SizedBox(height: 10),
                      _phoneLinkDeviceButton(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ParentalControlSettingsCard(
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _moreGroup(context, includeFeedback: !tv),
                  ],
                ),
              ),
            ],
          )
        else ...[
          _preferencesGroup(context),
          if (showPhoneLinkDevice) ...[
            const SizedBox(height: 10),
            _phoneLinkDeviceButton(),
          ],
          const SizedBox(height: 10),
          _ParentalControlSettingsCard(onChanged: () => setState(() {})),
          const SizedBox(height: 10),
          _moreGroup(context, includeFeedback: !tv),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  @override
  void dispose() {
    _privacyFocusNode.dispose();
    _aboutFocusNode.dispose();
    _contactFocusNode.dispose();
    _autoPlayNextFocusNode.dispose();
    _subtitleLangFocusNode.dispose();
    _subtitleStyleFocusNode.dispose();
    _rememberLastChannelFocusNode.dispose();
    _pushNotificationsFocusNode.dispose();
    _themePickerFocusNode.dispose();
    _perfModeFocusNode.dispose();
    _exoSoftwareFocusNode.dispose();
    _streamFormatFocusNode.dispose();
    _feedbackFocusNode.dispose();
    super.dispose();
  }
}

/// أيقونة لغة الترجمة: علم لكل لغة.
class _SubtitleLangFlagIcon extends StatelessWidget {
  const _SubtitleLangFlagIcon({required this.code});

  final String code;
  static const double _size = 32;

  static String _flagEmojiFor(String code) {
    switch (code.trim().toLowerCase()) {
      case 'ar':
        return '🇸🇦';
      case 'en':
        return '🇬🇧';
      case 'fr':
        return '🇫🇷';
      case 'es':
        return '🇪🇸';
      case 'de':
        return '🇩🇪';
      case 'it':
        return '🇮🇹';
      case 'pt':
        return '🇵🇹';
      case 'tr':
        return '🇹🇷';
      case 'fa':
        return '🇮🇷';
      case 'zh':
        return '🇨🇳';
      default:
        return '🌐';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_size * 0.28),
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Center(
          child: Text(
            _flagEmojiFor(code),
            style: TextStyle(fontSize: _size * 0.56, height: 1),
          ),
        ),
      ),
    );
  }
}
