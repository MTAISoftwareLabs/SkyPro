part of '../screens.dart';

/// ألوان واجهة الدخول الفاخرة.
abstract final class LoginPremiumColors {
  /// لون التمييز/التركيز — يتبع ثيم التطبيق (مش ذهب ثابت).
  static Color get gold => kColorPrimary;
  static Color get goldDark => kColorPrimaryDark;
  static const Color bgTop = Color(0xFF0A0E1A);
  static const Color bgBottom = Color(0xFF050508);
  static const Color greenActive = Color(0xFF4ADE80);
  static const Color glassFill = Color(0x12FFFFFF);
  static const Color glassBorder = Color(0x20FFFFFF);

  /// خلفية كروت طرق الدخول — كحل بارد غير شفاف.
  static const Color methodCard = Color(0xFF0E1118);
  static const Color methodCardDeep = Color(0xFF080A10);
  static const Color methodCardBorder = Color(0xFF2A3140);
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

/// خلفية شاشة الدخول — صورة `back_login` (نفس أسلوب Desktop).
class _LoginEntryPremiumBackground extends StatelessWidget {
  const _LoginEntryPremiumBackground();

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: LoginPremiumColors.bgBottom),
          Image(
            image: AssetImage(kLoginBackground),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
          // تعتيم خفيف فالوسط باش الكروت والنصوص يبقاو واضحين.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.95,
                colors: [
                  Color(0x59050508),
                  Color(0x24050508),
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
    this.connectStyle = true,
    this.compact = false,
  });

  final bool isTvDevice;
  final bool connectStyle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!connectStyle) {
      return _legacyWelcomeHero(context);
    }
    final logoSize = compact
        ? (isTvDevice ? 36.0 : 32.0)
        : (isTvDevice ? 48.0 : 40.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: logoSize,
              height: logoSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: kColorPrimary.withValues(alpha: 0.28),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image(
                image: const AssetImage(kIconSplash),
                fit: BoxFit.cover,
                width: logoSize,
                height: logoSize,
              ),
            ),
            SizedBox(width: isTvDevice ? 12 : 10),
            Flexible(
              child: Text(
                kAppName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Get.textTheme.titleMedium!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  fontSize: compact
                      ? (isTvDevice ? 15.0 : 13.0)
                      : (isTvDevice ? 18.0 : 15.0),
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: compact ? (isTvDevice ? 8 : 6) : (isTvDevice ? 14 : 10),
        ),
        Text(
          'entry_connect_title'.tr,
          textAlign: TextAlign.center,
          style: Get.textTheme.headlineSmall!.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: compact
                ? (isTvDevice ? 22.0 : 18.0)
                : (isTvDevice ? 28.0 : 22.0),
            letterSpacing: 0.6,
            height: 1.15,
          ),
        ),
        if (!compact) ...[
          SizedBox(
            height: LoginPremiumTypography.gap(isTvDevice, tv: 8, mobile: 5),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isTvDevice ? 20 : 8),
            child: Text(
              'entry_connect_subtitle'.tr,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Get.textTheme.bodyMedium!.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.35,
                fontSize: LoginPremiumTypography.subtitle(isTvDevice),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _legacyWelcomeHero(BuildContext context) {
    final fpSize = isTvDevice ? 56.0 : 44.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: fpSize + 36,
          height: fpSize + 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ...List.generate(3, (i) {
                final scale = 1.0 + i * 0.18;
                return Container(
                  width: fpSize * scale,
                  height: fpSize * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: LoginPremiumColors.gold.withValues(
                        alpha: 0.22 - i * 0.05,
                      ),
                      width: 1.2,
                    ),
                  ),
                );
              }),
              Container(
                width: fpSize,
                height: fpSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      LoginPremiumColors.gold.withValues(alpha: 0.28),
                      LoginPremiumColors.gold.withValues(alpha: 0.05),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: LoginPremiumColors.gold.withValues(alpha: 0.35),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  LucideIcons.fingerprint_pattern,
                  size: fpSize * 0.52,
                  color: LoginPremiumColors.gold,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: isTvDevice ? 8 : 6),
        Text(
          'entry_title'.tr,
          textAlign: TextAlign.center,
          style: Get.textTheme.headlineSmall!.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: LoginPremiumTypography.title(isTvDevice),
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

class _LoginEntryActivationPremium extends StatelessWidget {
  const _LoginEntryActivationPremium({
    required this.status,
    required this.expiryDate,
    required this.onActivate,
    required this.showActivateButton,
    this.isTvDevice = false,
    this.activateButtonFocusNode,
    this.activateButtonOnKeyEvent,
  });

  final String status;
  final String expiryDate;
  final VoidCallback onActivate;
  final bool showActivateButton;
  final bool isTvDevice;
  final FocusNode? activateButtonFocusNode;
  final FocusOnKeyEventCallback? activateButtonOnKeyEvent;

  Color _statusColor() {
    switch (status) {
      case 'نشط':
        return LoginPremiumColors.greenActive;
      case 'منتهي':
        return Colors.orange;
      case 'محظور':
        return Colors.red;
      case 'checking':
      case 'جاري التحقق...':
        return const Color(0xFF42A5F5);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildTopPill(context);
  }

  Widget _buildTopPill(BuildContext context) {
    final color = _statusColor();
    final isActive = status == 'نشط';
    final showRenew =
        isActive &&
        showActivateButton &&
        shouldOfferActivationRenewal(expiryDate);
    final showActionButton = (showActivateButton && !isActive) || showRenew;
    final remaining = expiryDate.trim().isNotEmpty
        ? parseActivationRemaining(expiryDate)
        : null;
    final remainingLabel = remaining == null
        ? ''
        : formatActivationPillRemaining(remaining);
    final remainingAccent = remaining == null
        ? color
        : remaining.isLifetime
        ? const Color(0xFFFBBF24)
        : (showRenew ? Colors.orangeAccent : LoginPremiumColors.greenActive);
    final pct = activationProgressFraction(remaining);

    final pill = Container(
      constraints: BoxConstraints(
        maxWidth: isTvDevice ? 300 : 240,
        minWidth: isTvDevice ? 160 : 140,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isTvDevice ? 12 : 10,
        vertical: isTvDevice ? 7 : 6,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.10),
        border: Border.all(
          color: color.withValues(alpha: isActive ? 0.45 : 0.28),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive
                    ? LucideIcons.circle_check
                    : status == 'محظور'
                    ? LucideIcons.ban
                    : LucideIcons.circle_alert,
                color: color,
                size: isTvDevice ? 14 : 13,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  activationStatusKey(status).tr.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: isTvDevice ? 12 : 11,
                    letterSpacing: 0.3,
                    height: 1.1,
                  ),
                ),
              ),
              if (remainingLabel.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    width: 1,
                    height: 12,
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                Flexible(
                  child: Text(
                    remainingLabel.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w800,
                      fontSize: isTvDevice ? 11.5 : 10.5,
                      letterSpacing: 0.2,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (remaining != null && (isActive || remaining.isValid)) ...[
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    remainingAccent.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ),
          ],
          if (showActionButton) ...[
            const SizedBox(height: 6),
            _ActivateAppPremiumButton(
              focusNode: activateButtonFocusNode,
              onTap: onActivate,
              isTvDevice: isTvDevice,
              compact: true,
              onKeyEvent: activateButtonOnKeyEvent,
              label: showRenew ? 'renew_activation'.tr : 'activate_app'.tr,
              icon: showRenew
                  ? LucideIcons.refresh_cw
                  : LucideIcons.shield_check,
            ),
          ],
        ],
      ),
    );

    return pill;
  }
}

/// زر تفعيل عصري مع أيقونة وهالة وتكبير 1.08 عند التركيز بالريموت.
class _ActivateAppPremiumButton extends StatefulWidget {
  const _ActivateAppPremiumButton({
    required this.onTap,
    required this.isTvDevice,
    this.focusNode,
    this.onKeyEvent,
    this.label,
    this.icon,
    this.compact = false,
  });

  final VoidCallback onTap;
  final bool isTvDevice;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final String? label;
  final IconData? icon;
  final bool compact;

  @override
  State<_ActivateAppPremiumButton> createState() =>
      _ActivateAppPremiumButtonState();
}

class _ActivateAppPremiumButtonState extends State<_ActivateAppPremiumButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: homeThemeRevision,
      builder: (context, _, _) {
        final focusColor = kColorFocus;
        final btnH = widget.compact ? 32.0 : (widget.isTvDevice ? 40.0 : 36.0);
        final iconSize = widget.compact
            ? 14.0
            : (widget.isTvDevice ? 17.0 : 15.0);
        final radius = 11.0;
        final label = (widget.label ?? '').trim().isEmpty
            ? 'activate_app'.tr
            : widget.label!.trim();
        final icon = widget.icon ?? LucideIcons.shield_check;
        final keyHandler =
            widget.onKeyEvent ??
            (FocusNode node, KeyEvent event) =>
                settingsTvActivateOnSelect(event, widget.onTap);
        final node = widget.focusNode;
        if (node != null) {
          node.onKeyEvent = keyHandler;
        }

        return Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.isTvDevice ? 260 : 200,
              minHeight: btnH,
            ),
            child: Focus(
          focusNode: node,
          onKeyEvent: node == null ? keyHandler : null,
          descendantsAreFocusable: false,
          descendantsAreTraversable: false,
          onFocusChange: (v) {
            if (_focused == v) return;
            setState(() => _focused = v);
          },
          child: AnimatedScale(
            scale: kReduceFocusMotion
                ? 1.0
                : (_focused ? (widget.compact ? 1.02 : 1.05) : 1.0),
            duration: AppPerf.instance.focusAnimDuration,
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: AppPerf.instance.focusAnimDuration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: _focused
                    ? Border.all(color: focusColor, width: 2)
                    : null,
                boxShadow: _focused
                    ? (kReduceFocusMotion
                        ? null
                        : [
                            BoxShadow(
                              color: focusColor.withValues(alpha: 0.32),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ])
                    : [
                        BoxShadow(
                          color: LoginPremiumColors.gold.withValues(
                            alpha: 0.18,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(radius),
                child: InkWell(
                  onTap: widget.onTap,
                  canRequestFocus: false,
                  borderRadius: BorderRadius.circular(radius),
                  focusColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  splashColor: focusColor.withValues(alpha: 0.12),
                  child: Ink(
                    height: btnH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          LoginPremiumColors.gold,
                          LoginPremiumColors.goldDark,
                        ],
                      ),
                      border: Border.all(
                        color: _focused
                            ? focusColor
                            : Colors.white.withValues(alpha: 0.18),
                        width: _focused ? 2 : 1,
                      ),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.compact
                          ? (widget.isTvDevice ? 10 : 9)
                          : 14,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: iconSize, color: Colors.black87),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Get.textTheme.bodyMedium!.copyWith(
                              color: Colors.black87,
                              fontWeight: FontWeight.w800,
                              fontSize: widget.compact
                                  ? (widget.isTvDevice ? 12.5 : 12)
                                  : (widget.isTvDevice ? 14 : 13),
                              letterSpacing: 0.1,
                              height: 1.1,
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
        ),
        ),
        );
      },
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
                        // مثل الإصدار القديم: أي كود host-only يفعّل وضع اليوزر/الباس
                        // بغض النظر عن إعداد إظهار زر الدخول باليوزر من اللوحة.
                        final showManualCreds =
                            _pendingHostDomainFromCode != null;
                        final allowUsernameLogin = showUsernameLogin;
                        final tvKeypadMode =
                            isTvDevice && _showTvCodeKeypad && !showManualCreds;
                        final hPad = isTvDevice ? 36.0 : 20.0;
                        final showMethodsGrid =
                            !showManualCreds && !tvKeypadMode;
                        final screenW = MediaQuery.sizeOf(context).width;
                        final cardMaxWidth = showMethodsGrid
                            ? (screenW - hPad * 2).clamp(720.0, 1400.0)
                            : (isTvDevice ? 720.0 : 520.0);

                        final bottomPad = (isTvDevice && _showTvCodeKeypad)
                            ? _LoginEntryScreenState._tvKeypadReserveHeight + 12
                            : 12.0;

                        final showActivationPill =
                            shouldShowActivationStatusBanner(_activationStatus);
                        final activationPill = showActivationPill
                            ? tvTraverseOrder(
                                5,
                                _LoginEntryActivationPremium(
                                  status: _activationStatus,
                                  expiryDate: _activationExpiryDate,
                                  onActivate: _activateDeviceFromApp,
                                  showActivateButton:
                                      _activationUiEnforced &&
                                      !tvKeypadMode &&
                                      (_activationStatus.trim() != 'نشط' ||
                                          shouldOfferActivationRenewal(
                                            _activationExpiryDate,
                                          )),
                                  isTvDevice: isTvDevice,
                                  activateButtonFocusNode:
                                      _activationUiEnforced &&
                                          (_activationStatus.trim() != 'نشط' ||
                                              shouldOfferActivationRenewal(
                                                _activationExpiryDate,
                                              ))
                                      ? _activationButtonFocus
                                      : null,
                                  activateButtonOnKeyEvent:
                                      _activationUiEnforced &&
                                          (_activationStatus.trim() != 'نشط' ||
                                              shouldOfferActivationRenewal(
                                                _activationExpiryDate,
                                              ))
                                      ? (node, event) =>
                                            _tvActivationKeyEvent(event)
                                      : null,
                                ),
                              )
                            : null;

                        final topSection = Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                legalChip,
                                if (activationPill != null) ...[
                                  SizedBox(width: isTvDevice ? 8 : 6),
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: activationPill,
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                SizedBox(width: isTvDevice ? 8 : 6),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      langChip,
                                      SizedBox(width: isTvDevice ? 8 : 6),
                                      manageChip,
                                      SizedBox(width: isTvDevice ? 8 : 6),
                                      supportChip,
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );

                        final middleContent = Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!tvKeypadMode &&
                                !(isTvDevice && showManualCreds))
                              _LoginEntryHero(
                                isTvDevice: isTvDevice,
                                connectStyle: false,
                              ),
                            if (!tvKeypadMode &&
                                !(isTvDevice && showManualCreds))
                              SizedBox(
                                height: LoginPremiumTypography.gap(
                                  isTvDevice,
                                  tv: 8,
                                  mobile: 4,
                                ),
                              ),
                            // أثناء التحميل: عطّل الأزرار فقط — لا تحجب الشاشة كاملة (مراجعة Play).
                            Container(
                                padding: EdgeInsets.all(
                                  tvKeypadMode ? 0 : (isTvDevice ? 12 : 10),
                                ),
                                decoration: tvKeypadMode
                                    ? null
                                    : _loginGlassDecoration(radius: 22),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    tvTraverseOrder(
                                      7,
                                      TextField(
                                        controller: _codeController,
                                        focusNode: _codeFieldFocus,
                                        readOnly: isTvDevice || loadingAuth,
                                        showCursor: !isTvDevice && !loadingAuth,
                                        enabled: !loadingAuth,
                                        keyboardType: TextInputType.number,
                                        textInputAction: TextInputAction.done,
                                        maxLength: 6,
                                        textAlign: TextAlign.center,
                                        style: Get.textTheme.titleLarge!
                                            .copyWith(
                                              color: Colors.white,
                                              letterSpacing: 4,
                                              fontWeight: FontWeight.bold,
                                              fontSize:
                                                  LoginPremiumTypography.input(
                                                    isTvDevice,
                                                  ),
                                            ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration:
                                            _loginPremiumFieldDecoration(
                                              hint: 'access_code_hint'.tr,
                                              prefixIcon: LucideIcons.hash,
                                              isTvDevice: isTvDevice,
                                              suffixIcon: isTvDevice
                                                  ? Icon(
                                                      LucideIcons.grid_3x3,
                                                      size: 16,
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.45,
                                                          ),
                                                    )
                                                  : null,
                                            ).copyWith(counterText: ''),
                                        onTap: () {
                                          if (!isTvDevice || loadingAuth) {
                                            return;
                                          }
                                          _openTvCodeKeypad();
                                        },
                                        onSubmitted: (_) => _verifyAccessCode(),
                                      ),
                                    ),
                                    AnimatedSwitcher(
                                      duration: Duration(
                                        milliseconds: isTvDevice ? 200 : 280,
                                      ),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      layoutBuilder: (currentChild, previousChildren) {
                                        return Stack(
                                          alignment: Alignment.topCenter,
                                          children: [
                                            ...previousChildren,
                                            ?currentChild,
                                          ],
                                        );
                                      },
                                      transitionBuilder: (child, animation) {
                                        final slide = Tween<Offset>(
                                          begin: const Offset(0, 0.04),
                                          end: Offset.zero,
                                        ).animate(animation);
                                        return FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: slide,
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: showManualCreds
                                          ? AnimatedBuilder(
                                              key: const ValueKey(
                                                'manual-creds-visible',
                                              ),
                                              animation:
                                                  _manualCredsShakeController,
                                              builder: (context, child) {
                                                return Transform.translate(
                                                  offset: Offset(
                                                    _manualCredsShakeOffset
                                                        .value,
                                                    0,
                                                  ),
                                                  child: child,
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 14,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    tvTraverseOrder(
                                                      9,
                                                      TextField(
                                                        controller:
                                                            _manualUsernameController,
                                                        focusNode:
                                                            _manualUsernameFocus,
                                                        textInputAction:
                                                            TextInputAction
                                                                .next,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: Get
                                                            .textTheme
                                                            .titleSmall!
                                                            .copyWith(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                        decoration:
                                                            _loginPremiumFieldDecoration(
                                                              hint:
                                                                  'username'.tr,
                                                              prefixIcon:
                                                                  LucideIcons
                                                                      .user,
                                                              isTvDevice:
                                                                  isTvDevice,
                                                            ),
                                                        onSubmitted: (_) {
                                                          _manualPasswordFocus
                                                              .requestFocus();
                                                        },
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    tvTraverseOrder(
                                                      10,
                                                      TextField(
                                                        controller:
                                                            _manualPasswordController,
                                                        focusNode:
                                                            _manualPasswordFocus,
                                                        obscureText:
                                                            _isPasswordObscured,
                                                        textInputAction:
                                                            TextInputAction
                                                                .done,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: Get
                                                            .textTheme
                                                            .titleSmall!
                                                            .copyWith(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                        decoration: _loginPremiumFieldDecoration(
                                                          hint: 'password'.tr,
                                                          prefixIcon:
                                                              LucideIcons.lock,
                                                          isTvDevice:
                                                              isTvDevice,
                                                          suffixIcon: IconButton(
                                                            onPressed: () {
                                                              _togglePasswordVisibility();
                                                            },
                                                            icon: Icon(
                                                              _isPasswordObscured
                                                                  ? LucideIcons
                                                                        .eye_off
                                                                  : LucideIcons
                                                                        .eye,
                                                              size: 16,
                                                              color:
                                                                  LoginPremiumColors
                                                                      .gold
                                                                      .withValues(
                                                                        alpha:
                                                                            0.9,
                                                                      ),
                                                            ),
                                                          ),
                                                        ),
                                                        onSubmitted: (_) =>
                                                            _submitManualCredsAfterCode(),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    tvTraverseOrder(
                                                      11,
                                                      _LoginFocusShell(
                                                        focusNode:
                                                            _manualLoginFocus,
                                                        borderRadius: 14,
                                                        enabled: !loadingAuth,
                                                        onTap:
                                                            _submitManualCredsAfterCode,
                                                        onKeyEvent:
                                                            _tvManualLoginKeyEvent,
                                                        child: Container(
                                                          width:
                                                              double.infinity,
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                vertical: 12,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  14,
                                                                ),
                                                            gradient: LinearGradient(
                                                              colors: [
                                                                LoginPremiumColors
                                                                    .gold,
                                                                LoginPremiumColors
                                                                    .goldDark,
                                                              ],
                                                            ),
                                                          ),
                                                          child: Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .center,
                                                            children: [
                                                              const Icon(
                                                                LucideIcons
                                                                    .log_in,
                                                                size: 16,
                                                                color: Colors
                                                                    .black87,
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Text(
                                                                'login'.tr,
                                                                style: const TextStyle(
                                                                  color: Colors
                                                                      .black87,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
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
                                            )
                                          : const SizedBox.shrink(
                                              key: ValueKey(
                                                'manual-creds-hidden',
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );

                        Widget buildMethodsOnePage({
                          required bool compact,
                          required double gap,
                        }) {
                          _LoginMethodCard method({
                            required FocusNode focusNode,
                            required IconData icon,
                            required String titleKey,
                            required String hintKey,
                            required String descKey,
                            required VoidCallback onTap,
                            required double order,
                            KeyEventResult Function(FocusNode, KeyEvent)?
                            onKeyEvent,
                            bool recommended = false,
                          }) {
                            return _LoginMethodCard(
                              focusNode: focusNode,
                              icon: icon,
                              title: titleKey.tr,
                              hint: hintKey.tr,
                              description: descKey.tr,
                              onTap: onTap,
                              isTvDevice: isTvDevice,
                              traversalOrder: order,
                              onKeyEvent: onKeyEvent,
                              expand: true,
                              compact: compact,
                              recommended: recommended,
                            );
                          }

                          final xtreamCard = allowUsernameLogin
                              ? method(
                                  focusNode: _loginRouteFocus,
                                  icon: LucideIcons.lock_keyhole,
                                  titleKey: 'entry_method_xtream',
                                  hintKey: 'entry_method_xtream_hint',
                                  descKey: 'entry_method_xtream_desc',
                                  onTap: _openCredentialsLogin,
                                  order: 6,
                                  onKeyEvent: _tvLoginRouteKeyEvent,
                                  recommended: true,
                                )
                              : null;
                          final m3uCard = method(
                            focusNode: _m3uMethodFocus,
                            icon: LucideIcons.link_2,
                            titleKey: 'entry_method_m3u',
                            hintKey: 'entry_method_m3u_hint',
                            descKey: 'entry_method_m3u_desc',
                            onTap: _openM3uLogin,
                            order: 7,
                            onKeyEvent: _tvM3uMethodKeyEvent,
                          );
                          final codeCard = method(
                            focusNode: _codeMethodFocus,
                            icon: LucideIcons.ticket,
                            titleKey: 'entry_method_code',
                            hintKey: 'entry_method_code_hint',
                            descKey: 'entry_method_code_desc',
                            onTap: _openPlaylistCodeEntry,
                            order: 8,
                            onKeyEvent: _tvCodeMethodKeyEvent,
                          );
                          final qrCard = method(
                            focusNode: _qrMethodFocus,
                            icon: LucideIcons.qr_code,
                            titleKey: 'entry_method_qr',
                            hintKey: 'entry_method_qr_hint',
                            descKey: 'entry_method_qr_desc',
                            onTap: () {
                              unawaited(_openDeviceQrFromEntry());
                            },
                            order: 9,
                            onKeyEvent: _tvQrMethodKeyEvent,
                          );
                          final webCard = method(
                            focusNode: _webMethodFocus,
                            icon: LucideIcons.globe,
                            titleKey: 'entry_method_web',
                            hintKey: 'entry_method_web_hint',
                            descKey: 'entry_method_web_desc',
                            onTap: () {
                              unawaited(_openWebPlaylistsFromEntry());
                            },
                            order: 10,
                            onKeyEvent: _tvWebMethodKeyEvent,
                          );
                          final downloadsCard = method(
                            focusNode: _downloadsMethodFocus,
                            icon: LucideIcons.download,
                            titleKey: 'entry_method_downloads',
                            hintKey: 'entry_method_downloads_hint',
                            descKey: 'entry_method_downloads_desc',
                            onTap: () {
                              Get.toNamed(screenDownloads);
                            },
                            order: 11,
                            onKeyEvent: _tvDownloadsMethodKeyEvent,
                          );

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _LoginEntryHero(
                                isTvDevice: isTvDevice,
                                compact: compact,
                              ),
                              SizedBox(height: compact ? 8 : gap),
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: xtreamCard != null
                                          ? Row(
                                              children: [
                                                Expanded(child: xtreamCard),
                                                SizedBox(width: gap),
                                                Expanded(child: m3uCard),
                                              ],
                                            )
                                          : m3uCard,
                                    ),
                                    SizedBox(height: gap),
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          Expanded(child: codeCard),
                                          SizedBox(width: gap),
                                          Expanded(child: qrCard),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: gap),
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          Expanded(child: webCard),
                                          SizedBox(width: gap),
                                          Expanded(child: downloadsCard),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _LoginTrustBar(
                                isTvDevice: isTvDevice,
                                compact: compact,
                              ),
                            ],
                          );
                        }

                        // على التلفاز عند host-only (بدون hero): ارفع المحتوى للأعلى
                        final contentAlignment = (isTvDevice && showManualCreds)
                            ? Alignment.topCenter
                            : Alignment.center;

                        final pageBody = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                hPad,
                                isTvDevice ? 8 : 0,
                                hPad,
                                tvKeypadMode
                                    ? LoginPremiumTypography.gap(
                                        isTvDevice,
                                        tv: 16,
                                        mobile: 12,
                                      )
                                    : 0,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: cardMaxWidth,
                                  ),
                                  child: topSection,
                                ),
                              ),
                            ),
                            Expanded(
                              child: AnimatedPadding(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                padding: tvKeypadMode
                                    ? EdgeInsets.fromLTRB(
                                        hPad,
                                        LoginPremiumTypography.gap(
                                          isTvDevice,
                                          tv: 24,
                                          mobile: 18,
                                        ),
                                        hPad,
                                        _LoginEntryScreenState
                                                ._tvKeypadReserveHeight +
                                            24,
                                      )
                                    : EdgeInsets.zero,
                                child: tvKeypadMode
                                    ? Align(
                                        alignment: Alignment.topCenter,
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: cardMaxWidth,
                                          ),
                                          child: middleContent,
                                        ),
                                      )
                                    : showMethodsGrid
                                    ? Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: hPad,
                                        ),
                                        child: Center(
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: cardMaxWidth,
                                            ),
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                final h = constraints.maxHeight;
                                                final compact =
                                                    h <
                                                    (isTvDevice ? 520 : 420);
                                                final gap = compact
                                                    ? (isTvDevice ? 10.0 : 8.0)
                                                    : (isTvDevice
                                                          ? 14.0
                                                          : 10.0);
                                                return buildMethodsOnePage(
                                                  compact: compact,
                                                  gap: gap,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      )
                                    : _AuthPremiumOnePageFit(
                                        maxWidth: cardMaxWidth,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: hPad,
                                        ),
                                        alignment: contentAlignment,
                                        child: middleContent,
                                      ),
                              ),
                            ),
                            // Disclaimer ثابت في الأسفل (يظهر أيضاً بعد كود host-only)
                            if (!tvKeypadMode)
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  hPad,
                                  0,
                                  hPad,
                                  bottomPad,
                                ),
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
                                                'loading'.tr,
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
                            if (isTvDevice)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: ExcludeFocus(
                                  excluding: !_showTvCodeKeypad,
                                  child: SafeArea(
                                    top: false,
                                    child: IgnorePointer(
                                      ignoring: !_showTvCodeKeypad,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          0,
                                          12,
                                          8,
                                        ),
                                        child: AnimatedOpacity(
                                          opacity: _showTvCodeKeypad ? 1 : 0,
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          child: AnimatedSlide(
                                            duration: const Duration(
                                              milliseconds: 260,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            offset: _showTvCodeKeypad
                                                ? Offset.zero
                                                : const Offset(0, 0.2),
                                            child: Align(
                                              alignment: Alignment.bottomCenter,
                                              child: FractionallySizedBox(
                                                widthFactor: 0.5,
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF1A1D24,
                                                    ).withValues(alpha: 0.96),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.16,
                                                          ),
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.4,
                                                            ),
                                                        blurRadius: 20,
                                                        offset: const Offset(
                                                          0,
                                                          8,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          10,
                                                        ),
                                                    child: _TvAccessCodeKeypad(
                                                      visible:
                                                          _showTvCodeKeypad,
                                                      codeLength:
                                                          _codeController
                                                              .text
                                                              .length,
                                                      onDigit: _tvAppendDigit,
                                                      onBackspace: _tvBackspace,
                                                      onOk:
                                                          loadingAuth ||
                                                              _codeVerifyLoading
                                                          ? null
                                                          : _verifyAccessCode,
                                                      onExitUp:
                                                          _tvFocusExitKeypadUpward,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
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
