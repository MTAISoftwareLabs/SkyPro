part of '../screens.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen>
    with LandscapeMainAppStateMixin<AddDeviceScreen> {
  final TextEditingController _deviceIdController = TextEditingController();
  bool _isSaving = false;
  String? _statusMessage;
  List<String> _linkedDevices = [];
  bool _scanInProgress = false;

  @override
  void dispose() {
    _deviceIdController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final box = GetStorage();
    final list = (box.read('linked_devices') as List?)?.cast<String>() ?? [];
    _linkedDevices = list;
  }

  Future<UserModel?> _getCurrentUser() async {
    try {
      return await LocaleApi.getUser();
    } catch (_) {
      return null;
    }
  }

  String? _buildPlaylistUrl(UserModel user) {
    final username = user.userInfo?.username?.trim() ?? '';
    final password = user.userInfo?.password?.trim() ?? '';
    final serverUrl = user.serverInfo?.serverUrl?.trim() ?? '';
    if (username.isEmpty || password.isEmpty || serverUrl.isEmpty) {
      return null;
    }
    final base = serverUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/get.php?username=$username&password=$password&type=m3u_plus&output=m3u8';
  }

  Future<void> _saveForDevice(String deviceId) async {
    if (deviceId.trim().isEmpty) {
      setState(() {
        _statusMessage = 'add_device_empty_error'.tr;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    final user = await _getCurrentUser();
    if (user == null) {
      setState(() {
        _isSaving = false;
        _statusMessage = 'add_device_no_user'.tr;
      });
      return;
    }

    final playlistUrl = _buildPlaylistUrl(user);
    if (playlistUrl == null) {
      setState(() {
        _isSaving = false;
        _statusMessage = 'add_device_build_failed'.tr;
      });
      return;
    }

    final api = ActivationApi();
    final result = await api.savePlaylistUrl(
      deviceId.trim(),
      playlistUrl,
      forRemoteDevice: true,
    );
    final success = result['success'] == true;

    if (!mounted) return;

    setState(() {
      _isSaving = false;
      final message = (result['message'] as String?) ?? '';
      if (!success && message.contains('Max devices')) {
        _statusMessage = 'add_device_max_devices'.trParams({
          'max': '${result['max_devices'] ?? 1}',
        });
      } else {
        _statusMessage =
            success ? 'add_device_success'.tr : 'add_device_failed'.tr;
      }
      if (success) {
        final box = GetStorage();
        if (!_linkedDevices.contains(deviceId.trim())) {
          _linkedDevices.insert(0, deviceId.trim());
          box.write('linked_devices', _linkedDevices);
        }
      }
    });
  }

  Future<void> _removeLinkedDevice(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final box = GetStorage();
    setState(() {
      _linkedDevices.removeWhere((e) => e == id);
    });
    await box.write('linked_devices', _linkedDevices);
    try {
      final api = ActivationApi();
      // فك الربط فقط — لا تُنهَ تفعيل الجهاز الهدف في اللوحة.
      await api.unlinkRemoteDevice(id);
    } catch (_) {}
  }

  void _startScan() async {
    if (_scanInProgress) return;
    _scanInProgress = true;
    try {
      final result = await Get.to<String>(() => const _DeviceQrScannerPage());
      final value = (result ?? '').trim();
      if (!mounted) return;
      if (value.isNotEmpty) {
        _deviceIdController.text = value;
        // حفظ تلقائي بعد المسح لتجربة سلسة
        await _saveForDevice(value);
      }
    } finally {
      _scanInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Get.textTheme;

    return Scaffold(
      body: Ink(
        width: 100.w,
        height: 100.h,
        decoration: kDecorBackground,
        child: SafeArea(
          top: false,
          bottom: false,
          left: false,
          right: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Get.back(),
                      icon: const Icon(
                        FontAwesomeIcons.chevronLeft,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'add_device_title'.tr,
                      style: theme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 2.h),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'add_device_intro'.tr,
                        style: theme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                      SizedBox(height: 2.h),
                      TextField(
                        controller: _deviceIdController,
                        decoration: InputDecoration(
                          labelText: 'add_device_code_label'.tr,
                          labelStyle: theme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                          hintText: 'add_device_code_hint'.tr,
                          hintStyle: theme.bodySmall?.copyWith(
                            color: Colors.white38,
                          ),
                          prefixIcon: Icon(
                            FontAwesomeIcons.tv,
                            size: 18,
                            color: kColorPrimary,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.04),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: kColorPrimary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        style: theme.bodyMedium?.copyWith(color: Colors.white),
                      ),
                      SizedBox(height: 1.5.h),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _startScan,
                              icon: const Icon(
                                FontAwesomeIcons.qrcode,
                                size: 18,
                              ),
                              label: Text('add_device_scan_button'.tr),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kColorPrimary,
                                side: BorderSide(
                                  color: kColorPrimary.withValues(alpha: 0.6),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2.h),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _isSaving
                                  ? null
                                  : () =>
                                      _saveForDevice(_deviceIdController.text),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kColorPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child:
                              _isSaving
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.black,
                                      ),
                                    ),
                                  )
                                  : Text(
                                    'add_device_link_button'.tr,
                                    style: theme.titleSmall?.copyWith(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                        ),
                      ),
                      if (_statusMessage != null) ...[
                        SizedBox(height: 1.5.h),
                        Text(
                          _statusMessage!,
                          style: theme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                      if (_linkedDevices.isNotEmpty) ...[
                        SizedBox(height: 2.h),
                        Divider(color: Colors.white.withValues(alpha: 0.15)),
                        SizedBox(height: 1.h),
                        Text(
                          'add_device_linked_list_title'.tr,
                          style: theme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 0.8.h),
                        ..._linkedDevices.map(
                          (id) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Icon(
                                  FontAwesomeIcons.tv,
                                  size: 14,
                                  color: kColorPrimary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    id,
                                    style: theme.bodySmall?.copyWith(
                                      color: Colors.white70,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _removeLinkedDevice(id),
                                  icon: const Icon(
                                    FontAwesomeIcons.trash,
                                    size: 16,
                                    color: Colors.white70,
                                  ),
                                  tooltip: 'حذف',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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

class _DeviceQrScannerPage extends StatefulWidget {
  const _DeviceQrScannerPage();

  @override
  State<_DeviceQrScannerPage> createState() => _DeviceQrScannerPageState();
}

class _DeviceQrScannerPageState extends State<_DeviceQrScannerPage>
    with SingleTickerProviderStateMixin {
  bool _returned = false;
  late final AnimationController _laserCtrl;
  late final Animation<double> _laserAnim;

  @override
  void initState() {
    super.initState();
    _laserCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    )..repeat(reverse: true);
    _laserAnim = CurvedAnimation(
      parent: _laserCtrl,
      curve: Curves.easeInOut,
    );
  }

  void _returnValue(String value) {
    if (_returned) return;
    _returned = true;

    changeDeviceOrientBack();
    Get.back(result: value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // مسح QR: عمودي على الهاتف فقط — التلفاز يبقى أفقي دائماً.
    if (isStoredTvDevice || isTv(context)) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  @override
  void dispose() {
    _laserCtrl.dispose();
    changeDeviceOrientBack();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final frame = (size.shortestSide * 0.72).clamp(220.0, 320.0);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: () {
            changeDeviceOrientBack();
            Get.back();
          },
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text(
          'add_device_scanner_title'.tr,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            fit: BoxFit.cover,
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final value = (barcode.rawValue ?? '').trim();
                if (value.isNotEmpty) {
                  _returnValue(value);
                  break;
                }
              }
            },
          ),
          // إطار مسح + خط أحمر متحرك
          Center(
            child: SizedBox(
              width: frame,
              height: frame,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _QrScannerFramePainter(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _laserAnim,
                      builder: (context, _) {
                        final y = _laserAnim.value * (frame - 3);
                        return Stack(
                          children: [
                            Positioned(
                              left: 10,
                              right: 10,
                              top: y,
                              child: Container(
                                height: 2.5,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE53935),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFE53935)
                                          .withValues(alpha: 0.9),
                                      blurRadius: 12,
                                      spreadRadius: 1.4,
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
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Text(
                'add_device_scanner_hint'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrScannerFramePainter extends CustomPainter {
  _QrScannerFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    // corners
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, len), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - len, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), paint);
    canvas.drawLine(
      Offset(0, size.height),
      Offset(len, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - len),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - len, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _QrScannerFramePainter oldDelegate) =>
      oldDelegate.color != color;
}
