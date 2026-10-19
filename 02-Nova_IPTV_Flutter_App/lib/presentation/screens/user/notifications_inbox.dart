part of '../screens.dart';

class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({super.key});

  @override
  State<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen>
    with LandscapeMainAppStateMixin<NotificationsInboxScreen> {
  late final FocusNode _backFocusNode;
  late final FocusNode _firstContentFocusNode;
  bool _backFocused = false;

  static bool _isKeyDown(KeyEvent event) =>
      event is KeyDownEvent || event is KeyRepeatEvent;

  @override
  void initState() {
    super.initState();
    NotificationInboxService.instance.ensureLoaded();
    unawaited(ActivationApi().syncNotificationInbox());
    _backFocusNode = FocusNode(
      debugLabel: 'notifications_back',
      onKeyEvent: (n, e) {
        if (!_isKeyDown(e)) return KeyEventResult.ignored;
        final key = e.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.browserBack) {
          Get.back();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowRight) {
          if (_firstContentFocusNode.canRequestFocus) {
            _firstContentFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
    _backFocusNode.addListener(_onBackFocusChanged);
    _firstContentFocusNode = FocusNode(debugLabel: 'notifications_first');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(NotificationInboxService.instance.markAllRead());
      _backFocusNode.requestFocus();
    });
  }

  void _onBackFocusChanged() {
    if (!mounted) return;
    final has = _backFocusNode.hasFocus;
    if (_backFocused != has) setState(() => _backFocused = has);
  }

  @override
  void dispose() {
    _backFocusNode.removeListener(_onBackFocusChanged);
    _backFocusNode.dispose();
    _firstContentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _confirmClearAll() async {
    final ok = await AppActionConfirmDialog.show(
      context,
      icon: LucideIcons.bell_off,
      accent: const Color(0xFFD32F2F),
      title: 'notifications_clear_all'.tr,
      message: 'notifications_clear_all_confirm'.tr,
      confirmLabel: 'delete'.tr,
      cancelLabel: 'no'.tr,
      confirmIcon: LucideIcons.trash,
    );
    if (ok == true) {
      await NotificationInboxService.instance.clearAll();
    }
  }

  Future<void> _openItem(InboxNotification item) async {
    await NotificationInboxService.instance.markRead(item.id);
    final url = (item.url ?? '').trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (sameDay) return '$hh:$mm';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    return Scaffold(
      body: Container(
        width: 100.w,
        height: 100.h,
        decoration: kDecorBackground,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tv ? 28 : 16,
              vertical: tv ? 14 : 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NotificationsAppBar(
                  backFocusNode: _backFocusNode,
                  backFocused: _backFocused,
                  onClearAll: _confirmClearAll,
                ),
                SizedBox(height: tv ? 18 : 12),
                Expanded(
                  child: ValueListenableBuilder<List<InboxNotification>>(
                    valueListenable: NotificationInboxService.instance.items,
                    builder: (context, list, _) {
                      if (list.isEmpty) {
                        return const _NotificationsEmptyState();
                      }
                      return ListView.separated(
                        padding: EdgeInsets.only(bottom: tv ? 24 : 12),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => SizedBox(height: tv ? 12 : 10),
                        itemBuilder: (context, index) {
                          final item = list[index];
                          return _NotificationCard(
                            item: item,
                            timeLabel: _formatWhen(item.createdAt),
                            autofocus: index == 0,
                            focusNode:
                                index == 0 ? _firstContentFocusNode : null,
                            onOpen: () => _openItem(item),
                            onDelete: () => NotificationInboxService.instance
                                .delete(item.id),
                          );
                        },
                      );
                    },
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

class _NotificationsAppBar extends StatelessWidget {
  const _NotificationsAppBar({
    required this.backFocusNode,
    required this.backFocused,
    required this.onClearAll,
  });

  final FocusNode backFocusNode;
  final bool backFocused;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    return SizedBox(
      height: tv ? 48 : 44,
      // موبايل: LTR باش زر الرجوع يبقى فاليمين (بحال Movie/Series).
      child: Directionality(
        textDirection: tv ? Directionality.of(context) : TextDirection.ltr,
        child: Row(
          children: [
            Image(
              width: tv ? 30 : 28,
              height: tv ? 30 : 28,
              image: const AssetImage(kIconSplash),
            ),
            const SizedBox(width: 8),
            Text(
              'notifications_inbox_title'.tr,
              style: Get.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: tv ? 20 : null,
              ),
            ),
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: Colors.white24,
            ),
            Icon(
              FontAwesomeIcons.bell,
              size: tv ? 16 : 15,
              color: kColorPrimary,
            ),
            const Spacer(),
            ValueListenableBuilder<List<InboxNotification>>(
              valueListenable: NotificationInboxService.instance.items,
              builder: (context, list, _) {
                if (list.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: onClearAll,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: Icon(LucideIcons.trash, size: tv ? 18 : 16),
                    label: Text(
                      'notifications_clear_all'.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: tv ? 14 : 12.5,
                      ),
                    ),
                  ),
                );
              },
            ),
            Focus(
              focusNode: backFocusNode,
              child: InkWell(
                onTap: () => Get.back(),
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(22),
                child: AnimatedContainer(
                  duration: kFocusAnimDuration,
                  width: tv ? 44 : 40,
                  height: tv ? 44 : 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2A2D34),
                    border: Border.all(
                      color: backFocused ? kColorFocus : Colors.white24,
                      width: backFocused ? 2 : 1,
                    ),
                    boxShadow: backFocused
                        ? [
                            BoxShadow(
                              color: kColorFocus.withValues(alpha: 0.35),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    FontAwesomeIcons.chevronRight,
                    color: backFocused ? kColorFocus : Colors.white,
                    size: tv ? 18 : 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState();

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tv ? 48 : 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: tv ? 120 : 96,
              height: tv ? 120 : 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kColorCardLight,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: kColorPrimary.withValues(alpha: 0.12),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                FontAwesomeIcons.bellSlash,
                size: tv ? 42 : 34,
                color: kColorHint,
              ),
            ),
            SizedBox(height: tv ? 26 : 20),
            Text(
              'notifications_empty_title'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: tv ? 22 : 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'notifications_empty_hint'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: tv ? 15.5 : 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatefulWidget {
  const _NotificationCard({
    required this.item,
    required this.timeLabel,
    required this.onOpen,
    required this.onDelete,
    this.autofocus = false,
    this.focusNode,
  });

  final InboxNotification item;
  final String timeLabel;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  late final FocusNode _focusNode;
  bool _ownedFocus = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode(debugLabel: 'notif_card_${widget.item.id}');
      _ownedFocus = true;
    }
    _focusNode.addListener(_onFocus);
  }

  void _onFocus() {
    if (!mounted) return;
    final has = _focusNode.hasFocus;
    if (_focused != has) setState(() => _focused = has);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    if (_ownedFocus) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final item = widget.item;
    final hasLink = (item.url ?? '').trim().isNotEmpty;
    final unread = !item.read;

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter) {
          widget.onOpen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onOpen,
          onLongPress: widget.onDelete,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: kFocusAnimDuration,
            padding: EdgeInsets.symmetric(
              horizontal: tv ? 18 : 14,
              vertical: tv ? 16 : 13,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF1C2538).withValues(alpha: 0.92),
              border: Border.all(
                color: _focused
                    ? kColorFocus
                    : Colors.white.withValues(alpha: unread ? 0.22 : 0.1),
                width: _focused ? 2 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: kColorFocus.withValues(alpha: 0.28),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: tv ? 46 : 40,
                  height: tv ? 46 : 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kColorPrimary.withValues(alpha: 0.14),
                    border: Border.all(
                      color: kColorPrimary.withValues(alpha: 0.28),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    hasLink ? LucideIcons.link_2 : FontAwesomeIcons.bell,
                    size: tv ? 18 : 15,
                    color: kColorPrimary,
                  ),
                ),
                SizedBox(width: tv ? 14 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (unread) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: kColorPrimary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: tv ? 16.5 : 14.5,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.timeLabel,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: tv ? 13 : 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (item.body.trim().isNotEmpty) ...[
                        SizedBox(height: tv ? 8 : 6),
                        Text(
                          item.body,
                          maxLines: tv ? 4 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: tv ? 14.5 : 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (hasLink) ...[
                        SizedBox(height: tv ? 10 : 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: Colors.white.withValues(alpha: 0.06),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.external_link,
                                size: 13,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'notifications_open_link'.tr,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: tv ? 13 : 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
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
