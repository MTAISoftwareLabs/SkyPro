import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

/// إشعار محفوظ محلياً (صندوق الوارد داخل التطبيق).
class InboxNotification {
  const InboxNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.url,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? url;
  final bool read;

  InboxNotification copyWith({bool? read}) {
    return InboxNotification(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt,
      url: url,
      read: read ?? this.read,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'created_at': createdAt.toIso8601String(),
        'url': url,
        'read': read,
      };

  factory InboxNotification.fromJson(Map<String, dynamic> json) {
    final createdRaw = (json['created_at'] ?? '').toString();
    final created = DateTime.tryParse(createdRaw) ?? DateTime.now();
    return InboxNotification(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      createdAt: created,
      url: (json['url'] as String?)?.trim().isEmpty == true
          ? null
          : (json['url'] as String?)?.trim(),
      read: json['read'] == true,
    );
  }
}

/// يخزّن إشعارات Push الواردة لعرضها داخل التطبيق (TV + Phone).
class NotificationInboxService {
  NotificationInboxService._();
  static final NotificationInboxService instance = NotificationInboxService._();

  static const String _storageKey = 'notification_inbox_v1';
  /// أول تشغيل للتطبيق على هذا الجهاز — لا نجلب إشعارات اللوحة الأقدم من هذا الوقت.
  static const String _sinceKey = 'notification_inbox_since_ms';
  /// إشعارات مسحها المستخدم — لا تُعاد من مزامنة اللوحة.
  static const String _dismissedIdsKey = 'notification_inbox_dismissed_ids_v1';
  static const int _maxItems = 80;
  static const int _maxDismissedIds = 300;

  final GetStorage _storage = GetStorage();
  final ValueNotifier<List<InboxNotification>> items =
      ValueNotifier<List<InboxNotification>>(const []);
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  bool _loaded = false;

  /// وقت بداية صندوق الوارد لهذا التثبيت (يُثبَّت مرة واحدة).
  DateTime inboxSince() {
    final raw = _storage.read(_sinceKey);
    if (raw is int && raw > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed > 0) {
        return DateTime.fromMillisecondsSinceEpoch(parsed);
      }
    }
    final now = DateTime.now();
    _storage.write(_sinceKey, now.millisecondsSinceEpoch);
    return now;
  }

  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    inboxSince();
    _reloadFromStorage();
    unawaited(_pruneBeforeSince());
  }

  Future<void> _pruneBeforeSince() async {
    final since = inboxSince();
    final current = items.value;
    final kept = current
        .where(
          (e) =>
              !e.createdAt.isBefore(since.subtract(const Duration(seconds: 2))),
        )
        .toList();
    if (kept.length == current.length) return;
    await _persist(kept);
  }

  void _reloadFromStorage() {
    try {
      final raw = _storage.read(_storageKey);
      final list = <InboxNotification>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            try {
              list.add(
                InboxNotification.fromJson(Map<String, dynamic>.from(e)),
              );
            } catch (_) {}
          } else if (e is String) {
            try {
              final decoded = jsonDecode(e);
              if (decoded is Map) {
                list.add(
                  InboxNotification.fromJson(
                    Map<String, dynamic>.from(decoded),
                  ),
                );
              }
            } catch (_) {}
          }
        }
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      items.value = List.unmodifiable(list);
      unreadCount.value = list.where((e) => !e.read).length;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[NotificationInbox] load failed: $e\n$st');
      }
      items.value = const [];
      unreadCount.value = 0;
    }
  }

  Future<void> _persist(List<InboxNotification> list) async {
    final payload = list.map((e) => e.toJson()).toList(growable: false);
    await _storage.write(_storageKey, payload);
    items.value = List.unmodifiable(list);
    unreadCount.value = list.where((e) => !e.read).length;
  }

  /// يضيف إشعاراً من OneSignal (أو يحدّثه إن وُجد بنفس الـ id).
  Future<void> addIncoming({
    required String id,
    required String title,
    required String body,
    String? url,
  }) async {
    ensureLoaded();
    final cleanId = id.trim().isEmpty
        ? 'local_${DateTime.now().millisecondsSinceEpoch}'
        : id.trim();
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty && cleanBody.isEmpty) return;

    final current = List<InboxNotification>.from(items.value);
    final existingIdx = current.indexWhere((e) => e.id == cleanId);
    if (existingIdx >= 0) {
      // لا نكرر؛ نُبقي الحالة الحالية (مقروء/غير مقروء).
      return;
    }

    current.insert(
      0,
      InboxNotification(
        id: cleanId,
        title: cleanTitle.isEmpty ? cleanBody : cleanTitle,
        body: cleanBody,
        createdAt: DateTime.now(),
        url: (url ?? '').trim().isEmpty ? null : url!.trim(),
        read: false,
      ),
    );
    if (current.length > _maxItems) {
      current.removeRange(_maxItems, current.length);
    }
    await _persist(current);
  }

  Future<void> markRead(String id) async {
    ensureLoaded();
    final current = List<InboxNotification>.from(items.value);
    final i = current.indexWhere((e) => e.id == id);
    if (i < 0 || current[i].read) return;
    current[i] = current[i].copyWith(read: true);
    await _persist(current);
  }

  Future<void> markAllRead() async {
    ensureLoaded();
    final current = items.value;
    if (current.every((e) => e.read)) return;
    await _persist(
      current.map((e) => e.read ? e : e.copyWith(read: true)).toList(),
    );
  }

  Future<void> delete(String id) async {
    ensureLoaded();
    final next = items.value.where((e) => e.id != id).toList();
    if (next.length == items.value.length) return;
    await _rememberDismissed({id});
    await _persist(next);
  }

  Future<void> clearAll() async {
    ensureLoaded();
    final ids = items.value.map((e) => e.id).where((e) => e.isNotEmpty).toSet();
    if (ids.isNotEmpty) {
      await _rememberDismissed(ids);
    }
    await _persist(const []);
  }

  Set<String> _dismissedIds() {
    final raw = _storage.read(_dismissedIdsKey);
    if (raw is! List) return <String>{};
    return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet();
  }

  Future<void> _rememberDismissed(Set<String> ids) async {
    if (ids.isEmpty) return;
    final current = _dismissedIds()..addAll(ids);
    var list = current.toList();
    if (list.length > _maxDismissedIds) {
      list = list.sublist(list.length - _maxDismissedIds);
    }
    await _storage.write(_dismissedIdsKey, list);
  }

  /// يدمج إشعارات قادمة من لوحة التحكم (حتى لو ما توصلش Push للنظام).
  /// يتجاهل ما قبل تثبيت/أول تشغيل التطبيق، وما مسحه المستخدم.
  Future<int> mergeRemote(List<Map<String, dynamic>> remote) async {
    ensureLoaded();
    if (remote.isEmpty) return 0;

    final since = inboxSince();
    final dismissed = _dismissedIds();
    final current = List<InboxNotification>.from(items.value);
    final existingIds = current.map((e) => e.id).toSet();
    var added = 0;

    for (final raw in remote) {
      final id = (raw['id'] ?? '').toString().trim();
      final title = (raw['title'] ?? '').toString().trim();
      final body = (raw['message'] ?? raw['body'] ?? '').toString().trim();
      final url = (raw['url'] ?? '').toString().trim();
      if (id.isEmpty || (title.isEmpty && body.isEmpty)) continue;
      if (existingIds.contains(id) || dismissed.contains(id)) continue;

      final createdRaw = (raw['created_at'] ?? '').toString().trim();
      final created = DateTime.tryParse(createdRaw) ?? DateTime.now();
      // لا تعرض إشعارات أقدم من تثبيت التطبيق.
      if (created.isBefore(since.subtract(const Duration(seconds: 2)))) {
        continue;
      }

      current.add(
        InboxNotification(
          id: id,
          title: title.isEmpty ? body : title,
          body: body,
          createdAt: created,
          url: url.isEmpty ? null : url,
          read: false,
        ),
      );
      existingIds.add(id);
      added++;
    }

    if (added == 0) return 0;
    current.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (current.length > _maxItems) {
      current.removeRange(_maxItems, current.length);
    }
    await _persist(current);
    return added;
  }
}
