part of '../screens.dart';

/// يضغط المحتوى ليظهر كاملاً في شاشة واحدة بدون تمرير.
class _AuthPremiumOnePageFit extends StatelessWidget {
  const _AuthPremiumOnePageFit({
    required this.child,
    this.maxWidth,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double? maxWidth;
  final EdgeInsets padding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = maxWidth ?? constraints.maxWidth;
        return Padding(
          padding: padding,
          child: Align(
            alignment: alignment,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: alignment,
              child: SizedBox(
                width: width.clamp(0, constraints.maxWidth),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// عرض QR الجهاز في حوار منبثق عند الضغط على الأيقونة.
/// [onPoll] يُستدعى كل ثانيتين (مثل شاشات register) لاكتشاف المسح والدخول التلقائي.
void _showDeviceQrDialog({
  required String deviceId,
  Future<void> Function()? onPoll,
}) {
  prepareDeviceQrDialogLoginMode();
  Get.dialog(
    barrierColor: Colors.black.withValues(alpha: 0.72),
    barrierDismissible: true,
    _DeviceQrDialog(
      initialDeviceId: deviceId,
      onPoll: onPoll,
    ),
  );
}

class _DeviceQrDialog extends StatefulWidget {
  const _DeviceQrDialog({
    required this.initialDeviceId,
    this.onPoll,
  });

  final String initialDeviceId;
  /// سحب التفعيل / محاولة الدخول التلقائي من الشاشة الأم كل ثانيتين.
  final Future<void> Function()? onPoll;

  @override
  State<_DeviceQrDialog> createState() => _DeviceQrDialogState();
}

enum _QrLinkVisual { idle, success, failed }

class _DeviceQrDialogState extends State<_DeviceQrDialog>
    with SingleTickerProviderStateMixin {
  final FocusNode _closeFocus = FocusNode();
  String _deviceId = '';
  bool _loading = false;
  Timer? _qrPollTimer;
  Timer? _resultWatchTimer;
  bool _qrPollInFlight = false;
  _QrLinkVisual _linkVisual = _QrLinkVisual.idle;
  late final AnimationController _scanLaserCtrl;
  late final Animation<double> _scanLaserAnim;

  @override
  void initState() {
    super.initState();
    GetStorage().remove(kStorageQrLinkResult);
    _scanLaserCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    )..repeat(reverse: true);
    _scanLaserAnim = CurvedAnimation(
      parent: _scanLaserCtrl,
      curve: Curves.easeInOut,
    );
    _deviceId = widget.initialDeviceId.trim();
    if (_deviceId.isEmpty) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveDeviceId());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && isTv(context)) _closeFocus.requestFocus();
      });
    }
    _startQrBackgroundPoll();
    _resultWatchTimer = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) => _checkQrLinkResult(),
    );
  }

  void _checkQrLinkResult() {
    if (!mounted || _linkVisual != _QrLinkVisual.idle) return;
    final result = GetStorage().read(kStorageQrLinkResult);
    if (result == 'success') {
      GetStorage().remove(kStorageQrLinkResult);
      setState(() => _linkVisual = _QrLinkVisual.success);
      _scanLaserCtrl.stop();
      _qrPollTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 2200), () {
        if (mounted && Get.isDialogOpen == true) Get.back();
      });
    } else if (result == 'failed') {
      GetStorage().remove(kStorageQrLinkResult);
      setState(() => _linkVisual = _QrLinkVisual.failed);
      _scanLaserCtrl.stop();
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (!mounted) return;
        setState(() => _linkVisual = _QrLinkVisual.idle);
        _scanLaserCtrl.repeat(reverse: true);
      });
    }
  }

  void _startQrBackgroundPoll() {
    _qrPollTimer?.cancel();
    // سحب التفعيل أثناء فتح QR: كل ثانيتين
    _qrPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_runQrBackgroundPoll());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runQrBackgroundPoll());
    });
  }

  void _keepQrLoginModeAlive() {
    final box = GetStorage();
    if (box.read(kStorageAddingNewAccount) == true) {
      box.write(kStorageQrAwaitNewAccount, true);
      box.remove(kStorageForceQrAutoLogin);
    } else {
      box.write(kStorageForceQrAutoLogin, true);
      box.remove(kStorageSuppressPlaylistAutoLogin);
    }
  }

  Future<void> _runQrBackgroundPoll() async {
    if (!mounted || _qrPollInFlight) return;
    if (Get.isDialogOpen != true) return;
    _qrPollInFlight = true;
    try {
      _keepQrLoginModeAlive();
      final poll = widget.onPoll;
      if (poll != null) {
        await poll();
      }
    } finally {
      _qrPollInFlight = false;
    }
  }

  Future<void> _resolveDeviceId() async {
    try {
      final id = (await ActivationApi().getDeviceId()).trim();
      if (!mounted) return;
      setState(() {
        _deviceId = id;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && isTv(context)) _closeFocus.requestFocus();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && isTv(context)) _closeFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _qrPollTimer?.cancel();
    _resultWatchTimer?.cancel();
    _scanLaserCtrl.dispose();
    _closeFocus.dispose();
    // إغلاق بدون دخول: أوقف وضع إجبار QR
    final box = GetStorage();
    box.remove(kStorageForceQrAutoLogin);
    box.remove(kStorageQrLinkResult);
    if (box.read(kStorageAddingNewAccount) != true) {
      clearQrAwaitNewAccountFlags();
    }
    super.dispose();
  }

  void _close() => Get.back();

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final size = MediaQuery.sizeOf(context);
    final screenW = size.width;
    final screenH = size.height;
    final viewPad = MediaQuery.paddingOf(context);

    final insetH = tv ? 24.0 : 16.0;
    final insetV = tv ? 12.0 : 16.0;
    final dialogW = tv
        ? (screenW * 0.42).clamp(280.0, 420.0)
        : (screenW * 0.72).clamp(280.0, 400.0);
    final maxDialogH =
        (screenH - viewPad.vertical - insetV * 2).clamp(220.0, screenH);

    final padH = tv ? 14.0 : 18.0;
    final padTop = tv ? 36.0 : 40.0;
    final padBottom = tv ? 16.0 : 18.0;
    // احتياطي واقعي: أيقونة + عنوان + سطرين تعليمات + شريط المعرف + فراغات
    final headerH = tv ? 108.0 : 128.0;
    final idBarH = tv ? 64.0 : 72.0;
    final gaps = tv ? 18.0 : 22.0;
    final qrPad = tv ? 8.0 : 10.0;
    final availableH =
        maxDialogH - padTop - padBottom - headerH - idBarH - gaps;
    final availableW = dialogW - padH * 2 - qrPad * 2;
    final qrSize = (availableH < availableW ? availableH : availableW)
        .clamp(tv ? 100.0 : 120.0, tv ? 180.0 : 200.0);

    final radius = tv ? 16.0 : 20.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: insetH, vertical: insetV),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogW,
          maxHeight: maxDialogH,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: dialogW,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xF01A1A24), Color(0xF0121218)],
              ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: LoginPremiumColors.gold.withValues(alpha: 0.38),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padH,
                    padTop,
                    padH,
                    padBottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: tv ? 32 : 40,
                        height: tv ? 32 : 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: LoginPremiumColors.gold.withValues(alpha: 0.14),
                          border: Border.all(
                            color: LoginPremiumColors.gold.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Icon(
                          LucideIcons.qr_code,
                          size: tv ? 15 : 18,
                          color: LoginPremiumColors.gold,
                        ),
                      ),
                      SizedBox(height: tv ? 6 : 8),
                      Text(
                        'device_qr_dialog_title'.tr,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Get.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: tv ? 14 : 16,
                        ),
                      ),
                      SizedBox(height: tv ? 4 : 6),
                      Text(
                        'device_qr_dialog_instructions'.tr,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Get.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          fontSize: tv ? 11 : 12.5,
                        ),
                      ),
                      SizedBox(height: tv ? 8 : 10),
                      if (_loading)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: qrSize * 0.2),
                          child: CircularProgressIndicator(
                            color: LoginPremiumColors.gold,
                            strokeWidth: 2.4,
                          ),
                        )
                      else if (_deviceId.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: qrSize * 0.15),
                          child: Text(
                            'loading'.tr,
                            style: Get.textTheme.bodyMedium?.copyWith(
                              color: Colors.white54,
                            ),
                          ),
                        )
                      else ...[
                        Container(
                          width: qrSize + qrPad * 2,
                          height: qrSize + qrPad * 2,
                          padding: EdgeInsets.all(qrPad),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(tv ? 10 : 14),
                            boxShadow: [
                              BoxShadow(
                                color: LoginPremiumColors.gold.withValues(
                                  alpha: 0.18,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(tv ? 6 : 8),
                            child: SizedBox(
                              width: qrSize,
                              height: qrSize,
                              child: Stack(
                                clipBehavior: Clip.hardEdge,
                                fit: StackFit.expand,
                                children: [
                                  // QR بمستوى تصحيح عالٍ + فراغ محجوز للشعار (لا يُرسم فوق الموديولات)
                                  _DeviceQrWithLogoHole(
                                    data: _deviceId,
                                    size: qrSize,
                                    showLogo:
                                        _linkVisual == _QrLinkVisual.idle,
                                  ),
                                  // خط مسح أحمر يتحرك رأسيًا (مثل فيديو المرجع)
                                  if (_linkVisual == _QrLinkVisual.idle)
                                    IgnorePointer(
                                      child: AnimatedBuilder(
                                        animation: _scanLaserAnim,
                                        builder: (context, _) {
                                          final y = _scanLaserAnim.value *
                                              (qrSize - 3);
                                          return Stack(
                                            children: [
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                top: y,
                                                child: Container(
                                                  height: 2.5,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFE53935,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: const Color(
                                                          0xFFE53935,
                                                        ).withValues(
                                                          alpha: 0.85,
                                                        ),
                                                        blurRadius: 10,
                                                        spreadRadius: 1.2,
                                                      ),
                                                      BoxShadow(
                                                        color: const Color(
                                                          0xFFFF8A80,
                                                        ).withValues(
                                                          alpha: 0.45,
                                                        ),
                                                        blurRadius: 16,
                                                        spreadRadius: 0.5,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  if (_linkVisual != _QrLinkVisual.idle)
                                    Positioned(
                                      left: qrSize *
                                          (1 - _DeviceQrWithLogoHole.holeRatio) /
                                          2,
                                      top: qrSize *
                                          (1 - _DeviceQrWithLogoHole.holeRatio) /
                                          2,
                                      width: qrSize *
                                          _DeviceQrWithLogoHole.holeRatio,
                                      height: qrSize *
                                          _DeviceQrWithLogoHole.holeRatio,
                                      child: ClipOval(
                                        child: ColoredBox(
                                          color: Colors.white,
                                          child: _linkVisual ==
                                                  _QrLinkVisual.success
                                              ? Lottie.asset(
                                                  'assets/animations/Checked.json',
                                                  fit: BoxFit.contain,
                                                  repeat: false,
                                                )
                                              : Image.asset(
                                                  'assets/animations/failed.gif',
                                                  fit: BoxFit.contain,
                                                ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: tv ? 10 : 12),
                        // شريط المعرف داخل الإطار دائماً
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: _DeviceQrIdCopyBar(
                            deviceId: _deviceId,
                            compact: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  top: tv ? 6 : 8,
                  left: tv ? 6 : 8,
                  child: _LoginFocusShell(
                    focusNode: _closeFocus,
                    autofocus: tv,
                    borderRadius: 12,
                    onTap: _close,
                    child: Container(
                      width: tv ? 32 : 36,
                      height: tv ? 32 : 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Icon(
                        LucideIcons.x,
                        size: tv ? 15 : 16,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
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

/// QR بمستوى تصحيح H + فراغ دائري للشعار (بدون موديولات بيانات تحت الشعار).
class _DeviceQrWithLogoHole extends StatelessWidget {
  const _DeviceQrWithLogoHole({
    required this.data,
    required this.size,
    this.showLogo = true,
  });

  final String data;
  final double size;
  final bool showLogo;

  /// قطر الشعار الحالي (يبقى كما هو بصرياً).
  static const double holeRatio = 0.42;

  /// فراغ الموديولات أكبر قليلاً من الشعار حتى لا يبقى أي مربع تحت حافة الشعار.
  static const double clearRatio = 0.45;

  @override
  Widget build(BuildContext context) {
    final hole = size * holeRatio;
    final holeLeft = (size - hole) / 2;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DeviceQrHolePainter(
                data: data,
                clearRatio: clearRatio,
              ),
            ),
          ),
          if (showLogo)
            Positioned(
              left: holeLeft,
              top: holeLeft,
              width: hole,
              height: hole,
              child: ClipOval(
                child: ColoredBox(
                  color: Colors.white,
                  child: Image.asset(
                    'assets/images/logo app.png',
                    width: hole,
                    height: hole,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceQrHolePainter extends CustomPainter {
  _DeviceQrHolePainter({
    required this.data,
    required this.clearRatio,
  }) : _qrImage = _buildQrImage(data);

  final String data;
  final double clearRatio;
  final QrImage? _qrImage;

  /// مواضع أنماط المحاذاة (نسخ مبسّط من مواصفات QR للإصدارات الشائعة).
  static const Map<int, List<int>> _alignPos = {
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30],
    6: [6, 34],
    7: [6, 22, 38],
    8: [6, 24, 42],
    9: [6, 26, 46],
    10: [6, 28, 50],
    11: [6, 30, 54],
    12: [6, 32, 58],
    13: [6, 34, 62],
  };

  static QrImage? _buildQrImage(String data) {
    final payload = data.trim();
    if (payload.isEmpty) return null;
    try {
      // إصدار أعلى = تصحيح أخطاء أكثر → يبقى قابلاً للمسح مع فراغ الشعار الكبير
      final base = QrCode.fromData(
        data: payload,
        errorCorrectLevel: QrErrorCorrectLevel.H,
      );
      final bumped = (base.typeNumber + 4).clamp(1, 40);
      final code = QrCode(bumped, QrErrorCorrectLevel.H)..addData(payload);
      return QrImage(code);
    } catch (_) {
      try {
        final code = QrCode.fromData(
          data: payload,
          errorCorrectLevel: QrErrorCorrectLevel.H,
        );
        return QrImage(code);
      } catch (_) {
        return null;
      }
    }
  }

  /// أنماط وظيفية يجب إبقاؤها دائماً (عيون / توقيت / محاذاة / تنسيق).
  static bool _isReserved(int x, int y, int n, int typeNumber) {
    if (x <= 8 && y <= 8) return true;
    if (x >= n - 8 && y <= 8) return true;
    if (x <= 8 && y >= n - 8) return true;
    if (x == 6 || y == 6) return true;
    if (x == 8 && y == n - 8) return true;
    if (typeNumber >= 7) {
      if (y < 6 && x >= n - 11) return true;
      if (x < 6 && y >= n - 11) return true;
    }
    final pos = _alignPos[typeNumber];
    if (pos != null) {
      for (final row in pos) {
        for (final col in pos) {
          final nearFinder = (row <= 8 && col <= 8) ||
              (row <= 8 && col >= n - 8) ||
              (row >= n - 8 && col <= 8);
          if (nearFinder) continue;
          if ((x - col).abs() <= 2 && (y - row).abs() <= 2) return true;
        }
      }
    }
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final qr = _qrImage;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );
    if (qr == null) return;

    final moduleCount = qr.moduleCount;
    final typeNumber = qr.typeNumber;
    final pixel = size.shortestSide / moduleCount;
    final center = Offset(size.width / 2, size.height / 2);
    final clearRadius = size.shortestSide * clearRatio / 2;
    final logoRadius =
        size.shortestSide * _DeviceQrWithLogoHole.holeRatio / 2;

    final dark = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    // 1) موديولات البيانات فقط خارج فراغ الشعار
    for (var x = 0; x < moduleCount; x++) {
      for (var y = 0; y < moduleCount; y++) {
        if (_isReserved(x, y, moduleCount, typeNumber)) continue;
        if (!qr.isDark(y, x)) continue;
        final left = x * pixel;
        final top = y * pixel;
        final moduleCenter = Offset(left + pixel / 2, top + pixel / 2);
        if ((moduleCenter - center).distance <= clearRadius) continue;
        canvas.drawRect(
          Rect.fromLTWH(left, top, pixel + 0.4, pixel + 0.4),
          dark,
        );
      }
    }

    // 2) قرص أبيض تحت الشعار (بدون بيانات تحته)
    canvas.drawCircle(
      center,
      clearRadius,
      Paint()..color = Colors.white,
    );

    // 3) أعد رسم الأنماط الوظيفية فوق الأبيض إن لزم (عيون/توقيت/محاذاة)
    for (var x = 0; x < moduleCount; x++) {
      for (var y = 0; y < moduleCount; y++) {
        if (!_isReserved(x, y, moduleCount, typeNumber)) continue;
        if (!qr.isDark(y, x)) continue;
        final left = x * pixel;
        final top = y * pixel;
        canvas.drawRect(
          Rect.fromLTWH(left, top, pixel + 0.4, pixel + 0.4),
          dark,
        );
      }
    }

    // إطار رفيع حول الشعار
    canvas.drawCircle(
      center,
      logoRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.shortestSide * 0.005).clamp(1.0, 1.8),
    );
  }

  @override
  bool shouldRepaint(covariant _DeviceQrHolePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.clearRatio != clearRatio;
  }
}

/// شريط معرف الجهاز + زر نسخ أنيق أسفل QR (لا يغيّر بيانات الرمز).
class _DeviceQrIdCopyBar extends StatefulWidget {
  const _DeviceQrIdCopyBar({
    required this.deviceId,
    this.compact = false,
  });

  final String deviceId;
  final bool compact;

  @override
  State<_DeviceQrIdCopyBar> createState() => _DeviceQrIdCopyBarState();
}

class _DeviceQrIdCopyBarState extends State<_DeviceQrIdCopyBar> {
  bool _copied = false;

  Future<void> _copy() async {
    final id = widget.deviceId.trim();
    if (id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    setState(() => _copied = true);
    Get.snackbar(
      'copied'.tr,
      'device_id_copied'.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: const Color(0xE61B4332),
      colorText: Colors.white,
      margin: const EdgeInsets.all(14),
      borderRadius: 12,
      duration: const Duration(seconds: 2),
      icon: const Icon(
        LucideIcons.copy_check,
        color: Color(0xFF95D5B2),
        size: 20,
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.deviceId.trim();
    final gold = LoginPremiumColors.gold;
    final compact = widget.compact;
    final iconBox = compact ? 32.0 : 40.0;
    final copyBtn = compact ? 34.0 : 42.0;
    final radius = compact ? 12.0 : 16.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(color: gold.withValues(alpha: 0.32)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: compact ? 2.0 : 2.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    gold.withValues(alpha: 0.15),
                    gold,
                    gold.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                compact ? 8 : 12,
                compact ? 8 : 10,
                compact ? 8 : 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: iconBox,
                    height: iconBox,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(compact ? 9 : 12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          gold.withValues(alpha: 0.22),
                          gold.withValues(alpha: 0.08),
                        ],
                      ),
                      border: Border.all(color: gold.withValues(alpha: 0.35)),
                    ),
                    child: Icon(
                      LucideIcons.hash,
                      size: compact ? 15 : 18,
                      color: gold.withValues(alpha: 0.95),
                    ),
                  ),
                  SizedBox(width: compact ? 8 : 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'device_id'.tr.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Get.textTheme.bodySmall?.copyWith(
                            color: gold.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w700,
                            fontSize: compact ? 9.5 : 10.5,
                            letterSpacing: 1.1,
                            height: 1.1,
                          ),
                        ),
                        SizedBox(height: compact ? 3 : 5),
                        Tooltip(
                          message: id,
                          waitDuration: const Duration(milliseconds: 400),
                          child: Text(
                            id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Get.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.96),
                              fontWeight: FontWeight.w700,
                              fontSize: compact ? 11.5 : 12.8,
                              letterSpacing: 0.35,
                              height: 1.2,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? 6 : 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _copy,
                      borderRadius: BorderRadius.circular(compact ? 10 : 12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        width: copyBtn,
                        height: copyBtn,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            compact ? 10 : 12,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _copied
                                ? const [
                                    Color(0xFF2D6A4F),
                                    Color(0xFF40916C),
                                  ]
                                : [
                                    gold.withValues(alpha: 0.98),
                                    gold.withValues(alpha: 0.72),
                                  ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_copied
                                      ? const Color(0xFF40916C)
                                      : gold)
                                  .withValues(alpha: 0.38),
                              blurRadius: compact ? 8 : 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          _copied ? LucideIcons.check : LucideIcons.copy,
                          size: compact ? 15 : 17,
                          color: _copied
                              ? Colors.white
                              : const Color(0xFF1A1208),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _loginServerChoiceBar({
  required List<PanelLoginServer> servers,
  required String selectedKey,
  required ValueChanged<String> onSelected,
  FocusNode? focusNode,
  FocusOnKeyEventCallback? onKeyEvent,
  bool isTvDevice = false,
  bool showPickHint = true,
  bool compact = false,
}) {
  final chips = <({String key, String label})>[
    (key: kLoginServerExternalKey, label: 'login_server_external'.tr),
    for (var i = 0; i < servers.length; i++)
      (
        key: '$i',
        label: servers[i].name.trim().isEmpty
            ? 'login_server_fallback_name'.tr
            : servers[i].name,
      ),
  ];
  final chipKeys = [for (final c in chips) c.key];

  KeyEventResult handleBarKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      final isLeft = key == LogicalKeyboardKey.arrowLeft;
      final isRight = key == LogicalKeyboardKey.arrowRight;
      if (isLeft || isRight) {
        // إلا ما كاين غير External (أو وصلنا للطرف) يبقى التركيز هنا بلا دوران.
        if (chipKeys.length <= 1) return KeyEventResult.handled;
        var i = chipKeys.indexOf(selectedKey);
        if (i < 0) i = 0;
        final next = isRight ? i + 1 : i - 1;
        if (next < 0 || next >= chipKeys.length) {
          return KeyEventResult.handled;
        }
        onSelected(chipKeys[next]);
        return KeyEventResult.handled;
      }
    }
    if (onKeyEvent != null) return onKeyEvent(node, event);
    return KeyEventResult.ignored;
  }

  // External دائماً على اليسار، والسيرفرات المضافة على يمينها.
  Widget bar = Directionality(
    textDirection: TextDirection.ltr,
    child: Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: compact ? 6 : 8,
      children: [
        for (final chip in chips)
          _LoginServerChip(
            label: chip.label,
            selected: selectedKey == chip.key,
            onTap: () => onSelected(chip.key),
            compact: compact,
          ),
      ],
    ),
  );

  if (focusNode != null) {
    final chipsBar = bar;
    bar = ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        return Focus(
          focusNode: focusNode,
          onKeyEvent: handleBarKey,
          descendantsAreFocusable: false,
          descendantsAreTraversable: false,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: EdgeInsets.all(compact ? 2 : 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: focusNode.hasFocus
                    ? LoginPremiumColors.gold
                    : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: chipsBar,
          ),
        );
      },
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showPickHint && servers.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(bottom: compact ? 4 : 8),
          child: Text(
            'login_server_pick_hint'.tr,
            textAlign: TextAlign.center,
            style: Get.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.58),
              height: 1.25,
              fontSize: isTvDevice ? 11 : 12,
            ),
          ),
        ),
      bar,
    ],
  );
}

class _LoginServerChip extends StatelessWidget {
  const _LoginServerChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? LoginPremiumColors.gold.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? LoginPremiumColors.gold
                  : Colors.white.withValues(alpha: 0.28),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: LoginPremiumColors.gold,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.check,
                    size: 11,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: selected ? 1 : 0.88),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
