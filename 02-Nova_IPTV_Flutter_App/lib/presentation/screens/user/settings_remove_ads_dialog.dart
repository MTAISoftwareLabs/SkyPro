part of '../screens.dart';

class _RemoveAdsPlan {
  const _RemoveAdsPlan({
    required this.id,
    required this.titleKey,
    required this.priceLabel,
    required this.noAds,
    this.bestValue = false,
  });

  final String id;
  final String titleKey;
  final String priceLabel;
  final bool noAds;
  final bool bestValue;
}

const List<_RemoveAdsPlan> _kRemoveAdsPlans = [
  _RemoveAdsPlan(
    id: '1_month',
    titleKey: 'remove_ads_plan_1m',
    priceLabel: '\$0.99',
    noAds: false,
  ),
  _RemoveAdsPlan(
    id: '3_months',
    titleKey: 'remove_ads_plan_3m',
    priceLabel: '\$1.5',
    noAds: false,
  ),
  _RemoveAdsPlan(
    id: '6_months',
    titleKey: 'remove_ads_plan_6m',
    priceLabel: '\$2',
    noAds: false,
  ),
  _RemoveAdsPlan(
    id: '1_year',
    titleKey: 'remove_ads_plan_1y',
    priceLabel: '\$10',
    noAds: true,
  ),
  _RemoveAdsPlan(
    id: '2_years',
    titleKey: 'remove_ads_plan_2y',
    priceLabel: '\$15',
    noAds: true,
  ),
  _RemoveAdsPlan(
    id: 'lifetime',
    titleKey: 'remove_ads_plan_lifetime',
    priceLabel: '\$20',
    noAds: true,
    bestValue: true,
  ),
];

Future<void> showRemoveAdsActivateDialog(
  BuildContext context, {
  FocusNode? returnFocus,
}) async {
  settingsReleaseTouchFocus(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _RemoveAdsActivateDialog(),
  );
  if (returnFocus != null && context.mounted && isTv(context)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (returnFocus.canRequestFocus) returnFocus.requestFocus();
    });
  }
}

class _RemoveAdsActivateDialog extends StatefulWidget {
  const _RemoveAdsActivateDialog();

  @override
  State<_RemoveAdsActivateDialog> createState() =>
      _RemoveAdsActivateDialogState();
}

class _RemoveAdsActivateDialogState extends State<_RemoveAdsActivateDialog> {
  String _selectedId = _kRemoveAdsPlans.last.id;
  bool _sending = false;
  bool _closeFocused = false;
  bool _contactFocused = false;
  final Map<String, bool> _planFocused = {
    for (final p in _kRemoveAdsPlans) p.id: false,
  };

  final FocusNode _closeFocus = FocusNode(debugLabel: 'remove_ads_close');
  final FocusNode _contactFocus = FocusNode(debugLabel: 'remove_ads_contact');
  final Map<String, FocusNode> _planFocus = {
    for (final p in _kRemoveAdsPlans)
      p.id: FocusNode(debugLabel: 'remove_ads_plan_${p.id}'),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isTv(context)) {
        _planFocus[_selectedId]?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _closeFocus.dispose();
    _contactFocus.dispose();
    for (final n in _planFocus.values) {
      n.dispose();
    }
    super.dispose();
  }

  _RemoveAdsPlan get _selectedPlan =>
      _kRemoveAdsPlans.firstWhere((p) => p.id == _selectedId);

  /// Close → plans (top→bottom) → Contact Us. D-pad follows this tree, not geometry.
  List<FocusNode> get _tvFocusChain => [
        _closeFocus,
        for (final p in _kRemoveAdsPlans) _planFocus[p.id]!,
        _contactFocus,
      ];

  int _tvFocusIndex() {
    final chain = _tvFocusChain;
    final current = FocusManager.instance.primaryFocus;
    if (current == null) return -1;
    for (var i = 0; i < chain.length; i++) {
      FocusNode? walk = current;
      while (walk != null) {
        if (identical(walk, chain[i])) return i;
        walk = walk.parent;
      }
      if (chain[i].hasFocus) return i;
    }
    return -1;
  }

  void _handleTvDirectionalFocus(TraversalDirection direction) {
    if (!isTv(context)) return;
    final chain = _tvFocusChain;
    var idx = _tvFocusIndex();
    if (idx < 0) {
      _planFocus[_selectedId]?.requestFocus();
      return;
    }

    switch (direction) {
      case TraversalDirection.down:
        if (idx < chain.length - 1) chain[idx + 1].requestFocus();
      case TraversalDirection.up:
        if (idx > 0) chain[idx - 1].requestFocus();
      case TraversalDirection.left:
      case TraversalDirection.right:
        break;
    }
  }

  Widget _wrapTvFocusTree(Widget child) {
    if (!isTv(context)) return child;
    return Actions(
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            _handleTvDirectionalFocus(intent.direction);
            return null;
          },
        ),
      },
      child: child,
    );
  }

  Future<void> _onContactUs() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      var deviceId = (GetStorage().read('device_id') ?? '').toString().trim();
      if (deviceId.isEmpty) {
        deviceId = await ActivationApi().getDeviceId();
      }
      final planLabel =
          '${_selectedPlan.titleKey.tr} (${_selectedPlan.priceLabel})';
      final message = 'remove_ads_contact_message'
          .tr
          .replaceAll('{plan}', planLabel)
          .replaceAll('{device_id}', deviceId.isEmpty ? '—' : deviceId);

      final support =
          (GetStorage().read('support_contact_url') ?? '').toString().trim();
      if (support.isEmpty) {
        if (!mounted) return;
        Get.snackbar(
          'remove_ads_dialog_title'.tr,
          'remove_ads_no_contact_url'.tr,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.black87,
          colorText: Colors.white,
        );
        return;
      }

      final ok = await openSupportContactWithMessage(message);
      if (!ok && mounted) {
        Get.snackbar(
          'remove_ads_dialog_title'.tr,
          'remove_ads_open_failed'.tr,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.black87,
          colorText: Colors.white,
        );
      } else if (mounted) {
        Navigator.of(context).maybePop();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _benefit({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required double iconSize,
    required double titleSize,
    required double subSize,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: iconSize + 14,
            height: iconSize + 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Icon(icon, color: color, size: iconSize),
          ),
          SizedBox(height: titleSize > 10 ? 4 : 3),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: titleSize,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: subSize,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _planRow(_RemoveAdsPlan plan, {required bool compact}) {
    final selected = plan.id == _selectedId;
    final focused = settingsShowFocusDecor(
      context,
      _planFocused[plan.id] == true,
    );
    final accent = plan.bestValue
        ? const Color(0xFF8B5CF6)
        : plan.noAds
            ? const Color(0xFF22C55E)
            : Colors.white.withValues(alpha: 0.14);
    final bg = focused
        ? kColorPrimary.withValues(alpha: 0.18)
        : selected
            ? (plan.bestValue
                ? const Color(0xFF8B5CF6).withValues(alpha: 0.14)
                : plan.noAds
                    ? const Color(0xFF22C55E).withValues(alpha: 0.10)
                    : kColorPrimary.withValues(alpha: 0.10))
            : const Color(0xFF151B2B);
    final borderColor = focused
        ? kColorPrimary
        : selected
            ? accent
            : accent.withValues(alpha: 0.55);
    final vPad = compact ? 5.0 : 7.0;
    final fontSize = compact ? 11.5 : 12.5;
    final badgeSize = compact ? 9.0 : 10.0;

    return Focus(
      focusNode: _planFocus[plan.id],
      onFocusChange: (v) {
        if (!isTv(context)) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        if (_planFocused[plan.id] != v) {
          setState(() => _planFocused[plan.id] = v);
        }
      },
      onKeyEvent: isTv(context)
          ? (node, event) => settingsTvActivateOnSelect(event, () {
                setState(() => _selectedId = plan.id);
              })
          : null,
      child: Padding(
        padding: EdgeInsets.only(bottom: compact ? 4 : 5),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _selectedId = plan.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: vPad),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: borderColor,
                  width: focused ? 2 : (selected || plan.noAds ? 1.4 : 1),
                ),
                boxShadow: settingsThemedFocusGlow(focused),
              ),
              child: Row(
                children: [
                  Container(
                    width: compact ? 14 : 16,
                    height: compact ? 14 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected || focused
                            ? kColorPrimary
                            : Colors.white38,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: compact ? 6 : 7,
                              height: compact ? 6 : 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: kColorPrimary,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      plan.titleKey.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: fontSize,
                      ),
                    ),
                  ),
                  Text(
                    plan.priceLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w800,
                      fontSize: fontSize,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 6 : 7,
                      vertical: compact ? 2 : 3,
                    ),
                    decoration: BoxDecoration(
                      color: plan.noAds
                          ? const Color(0xFF22C55E).withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: plan.noAds
                            ? const Color(0xFF22C55E).withValues(alpha: 0.55)
                            : Colors.white24,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (plan.noAds) ...[
                          Icon(
                            FontAwesomeIcons.crown,
                            size: badgeSize - 1,
                            color: kColorPrimary,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          plan.noAds
                              ? 'remove_ads_no_ads'.tr
                              : 'remove_ads_with_ads'.tr,
                          style: TextStyle(
                            color: plan.noAds
                                ? const Color(0xFF86EFAC)
                                : Colors.white70,
                            fontSize: badgeSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (plan.bestValue) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 5 : 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            FontAwesomeIcons.crown,
                            size: 7,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'remove_ads_best_value'.tr,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: badgeSize - 0.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tv = isTv(context);
    final wide = size.width >= 700;
    final short = size.height < 520;
    final compact = !wide || short || size.height < 600;
    final maxW = wide ? math.min(640.0, size.width * 0.82) : size.width * 0.94;
    final maxH = size.height * (tv ? 0.92 : 0.94);
    final closeFocused = settingsShowFocusDecor(context, _closeFocused);
    final contactFocused = settingsShowFocusDecor(context, _contactFocused);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: wide ? 28 : 10,
        vertical: short ? 8 : 12,
      ),
      child: _wrapTvFocusTree(
        FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
            child: Material(
              color: const Color(0xFF0B1220),
              borderRadius: BorderRadius.circular(14),
              child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: kColorPrimary.withValues(alpha: 0.55),
                  width: 1.3,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF121A2C),
                    const Color(0xFF0B1220),
                    kColorPrimary.withValues(alpha: 0.05),
                  ],
                ),
              ),
              // One page, no scroll — scale down if needed so all fits.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : maxW,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 10 : 12,
                          compact ? 8 : 10,
                          compact ? 8 : 10,
                          compact ? 8 : 10,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Image.asset(
                                    kIconSplash,
                                    width: compact ? 28 : 32,
                                    height: compact ? 28 : 32,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => Icon(
                                      FontAwesomeIcons.tv,
                                      color: kColorPrimary,
                                      size: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'remove_ads_dialog_title'.tr,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: compact ? 13 : 14.5,
                                        ),
                                      ),
                                      Text(
                                        'remove_ads_dialog_subtitle'.tr,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.55),
                                          fontSize: compact ? 9.5 : 10.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                FocusTraversalOrder(
                                  order: const NumericFocusOrder(1),
                                  child: Focus(
                                    focusNode: _closeFocus,
                                    onFocusChange: (v) {
                                      if (!tv) {
                                        if (v) {
                                          settingsReleaseTouchFocus(context);
                                        }
                                        return;
                                      }
                                      if (_closeFocused != v) {
                                        setState(() => _closeFocused = v);
                                      }
                                    },
                                    onKeyEvent: tv
                                        ? (node, event) =>
                                            settingsTvActivateOnSelect(
                                              event,
                                              () => Navigator.of(context)
                                                  .maybePop(),
                                            )
                                        : null,
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 120),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: closeFocused
                                              ? kColorPrimary
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                        boxShadow: settingsThemedFocusGlow(
                                          closeFocused,
                                        ),
                                      ),
                                      child: ExcludeFocus(
                                        child: IconButton(
                                          onPressed: () =>
                                              Navigator.of(context).maybePop(),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 34,
                                            minHeight: 34,
                                          ),
                                          icon: Icon(
                                            Icons.close,
                                            color: closeFocused
                                                ? Colors.white
                                                : Colors.white70,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: compact ? 6 : 8),
                            Row(
                              children: [
                                _benefit(
                                  icon: FontAwesomeIcons.ban,
                                  color: const Color(0xFFEF4444),
                                  title: 'remove_ads_benefit_no_ads'.tr,
                                  subtitle:
                                      'remove_ads_benefit_no_ads_desc'.tr,
                                  iconSize: compact ? 12 : 14,
                                  titleSize: compact ? 10 : 11,
                                  subSize: compact ? 8.5 : 9,
                                ),
                                _benefit(
                                  icon: FontAwesomeIcons.rocket,
                                  color: const Color(0xFF3B82F6),
                                  title: 'remove_ads_benefit_experience'.tr,
                                  subtitle:
                                      'remove_ads_benefit_experience_desc'.tr,
                                  iconSize: compact ? 12 : 14,
                                  titleSize: compact ? 10 : 11,
                                  subSize: compact ? 8.5 : 9,
                                ),
                                _benefit(
                                  icon: FontAwesomeIcons.heart,
                                  color: const Color(0xFFEC4899),
                                  title: 'remove_ads_benefit_support'.tr,
                                  subtitle:
                                      'remove_ads_benefit_support_desc'.tr,
                                  iconSize: compact ? 12 : 14,
                                  titleSize: compact ? 10 : 11,
                                  subSize: compact ? 8.5 : 9,
                                ),
                              ],
                            ),
                            SizedBox(height: compact ? 6 : 8),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                'remove_ads_choose_plan'.tr,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: compact ? 12 : 13,
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 4 : 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: wide ? 7 : 1,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var i = 0;
                                          i < _kRemoveAdsPlans.length;
                                          i++)
                                        FocusTraversalOrder(
                                          order: NumericFocusOrder(10.0 + i),
                                          child: _planRow(
                                            _kRemoveAdsPlans[i],
                                            compact: compact,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (wide) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                          color: kColorPrimary
                                              .withValues(alpha: 0.3),
                                        ),
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            kColorPrimary
                                                .withValues(alpha: 0.16),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            FontAwesomeIcons.crown,
                                            color: kColorPrimary,
                                            size: compact ? 22 : 28,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'remove_ads_lifetime_fun'.tr,
                                            textAlign: TextAlign.center,
                                            maxLines: 3,
                                            style: TextStyle(
                                              color: kColorPrimary,
                                              fontWeight: FontWeight.w900,
                                              fontSize: compact ? 9.5 : 11,
                                              height: 1.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: compact ? 4 : 6),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: compact ? 6 : 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    FontAwesomeIcons.envelope,
                                    color: Colors.white70,
                                    size: compact ? 12 : 13,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      '${'remove_ads_contact_title'.tr} — ${'remove_ads_contact_body'.tr}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.65),
                                        fontSize: compact ? 9.5 : 10.5,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: compact ? 6 : 8),
                            FocusTraversalOrder(
                              order: const NumericFocusOrder(50),
                              child: Focus(
                                focusNode: _contactFocus,
                                onFocusChange: (v) {
                                  if (!tv) {
                                    if (v) {
                                      settingsReleaseTouchFocus(context);
                                    }
                                    return;
                                  }
                                  if (_contactFocused != v) {
                                    setState(() => _contactFocused = v);
                                  }
                                },
                                onKeyEvent: tv
                                    ? (node, event) =>
                                        settingsTvActivateOnSelect(
                                          event,
                                          _onContactUs,
                                        )
                                    : null,
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 120),
                                  height: compact ? 40 : 44,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(
                                      color: contactFocused
                                          ? kColorPrimary
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                    boxShadow: settingsThemedFocusGlow(
                                      contactFocused,
                                    ),
                                  ),
                                  child: ExcludeFocus(
                                    child: ElevatedButton(
                                      onPressed:
                                          _sending ? null : _onContactUs,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: contactFocused
                                            ? const Color(0xFF3B82F6)
                                            : const Color(0xFF2563EB),
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            const Color(0xFF2563EB)
                                                .withValues(alpha: 0.5),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(9),
                                        ),
                                        elevation: 0,
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: _sending
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  FontAwesomeIcons.paperPlane,
                                                  size: 12,
                                                ),
                                                const SizedBox(width: 7),
                                                Text(
                                                  'remove_ads_contact_btn'.tr,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize:
                                                        compact ? 12.5 : 13.5,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.chevron_right,
                                                  size: 18,
                                                ),
                                              ],
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
