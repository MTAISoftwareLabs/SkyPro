class ChannelSerie {
  final String? num;
  final String? name;
  final String? seriesId;
  final String? cover;
  final String? plot;

  final String? rating;
  final String? rating5based;

  final String? categoryId;
  /// تاريخ الإضافة أو آخر تعديل (من السيرفر) لترتيب "المسلسلات المضافة حديثاً"
  /// يُقرأ من last_modified أو last_update أو added
  final String? added;

  ChannelSerie({
    this.num,
    this.name,
    this.seriesId,
    this.cover,
    this.plot,
    this.rating,
    this.rating5based,
    this.categoryId,
    this.added,
  });

  ChannelSerie.fromJson(Map<String, dynamic> json)
      : num = json['num']?.toString(),
        name = json['name']?.toString(),
        seriesId = json['series_id']?.toString(),
        cover = json['cover']?.toString(),
        plot = json['plot']?.toString(),
        rating = json['rating']?.toString(),
        rating5based = json['rating_5based']?.toString(),
        categoryId = json['category_id']?.toString(),
        added = _readTimestamp(json);

  static String? _readTimestamp(Map<String, dynamic> json) {
    final v = json['last_modified'] ?? json['last_update'] ?? json['added'];
    return v?.toString();
  }

  /// قيمة رقمية للترتيب (ثوانٍ تُحوّل لميلي ثانية إن كانت &lt; 100000000000)
  int get sortTimestamp {
    final v = int.tryParse(added ?? '0') ?? 0;
    if (v > 0 && v < 100000000000) return v * 1000;
    return v;
  }

  Map<String, dynamic> toJson() => {
        'num': num,
        'name': name,
        'series_id': seriesId,
        'cover': cover,
        'plot': plot,
        'rating': rating,
        'rating_5based': rating5based,
        'category_id': categoryId,
        if (added != null) 'added': added,
      };
}
