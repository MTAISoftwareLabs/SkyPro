part of '../screens.dart';

String _wrapPanelHtmlFragment(String inner) {
  final dir = isAppRtl() ? 'rtl' : 'ltr';
  final trimmed = inner.trim();
  final lower = trimmed.toLowerCase();
  if (trimmed.startsWith('<!DOCTYPE') || lower.startsWith('<html')) {
    return trimmed;
  }
  return '<!DOCTYPE html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<style>'
      'body{margin:0;padding:16px 18px;background:#0b0d10;color:#eaeaea;'
      'font-size:15px;line-height:1.65;font-family:system-ui,-apple-system,sans-serif;}'
      'img{max-width:100%;height:auto;} a{color:#5ecfff;word-break:break-word;}'
      '</style></head><body dir="$dir">$trimmed</body></html>';
}

Future<void> showAboutUsDialog(
  BuildContext context, {
  required String html,
}) async {
  await showLegalContentDialog(
    context,
    title: 'about_us_title'.tr,
    html: html,
  );
}

/// نافذة محتوى قانوني (سياسة / من نحن) من لوحة التحكم — تركيز X للتلفاز فقط.
Future<void> showLegalContentDialog(
  BuildContext context, {
  required String title,
  String? html,
  String? url,
}) async {
  final hasHtml = (html ?? '').trim().isNotEmpty;
  final hasUrl = (url ?? '').trim().isNotEmpty;
  if (!hasHtml && !hasUrl) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'legal_content',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, animation, secondary) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ),
        child: _LegalContentDialogPanel(
          dialogContext: ctx,
          title: title,
          html: hasHtml ? html!.trim() : null,
          url: hasUrl ? url!.trim() : null,
        ),
      );
    },
  );
}

/// قائمة Legal على شاشة الدخول: سياسة الخصوصية + من نحن.
Future<void> showLoginLegalMenuDialog(
  BuildContext context, {
  FocusNode? returnFocus,
}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'legal_menu',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, animation, secondary) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ),
        child: _LoginLegalMenuDialog(
          dialogContext: ctx,
          returnFocus: returnFocus,
        ),
      );
    },
  );
  if (context.mounted) {
    settingsRestoreFocusIfTv(context, returnFocus);
  }
}

class _LoginLegalMenuDialog extends StatefulWidget {
  const _LoginLegalMenuDialog({
    required this.dialogContext,
    this.returnFocus,
  });

  final BuildContext dialogContext;
  final FocusNode? returnFocus;

  @override
  State<_LoginLegalMenuDialog> createState() => _LoginLegalMenuDialogState();
}

class _LoginLegalMenuDialogState extends State<_LoginLegalMenuDialog> {
  late final FocusNode _closeFocus;
  late final FocusNode _privacyFocus;
  late final FocusNode _aboutFocus;
  late final FocusNode _deviceInfoFocus;
  bool _closeFocused = false;
  bool _privacyFocused = false;
  bool _aboutFocused = false;
  bool _deviceInfoFocused = false;

  @override
  void initState() {
    super.initState();
    _closeFocus = FocusNode(debugLabel: 'legal_menu_close');
    _privacyFocus = FocusNode(debugLabel: 'legal_menu_privacy');
    _aboutFocus = FocusNode(debugLabel: 'legal_menu_about');
    _deviceInfoFocus = FocusNode(debugLabel: 'legal_menu_device_info');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isTv(context)) _privacyFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _closeFocus.dispose();
    _privacyFocus.dispose();
    _aboutFocus.dispose();
    _deviceInfoFocus.dispose();
    super.dispose();
  }

  void _closeMenu() {
    Navigator.of(widget.dialogContext).pop();
  }

  Future<void> _openPrivacy() async {
    final box = GetStorage();
    final mode =
        (box.read('privacy_policy_mode') ?? 'url').toString().toLowerCase();
    String? html;
    String? url;
    if (mode == 'html') {
      html = (box.read('privacy_policy_html') ?? '').toString().trim();
      if (html.isEmpty) {
        showWarningToast(
          context,
          'notice_title'.tr,
          'legal_not_configured'.tr,
        );
        return;
      }
    } else {
      url = (box.read('privacy_policy_url') ?? '').toString().trim();
      if (url.isEmpty) {
        showWarningToast(
          context,
          'notice_title'.tr,
          'legal_not_configured'.tr,
        );
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
    await showLegalContentDialog(
      widget.dialogContext,
      title: 'privacy_policy_title'.tr,
      html: html,
      url: url,
    );
    if (mounted && isTv(context)) _privacyFocus.requestFocus();
  }

  Future<void> _openAbout() async {
    final html = (GetStorage().read('about_us_html') ?? '').toString().trim();
    if (html.isEmpty) {
      showWarningToast(
        context,
        'notice_title'.tr,
        'about_not_configured'.tr,
      );
      return;
    }
    await showLegalContentDialog(
      widget.dialogContext,
      title: 'about_us_title'.tr,
      html: html,
    );
    if (mounted && isTv(context)) _aboutFocus.requestFocus();
  }

  Future<void> _openDeviceInfo() async {
    await showDeviceInfoDialog(
      widget.dialogContext,
      returnFocus: _deviceInfoFocus,
    );
    if (mounted && isTv(context)) _deviceInfoFocus.requestFocus();
  }

  Widget _menuButton({
    required FocusNode focusNode,
    required bool focused,
    required ValueChanged<bool> onFocusChange,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      onKeyEvent:
          isTv(context)
              ? (node, event) => settingsTvActivateOnSelect(event, onTap)
              : null,
      child: Builder(
        builder: (ctx) {
          final showFocus = settingsShowFocusDecor(ctx, focused);
          return AnimatedScale(
            scale: showFocus ? 1.02 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color:
                        showFocus
                            ? kColorPrimary
                            : Colors.white.withValues(alpha: 0.12),
                    width: showFocus ? 2.5 : 1,
                  ),
                  // هالة خارجية فقط — بدون spread حتى لا تُقصّ وتبدو تعتيماً داخلياً.
                  boxShadow:
                      showFocus
                          ? [
                            BoxShadow(
                              color: kColorPrimary.withValues(alpha: 0.5),
                              blurRadius: 14,
                              spreadRadius: 0,
                              offset: Offset.zero,
                            ),
                          ]
                          : const [],
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(icon, color: kColorPrimary, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: Get.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      FontAwesomeIcons.chevronRight,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: kColorPrimary.withValues(alpha: 0.35)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF151922).withValues(alpha: 0.98),
                  const Color(0xFF0b0d11).withValues(alpha: 0.99),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            // بدون ClipRRect: حتى لا تُقصّ هالة التركيز على About وتبدو كتعتيم داخلي.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'legal_button'.tr,
                            style: Get.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Focus(
                          focusNode: _closeFocus,
                          onFocusChange: (v) {
                            if (_closeFocused != v) {
                              setState(() => _closeFocused = v);
                            }
                          },
                          onKeyEvent:
                              isTv(context)
                                  ? (node, event) =>
                                      settingsTvActivateOnSelect(
                                        event,
                                        _closeMenu,
                                      )
                                  : null,
                          child: Builder(
                            builder: (c) {
                              final showFocus = settingsShowFocusDecor(
                                c,
                                _closeFocused,
                              );
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        showFocus
                                            ? kColorPrimary
                                            : Colors.transparent,
                                    width: showFocus ? 2 : 0,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _closeMenu,
                                  child: const SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Icon(
                                      FontAwesomeIcons.xmark,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                    child: Column(
                      children: [
                        _menuButton(
                          focusNode: _privacyFocus,
                          focused: _privacyFocused,
                          onFocusChange: (v) {
                            if (_privacyFocused != v) {
                              setState(() => _privacyFocused = v);
                            }
                          },
                          icon: FontAwesomeIcons.shieldHalved,
                          label: 'privacy_policy_title'.tr,
                          onTap: () => unawaited(_openPrivacy()),
                        ),
                        const SizedBox(height: 12),
                        _menuButton(
                          focusNode: _aboutFocus,
                          focused: _aboutFocused,
                          onFocusChange: (v) {
                            if (_aboutFocused != v) {
                              setState(() => _aboutFocused = v);
                            }
                          },
                          icon: FontAwesomeIcons.circleInfo,
                          label: 'about_us_title'.tr,
                          onTap: () => unawaited(_openAbout()),
                        ),
                        const SizedBox(height: 12),
                        _menuButton(
                          focusNode: _deviceInfoFocus,
                          focused: _deviceInfoFocused,
                          onFocusChange: (v) {
                            if (_deviceInfoFocused != v) {
                              setState(() => _deviceInfoFocused = v);
                            }
                          },
                          icon: LucideIcons.monitor_smartphone,
                          label: 'settings_device_info'.tr,
                          onTap: () => unawaited(_openDeviceInfo()),
                        ),
                      ],
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

class _LegalContentDialogPanel extends StatefulWidget {
  const _LegalContentDialogPanel({
    required this.dialogContext,
    required this.title,
    this.html,
    this.url,
  });

  final BuildContext dialogContext;
  final String title;
  final String? html;
  final String? url;

  @override
  State<_LegalContentDialogPanel> createState() =>
      _LegalContentDialogPanelState();
}

class _LegalContentDialogPanelState extends State<_LegalContentDialogPanel> {
  late final FocusNode _closeFocusNode;
  bool _closeFocused = false;

  @override
  void initState() {
    super.initState();
    _closeFocusNode = FocusNode(debugLabel: 'legal_content_close');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isTv(context)) _closeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _closeFocusNode.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(widget.dialogContext).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.dialogContext;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(ctx).size.height * 0.86,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: kColorPrimary.withValues(alpha: 0.35),
                width: 1.2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF151922).withValues(alpha: 0.98),
                  const Color(0xFF0b0d11).withValues(alpha: 0.99),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: kColorPrimary.withValues(alpha: 0.12),
                  blurRadius: 28,
                  spreadRadius: 0,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          kColorPrimary.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: kColorPrimary.withValues(alpha: 0.22),
                            border: Border.all(
                              color: kColorPrimary.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Icon(
                            FontAwesomeIcons.scaleBalanced,
                            color: kColorPrimary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: Get.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        Focus(
                          focusNode: _closeFocusNode,
                          onFocusChange: (v) {
                            if (_closeFocused != v) {
                              setState(() => _closeFocused = v);
                            }
                          },
                          onKeyEvent:
                              isTv(context)
                                  ? (node, event) =>
                                      settingsTvActivateOnSelect(event, _close)
                                  : null,
                          child: Builder(
                            builder: (c) {
                              final showFocus = settingsShowFocusDecor(
                                c,
                                _closeFocused,
                              );
                              return AnimatedScale(
                                scale: showFocus ? 1.08 : 1.0,
                                duration: const Duration(milliseconds: 140),
                                curve: Curves.easeOut,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          showFocus
                                              ? kColorPrimary
                                              : Colors.transparent,
                                      width: showFocus ? 2 : 0,
                                    ),
                                    boxShadow: settingsThemedFocusGlow(
                                      showFocus,
                                    ),
                                  ),
                                  child: Material(
                                    color:
                                        showFocus
                                            ? kColorPrimary.withValues(alpha: 0.22)
                                            : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: _close,
                                      child: const SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Icon(
                                          FontAwesomeIcons.xmark,
                                          color: Colors.white70,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(ctx).size.height * 0.52,
                    child: _LegalContentWebView(
                      html: widget.html,
                      url: widget.url,
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

class _LegalContentWebView extends StatefulWidget {
  const _LegalContentWebView({this.html, this.url});

  final String? html;
  final String? url;

  @override
  State<_LegalContentWebView> createState() => _LegalContentWebViewState();
}

class _LegalContentWebViewState extends State<_LegalContentWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(const Color(0xFF0b0d10));
    final url = widget.url?.trim() ?? '';
    final html = widget.html?.trim() ?? '';
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null &&
          uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https')) {
        _controller.loadRequest(uri);
      } else if (html.isNotEmpty) {
        _controller.loadHtmlString(_wrapPanelHtmlFragment(html));
      }
    } else if (html.isNotEmpty) {
      _controller.loadHtmlString(_wrapPanelHtmlFragment(html));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
