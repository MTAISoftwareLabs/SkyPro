import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:get/get.dart';
import 'package:mehdi_iptv/helpers/helpers.dart';
import 'package:mehdi_iptv/services/app_update_flow_controller.dart';

enum AppUpdateDialogAction { later, update }

/// حوارات تحديث Google Play — متوافقة مع تصميم Nova IPTV (موبايل + TV).
abstract final class AppUpdateDialog {
  /// حوار واحد ثابت: مطالبة → تنزيل → تثبيت → إعادة تشغيل.
  static Future<void> showFlow(
    BuildContext context,
    AppUpdateFlowController controller,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      useRootNavigator: true,
      builder: (ctx) => PopScope(
        // ملاحظة مهمة: canPop دايماً false هنا — التحكم فالإغلاق كيتدار
        // يدوياً فonPopInvokedWithResult باش نضمنو أن chooseLater() تتندى
        // قبل الإغلاق (وإلا الـ Future ديال waitForPromptAction() تبقى
        // معلقة للأبد إيلا المستخدم ضغط زر الرجوع، وهادشي كيبلوكي جميع
        // الفحوصات الجاية طول الـ session عبر _checkInFlight).
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (!controller.canDismiss) return;
          controller.chooseLater();
          Navigator.of(ctx, rootNavigator: true).pop();
        },
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _AppUpdateFlowDialog(controller: controller),
        ),
      ),
    );
  }
}

class _AppUpdateShell extends StatelessWidget {
  const _AppUpdateShell({
    required this.icon,
    required this.title,
    required this.message,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tv = isTvDevice(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: tv ? 48 : 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF151C2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kColorPrimary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: kColorPrimary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _AppUpdateFlowDialog extends StatefulWidget {
  const _AppUpdateFlowDialog({required this.controller});

  final AppUpdateFlowController controller;

  @override
  State<_AppUpdateFlowDialog> createState() => _AppUpdateFlowDialogState();
}

class _AppUpdateFlowDialogState extends State<_AppUpdateFlowDialog> {
  late final FocusNode _laterFocus;
  late final FocusNode _updateFocus;
  late final FocusNode _restartFocus;
  late final FocusNode _retryFocus;

  AppUpdateFlowController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _laterFocus = FocusNode(debugLabel: 'app_update_later');
    _updateFocus = FocusNode(debugLabel: 'app_update_now');
    _restartFocus = FocusNode(debugLabel: 'app_update_restart');
    _retryFocus = FocusNode(debugLabel: 'app_update_retry');
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestInitialFocus());
  }

  void _requestInitialFocus() {
    if (!mounted) return;
    if (!isTvDevice(context)) return;
    switch (_c.phase) {
      case AppUpdateUiPhase.prompt:
        _updateFocus.requestFocus();
      case AppUpdateUiPhase.ready:
        _restartFocus.requestFocus();
      case AppUpdateUiPhase.failed:
        _retryFocus.requestFocus();
      default:
        break;
    }
  }

  @override
  void dispose() {
    _laterFocus.dispose();
    _updateFocus.dispose();
    _restartFocus.dispose();
    _retryFocus.dispose();
    super.dispose();
  }

  String _titleForPhase(AppUpdateUiPhase phase) {
    return switch (phase) {
      AppUpdateUiPhase.ready => 'app_update_ready_title'.tr,
      AppUpdateUiPhase.failed => 'app_update_failed_title'.tr,
      _ => 'app_update_title'.tr,
    };
  }

  String _messageForPhase(AppUpdateUiPhase phase) {
    return switch (phase) {
      AppUpdateUiPhase.preparing => 'app_update_preparing'.tr,
      AppUpdateUiPhase.downloading => 'app_update_downloading'.tr,
      AppUpdateUiPhase.installing => 'app_update_installing'.tr,
      AppUpdateUiPhase.ready => 'app_update_ready_message'.tr,
      AppUpdateUiPhase.failed =>
        (_c.errorMessageKey ?? 'app_update_failed_message').tr,
      AppUpdateUiPhase.prompt => 'app_update_message'.tr,
    };
  }

  IconData _iconForPhase(AppUpdateUiPhase phase) {
    return switch (phase) {
      AppUpdateUiPhase.ready => LucideIcons.refresh_ccw,
      AppUpdateUiPhase.failed => LucideIcons.circle_alert,
      AppUpdateUiPhase.installing => LucideIcons.package,
      _ => LucideIcons.download,
    };
  }

  @override
  Widget build(BuildContext context) {
    final phase = _c.phase;
    return _AppUpdateShell(
      icon: _iconForPhase(phase),
      title: _titleForPhase(phase),
      message: _messageForPhase(phase),
      child: switch (phase) {
        AppUpdateUiPhase.prompt => _buildPromptActions(),
        AppUpdateUiPhase.ready => _buildRestartAction(),
        AppUpdateUiPhase.failed => _buildFailedActions(),
        _ => _buildProgress(),
      },
    );
  }

  Widget _buildPromptActions() {
    return Row(
      children: [
        Expanded(
          child: _AppUpdateButton(
            focusNode: _laterFocus,
            label: 'app_update_later'.tr,
            icon: LucideIcons.clock,
            onPressed: () {
              _c.chooseLater();
              Navigator.of(context, rootNavigator: true).pop();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _AppUpdateButton(
            focusNode: _updateFocus,
            label: 'app_update_now'.tr,
            icon: LucideIcons.download,
            isPrimary: true,
            onPressed: _c.chooseUpdate,
          ),
        ),
      ],
    );
  }

  Widget _buildRestartAction() {
    return _AppUpdateButton(
      focusNode: _restartFocus,
      label: 'app_update_restart'.tr,
      icon: LucideIcons.refresh_ccw,
      isPrimary: true,
      expanded: false,
      onPressed: () async {
        await _c.onRestartRequested?.call();
        _c.completeRestartWait();
      },
    );
  }

  Widget _buildFailedActions() {
    return _AppUpdateButton(
      focusNode: _retryFocus,
      label: 'app_update_later'.tr,
      icon: LucideIcons.clock,
      expanded: false,
      onPressed: () {
        _c.markFlowFinished();
        Navigator.of(context, rootNavigator: true).pop();
      },
    );
  }

  Widget _buildProgress() {
    final percent = (_c.progress * 100).round().clamp(0, 100);
    final showPercent = !_c.indeterminate && _c.phase == AppUpdateUiPhase.downloading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _c.indeterminate
              ? LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  color: kColorPrimary,
                )
              : LinearProgressIndicator(
                  minHeight: 6,
                  value: _c.progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  color: kColorPrimary,
                ),
        ),
        if (showPercent) ...[
          const SizedBox(height: 8),
          Text(
            'app_update_progress_percent'.trParams({'percent': '$percent'}),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _AppUpdateButton extends StatefulWidget {
  const _AppUpdateButton({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isPrimary = false,
    this.expanded = true,
  });

  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool expanded;

  @override
  State<_AppUpdateButton> createState() => _AppUpdateButtonState();
}

class _AppUpdateButtonState extends State<_AppUpdateButton> {
  static const double _scale = 1.1;

  @override
  Widget build(BuildContext context) {
    final tv = isTvDevice(context);
    return ListenableBuilder(
      listenable: widget.focusNode,
      builder: (context, _) {
        final hasFocus = widget.focusNode.hasFocus;
        final accent = widget.isPrimary ? kColorPrimary : Colors.white70;
        final focusScale = kTvFocusScale(hasFocus && tv, 1.08);
        return Focus(
          focusNode: widget.focusNode,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.space) {
              widget.onPressed();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: AnimatedScale(
            scale: focusScale,
            duration: kFocusAnimDuration,
            child: AnimatedContainer(
              duration: kFocusAnimDuration,
              width: widget.expanded ? double.infinity : null,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11 * _scale),
                border: hasFocus
                    ? Border.all(color: accent, width: 1.5)
                    : null,
                boxShadow: kTvFocusGlow(
                  focused: hasFocus && tv,
                  blur: 10,
                  alpha: 0.45,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(11 * _scale),
                child: InkWell(
                  onTap: widget.onPressed,
                  borderRadius: BorderRadius.circular(11 * _scale),
                  focusColor: Colors.transparent,
                  hoverColor: Colors.white.withValues(alpha: 0.06),
                  splashColor: kColorPrimary.withValues(alpha: 0.18),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: widget.isPrimary
                          ? kColorPrimary.withValues(
                              alpha: hasFocus ? 0.35 : 0.22,
                            )
                          : Colors.white.withValues(
                              alpha: hasFocus ? 0.12 : 0.06,
                            ),
                      borderRadius: BorderRadius.circular(11 * _scale),
                      border: Border.all(
                        color: hasFocus
                            ? accent
                            : Colors.white.withValues(alpha: 0.12),
                        width: hasFocus ? 1.5 : 1,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10 * _scale,
                        vertical: 10 * _scale,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(widget.icon, size: 15 * _scale, color: accent),
                          SizedBox(width: 6 * _scale),
                          Flexible(
                            child: Text(
                              widget.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.isPrimary
                                    ? Colors.white
                                    : Colors.white70,
                                fontWeight: FontWeight.w700,
                                fontSize: 13 * _scale,
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
        );
      },
    );
  }
}
