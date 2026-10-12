part of '../screens.dart';

/// تظهر عند رفض لوحة الترخيص أو عند غياب الاتصال بالإنترنت أثناء التحقق.
class LicenseInvalidScreen extends StatefulWidget {
  const LicenseInvalidScreen({super.key});

  @override
  State<LicenseInvalidScreen> createState() => _LicenseInvalidScreenState();
}

class _LicenseInvalidScreenState extends State<LicenseInvalidScreen> {
  bool _busy = false;
  LicenseVerifyResult _reason = LicenseVerifyResult.rejected;
  String? _detailCode;
  final FocusNode _retryFocus = FocusNode(debugLabel: 'license_retry');

  bool get _isOffline => _reason == LicenseVerifyResult.noConnection;
  bool get _isClockSkew => _reason == LicenseVerifyResult.clockSkew;
  bool get _isBlocked => _reason == LicenseVerifyResult.blocked;
  bool get _isPaused => _reason == LicenseVerifyResult.paused;

  String get _statusLabelKey {
    if (_isOffline) return 'license_status_offline';
    if (_isClockSkew) return 'license_status_clock';
    if (_isBlocked) return 'license_status_blocked';
    if (_isPaused) return 'license_status_paused';
    return 'license_status_rejected';
  }

  String? get _detailText {
    final code = (_detailCode ?? '').trim().toLowerCase();
    if (code.isEmpty) return null;
    switch (code) {
      case 'package_mismatch':
        return 'license_detail_package_mismatch'.tr;
      case 'url_mismatch':
        return 'license_detail_url_mismatch'.tr;
      case 'ticket_missing':
      case 'ticket_verify_failed':
      case 'ticket_issue_failed':
        return 'license_detail_ticket'.tr;
      case 'local_seal_failed':
        return 'license_detail_local_seal'.tr;
      case 'tls_pinning_failed':
        return 'license_detail_tls'.tr;
      case 'not_registered':
        return 'license_detail_not_registered'.tr;
      default:
        return '${'license_detail_code'.tr}: $code';
    }
  }

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is LicenseVerifyResult) {
      _reason = args;
    }
    _detailCode = SellerLicenseService.lastFailureCode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _retryFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _retryFocus.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    final result = await RuntimeSeal.primeAtLaunch();
    if (!mounted) return;
    if (!await RuntimeSeal.launchFullySealed(result)) {
      setState(() {
        _busy = false;
        _reason =
            result == LicenseVerifyResult.valid
                ? LicenseVerifyResult.rejected
                : result;
        _detailCode = SellerLicenseService.lastFailureCode;
      });
      return;
    }
    setState(() {
      _busy = false;
      _reason = result;
    });
    RuntimeSeal.startPulse();
    Get.offAllNamed(screenSplash);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: kDecorBackground,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final tv = isTv(context);
              final landscape = w >= h;
              final short = h < 430;
              final veryShort = h < 360;
              final padH = (w * 0.035).clamp(12.0, tv ? 28.0 : 20.0);
              final padV = (h * 0.03).clamp(8.0, 16.0);
              // عرض تصميم ثابت — FittedBox يصغّره ليتسع في الشاشة.
              final designW = landscape
                  ? (tv ? 860.0 : 720.0).clamp(0.0, w - padH * 2)
                  : (tv ? 560.0 : 400.0).clamp(0.0, w - padH * 2);

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                child: SizedBox(
                  width: w - padH * 2,
                  height: h - padV * 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: designW,
                      child: _buildContent(
                        tv: tv,
                        landscape: landscape,
                        short: short || veryShort,
                        veryShort: veryShort,
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

  Widget _buildContent({
    required bool tv,
    required bool landscape,
    required bool short,
    required bool veryShort,
  }) {
    final titleKey = _isOffline
        ? 'license_offline_title'
        : _isClockSkew
        ? 'license_clock_title'
        : _isBlocked
        ? 'license_blocked_title'
        : _isPaused
        ? 'license_paused_title'
        : 'license_invalid_title';
    final subtitleKey = _isOffline
        ? 'license_offline_subtitle'
        : _isClockSkew
        ? 'license_clock_subtitle'
        : _isBlocked
        ? 'license_blocked_subtitle'
        : _isPaused
        ? 'license_paused_subtitle'
        : 'license_invalid_subtitle';
    final statusColor = _isOffline
        ? const Color(0xFFFFA726)
        : _isClockSkew
        ? const Color(0xFF42A5F5)
        : _isPaused
        ? const Color(0xFFFFB300)
        : const Color(0xFFE53935);
    final statusIcon = _isOffline
        ? FontAwesomeIcons.wifi
        : _isClockSkew
        ? FontAwesomeIcons.clock
        : _isBlocked
        ? FontAwesomeIcons.ban
        : _isPaused
        ? FontAwesomeIcons.circlePause
        : FontAwesomeIcons.shieldHalved;
    final hintRows = _isOffline
        ? [
            (FontAwesomeIcons.wifi, 'license_offline_hint_wifi'),
            (FontAwesomeIcons.networkWired, 'license_offline_hint_router'),
            (FontAwesomeIcons.arrowsRotate, 'license_offline_hint_retry'),
          ]
        : _isClockSkew
        ? [
            (FontAwesomeIcons.clock, 'license_clock_hint_auto'),
            (FontAwesomeIcons.desktop, 'license_clock_hint_emulator'),
            (FontAwesomeIcons.arrowsRotate, 'license_clock_hint_retry'),
          ]
        : _isBlocked
        ? [
            (FontAwesomeIcons.ban, 'license_blocked_hint_panel'),
            (FontAwesomeIcons.headset, 'license_blocked_hint_contact'),
            (FontAwesomeIcons.arrowsRotate, 'license_blocked_hint_retry'),
          ]
        : _isPaused
        ? [
            (FontAwesomeIcons.circlePause, 'license_paused_hint_panel'),
            (FontAwesomeIcons.headset, 'license_paused_hint_contact'),
            (FontAwesomeIcons.arrowsRotate, 'license_paused_hint_retry'),
          ]
        : [
            (FontAwesomeIcons.code, 'license_invalid_hint_code'),
            (FontAwesomeIcons.user, 'license_invalid_hint_user'),
            (FontAwesomeIcons.globe, 'license_invalid_hint_panel'),
          ];

    final iconSize = veryShort
        ? (tv ? 36.0 : 40.0)
        : short
        ? (tv ? 44.0 : 48.0)
        : (tv ? 52.0 : 56.0);
    final titleSize = veryShort ? 18.0 : (short ? 20.0 : 22.0);
    final bodySize = veryShort ? 12.0 : (short ? 13.0 : 14.0);
    final btnH = veryShort ? 40.0 : (short ? 44.0 : 46.0);
    final gap = veryShort ? 8.0 : (short ? 10.0 : 12.0);

    final header = _buildHeader(
      titleKey: titleKey,
      subtitleKey: subtitleKey,
      statusColor: statusColor,
      statusIcon: statusIcon,
      iconSize: iconSize,
      titleSize: titleSize,
      bodySize: bodySize,
      gap: gap,
      compact: short || landscape,
    );

    final hints = _buildHintsBox(
      hintRows: hintRows,
      bodySize: bodySize,
      compact: short || landscape,
    );

    final button = SizedBox(
      width: double.infinity,
      height: btnH,
      child: Focus(
        focusNode: _retryFocus,
        child: FilledButton.icon(
          onPressed: _busy ? null : _retry,
          icon: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kColorBack,
                  ),
                )
              : FaIcon(
                  FontAwesomeIcons.arrowsRotate,
                  size: 16,
                  color: kColorBack,
                ),
          label: Text(
            _busy ? 'checking'.tr : 'license_invalid_retry'.tr,
            style: TextStyle(
              fontSize: bodySize + 1,
              fontWeight: FontWeight.w700,
              color: kColorBack,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: kColorPrimary,
            foregroundColor: kColorBack,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );

    // Landscape / شاشات عريضة: عمودين — كل شيء يظهر دفعة واحدة.
    if (landscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 5, child: header),
          SizedBox(width: gap + 6),
          Expanded(
            flex: 6,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                hints,
                SizedBox(height: gap),
                button,
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        SizedBox(height: gap),
        hints,
        SizedBox(height: gap + 2),
        button,
      ],
    );
  }

  Widget _buildHeader({
    required String titleKey,
    required String subtitleKey,
    required Color statusColor,
    required IconData statusIcon,
    required double iconSize,
    required double titleSize,
    required double bodySize,
    required double gap,
    required bool compact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 10 : 14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kColorCardLight.withValues(alpha: 0.85),
            boxShadow: [
              BoxShadow(
                color: kColorPrimary.withValues(alpha: 0.12),
                blurRadius: compact ? 12 : 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: FaIcon(statusIcon, size: iconSize, color: statusColor),
        ),
        SizedBox(height: gap),
        Text(
          titleKey.tr,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Get.textTheme.headlineSmall?.copyWith(
            color: kColorFontLight,
            fontWeight: FontWeight.w800,
            height: 1.15,
            fontSize: titleSize,
          ),
        ),
        SizedBox(height: gap * 0.7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: statusColor.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(statusIcon, size: 11, color: statusColor),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  '${'license_status_label'.tr}: ${_statusLabelKey.tr}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Get.textTheme.labelLarge?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: bodySize - 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: gap * 0.75),
        Text(
          subtitleKey.tr,
          textAlign: TextAlign.center,
          maxLines: compact ? 3 : 4,
          overflow: TextOverflow.ellipsis,
          style: Get.textTheme.bodyLarge?.copyWith(
            color: kColorHint,
            height: 1.25,
            fontSize: bodySize,
          ),
        ),
        if (_detailText != null) ...[
          SizedBox(height: gap * 0.55),
          Text(
            _detailText!,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Get.textTheme.bodySmall?.copyWith(
              color: statusColor.withValues(alpha: 0.95),
              height: 1.25,
              fontWeight: FontWeight.w600,
              fontSize: bodySize - 1,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHintsBox({
    required List<(IconData, String)> hintRows,
    required double bodySize,
    required bool compact,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: kColorCardDark,
        border: Border.all(
          color: kColorPrimary.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < hintRows.length; i++) ...[
            if (i > 0) SizedBox(height: compact ? 6 : 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: FaIcon(
                    hintRows[i].$1,
                    size: 13,
                    color: kColorPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hintRows[i].$2.tr,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: Get.textTheme.bodyMedium?.copyWith(
                      color: kColorFontLight.withValues(alpha: 0.92),
                      height: 1.25,
                      fontSize: bodySize,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
