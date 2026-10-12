import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:mehdi_iptv/helpers/helpers.dart';
import 'package:mehdi_iptv/presentation/widgets/app_update_dialog.dart';
import 'package:mehdi_iptv/services/app_update_flow_controller.dart';
import 'package:mehdi_iptv/services/app_update_progress_channel.dart';

enum AppUpdateHost { loginEntry, home }

/// Google Play In-App Updates — Android فقط.
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  bool get isSupported => true;

  /// بدون prefetch: انتظار قصير نادر؛ مع prefetch من السبلاش: فوري.
  static const Duration _checkStartDelay = Duration.zero;
  static const Duration _checkStartDelayWhenPrefetched = Duration.zero;
  static const Duration _prefetchWaitTimeout = Duration(seconds: 12);
  static const Duration _checkDebounce = Duration(seconds: 2);
  static const Duration _downloadPollInterval = Duration(seconds: 4);
  static const Duration _downloadMaxWait = Duration(minutes: 45);
  static const Duration _showContextWait = Duration(seconds: 6);

  AppUpdateHost? _sessionHost;
  bool _promptDismissedThisSession = false;

  /// true بعد ما تكمّل الفحص فعلاً (لا تحديث / عُرض الحوار / تحديث فوري).
  bool _updateCheckResolved = false;
  bool _checkInFlight = false;
  DateTime? _lastCheckScheduledAt;

  /// true فقط بعد ضغط المستخدم على «تحديث الآن».
  bool _userAcceptedUpdate = false;
  bool _downloadStarted = false;

  StreamSubscription<InstallStatus>? _installListener;
  StreamSubscription<AppUpdateProgressEvent>? _progressListener;
  BuildContext? _hostContext;
  AppUpdateFlowController? _flowController;
  bool _flowDialogVisible = false;

  AppUpdateInfo? _prefetchedInfo;
  bool _prefetchCompleted = false;
  Completer<void>? _prefetchCompleter;

  /// يُستدعى من السبلاش — فحص Play بالتوازي مع الترخيص/التفعيل (بلا واجهة).
  Future<void> prefetchAtLaunch() {
    if (_prefetchCompleted) {
      return Future<void>.value();
    }
    final existing = _prefetchCompleter;
    if (existing != null) return existing.future;

    final completer = Completer<void>();
    _prefetchCompleter = completer;
    unawaited(_runPrefetch(completer));
    return completer.future;
  }

  Future<void> _runPrefetch(Completer<void> completer) async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      _prefetchedInfo = info;
      if (kDebugMode) {
        debugPrint(
          '[AppUpdate] prefetch complete: availability=${info.updateAvailability}',
        );
      }
    } catch (e, st) {
      _prefetchedInfo = null;
      if (kDebugMode) {
        debugPrint('[AppUpdate] prefetch failed: $e\n$st');
      }
    } finally {
      _prefetchCompleted = true;
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<AppUpdateInfo> _fetchSessionUpdateInfo() async {
    if (!_prefetchCompleted) {
      try {
        await prefetchAtLaunch().timeout(_prefetchWaitTimeout);
      } catch (_) {
        _logSkip('_fetchSessionUpdateInfo', 'prefetch wait timed out');
      }
    }

    final cached = _prefetchedInfo;
    if (cached != null) {
      _prefetchedInfo = null;
      if (kDebugMode) {
        debugPrint('[AppUpdate] using prefetched Play update info');
      }
      return cached;
    }

    return InAppUpdate.checkForUpdate();
  }

  /// إطار واحد بعد جدولة الفحص — بلا انتظار مزدوج يؤخّر الحوار.
  Future<void> _waitForHostUiSettled() async {
    await WidgetsBinding.instance.endOfFrame;
  }

  void scheduleCheckForLoginEntry(BuildContext context) {
    _scheduleCheck(context, AppUpdateHost.loginEntry);
  }

  void scheduleCheckForHome(BuildContext context) {
    _scheduleCheck(context, AppUpdateHost.home);
  }

  void _scheduleCheck(BuildContext context, AppUpdateHost host) {
    if (_updateCheckResolved) {
      _logSkip('scheduleCheck', 'update check already resolved this session');
      return;
    }
    if (_promptDismissedThisSession) {
      _logSkip('scheduleCheck', 'prompt dismissed this session');
      return;
    }
    if (_userAcceptedUpdate) {
      _logSkip('scheduleCheck', 'user already accepted update');
      return;
    }
    if (_flowDialogVisible) {
      _logSkip('scheduleCheck', 'update dialog already visible');
      return;
    }
    if (_checkInFlight) {
      _logSkip('scheduleCheck', 'check already in flight');
      return;
    }

    final now = DateTime.now();
    if (_lastCheckScheduledAt != null &&
        now.difference(_lastCheckScheduledAt!) < _checkDebounce) {
      _logSkip('scheduleCheck', 'debounced (${_checkDebounce.inSeconds}s)');
      return;
    }

    _lastCheckScheduledAt = now;
    _sessionHost = host;
    _hostContext = context;
    _checkInFlight = true;

    // إطار واحد فقط: الحوار يبان مع رسم الشاشة، ويبقى صالحاً فوق أي قسم يدخلو المستخدم.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _runSessionCheck(context.mounted ? context : null).whenComplete(() {
          _checkInFlight = false;
        }),
      );
    });
  }

  void onAppResumed(BuildContext? context) {
    if (!_userAcceptedUpdate) return;
    final ctx = _activeContext(context);
    if (ctx == null) {
      _logSkip('onAppResumed', 'no active context');
      return;
    }
    if (!_canShowUpdateUi(ctx)) {
      _logSkip(
        'onAppResumed',
        'blocked route: ${Get.currentRoute} (host=$_sessionHost)',
      );
      return;
    }
    unawaited(_resumeAcceptedUpdateUi(ctx));
  }

  Future<void> _runSessionCheck(BuildContext? context) async {
    try {
      await _waitForHostUiSettled();

      final delay = _prefetchCompleted
          ? _checkStartDelayWhenPrefetched
          : _checkStartDelay;
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }

      final info = await _fetchSessionUpdateInfo();

      if (!_hasPlayUpdate(info)) {
        _markUpdateCheckResolved(
          '_runSessionCheck',
          'no Play update available',
        );
        return;
      }

      // ننتظر سياقاً صالحاً (overlay) بدل ما نلغي الفحص إلا المستخدم خرج من login/home.
      // ignore: use_build_context_synchronously
      final dialogCtx = await _waitForShowContext(fallback: context);
      if (dialogCtx == null) {
        _logSkip('_runSessionCheck', 'no dialog context after checkForUpdate');
        return;
      }

      // دائماً حوار التطبيق أولاً — ما نعرضوش شاشة Google Play Immediate تلقائياً.
      // بعد «تحديث الآن» كنبداو Flexible (تنزيل + تقدّم داخل التطبيق).
      if (!info.flexibleUpdateAllowed && !info.immediateUpdateAllowed) {
        _logSkip(
          '_runSessionCheck',
          'flexible and immediate updates not allowed',
        );
        return;
      }

      if (_userAcceptedUpdate) {
        if (info.installStatus == InstallStatus.downloaded) {
          await _showPostDownloadFlow(dialogCtx); // ignore: use_build_context_synchronously
          return;
        }
        if (_isDownloadInProgress(info.installStatus)) {
          await _showProgressFlow(dialogCtx, resume: true); // ignore: use_build_context_synchronously
          return;
        }
      }

      if (_promptDismissedThisSession) {
        _logSkip('_runSessionCheck', 'prompt dismissed this session');
        return;
      }

      // ignore: use_build_context_synchronously
      final promptHandled = await _showPromptFlow(dialogCtx);
      if (promptHandled) {
        _markUpdateCheckResolved('_runSessionCheck', 'prompt flow finished');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AppUpdate] _runSessionCheck error: $e\n$st');
      }
    }
  }

  Future<void> _resumeAcceptedUpdateUi(BuildContext context) async {
    try {
      if (!_canShowUpdateUi(context)) {
        _logSkip(
          '_resumeAcceptedUpdateUi',
          'blocked route: ${Get.currentRoute} (host=$_sessionHost)',
        );
        return;
      }

      final info = await InAppUpdate.checkForUpdate();
      if (!_hasPlayUpdate(info)) {
        _logSkip('_resumeAcceptedUpdateUi', 'no Play update in progress');
        return;
      }

      if (info.installStatus == InstallStatus.downloaded) {
        await _showPostDownloadFlow(context); // ignore: use_build_context_synchronously
        return;
      }
      if (_isDownloadInProgress(info.installStatus) && _downloadStarted) {
        await _showProgressFlow(context, resume: true); // ignore: use_build_context_synchronously
        return;
      }

      _logSkip(
        '_resumeAcceptedUpdateUi',
        'installStatus=${info.installStatus} downloadStarted=$_downloadStarted',
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AppUpdate] _resumeAcceptedUpdateUi error: $e\n$st');
      }
    }
  }

  bool _hasPlayUpdate(AppUpdateInfo info) {
    return info.updateAvailability == UpdateAvailability.updateAvailable ||
        info.updateAvailability ==
            UpdateAvailability.developerTriggeredUpdateInProgress;
  }

  bool _isDownloadInProgress(InstallStatus status) {
    return status == InstallStatus.pending ||
        status == InstallStatus.downloading;
  }

  void _markUpdateCheckResolved(String source, String reason) {
    _updateCheckResolved = true;
    if (kDebugMode) {
      debugPrint('[AppUpdate] resolved [$source]: $reason');
    }
  }

  void _logSkip(String source, String reason) {
    if (kDebugMode) {
      debugPrint('[AppUpdate] skip [$source]: $reason');
    }
  }

  Future<void> _tryImmediateUpdate() async {
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      if (kDebugMode) {
        debugPrint('[AppUpdate] immediate result: $result');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AppUpdate] immediate failed: $e\n$st');
      }
    }
  }

  Future<bool> _showPromptFlow(BuildContext context) async {
    if (_flowDialogVisible) {
      _logSkip('_showPromptFlow', 'dialog already visible');
      return false;
    }

    final controller = AppUpdateFlowController();
    controller.onRestartRequested = _completeDownloadedUpdate;
    _flowController = controller;

    final dialogFuture = _presentFlowDialog(context, controller);
    final action = await controller.waitForPromptAction();

    if (action == AppUpdateDialogAction.later) {
      _promptDismissedThisSession = true;
      await dialogFuture;
      return true;
    }

    if (action == AppUpdateDialogAction.update) {
      _userAcceptedUpdate = true;
      await _startDownloadFlow(controller);
      await dialogFuture;
      return true;
    }
    await dialogFuture;
    return false;
  }

  Future<void> _showProgressFlow(
    BuildContext context, {
    required bool resume,
  }) async {
    if (_flowDialogVisible) {
      _logSkip('_showProgressFlow', 'dialog already visible');
      return;
    }

    final controller = AppUpdateFlowController();
    controller.onRestartRequested = _completeDownloadedUpdate;
    _flowController = controller;
    controller.locked = true;
    controller.setPreparing();

    _ensureListeners();
    final dialogFuture = _presentFlowDialog(context, controller);

    if (!resume) {
      await _startFlexibleDownload(controller);
    }

    await _monitorDownloadProgress(controller);
    await dialogFuture;
  }

  Future<void> _showPostDownloadFlow(BuildContext context) async {
    if (_flowDialogVisible) {
      _logSkip('_showPostDownloadFlow', 'dialog already visible');
      return;
    }

    final controller = AppUpdateFlowController();
    controller.onRestartRequested = _completeDownloadedUpdate;
    _flowController = controller;
    controller.locked = true;
    controller.setReady();

    final dialogFuture = _presentFlowDialog(context, controller);
    await controller.waitForRestartTap();
    await dialogFuture;
  }

  Future<void> _startDownloadFlow(AppUpdateFlowController controller) async {
    controller.setPreparing();
    _ensureListeners();

    // بعد موافقة المستخدم في حوار التطبيق: Flexible فقط (بلا شاشة Play الزرقاء).
    // إلا Flexible ماشي متاح، كنحاولو Immediate كحل أخير (قد يظهر حوار Play).
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.flexibleUpdateAllowed) {
        await _startFlexibleDownload(controller);
        await _monitorDownloadProgress(controller);
        if (controller.phase == AppUpdateUiPhase.ready) {
          await controller.waitForRestartTap();
        }
        return;
      }
      if (info.immediateUpdateAllowed) {
        if (kDebugMode) {
          debugPrint(
            '[AppUpdate] flexible unavailable after accept — falling back to immediate',
          );
        }
        await _tryImmediateUpdate();
        controller.markFlowFinished();
        return;
      }
      controller.setFailed('app_update_failed_message');
      _resetUpdateSession();
      controller.markFlowFinished();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AppUpdate] _startDownloadFlow error: $e\n$st');
      }
      controller.setFailed('app_update_failed_message');
      _resetUpdateSession();
      controller.markFlowFinished();
    }
  }

  Future<void> _startFlexibleDownload(
    AppUpdateFlowController controller,
  ) async {
    _downloadStarted = true;
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.userDeniedUpdate) {
        controller.setFailed('app_update_denied_message');
        _resetUpdateSession();
        controller.markFlowFinished();
        return;
      }
      if (result == AppUpdateResult.inAppUpdateFailed) {
        controller.setFailed('app_update_failed_message');
        _resetUpdateSession();
        controller.markFlowFinished();
        return;
      }
      await _pollPlayUpdateStatus(controller, source: 'startFlexibleDownload');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AppUpdate] flexible start failed: $e\n$st');
      }
      controller.setFailed('app_update_failed_message');
      _resetUpdateSession();
      controller.markFlowFinished();
    }
  }

  /// ينتظر اكتمال التحميل مع استطلاع دوري لـ Play (احتياط إن فاتتنا أحداث native).
  Future<void> _monitorDownloadProgress(
    AppUpdateFlowController controller,
  ) async {
    final deadline = DateTime.now().add(_downloadMaxWait);
    var lastPollAt = DateTime.now();

    while (DateTime.now().isBefore(deadline)) {
      if (controller.phase == AppUpdateUiPhase.ready ||
          controller.phase == AppUpdateUiPhase.failed) {
        return;
      }

      if (DateTime.now().difference(lastPollAt) >= _downloadPollInterval) {
        lastPollAt = DateTime.now();
        final done = await _pollPlayUpdateStatus(
          controller,
          source: 'monitorDownloadProgress',
        );
        if (done) return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    if (controller.phase != AppUpdateUiPhase.ready) {
      controller.setFailed('app_update_failed_message');
      _resetUpdateSession();
      controller.markFlowFinished();
    }
  }

  /// يستعلم Play مباشرة. يُرجع true إن وصلنا لحالة downloaded.
  Future<bool> _pollPlayUpdateStatus(
    AppUpdateFlowController controller, {
    required String source,
  }) async {
    if (controller.phase == AppUpdateUiPhase.ready ||
        controller.phase == AppUpdateUiPhase.failed) {
      return controller.phase == AppUpdateUiPhase.ready;
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus == InstallStatus.downloaded) {
        if (kDebugMode) {
          debugPrint('[AppUpdate] poll [$source]: installStatus=downloaded');
        }
        controller.setReady();
        return true;
      }
      if (info.installStatus == InstallStatus.downloading) {
        if (controller.phase == AppUpdateUiPhase.preparing) {
          controller.setDownloading(0, indeterminate: true);
        }
      } else if (info.installStatus == InstallStatus.pending &&
          controller.phase == AppUpdateUiPhase.prompt) {
        controller.setPreparing();
      }
    } catch (e) {
      _logSkip('_pollPlayUpdateStatus', '$source failed: $e');
    }
    return false;
  }

  Future<void> _presentFlowDialog(
    BuildContext context,
    AppUpdateFlowController controller,
  ) async {
    // ignore: use_build_context_synchronously
    final showCtx = await _waitForShowContext(fallback: context);
    if (showCtx == null) {
      _logSkip(
        '_presentFlowDialog',
        'no show context: route=${Get.currentRoute} host=$_sessionHost',
      );
      controller.markFlowFinished();
      return;
    }
    _flowDialogVisible = true;
    try {
      await AppUpdateDialog.showFlow(showCtx, controller); // ignore: use_build_context_synchronously
    } finally {
      _flowDialogVisible = false;
      if (identical(_flowController, controller)) {
        _flowController = null;
      }
    }
  }

  Future<void> _completeDownloadedUpdate() async {
    final controller = _flowController;
    controller?.setInstalling();
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AppUpdate] complete failed: $e\n$st');
      }
      controller?.setReady();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await forceRelaunchApp();
  }

  void _ensureListeners() {
    if (!_userAcceptedUpdate) return;

    _installListener ??= InAppUpdate.installUpdateListener.listen(
      (status) => _handleInstallStatus(status),
      onError: (_) {},
    );

    _progressListener ??= AppUpdateProgressChannel.events.listen(
      (event) => _handleProgressEvent(event),
      onError: (_) {},
    );
  }

  void _handleInstallStatus(InstallStatus status) {
    if (!_userAcceptedUpdate || !_downloadStarted) return;
    final controller = _flowController;
    if (controller == null) return;

    switch (status) {
      case InstallStatus.pending:
        controller.setPreparing();
      case InstallStatus.downloading:
        if (controller.phase == AppUpdateUiPhase.preparing ||
            controller.indeterminate) {
          controller.setDownloading(0, indeterminate: true);
        }
      case InstallStatus.downloaded:
        controller.setReady();
      case InstallStatus.failed:
        controller.setFailed('app_update_failed_message');
        _resetUpdateSession();
        controller.markFlowFinished();
      case InstallStatus.canceled:
        controller.setFailed('app_update_denied_message');
        _resetUpdateSession();
        controller.markFlowFinished();
      case InstallStatus.installing:
        controller.setInstalling();
      default:
        break;
    }
  }

  void _handleProgressEvent(AppUpdateProgressEvent event) {
    if (!_userAcceptedUpdate || !_downloadStarted) return;
    final controller = _flowController;
    if (controller == null) return;

    switch (event.status) {
      case InstallStatus.pending:
        controller.setPreparing();
      case InstallStatus.downloading:
        final fraction = event.fraction;
        if (fraction != null && event.totalBytesToDownload > 0) {
          controller.setDownloading(fraction);
        } else {
          controller.setDownloading(0, indeterminate: true);
        }
      case InstallStatus.downloaded:
        controller.setReady();
      case InstallStatus.installing:
        controller.setInstalling(value: event.fraction ?? 0.9);
      case InstallStatus.failed:
        controller.setFailed('app_update_failed_message');
        _resetUpdateSession();
        controller.markFlowFinished();
      case InstallStatus.canceled:
        controller.setFailed('app_update_denied_message');
        _resetUpdateSession();
        controller.markFlowFinished();
      default:
        break;
    }
  }

  void _resetUpdateSession() {
    _userAcceptedUpdate = false;
    _downloadStarted = false;
  }

  /// الحوار يبان فوق أي شاشة داخل التطبيق (register / playlist / home / …).
  /// نمنع فقط السبلاش وفحص الترخيص حيث ما كاينش UI جاهز.
  bool _canShowUpdateUi([BuildContext? context]) {
    final route = Get.currentRoute;
    if (route == screenSplash || route == screenLicenseInvalid) {
      return false;
    }
    if (context != null) {
      final name = ModalRoute.of(context)?.settings.name;
      if (name == screenSplash || name == screenLicenseInvalid) {
        return false;
      }
    }
    return true;
  }

  // ignore: use_build_context_synchronously
  Future<BuildContext?> _waitForShowContext({
    BuildContext? fallback,
    Duration timeout = _showContextWait,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final ctx = _activeContext(fallback); // ignore: use_build_context_synchronously
      if (ctx != null && _canShowUpdateUi(ctx)) return ctx; // ignore: use_build_context_synchronously
      if (DateTime.now().isAfter(deadline)) {
        final last = _activeContext(fallback); // ignore: use_build_context_synchronously
        if (last != null && _canShowUpdateUi(last)) return last; // ignore: use_build_context_synchronously
        return null;
      }
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  BuildContext? _activeContext([BuildContext? fallback]) {
    final overlay = Get.overlayContext;
    if (overlay != null && overlay.mounted) return overlay;
    if (fallback != null && fallback.mounted) return fallback;
    final host = _hostContext;
    if (host != null && host.mounted) return host;
    return null;
  }

  void dispose() {
    _installListener?.cancel();
    _installListener = null;
    _progressListener?.cancel();
    _progressListener = null;
  }
}
