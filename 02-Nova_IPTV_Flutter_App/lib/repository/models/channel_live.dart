class ChannelLive {
  final String? num;
  final String? name;
  final String? streamType;
  final String? streamId;
  final String? streamIcon;
  final dynamic epgChannelId;
  final String? added;
  final String? isAdult;
  final String? categoryId;
  final String? customSid;
  final String? tvArchive;
  final String? directSource;
  final String? tvArchiveDuration;

  const ChannelLive({
    this.num,
    this.name,
    this.streamType,
    this.streamId,
    this.streamIcon,
    this.epgChannelId,
    this.added,
    this.isAdult,
    this.categoryId,
    this.customSid,
    this.tvArchive,
    this.directSource,
    this.tvArchiveDuration,
  });

  ChannelLive.fromJson(Map<String, dynamic> json)
      : num = json['num']?.toString(),
        name = json['name']?.toString(),
        streamType = json['stream_type']?.toString(),
        streamId = json['stream_id']?.toString(),
        streamIcon = json['stream_icon']?.toString(),
        epgChannelId = json['epg_channel_id']?.toString(),
        added = json['added']?.toString(),
        isAdult = json['is_adult']?.toString(),
        categoryId = _normalizeCategoryId(json['category_id']),
        customSid = json['custom_sid']?.toString(),
        tvArchive = json['tv_archive']?.toString(),
        directSource = json['direct_source']?.toString(),
        tvArchiveDuration = json['tv_archive_duration']?.toString();

  static String? _normalizeCategoryId(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s == 'null' || s == 'undefined') return null;
    return s;
  }

  Map<String, dynamic> toJson() => {
        'num': num,
        'name': name,
        'stream_type': streamType,
        'stream_id': streamId,
        'stream_icon': streamIcon,
        'epg_channel_id': epgChannelId,
        'added': added,
        'is_adult': isAdult,
        'category_id': categoryId,
        'custom_sid': customSid,
        'tv_archive': tvArchive,
        'direct_source': directSource,
        'tv_archive_duration': tvArchiveDuration
      };
}

/// هل القناتان المباشرتان هما نفس القناة؟
/// نفس [stream_id] = نفس القناة حتى لو اختلف الاسم المعروض (مثلاً KTV2 / KUWAIT HD2).
bool liveChannelsMatch(ChannelLive a, ChannelLive b) {
  final aSid = a.streamId?.trim() ?? '';
  final bSid = b.streamId?.trim() ?? '';
  if (aSid.isNotEmpty && bSid.isNotEmpty) {
    return aSid == bSid;
  }
  final aName = (a.name ?? '').trim().toLowerCase();
  final bName = (b.name ?? '').trim().toLowerCase();
  return aName.isNotEmpty && aName == bName;
}
