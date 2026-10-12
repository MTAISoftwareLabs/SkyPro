part of '../screens.dart';

/// تفعيل «الضغط» من ريموت التلفاز / كيبورد (select / enter / space / A) عند عنصر مركّز.
KeyEventResult settingsTvActivateOnSelect(KeyEvent event, VoidCallback onTap) {
  // KeyDown فقط — نتجاهل KeyRepeat حتى لا يفتح الحوار مرات.
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final k = event.logicalKey;
  if (k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.space ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA ||
      k == LogicalKeyboardKey.accept) {
    onTap();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// هالة/إطار التركيز — للتلفاز فقط (لا تظهر أثناء اللمس على الهاتف).
bool settingsShowFocusDecor(BuildContext context, bool hasFocus) {
  return hasFocus && isTv(context);
}

/// Focus لبلاطات الإعدادات: يمنع Material/Switch من سرقة التركيز ورسم طبقة صفراء
/// فوق الأيقونة والنص على التلفاز.
Focus settingsTvTileFocus({
  FocusNode? focusNode,
  ValueChanged<bool>? onFocusChange,
  FocusOnKeyEventCallback? onKeyEvent,
  bool autofocus = false,
  required Widget child,
}) {
  return Focus(
    focusNode: focusNode,
    autofocus: autofocus,
    // الأبناء (InkWell/Switch) يبقون قابلين للمس لكن بلا Focus مستقل.
    descendantsAreFocusable: false,
    descendantsAreTraversable: false,
    onFocusChange: onFocusChange,
    onKeyEvent: onKeyEvent,
    child: child,
  );
}

/// إزالة التركيز بعد اللمس على الهاتف.
void settingsReleaseTouchFocus(BuildContext context) {
  if (isTv(context)) return;
  FocusManager.instance.primaryFocus?.unfocus();
}

bool _settingsBackFocusArmed = false;

/// يُسلَّح عند فتح الإعدادات حتى ياخد زر الرجوع التركيز أول مرة (تلفاز فقط).
void settingsArmInitialBackFocus() {
  _settingsBackFocusArmed = true;
}

void settingsDisarmInitialBackFocus() {
  _settingsBackFocusArmed = false;
}

bool get settingsInitialBackFocusPending => _settingsBackFocusArmed;

/// يركّز زر الرجوع مرة واحدة عند أول ظهور لصفحة الإعدادات.
void settingsTryInitialBackFocus(BuildContext context, FocusNode node) {
  if (!_settingsBackFocusArmed || !isTv(context)) return;
  _settingsBackFocusArmed = false;
  settingsRestoreFocusIfTv(context, node);

  // إطارين إضافيين: المحتوى كيقدر ياخد التركيز قبل ما الزر يتسجل.
  void reassert(int left) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!node.canRequestFocus) return;
      if (FocusManager.instance.primaryFocus != node) {
        node.requestFocus();
      }
      if (left > 1) reassert(left - 1);
    });
  }

  reassert(3);
}

/// استعادة التركيز بعد الرجوع — للتلفاز فقط.
void settingsRestoreFocusIfTv(
  BuildContext context,
  FocusNode? node, {
  int maxAttempts = 6,
}) {
  if (node == null || !isTv(context)) return;

  void tryFocus(int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (node.canRequestFocus) {
        node.requestFocus();
        return;
      }
      if (attempt + 1 < maxAttempts) {
        tryFocus(attempt + 1);
      }
    });
  }

  tryFocus(0);
}

/// مجموعة ترتيب صريحة لعناصر الإعدادات (تلفاز + محاكي/كيبورد).
Widget wrapSettingsTvFocusTraversal(
  BuildContext context, {
  required Widget child,
}) {
  return FocusTraversalGroup(
    policy: OrderedTraversalPolicy(),
    child: child,
  );
}

/// ربط عنصر بترتيب رقمي داخل [wrapSettingsTvFocusTraversal].
Widget settingsTvTraversalOrder(
  BuildContext context, {
  required double order,
  required Widget child,
}) {
  return FocusTraversalOrder(
    order: NumericFocusOrder(order),
    child: child,
  );
}

/// يُبقي العنصر المركّز ظاهراً داخل [SingleChildScrollView] أثناء التنقل بالريموت.
void settingsEnsureFocusedVisible({
  double alignment = 0.35,
  Duration? duration,
}) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return;
  final anim = duration ?? kTvEnsureVisibleDuration;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!ctx.mounted) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: alignment,
      duration: anim,
      curve: Curves.easeOutCubic,
    );
  });
}
