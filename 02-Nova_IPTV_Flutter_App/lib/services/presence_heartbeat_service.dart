import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mehdi_iptv/core/runtime_seal.dart';
import 'package:mehdi_iptv/repository/api/activation_api.dart';
import 'package:mehdi_iptv/services/now_watching_presence.dart';

class PresenceHeartbeatService with WidgetsBindingObserver {
  PresenceHeartbeatService._();
  static final PresenceHeartbeatService instance = PresenceHeartbeatService._();

  final ActivationApi _api = ActivationApi();
  final GetStorage _storage = GetStorage();
  Timer? _timer;
  bool _started = false;
  bool _inFlight = false;
  bool? _scheduledForWatching;

  /// أثناء التشغيل: أسرع لتحديث «يشاهد الآن» في اللوحة.
  static const Duration _watchingInterval = Duration(seconds: 15);
  /// بدون تشغيل: نبضة تواجد أخف.
  static const Duration _idleInterval = Duration(seconds: 25);

  Duration get _interval => NowWatchingPresence.instance.hasContent
      ? _watchingInterval
      : _idleInterval;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _schedule(force: true);
    unawaited(beat());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _scheduledForWatching = null;
  }

  /// يُستدعى عند بدء/إيقاف المحتوى لإعادة ضبط فترة النبضة فوراً.
  void refreshSchedule({bool beatNow = false}) {
    if (!_started) return;
    _schedule(force: true);
    if (beatNow) unawaited(beat());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedule(force: true);
      unawaited(beat());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _timer = null;
      _scheduledForWatching = null;
    }
  }

  void _schedule({bool force = false}) {
    final watching = NowWatchingPresence.instance.hasContent;
    if (!force && _timer != null && _scheduledForWatching == watching) {
      return;
    }
    _scheduledForWatching = watching;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(beat()));
  }

  Future<void> beat() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      // إن تغيّر وضع المشاهدة، حدّث الفترة دون انتظار الدورة التالية.
      _schedule();
      var deviceId = (_storage.read('device_id') ?? '').toString().trim();
      if (deviceId.isEmpty) {
        deviceId = await _api.getDeviceId().timeout(
          const Duration(seconds: 4),
          onTimeout: () => '',
        );
        if (deviceId.isNotEmpty) {
          await _storage.write('device_id', deviceId);
        }
      }
      if (deviceId.isEmpty) return;
      await _api.sendHeartbeat(deviceId).timeout(const Duration(seconds: 12));
      // فحص خلفي نادر وصامت — لا يؤثر على الواجهة.
      if (DateTime.now().second % 17 == 0) {
        RuntimeSeal.touchQuiet();
      }
    } catch (_) {
      // لا نؤثر على تجربة المستخدم عند فشل النبضة
    } finally {
      _inFlight = false;
    }
  }
}
