import 'package:mehdi_iptv/services/presence_heartbeat_service.dart';

/// ما يشاهده المستخدم حالياً — يُرسل مع نبضة التواجد للوحة التحكم.
class NowWatchingPresence {
  NowWatchingPresence._();
  static final NowWatchingPresence instance = NowWatchingPresence._();

  String? _type; // live | movie | series
  String? _title;
  String? _streamId;
  String? _extra;

  String? get type => _type;
  String? get title => _title;
  String? get streamId => _streamId;
  String? get extra => _extra;

  bool get hasContent =>
      (_type ?? '').trim().isNotEmpty && (_title ?? '').trim().isNotEmpty;

  Map<String, String> toHeartbeatFields() {
    if (!hasContent) {
      return const {
        'watching_type': '',
        'watching_title': '',
        'watching_stream_id': '',
        'watching_extra': '',
      };
    }
    return {
      'watching_type': (_type ?? '').trim(),
      'watching_title': (_title ?? '').trim(),
      'watching_stream_id': (_streamId ?? '').trim(),
      'watching_extra': (_extra ?? '').trim(),
    };
  }

  void setWatching({
    required String type,
    required String title,
    String? streamId,
    String? extra,
    bool pushHeartbeat = true,
  }) {
    final t = type.trim().toLowerCase();
    final name = title.trim();
    if (t.isEmpty || name.isEmpty) {
      clear(pushHeartbeat: pushHeartbeat);
      return;
    }
    final normalized = switch (t) {
      'live' || 'movie' || 'series' => t,
      _ => 'live',
    };
    final nextId = (streamId ?? '').trim();
    final nextExtra = (extra ?? '').trim();
    final changed =
        _type != normalized ||
        _title != name ||
        _streamId != nextId ||
        _extra != nextExtra;
    _type = normalized;
    _title = name;
    _streamId = nextId.isEmpty ? null : nextId;
    _extra = nextExtra.isEmpty ? null : nextExtra;
    PresenceHeartbeatService.instance.refreshSchedule(beatNow: changed && pushHeartbeat);
  }

  void clear({bool pushHeartbeat = true}) {
    final had = hasContent;
    _type = null;
    _title = null;
    _streamId = null;
    _extra = null;
    if (had) {
      PresenceHeartbeatService.instance.refreshSchedule(beatNow: pushHeartbeat);
    }
  }
}
