part of 'screens.dart';

const double _kHomePosterRadius = 14.0;

/// بادئة تسميات فوكس Home على التلفزيون (مطابقة سلوك Smart TV).
const String _kStvTopPrefix = 'stv_top_';
const String _kStvPosterPrefix = 'stv_poster_';

/// ربط FocusNode ← تسمية حتى مع FocusNode خارجي (autofocus).
final Map<FocusNode, String> _stvFocusLabels = <FocusNode, String>{};

void _stvBindFocusLabel(FocusNode? node, String? label) {
  if (node == null) return;
  final t = (label ?? '').trim();
  if (t.isEmpty) {
    _stvFocusLabels.remove(node);
  } else {
    _stvFocusLabels[node] = t;
  }
}

String? _stvLabelOf(FocusNode node) =>
    _stvFocusLabels[node] ?? node.debugLabel;

String _stvTopLabel(String id) => '$_kStvTopPrefix$id';
String _stvPosterLabel(int row, int col) => '$_kStvPosterPrefix${row}_$col';

(int row, int col)? _stvParsePosterLabel(String? label) {
  if (label == null || !label.startsWith(_kStvPosterPrefix)) return null;
  final rest = label.substring(_kStvPosterPrefix.length);
  final parts = rest.split('_');
  if (parts.length != 2) return null;
  final row = int.tryParse(parts[0]);
  final col = int.tryParse(parts[1]);
  if (row == null || col == null) return null;
  return (row, col);
}

bool _stvIsTopBarLabel(String? label) =>
    label != null && label.startsWith(_kStvTopPrefix);

/// التبويب النشط في شلّ التلفزيون (للرجوع ↑ إلى نفس التبويب).
SmartTvShellTab _stvActiveShellTab = SmartTvShellTab.home;

void _stvSetActiveShellTab(SmartTvShellTab tab) {
  _stvActiveShellTab = tab;
}

FocusNode? _stvFindTopTabNode(SmartTvShellTab tab) {
  final id = switch (tab) {
    SmartTvShellTab.home => 'home',
    SmartTvShellTab.live => 'live',
    SmartTvShellTab.movies => 'movies',
    SmartTvShellTab.series => 'series',
    SmartTvShellTab.favourites => 'fav',
  };
  final want = _stvTopLabel(id);
  FocusNode? fallback;
  FocusNode? onCurrentRoute;
  for (final e in _stvFocusLabels.entries) {
    if (e.value != want) continue;
    final n = e.key;
    if (!n.canRequestFocus || n.context == null) continue;
    // آخر تطابق = أحدث بناء (شريط Live فوق Welcome).
    fallback = n;
    try {
      final route = ModalRoute.of(n.context!);
      if (route != null && route.isCurrent) {
        onCurrentRoute = n;
      }
    } catch (_) {}
  }
  return onCurrentRoute ?? fallback;
}

bool _stvFocusShellTab(SmartTvShellTab tab) {
  final n = _stvFindTopTabNode(tab);
  if (n == null) return false;
  if (n.canRequestFocus && n.context != null) {
    n.requestFocus();
  }
  if (!n.hasFocus) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (n.canRequestFocus && n.context != null) n.requestFocus();
    });
  }
  return true;
}

KeyEventResult _homeRowHorizontalKey(
  FocusNode node,
  KeyEvent event, {
  required bool isFirstInRow,
  required bool isLastInRow,
  required VoidCallback onActivate,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final key = event.logicalKey;
  final isArrow =
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowUp;

  // KeyRepeat أثناء ensureVisible يعطي إحداثيات متقلّبة → قفزات عشوائية.
  if (isArrow && event is KeyRepeatEvent) {
    final last = _homeFocusNavAt;
    if (last != null &&
        DateTime.now().difference(last) < _kHomeFocusNavMinInterval) {
      return KeyEventResult.handled;
    }
  }

  if (key == LogicalKeyboardKey.arrowRight) {
    if (isLastInRow) return KeyEventResult.handled;
    final next = _homePickHorizontalNeighbor(node, toRight: true);
    if (next != null) {
      _homeFocusNavAt = DateTime.now();
      next.requestFocus();
    }
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    if (isFirstInRow) return KeyEventResult.handled;
    final next = _homePickHorizontalNeighbor(node, toRight: false);
    if (next != null) {
      _homeFocusNavAt = DateTime.now();
      next.requestFocus();
    }
    return KeyEventResult.handled;
  }

  if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
    final last = _homeFocusNavAt;
    if (event is KeyRepeatEvent &&
        last != null &&
        DateTime.now().difference(last) < _kHomeFocusNavMinInterval) {
      return KeyEventResult.handled;
    }
    final next = _homePickVerticalNeighbor(
      node,
      down: key == LogicalKeyboardKey.arrowDown,
    );
    if (next != null) {
      _homeFocusNavAt = DateTime.now();
      next.requestFocus();
    }
    // نستهلك الحدث دائماً حتى لا تختار خوارزمية Flutter عنصراً خاطئاً (RTL).
    return KeyEventResult.handled;
  }

  return settingsTvActivateOnSelect(event, onActivate);
}

DateTime? _homeFocusNavAt;

/// فاصل KeyRepeat — أقصر على TV/lite باش الأسهم تحس فورية عند الضغط المستمر.
Duration get _kHomeFocusNavMinInterval {
  if (AppPerf.instance.isLite || AppPerf.instance.isTelevisionLike) {
    return const Duration(milliseconds: 55);
  }
  return const Duration(milliseconds: 110);
}

/// أقرب عنصر في نفس الصف يمين/يسار حسب المحور الأفقي الفيزيائي.
FocusNode? _homePickHorizontalNeighbor(
  FocusNode from, {
  required bool toRight,
}) {
  // تلفزيون + تسميات Smart TV: تنقّل صريح داخل الصف / الشريط.
  if (AppPerf.instance.isTelevisionLike) {
    final smart = _homePickHorizontalNeighborSmartTv(from, toRight: toRight);
    if (smart != null ||
        _stvParsePosterLabel(_stvLabelOf(from)) != null ||
        _stvIsTopBarLabel(_stvLabelOf(from))) {
      return smart;
    }
  }

  final scope = from.nearestScope;
  if (scope == null) return null;

  Rect? fromRect;
  try {
    fromRect = from.rect;
  } catch (_) {
    return null;
  }
  if (fromRect.isEmpty) return null;

  // نفس الصف تقريباً — أعلى على التلفزيون لأن البوسترات أكبر.
  final maxRowDy = AppPerf.instance.isTelevisionLike ? 120.0 : 48.0;
  const minStepDx = 6.0;

  FocusNode? best;
  var bestDx = double.infinity;
  var bestDy = double.infinity;

  for (final n in scope.traversalDescendants) {
    if (identical(n, from) || !n.canRequestFocus || n.skipTraversal) continue;
    Rect r;
    try {
      r = n.rect;
    } catch (_) {
      continue;
    }
    if (r.isEmpty) continue;
    final dy = (r.center.dy - fromRect.center.dy).abs();
    if (dy > maxRowDy) continue;
    final dx = r.center.dx - fromRect.center.dx;
    if (toRight && dx < minStepDx) continue;
    if (!toRight && dx > -minStepDx) continue;
    final adx = dx.abs();
    if (adx < bestDx - 0.5 || (adx - bestDx).abs() <= 0.5 && dy < bestDy) {
      best = n;
      bestDx = adx;
      bestDy = dy;
    }
  }
  return best;
}

FocusNode? _homePickHorizontalNeighborSmartTv(
  FocusNode from, {
  required bool toRight,
}) {
  final label = _stvLabelOf(from);

  final fromPoster = _stvParsePosterLabel(label);
  if (fromPoster != null) {
    final row = fromPoster.$1;
    final col = fromPoster.$2;
    final targetCol = toRight ? col + 1 : col - 1;
    if (targetCol < 0) return null;
    // البحث أولاً في الملصقات المسجلة مباشرة لتجنب مسح شجرة FocusNode كاملة
    for (final entry in _stvFocusLabels.entries) {
      final n = entry.key;
      if (!n.canRequestFocus || n.skipTraversal || n.context == null) continue;
      final p = _stvParsePosterLabel(entry.value);
      if (p != null && p.$1 == row && p.$2 == targetCol) return n;
    }
    final scope = from.nearestScope;
    if (scope != null) {
      for (final n in scope.traversalDescendants) {
        if (!n.canRequestFocus || n.skipTraversal) continue;
        final p = _stvParsePosterLabel(_stvLabelOf(n));
        if (p != null && p.$1 == row && p.$2 == targetCol) return n;
      }
    }
    return null; // حافة الصف — نبقى هنا مثل Smart TV
  }

  if (_stvIsTopBarLabel(label)) {
    // تنقل فوري داخل شريط التلفاز والأدوات بدون مسح مئات العناصر أو حساب Rects ثقيلة
    const topBarOrder = <String>[
      'home',
      'live',
      'movies',
      'series',
      'fav',
      'search',
      'profile',
      'notifications',
      'settings',
    ];

    String? currentId;
    for (final id in topBarOrder) {
      if (label == _stvTopLabel(id)) {
        currentId = id;
        break;
      }
    }

    final activeTopNodes = <String, FocusNode>{};
    for (final entry in _stvFocusLabels.entries) {
      final n = entry.key;
      if (!n.canRequestFocus || n.skipTraversal || n.context == null) continue;
      final l = entry.value;
      if (_stvIsTopBarLabel(l)) {
        activeTopNodes[l] = n;
      }
    }

    if (currentId != null) {
      final curIdx = topBarOrder.indexOf(currentId);
      if (toRight) {
        for (int i = curIdx + 1; i < topBarOrder.length; i++) {
          final targetNode = activeTopNodes[_stvTopLabel(topBarOrder[i])];
          if (targetNode != null && !identical(targetNode, from)) {
            return targetNode;
          }
        }
      } else {
        for (int i = curIdx - 1; i >= 0; i--) {
          final targetNode = activeTopNodes[_stvTopLabel(topBarOrder[i])];
          if (targetNode != null && !identical(targetNode, from)) {
            return targetNode;
          }
        }
      }
    }

    // احتياطي هندسي بين عناصر الشريط العلوي النشطة فقط (بدون أي مسح لبقية الشاشة)
    Rect? fromRect;
    try {
      fromRect = from.rect;
    } catch (_) {
      return null;
    }
    if (fromRect.isEmpty) return null;

    final tops = <({FocusNode node, double dx})>[];
    for (final n in activeTopNodes.values) {
      if (identical(n, from)) continue;
      Rect r;
      try {
        r = n.rect;
      } catch (_) {
        continue;
      }
      if (r.isEmpty) continue;
      tops.add((node: n, dx: r.center.dx - fromRect.center.dx));
    }
    final candidates = tops.where((e) {
      return toRight ? e.dx > 6 : e.dx < -6;
    }).toList()
      ..sort((a, b) => a.dx.abs().compareTo(b.dx.abs()));
    return candidates.isEmpty ? null : candidates.first.node;
  }

  return null;
}

/// يختار أقرب عنصر في الصف التالي/السابق حسب المحور العمودي ثم الأقرب أفقياً.
FocusNode? _homePickVerticalNeighbor(FocusNode from, {required bool down}) {
  if (AppPerf.instance.isTelevisionLike) {
    final smart = _homePickVerticalNeighborSmartTv(from, down: down);
    if (smart != null ||
        _stvParsePosterLabel(_stvLabelOf(from)) != null ||
        _stvIsTopBarLabel(_stvLabelOf(from))) {
      return smart;
    }
  }
  return _homePickVerticalNeighborGeometric(from, down: down);
}

/// سلوك Smart TV: الحفاظ على رقم العمود بين الصفوف؛ أعلى من الصف 0 → تبويب Home.
FocusNode? _homePickVerticalNeighborSmartTv(
  FocusNode from, {
  required bool down,
}) {
  final scope = from.nearestScope;
  if (scope == null) return null;

  final posters = <({FocusNode node, int row, int col})>[];
  FocusNode? homeTab;
  final topBar = <FocusNode>[];

  // استخدام الكاش المسجل في _stvFocusLabels أولاً
  for (final entry in _stvFocusLabels.entries) {
    final n = entry.key;
    if (!n.canRequestFocus || n.skipTraversal || n.context == null) continue;
    final l = entry.value;
    final p = _stvParsePosterLabel(l);
    if (p != null) {
      posters.add((node: n, row: p.$1, col: p.$2));
      continue;
    }
    if (_stvIsTopBarLabel(l)) {
      topBar.add(n);
      if (l == _stvTopLabel('home')) homeTab = n;
    }
  }

  if (posters.isEmpty && topBar.isEmpty) {
    for (final n in scope.traversalDescendants) {
      if (!n.canRequestFocus || n.skipTraversal) continue;
      final l = _stvLabelOf(n);
      final p = _stvParsePosterLabel(l);
      if (p != null) {
        posters.add((node: n, row: p.$1, col: p.$2));
        continue;
      }
      if (_stvIsTopBarLabel(l)) {
        topBar.add(n);
        if (l == _stvTopLabel('home')) homeTab = n;
      }
    }
  }

  final fromPoster = _stvParsePosterLabel(_stvLabelOf(from));
  if (fromPoster != null) {
    final row = fromPoster.$1;
    final col = fromPoster.$2;
    if (down) {
      final nextRows = posters
          .where((p) => p.row > row)
          .map((p) => p.row)
          .toSet()
          .toList()
        ..sort();
      if (nextRows.isEmpty) return null;
      final targetRow = nextRows.first;
      final inRow = posters.where((p) => p.row == targetRow).toList()
        ..sort((a, b) => a.col.compareTo(b.col));
      if (inRow.isEmpty) return null;
      return inRow[math.min(col, inRow.length - 1)].node;
    }

    final prevRows = posters
        .where((p) => p.row < row)
        .map((p) => p.row)
        .toSet()
        .toList()
      ..sort();
    if (prevRows.isEmpty) {
      // ↑ من المحتوى → نفس تبويب القسم النشط (Movies/Live/…)
      return _stvFindTopTabNode(_stvActiveShellTab) ??
          homeTab ??
          (topBar.isNotEmpty ? topBar.first : null);
    }
    final targetRow = prevRows.last;
    final inRow = posters.where((p) => p.row == targetRow).toList()
      ..sort((a, b) => a.col.compareTo(b.col));
    if (inRow.isEmpty) return null;
    return inRow[math.min(col, inRow.length - 1)].node;
  }

  if (_stvIsTopBarLabel(_stvLabelOf(from))) {
    if (!down) return null; // ↑ من الشريط: لا شيء
    // ↓ يدخل المحتوى — أول بوستر مثل enterHomeContent
    if (posters.isEmpty) return null;
    posters.sort((a, b) {
      final byRow = a.row.compareTo(b.row);
      if (byRow != 0) return byRow;
      return a.col.compareTo(b.col);
    });
    return posters.first.node;
  }

  return null;
}

FocusNode? _homePickVerticalNeighborGeometric(
  FocusNode from, {
  required bool down,
}) {
  final scope = from.nearestScope;
  if (scope == null) return null;

  Rect? fromRect;
  try {
    fromRect = from.rect;
  } catch (_) {
    return null;
  }
  if (fromRect.isEmpty) return null;

  // عناصر نفس الصف تقريباً — نتجاهلها عند التنقل العمودي.
  final minBandPx = AppPerf.instance.isTelevisionLike ? 56.0 : 40.0;
  // عناصر في نفس الصف التالي إن تقاربت مسافاتها العمودية.
  final bandTolerancePx = AppPerf.instance.isTelevisionLike ? 140.0 : 72.0;

  final candidates = <({FocusNode node, double dy, double dx})>[];
  for (final n in scope.traversalDescendants) {
    if (identical(n, from) || !n.canRequestFocus || n.skipTraversal) continue;
    Rect r;
    try {
      r = n.rect;
    } catch (_) {
      continue;
    }
    if (r.isEmpty) continue;
    final dy = r.center.dy - fromRect.center.dy;
    if (down && dy < minBandPx) continue;
    if (!down && dy > -minBandPx) continue;
    candidates.add((
      node: n,
      dy: dy.abs(),
      dx: (r.center.dx - fromRect.center.dx).abs(),
    ));
  }
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final byDy = a.dy.compareTo(b.dy);
    if (byDy != 0) return byDy;
    return a.dx.compareTo(b.dx);
  });

  final nearestBand = candidates.first.dy;
  ({FocusNode node, double dy, double dx})? best;
  for (final c in candidates) {
    if (c.dy > nearestBand + bandTolerancePx) break;
    if (best == null || c.dx < best.dx) best = c;
  }
  return best?.node;
}
