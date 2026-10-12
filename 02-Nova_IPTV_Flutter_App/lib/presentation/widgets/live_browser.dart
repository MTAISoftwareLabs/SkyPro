part of 'widgets.dart';

/// ارتفاع صف فئة/قناة في متصفح البث (شاشة Live + overlay المشغّل).
const double kLiveBrowserCatRowHeight = 36;
const double kLiveBrowserChRowHeight = 37;

/// فرق حجم التركيز على التلفاز (مركّز = 1.0، غير مركّز = 1/scale)
/// باش التكبير ما يقصّش الإطار ولا اللوغو.
const double kLiveBrowserTvFocusScale = 1.1;

/// ألوان المختار/النشط: [kLiveBrowserSelectedColor] في [colors.dart].
/// التركيز بالريموت: [kColorFocus].

/// تكبير داخل حدود الصف فقط — ما كيخرجش من الإطار.
Widget liveBrowserTvFocusScale({
  required BuildContext context,
  required bool zoom,
  required Widget child,
  bool animate = true,
}) {
  if (!isTvDevice(context)) return child;
  // أجهزة ضعيفة / Live overlay: بدون AnimatedScale — الإطار/اللون يكفي.
  if (kReduceFocusMotion || !animate) return child;
  final scale = zoom ? 1.0 : (1.0 / kLiveBrowserTvFocusScale);
  return ClipRect(
    child: AnimatedScale(
      scale: scale,
      duration: kFocusAnimDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      child: child,
    ),
  );
}

String liveBrowserQualityLabel(String? name) {
  final n = (name ?? '').toUpperCase();
  if (n.contains('4K') || n.contains('UHD')) return '4K';
  if (n.contains('FHD') || n.contains('1080')) return 'FHD';
  if (n.contains('HD') || n.contains('720')) return 'HD';
  return 'HD';
}

class LiveBrowserPanelShell extends StatelessWidget {
  const LiveBrowserPanelShell({
    super.key,
    required this.child,
    this.header,
  });

  final Widget child;
  final Widget? header;

  static const Color _panelColor = Color(0xFF141824);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _panelColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: kReduceFocusMotion
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null)
              Material(
                color: _panelColor,
                elevation: 0,
                child: header,
              ),
            Expanded(
              child: ClipRect(child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveBrowserCategoriesHeader extends StatelessWidget {
  const LiveBrowserCategoriesHeader({
    super.key,
    this.onBack,
    this.statusText,
    this.backFocusNode,
    this.onBackKeyEvent,
  });

  final VoidCallback? onBack;
  final String? statusText;
  final FocusNode? backFocusNode;
  final FocusOnKeyEventCallback? onBackKeyEvent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 14, 8),
      child: Row(
        children: [
          if (onBack != null)
            _LiveBrowserHeaderBackButton(
              focusNode: backFocusNode,
              onKeyEvent: onBackKeyEvent,
              onTap: onBack!,
            )
          else
            const SizedBox(width: 8),
          Image.asset(
            kIconLiveTv,
            width: 18,
            height: 18,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              (statusText != null && statusText!.trim().isNotEmpty)
                  ? statusText!
                  : 'live_servers'.tr.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Get.textTheme.labelLarge?.copyWith(
                color: statusText != null
                    ? kColorFocus
                    : Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
                letterSpacing: statusText != null ? 0.2 : 1.1,
                fontSize: statusText != null ? 11 : 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBrowserHeaderBackButton extends StatefulWidget {
  const _LiveBrowserHeaderBackButton({
    required this.onTap,
    this.focusNode,
    this.onKeyEvent,
  });

  final VoidCallback onTap;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<_LiveBrowserHeaderBackButton> createState() =>
      _LiveBrowserHeaderBackButtonState();
}

class _LiveBrowserHeaderBackButtonState
    extends State<_LiveBrowserHeaderBackButton> {
  bool _focused = false;

  bool _isOk(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (widget.onKeyEvent != null) {
          return widget.onKeyEvent!(node, event);
        }
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (_isOk(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (v) {
        if (_focused == v) return;
        setState(() => _focused = v);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(10),
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: _focused
                  ? kColorFocus
                  : Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

class LiveBrowserChannelPanelHeader extends StatelessWidget {
  const LiveBrowserChannelPanelHeader({
    super.key,
    required this.title,
    required this.count,
    this.onBack,
  });

  final String title;
  final int count;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 12, 8),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              focusColor: kColorFocus,
              onPressed: onBack,
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Get.textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: Get.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// شريط فئات كتالوج الأفلام/المسلسلات — نفس لوحة Live TV بدون ترويسة.
class CatalogCategoryPane extends StatelessWidget {
  const CatalogCategoryPane({
    super.key,
    required this.search,
    required this.list,
  });

  final Widget search;
  final Widget list;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: search,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: list,
          ),
        ),
      ],
    );
  }
}

const Duration _kCatalogCatCommitDelay = Duration(milliseconds: 110);
const Duration _kCatalogNavDebounce = Duration(milliseconds: 40);
const Duration _kCatalogCatReorderLongPress = Duration(milliseconds: 700);

class CatalogCategoryList extends StatefulWidget {
  const CatalogCategoryList({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.countOf,
    required this.onCommit,
    this.listFocusNode,
    this.onArrowUpFromFirst,
    this.countsListenable,
    this.pinnedCount = 0,
    this.enableReorder = false,
    this.onPersistOrder,
    this.reorderHintTitle,
  });

  final List<CategoryModel> categories;
  final String? selectedId;
  final int Function(String? id) countOf;
  final ValueChanged<CategoryModel> onCommit;
  final FocusNode? listFocusNode;
  final VoidCallback? onArrowUpFromFirst;
  final Listenable? countsListenable;

  /// عدد الصفوف المثبتة أعلى القائمة (All / Watched / Recently added).
  final int pinnedCount;

  /// تفعيل إعادة الترتيب (يُعطّل أثناء البحث).
  final bool enableReorder;

  /// يحفظ معرفات الفئات القابلة للسحب بالترتيب الجديد.
  final ValueChanged<List<String>>? onPersistOrder;

  /// عنوان توست الحفظ (اختياري).
  final String? reorderHintTitle;

  @override
  State<CatalogCategoryList> createState() => CatalogCategoryListState();
}

class CatalogCategoryListState extends State<CatalogCategoryList> {
  final ScrollController _scroll = ScrollController();
  List<FocusNode> _nodes = [];
  Timer? _commitTimer;
  DateTime? _lastNavAt;
  String? _pendingId;

  Timer? _reorderLongPressTimer;
  bool _reorderLongPressTriggered = false;
  bool _ignoreNextOkUp = false;
  int? _tvReorderIndex;
  List<String>? _tvReorderWorkingIds;

  bool get _isTvReordering =>
      _tvReorderIndex != null && _tvReorderWorkingIds != null;

  void _resyncNodes(int n) {
    if (_nodes.length == n) return;
    final old = _nodes;
    if (n > old.length) {
      _nodes = List<FocusNode>.generate(n, (i) {
        if (i < old.length) return old[i];
        final node = FocusNode(debugLabel: 'catalog_cat_$i');
        node.addListener(() => _onNodeFocused(i));
        return node;
      });
      return;
    }
    _nodes = n == 0 ? <FocusNode>[] : old.sublist(0, n);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (var i = n; i < old.length; i++) {
        try {
          old[i].dispose();
        } catch (_) {}
      }
    });
  }

  bool _navAllow() {
    final now = DateTime.now();
    if (_lastNavAt != null &&
        now.difference(_lastNavAt!) < _kCatalogNavDebounce) {
      return false;
    }
    _lastNavAt = now;
    return true;
  }

  bool _isOk(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space;
  }

  bool _isBack(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.goBack;
  }

  void _onNodeFocused(int index) {
    if (index < 0 || index >= _nodes.length || !_nodes[index].hasFocus) {
      return;
    }
    if (!mounted) return;
    final cats = _displayCategories;
    if (index >= cats.length) return;
    _scrollIndexIntoView(index, smooth: !kTvSnapFocusScroll);
    if (_isTvReordering) return;
    final id = cats[index].categoryId ?? '';
    if (id.isEmpty || id == (widget.selectedId ?? '')) {
      _cancelCommit();
      return;
    }
    _pendingId = id;
    _commitTimer?.cancel();
    _commitTimer = Timer(_kCatalogCatCommitDelay, () {
      if (!mounted) return;
      final pending = _pendingId;
      _pendingId = null;
      if (pending == null) return;
      final i = cats.indexWhere((c) => c.categoryId == pending);
      if (i < 0) return;
      widget.onCommit(cats[i]);
    });
  }

  void _cancelCommit() {
    _commitTimer?.cancel();
    _commitTimer = null;
    _pendingId = null;
  }

  void _flushCommit(CategoryModel cat) {
    _cancelCommit();
    widget.onCommit(cat);
  }

  List<CategoryModel> get _displayCategories {
    final working = _tvReorderWorkingIds;
    if (working == null) return widget.categories;
    final pinned = widget.pinnedCount;
    final head = widget.categories.take(pinned).toList();
    final byId = <String, CategoryModel>{};
    for (final c in widget.categories.skip(pinned)) {
      final id = (c.categoryId ?? '').trim();
      if (id.isEmpty) continue;
      byId.putIfAbsent(id, () => c);
    }
    final rest = <CategoryModel>[];
    final seen = <String>{};
    for (final id in working) {
      final c = byId[id];
      if (c != null && seen.add(id)) rest.add(c);
    }
    for (final c in widget.categories.skip(pinned)) {
      final id = (c.categoryId ?? '').trim();
      if (id.isEmpty) continue;
      if (seen.add(id)) rest.add(c);
    }
    return [...head, ...rest];
  }

  List<String> _reorderableIdsFrom(List<CategoryModel> display) {
    return display
        .skip(widget.pinnedCount)
        .map((c) => (c.categoryId ?? '').trim())
        .where((id) => id.isNotEmpty && !isCatalogPinnedCategory(id))
        .toList();
  }

  void _clearReorderTimers() {
    _reorderLongPressTimer?.cancel();
    _reorderLongPressTimer = null;
    _reorderLongPressTriggered = false;
  }

  void _beginTvReorder(int index) {
    if (!widget.enableReorder || _isTvReordering) return;
    if (index < widget.pinnedCount) return;
    final display = _displayCategories;
    if (index >= display.length) return;
    final id = (display[index].categoryId ?? '').trim();
    if (isCatalogPinnedCategory(id)) return;
    setState(() {
      _tvReorderWorkingIds = _reorderableIdsFrom(display);
      _tvReorderIndex = index;
    });
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  void _moveTvReorder(int delta) {
    final idx = _tvReorderIndex;
    final working = _tvReorderWorkingIds;
    if (idx == null || working == null || working.isEmpty) return;
    final next = idx + delta;
    if (next < widget.pinnedCount) {
      if (idx >= 0 && idx < _nodes.length) _nodes[idx].requestFocus();
      return;
    }
    final wi = idx - widget.pinnedCount;
    final wnext = next - widget.pinnedCount;
    if (wi < 0 || wi >= working.length) return;
    if (wnext < 0 || wnext >= working.length) {
      if (idx >= 0 && idx < _nodes.length) _nodes[idx].requestFocus();
      return;
    }
    final item = working.removeAt(wi);
    working.insert(wnext, item);
    setState(() => _tvReorderIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (next < _nodes.length) _nodes[next].requestFocus();
      _scrollIndexIntoView(next, smooth: !kTvSnapFocusScroll);
    });
  }

  void _commitTvReorder() {
    final working = _tvReorderWorkingIds;
    if (working == null) return;
    final keep = _tvReorderIndex;
    widget.onPersistOrder?.call(List<String>.from(working));
    setState(() {
      _tvReorderWorkingIds = null;
      _tvReorderIndex = null;
    });
    _ignoreNextOkUp = true;
    _clearReorderTimers();
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
    if (keep != null && keep < _nodes.length) {
      _nodes[keep].requestFocus();
    }
    if (mounted) {
      showSoftToast(
        context,
        widget.reorderHintTitle ?? 'live_cat_reorder_title'.tr,
        'live_cat_reorder_saved'.tr,
      );
    }
  }

  void _cancelTvReorder() {
    if (!_isTvReordering) return;
    setState(() {
      _tvReorderWorkingIds = null;
      _tvReorderIndex = null;
    });
    _clearReorderTimers();
  }

  void _onPhoneReorder(int oldIndex, int newIndex) {
    if (!widget.enableReorder) return;
    final pinned = widget.pinnedCount;
    if (oldIndex < pinned) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < pinned) newIndex = pinned;
    if (oldIndex == newIndex) return;
    final display = _displayCategories;
    if (oldIndex >= display.length) return;
    final ids = _reorderableIdsFrom(display);
    final from = oldIndex - pinned;
    if (from < 0 || from >= ids.length) return;
    final to = (newIndex - pinned).clamp(0, ids.length - 1);
    final item = ids.removeAt(from);
    ids.insert(to, item);
    widget.onPersistOrder?.call(ids);
  }

  void _scrollIndexIntoView(int index, {bool smooth = false}) {
    if (!_scroll.hasClients) return;
    final maxE = _scroll.position.maxScrollExtent;
    final o = (index * kLiveBrowserCatRowHeight - kLiveBrowserCatRowHeight * 2)
        .clamp(0.0, maxE);
    if (smooth && !kTvSnapFocusScroll) {
      unawaited(
        _scroll.animateTo(
          o,
          duration: kTvEnsureVisibleDuration,
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _scroll.jumpTo(o);
    }
  }

  void _jumpToStart() {
    void jump() {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.offset == 0) return;
      _scroll.jumpTo(0);
    }

    jump();
    WidgetsBinding.instance.addPostFrameCallback((_) => jump());
  }

  void focusFirst() {
    if (_nodes.isEmpty) {
      widget.listFocusNode?.requestFocus();
      return;
    }
    if (_nodes.first.canRequestFocus) {
      _nodes.first.requestFocus();
    }
  }

  /// يضع تركيز الريموت على الفئة المحددة (أو الأولى) — مهم للتلفاز.
  bool focusSelected() {
    final cats = _displayCategories;
    if (cats.isEmpty || _nodes.isEmpty) {
      focusFirst();
      return _nodes.isNotEmpty;
    }
    final selected = (widget.selectedId ?? '').trim();
    var i = 0;
    if (selected.isNotEmpty) {
      final found = cats.indexWhere((c) => (c.categoryId ?? '') == selected);
      if (found >= 0) i = found;
    }
    if (i >= _nodes.length) i = 0;
    final node = _nodes[i];
    if (!node.canRequestFocus) return false;
    node.requestFocus();
    _scrollIndexIntoView(i, smooth: false);
    return true;
  }

  void _onListFocus() {
    if (widget.listFocusNode?.hasFocus != true) return;
    focusSelected();
  }

  KeyEventResult _onItemKey(int index, KeyEvent event) {
    final key = event.logicalKey;
    final cats = _displayCategories;
    final n = cats.length;
    final tvLayout = isTvDevice(context);
    final canReorder = widget.enableReorder && widget.onPersistOrder != null;

    if (_isTvReordering) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (_isBack(key)) {
          if (event is KeyDownEvent) _cancelTvReorder();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (!_navAllow()) return KeyEventResult.handled;
          _moveTvReorder(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (!_navAllow()) return KeyEventResult.handled;
          _moveTvReorder(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled;
        }
        if (_isOk(key)) {
          if (event is KeyDownEvent) _commitTvReorder();
          return KeyEventResult.handled;
        }
      }
      if (event is KeyUpEvent && _isOk(key)) {
        _ignoreNextOkUp = false;
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (canReorder && tvLayout && _isOk(key)) {
      if (event is KeyDownEvent) {
        if (index >= widget.pinnedCount) {
          _reorderLongPressTimer?.cancel();
          _reorderLongPressTriggered = false;
          _reorderLongPressTimer = Timer(_kCatalogCatReorderLongPress, () {
            if (!mounted) return;
            _reorderLongPressTimer = null;
            _reorderLongPressTriggered = true;
            _beginTvReorder(index);
          });
          return KeyEventResult.handled;
        }
        if (index >= 0 && index < cats.length) {
          _flushCommit(cats[index]);
        }
        return KeyEventResult.handled;
      }
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (event is KeyUpEvent) {
        if (index < widget.pinnedCount) return KeyEventResult.handled;
        if (_ignoreNextOkUp) {
          _ignoreNextOkUp = false;
          return KeyEventResult.handled;
        }
        _reorderLongPressTimer?.cancel();
        _reorderLongPressTimer = null;
        final wasLong = _reorderLongPressTriggered;
        _reorderLongPressTriggered = false;
        if (wasLong) return KeyEventResult.handled;
        if (index >= 0 && index < cats.length) {
          _flushCommit(cats[index]);
        }
        return KeyEventResult.handled;
      }
    }

    if (_isOk(key)) {
      if (event is KeyDownEvent && index >= 0 && index < cats.length) {
        _flushCommit(cats[index]);
        return KeyEventResult.handled;
      }
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    if (!_navAllow()) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index < _nodes.length - 1 && index < n - 1) {
        _nodes[index + 1].requestFocus();
        _scrollIndexIntoView(index + 1, smooth: !kTvSnapFocusScroll);
      } else if (index >= 0 && index < _nodes.length) {
        // آخر فئة: ابقَ على نفس الصف — لا انتقال للشبكة.
        _nodes[index].requestFocus();
        _scrollIndexIntoView(index, smooth: !kTvSnapFocusScroll);
      }
      return KeyEventResult.handled;
    }
    if (index > 0) {
      _nodes[index - 1].requestFocus();
    } else {
      widget.onArrowUpFromFirst?.call();
    }
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    _resyncNodes(widget.categories.length);
    widget.listFocusNode?.addListener(_onListFocus);
  }

  @override
  void didUpdateWidget(CatalogCategoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listFocusNode != widget.listFocusNode) {
      oldWidget.listFocusNode?.removeListener(_onListFocus);
      widget.listFocusNode?.addListener(_onListFocus);
    }
    final oldIds = oldWidget.categories.map((c) => c.categoryId).join('|');
    final newIds = widget.categories.map((c) => c.categoryId).join('|');
    if (oldIds != newIds) {
      if (!_isTvReordering) {
        _resyncNodes(widget.categories.length);
        _jumpToStart();
      } else {
        _resyncNodes(_displayCategories.length);
      }
    }
  }

  @override
  void dispose() {
    _cancelCommit();
    _clearReorderTimers();
    widget.listFocusNode?.removeListener(_onListFocus);
    _scroll.dispose();
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _buildRow(int i, List<CategoryModel> cats, {required bool phoneDrag}) {
    if (i >= _nodes.length || i >= cats.length) {
      return const SizedBox.shrink();
    }
    final cat = cats[i];
    final id = cat.categoryId ?? '';
    final pinned = isCatalogPinnedCategory(id) || i < widget.pinnedCount;
    final node = _nodes[i];
    final showHandle =
        widget.enableReorder && widget.onPersistOrder != null && !pinned;
    Widget row = Focus(
      focusNode: node,
      onKeyEvent: (fn, ev) => _onItemKey(i, ev),
      child: ListenableBuilder(
        listenable: node,
        builder: (context, _) {
          return LiveBrowserCategoryRow(
            title: sanitizeDisplayTitle(cat.categoryName),
            count: widget.countOf(id),
            isFavorites: false,
            isRecentlyWatched: false,
            isActive: id == (widget.selectedId ?? ''),
            focused: node.hasFocus,
            isReorderTarget: _tvReorderIndex == i,
            showDragHandle: showHandle,
            showThumb: false,
            canItemFocus: false,
            flatOnPage: true,
            onTap: () {
              if (_isTvReordering) {
                if (_tvReorderIndex == i) _commitTvReorder();
                return;
              }
              _flushCommit(cat);
            },
          );
        },
      ),
    );
    if (phoneDrag && showHandle) {
      row = ReorderableDelayedDragStartListener(
        index: i,
        enabled: widget.enableReorder,
        child: row,
      );
    }
    return KeyedSubtree(
      key: ValueKey('catalog_cat_${id}_$i'),
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cats = _displayCategories;
    final n = cats.length;
    _resyncNodes(n);
    final tvLayout = isTvDevice(context);
    final canPhoneDrag =
        widget.enableReorder && widget.onPersistOrder != null && !tvLayout;

    Widget list() {
      if (canPhoneDrag) {
        return ReorderableListView.builder(
          scrollController: _scroll,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          cacheExtent: kListCacheExtent,
          itemExtent: kLiveBrowserCatRowHeight,
          itemCount: n,
          buildDefaultDragHandles: false,
          onReorder: _onPhoneReorder,
          onReorderStart: (_) {
            try {
              HapticFeedback.mediumImpact();
            } catch (_) {}
          },
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = Curves.easeOutCubic.transform(animation.value);
                return Material(
                  color: Colors.transparent,
                  elevation: 10 * t,
                  shadowColor: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(9),
                  child: Transform.scale(scale: 1 + 0.035 * t, child: child),
                );
              },
            );
          },
          itemBuilder: (_, i) => _buildRow(i, cats, phoneDrag: true),
        );
      }
      return ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        cacheExtent: kListCacheExtent,
        addAutomaticKeepAlives: false,
        addSemanticIndexes: false,
        itemExtent: kLiveBrowserCatRowHeight,
        itemCount: n,
        itemBuilder: (_, i) => _buildRow(i, cats, phoneDrag: false),
      );
    }

    final tick = widget.countsListenable;
    if (tick == null) return list();
    return ListenableBuilder(
      listenable: tick,
      builder: (context, _) => list(),
    );
  }
}

class LiveBrowserCategoryRow extends StatelessWidget {
  const LiveBrowserCategoryRow({
    super.key,
    required this.title,
    required this.count,
    required this.isFavorites,
    required this.isActive,
    required this.focused,
    required this.onTap,
    this.serverUrl,
    this.thumbUrl,
    this.isReorderTarget = false,
    this.showDragHandle = false,
    this.isRecentlyWatched = false,
    this.showThumb = true,
    this.canItemFocus = true,
    this.flatOnPage = false,
    this.animateFocusScale = true,
  });

  final String title;
  final int count;
  final bool isFavorites;
  final bool isRecentlyWatched;
  final bool isActive;
  final bool focused;
  final VoidCallback onTap;
  final String? serverUrl;
  final String? thumbUrl;
  final bool isReorderTarget;
  final bool showDragHandle;
  final bool showThumb;
  final bool canItemFocus;
  final bool flatOnPage;
  final bool animateFocusScale;

  @override
  Widget build(BuildContext context) {
    final tvZoom = isTvDevice(context) && focused;
    final fill = isReorderTarget
        ? kColorFocus.withValues(alpha: 0.22)
        : (focused
            ? kColorFocus.withValues(alpha: 0.14)
            : (isActive
                ? kLiveBrowserSelectedFill
                : (flatOnPage ? Colors.transparent : const Color(0xFF1C2130))));
    final borderColor = isReorderTarget
        ? kColorFocus
        : (focused
            ? kColorFocus
            : (isActive
                ? kLiveBrowserSelectedBorder
                : (flatOnPage
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.05))));
    final radius = BorderRadius.circular(flatOnPage ? 6 : 9);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: flatOnPage ? 1 : 2),
      child: liveBrowserTvFocusScale(
        context: context,
        zoom: tvZoom,
        animate: animateFocusScale,
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            canRequestFocus: canItemFocus,
            borderRadius: radius,
            focusColor: Colors.transparent,
            hoverColor: Colors.white.withValues(alpha: 0.04),
            child: Ink(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                border: Border.all(
                  color: borderColor,
                  width: isReorderTarget
                      ? 2
                      : (focused
                          ? 1.6
                          : (isActive ? 1.3 : (flatOnPage ? 0 : 1))),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Row(
                children: [
                  if (showThumb) ...[
                    LiveBrowserCategoryThumb(
                      title: title,
                      isFavorites: isFavorites,
                      isRecentlyWatched: isRecentlyWatched,
                      imageUrl:
                          thumbUrl != null
                              ? resolveImageUrl(thumbUrl, serverUrl)
                              : null,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: _CategoryMarqueeText(
                      // فقط الصف المركّز/إعادة الترتيب — لا ticker على الفئة النشطة أثناء تصفح القنوات.
                      animate: focused || isReorderTarget,
                      text: title,
                      style: Get.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: isActive || focused || isReorderTarget
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 12,
                          ) ??
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                  if (isReorderTarget) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.swap_vert_rounded,
                      size: 16,
                      color: kColorFocus,
                    ),
                  ] else if (showDragHandle) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.drag_handle_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ],
                  if (count > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isActive && !focused
                                ? kLiveBrowserSelectedColor.withValues(
                                    alpha: 0.22,
                                  )
                                : Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count',
                        style: Get.textTheme.labelSmall?.copyWith(
                          color:
                              isActive && !focused
                                  ? kLiveBrowserSelectedColor
                                  : Colors.white.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LiveBrowserCategoryThumb extends StatelessWidget {
  const LiveBrowserCategoryThumb({
    super.key,
    required this.title,
    required this.isFavorites,
    this.isRecentlyWatched = false,
    this.imageUrl,
  });

  final String title;
  final bool isFavorites;
  final bool isRecentlyWatched;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (isFavorites) {
      return Container(
        width: 28,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2418),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: const Color(0xFFFFC107).withValues(alpha: 0.35),
          ),
        ),
        alignment: Alignment.center,
        child: Image.asset(
          kIconFavourite,
          width: 13,
          height: 13,
          color: const Color(0xFFFFC107),
        ),
      );
    }

    if (isRecentlyWatched) {
      return Container(
        width: 28,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF1A2433),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: const Color(0xFF5BA8FF).withValues(alpha: 0.4),
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.history_rounded,
          size: 13,
          color: Color(0xFF5BA8FF),
        ),
      );
    }

    final hasImage =
        imageUrl != null &&
        imageUrl!.isNotEmpty &&
        imageUrl!.toLowerCase() != 'null';
    if (hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: 28,
          height: 22,
          color: const Color(0xFF252836),
          alignment: Alignment.center,
          child: Builder(
            builder: (context) {
              final mem = iptvMemCachePx(context, 28, 22);
              return CachedNetworkImage(
                imageUrl: imageUrl!,
                cacheManager: iptvImageCacheManager,
                memCacheWidth: mem.$1,
                memCacheHeight: mem.$2,
                width: 28,
                height: 22,
                fit: BoxFit.contain,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, _, _) => _letterThumb(title),
                placeholder: (_, _) => _letterThumb(title),
              );
            },
          ),
        ),
      );
    }

    return _letterThumb(title);
  }

  Widget _letterThumb(String title) {
    final letter =
        title.trim().isNotEmpty ? title.trim()[0].toUpperCase() : '?';
    final hue = (title.hashCode.abs() % 360).toDouble();
    return Container(
      width: 28,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: LinearGradient(
          colors: [
            HSLColor.fromAHSL(1, hue, 0.55, 0.42).toColor(),
            HSLColor.fromAHSL(1, hue, 0.45, 0.28).toColor(),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class LiveBrowserChannelRow extends StatelessWidget {
  const LiveBrowserChannelRow({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.quality,
    required this.isPlaying,
    required this.isFavorite,
    required this.focused,
    required this.onTap,
    this.flatList = false,
    this.animateFocusScale = true,
  });

  final String title;
  final String imageUrl;
  final String quality;
  final bool isPlaying;
  final bool isFavorite;
  final bool focused;
  final VoidCallback onTap;
  final bool flatList;
  final bool animateFocusScale;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.isNotEmpty && imageUrl.toLowerCase() != 'null';
    final tvZoom = isTvDevice(context) && focused;
    final radius = BorderRadius.circular(flatList ? 6 : 9);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: flatList ? 1 : 2),
      child: liveBrowserTvFocusScale(
        context: context,
        zoom: tvZoom,
        animate: animateFocusScale,
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            focusColor: Colors.transparent,
            hoverColor: Colors.white.withValues(alpha: 0.04),
            child: Ink(
              decoration: BoxDecoration(
                color: focused
                    ? kColorFocus.withValues(alpha: 0.14)
                    : (isPlaying
                        ? kLiveBrowserSelectedFill
                        : (flatList
                            ? Colors.transparent
                            : const Color(0xFF1C2130))),
                borderRadius: radius,
                border: Border.all(
                  color: focused
                      ? kColorFocus
                      : (isPlaying
                          ? kLiveBrowserSelectedBorder
                          : (flatList
                              ? Colors.transparent
                              : Colors.white.withValues(alpha: 0.05))),
                  width: isPlaying && !focused
                      ? 1.3
                      : (focused ? 1.6 : (flatList ? 0 : 1)),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      width: 30,
                      height: 22,
                      child:
                          hasImage
                              ? Builder(
                                builder: (context) {
                                  final mem = iptvMemCachePx(context, 30, 22);
                                  return CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    cacheManager: iptvImageCacheManager,
                                    memCacheWidth: mem.$1,
                                    memCacheHeight: mem.$2,
                                    fit: BoxFit.contain,
                                    fadeInDuration: Duration.zero,
                                    fadeOutDuration: Duration.zero,
                                    errorWidget:
                                        (_, _, _) =>
                                            const LiveBrowserChannelLogoFallback(),
                                    placeholder:
                                        (_, _) =>
                                            const LiveBrowserChannelLogoFallback(),
                                  );
                                },
                              )
                              : const LiveBrowserChannelLogoFallback(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Get.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight:
                            isPlaying || focused
                                ? FontWeight.w700
                                : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      quality,
                      style: Get.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                        fontSize: 9,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    isFavorite
                        ? FontAwesomeIcons.solidHeart
                        : FontAwesomeIcons.heart,
                    size: 12,
                    color:
                        isFavorite
                            ? kColorPrimary
                            : Colors.white.withValues(alpha: 0.35),
                  ),
                  if (isPlaying && !focused) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.play_arrow_rounded,
                      size: 16,
                      color: kLiveBrowserSelectedColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LiveBrowserChannelLogoFallback extends StatelessWidget {
  const LiveBrowserChannelLogoFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF252836),
      alignment: Alignment.center,
      child: Icon(
        Icons.live_tv_rounded,
        size: 14,
        color: Colors.white.withValues(alpha: 0.45),
      ),
    );
  }
}

/// اسم فئة طويل: كيتحرك من اليمين لليسار حتى يبان كامل فالخانة الصغيرة.
class _CategoryMarqueeText extends StatefulWidget {
  const _CategoryMarqueeText({
    required this.text,
    required this.style,
    this.animate = false,
  });

  final String text;
  final TextStyle style;
  final bool animate;

  @override
  State<_CategoryMarqueeText> createState() => _CategoryMarqueeTextState();
}

class _CategoryMarqueeTextState extends State<_CategoryMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _textWidth = 0;
  double _boxWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _CategoryMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.animate != widget.animate) {
      _textWidth = 0;
      _sync();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted || _boxWidth <= 0) return;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    _textWidth = painter.width;
    final overflow = _textWidth - _boxWidth;
    if (!widget.animate || overflow <= 8) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0;
      return;
    }
    // ~40px/s، مع وقفة فالبداية والنهاية.
    final travelMs = (overflow / 40 * 1000).round().clamp(1600, 7000);
    _controller.duration = Duration(milliseconds: travelMs + 1800);
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.maxWidth;
        if (box.isFinite && (box - _boxWidth).abs() > 1) {
          _boxWidth = box;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(_sync);
          });
        }
        final overflow = _textWidth - _boxWidth;
        if (!widget.animate || _textWidth <= 0 || overflow <= 8) {
          return Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              // 0–0.18 وقفة على البداية، ثم انزلاق لليسار، ثم وقفة على الآخر.
              double dx = 0;
              if (t < 0.18) {
                dx = 0;
              } else if (t < 0.82) {
                final p = (t - 0.18) / 0.64;
                dx = -overflow * Curves.easeInOut.transform(p);
              } else {
                dx = -overflow;
              }
              return Transform.translate(
                offset: Offset(dx, 0),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 0,
                  maxWidth: _textWidth,
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    softWrap: false,
                    style: widget.style,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
