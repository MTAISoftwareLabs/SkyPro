part of 'widgets.dart';

/// بحث فئات الشريط الجانبي.
/// الهاتف: TextField عادي. التلفاز: تركيز فقط، ثم OK يفتح كlavier على الشاشة مع تم/Done.
class CategorySidebarSearchField extends StatefulWidget {
  const CategorySidebarSearchField({
    super.key,
    required this.onChanged,
    this.onBecameEmpty,
    this.navFocusNode,
    this.editFocusNode,
    this.onNavArrowDown,
    this.onNavArrowUp,
    this.onEditDismissed,
    this.onTvKeyboardOpenChanged,
    this.compact = false,
  });

  final ValueChanged<String> onChanged;
  final VoidCallback? onBecameEmpty;
  final FocusNode? navFocusNode;
  /// اختياري: نفس الـ FocusNode من الأب (Live TV) حتى لا يُسرق التركيز.
  final FocusNode? editFocusNode;
  final VoidCallback? onNavArrowDown;
  final VoidCallback? onNavArrowUp;
  final VoidCallback? onEditDismissed;
  /// التلفاز: الكlavier الظاهر فوق المشغّل — حتى لا يُسرق التركيز.
  final ValueChanged<bool>? onTvKeyboardOpenChanged;
  /// Live TV: ارتفاع أقل (~نصف)، العرض كما هو.
  final bool compact;

  @override
  State<CategorySidebarSearchField> createState() =>
      _CategorySidebarSearchFieldState();
}

class _CategorySidebarSearchFieldState
    extends State<CategorySidebarSearchField> {
  late final FocusNode _navFocus;
  late final FocusNode _editFocus;
  final FocusNode _tvKbSeedFocus = FocusNode(debugLabel: 'tv_search_kb_seed');
  final TextEditingController _controller = TextEditingController();
  OverlayEntry? _tvKbOverlay;
  bool _tvKbOpen = false;
  bool get _ownsNavFocus => widget.navFocusNode == null;
  bool get _ownsEditFocus => widget.editFocusNode == null;

  @override
  void initState() {
    super.initState();
    _navFocus = widget.navFocusNode ??
        FocusNode(debugLabel: 'category_search_nav');
    _editFocus = widget.editFocusNode ??
        FocusNode(debugLabel: 'category_search_edit');
    _navFocus.addListener(_rebuildFocus);
    _editFocus.addListener(_onEditFocusChanged);
    _navFocus.onKeyEvent = _onNavKey;
    _editFocus.onKeyEvent = _onEditKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // التلفاز: TextField لا يأخذ التركيز حتى لا يفتح كlavier النظام.
      _editFocus.canRequestFocus = !isTv(context);
    });
  }

  @override
  void dispose() {
    _removeTvKeyboard(restoreNav: false);
    _navFocus.removeListener(_rebuildFocus);
    _editFocus.removeListener(_onEditFocusChanged);
    if (_ownsNavFocus) _navFocus.dispose();
    if (_ownsEditFocus) _editFocus.dispose();
    _tvKbSeedFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _rebuildFocus() {
    if (mounted) setState(() {});
  }

  void _hideIme() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _onEditFocusChanged() {
    if (!mounted) return;
    if (isTv(context)) {
      if (_editFocus.hasFocus) {
        _editFocus.unfocus();
        _hideIme();
        if (_navFocus.canRequestFocus) _navFocus.requestFocus();
      }
      return;
    }
    setState(() {});
  }

  void _emitQuery() {
    final value = _controller.text.trim().toLowerCase();
    widget.onChanged(value);
    if (value.isEmpty && !_tvKbOpen) {
      widget.onBecameEmpty?.call();
    }
  }

  void _insertChar(String ch) {
    final t = _controller.text;
    _controller.value = TextEditingValue(
      text: '$t$ch',
      selection: TextSelection.collapsed(offset: t.length + ch.length),
    );
    _emitQuery();
    if (mounted) setState(() {});
  }

  void _backspace() {
    final t = _controller.text;
    if (t.isEmpty) return;
    _controller.value = TextEditingValue(
      text: t.substring(0, t.length - 1),
      selection: TextSelection.collapsed(offset: t.length - 1),
    );
    _emitQuery();
    if (mounted) setState(() {});
  }

  void _removeTvKeyboard({required bool restoreNav}) {
    final wasOpen = _tvKbOpen;
    _tvKbOverlay?.remove();
    _tvKbOverlay = null;
    _tvKbOpen = false;
    if (wasOpen) widget.onTvKeyboardOpenChanged?.call(false);
    _hideIme();
    if (!restoreNav || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_navFocus.canRequestFocus) _navFocus.requestFocus();
    });
  }

  void _openTvKeyboard() {
    if (!isTv(context) || _tvKbOpen) return;
    _hideIme();
    _editFocus.canRequestFocus = false;
    if (_editFocus.hasFocus) _editFocus.unfocus();
    _tvKbOpen = true;
    widget.onTvKeyboardOpenChanged?.call(true);
    _tvKbOverlay = OverlayEntry(
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Positioned(
          left: 16,
          right: 16,
          bottom: bottom + 12,
          child: Material(
            color: Colors.transparent,
            child: AppTvSideKeyboard(
              seedFocus: _tvKbSeedFocus,
              onChar: _insertChar,
              onBackspace: _backspace,
              onPrimary: () {
                widget.onEditDismissed?.call();
                _removeTvKeyboard(restoreNav: true);
              },
              onDismiss: () => _removeTvKeyboard(restoreNav: true),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_tvKbOverlay!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tvKbOpen) return;
      if (_tvKbSeedFocus.canRequestFocus) {
        _tvKbSeedFocus.requestFocus();
      }
    });
  }

  KeyEventResult _onNavKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!isTv(context)) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.numpadEnter) {
      _openTvKeyboard();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_tvKbOpen) return KeyEventResult.handled;
      widget.onNavArrowDown?.call();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_tvKbOpen) return KeyEventResult.handled;
      if (widget.onNavArrowUp != null) {
        widget.onNavArrowUp!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onEditKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (isTv(context)) {
      _hideIme();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleChanged(String raw) {
    final value = raw.trim().toLowerCase();
    widget.onChanged(value);
    if (value.isEmpty && !_tvKbOpen) {
      widget.onBecameEmpty?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final compact = widget.compact;
    final vPad = compact ? 5.0 : 10.0;
    final fontSize = compact ? 13.0 : 14.0;
    final focused = tv && (_navFocus.hasFocus || _tvKbOpen);
    final phoneFocused = !tv && _editFocus.hasFocus;
    final query = _controller.text;

    final Widget inner;
    if (tv) {
      inner = Text(
        query.isEmpty ? 'search_in_categories'.tr : query,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: query.isEmpty ? Colors.white54 : Colors.white,
          fontSize: compact ? 12.0 : 13.0,
        ),
      );
    } else {
      inner = TextField(
        controller: _controller,
        focusNode: _editFocus,
        textInputAction: TextInputAction.done,
        onChanged: _handleChanged,
        onSubmitted: (_) => _hideIme(),
        style: TextStyle(color: Colors.white, fontSize: fontSize),
        cursorColor: kColorPrimary,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'search_in_categories'.tr,
          hintStyle: TextStyle(
            color: Colors.white54,
            fontSize: compact ? 12.0 : 13.0,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
        ),
      );
    }

    final box = RepaintBoundary(
      child: AnimatedContainer(
        duration: kFocusAnimDuration,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (focused || phoneFocused)
                ? kColorFocus
                : Colors.white.withValues(alpha: 0.10),
            width: 2,
          ),
          boxShadow: kTvFocusGlow(
            focused: focused || phoneFocused,
            blur: 10,
            spread: 0.5,
            alpha: 0.45,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: vPad),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
          ),
          child: inner,
        ),
      ),
    );

    if (!tv) return box;

    return Focus(
      focusNode: _navFocus,
      onKeyEvent: _onNavKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openTvKeyboard,
        child: box,
      ),
    );
  }
}
