import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mehdi_iptv/helpers/helpers.dart';
import 'package:mehdi_iptv/services/parental_control_service.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

/// عرض حوار إدخال PIN والتحقق منه.
Future<bool?> showParentalPinDialog(
  BuildContext context, {
  String? title,
  String? subtitle,
  bool verifyAgainstStored = true,
  String? matchPin,
  bool saveOnMatch = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ParentalPinDialog(
      title: title ?? 'parental_pin_enter'.tr,
      subtitle: subtitle,
      verifyAgainstStored: verifyAgainstStored,
      matchPin: matchPin,
      saveOnMatch: saveOnMatch,
    ),
  );
}

/// إنشاء PIN جديد مع تأكيد.
Future<bool?> showParentalPinSetupFlow(BuildContext context) async {
  final first = await showParentalPinDialog(
    context,
    title: 'parental_pin_create'.tr,
    subtitle: 'parental_pin_create_sub'.tr,
    verifyAgainstStored: false,
  );
  if (first != true) return false;
  if (!context.mounted) return false;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ParentalPinConfirmSetupDialog(
      expectedPin: _ParentalPinSetupHolder.lastPin,
    ),
  );
}

abstract final class _ParentalPinSetupHolder {
  static String lastPin = '';
}

/// تغيير PIN: الحالي → الجديد → التأكيد.
Future<bool?> showParentalPinChangeFlow(BuildContext context) async {
  final currentOk = await showParentalPinDialog(
    context,
    title: 'parental_pin_current'.tr,
    verifyAgainstStored: true,
  );
  if (currentOk != true) return false;
  if (!context.mounted) return false;

  final newPin = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ParentalPinDialog(
      title: 'parental_pin_new'.tr,
      verifyAgainstStored: false,
      returnPinOnSuccess: true,
    ),
  );
  if (newPin == null || newPin.length != ParentalControlService.pinLength) {
    return false;
  }
  if (!context.mounted) return false;

  final confirmOk = await showParentalPinDialog(
    context,
    title: 'parental_pin_confirm'.tr,
    verifyAgainstStored: false,
    matchPin: newPin,
  );
  if (confirmOk != true) return false;

  return ParentalControlService.instance.changePin(
    ParentalPinSessionHolder.lastVerifiedPin,
    newPin,
  );
}

abstract final class ParentalPinSessionHolder {
  static String lastVerifiedPin = '';
}

class ParentalPinDialog extends StatefulWidget {
  const ParentalPinDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.verifyAgainstStored = true,
    this.matchPin,
    this.saveOnMatch = false,
    this.returnPinOnSuccess = false,
  });

  final String title;
  final String? subtitle;
  final bool verifyAgainstStored;
  final String? matchPin;
  final bool saveOnMatch;
  final bool returnPinOnSuccess;

  @override
  State<ParentalPinDialog> createState() => _ParentalPinDialogState();
}

class _ParentalPinDialogState extends State<ParentalPinDialog> {
  String _pin = '';
  String? _errorText;
  bool _submitting = false;
  final FocusNode _dialogFocus = FocusNode();

  @override
  void dispose() {
    _dialogFocus.dispose();
    super.dispose();
  }

  void _onDigit(int digit) {
    if (_submitting || _pin.length >= ParentalControlService.pinLength) return;
    setState(() {
      _pin += digit.toString();
      _errorText = null;
    });
    if (_pin.length == ParentalControlService.pinLength) {
      _submitPin();
    }
  }

  void _onBackspace() {
    if (_submitting || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorText = null;
    });
  }

  Future<void> _submitPin() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    await Future<void>.delayed(const Duration(milliseconds: 90));

    if (!mounted) return;

    final service = ParentalControlService.instance;
    var success = false;

    if (widget.matchPin != null) {
      success = _pin == widget.matchPin;
      if (success && widget.saveOnMatch) {
        await service.savePinAndEnable(_pin);
      }
    } else if (widget.verifyAgainstStored) {
      success = service.verifyPin(_pin);
      if (success) {
        ParentalPinSessionHolder.lastVerifiedPin = _pin;
      }
    } else {
      success = _pin.length == ParentalControlService.pinLength;
      if (success) {
        _ParentalPinSetupHolder.lastPin = _pin;
      }
    }

    if (!mounted) return;

    if (success) {
      if (widget.returnPinOnSuccess) {
        Navigator.of(context).pop(_pin);
      } else {
        Navigator.of(context).pop(true);
      }
      return;
    }

    setState(() {
      _submitting = false;
      _pin = '';
      _errorText = 'parental_pin_wrong'.tr;
    });
  }

  void _onCancel() {
    if (_submitting) return;
    Navigator.of(context).pop(widget.returnPinOnSuccess ? null : false);
  }

  KeyEventResult _onDialogKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _submitting) return KeyEventResult.ignored;
    final k = event.logicalKey;

    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
      _onCancel();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace ||
        k == LogicalKeyboardKey.delete) {
      _onBackspace();
      return KeyEventResult.handled;
    }

    final digitMap = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit0: 0,
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
      LogicalKeyboardKey.numpad0: 0,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.numpad4: 4,
      LogicalKeyboardKey.numpad5: 5,
      LogicalKeyboardKey.numpad6: 6,
      LogicalKeyboardKey.numpad7: 7,
      LogicalKeyboardKey.numpad8: 8,
      LogicalKeyboardKey.numpad9: 9,
    };
    final digit = digitMap[k];
    if (digit != null) {
      _onDigit(digit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    return Focus(
      focusNode: _dialogFocus,
      autofocus: false,
      onKeyEvent: _onDialogKey,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: tv ? 22.w : 14.w,
          vertical: tv ? 8.h : 10.h,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: tv ? 340 : 300,
            maxHeight: tv ? 86.h : 80.h,
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                tv ? 16 : 14,
                tv ? 14 : 12,
                tv ? 16 : 14,
                tv ? 12 : 10,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1A1F2B),
                    kColorCardLight,
                    const Color(0xFF12151C),
                  ],
                ),
                border: Border.all(
                  color: kColorPrimary.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: kColorPrimary.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: LinearGradient(
                            colors: [
                              kColorPrimary.withValues(alpha: 0.35),
                              kColorPrimary.withValues(alpha: 0.12),
                            ],
                          ),
                          border: Border.all(
                            color: kColorPrimary.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Icon(
                          Icons.lock_rounded,
                          color: kColorPrimary,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: Get.textTheme.titleSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                            if (widget.subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.subtitle!,
                                style: Get.textTheme.labelSmall?.copyWith(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: tv ? 12 : 10),
                  _PinDots(
                    length: ParentalControlService.pinLength,
                    filled: _pin.length,
                    hasError: _errorText != null,
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _errorText!,
                      style: Get.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFFF6B6B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  SizedBox(height: tv ? 10 : 8),
                  _ParentalPinKeypad(
                    onDigit: _onDigit,
                    onBackspace: _onBackspace,
                    onCancel: _onCancel,
                    enabled: !_submitting,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParentalPinConfirmSetupDialog extends StatefulWidget {
  const _ParentalPinConfirmSetupDialog({required this.expectedPin});

  final String expectedPin;

  @override
  State<_ParentalPinConfirmSetupDialog> createState() =>
      _ParentalPinConfirmSetupDialogState();
}

class _ParentalPinConfirmSetupDialogState
    extends State<_ParentalPinConfirmSetupDialog> {
  @override
  Widget build(BuildContext context) {
    return ParentalPinDialog(
      title: 'parental_pin_confirm'.tr,
      subtitle: 'parental_pin_confirm_sub'.tr,
      verifyAgainstStored: false,
      matchPin: widget.expectedPin,
      saveOnMatch: true,
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.length,
    required this.filled,
    required this.hasError,
  });

  final int length;
  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final active = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: active ? 12 : 10,
          height: active ? 12 : 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? (hasError ? const Color(0xFFFF6B6B) : kColorPrimary)
                : Colors.white.withValues(alpha: 0.1),
            border: Border.all(
              color: hasError
                  ? const Color(0xFFFF6B6B)
                  : (active
                      ? kColorPrimary
                      : Colors.white.withValues(alpha: 0.22)),
            ),
            boxShadow: active && !hasError
                ? [
                    BoxShadow(
                      color: kColorPrimary.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _ParentalPinKeypad extends StatefulWidget {
  const _ParentalPinKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onCancel,
    required this.enabled,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onCancel;
  final bool enabled;

  @override
  State<_ParentalPinKeypad> createState() => _ParentalPinKeypadState();
}

class _ParentalPinKeypadState extends State<_ParentalPinKeypad> {
  static const int _keyCount = 12;
  final List<FocusNode> _focusNodes =
      List<FocusNode>.generate(_keyCount, (_) => FocusNode());
  int _focusedIndex = 4; // ابدأ من المنتصف (5) لسرعة الريموت

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _keyCount; i++) {
      final index = i;
      _focusNodes[i].onKeyEvent = (node, event) {
        if (event is! KeyDownEvent || !widget.enabled) {
          return KeyEventResult.ignored;
        }
        return _handleDpad(index, event.logicalKey);
      };
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isTv(context)) {
        _focusedIndex = 4;
        _focusNodes[4].requestFocus();
      }
    });
  }

  KeyEventResult _handleDpad(int i, LogicalKeyboardKey key) {
    bool moveTo(int target) {
      if (target < 0 || target >= _keyCount) return false;
      setState(() => _focusedIndex = target);
      _focusNodes[target].requestFocus();
      return true;
    }

    final row = i <= 8 ? i ~/ 3 : 3;
    final col = i <= 8 ? i % 3 : i - 9;

    if (key == LogicalKeyboardKey.arrowUp) {
      if (row == 0) return KeyEventResult.handled;
      final newRow = row - 1;
      final target =
          newRow < 3 ? newRow * 3 + col : (col == 0 ? 9 : (col == 1 ? 10 : 11));
      return moveTo(target) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (row >= 3) return KeyEventResult.handled;
      final newRow = row + 1;
      final target =
          newRow < 3 ? newRow * 3 + col : (col == 0 ? 9 : (col == 1 ? 10 : 11));
      return moveTo(target) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (col <= 0) return KeyEventResult.handled;
      final target = row < 3
          ? row * 3 + (col - 1)
          : (col - 1 == 0 ? 9 : (col - 1 == 1 ? 10 : 11));
      return moveTo(target) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (col >= 2) return KeyEventResult.handled;
      final target =
          row < 3 ? row * 3 + (col + 1) : (col + 1 == 1 ? 10 : 11);
      return moveTo(target) ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.numpadEnter) {
      _activateKey(i);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      widget.onCancel();
      return KeyEventResult.handled;
    }

    // أرقام الريموت/الكيبورد تعمل مباشرة حتى والتركيز على زر
    final digitMap = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit0: 0,
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
      LogicalKeyboardKey.numpad0: 0,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.numpad4: 4,
      LogicalKeyboardKey.numpad5: 5,
      LogicalKeyboardKey.numpad6: 6,
      LogicalKeyboardKey.numpad7: 7,
      LogicalKeyboardKey.numpad8: 8,
      LogicalKeyboardKey.numpad9: 9,
    };
    final digit = digitMap[key];
    if (digit != null) {
      widget.onDigit(digit);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      widget.onBackspace();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _activateKey(int i) {
    if (!widget.enabled) return;
    if (i >= 0 && i <= 8) {
      widget.onDigit(i + 1);
    } else if (i == 9) {
      widget.onBackspace();
    } else if (i == 10) {
      widget.onDigit(0);
    } else if (i == 11) {
      widget.onCancel();
    }
  }

  @override
  void dispose() {
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Widget _key({
    required int index,
    required Widget child,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final focused = _focusedIndex == index && isTv(context);
    final accent = danger ? const Color(0xFFFF6B6B) : kColorPrimary;

    return Focus(
      focusNode: _focusNodes[index],
      onFocusChange: (has) {
        if (has && _focusedIndex != index) {
          setState(() => _focusedIndex = index);
        }
      },
      child: AnimatedScale(
        scale: kTvFocusScale(focused, 1.07),
        duration: kFocusAnimDuration,
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: focused
                  ? [
                      accent.withValues(alpha: 0.35),
                      accent.withValues(alpha: 0.12),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.03),
                    ],
            ),
            border: Border.all(
              color: focused
                  ? accent
                  : Colors.white.withValues(alpha: 0.12),
              width: focused ? 1.6 : 1,
            ),
            boxShadow: kTvFocusGlow(
              focused: focused,
              color: accent,
              blur: 12,
              alpha: 0.4,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: widget.enabled ? onTap : null,
              child: SizedBox(
                height: isTv(context) ? 40 : 36,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    TextStyle labelStyle({bool accent = false, bool danger = false}) =>
        Get.textTheme.titleMedium!.copyWith(
          color: danger
              ? const Color(0xFFFF8A8A)
              : (accent ? kColorPrimary : Colors.white),
          fontWeight: FontWeight.w800,
          fontSize: tv ? 17 : 16,
        );

    Widget row(List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(child: children[i]),
              ],
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([
          for (var d = 1; d <= 3; d++)
            _key(
              index: d - 1,
              onTap: () => _activateKey(d - 1),
              child: Text('$d', style: labelStyle()),
            ),
        ]),
        row([
          for (var d = 4; d <= 6; d++)
            _key(
              index: d - 1,
              onTap: () => _activateKey(d - 1),
              child: Text('$d', style: labelStyle()),
            ),
        ]),
        row([
          for (var d = 7; d <= 9; d++)
            _key(
              index: d - 1,
              onTap: () => _activateKey(d - 1),
              child: Text('$d', style: labelStyle()),
            ),
        ]),
        row([
          _key(
            index: 9,
            onTap: () => _activateKey(9),
            child: Icon(
              Icons.backspace_rounded,
              color: Colors.white70,
              size: tv ? 18 : 16,
            ),
          ),
          _key(
            index: 10,
            onTap: () => _activateKey(10),
            child: Text('0', style: labelStyle()),
          ),
          _key(
            index: 11,
            danger: true,
            onTap: () => _activateKey(11),
            child: Text(
              'settings_refresh_dialog_cancel'.tr,
              style: labelStyle(danger: true).copyWith(fontSize: tv ? 12 : 11),
            ),
          ),
        ]),
      ],
    );
  }
}
