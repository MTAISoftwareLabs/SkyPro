import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import '../../helpers/helpers.dart';
import '../../logic/cubits/prefetch/prefetch_cubit.dart';
import '../../services/subtitle/opensubtitles_debug_log.dart';
import '../../services/subtitle/subtitle_error_formatter.dart';
import '../../services/subtitle/subtitle_models.dart';
import '../../services/subtitle/subtitle_service.dart';

const Color _kPanel = Color(0xFF16161E);
const Color _kPanelElevated = Color(0xFF1E1E28);
const Color _kLine = Color(0xFF2C2C38);

KeyEventResult _tvActivate(KeyEvent event, VoidCallback onTap) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final k = event.logicalKey;
  if (k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.space ||
      k == LogicalKeyboardKey.numpadEnter) {
    onTap();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

Color get _focusColor => kColorFocus;

/// Halo only (border + soft glow) — never fills / tints the tile interior.
BoxDecoration _focusHalo({
  required bool focused,
  BorderRadius? borderRadius,
  Color? color,
  Color unfocusedBorder = Colors.transparent,
  double unfocusedBorderWidth = 0,
}) {
  final radius = borderRadius ?? BorderRadius.circular(12);
  return BoxDecoration(
    color: color,
    borderRadius: radius,
    border: Border.all(
      color: focused ? _focusColor : unfocusedBorder,
      width: focused ? 2.2 : unfocusedBorderWidth,
    ),
    boxShadow: focused
        ? [
            BoxShadow(
              color: _focusColor.withValues(alpha: 0.5),
              blurRadius: 14,
              spreadRadius: 0.4,
            ),
          ]
        : null,
  );
}

/// Kill Material/InkWell internal focus wash — TV remote shows halo only.
ButtonStyle get _tvIconButtonStyle => IconButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white70,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    );

/// Rebuilds on focus change so the theme halo actually appears on TV remotes.
class _TvFocus extends StatefulWidget {
  const _TvFocus({
    required this.builder,
    this.onActivated,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.scrollIntoView = false,
    this.focusNode,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onActivated;
  final bool autofocus;
  final bool canRequestFocus;
  final bool scrollIntoView;
  final FocusNode? focusNode;

  @override
  State<_TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<_TvFocus> {
  FocusNode? _ownedNode;
  late FocusNode _node;
  bool _didAutofocus = false;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ??
        (_ownedNode = FocusNode(canRequestFocus: widget.canRequestFocus));
    _node.canRequestFocus = widget.canRequestFocus;
    _node.addListener(_onFocus);
    _scheduleAutofocus();
  }

  @override
  void didUpdateWidget(covariant _TvFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _node.removeListener(_onFocus);
      _ownedNode?.dispose();
      _ownedNode = null;
      _node = widget.focusNode ??
          (_ownedNode = FocusNode(canRequestFocus: widget.canRequestFocus));
      _node.addListener(_onFocus);
    }
    _node.canRequestFocus = widget.canRequestFocus;
    if (widget.autofocus && !_didAutofocus) {
      _scheduleAutofocus();
    }
  }

  void _scheduleAutofocus() {
    if (!widget.autofocus || _didAutofocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didAutofocus) return;
      if (!isTvDevice(context)) return;
      if (!_node.canRequestFocus) return;
      _didAutofocus = true;
      if (!_node.hasFocus) _node.requestFocus();
    });
  }

  void _onFocus() {
    if (!mounted) return;
    setState(() {});
    if (!_node.hasFocus || !widget.scrollIntoView) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_node.hasFocus) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.35,
        duration: Duration.zero,
        curve: Curves.linear,
      );
    });
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _ownedNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phones: no remote focus / halo — plain tappable content only.
    if (!isTvDevice(context)) {
      return widget.builder(context, false);
    }
    return Focus(
      focusNode: _node,
      autofocus: false,
      canRequestFocus: widget.canRequestFocus,
      onKeyEvent: widget.onActivated == null
          ? null
          : (node, event) => _tvActivate(event, widget.onActivated!),
      child: widget.builder(context, _node.hasFocus),
    );
  }
}

/// Locks TV focus inside subtitle dialogs so D-pad never leaks to the player.
class _SubtitleFocusTrap extends StatefulWidget {
  const _SubtitleFocusTrap({required this.child, this.debugLabel});

  final Widget child;
  final String? debugLabel;

  @override
  State<_SubtitleFocusTrap> createState() => _SubtitleFocusTrapState();
}

class _SubtitleFocusTrapState extends State<_SubtitleFocusTrap> {
  late final FocusScopeNode _scope = FocusScopeNode(
    debugLabel: widget.debugLabel ?? 'subtitle_focus_trap',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  FocusNode? _lastInside;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_guardFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && isTvDevice(context)) _ensureFocusInside();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_guardFocus);
    _scope.dispose();
    super.dispose();
  }

  bool _isInside(FocusNode? node) {
    if (node == null) return false;
    if (node == _scope) return true;
    return node.enclosingScope == _scope;
  }

  void _guardFocus() {
    if (!mounted || _restoring) return;
    if (!isTvDevice(context)) return;
    // Don't steal focus from a sheet/dialog opened on top of this trap.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final primary = FocusManager.instance.primaryFocus;
    if (_isInside(primary)) {
      if (primary != _scope) _lastInside = primary;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _restoring) return;
      final routeNow = ModalRoute.of(context);
      if (routeNow != null && !routeNow.isCurrent) return;
      if (_isInside(FocusManager.instance.primaryFocus)) return;
      _ensureFocusInside();
    });
  }

  void _ensureFocusInside() {
    if (!mounted) return;
    _restoring = true;
    try {
      final last = _lastInside;
      if (last != null &&
          last.canRequestFocus &&
          !last.skipTraversal &&
          last.context != null &&
          _isInside(last)) {
        last.requestFocus();
        return;
      }
      FocusNode? first;
      for (final n in _scope.traversalDescendants) {
        if (!n.canRequestFocus || n.skipTraversal) continue;
        if (n.context == null) continue;
        first = n;
        break;
      }
      if (first != null) {
        first.requestFocus();
      } else {
        _scope.requestFocus();
      }
    } finally {
      _restoring = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice(context)) {
      return widget.child;
    }
    return FocusScope(
      node: _scope,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
              ),
            ),
            listTileTheme: const ListTileThemeData(
              selectedTileColor: Colors.transparent,
              tileColor: Colors.transparent,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class SubtitleDownloadSelection {
  const SubtitleDownloadSelection({
    required this.item,
    required this.localPath,
  });

  final SubtitleResultItem item;
  final String localPath;
}

/// Orchestrates form → loading → results as **separate root routes**.
/// Never stacks results under the form (that hung / hid results in the recording).
class SubtitleSearchSheet {
  SubtitleSearchSheet._();

  static Future<SubtitleDownloadSelection?> show({
    required BuildContext context,
    required SubtitleContentContext contextData,
    VoidCallback? onTurnOff,
  }) async {
    final tv = isTv(context) || isAndroidTv(context);

    while (context.mounted) {
      final form = await _openForm(
        context: context,
        contextData: contextData,
        asDialog: tv,
      );

      if (!context.mounted) return null;
      if (form == null) return null;
      if (form.turnOff) {
        onTurnOff?.call();
        return null;
      }

      final query = form.query;
      if (query == null) return null;

      // Let the form route finish closing.
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!context.mounted) return null;

      // 1) Await search on the PLAYER context (result cannot be lost).
      // 2) Then open a FRESH results route that already has the list.
      final loader = _BusyOverlay.insert(
        context,
        message: 'subtitle_searching'.tr,
      );
      List<SubtitleResultItem> results = const [];
      String? error;
      try {
        results = await SubtitleService.instance.searchSubtitles(query);
      } on SubtitleSearchException catch (e) {
        error = e.messageKey.tr;
      } catch (e, st) {
        OpenSubtitlesDebugLog.logGenericError(e, st);
        error = SubtitleErrorFormatter.format(e);
      } finally {
        loader.remove();
      }

      if (!context.mounted) return null;

      if (error != null || results.isEmpty) {
        final retry = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            backgroundColor: _kPanel,
            content: Text(
              error ?? 'subtitle_not_found'.tr,
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('OK', style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'subtitle_search_title'.tr,
                  style: TextStyle(color: _focusColor),
                ),
              ),
            ],
          ),
        );
        if (retry != true || !context.mounted) return null;
        continue;
      }

      SubtitleService.instance.warmUpAuth();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!context.mounted) return null;

      // Keep offering the same result list until user backs out or download succeeds.
      while (context.mounted) {
        final item = await _openResults(
          context: context,
          results: List<SubtitleResultItem>.from(results),
          contentTitle: contextData.title,
          asDialog: tv,
        );

        if (!context.mounted) return null;
        if (item == null) break; // back → form again

        // Same pattern as search: close list first, download on player context.
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (!context.mounted) return null;

        // Busy UI as a Dialog (Overlay over video often never clears visually).
        String? path;
        String? dlError;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black54,
          useRootNavigator: true,
          builder: (dialogCtx) {
            Future<void> run() async {
              try {
                path = await SubtitleService.instance
                    .downloadSubtitleFile(item)
                    .timeout(
                      const Duration(seconds: 28),
                      onTimeout: () => null,
                    );
                if ((path ?? '').isEmpty) {
                  dlError =
                      SubtitleErrorFormatter.downloadFailureMessage();
                }
              } catch (e, st) {
                OpenSubtitlesDebugLog.logGenericError(e, st);
                dlError = SubtitleErrorFormatter.format(e);
              } finally {
                if (dialogCtx.mounted) {
                  Navigator.of(dialogCtx).pop();
                }
              }
            }

            unawaited(run());
            return PopScope(
              canPop: false,
              child: Dialog(
                backgroundColor: _kPanel,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: _focusColor,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'subtitle_downloading'.tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ).timeout(
          const Duration(seconds: 32),
          onTimeout: () {
            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).maybePop();
            }
            dlError ??= SubtitleErrorFormatter.downloadFailureMessage();
            return null;
          },
        );

        if (!context.mounted) return null;

        final downloadedPath = path;
        if (downloadedPath == null || downloadedPath.isEmpty) {
          final retry = await showDialog<bool>(
            context: context,
            barrierDismissible: true,
            useRootNavigator: true,
            builder: (ctx) => AlertDialog(
              backgroundColor: _kPanel,
              content: Text(
                dlError ?? SubtitleErrorFormatter.downloadFailureMessage(),
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child:
                      const Text('OK', style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(
                    'subtitle_search_results'.tr,
                    style: TextStyle(color: _focusColor),
                  ),
                ),
              ],
            ),
          );
          if (retry == true && context.mounted) continue; // show list again
          return null;
        }

        return SubtitleDownloadSelection(
          item: item,
          localPath: downloadedPath,
        );
      }
    }
    return null;
  }

  static Future<_FormResult?> _openForm({
    required BuildContext context,
    required SubtitleContentContext contextData,
    required bool asDialog,
  }) {
    if (asDialog) {
      return showDialog<_FormResult>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (_) => _SubtitleFormPage(
          contextData: contextData,
          asDialog: true,
        ),
      );
    }
    return showModalBottomSheet<_FormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      useRootNavigator: true,
      builder: (_) => _SubtitleFormPage(
        contextData: contextData,
        asDialog: false,
      ),
    );
  }

  static Future<SubtitleResultItem?> _openResults({
    required BuildContext context,
    required List<SubtitleResultItem> results,
    required String contentTitle,
    required bool asDialog,
  }) {
    if (asDialog) {
      return showDialog<SubtitleResultItem>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        useRootNavigator: true,
        builder: (_) => _SubtitleResultsHost(
          results: results,
          contentTitle: contentTitle,
          asDialog: true,
        ),
      );
    }
    return showModalBottomSheet<SubtitleResultItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      useRootNavigator: true,
      builder: (_) => _SubtitleResultsHost(
        results: results,
        contentTitle: contentTitle,
        asDialog: false,
      ),
    );
  }
}

/// Temporary spinner — work Future is owned by [SubtitleSearchSheet.show].
class _BusyOverlay {
  _BusyOverlay._(this._entry);

  final OverlayEntry _entry;

  static _BusyOverlay insert(
    BuildContext context, {
    required String message,
  }) {
    final entry = OverlayEntry(
      builder: (ctx) => Material(
        color: Colors.black54,
        child: SafeArea(
          child: Center(
            child: Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              decoration: BoxDecoration(
                color: _kPanel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _kLine),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: _focusColor,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    return _BusyOverlay._(entry);
  }

  void remove() {
    try {
      _entry.remove();
    } catch (_) {}
  }
}

class _FormResult {
  const _FormResult.query(this.query) : turnOff = false;
  const _FormResult.turnOff()
      : query = null,
        turnOff = true;

  final SubtitleSearchQuery? query;
  final bool turnOff;
}

/* ───────────────────────── Form ───────────────────────── */

class _SubtitleFormPage extends StatefulWidget {
  const _SubtitleFormPage({
    required this.contextData,
    required this.asDialog,
  });

  final SubtitleContentContext contextData;
  final bool asDialog;

  @override
  State<_SubtitleFormPage> createState() => _SubtitleFormPageState();
}

class _SubtitleFormPageState extends State<_SubtitleFormPage> {
  static List<MapEntry<String, String>> get _languages =>
      SubtitleService.supportedUiLanguages;

  late String _languageCode;
  SubtitleSearchBy _searchBy = SubtitleSearchBy.imdbId;
  late final TextEditingController _queryController;
  /// Code field is editable on tap, but never takes TV remote focus.
  late final FocusNode _queryFocusNode = FocusNode(
    skipTraversal: true,
    canRequestFocus: !widget.asDialog,
  );
  final FocusNode _langChipFocusNode = FocusNode(debugLabel: 'lang_chip');

  String? _resolvedTmdbId;
  String? _resolvedImdbId;
  bool _resolvingMeta = false;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _languageCode = SubtitleService.instance.defaultLanguageCode;
    _resolvedTmdbId = widget.contextData.tmdbId;
    SubtitleService.instance.warmUpAuth();

    final existingImdb = widget.contextData.imdbId?.trim();
    if (existingImdb != null && existingImdb.isNotEmpty) {
      _resolvedImdbId = existingImdb.toLowerCase().startsWith('tt')
          ? existingImdb.substring(2)
          : existingImdb;
    } else if (_resolvedTmdbId != null) {
      _resolvedImdbId = SubtitleService.instance.peekCachedImdbId(
        tmdbId: _resolvedTmdbId,
        isSeries: widget.contextData.isSeries,
      );
    }

    final initial = (_resolvedImdbId != null && _resolvedImdbId!.isNotEmpty)
        ? 'tt$_resolvedImdbId'
        : '';
    _queryController = TextEditingController(text: initial);
    unawaited(_warmMeta());
  }

  @override
  void dispose() {
    _queryFocusNode.dispose();
    _langChipFocusNode.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _warmMeta() async {
    if (_resolvedImdbId != null && _resolvedImdbId!.isNotEmpty) return;
    if (_resolvingMeta) return;
    _resolvingMeta = true;
    if (mounted) setState(() {});

    try {
      if (_resolvedTmdbId == null || _resolvedTmdbId!.isEmpty) {
        final parts = widget.contextData.contentKey.split(':');
        if (parts.length == 2) {
          try {
            if (parts[0] == 'movie') {
              final detail = await context
                  .read<PrefetchCubit>()
                  .getMovieDetailCached(parts[1])
                  .timeout(const Duration(seconds: 4));
              _resolvedTmdbId = detail?.info?.tmdbId;
            } else if (parts[0] == 'series') {
              final detail = await context
                  .read<PrefetchCubit>()
                  .getSerieDetailCached(parts[1])
                  .timeout(const Duration(seconds: 4));
              _resolvedTmdbId = detail?.info?.tmdbId;
            }
          } catch (_) {}
        }
      }

      if (_resolvedTmdbId == null || _resolvedTmdbId!.isEmpty) {
        try {
          _resolvedTmdbId = await SubtitleService.instance.resolveTmdbId(
            contentKey: widget.contextData.contentKey,
            title: widget.contextData.title,
            isSeries: widget.contextData.isSeries,
            year: widget.contextData.year,
            existingTmdbId: widget.contextData.tmdbId,
          );
        } catch (_) {}
      }

      final imdb = await SubtitleService.instance.resolveImdbId(
        tmdbId: _resolvedTmdbId ?? widget.contextData.tmdbId,
        isSeries: widget.contextData.isSeries,
      );
      if (!mounted) return;
      if (imdb != null && imdb.isNotEmpty) {
        _resolvedImdbId = imdb;
        if (_searchBy == SubtitleSearchBy.imdbId &&
            _queryController.text.trim().isEmpty) {
          _queryController.text = 'tt$imdb';
        }
      }
    } finally {
      _resolvingMeta = false;
      if (mounted) setState(() {});
    }
  }

  void _submitSearch() {
    final queryText = _queryController.text.trim();
    final hasTitle = widget.contextData.title.trim().isNotEmpty;
    final hasFile = widget.contextData.fileName?.trim().isNotEmpty == true;
    if (queryText.isEmpty &&
        _resolvedImdbId == null &&
        _resolvedTmdbId == null &&
        !hasTitle &&
        !hasFile) {
      setState(() => _banner = 'subtitle_imdb_required'.tr);
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');

    String? imdb = _resolvedImdbId;
    String? tmdb = _resolvedTmdbId ?? widget.contextData.tmdbId;
    if (_searchBy == SubtitleSearchBy.imdbId && queryText.isNotEmpty) {
      imdb = queryText;
    } else if (_searchBy == SubtitleSearchBy.tmdbId && queryText.isNotEmpty) {
      tmdb = queryText;
    }

    Navigator.of(context).pop(
      _FormResult.query(
        SubtitleSearchQuery(
          searchBy: _searchBy,
          query: queryText,
          languageCode: _languageCode,
          isSeries: widget.contextData.isSeries,
          season: widget.contextData.season,
          episode: widget.contextData.episode,
          tmdbId: tmdb,
          imdbId: imdb,
          title: widget.contextData.title,
          year: widget.contextData.year,
          fileName: widget.contextData.fileName,
        ),
      ),
    );
  }

  Future<void> _pickLanguage() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: _kPanelElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: _SubtitleFocusTrap(
            debugLabel: 'subtitle_languages',
            child: ListView(
              shrinkWrap: true,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'subtitle_language'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...List.generate(_languages.length, (i) {
                  final e = _languages[i];
                  final selected = e.key == _languageCode;
                  final selectedIndex =
                      _languages.indexWhere((x) => x.key == _languageCode);
                  return FocusTraversalOrder(
                    order: NumericFocusOrder(i.toDouble()),
                    child: Padding(
                      key: ValueKey('lang-${e.key}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: _TvFocus(
                        autofocus:
                            i == (selectedIndex >= 0 ? selectedIndex : 0),
                        scrollIntoView: true,
                        onActivated: () => Navigator.of(ctx).pop(e.key),
                        builder: (context, focused) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            decoration: _focusHalo(
                              focused: focused,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              focusColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                              selectedTileColor: Colors.transparent,
                              title: Text(
                                e.value,
                                style: TextStyle(
                                  color: selected ? _focusColor : Colors.white,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              trailing: selected
                                  ? Icon(Icons.check_rounded,
                                      color: _focusColor)
                                  : null,
                              onTap: () => Navigator.of(ctx).pop(e.key),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (picked != null) {
      await SubtitleService.instance.setDefaultLanguageCode(picked);
      if (!mounted) return;
      setState(() => _languageCode = picked);
    }
    // Restore focus on the language chip (last control the user activated).
    _restoreLangChipFocus();
  }

  void _restoreLangChipFocus() {
    if (!isTvDevice(context)) return;
    void request() {
      if (!mounted) return;
      if (_langChipFocusNode.canRequestFocus) {
        _langChipFocusNode.requestFocus();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      request();
      // Second frame: sheet route teardown can steal focus once more.
      WidgetsBinding.instance.addPostFrameCallback((_) => request());
    });
  }

  String _languageLabel() {
    for (final e in _languages) {
      if (e.key == _languageCode) return e.value;
    }
    return _languageCode.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxH = media.size.height * (widget.asDialog ? 0.72 : 0.78);

    final panel = Material(
      color: _kPanel,
      borderRadius: widget.asDialog
          ? BorderRadius.circular(22)
          : const BorderRadius.vertical(top: Radius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: widget.asDialog ? 560 : double.infinity,
        height: maxH,
        child: SafeArea(
          top: false,
          child: _SubtitleFocusTrap(
            debugLabel: 'subtitle_form',
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.asDialog)
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                )
              else
                const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(0),
                      child: _FocusIconButton(
                        tooltip: 'Close',
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'subtitle_search_title'.tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: _TurnOffChip(
                        onPressed: () => Navigator.of(context)
                            .pop(const _FormResult.turnOff()),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: _SegmentedMode(
                            value: _searchBy,
                            enabled: true,
                            onChanged: (mode) {
                              setState(() {
                                _searchBy = mode;
                                if (mode == SubtitleSearchBy.imdbId) {
                                  _queryController.text =
                                      (_resolvedImdbId != null &&
                                              _resolvedImdbId!.isNotEmpty)
                                          ? 'tt$_resolvedImdbId'
                                          : '';
                                  if (_queryController.text.isEmpty) {
                                    unawaited(_warmMeta());
                                  }
                                } else {
                                  _queryController.text = _resolvedTmdbId ?? '';
                                  if (_queryController.text.isEmpty) {
                                    unawaited(_warmMeta());
                                  }
                                }
                              });
                            },
                            labelOf: (m) => m == SubtitleSearchBy.imdbId
                                ? 'IMDb'
                                : 'TMDB',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(4),
                            child: _LangChip(
                              label: _languageLabel(),
                              enabled: true,
                              focusNode: _langChipFocusNode,
                              onTap: _pickLanguage,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: _kPanelElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _kLine),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _queryController,
                              focusNode: _queryFocusNode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _submitSearch(),
                              decoration: InputDecoration(
                                hintText: _searchBy == SubtitleSearchBy.imdbId
                                    ? 'tt0000000'
                                    : 'TMDB id',
                                hintStyle: const TextStyle(
                                  color: Colors.white30,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                suffixIcon: _resolvingMeta
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FocusTraversalOrder(
                              order: const NumericFocusOrder(5),
                              child: _TvFocus(
                                autofocus: true,
                                onActivated: _submitSearch,
                                builder: (context, focused) {
                                  return Material(
                                    color: _focusColor,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      onTap: _submitSearch,
                                      borderRadius: BorderRadius.circular(12),
                                      splashColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      hoverColor: Colors.transparent,
                                      focusColor: Colors.transparent,
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 120),
                                        width: 46,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: focused
                                                ? Colors.white
                                                : Colors.transparent,
                                            width: focused ? 2.2 : 0,
                                          ),
                                          boxShadow: focused
                                              ? [
                                                  BoxShadow(
                                                    color:
                                                        _focusColor.withValues(
                                                      alpha: 0.55,
                                                    ),
                                                    blurRadius: 12,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: const Icon(
                                          Icons.search_rounded,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.contextData.title.trim().isNotEmpty)
                      _MovieTitleHeader(
                        title: widget.contextData.title,
                        compact: true,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.subtitles_outlined,
                          size: 42,
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _banner ?? 'subtitle_search_by_hint'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _banner != null
                                ? Colors.redAccent.shade100
                                : Colors.white54,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );

    if (widget.asDialog) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
        child: panel,
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: panel,
    );
  }
}

/* ───────────────────────── Results ───────────────────────── */

class _SubtitleResultsHost extends StatelessWidget {
  const _SubtitleResultsHost({
    required this.results,
    required this.contentTitle,
    required this.asDialog,
  });

  final List<SubtitleResultItem> results;
  final String contentTitle;
  final bool asDialog;

  @override
  Widget build(BuildContext context) {
    final page = _SubtitleResultsPage(
      results: results,
      contentTitle: contentTitle,
    );

    if (asDialog) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        child: Material(
          color: _kPanel,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 640,
            height: MediaQuery.of(context).size.height * 0.82,
            child: page,
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Material(
        color: _kPanel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: page,
        ),
      ),
    );
  }
}

/// Results list only — tap / remote OK closes immediately with the chosen item.
class _SubtitleResultsPage extends StatelessWidget {
  const _SubtitleResultsPage({
    required this.results,
    required this.contentTitle,
  });

  final List<SubtitleResultItem> results;
  final String contentTitle;

  @override
  Widget build(BuildContext context) {
    return _SubtitleFocusTrap(
      debugLabel: 'subtitle_results',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
            child: Row(
              children: [
                FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: _FocusIconButton(
                    tooltip: 'Back',
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Expanded(
                  child: contentTitle.trim().isEmpty
                      ? Text(
                          'subtitle_search_results'.tr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : _MovieTitleHeader(
                          title: contentTitle,
                          eyebrow: 'subtitle_search_results'.tr,
                          meta: '${results.length}',
                        ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              cacheExtent: 1200,
              children: [
                for (var index = 0; index < results.length; index++)
                  Padding(
                    key: ValueKey('sub-${results[index].fileId}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FocusTraversalOrder(
                      order: NumericFocusOrder(2.0 + index),
                      child: _ResultTile(
                        item: results[index],
                        busy: false,
                        enabled: true,
                        autofocus: index == 0,
                        onTap: () =>
                            Navigator.of(context).pop(results[index]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────── Shared bits ───────────────────────── */

/// Elegant movie/series title for search form + results header.
class _MovieTitleHeader extends StatelessWidget {
  const _MovieTitleHeader({
    required this.title,
    this.eyebrow,
    this.meta,
    this.compact = false,
  });

  final String title;
  final String? eyebrow;
  final String? meta;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = title.trim();
    if (t.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        top: compact ? 12 : 0,
        left: compact ? 2 : 0,
        right: compact ? 2 : 0,
        bottom: compact ? 2 : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null && eyebrow!.trim().isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    eyebrow!.trim().toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.48),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.35,
                    ),
                  ),
                ),
                if (meta != null && meta!.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      meta!.trim(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: compact ? 20 : 26,
                margin: EdgeInsets.only(top: compact ? 2 : 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _focusColor,
                      _focusColor.withValues(alpha: 0.2),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t,
                  maxLines: compact ? 2 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 15.5 : 17,
                    fontWeight: FontWeight.w700,
                    height: 1.22,
                    letterSpacing: 0.15,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TurnOffChip extends StatelessWidget {
  const _TurnOffChip({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _TvFocus(
      onActivated: onPressed,
      builder: (context, focused) {
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(22),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: _focusHalo(
                focused: focused,
                borderRadius: BorderRadius.circular(22),
                unfocusedBorder: _focusColor.withValues(alpha: 0.45),
                unfocusedBorderWidth: 1.1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.subtitles_off_rounded, size: 16, color: _focusColor),
                  const SizedBox(width: 6),
                  Text(
                    'subtitle_turn_off'.tr,
                    style: TextStyle(
                      color: _focusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FocusIconButton extends StatelessWidget {
  const _FocusIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return _TvFocus(
      onActivated: onPressed,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: _focusHalo(
            focused: focused,
            borderRadius: BorderRadius.circular(22),
          ),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            style: _tvIconButtonStyle,
            icon: Icon(icon, color: Colors.white70),
          ),
        );
      },
    );
  }
}

class _SegmentedMode extends StatelessWidget {
  const _SegmentedMode({
    required this.value,
    required this.onChanged,
    required this.labelOf,
    required this.enabled,
  });

  final SubtitleSearchBy value;
  final ValueChanged<SubtitleSearchBy> onChanged;
  final String Function(SubtitleSearchBy) labelOf;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kPanelElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: SubtitleSearchBy.values.map((mode) {
          final selected = mode == value;
          return _TvFocus(
            canRequestFocus: enabled,
            onActivated: enabled ? () => onChanged(mode) : null,
            builder: (context, focused) {
              return InkWell(
                onTap: enabled ? () => onChanged(mode) : null,
                borderRadius: BorderRadius.circular(11),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: _focusHalo(
                    focused: focused,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    labelOf(mode),
                    style: TextStyle(
                      color: selected ? _focusColor : Colors.white60,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.onTap,
    required this.enabled,
    this.focusNode,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return _TvFocus(
      focusNode: focusNode,
      canRequestFocus: enabled,
      onActivated: enabled ? onTap : null,
      builder: (context, focused) {
        return Material(
          color: _kPanelElevated,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: _focusHalo(
                focused: focused,
                borderRadius: BorderRadius.circular(12),
                unfocusedBorder: _kLine,
                unfocusedBorderWidth: 1,
              ),
              child: Row(
                children: [
                  Icon(Icons.translate_rounded, size: 16, color: _focusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded,
                      color: Colors.white54, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.item,
    required this.onTap,
    required this.busy,
    required this.enabled,
    this.autofocus = false,
  });

  final SubtitleResultItem item;
  final VoidCallback onTap;
  final bool busy;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return _TvFocus(
      autofocus: autofocus,
      canRequestFocus: enabled,
      scrollIntoView: true,
      onActivated: enabled ? onTap : null,
      builder: (context, focused) {
        return Material(
          color: _kPanelElevated,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              decoration: _focusHalo(
                focused: focused,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0x22FFFFFF),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: busy
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _focusColor,
                            ),
                          )
                        : Text(
                            item.language.toUpperCase(),
                            style: TextStyle(
                              color: _focusColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.releaseName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${'subtitle_result_downloads'.tr}: ${item.downloads}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.download_rounded,
                    color: enabled ? Colors.white54 : Colors.white24,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
