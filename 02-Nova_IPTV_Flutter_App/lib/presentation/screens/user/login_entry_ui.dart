part of '../screens.dart';

/// ألوان واجهة الدخول الفاخرة.
abstract final class LoginPremiumColors {
  /// SkyPro blue accent.
  static Color get gold => kColorPrimary;
  static Color get goldDark => kColorPrimaryDark;
  static const Color bgTop = kSkyProBlack;
  static const Color bgBottom = kSkyProBlack;
  static const Color greenActive = kSkyProBlue;
  static const Color glassFill = Color(0x12E0E0E0);
  static const Color glassBorder = Color(0x55007BFF);

  static const Color methodCard = Color(0xFF080808);
  static const Color methodCardDeep = kSkyProBlack;
  static const Color methodCardBorder = Color(0x55007BFF);
}

/// أحجام خطوط موحّدة لواجهات الدخول — أوضح على TV والهاتف.
abstract final class LoginPremiumTypography {
  static double title(bool isTv) => isTv ? 30.sp : 26.sp;
  static double subtitle(bool isTv) => isTv ? 15.sp : 14.sp;
  static double chip(bool isTv) => isTv ? 14.sp : 13.sp;
  static double label(bool isTv) => isTv ? 14.sp : 13.sp;
  static double hint(bool isTv) => isTv ? 14.sp : 13.sp;
  static double button(bool isTv) => isTv ? 17.0 : 16.0;
  static double input(bool isTv) => isTv ? 18.sp : 17.sp;
  static double gap(bool isTv, {double tv = 10, double mobile = 6}) =>
      isTv ? tv : mobile;
}

/// Pure-black login background with a restrained SkyPro-blue glow.
class _LoginEntryPremiumBackground extends StatelessWidget {
  const _LoginEntryPremiumBackground();

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: LoginPremiumColors.bgBottom),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.95,
                colors: [
                  Color(0x1A007BFF),
                  Color(0x08007BFF),
                  Colors.transparent,
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// غلاف تركيز بأبعاد ثابتة — يمنع اهتزاز التخطيط.
class _LoginFocusShell extends StatefulWidget {
  const _LoginFocusShell({
    required this.child,
    this.onTap,
    this.focusNode,
    this.onKeyEvent,
    this.borderRadius = 16,
    this.enabled = true,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final double borderRadius;
  final bool enabled;
  final bool autofocus;

  @override
  State<_LoginFocusShell> createState() => _LoginFocusShellState();
}

class _LoginFocusShellState extends State<_LoginFocusShell> {
  bool _focused = false;
  FocusNode? _chainedForNode;
  FocusOnKeyEventCallback? _chainedNodeHandler;

  static const double _borderWidth = 2.2;

  @override
  void initState() {
    super.initState();
    _captureChainedHandler();
  }

  @override
  void didUpdateWidget(covariant _LoginFocusShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      _restoreChainedHandler(oldWidget.focusNode);
      _captureChainedHandler();
    }
  }

  @override
  void dispose() {
    _restoreChainedHandler(widget.focusNode);
    super.dispose();
  }

  void _captureChainedHandler() {
    final node = widget.focusNode;
    if (node == null) {
      _chainedForNode = null;
      _chainedNodeHandler = null;
      return;
    }
    if (identical(_chainedForNode, node)) return;
    _chainedForNode = node;
    // شجرة Xtream تضع onKeyEvent على الـ node قبل البناء — نحتفظ بها.
    final existing = node.onKeyEvent;
    _chainedNodeHandler = identical(existing, _handleKey) ? null : existing;
  }

  void _restoreChainedHandler(FocusNode? node) {
    if (node == null) return;
    if (identical(node.onKeyEvent, _handleKey)) {
      node.onKeyEvent = _chainedNodeHandler;
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (widget.onKeyEvent != null) {
      final r = widget.onKeyEvent!(node, event);
      if (r != KeyEventResult.ignored) return r;
    } else if (_chainedNodeHandler != null) {
      final r = _chainedNodeHandler!(node, event);
      if (r != KeyEventResult.ignored) return r;
    }
    if (widget.enabled && widget.onTap != null) {
      return settingsTvActivateOnSelect(event, widget.onTap!);
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: homeThemeRevision,
      builder: (context, _, _) {
        final focusColor = kColorFocus;
        final node = widget.focusNode;
        // Focus مع focusNode خارجي لا يحدّث onKeyEvent بعد أول attach —
        // نزامن المعالج على الـ node في كل بناء حتى يبقى OK/Enter شغّالاً.
        if (node != null) {
          node.onKeyEvent = _handleKey;
        }

        return Focus(
          autofocus: widget.autofocus,
          focusNode: node,
          // مع node خارجي: المعالج على الـ node. بدونه: على الـ Focus.
          onKeyEvent: node == null ? _handleKey : null,
          // امنع InkWell/الأبناء من سرقة primary focus (سبب OK الميت المتقطع)
          descendantsAreFocusable: false,
          descendantsAreTraversable: false,
          onFocusChange: (v) {
            if (_focused == v) return;
            setState(() => _focused = v);
          },
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.enabled ? widget.onTap : null,
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: focusColor.withValues(alpha: 0.08),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (_focused && !kReduceFocusMotion)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              widget.borderRadius,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: focusColor.withValues(alpha: 0.38),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.zero,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          widget.borderRadius,
                        ),
                        border: Border.all(
                          color: _focused ? focusColor : Colors.transparent,
                          width: _borderWidth,
                        ),
                      ),
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

BoxDecoration _loginGlassDecoration({
  double radius = 20,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    color: LoginPremiumColors.glassFill,
    border: Border.all(
      color: LoginPremiumColors.glassBorder,
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.35),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

class _LoginEntryHero extends StatelessWidget {
  const _LoginEntryHero({
    required this.isTvDevice,
    this.compact = false,
  });

  final bool isTvDevice;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logoSize = compact
        ? (isTvDevice ? 52.0 : 44.0)
        : (isTvDevice ? 68.0 : 56.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: kSkyProBlue.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: kSkyProBlue.withValues(alpha: 0.4),
                blurRadius: 22,
                spreadRadius: 2,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            kIconSplash,
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(
          height: compact ? (isTvDevice ? 8 : 6) : (isTvDevice ? 12 : 10),
        ),
        Text(
          kAppName.toUpperCase(),
          textAlign: TextAlign.center,
          style: Get.textTheme.headlineMedium!.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.8,
            fontSize: compact
                ? (isTvDevice ? 20.0 : 18.0)
                : (isTvDevice ? 26.0 : 22.0),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'entry_method_xtream_hint'.tr, // "Username & Password"
          textAlign: TextAlign.center,
          style: Get.textTheme.bodyMedium!.copyWith(
            color: kSkyProSilver.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
            fontSize: isTvDevice ? 14.0 : 12.5,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _LoginMethodCard extends StatelessWidget {
  const _LoginMethodCard({
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.hint,
    required this.description,
    required this.onTap,
    required this.isTvDevice,
    this.onKeyEvent,
    this.traversalOrder = 6,
    this.expand = false,
    this.compact = false,
    this.recommended = false,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String title;
  final String hint;
  final String description;
  final VoidCallback onTap;
  final bool isTvDevice;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final double traversalOrder;
  final bool expand;
  final bool compact;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final radius = isTvDevice ? 20.0 : 16.0;

    Widget card = _LoginFocusShell(
      focusNode: focusNode,
      borderRadius: radius,
      onTap: onTap,
      onKeyEvent: onKeyEvent,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          return LayoutBuilder(
            builder: (context, constraints) {
              final h =
                  constraints.maxHeight.isFinite && constraints.maxHeight > 0
                  ? constraints.maxHeight
                  : (isTvDevice ? 120.0 : 100.0);
              // مقياس مستمر حسب ارتفاع الكارت — النصوص تبقى ظاهرة وتتصغّر فقط
              final idealH = isTvDevice ? 120.0 : 102.0;
              final scale = (h / idealH).clamp(0.58, 1.0);
              double s(double v) => v * scale;

              final iconBox = s(isTvDevice ? 56.0 : 48.0).clamp(30.0, 56.0);
              final padH = s(isTvDevice ? 16.0 : 14.0).clamp(8.0, 16.0);
              final padV = s(isTvDevice ? 10.0 : 8.0).clamp(4.0, 10.0);
              final titleSize = s(isTvDevice ? 17.0 : 15.0).clamp(11.5, 17.0);
              final hintSize = s(isTvDevice ? 13.0 : 12.0).clamp(9.5, 13.0);
              final descSize = s(isTvDevice ? 12.5 : 11.5).clamp(9.0, 12.5);
              final chevron = s(32.0).clamp(22.0, 32.0);
              final gapIcon = s(isTvDevice ? 12.0 : 10.0).clamp(6.0, 12.0);
              final descMaxLines = h < 70 ? 1 : 2;
              final showRecommended = recommended && scale > 0.78;
              final accent = kColorPrimary;

              final textBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: titleSize,
                            letterSpacing: 0.35,
                            height: 1.12,
                          ),
                        ),
                      ),
                      if (showRecommended) ...[
                        SizedBox(width: s(8)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: s(8).clamp(5, 8),
                            vertical: s(3).clamp(2, 3),
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              colors: [accent, accent.withValues(alpha: 0.75)],
                            ),
                            boxShadow: kReduceFocusMotion
                                ? null
                                : [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Text(
                            'entry_method_recommended'.tr,
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w900,
                              fontSize: s(
                                isTvDevice ? 10.5 : 9.5,
                              ).clamp(8.0, 10.5),
                              letterSpacing: 0.4,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: s(3).clamp(1.0, 3.0)),
                  Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: hintSize,
                      height: 1.12,
                    ),
                  ),
                  SizedBox(height: s(3).clamp(1.0, 4.0)),
                  Text(
                    description,
                    maxLines: descMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontWeight: FontWeight.w500,
                      fontSize: descSize,
                      height: 1.2,
                    ),
                  ),
                ],
              );

              final content = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: iconBox,
                    height: iconBox,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(iconBox * 0.28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: focused
                            ? [
                                accent.withValues(alpha: 0.38),
                                accent.withValues(alpha: 0.12),
                              ]
                            : [
                                const Color(0xFF1A2030),
                                const Color(0xFF12161F),
                              ],
                      ),
                      border: Border.all(
                        color: focused
                            ? accent.withValues(alpha: 0.65)
                            : LoginPremiumColors.methodCardBorder,
                      ),
                      boxShadow: focused && !kReduceFocusMotion
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.28),
                                blurRadius: 10,
                                spreadRadius: 0,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      icon,
                      size: iconBox * 0.44,
                      color: focused
                          ? accent
                          : Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  SizedBox(width: gapIcon),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, textBox) {
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: SizedBox(
                            width: textBox.maxWidth,
                            child: textBlock,
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: s(6).clamp(4.0, 8.0)),
                  Container(
                    width: chevron,
                    height: chevron,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: focused
                          ? accent.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                        color: focused
                            ? accent.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? LucideIcons.chevron_left
                          : LucideIcons.chevron_right,
                      color: focused
                          ? accent
                          : Colors.white.withValues(alpha: 0.5),
                      size: chevron * 0.5,
                    ),
                  ),
                ],
              );

              return AnimatedContainer(
                duration: AppPerf.instance.focusAnimDuration,
                curve: Curves.easeOut,
                width: double.infinity,
                height: expand ? double.infinity : null,
                clipBehavior: Clip.antiAlias,
                constraints: expand
                    ? null
                    : BoxConstraints(minHeight: isTvDevice ? 100 : 84),
                padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: focused
                        ? [
                            Color.lerp(
                              LoginPremiumColors.methodCard,
                              accent,
                              0.14,
                            )!,
                            LoginPremiumColors.methodCardDeep,
                          ]
                        : [
                            LoginPremiumColors.methodCard,
                            LoginPremiumColors.methodCardDeep,
                          ],
                  ),
                  border: Border.all(
                    color: focused
                        ? accent.withValues(alpha: 0.55)
                        : LoginPremiumColors.methodCardBorder,
                    width: focused ? 1.4 : 1.1,
                  ),
                  boxShadow: (AppPerf.instance.isLite ||
                          AppPerf.instance.isTelevisionLike)
                      ? (focused
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.28),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ])
                      : focused
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.18),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                ),
                alignment: Alignment.center,
                child: content,
              );
            },
          );
        },
      ),
    );

    if (expand) {
      card = SizedBox.expand(child: card);
    }

    if (!isTvDevice) return card;
    return FocusTraversalOrder(
      order: NumericFocusOrder(traversalOrder),
      child: card,
    );
  }
}

class _LoginTrustBar extends StatelessWidget {
  const _LoginTrustBar({required this.isTvDevice, this.compact = false});

  final bool isTvDevice;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: compact ? 6 : (isTvDevice ? 16 : 12)),
      padding: EdgeInsets.symmetric(
        horizontal: isTvDevice ? 18 : 14,
        vertical: compact ? (isTvDevice ? 8 : 6) : (isTvDevice ? 12 : 10),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.shield_check,
            size: isTvDevice ? 16 : 14,
            color: kColorPrimary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'entry_trust_bar'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w700,
                fontSize: isTvDevice ? 13 : 11.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              width: 1,
              height: 14,
              color: Colors.white.withValues(alpha: 0.22),
            ),
          ),
          Flexible(
            child: Text(
              'entry_trust_privacy'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontWeight: FontWeight.w600,
                fontSize: isTvDevice ? 12.5 : 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _LoginEntryDisclaimerCard extends StatelessWidget {
  const _LoginEntryDisclaimerCard({this.isTvDevice = false});

  final bool isTvDevice;

  @override
  Widget build(BuildContext context) {
    final isAr = Get.locale?.languageCode == 'ar';
    final rtl = isAppRtl();
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTvDevice ? 12 : 10,
        vertical: isTvDevice ? 8 : 6,
      ),
      child: Row(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: isTvDevice ? 30 : 28,
            height: isTvDevice ? 30 : 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: LoginPremiumColors.gold.withValues(alpha: 0.18),
            ),
            child: Icon(
              LucideIcons.shield,
              size: isTvDevice ? 16 : 15,
              color: LoginPremiumColors.gold,
            ),
          ),
          SizedBox(width: isTvDevice ? 10 : 8),
          Expanded(
            child: RichText(
              textAlign: rtl ? TextAlign.right : TextAlign.left,
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: Get.textTheme.bodyMedium!.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.35,
                  fontSize: isTvDevice ? 12.5 : 11.5,
                  fontWeight: FontWeight.w500,
                ),
                children: _disclaimerSpans(isAr),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _disclaimerSpans(bool isAr) {
    if (isAr) {
      return [
        const TextSpan(text: 'إخلاء المسؤولية: هذا التطبيق هو مجرد '),
        TextSpan(
          text: 'مشغل وسائط',
          style: TextStyle(
            color: LoginPremiumColors.gold,
            fontWeight: FontWeight.w800,
          ),
        ),
        const TextSpan(text: '. يجب على المستخدمين توفير '),
        TextSpan(
          text: 'المحتوى',
          style: TextStyle(
            color: LoginPremiumColors.gold,
            fontWeight: FontWeight.w800,
          ),
        ),
        const TextSpan(text: ' الخاص بهم.'),
      ];
    }
    return [
      const TextSpan(text: 'Disclaimer: This app is only a '),
      TextSpan(
        text: 'media player',
        style: TextStyle(
          color: LoginPremiumColors.gold,
          fontWeight: FontWeight.w800,
        ),
      ),
      const TextSpan(text: '. Users must provide their own '),
      TextSpan(
        text: 'content',
        style: TextStyle(
          color: LoginPremiumColors.gold,
          fontWeight: FontWeight.w800,
        ),
      ),
      const TextSpan(text: '.'),
    ];
  }
}

InputDecoration _loginPremiumFieldDecoration({
  required String hint,
  required IconData prefixIcon,
  Widget? suffixIcon,
  bool isTvDevice = false,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
  );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(
      color: Colors.white.withValues(alpha: 0.45),
      fontSize: LoginPremiumTypography.hint(isTvDevice),
    ),
    prefixIcon: Icon(
      prefixIcon,
      size: isTvDevice ? 22 : 20,
      color: kColorPrimary.withValues(alpha: 0.9),
    ),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.05),
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: kColorFocus, width: 2),
    ),
  );
}

extension _LoginEntryPremiumLayout on _LoginEntryScreenState {
  Widget buildPremiumLoginUi(BuildContext context) {
    final isTvDevice = isTv(context);
    final currentLang = currentAppLanguageCode();
    final langLabel = currentAppUiLanguage().nativeName;

    Widget tvTraverseOrder(double rank, Widget child) {
      if (!isTvDevice) return child;
      return FocusTraversalOrder(order: NumericFocusOrder(rank), child: child);
    }

    final chipPadH = isTvDevice ? 14.0 : 8.0;
    final chipPadV = isTvDevice ? 10.0 : 8.0;
    final chipGap = isTvDevice ? 8.0 : 5.0;
    final chipIconSize = isTvDevice ? 16.0 : 14.0;
    final chipFontSize = isTvDevice ? LoginPremiumTypography.chip(true) : 11.5;

    Widget langChip = tvTraverseOrder(
      2,
      _LoginFocusShell(
        focusNode: _languageFocusNode,
        borderRadius: 14,
        onTap: _showLanguageDialog,
        onKeyEvent: (node, event) => _tvTopChipKeyEvent(
          event,
          left: _tvNodeFocusable(_activationButtonFocus)
              ? _activationButtonFocus
              : _legalFocusNode,
          right: _manageAccountsFocus,
          onTap: _showLanguageDialog,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: chipPadH,
            vertical: chipPadV,
          ),
          decoration: _loginGlassDecoration(radius: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLangFlagIcon(code: currentLang, size: isTvDevice ? 20 : 18),
              SizedBox(width: chipGap),
              Text(
                langLabel,
                style: Get.textTheme.bodyMedium!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: chipFontSize,
                ),
              ),
              SizedBox(width: isTvDevice ? 6 : 4),
              Icon(
                LucideIcons.chevron_down,
                size: isTvDevice ? 14 : 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );

    Widget legalChip = tvTraverseOrder(
      1,
      _LoginFocusShell(
        focusNode: _legalFocusNode,
        borderRadius: 14,
        onTap: _openLegalMenu,
        onKeyEvent: (node, event) => _tvTopChipKeyEvent(
          event,
          right: _tvNodeFocusable(_activationButtonFocus)
              ? _activationButtonFocus
              : _languageFocusNode,
          onTap: _openLegalMenu,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: chipPadH,
            vertical: chipPadV,
          ),
          decoration: _loginGlassDecoration(radius: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.scale,
                size: chipIconSize,
                color: LoginPremiumColors.gold,
              ),
              SizedBox(width: chipGap),
              Text(
                'legal_button'.tr,
                style: Get.textTheme.bodyMedium!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: chipFontSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget manageChip = tvTraverseOrder(
      3,
      _LoginFocusShell(
        focusNode: _manageAccountsFocus,
        borderRadius: 14,
        onTap: _openManageAccounts,
        onKeyEvent: (node, event) => _tvTopChipKeyEvent(
          event,
          left: _languageFocusNode,
          right: _supportFocus,
          onTap: _openManageAccounts,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: chipPadH,
            vertical: chipPadV,
          ),
          decoration: _loginGlassDecoration(radius: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.users,
                size: chipIconSize,
                color: LoginPremiumColors.gold,
              ),
              SizedBox(width: chipGap),
              Text(
                'manage_accounts_btn'.tr,
                style: Get.textTheme.bodyMedium!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: chipFontSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget supportChip = tvTraverseOrder(
      4,
      _LoginFocusShell(
        focusNode: _supportFocus,
        borderRadius: 14,
        onTap: _openSupportContact,
        onKeyEvent: (node, event) => _tvTopChipKeyEvent(
          event,
          left: _manageAccountsFocus,
          onTap: _openSupportContact,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: chipPadH,
            vertical: chipPadV,
          ),
          decoration: _loginGlassDecoration(radius: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.headset,
                size: chipIconSize,
                color: LoginPremiumColors.gold,
              ),
              SizedBox(width: chipGap),
              Text(
                'contact_support'.tr,
                style: Get.textTheme.bodyMedium!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: chipFontSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return ValueListenableBuilder<int>(
      valueListenable: homeThemeRevision,
      builder: (context, _, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, dynamic result) {
          if (!didPop) _showEntryExitConfirm();
        },
        child: Scaffold(
          backgroundColor: LoginPremiumColors.bgBottom,
          resizeToAvoidBottomInset: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const _LoginEntryPremiumBackground(),
              AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(
                  bottom: isTvDevice
                      ? MediaQuery.viewInsetsOf(context).bottom
                      : 0,
                ),
                child: SafeArea(
                  // تقريب الشريط العلوي من الشق دون قصّ الأزرار (هاتف فقط)
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: () {
                        final inset = MediaQuery.paddingOf(context).top;
                        if (isTvDevice) {
                          // تلفاز: غالباً لا يوجد safe inset — أضف فراغاً عن الحافة
                          return inset > 0 ? inset + 12.0 : 28.0;
                        }
                        // تجنّب clamp عندما inset < 10 (Nox وغيره) — يرمي خطأ ويفرغ الشاشة
                        final reduced = inset - 10;
                        return reduced < 2
                            ? (inset > 0 ? inset : 2.0)
                            : reduced;
                      }(),
                    ),
                    child: BlocConsumer<AuthBloc, AuthState>(
                      listener: (context, state) {
                        if (state is AuthSuccess) {
                          // أثناء انتظار اليوزر/الباس: تجاهل أي AuthSuccess بدون اعتمادات
                          // (كان يحدث عند الدخول التلقائي الخاطئ كقائمة فارغة)
                          if (_pendingHostDomainFromCode != null) {
                            final u = (state.user.userInfo?.username ?? '')
                                .trim();
                            final p = (state.user.userInfo?.password ?? '')
                                .trim();
                            if (u.isEmpty || p.isEmpty) {
                              return;
                            }
                          }
                          _pendingHostDomainFromCode = null;
                          _tryNavigateHome(state);
                        } else if (state is AuthFailed) {
                          // إيقاف الحلقة + حذف الرابط من اللوحة — QR يُعاد عند رابط جديد
                          // لا تمسح حالة host-only عند فشل بيانات الدخول
                          if (state.message == 'host_only_needs_credentials') {
                            return;
                          }
                          // صفحة فوق الدخول (مثل Add Playlist) تعرض الـ toast وحدها.
                          final routeIsCurrent =
                              ModalRoute.of(context)?.isCurrent ?? true;
                          if (_pendingHostDomainFromCode == null) {
                            _playlistAutoLoginBlocked = true;
                            _autoLoginTried = true;
                          }
                          if (state.message == 'LogOut') return;
                          if (_pendingHostDomainFromCode == null &&
                              routeIsCurrent) {
                            unawaited(() async {
                              // أثناء انتظار QR: لا تمسح playlist من اللوحة عند أول فشل دخول.
                              final waitingQr =
                                  _storage.read(kStorageForceQrAutoLogin) ==
                                      true ||
                                  _storage.read(kStorageQrAwaitNewAccount) ==
                                      true;
                              if (waitingQr) return;
                              if (_deviceId.isEmpty) {
                                _deviceId = await _activationApi.getDeviceId();
                              }
                              await clearLocalFailedPlaylistAutoLogin(_storage);
                              if (_deviceId.isNotEmpty) {
                                await _activationApi.clearPlaylistUrl(
                                  _deviceId,
                                );
                              }
                            }());
                          }
                          if (!routeIsCurrent) return;
                          if (_pendingHostDomainFromCode != null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _manualUsernameFocus.requestFocus();
                            });
                            if (state.message != 'LogOut' &&
                                state.message !=
                                    'host_only_needs_credentials') {
                              showWarningToast(
                                context,
                                'login_failed'.tr,
                                'check_credentials'.tr,
                              );
                            }
                          } else {
                            showWarningToast(
                              context,
                              'login_failed'.tr,
                              'check_credentials'.tr,
                            );
                          }
                        }
                      },
                      builder: (context, authState) {
                        final loadingAuth = authState is AuthLoading;
                        final hPad = isTvDevice ? 32.0 : 16.0;
                        final cardMaxWidth = isTvDevice ? 480.0 : 380.0;

                        final topSection = Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTvDevice ? 16 : 8,
                          ),
                          child: Row(
                            children: [
                              legalChip,
                              const Spacer(),
                              langChip,
                              SizedBox(width: isTvDevice ? 8 : 6),
                              manageChip,
                              SizedBox(width: isTvDevice ? 8 : 6),
                              supportChip,
                            ],
                          ),
                        );

                        final formCard = AnimatedBuilder(
                          animation: _manualCredsShakeController,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(_manualCredsShakeOffset.value, 0),
                              child: child,
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isTvDevice ? 28 : 20,
                              vertical: isTvDevice ? 24 : 18,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C0D11).withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: kSkyProBlue.withValues(alpha: 0.45),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  blurRadius: 32,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: kSkyProBlue.withValues(alpha: 0.18),
                                  blurRadius: 24,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _LoginEntryHero(isTvDevice: isTvDevice),
                                SizedBox(height: isTvDevice ? 20 : 16),
                                tvTraverseOrder(
                                  1,
                                  TextField(
                                    controller: _manualUsernameController,
                                    focusNode: _manualUsernameFocus,
                                    keyboardType: TextInputType.text,
                                    textInputAction: TextInputAction.next,
                                    textAlign: TextAlign.center,
                                    style: Get.textTheme.titleSmall!.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: LoginPremiumTypography.input(
                                        isTvDevice,
                                      ),
                                    ),
                                    decoration: _loginPremiumFieldDecoration(
                                      hint: "username".tr,
                                      prefixIcon: LucideIcons.user,
                                      isTvDevice: isTvDevice,
                                    ),
                                    onTap: () {
                                      _manualUsernameFocus.requestFocus();
                                      _showIme();
                                    },
                                    onSubmitted: (_) {
                                      _manualPasswordFocus.requestFocus();
                                      _showIme();
                                    },
                                  ),
                                ),
                                SizedBox(height: isTvDevice ? 12 : 10),
                                tvTraverseOrder(
                                  2,
                                  TextField(
                                    controller: _manualPasswordController,
                                    focusNode: _manualPasswordFocus,
                                    obscureText: _isPasswordObscured,
                                    keyboardType: TextInputType.visiblePassword,
                                    textInputAction: TextInputAction.done,
                                    textAlign: TextAlign.center,
                                    style: Get.textTheme.titleSmall!.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: LoginPremiumTypography.input(
                                        isTvDevice,
                                      ),
                                    ),
                                    decoration: _loginPremiumFieldDecoration(
                                      hint: "password".tr,
                                      prefixIcon: LucideIcons.lock,
                                      isTvDevice: isTvDevice,
                                      suffixIcon: IconButton(
                                        onPressed: _togglePasswordVisibility,
                                        icon: Icon(
                                          _isPasswordObscured
                                              ? LucideIcons.eye_off
                                              : LucideIcons.eye,
                                          size: 18,
                                          color: LoginPremiumColors.gold
                                              .withValues(alpha: 0.9),
                                        ),
                                      ),
                                    ),
                                    onTap: () {
                                      _manualPasswordFocus.requestFocus();
                                      _showIme();
                                    },
                                    onSubmitted: (_) =>
                                        _submitManualCredsAfterCode(),
                                  ),
                                ),
                                SizedBox(height: isTvDevice ? 18 : 14),
                                tvTraverseOrder(
                                  3,
                                  _LoginFocusShell(
                                    focusNode: _manualLoginFocus,
                                    borderRadius: 14,
                                    enabled: !loadingAuth,
                                    onTap: _submitManualCredsAfterCode,
                                    onKeyEvent: _tvManualLoginKeyEvent,
                                    child: Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.symmetric(
                                        vertical: isTvDevice ? 15 : 13,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        gradient: LinearGradient(
                                          colors: [
                                            LoginPremiumColors.gold,
                                            LoginPremiumColors.goldDark,
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: LoginPremiumColors.gold
                                                .withValues(alpha: 0.35),
                                            blurRadius: 16,
                                            spreadRadius: 1,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (loadingAuth) ...[
                                            const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                          ] else ...[
                                            const Icon(
                                              LucideIcons.log_in,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          Text(
                                            loadingAuth
                                                ? "loading".tr
                                                : "login".tr,
                                            style: Get.textTheme.bodyLarge!
                                                .copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize:
                                                      LoginPremiumTypography
                                                          .button(isTvDevice),
                                                  letterSpacing: 0.5,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );

                        final pageBody = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            topSection,
                            Expanded(
                              child: Center(
                                child: SingleChildScrollView(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: hPad,
                                    vertical: 8,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: cardMaxWidth,
                                    ),
                                    child: formCard,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: cardMaxWidth,
                                  ),
                                  child: _LoginEntryDisclaimerCard(
                                    isTvDevice: isTvDevice,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: isTvDevice
                                  ? FocusTraversalGroup(
                                      policy: OrderedTraversalPolicy(),
                                      child: pageBody,
                                    )
                                  : pageBody,
                            ),
                            if (loadingAuth)
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
                                          color: LoginPremiumColors.gold
                                              .withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                                color: LoginPremiumColors.gold,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Flexible(
                                              child: Text(
                                                "loading".tr,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.92),
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: isTvDevice
                                                      ? 14
                                                      : 13,
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
                    ),
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
