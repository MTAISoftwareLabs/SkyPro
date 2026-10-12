class WatchingModel {
  final String streamId;
  final String image;
  final String title;

  double sliderValue;
  final double durationStrm;
  final String stream;

  /// للمسلسلات: معرف المسلسل لعرض "تمت مشاهدته"
  final String? seriesId;
  /// للمسلسلات: اسم المسلسل للعرض في قائمة تمت مشاهدته
  final String? seriesName;
  /// للمسلسلات: صورة المسلسل للعرض في قائمة تمت مشاهدته
  final String? seriesCover;

  /// تقييم IPTV المحفوظ لعرض الشارة في صف متابعة المشاهدة
  final String? rating;
  final String? rating5based;

  /// فئة الفيلم — لازمة لعرض الأفلام المقترحة في المشغّل
  final String? categoryId;

  WatchingModel({
    required this.streamId,
    required this.image,
    required this.title,
    required this.stream,
    required this.sliderValue,
    required this.durationStrm,
    this.seriesId,
    this.seriesName,
    this.seriesCover,
    this.rating,
    this.rating5based,
    this.categoryId,
  });

  factory WatchingModel.fromJson(Map<String, dynamic> json) {
    return WatchingModel(
      streamId: json["streamId"]?.toString() ?? '',
      image: json["image"]?.toString() ?? '',
      title: json["title"]?.toString() ?? '',
      sliderValue: double.tryParse(json["sliderValue"].toString()) ?? 0,
      stream: json["stream"]?.toString() ?? '',
      durationStrm: double.tryParse(json['durationStrm'].toString()) ?? 0,
      seriesId: json["seriesId"]?.toString(),
      seriesName: json["seriesName"]?.toString(),
      seriesCover: json["seriesCover"]?.toString(),
      rating: json["rating"]?.toString(),
      rating5based: json["rating5based"]?.toString(),
      categoryId: json["categoryId"]?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "streamId": streamId,
      "image": image,
      "title": title,
      "sliderValue": sliderValue,
      "stream": stream,
      'durationStrm': durationStrm,
      if (seriesId != null) "seriesId": seriesId,
      if (seriesName != null) "seriesName": seriesName,
      if (seriesCover != null) "seriesCover": seriesCover,
      if (rating != null) "rating": rating,
      if (rating5based != null) "rating5based": rating5based,
      if (categoryId != null) "categoryId": categoryId,
    };
  }

//
}
