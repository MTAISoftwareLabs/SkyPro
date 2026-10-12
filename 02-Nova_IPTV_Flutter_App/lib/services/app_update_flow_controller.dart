import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mehdi_iptv/presentation/widgets/app_update_dialog.dart';

enum AppUpdateUiPhase {
  prompt,
  preparing,
  downloading,
  installing,
  ready,
  failed,
}

/// يتحكم في واجهة حوار التحديث (مرحلة واحدة ثابتة على الشاشة).
class AppUpdateFlowController extends ChangeNotifier {
  AppUpdateUiPhase phase = AppUpdateUiPhase.prompt;
  double progress = 0;
  bool indeterminate = true;
  String? errorMessageKey;
  bool locked = false;

  Completer<AppUpdateDialogAction?>? _promptCompleter;
  Completer<void>? _restartCompleter;

  Future<void> Function()? onRestartRequested;

  bool get canDismiss =>
      !locked && (phase == AppUpdateUiPhase.prompt || phase == AppUpdateUiPhase.failed);

  Future<AppUpdateDialogAction?> waitForPromptAction() {
    _promptCompleter = Completer<AppUpdateDialogAction?>();
    return _promptCompleter!.future;
  }

  Future<void> waitForRestartTap() {
    _restartCompleter ??= Completer<void>();
    return _restartCompleter!.future;
  }

  void chooseLater() {
    if (locked) return;
    _promptCompleter?.complete(AppUpdateDialogAction.later);
    markFlowFinished();
  }

  void chooseUpdate() {
    if (locked) return;
    locked = true;
    _setPhase(AppUpdateUiPhase.preparing, progress: 0, indeterminate: true);
    _promptCompleter?.complete(AppUpdateDialogAction.update);
  }

  void setPreparing() {
    locked = true;
    _setPhase(AppUpdateUiPhase.preparing, progress: 0, indeterminate: true);
  }

  void setDownloading(double value, {bool indeterminate = false}) {
    locked = true;
    _setPhase(
      AppUpdateUiPhase.downloading,
      progress: value.clamp(0.0, 1.0),
      indeterminate: indeterminate,
    );
  }

  void setInstalling({double value = 0}) {
    locked = true;
    _setPhase(
      AppUpdateUiPhase.installing,
      progress: value.clamp(0.0, 1.0),
      indeterminate: value <= 0,
    );
  }

  void setReady() {
    if (phase == AppUpdateUiPhase.ready) return;
    locked = true;
    _setPhase(AppUpdateUiPhase.ready, progress: 1, indeterminate: false);
  }

  void setFailed(String messageKey) {
    if (phase == AppUpdateUiPhase.failed) return;
    locked = false;
    errorMessageKey = messageKey;
    _setPhase(AppUpdateUiPhase.failed, progress: 0, indeterminate: true);
  }

  void _setPhase(
    AppUpdateUiPhase next, {
    required double progress,
    required bool indeterminate,
  }) {
    phase = next;
    this.progress = progress;
    this.indeterminate = indeterminate;
    notifyListeners();
  }

  void markFlowFinished() {}

  void completeRestartWait() {
    if (!(_restartCompleter?.isCompleted ?? true)) {
      _restartCompleter?.complete();
    }
    _restartCompleter = null;
    markFlowFinished();
  }
}
