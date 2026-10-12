part of 'widgets.dart';

/// شريط فرز يظهر فقط فوق شبكة فئة «الكل».
class AllCatalogSortBar extends StatelessWidget {
  const AllCatalogSortBar({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AllCatalogSort value;
  final ValueChanged<AllCatalogSort> onChanged;

  static ThemeData _menuTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      menuButtonTheme: const MenuButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStatePropertyAll(Colors.transparent),
          backgroundColor: WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = box.size;
    final screen = overlay.size;

    // أبقِ القائمة تحت الزر مع هامش واضح عن حافة الشاشة اليمنى/اليسرى.
    const menuWidth = 280.0;
    const edgePad = 24.0;
    var left = topLeft.dx;
    if (left + menuWidth > screen.width - edgePad) {
      left = screen.width - edgePad - menuWidth;
    }
    if (left < edgePad) left = edgePad;
    final top = topLeft.dy + size.height + 8;
    final right = screen.width - left - menuWidth;
    final bottom = screen.height - top;

    final selected = await showMenu<AllCatalogSort>(
      context: context,
      position: RelativeRect.fromLTRB(left, top, right, bottom),
      color: const Color(0xFF1E293B),
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      constraints: const BoxConstraints(
        minWidth: menuWidth,
        maxWidth: menuWidth,
      ),
      initialValue: value,
      items: [
        for (final option in AllCatalogSort.values)
          PopupMenuItem<AllCatalogSort>(
            value: option,
            padding: EdgeInsets.zero,
            child: _SortMenuRow(
              option: option,
              selected: option == value,
              // initialValue لا يضع Focus للريموت — نفرضه على العنصر الحالي.
              requestInitialFocus: option == value,
            ),
          ),
      ],
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8, end: 24),
        // ثيم بلا تظليل داخلي يُلتقط مع showMenu لعناصر القائمة.
        child: Theme(
          data: _menuTheme(context),
          child: Focus(
            canRequestFocus: false,
            descendantsAreFocusable: true,
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return AnimatedContainer(
                  duration: kFocusAnimDuration,
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: focused ? kColorFocus : Colors.transparent,
                      width: focused ? 2 : 0,
                    ),
                    boxShadow: kTvFocusGlow(
                      focused: focused,
                      blur: 10,
                      spread: 0.5,
                      alpha: 0.45,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openMenu(context),
                      borderRadius: BorderRadius.circular(12),
                      focusColor: Colors.transparent,
                      hoverColor: Colors.white.withValues(alpha: 0.04),
                      child: Container(
                        height: 42,
                        constraints: const BoxConstraints(
                          minWidth: 220,
                          maxWidth: 340,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.07),
                              Colors.white.withValues(alpha: 0.03),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: kColorPrimary.withValues(alpha: 0.18),
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                size: 15,
                                color: kColorPrimary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'all_sort_label'.tr,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                value.labelKey.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// صف عنصر قائمة الفرز — تركيز بهالة خارجية فقط دون تظليل داخلي.
class _SortMenuRow extends StatefulWidget {
  const _SortMenuRow({
    required this.option,
    required this.selected,
    this.requestInitialFocus = false,
  });

  final AllCatalogSort option;
  final bool selected;
  final bool requestInitialFocus;

  @override
  State<_SortMenuRow> createState() => _SortMenuRowState();
}

class _SortMenuRowState extends State<_SortMenuRow> {
  @override
  void initState() {
    super.initState();
    if (!widget.requestInitialFocus) return;
    // إطاران: انتظار اكتمال Route القائمة ثم تركيز عنصر InkWell للأب.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final node = Focus.maybeOf(context);
        if (node != null && node.canRequestFocus) {
          node.requestFocus();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FocusManager.instance,
      builder: (context, _) {
        final focused = Focus.of(context).hasFocus;
        return AnimatedContainer(
          duration: kFocusAnimDuration,
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color:
                widget.selected && !focused
                    ? kColorPrimary.withValues(alpha: 0.10)
                    : Colors.transparent,
            border: Border.all(
              color:
                  focused
                      ? kColorFocus
                      : widget.selected
                      ? kColorPrimary.withValues(alpha: 0.45)
                      : Colors.transparent,
              width: focused ? 2 : 1,
            ),
            boxShadow: kTvFocusGlow(
              focused: focused,
              blur: 10,
              alpha: 0.45,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.option.icon,
                size: 16,
                color: widget.selected ? kColorPrimary : Colors.white70,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.option.labelKey.tr,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight:
                        widget.selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (widget.selected)
                Icon(Icons.check_rounded, size: 16, color: kColorPrimary),
            ],
          ),
        );
      },
    );
  }
}
