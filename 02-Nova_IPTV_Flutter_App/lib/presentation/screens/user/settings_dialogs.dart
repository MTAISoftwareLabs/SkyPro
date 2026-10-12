part of '../screens.dart';

class _RefreshContentConfirmDialog extends StatefulWidget {
  const _RefreshContentConfirmDialog();

  @override
  State<_RefreshContentConfirmDialog> createState() =>
      _RefreshContentConfirmDialogState();
}

class _RefreshContentConfirmDialogState extends State<_RefreshContentConfirmDialog> {
  final FocusNode _cancelFocusNode = FocusNode();
  final FocusNode _confirmFocusNode = FocusNode();
  bool _cancelFocused = false;
  bool _confirmFocused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && isTv(context)) _confirmFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cancelFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  Widget _dialogAction({
    required FocusNode node,
    required bool focused,
    required void Function(bool) onFocusChanged,
    required VoidCallback onPressed,
    required Widget label,
    required bool primary,
  }) {
    return Builder(
      builder: (ctx) {
        final showFocus = settingsShowFocusDecor(ctx, focused);
        return Focus(
      focusNode: node,
      onFocusChange: onFocusChanged,
      onKeyEvent: (n, e) => settingsTvActivateOnSelect(e, onPressed),
      child: AnimatedScale(
        scale: showFocus ? kTvFocusScale(true, 1.06) : 1.0,
        duration: kFocusAnimDuration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: showFocus ? kColorPrimary : Colors.white.withValues(alpha: 0.14),
              width: showFocus ? 2 : 1,
            ),
            boxShadow: settingsThemedFocusGlow(showFocus),
            color: primary
                ? kColorPrimary.withValues(alpha: showFocus ? 0.28 : 0.16)
                : Colors.white.withValues(alpha: 0.05),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(child: label),
              ),
            ),
          ),
        ),
      ),
    );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    Widget cancelBtn = _dialogAction(
      node: _cancelFocusNode,
      focused: _cancelFocused,
      onFocusChanged: (v) {
        if (_cancelFocused != v) setState(() => _cancelFocused = v);
      },
      onPressed: () => Navigator.of(context).pop(false),
      primary: false,
      label: Text(
        'settings_refresh_dialog_cancel'.tr,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    Widget confirmBtn = _dialogAction(
      node: _confirmFocusNode,
      focused: _confirmFocused,
      onFocusChanged: (v) {
        if (_confirmFocused != v) setState(() => _confirmFocused = v);
      },
      onPressed: () => Navigator.of(context).pop(true),
      primary: true,
      label: Text(
        'settings_refresh_dialog_confirm'.tr,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (tv) {
      cancelBtn = FocusTraversalOrder(
        order: NumericFocusOrder(1),
        child: cancelBtn,
      );
      confirmBtn = FocusTraversalOrder(
        order: NumericFocusOrder(2),
        child: confirmBtn,
      );
    }

    return wrapAppDirectionality(
      child: Dialog(
      backgroundColor: Colors.transparent,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF121418),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: kColorPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      FontAwesomeIcons.arrowsRotate,
                      color: kColorPrimary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'settings_refresh_dialog_title'.tr,
                      style: Get.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'settings_refresh_dialog_body'.tr,
                style: Get.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: cancelBtn),
                  const SizedBox(width: 10),
                  Expanded(child: confirmBtn),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _SettingsChoiceItem {
  const _SettingsChoiceItem({
    required this.id,
    required this.label,
    this.subtitle,
    this.leading,
  });

  final String id;
  final String label;
  final String? subtitle;
  final Widget? leading;
}

const List<String> _kOrderedThemeKeys = <String>[
  'original',
  'netflix_red',
  'ramadan_gold',
  'sports_sky',
  'halloween_orange',
  'purple',
];

List<String> _availableThemeKeys() =>
    _kOrderedThemeKeys.where((k) => allowedHomeThemes.contains(k)).toList();

String _themeLabelForKey(String key) {
  switch (key) {
    case 'original':
      return 'theme_original'.tr;
    case 'netflix_red':
      return 'theme_netflix'.tr;
    case 'ramadan_gold':
      return 'theme_ramadan'.tr;
    case 'sports_sky':
      return 'theme_sports'.tr;
    case 'halloween_orange':
      return 'theme_halloween'.tr;
    case 'purple':
      return 'theme_purple'.tr;
    default:
      return key;
  }
}

IconData _themeIconForKey(String key) {
  switch (key) {
    case 'netflix_red':
      return FontAwesomeIcons.film;
    case 'ramadan_gold':
      return FontAwesomeIcons.moon;
    case 'sports_sky':
      return FontAwesomeIcons.futbol;
    case 'halloween_orange':
      return FontAwesomeIcons.ghost;
    case 'purple':
      return FontAwesomeIcons.wandMagicSparkles;
    default:
      return FontAwesomeIcons.palette;
  }
}

Color _themeAccentForKey(String key) {
  switch (key) {
    case 'netflix_red':
      return const Color(0xFFE53935);
    case 'ramadan_gold':
      return const Color(0xFF81C784);
    case 'sports_sky':
      return const Color(0xFF4FC3F7);
    case 'halloween_orange':
      return const Color(0xFFFF9800);
    case 'purple':
      return const Color(0xFFB026FF);
    default:
      return const Color(0xFFF5C242);
  }
}

/// شبكة اختيار الثيمات — تعرض كل الثيمات دون قصّ، مع تركيز ريموت سلس.
class _ThemeGridDialog extends StatefulWidget {
  const _ThemeGridDialog({
    required this.selectedId,
    required this.themeKeys,
    required this.onPick,
  });

  final String selectedId;
  final List<String> themeKeys;
  final ValueChanged<String> onPick;

  @override
  State<_ThemeGridDialog> createState() => _ThemeGridDialogState();
}

class _ThemeGridDialogState extends State<_ThemeGridDialog> {
  final List<FocusNode> _nodes = [];
  final List<bool> _focused = [];
  late String _selectedId;
  final FocusNode _closeFocus = FocusNode(debugLabel: 'theme_close');
  bool _closeFocused = false;

  /// أعمدة الصف الأول: على التلفاز كل الثيمات في صف واحد؛ على الهاتف 3 ثم الباقي.
  int _colsFor(BuildContext context, int count) {
    if (isTv(context) || MediaQuery.sizeOf(context).width >= 560) {
      return count.clamp(1, 5);
    }
    return count <= 3 ? count : 3;
  }

  int _lastPickedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    for (var i = 0; i < widget.themeKeys.length; i++) {
      _nodes.add(FocusNode(debugLabel: 'theme_grid_$i'));
      _focused.add(false);
    }
    final initial = widget.themeKeys.indexOf(_selectedId);
    _lastPickedIndex = initial < 0 ? 0 : initial;
    // عند إعادة بناء MaterialApp بسبب تغيير الثيم — أعد التركيز فوراً لنفس البطاقة.
    homeThemeRevision.addListener(_onHomeThemeRevision);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !isTv(context)) return;
      _retainFocusOn(_lastPickedIndex);
    });
  }

  @override
  void dispose() {
    homeThemeRevision.removeListener(_onHomeThemeRevision);
    for (final n in _nodes) {
      n.dispose();
    }
    _closeFocus.dispose();
    super.dispose();
  }

  void _onHomeThemeRevision() {
    if (!mounted) return;
    _retainFocusOn(_lastPickedIndex);
  }

  /// يعيد التركيز بصرياً وفعلياً بعد تغيير الثيم (إعادة بناء التطبيق).
  void _retainFocusOn(int index) {
    if (index < 0 || index >= _nodes.length) return;
    _lastPickedIndex = index;

    void attempt(int n) {
      if (!mounted) return;
      final node = _nodes[index];
      if (node.canRequestFocus) {
        node.requestFocus();
      }
      if (mounted) {
        setState(() {
          for (var i = 0; i < _focused.length; i++) {
            _focused[i] = i == index;
          }
        });
      }
      if (n < 10) {
        Future<void>.delayed(Duration(milliseconds: 30 + n * 20), () {
          if (!mounted) return;
          // إن هرب التركيز خارج الحوار — اسحبه مجدداً.
          final primary = FocusManager.instance.primaryFocus;
          if (primary != node) {
            attempt(n + 1);
          }
        });
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt(0));
  }

  void _pick(int index) {
    final key = widget.themeKeys[index];
    // إعادة الضغط على الثيم المطبق → إغلاق القائمة (هاتف وتلفاز).
    if (key == _selectedId || key == getActiveHomeThemeKey()) {
      Navigator.of(context).pop();
      return;
    }
    _lastPickedIndex = index;
    // حدّث التمييز أولاً حتى يبقى لون الثيم المطبق واضحاً أثناء إعادة البناء.
    setState(() {
      _selectedId = key;
      for (var i = 0; i < _focused.length; i++) {
        _focused[i] = i == index;
      }
    });
    widget.onPick(key);
    _retainFocusOn(index);
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent || !isTv(context)) {
      return KeyEventResult.ignored;
    }
    final activate = settingsTvActivateOnSelect(event, () => _pick(index));
    if (activate == KeyEventResult.handled) return activate;

    final count = widget.themeKeys.length;
    final cols = _colsFor(context, count);
    final row = index ~/ cols;
    final col = index % cols;
    final rows = (count / cols).ceil();
    final rtl = Directionality.of(context) == TextDirection.rtl;

    int? target;
    final key = event.logicalKey;
    final goNext = rtl
        ? key == LogicalKeyboardKey.arrowLeft
        : key == LogicalKeyboardKey.arrowRight;
    final goPrev = rtl
        ? key == LogicalKeyboardKey.arrowRight
        : key == LogicalKeyboardKey.arrowLeft;

    if (goNext) {
      if (index + 1 < count && col < cols - 1) {
        target = index + 1;
      } else if (index + 1 < count && row == rows - 1) {
        // آخر صف قد يكون أقصر
        target = index + 1;
      }
    } else if (goPrev) {
      if (col > 0) target = index - 1;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      final next = index + cols;
      if (next < count) {
        target = next;
      } else if (row < rows - 1) {
        target = count - 1;
      } else {
        _closeFocus.requestFocus();
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      final prev = index - cols;
      if (prev >= 0) {
        target = prev;
      } else {
        _closeFocus.requestFocus();
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    if (target != null) {
      _nodes[target].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _themeCard(int index, {required bool compact}) {
    final tv = isTv(context);
    final key = widget.themeKeys[index];
    final selected = key == _selectedId;
    final accent = _themeAccentForKey(key);
    // أبقِ هالة التركيز ظاهرة على آخر ثيم مطبق حتى لو فقد FocusNode لحظة إعادة البناء.
    final showFocus = settingsShowFocusDecor(
      context,
      _focused[index] || (tv && _lastPickedIndex == index && selected),
    );
    final ringColor = showFocus || selected ? accent : Colors.white.withValues(alpha: 0.12);

    return Focus(
      focusNode: _nodes[index],
      onFocusChange: (v) {
        if (!tv) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        if (v) {
          if (!_focused[index] || _lastPickedIndex != index) {
            setState(() {
              _lastPickedIndex = index;
              for (var i = 0; i < _focused.length; i++) {
                _focused[i] = i == index;
              }
            });
          }
          return;
        }
        // لا تمسح التركيز البصري عن الثيم المطبق أثناء إعادة بناء MaterialApp.
        if (_lastPickedIndex == index && selected) return;
        if (_focused[index]) {
          setState(() => _focused[index] = false);
        }
      },
      onKeyEvent: (n, e) => _onKey(index, e),
      child: AnimatedScale(
        scale: showFocus ? kTvFocusScale(true, 1.04) : 1.0,
        duration: kFocusAnimDuration,
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: selected || showFocus ? 0.32 : 0.12),
                Colors.white.withValues(alpha: 0.03),
              ],
            ),
            border: Border.all(
              color: ringColor,
              width: showFocus || selected ? 2.2 : 1,
            ),
            boxShadow: [
              if (selected || showFocus)
                BoxShadow(
                  color: accent.withValues(alpha: 0.4),
                  blurRadius: 14,
                ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pick(index),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: compact ? 8 : 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: compact ? 30 : 36,
                      height: compact ? 30 : 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            accent.withValues(alpha: 0.9),
                            accent.withValues(alpha: 0.35),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(
                        _themeIconForKey(key),
                        color: Colors.white,
                        size: compact ? 13 : 15,
                      ),
                    ),
                    SizedBox(height: compact ? 5 : 7),
                    Text(
                      _themeLabelForKey(key),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Get.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: compact ? 10.5 : 11.5,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(height: 3),
                      Icon(
                        FontAwesomeIcons.circleCheck,
                        color: accent,
                        size: 12,
                      ),
                    ] else
                      const SizedBox(height: 15),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// صفوف ثابتة بدون سحب — كل الثيمات ظاهرة دفعة واحدة.
  Widget _buildAllThemesVisible(BuildContext context) {
    final keys = widget.themeKeys;
    final cols = _colsFor(context, keys.length);
    final compact = keys.length >= 5;
    final rows = <Widget>[];

    for (var start = 0; start < keys.length; start += cols) {
      final end = (start + cols).clamp(0, keys.length);
      final slice = <Widget>[];
      for (var i = start; i < end; i++) {
        slice.add(Expanded(child: _themeCard(i, compact: compact)));
        if (i < end - 1) slice.add(const SizedBox(width: 8));
      }
      // املأ الفراغ في آخر صف ليبقى المحاذاة متزنة
      final missing = cols - (end - start);
      for (var m = 0; m < missing; m++) {
        slice.add(const SizedBox(width: 8));
        slice.add(const Expanded(child: SizedBox.shrink()));
      }
      rows.add(Row(children: slice));
      if (end < keys.length) rows.add(const SizedBox(height: 8));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showCloseFocus = settingsShowFocusDecor(context, _closeFocused);

    return wrapAppDirectionality(
      child: Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: tv ? 6.w : 16,
        vertical: tv ? 10.h : 20,
      ),
      child: FocusScope(
        autofocus: true,
        child: Container(
        constraints: BoxConstraints(maxWidth: tv ? 900 : 460),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF161A22),
              kColorCardLight,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 12),
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
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: kColorPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    FontAwesomeIcons.palette,
                    color: kColorPrimary,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'theme_selector_label'.tr,
                    style: Get.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Focus(
                  focusNode: _closeFocus,
                  onFocusChange: (v) {
                    if (_closeFocused != v) {
                      setState(() => _closeFocused = v);
                    }
                  },
                  onKeyEvent: (n, e) {
                    if (e is! KeyDownEvent) return KeyEventResult.ignored;
                    final activate = settingsTvActivateOnSelect(
                      e,
                      () => Navigator.of(context).pop(),
                    );
                    if (activate == KeyEventResult.handled) return activate;
                    if (e.logicalKey == LogicalKeyboardKey.arrowDown ||
                        e.logicalKey == LogicalKeyboardKey.arrowLeft ||
                        e.logicalKey == LogicalKeyboardKey.arrowRight) {
                      final idx = widget.themeKeys.indexOf(_selectedId);
                      _nodes[idx < 0 ? 0 : idx].requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.escape ||
                        e.logicalKey == LogicalKeyboardKey.goBack) {
                      Navigator.of(context).pop();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 110),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: showCloseFocus
                            ? kColorPrimary
                            : Colors.transparent,
                        width: showCloseFocus ? 1.6 : 0,
                      ),
                      boxShadow: settingsThemedFocusGlow(showCloseFocus),
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'settings_refresh_dialog_cancel'.tr,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildAllThemesVisible(context),
          ],
        ),
        ),
      ),
      ),
    );
  }
}

/// حوار اختيار عصري (لغة، مشغل) مع دعم ريموت التلفاز.
class _SettingsChoiceDialog extends StatefulWidget {
  const _SettingsChoiceDialog({
    required this.title,
    required this.titleIcon,
    required this.items,
    required this.selectedId,
    this.compactItems = false,
  });

  final String title;
  final IconData titleIcon;
  final List<_SettingsChoiceItem> items;
  final String selectedId;
  /// تباعد أصغر بين العناصر (مثلاً قائمة لغات الترجمة).
  final bool compactItems;

  @override
  State<_SettingsChoiceDialog> createState() => _SettingsChoiceDialogState();
}

class _SettingsChoiceDialogState extends State<_SettingsChoiceDialog> {
  final List<FocusNode> _optionNodes = [];
  final List<bool> _optionFocused = [];
  final FocusNode _closeFocus = FocusNode(debugLabel: 'settings_choice_close');
  bool _closeFocused = false;
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    for (var i = 0; i < widget.items.length; i++) {
      _optionNodes.add(FocusNode(debugLabel: 'settings_choice_$i'));
      _optionFocused.add(false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!isTv(context)) return;
      _focusSelectedOption();
    });
  }

  void _focusSelectedOption() {
    final selectedIdx =
        widget.items.indexWhere((e) => e.id == _selectedId);
    final idx = selectedIdx >= 0 ? selectedIdx : 0;
    settingsRestoreFocusIfTv(context, _optionNodes[idx]);
  }

  @override
  void dispose() {
    _closeFocus.dispose();
    for (final n in _optionNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _close() {
    Navigator.of(context).pop();
  }

  void _pick(String id) {
    Navigator.of(context).pop(id);
  }

  Widget _optionTile(int index) {
    final item = widget.items[index];
    final selected = item.id == _selectedId;
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, _optionFocused[index]);
    final compact = widget.compactItems;
    final iconBox = compact ? 34.0 : 44.0;
    final gap = compact ? 4.0 : 10.0;
    final padH = compact ? 12.0 : 14.0;
    final padV = compact ? 8.0 : 13.0;
    final hasSubtitle = (item.subtitle ?? '').trim().isNotEmpty;

    Widget tile = Focus(
      focusNode: _optionNodes[index],
      autofocus: tv && selected,
      onFocusChange: (v) {
        if (!tv) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        if (_optionFocused[index] != v) {
          setState(() => _optionFocused[index] = v);
        }
        if (v) {
          final ctx = _optionNodes[index].context;
          if (ctx != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!ctx.mounted) return;
              Scrollable.ensureVisible(
                ctx,
                alignment: 0.35,
                duration: kTvEnsureVisibleDuration,
                curve: Curves.easeOut,
              );
            });
          }
        }
      },
      onKeyEvent: tv
          ? (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack) {
                _close();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowUp && index == 0) {
                _closeFocus.requestFocus();
                return KeyEventResult.handled;
              }
              return settingsTvActivateOnSelect(event, () => _pick(item.id));
            }
          : null,
      child: AnimatedScale(
        scale: showFocus
            ? kTvFocusScale(true, compact || hasSubtitle ? 1.015 : 1.03)
            : 1.0,
        duration: kFocusAnimDuration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          margin: EdgeInsets.only(top: index == 0 ? 0 : gap),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 12 : 14),
            // التركيز: خلفية داكنة + إطار واضح — بدون تعبئة صفراء ثقيلة.
            // المحدد بدون تركيز: تمييز خفيف فقط.
            gradient: (!showFocus && selected)
                ? LinearGradient(
                    colors: [
                      kColorPrimary.withValues(alpha: 0.16),
                      kColorPrimaryDark.withValues(alpha: 0.10),
                    ],
                  )
                : null,
            color: showFocus
                ? const Color(0xFF1A1F28)
                : (selected ? null : Colors.white.withValues(alpha: 0.045)),
            border: Border.all(
              color: showFocus
                  ? kColorPrimary
                  : (selected
                      ? kColorPrimary.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.12)),
              width: showFocus ? 2.4 : 1,
            ),
            boxShadow: showFocus
                ? [
                    BoxShadow(
                      color: kColorPrimary.withValues(alpha: 0.32),
                      blurRadius: 12,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
              onTap: () => _pick(item.id),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                child: Row(
                  children: [
                    Container(
                      width: iconBox,
                      height: iconBox,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(compact ? 10 : 12),
                        color: (selected || showFocus)
                            ? kColorPrimary.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: (selected || showFocus)
                              ? kColorPrimary.withValues(alpha: 0.55)
                              : Colors.white24,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Center(
                        child: item.leading ??
                            Icon(
                              FontAwesomeIcons.circle,
                              color: (selected || showFocus)
                                  ? kColorPrimary
                                  : Colors.white54,
                              size: compact ? 16 : 20,
                            ),
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.label,
                            style: Get.textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: (selected || showFocus)
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: compact ? 13.5 : null,
                            ),
                          ),
                          if (hasSubtitle) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.subtitle!.tr,
                              style: Get.textTheme.bodySmall?.copyWith(
                                color: showFocus
                                    ? Colors.white70
                                    : Colors.white54,
                                height: 1.25,
                                fontSize: compact ? 11.5 : 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(
                        FontAwesomeIcons.circleCheck,
                        color: kColorPrimary,
                        size: compact ? 16 : 20,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (tv) {
      tile = FocusTraversalOrder(
        order: NumericFocusOrder(index + 1.0),
        child: tile,
      );
    }
    return tile;
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final maxH = MediaQuery.sizeOf(context).height * (tv ? 0.78 : 0.72);
    final showCloseFocus = settingsShowFocusDecor(context, _closeFocused);
    return wrapAppDirectionality(
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: tv ? 28 : 24,
          vertical: tv ? 20 : 24,
        ),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: tv ? 520 : 420,
              maxHeight: maxH,
            ),
            padding: EdgeInsets.fromLTRB(tv ? 16 : 18, 14, tv ? 12 : 18, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF121418),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kColorPrimary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.titleIcon,
                        color: kColorPrimary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Get.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(0),
                      child: Focus(
                        focusNode: _closeFocus,
                        onFocusChange: (v) {
                          if (!tv) {
                            if (v) settingsReleaseTouchFocus(context);
                            return;
                          }
                          if (_closeFocused != v) {
                            setState(() => _closeFocused = v);
                          }
                        },
                        onKeyEvent: (n, e) {
                          if (e is! KeyDownEvent) return KeyEventResult.ignored;
                          final activate = settingsTvActivateOnSelect(
                            e,
                            _close,
                          );
                          if (activate == KeyEventResult.handled) return activate;
                          if (e.logicalKey == LogicalKeyboardKey.arrowDown ||
                              e.logicalKey == LogicalKeyboardKey.arrowLeft ||
                              e.logicalKey == LogicalKeyboardKey.arrowRight) {
                            _focusSelectedOption();
                            return KeyEventResult.handled;
                          }
                          if (e.logicalKey == LogicalKeyboardKey.escape ||
                              e.logicalKey == LogicalKeyboardKey.goBack) {
                            _close();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: AnimatedContainer(
                          duration: kFocusAnimDuration,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: showCloseFocus
                                  ? kColorPrimary
                                  : Colors.transparent,
                              width: showCloseFocus ? 2 : 0,
                            ),
                            boxShadow: showCloseFocus
                                ? [
                                    BoxShadow(
                                      color: kColorPrimary.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : const [],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _close,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: tv ? 24 : 22,
                                  color: showCloseFocus
                                      ? kColorPrimary
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: widget.items.length,
                    itemBuilder: (context, i) => _optionTile(i),
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

/// حوار Feedback للتلفاز (بدون كيبورد لمسي).
class _SettingsFeedbackDialog extends StatefulWidget {
  const _SettingsFeedbackDialog();

  @override
  State<_SettingsFeedbackDialog> createState() =>
      _SettingsFeedbackDialogState();
}

class _SettingsFeedbackDialogState extends State<_SettingsFeedbackDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final FocusNode _cancelFocus = FocusNode();
  final FocusNode _sendFocus = FocusNode();
  bool _cancelFocused = false;
  bool _sendFocused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _cancelFocus.dispose();
    _sendFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final note = _controller.text.trim();
    if (note.isEmpty) return;
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    return wrapAppDirectionality(
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
            color: kColorCardLight,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        FontAwesomeIcons.commentDots,
                        color: kColorPrimary,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'feedback_section_title'.tr,
                          style: Get.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'feedback_section_desc'.tr,
                    style: Get.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    focusNode: _inputFocus,
                    maxLines: 4,
                    maxLength: 500,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'feedback_hint'.tr,
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: kColorPrimary,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Focus(
                          focusNode: _cancelFocus,
                          onFocusChange: (v) {
                            if (_cancelFocused != v) {
                              setState(() => _cancelFocused = v);
                            }
                          },
                          onKeyEvent:
                              (n, e) => settingsTvActivateOnSelect(
                                e,
                                () => Navigator.of(context).pop(),
                              ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color:
                                    settingsShowFocusDecor(
                                          context,
                                          _cancelFocused,
                                        )
                                        ? kColorPrimary
                                        : Colors.white24,
                                width:
                                    settingsShowFocusDecor(
                                          context,
                                          _cancelFocused,
                                        )
                                        ? 2
                                        : 1,
                              ),
                            ),
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('settings_refresh_dialog_cancel'.tr),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Focus(
                          focusNode: _sendFocus,
                          onFocusChange: (v) {
                            if (_sendFocused != v) {
                              setState(() => _sendFocused = v);
                            }
                          },
                          onKeyEvent:
                              (n, e) => settingsTvActivateOnSelect(e, _submit),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: settingsThemedFocusGlow(
                                settingsShowFocusDecor(context, _sendFocused),
                              ),
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _submit,
                              icon: const Icon(
                                FontAwesomeIcons.paperPlane,
                                size: 13,
                              ),
                              label: Text('feedback_send'.tr),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kColorPrimary,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// ورقة Feedback للهاتف — تلتصق بأسفل الشاشة فوق لوحة المفاتيح.
class _SettingsFeedbackSheet extends StatefulWidget {
  const _SettingsFeedbackSheet();

  @override
  State<_SettingsFeedbackSheet> createState() => _SettingsFeedbackSheetState();
}

class _SettingsFeedbackSheetState extends State<_SettingsFeedbackSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final note = _controller.text.trim();
    if (note.isEmpty) return;
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return wrapAppDirectionality(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(12, 0, 12, keyboard + 8),
        child: Material(
          color: kColorCardLight,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        FontAwesomeIcons.commentDots,
                        color: kColorPrimary,
                        size: 15,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'feedback_section_title'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Get.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          LucideIcons.x,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: _controller,
                    focusNode: _inputFocus,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      color: Colors.white,
                      height: 1.3,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'feedback_hint'.tr,
                      hintStyle: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: kColorPrimary,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('settings_refresh_dialog_cancel'.tr),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _submit,
                          icon: const Icon(
                            FontAwesomeIcons.paperPlane,
                            size: 12,
                          ),
                          label: Text('feedback_send'.tr),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kColorPrimary,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
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

enum _SpeedTestPhase { idle, ping, download, done, error }

class _SpeedTestDialog extends StatefulWidget {
  const _SpeedTestDialog();

  @override
  State<_SpeedTestDialog> createState() => _SpeedTestDialogState();
}

class _SpeedTestDialogState extends State<_SpeedTestDialog>
    with SingleTickerProviderStateMixin {
  static const _endpoint = 'https://speed.cloudflare.com/__down';
  static const _downloadBytes = 5 * 1024 * 1024;

  final FocusNode _primaryFocusNode = FocusNode();
  final FocusNode _closeFocusNode = FocusNode();
  bool _primaryFocused = false;
  bool _closeFocused = false;

  late final AnimationController _pulse;
  CancelToken? _cancelToken;

  _SpeedTestPhase _phase = _SpeedTestPhase.idle;
  double _gauge = 0;
  double? _pingMs;
  double? _downloadMbps;
  String? _status;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isTv(context)) {
        _primaryFocusNode.requestFocus();
      } else {
        _runTest();
      }
    });
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _pulse.dispose();
    _primaryFocusNode.dispose();
    _closeFocusNode.dispose();
    super.dispose();
  }

  bool get _busy =>
      _phase == _SpeedTestPhase.ping || _phase == _SpeedTestPhase.download;

  String get _qualityKey {
    final mbps = _downloadMbps;
    if (mbps == null) return '';
    if (mbps >= 50) return 'speed_test_quality_excellent';
    if (mbps >= 20) return 'speed_test_quality_good';
    if (mbps >= 8) return 'speed_test_quality_fair';
    return 'speed_test_quality_poor';
  }

  Color get _qualityColor {
    final mbps = _downloadMbps;
    if (mbps == null) return kColorPrimary;
    if (mbps >= 50) return const Color(0xFF3DDC97);
    if (mbps >= 20) return const Color(0xFF6BCBFF);
    if (mbps >= 8) return const Color(0xFFFFC857);
    return const Color(0xFFFF6B6B);
  }

  Future<void> _runTest() async {
    if (_busy) return;
    _cancelToken?.cancel();
    final token = CancelToken();
    _cancelToken = token;

    setState(() {
      _phase = _SpeedTestPhase.ping;
      _gauge = 0.08;
      _pingMs = null;
      _downloadMbps = null;
      _status = 'speed_test_phase_ping'.tr;
    });

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 45),
        responseType: ResponseType.bytes,
        headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      ),
    );

    try {
      // Warm-up then average a few tiny probes for latency.
      await dio.get<List<int>>(
        _endpoint,
        queryParameters: const {'bytes': 1000},
        cancelToken: token,
      );
      final samples = <double>[];
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        await dio.get<List<int>>(
          _endpoint,
          queryParameters: const {'bytes': 1000},
          cancelToken: token,
        );
        sw.stop();
        samples.add(sw.elapsedMilliseconds.toDouble());
        if (!mounted) return;
        setState(() {
          _gauge = 0.12 + (i + 1) * 0.08;
          _pingMs = samples.reduce((a, b) => a + b) / samples.length;
        });
      }

      if (!mounted) return;
      setState(() {
        _phase = _SpeedTestPhase.download;
        _status = 'speed_test_phase_download'.tr;
        _gauge = 0.38;
      });

      var received = 0;
      final sw = Stopwatch()..start();
      await dio.get<List<int>>(
        _endpoint,
        queryParameters: const {'bytes': _downloadBytes},
        cancelToken: token,
        onReceiveProgress: (count, total) {
          if (!mounted || token.isCancelled) return;
          received = count;
          final elapsedSec = sw.elapsedMicroseconds / 1e6;
          if (elapsedSec <= 0.05) return;
          final mbps = (count * 8) / (elapsedSec * 1000 * 1000);
          final progress = total > 0 ? count / total : count / _downloadBytes;
          setState(() {
            _downloadMbps = mbps;
            _gauge = 0.38 + progress.clamp(0.0, 1.0) * 0.58;
          });
        },
      );
      sw.stop();
      if (!mounted) return;

      final elapsedSec = sw.elapsedMicroseconds / 1e6;
      final bytes = received > 0 ? received : _downloadBytes;
      final mbps =
          elapsedSec > 0 ? (bytes * 8) / (elapsedSec * 1000 * 1000) : 0.0;

      setState(() {
        _downloadMbps = mbps;
        _gauge = 1;
        _phase = _SpeedTestPhase.done;
        _status = null;
      });
      if (isTv(context)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _primaryFocusNode.requestFocus();
        });
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || !mounted) return;
      setState(() {
        _phase = _SpeedTestPhase.error;
        _status = 'speed_test_failed'.tr;
        _gauge = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _SpeedTestPhase.error;
        _status = 'speed_test_failed'.tr;
        _gauge = 0;
      });
    }
  }

  Widget _actionButton({
    required FocusNode node,
    required bool focused,
    required void Function(bool) onFocusChanged,
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required bool primary,
    required num focusOrder,
  }) {
    final tv = isTv(context);
    final enabled = onPressed != null;
    Widget btn = Builder(
      builder: (context) {
        return Focus(
          focusNode: node,
          onFocusChange: (v) {
            if (!tv) {
              if (v) settingsReleaseTouchFocus(context);
              return;
            }
            onFocusChanged(v);
          },
          onKeyEvent: (n, e) => settingsTvActivateOnSelect(e, () {
            if (enabled) onPressed();
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: settingsThemedFocusGlow(
                settingsShowFocusDecor(context, focused),
              ),
            ),
            child: ElevatedButton.icon(
              onPressed: enabled
                  ? () {
                      settingsReleaseTouchFocus(context);
                      onPressed();
                    }
                  : null,
              icon: Icon(icon, size: 14),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    primary ? kColorPrimary : Colors.white.withValues(alpha: 0.08),
                foregroundColor: primary ? Colors.black : Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
                disabledForegroundColor: Colors.white38,
                minimumSize: Size.fromHeight(isTv(context) ? 44 : 40),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (tv) {
      btn = FocusTraversalOrder(
        order: NumericFocusOrder(focusOrder.toDouble()),
        child: btn,
      );
    }
    return btn;
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color accent,
    required bool compact,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 11,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 26 : 30,
              height: compact ? 26 : 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: compact ? 12 : 13, color: accent),
            ),
            SizedBox(height: compact ? 6 : 9),
            Text(
              label,
              style: Get.textTheme.labelSmall?.copyWith(
                color: Colors.white60,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 10.5 : null,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: (compact
                            ? Get.textTheme.titleMedium
                            : Get.textTheme.titleLarge)
                        ?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(
                    unit,
                    style: Get.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 10 : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final rtl = isAppRtl();
    final media = MediaQuery.of(context);
    final screenH = media.size.height;
    final screenW = media.size.width;
    final compact = !tv && (screenH < 760 || screenW < 400);
    final gaugeSize = tv ? 168.0 : (compact ? 128.0 : 148.0);
    final maxDialogH = screenH - media.viewPadding.vertical - (tv ? 48 : 32);
    final hInset = tv ? 120.0 : 18.0;
    final vInset = tv ? 28.0 : 16.0;
    final mbps = _downloadMbps;
    final ping = _pingMs;
    final primaryLabel = switch (_phase) {
      _SpeedTestPhase.idle => 'speed_test_start'.tr,
      _SpeedTestPhase.ping ||
      _SpeedTestPhase.download => 'speed_test_testing'.tr,
      _SpeedTestPhase.done ||
      _SpeedTestPhase.error => 'speed_test_retry'.tr,
    };
    final primaryIcon = switch (_phase) {
      _SpeedTestPhase.idle => FontAwesomeIcons.bolt,
      _SpeedTestPhase.ping ||
      _SpeedTestPhase.download => FontAwesomeIcons.spinner,
      _ => FontAwesomeIcons.arrowRotateRight,
    };

    final actions = Row(
      children: [
        Expanded(
          child: _actionButton(
            node: _closeFocusNode,
            focused: _closeFocused,
            onFocusChanged: (v) {
              if (_closeFocused != v) setState(() => _closeFocused = v);
            },
            onPressed: () => Navigator.of(context).pop(),
            icon: FontAwesomeIcons.xmark,
            label: 'speed_test_close'.tr,
            primary: false,
            focusOrder: 1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            node: _primaryFocusNode,
            focused: _primaryFocused,
            onFocusChanged: (v) {
              if (_primaryFocused != v) setState(() => _primaryFocused = v);
            },
            onPressed: _busy ? null : _runTest,
            icon: primaryIcon,
            label: primaryLabel,
            primary: true,
            focusOrder: 2,
          ),
        ),
      ],
    );

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) {
                final t = _busy ? _pulse.value : 0.35;
                return Container(
                  width: compact ? 36 : 42,
                  height: compact ? 36 : 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: LinearGradient(
                      colors: [
                        kColorPrimary.withValues(alpha: 0.35 + t * 0.25),
                        const Color(0xFF2A3344),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kColorPrimary.withValues(alpha: 0.2 + t * 0.25),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: Icon(
                FontAwesomeIcons.gaugeHigh,
                color: kColorPrimary,
                size: compact ? 15 : 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'speed_test_title'.tr,
                    textAlign: rtl ? TextAlign.right : TextAlign.left,
                    style: Get.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 15.5 : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'speed_test_subtitle'.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: rtl ? TextAlign.right : TextAlign.left,
                    style: Get.textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                      height: 1.3,
                      fontSize: compact ? 11.5 : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 12 : 16),
        SizedBox(
          width: gaugeSize,
          height: gaugeSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(gaugeSize, gaugeSize),
                painter: _SpeedGaugePainter(
                  progress: _gauge.clamp(0.0, 1.0),
                  accent: _qualityColor,
                  track: Colors.white.withValues(alpha: 0.08),
                  strokeWidth: compact ? 8 : 10,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FontAwesomeIcons.wifi,
                    size: compact ? 13 : 15,
                    color: _qualityColor.withValues(alpha: 0.95),
                  ),
                  SizedBox(height: compact ? 5 : 7),
                  Text(
                    mbps == null ? '--' : mbps.toStringAsFixed(1),
                    style: Get.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      fontSize: compact ? 28 : 34,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'speed_test_mbps'.tr,
                    style: Get.textTheme.labelMedium?.copyWith(
                      color: Colors.white60,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 11 : null,
                    ),
                  ),
                  if (_qualityKey.isNotEmpty) ...[
                    SizedBox(height: compact ? 6 : 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _qualityColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _qualityColor.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        _qualityKey.tr,
                        style: TextStyle(
                          color: _qualityColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (_status != null) ...[
          SizedBox(height: compact ? 6 : 8),
          Text(
            _status!,
            textAlign: TextAlign.center,
            style: Get.textTheme.bodySmall?.copyWith(
              color: _phase == _SpeedTestPhase.error
                  ? const Color(0xFFFF8E8E)
                  : Colors.white70,
              fontSize: compact ? 11.5 : null,
            ),
          ),
        ],
        SizedBox(height: compact ? 10 : 12),
        Row(
          children: [
            _metricCard(
              icon: FontAwesomeIcons.waveSquare,
              label: 'speed_test_ping'.tr,
              value: ping == null ? '--' : ping.toStringAsFixed(0),
              unit: 'speed_test_ms'.tr,
              accent: const Color(0xFF6BCBFF),
              compact: compact,
            ),
            const SizedBox(width: 8),
            _metricCard(
              icon: FontAwesomeIcons.cloudArrowDown,
              label: 'speed_test_download'.tr,
              value: mbps == null ? '--' : mbps.toStringAsFixed(1),
              unit: 'speed_test_mbps'.tr,
              accent: _qualityColor,
              compact: compact,
            ),
          ],
        ),
      ],
    );

    return wrapAppDirectionality(
      child: Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: hInset, vertical: vInset),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: tv ? 520 : 400,
            maxHeight: maxDialogH.clamp(280, screenH),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF171B22), Color(0xFF10131A)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: kColorPrimary.withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 16,
                    compact ? 14 : 16,
                    compact ? 14 : 16,
                    compact ? 12 : 14,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final actionsGap = compact ? 10.0 : 12.0;
                      final actionsBlock = 52.0 + actionsGap;
                      final bodyMaxH =
                          (constraints.maxHeight.isFinite
                                  ? constraints.maxHeight - actionsBlock
                                  : maxDialogH - actionsBlock)
                              .clamp(120.0, maxDialogH);

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: bodyMaxH),
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: body,
                            ),
                          ),
                          SizedBox(height: actionsGap),
                          actions,
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _SpeedGaugePainter extends CustomPainter {
  _SpeedGaugePainter({
    required this.progress,
    required this.accent,
    required this.track,
    this.strokeWidth = 10,
  });

  final double progress;
  final Color accent;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth;
    const start = -math.pi * 0.75;
    const sweep = math.pi * 1.5;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      trackPaint,
    );

    final activePaint = Paint()
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + sweep,
        colors: [
          accent.withValues(alpha: 0.35),
          accent,
          Colors.white.withValues(alpha: 0.9),
        ],
        transform: GradientRotation(start),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep * progress.clamp(0.0, 1.0),
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedGaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.track != track ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

Future<void> showDeviceInfoDialog(
  BuildContext context, {
  FocusNode? returnFocus,
}) async {
  settingsReleaseTouchFocus(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _DeviceInfoDialog(),
  );
  if (context.mounted) {
    settingsRestoreFocusIfTv(context, returnFocus);
  }
}

class _DeviceInfoDialog extends StatefulWidget {
  const _DeviceInfoDialog();

  @override
  State<_DeviceInfoDialog> createState() => _DeviceInfoDialogState();
}

class _DeviceInfoDialogState extends State<_DeviceInfoDialog> {
  final FocusNode _copyFocus = FocusNode(debugLabel: 'device_info_copy');
  final FocusNode _closeFocus = FocusNode(debugLabel: 'device_info_close');
  bool _copyFocused = false;
  bool _closeFocused = false;
  bool _loading = true;
  bool _copied = false;

  String _deviceId = '';
  String _model = '—';
  String _os = '—';
  String _activationExpiry = '';
  String _serverExpiry = '';
  bool _hasServerAccount = false;
  bool _activationIsTrial = false;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !isTv(context)) return;
      _copyFocus.requestFocus();
    });
  }

  Future<void> _load() async {
    try {
      final id = (await ActivationApi().getDeviceId()).trim();
      final storage = GetStorage();
      final expiry =
          (storage.read('activation_expiry_date') ?? '').toString().trim();
      final isTrial = storage.read('activation_is_trial') == true;
      final user = LocaleApi.getUserSync();
      final hasServer = user?.userInfo != null;
      var serverExp = (user?.userInfo?.expDate ?? '').toString().trim();
      if (serverExp.isEmpty || serverExp.toLowerCase() == 'null') {
        serverExp =
            (storage.read('cached_iptv_exp_date') ?? '').toString().trim();
      }
      final info = DeviceInfoPlugin();
      var model = '—';
      var os = '—';

      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final brand = a.brand.trim();
        final name = a.model.trim();
        final joined = [brand, name].where((e) => e.isNotEmpty).join(' ');
        model = joined.isEmpty ? 'Android' : joined;
        os = 'Android ${a.version.release}'.trim();
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        final machine = i.utsname.machine.trim();
        final iosModel = i.model.trim();
        model =
            machine.isNotEmpty
                ? machine
                : (iosModel.isNotEmpty ? iosModel : 'iOS');
        os = '${i.systemName} ${i.systemVersion}'.trim();
      }

      if (!mounted) return;
      setState(() {
        _deviceId = id;
        _model = model;
        _os = os;
        _activationExpiry = expiry;
        _activationIsTrial = isTrial;
        _serverExpiry = serverExp;
        _hasServerAccount = hasServer;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _copyId() async {
    final id = _deviceId.trim();
    if (id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    setState(() => _copied = true);
    showSoftToastAboveOverlay(context, 'copied'.tr, 'device_id_copied'.tr);
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _copyFocus.dispose();
    _closeFocus.dispose();
    super.dispose();
  }

  String _formatDeviceActivationDate(String raw) {
    final info = parseActivationRemaining(raw);
    if (info == null) return raw;
    if (info.isLifetime) return 'activation_lifetime'.tr;
    final date = DateFormat('yyyy-MM-dd').format(info.expiry);
    if (_activationIsTrial) {
      return '$date (${'activation_trial'.tr})';
    }
    return date;
  }

  String _formatServerExpiryDate(String raw) {
    if (isIptvLifetimeExpDate(raw)) return 'activation_lifetime'.tr;
    final s = raw.trim();
    final ts = int.tryParse(s);
    if (ts != null) {
      final millis = s.length > 12 ? ts : ts * 1000;
      final dt = DateTime.fromMillisecondsSinceEpoch(millis);
      final dateStr = DateFormat('yyyy-MM-dd').format(dt);
      final rem = iptvSubscriptionRemaining(s);
      if (rem == null) return dateStr;
      if (rem.isLifetime) return 'activation_lifetime'.tr;
      if (rem.expired) {
        return '$dateStr · ${'subscription_expired'.tr}';
      }
      return '$dateStr · ${formatIptvSubscriptionRemainingShort(s)}';
    }
    return expirationDate(s);
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: kColorPrimary.withValues(alpha: 0.14),
              border: Border.all(color: kColorPrimary.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, size: 13, color: kColorPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  textDirection: appTextDirection,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  textDirection: appTextDirection,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required FocusNode node,
    required bool focused,
    required ValueChanged<bool> onFocusChange,
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required bool primary,
    required double order,
  }) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, focused);
    Widget chip = Focus(
      focusNode: node,
      onFocusChange: (v) {
        if (!tv) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        onFocusChange(v);
      },
      onKeyEvent:
          tv ? (n, e) => settingsTvActivateOnSelect(e, onTap) : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient:
                  primary
                      ? LinearGradient(
                        colors: [
                          kColorPrimary.withValues(alpha: 0.34),
                          kColorPrimaryDark.withValues(alpha: 0.2),
                        ],
                      )
                      : null,
              color: primary ? null : Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                color:
                    showFocus
                        ? kColorPrimary
                        : (primary
                            ? kColorPrimary.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.12)),
                width: showFocus ? 1.8 : 1,
              ),
              boxShadow: settingsThemedFocusGlow(showFocus),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: primary ? kColorPrimary : Colors.white70,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (tv) {
      chip = FocusTraversalOrder(
        order: NumericFocusOrder(order),
        child: chip,
      );
    }
    return chip;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final tv = isTv(context);
    final maxW = math.min(tv ? 420.0 : 360.0, size.width - 32);
    final maxH = math.min(
      470.0,
      size.height - pad.vertical - (tv ? 48 : 32),
    );

    final copyChip = _actionChip(
      node: _copyFocus,
      focused: _copyFocused,
      onFocusChange: (v) {
        if (_copyFocused != v) setState(() => _copyFocused = v);
      },
      onTap: _copyId,
      icon: _copied ? LucideIcons.copy_check : LucideIcons.copy,
      label: _copied ? 'copied'.tr : 'settings_device_copy'.tr,
      primary: true,
      order: 1,
    );
    final closeChip = _actionChip(
      node: _closeFocus,
      focused: _closeFocused,
      onFocusChange: (v) {
        if (_closeFocused != v) setState(() => _closeFocused = v);
      },
      onTap: () => Navigator.of(context).pop(),
      icon: LucideIcons.x,
      label: 'settings_device_close'.tr,
      primary: false,
      order: 2,
    );

    return wrapAppDirectionality(
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: tv ? 24 : 16,
          vertical: tv ? 24 : 16,
        ),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
            child: Material(
              color: const Color(0xFF121418),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // مساحة للأزرار + العنوان حتى لا تخرج خارج الحوار على الهاتف.
                      const headerBlock = 58.0;
                      const actionsBlock = 56.0;
                      final bodyMaxH = math.max(
                        120.0,
                        constraints.maxHeight - headerBlock - actionsBlock,
                      );

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  gradient: LinearGradient(
                                    colors: [
                                      kColorPrimary.withValues(alpha: 0.3),
                                      kColorPrimaryDark.withValues(
                                        alpha: 0.16,
                                      ),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: kColorPrimary.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  LucideIcons.monitor_smartphone,
                                  color: kColorPrimary,
                                  size: 17,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'settings_device_info'.tr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Get.textTheme.titleSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: Center(
                                child: SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                ),
                              ),
                            )
                          else ...[
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: bodyMaxH,
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _infoRow(
                                      icon: LucideIcons.smartphone,
                                      label: 'settings_device_model'.tr,
                                      value: _model,
                                    ),
                                    _infoRow(
                                      icon: LucideIcons.cpu,
                                      label: 'settings_device_os'.tr,
                                      value: _os,
                                    ),
                                    _infoRow(
                                      icon: LucideIcons.package,
                                      label: 'settings_device_app'.tr,
                                      value: 'v$appVersionText',
                                    ),
                                    if (_activationExpiry.isNotEmpty)
                                      _infoRow(
                                        icon: LucideIcons.shield_check,
                                        label: 'settings_device_activation'.tr,
                                        value: _formatDeviceActivationDate(
                                          _activationExpiry,
                                        ),
                                      ),
                                    if (_hasServerAccount)
                                      _infoRow(
                                        icon: LucideIcons.server,
                                        label:
                                            'settings_device_server_expiry'.tr,
                                        value: _formatServerExpiryDate(
                                          _serverExpiry,
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: AlignmentDirectional.centerStart,
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          9,
                                          10,
                                          9,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          color: Colors.white.withValues(
                                            alpha: 0.04,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.1,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 1,
                                              ),
                                              child: Icon(
                                                LucideIcons.hash,
                                                size: 14,
                                                color: kColorPrimary.withValues(
                                                  alpha: 0.9,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: (MediaQuery.sizeOf(
                                                              context,
                                                            ).width *
                                                            0.55)
                                                        .clamp(160.0, 320.0),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'device_id'.tr,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.55,
                                                          ),
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    _deviceId.isEmpty
                                                        ? '—'
                                                        : _deviceId,
                                                    maxLines: 3,
                                                    softWrap: true,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.96,
                                                          ),
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontFamily: 'monospace',
                                                      height: 1.25,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: copyChip),
                                const SizedBox(width: 8),
                                Expanded(child: closeChip),
                              ],
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// حوار مظهر الترجمة — مضغوط لشاشات الهاتف/Landscape بدون خروج عن الإطار.
class _SubtitleAppearanceDialog extends StatefulWidget {
  const _SubtitleAppearanceDialog({required this.initial});

  final SubtitleAppearance initial;

  @override
  State<_SubtitleAppearanceDialog> createState() =>
      _SubtitleAppearanceDialogState();
}

class _SubtitleAppearanceDialogState extends State<_SubtitleAppearanceDialog> {
  late SubtitleAppearance _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  bool _sameColor(Color a, Color b) => a.toARGB32() == b.toARGB32();

  Future<Color?> _pickFromPalette({
    required String title,
    required List<Color> colors,
    required Color selected,
    bool showAlpha = false,
  }) {
    return showDialog<Color>(
      context: context,
      barrierDismissible: true,
      // نفس الـ navigator ديال حوار الترجمة — ما يبقاش عالق فوق الـ Home.
      useRootNavigator: false,
      builder: (ctx) {
        return _SubtitlePalettePickerDialog(
          title: title,
          colors: colors,
          selected: selected,
          showAlpha: showAlpha,
        );
      },
    );
  }

  Widget _optionCard({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? swatch,
    bool dashed = false,
    double? tvOrder,
    bool autofocus = false,
  }) {
    final Color iconColor;
    if (swatch == null || dashed) {
      iconColor = Colors.white70;
    } else {
      iconColor =
          swatch.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    }

    Widget card = Builder(
      builder: (context) {
        final tv = isTv(context);
        return Focus(
          autofocus: autofocus && tv,
          descendantsAreFocusable: false,
          descendantsAreTraversable: false,
          onFocusChange: (_) {
            if (mounted) setState(() {});
          },
          onKeyEvent: tv
              ? (node, event) => settingsTvActivateOnSelect(event, onTap)
              : null,
          child: Builder(
            builder: (ctx) {
              final focused = settingsShowFocusDecor(
                ctx,
                Focus.of(ctx).hasFocus,
              );
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  canRequestFocus: false,
                  focusColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: focused
                          ? kColorPrimary.withValues(alpha: 0.18)
                          : selected
                              ? kColorPrimary.withValues(alpha: 0.14)
                              : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: focused || selected
                            ? kColorPrimary
                            : Colors.white24,
                        width: focused || selected ? 1.6 : 1,
                      ),
                      boxShadow: settingsThemedFocusGlow(focused),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: swatch ?? Colors.transparent,
                            border: Border.all(
                              color: Colors.white38,
                              width: dashed ? 1.2 : 1,
                            ),
                          ),
                          child: Icon(icon, size: 13, color: iconColor),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
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
        );
      },
    );

    if (tvOrder != null) {
      card = FocusTraversalOrder(
        order: NumericFocusOrder(tvOrder),
        child: card,
      );
    }
    return Expanded(child: card);
  }

  Widget _previewBox({required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _draft.backgroundEnabled
                ? _draft.backgroundColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(
              'settings_subtitle_appearance_preview'.tr,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _draft.fontColor,
                fontSize: _draft.fontSize.clamp(12, compact ? 22 : 28),
                fontWeight: FontWeight.w700,
                height: 1.2,
                shadows: const [
                  Shadow(
                    color: Colors.black87,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls({required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.a_large_small, size: 14, color: kColorPrimary),
            const SizedBox(width: 6),
            Text(
              'settings_subtitle_font_size'.tr,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
            const Spacer(),
            Text(
              '${_draft.fontSize.round()}',
              style: TextStyle(
                color: kColorPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
        FocusTraversalOrder(
          order: const NumericFocusOrder(1),
          child: Focus(
            autofocus: isTv(context),
            descendantsAreFocusable: false,
            descendantsAreTraversable: false,
            onFocusChange: (_) {
              if (mounted) setState(() {});
            },
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              final k = event.logicalKey;
              // يسار/يمين: الحجم. فوق/تحت: انتقل للاختيارات التالية.
              if (k == LogicalKeyboardKey.arrowDown ||
                  k == LogicalKeyboardKey.arrowUp) {
                if (k == LogicalKeyboardKey.arrowDown) {
                  node.nextFocus();
                } else {
                  node.previousFocus();
                }
                return KeyEventResult.handled;
              }
              if (k == LogicalKeyboardKey.arrowRight ||
                  k == LogicalKeyboardKey.arrowLeft) {
                final delta = k == LogicalKeyboardKey.arrowRight ? 1.0 : -1.0;
                final next = (_draft.fontSize + delta).clamp(
                  SubtitleAppearance.minFontSize,
                  SubtitleAppearance.maxFontSize,
                );
                if (next != _draft.fontSize) {
                  setState(() {
                    _draft = _draft.copyWith(fontSize: next);
                  });
                }
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (ctx) {
                final focused = settingsShowFocusDecor(
                  ctx,
                  Focus.of(ctx).hasFocus,
                );
                return SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: kColorPrimary,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: kColorPrimary,
                    overlayColor: kColorPrimary.withValues(alpha: 0.15),
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: focused ? kColorPrimary : Colors.transparent,
                        width: focused ? 1.5 : 0,
                      ),
                      color: focused
                          ? kColorPrimary.withValues(alpha: 0.08)
                          : Colors.transparent,
                    ),
                    child: SizedBox(
                      height: compact ? 28 : 36,
                      child: Slider(
                        min: SubtitleAppearance.minFontSize,
                        max: SubtitleAppearance.maxFontSize,
                        divisions: (SubtitleAppearance.maxFontSize -
                                SubtitleAppearance.minFontSize)
                            .round(),
                        value: _draft.fontSize,
                        onChanged: (v) => setState(() {
                          _draft = _draft.copyWith(fontSize: v);
                        }),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(height: compact ? 4 : 8),
        Text(
          'settings_subtitle_font_color'.tr,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _optionCard(
              icon: LucideIcons.type,
              label: 'settings_subtitle_color_white'.tr,
              selected: _sameColor(_draft.fontColor, Colors.white),
              swatch: Colors.white,
              tvOrder: 2,
              onTap: () => setState(() {
                _draft = _draft.copyWith(fontColor: Colors.white);
              }),
            ),
            const SizedBox(width: 8),
            _optionCard(
              icon: LucideIcons.palette,
              label: 'settings_subtitle_color_more'.tr,
              selected: !_sameColor(_draft.fontColor, Colors.white),
              swatch: _draft.fontColor,
              tvOrder: 3,
              onTap: () async {
                final picked = await _pickFromPalette(
                  title: 'settings_subtitle_font_color'.tr,
                  colors: SubtitleAppearance.fontColorPalette,
                  selected: _draft.fontColor,
                );
                if (picked == null || !mounted) return;
                setState(() {
                  _draft = _draft.copyWith(fontColor: picked);
                });
              },
            ),
          ],
        ),
        SizedBox(height: compact ? 8 : 12),
        Text(
          'settings_subtitle_background'.tr,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _optionCard(
              icon: LucideIcons.ban,
              label: 'settings_subtitle_bg_transparent'.tr,
              selected: !_draft.backgroundEnabled,
              dashed: true,
              tvOrder: 4,
              onTap: () => setState(() {
                _draft = _draft.copyWith(backgroundEnabled: false);
              }),
            ),
            const SizedBox(width: 8),
            _optionCard(
              icon: LucideIcons.palette,
              label: 'settings_subtitle_color_more'.tr,
              selected: _draft.backgroundEnabled,
              swatch: _draft.backgroundEnabled
                  ? _draft.backgroundColor.withValues(alpha: 1)
                  : const Color(0xFF455A64),
              tvOrder: 5,
              onTap: () async {
                final picked = await _pickFromPalette(
                  title: 'settings_subtitle_background'.tr,
                  colors: SubtitleAppearance.backgroundColorPalette,
                  selected: _draft.backgroundColor,
                  showAlpha: true,
                );
                if (picked == null || !mounted) return;
                setState(() {
                  _draft = _draft.copyWith(
                    backgroundEnabled: true,
                    backgroundColor: picked,
                  );
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final landscape = mq.width > mq.height;
    final maxW = landscape
        ? (mq.width * 0.72).clamp(380.0, 560.0)
        : (mq.width * 0.92).clamp(280.0, 400.0);
    final maxH = mq.height * (landscape ? 0.92 : 0.82);
    const padV = 16.0;
    const headerH = 36.0;
    const footerH = 48.0;
    final bodyMax =
        (maxH - padV - headerH - footerH).clamp(100.0, maxH);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: landscape ? 20 : 12,
        vertical: landscape ? 8 : 16,
      ),
      child: FocusScope(
        autofocus: true,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF222938), Color(0xFF12161F)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kColorPrimary.withValues(alpha: 0.28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: headerH,
                child: Row(
                  children: [
                    const _SettingsIconBadge(icon: LucideIcons.type),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'settings_subtitle_appearance_title'.tr,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: landscape ? 14.5 : 15.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: bodyMax),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: landscape
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: _previewBox(compact: true),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 6,
                              child: _controls(compact: true),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _previewBox(compact: true),
                            const SizedBox(height: 8),
                            _controls(compact: true),
                          ],
                        ),
                ),
              ),
              SizedBox(
                height: footerH,
                child: Row(
                  children: [
                    _subtitleFooterAction(
                      order: 6,
                      label: 'settings_subtitle_appearance_reset'.tr,
                      onPressed: () => setState(() {
                        _draft = SubtitleAppearance.defaults;
                      }),
                    ),
                    const Spacer(),
                    _subtitleFooterAction(
                      order: 7,
                      label: 'settings_refresh_dialog_cancel'.tr,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 6),
                    _subtitleFooterAction(
                      order: 8,
                      label: 'settings_subtitle_appearance_save'.tr,
                      filled: true,
                      onPressed: () => Navigator.of(context).pop(_draft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }

  Widget _subtitleFooterAction({
    required double order,
    required String label,
    required VoidCallback onPressed,
    bool filled = false,
  }) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: Focus(
        descendantsAreFocusable: false,
        descendantsAreTraversable: false,
        onFocusChange: (_) {
          if (mounted) setState(() {});
        },
        onKeyEvent: (node, event) =>
            settingsTvActivateOnSelect(event, onPressed),
        child: Builder(
          builder: (ctx) {
            final focused =
                settingsShowFocusDecor(ctx, Focus.of(ctx).hasFocus);
            return AnimatedScale(
              scale: focused ? kTvFocusScale(true, 1.1) : 1.0,
              duration: kFocusAnimDuration,
              curve: Curves.easeOut,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  canRequestFocus: false,
                  focusColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  customBorder: const StadiumBorder(),
                  onTap: onPressed,
                  child: AnimatedContainer(
                    duration: kFocusAnimDuration,
                    padding: EdgeInsets.symmetric(
                      horizontal: filled ? 16 : 12,
                      vertical: filled ? 10 : 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: filled
                          ? kColorPrimary
                          : (focused
                              ? kColorPrimary.withValues(alpha: 0.14)
                              : Colors.transparent),
                      border: Border.all(
                        color: focused
                            ? kColorPrimary
                            : (filled
                                ? kColorPrimary
                                : Colors.white.withValues(alpha: 0.22)),
                        width: focused ? 2.2 : 1,
                      ),
                      boxShadow: settingsThemedFocusGlow(focused),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: filled
                            ? Colors.black
                            : Colors.white.withValues(
                                alpha: focused ? 0.95 : 0.7,
                              ),
                        fontWeight: FontWeight.w800,
                        fontSize: filled ? 12.5 : 12,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// شبكة ألوان الترجمة — تركيز ظاهر على التلفاز، وFocusScope يمنع الهروب للـ Home.
class _SubtitlePalettePickerDialog extends StatefulWidget {
  const _SubtitlePalettePickerDialog({
    required this.title,
    required this.colors,
    required this.selected,
    required this.showAlpha,
  });

  final String title;
  final List<Color> colors;
  final Color selected;
  final bool showAlpha;

  @override
  State<_SubtitlePalettePickerDialog> createState() =>
      _SubtitlePalettePickerDialogState();
}

class _SubtitlePalettePickerDialogState
    extends State<_SubtitlePalettePickerDialog> {
  late final List<FocusNode> _nodes;
  late final FocusNode _closeNode;
  int _focusedIndex = 0;

  bool _sameColor(Color a, Color b) => a.toARGB32() == b.toARGB32();

  @override
  void initState() {
    super.initState();
    _nodes = List.generate(
      widget.colors.length,
      (i) => FocusNode(debugLabel: 'sub_palette_$i'),
    );
    _closeNode = FocusNode(debugLabel: 'sub_palette_close');
    final sel = widget.colors.indexWhere((c) => _sameColor(c, widget.selected));
    _focusedIndex = sel >= 0 ? sel : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_nodes.isEmpty) {
        _closeNode.requestFocus();
      } else {
        _nodes[_focusedIndex.clamp(0, _nodes.length - 1)].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    _closeNode.dispose();
    super.dispose();
  }

  KeyEventResult _onScopeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final maxH = mq.height * 0.7;
    final tv = isTv(context);

    return Dialog(
      backgroundColor: const Color(0xFF1A2030),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kColorPrimary.withValues(alpha: 0.28)),
      ),
      child: FocusScope(
        autofocus: true,
        onKeyEvent: _onScopeKey,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (mq.width * 0.85).clamp(260.0, 420.0),
              maxHeight: maxH,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.palette, color: kColorPrimary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      itemCount: widget.colors.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                      ),
                      itemBuilder: (_, i) {
                        final c = widget.colors[i];
                        final on = _sameColor(c, widget.selected);
                        return FocusTraversalOrder(
                          order: NumericFocusOrder(i.toDouble()),
                          child: Focus(
                            focusNode: _nodes[i],
                            descendantsAreFocusable: false,
                            descendantsAreTraversable: false,
                            onFocusChange: (v) {
                              if (v && _focusedIndex != i) {
                                setState(() => _focusedIndex = i);
                              } else if (mounted) {
                                setState(() {});
                              }
                            },
                            onKeyEvent: (node, event) =>
                                settingsTvActivateOnSelect(
                              event,
                              () => Navigator.of(context).pop(c),
                            ),
                            child: Builder(
                              builder: (ctx) {
                                final focused = settingsShowFocusDecor(
                                  ctx,
                                  Focus.of(ctx).hasFocus,
                                );
                                return AnimatedScale(
                                  scale: focused
                                      ? kTvFocusScale(true, 1.12)
                                      : 1.0,
                                  duration: kFocusAnimDuration,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      canRequestFocus: false,
                                      customBorder: const CircleBorder(),
                                      focusColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      onTap: () =>
                                          Navigator.of(context).pop(c),
                                      child: AnimatedContainer(
                                        duration: kFocusAnimDuration,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: widget.showAlpha
                                              ? const Color(0xFF2A3140)
                                              : c,
                                          border: Border.all(
                                            color: focused
                                                ? kColorPrimary
                                                : (on
                                                    ? kColorPrimary
                                                        .withValues(alpha: 0.85)
                                                    : Colors.white24),
                                            width: focused
                                                ? 3
                                                : (on ? 2.4 : 1),
                                          ),
                                          boxShadow: focused
                                              ? settingsThemedFocusGlow(true)
                                              : const [],
                                        ),
                                        child: widget.showAlpha
                                            ? Padding(
                                                padding:
                                                    const EdgeInsets.all(3),
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: c,
                                                  ),
                                                  child: on
                                                      ? Icon(
                                                          LucideIcons.check,
                                                          size: 12,
                                                          color: Colors.white,
                                                        )
                                                      : null,
                                                ),
                                              )
                                            : (on
                                                ? Icon(
                                                    LucideIcons.check,
                                                    size: 14,
                                                    color: c.computeLuminance() >
                                                            0.55
                                                        ? Colors.black
                                                        : Colors.white,
                                                  )
                                                : null),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  FocusTraversalOrder(
                    order: NumericFocusOrder(widget.colors.length.toDouble()),
                    child: Focus(
                      focusNode: _closeNode,
                      descendantsAreFocusable: false,
                      onFocusChange: (_) => setState(() {}),
                      onKeyEvent: (node, event) => settingsTvActivateOnSelect(
                        event,
                        () => Navigator.of(context).maybePop(),
                      ),
                      child: Builder(
                        builder: (ctx) {
                          final focused = settingsShowFocusDecor(
                            ctx,
                            Focus.of(ctx).hasFocus,
                          );
                          return AnimatedScale(
                            scale: focused ? kTvFocusScale(true, 1.1) : 1.0,
                            duration: kFocusAnimDuration,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(context).maybePop(),
                              style: TextButton.styleFrom(
                                side: BorderSide(
                                  color: focused
                                      ? kColorPrimary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                'settings_refresh_dialog_cancel'.tr,
                                style: TextStyle(
                                  color: Colors.white.withValues(
                                    alpha: focused ? 0.95 : 0.7,
                                  ),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (!tv) const SizedBox(height: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
