part of 'widgets.dart';

/// كlavier على الشاشة للتلفاز — زر تم/Done حسب لغة التطبيق.
class AppTvSideKeyboard extends StatefulWidget {
  const AppTvSideKeyboard({
    super.key,
    required this.seedFocus,
    required this.onChar,
    required this.onBackspace,
    required this.onPrimary,
    required this.onDismiss,
    this.showNext = false,
  });

  final FocusNode seedFocus;
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onPrimary;
  final VoidCallback onDismiss;
  final bool showNext;

  @override
  State<AppTvSideKeyboard> createState() => _AppTvSideKeyboardState();
}

class _AppTvSideKeyboardState extends State<AppTvSideKeyboard> {
  int _page = 0;
  bool _shift = false;

  static const _letterRows = <List<String>>[
    ['a', 'z', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['q', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'm'],
    ['w', 'x', 'c', 'v', 'b', 'n'],
  ];

  static const _symbolRows1 = <List<String>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['@', '#', r'$', '_', '&', '-', '+', '(', ')', '/'],
    ['*', '"', "'", ':', ';', '!', '?', '\\', '%', '='],
  ];

  static const _symbolRows2 = <List<String>>[
    ['~', '`', '|', '•', '√', 'π', '÷', '×', '¶', '∆'],
    ['£', '€', '¥', '¢', '^', '°', '=', '{', '}', '\\'],
    ['©', '®', '™', '✓', '[', ']', '<', '>', '«', '»'],
  ];

  List<List<String>> get _rows {
    switch (_page) {
      case 1:
        return _symbolRows1;
      case 2:
        return _symbolRows2;
      default:
        return _letterRows;
    }
  }

  String get _modeToggleLabel {
    switch (_page) {
      case 1:
        return r'=\<';
      case 2:
        return 'ABC';
      default:
        return '?123';
    }
  }

  void _cycleMode() {
    setState(() {
      if (_page == 0) {
        _page = 1;
      } else if (_page == 1) {
        _page = 2;
      } else {
        _page = 0;
      }
      _shift = false;
    });
  }

  Widget _key({
    required String label,
    required VoidCallback onTap,
    FocusNode? focusNode,
    int flex = 1,
    bool accent = false,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: Focus(
          focusNode: focusNode,
          // يخلي Live focus-safety يميّز أزرار الكلافيي على الشاشة.
          debugLabel: focusNode?.debugLabel ?? 'tv_search_kb_key',
          onKeyEvent: (node, event) {
            if (event is KeyUpEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack ||
                    event.logicalKey == LogicalKeyboardKey.browserBack)) {
              return KeyEventResult.handled;
            }
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter) {
              onTap();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.escape ||
                key == LogicalKeyboardKey.goBack ||
                key == LogicalKeyboardKey.browserBack) {
              widget.onDismiss();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              final bg = focused
                  ? kColorPrimary.withValues(alpha: 0.95)
                  : accent
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.07);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    alignment: Alignment.center,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: bg,
                      border: Border.all(
                        color: focused
                            ? kColorPrimary
                            : kColorPrimary.withValues(alpha: 0.35),
                        width: focused ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: focused ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: label.length > 3 ? 11 : 13,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final primaryLabel =
        widget.showNext ? 'tv_kb_next'.tr : 'tv_kb_done'.tr;
    return FocusScope(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF0E1118).withValues(alpha: 0.92),
          border: Border.all(
            color: kColorPrimary.withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows.length; r++)
                Row(
                  children: [
                    if (_page == 0 && r == 2)
                      _key(
                        label: '⇧',
                        accent: _shift,
                        onTap: () => setState(() => _shift = !_shift),
                      ),
                    for (var i = 0; i < rows[r].length; i++)
                      _key(
                        focusNode: r == 0 && i == 0 ? widget.seedFocus : null,
                        label: _page == 0 && _shift
                            ? rows[r][i].toUpperCase()
                            : rows[r][i],
                        onTap: () {
                          final ch = rows[r][i];
                          widget.onChar(
                            _page == 0 && _shift ? ch.toUpperCase() : ch,
                          );
                          if (_shift) setState(() => _shift = false);
                        },
                      ),
                    if (_page == 0 && r == 2)
                      _key(
                        label: '⌫',
                        accent: true,
                        onTap: widget.onBackspace,
                      ),
                  ],
                ),
              if (_page != 0)
                Row(
                  children: [
                    for (final ch in ['.', ',', '?', '!', "'", '"', '-', '@'])
                      _key(
                        label: ch,
                        onTap: () => widget.onChar(ch),
                      ),
                  ],
                ),
              Row(
                children: [
                  _key(
                    label: _modeToggleLabel,
                    accent: true,
                    flex: 2,
                    onTap: _cycleMode,
                  ),
                  if (_page != 0)
                    _key(
                      label: 'ABC',
                      accent: true,
                      flex: 2,
                      onTap: () => setState(() {
                        _page = 0;
                        _shift = false;
                      }),
                    ),
                  if (_page == 0)
                    _key(
                      label: ',',
                      onTap: () => widget.onChar(','),
                    ),
                  _key(
                    label: 'tv_kb_space'.tr,
                    flex: _page == 0 ? 5 : 4,
                    onTap: () => widget.onChar(' '),
                  ),
                  if (_page == 0)
                    _key(
                      label: '.',
                      onTap: () => widget.onChar('.'),
                    ),
                  if (_page != 0)
                    _key(
                      label: '⌫',
                      accent: true,
                      flex: 2,
                      onTap: widget.onBackspace,
                    ),
                  _key(
                    label: primaryLabel,
                    accent: true,
                    flex: 2,
                    onTap: widget.onPrimary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
