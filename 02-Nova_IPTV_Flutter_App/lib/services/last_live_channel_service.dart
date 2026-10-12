import 'package:get_storage/get_storage.dart';

import '../repository/models/channel_live.dart';

/// تذكر آخر قناة مباشرة مع نافذة استكمال حتى 3 ساعات.
class LastLiveChannelService {
  LastLiveChannelService._();

  static const String kStorageLastLiveChannel = 'last_live_channel_v1';
  static const Duration maxResumeAge = Duration(hours: 3);

  static final GetStorage _box = GetStorage();

  /// يطابق [rememberLastChannelEnabled] في constants.
  static bool get isEnabled {
    final stored = _box.read('remember_last_channel');
    if (stored is bool) return stored;
    return false;
  }

  static void setEnabled(bool enabled) {
    _box.write('remember_last_channel', enabled);
    if (!enabled) clear();
  }

  static void save({
    required ChannelLive channel,
    required String link,
    String? categoryId,
  }) {
    if (!isEnabled) return;
    final sid = channel.streamId?.trim() ?? '';
    if (sid.isEmpty || link.trim().isEmpty) return;

    _box.write(kStorageLastLiveChannel, <String, dynamic>{
      'channel': channel.toJson(),
      'link': link.trim(),
      'category_id':
          (categoryId ?? channel.categoryId)?.toString().trim() ?? '',
      'saved_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// يعيد بيانات الاستكمال إن كانت الخاصية مفعّلة وضمن مهلة 3 ساعات.
  static LastLiveResume? peekResume() {
    if (!isEnabled) return null;
    final raw = _box.read(kStorageLastLiveChannel);
    if (raw is! Map) return null;

    final map = Map<String, dynamic>.from(raw);
    final savedAtMs = map['saved_at_ms'];
    final ms =
        savedAtMs is int
            ? savedAtMs
            : int.tryParse(savedAtMs?.toString() ?? '');
    if (ms == null) {
      clear();
      return null;
    }

    final savedAt = DateTime.fromMillisecondsSinceEpoch(ms);
    if (DateTime.now().difference(savedAt) > maxResumeAge) {
      clear();
      return null;
    }

    final link = (map['link'] ?? '').toString().trim();
    final channelRaw = map['channel'];
    if (link.isEmpty || channelRaw is! Map) {
      clear();
      return null;
    }

    final channel = ChannelLive.fromJson(Map<String, dynamic>.from(channelRaw));
    final name = (channel.name ?? '').trim();
    if ((channel.streamId ?? '').trim().isEmpty || name.isEmpty) {
      clear();
      return null;
    }

    final categoryId = (map['category_id'] ?? channel.categoryId ?? '')
        .toString()
        .trim();

    return LastLiveResume(
      channel: channel,
      link: link,
      categoryId: categoryId.isEmpty ? null : categoryId,
      savedAt: savedAt,
    );
  }

  static void clear() {
    _box.remove(kStorageLastLiveChannel);
  }

  /// عند إغلاق توست الاستكمال بدون متابعة: لا يُعرض مجدداً حتى مشاهدة جديدة.
  static void markResumeDismissed() {
    clear();
  }
}

class LastLiveResume {
  const LastLiveResume({
    required this.channel,
    required this.link,
    required this.savedAt,
    this.categoryId,
  });

  final ChannelLive channel;
  final String link;
  final DateTime savedAt;
  final String? categoryId;

  String get title => (channel.name ?? '').trim();
}
