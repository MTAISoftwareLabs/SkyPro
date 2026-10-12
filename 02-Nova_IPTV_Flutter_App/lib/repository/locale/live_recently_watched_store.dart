import 'package:get_storage/get_storage.dart';

import '../../helpers/helpers.dart';
import '../models/channel_live.dart';

/// قنوات البث المباشر التي شُغّلت 15 ثانية فأكثر — لكل حساب.
class LiveRecentlyWatchedStore {
  LiveRecentlyWatchedStore._();

  static const int maxItems = 50;

  static GetStorage get _box => GetStorage();

  static String _key(String accountId) =>
      '$kStorageLiveRecentlyWatchedPrefix$accountId';

  static List<ChannelLive> load(String accountId) {
    final id = accountId.trim();
    if (id.isEmpty) return const [];
    final raw = _box.read(_key(id));
    if (raw is! List) return const [];
    final out = <ChannelLive>[];
    final seen = <String>{};
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        final ch = ChannelLive.fromJson(Map<String, dynamic>.from(e));
        final sid = (ch.streamId ?? '').trim();
        if (sid.isEmpty || !seen.add(sid)) continue;
        out.add(ch);
      } catch (_) {}
    }
    return out;
  }

  static void save(String accountId, List<ChannelLive> channels) {
    final id = accountId.trim();
    if (id.isEmpty) return;
    _box.write(
      _key(id),
      channels.take(maxItems).map((e) => e.toJson()).toList(),
    );
  }

  /// ينقل القناة لأعلى القائمة ويحفظها.
  static List<ChannelLive> record(
    String accountId,
    ChannelLive channel, {
    List<ChannelLive>? current,
  }) {
    final sid = (channel.streamId ?? '').trim();
    if (sid.isEmpty) return current ?? load(accountId);
    final list = List<ChannelLive>.from(current ?? load(accountId));
    list.removeWhere((c) => liveChannelsMatch(c, channel));
    list.insert(0, channel);
    if (list.length > maxItems) {
      list.removeRange(maxItems, list.length);
    }
    save(accountId, list);
    return list;
  }

  static void clearAll() {
    try {
      final keys = _box.getKeys().toList();
      for (final k in keys) {
        if (k.toString().startsWith(kStorageLiveRecentlyWatchedPrefix)) {
          _box.remove(k);
        }
      }
    } catch (_) {}
  }
}
