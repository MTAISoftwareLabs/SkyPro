import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/category.dart';
import '../models/channel_live.dart';
import '../models/channel_movie.dart';
import '../models/channel_serie.dart';

/// بصمات ثابتة لمقارنة الكاش المحلي مع بيانات السيرفر (بدون تحميل UI إن لم يتغيّر شيء).
class CatalogFingerprint {
  CatalogFingerprint._();

  static String _digest(String raw) => md5.convert(utf8.encode(raw)).toString();

  static String categories(List<CategoryModel> list) {
    final parts =
        list
            .map(
              (c) =>
                  '${(c.categoryId ?? '').trim()}|${(c.categoryName ?? '').trim()}|${(c.parentId ?? '').trim()}',
            )
            .toList()
          ..sort();
    return _digest('${parts.length}\n${parts.join('\n')}');
  }

  static String lives(List<ChannelLive> list) {
    final parts =
        list
            .map(
              (c) =>
                  '${(c.streamId ?? '').trim()}|${(c.name ?? '').trim()}|${(c.streamIcon ?? '').trim()}|${(c.added ?? '').trim()}',
            )
            .toList()
          ..sort();
    return _digest('${parts.length}\n${parts.join('\n')}');
  }

  static String movies(List<ChannelMovie> list) {
    final parts =
        list
            .map(
              (c) =>
                  '${(c.streamId ?? '').trim()}|${(c.name ?? '').trim()}|${(c.streamIcon ?? '').trim()}|${(c.added ?? '').trim()}',
            )
            .toList()
          ..sort();
    return _digest('${parts.length}\n${parts.join('\n')}');
  }

  static String series(List<ChannelSerie> list) {
    final parts =
        list
            .map(
              (c) =>
                  '${(c.seriesId ?? '').trim()}|${(c.name ?? '').trim()}|${(c.cover ?? '').trim()}|${(c.added ?? '').trim()}',
            )
            .toList()
          ..sort();
    return _digest('${parts.length}\n${parts.join('\n')}');
  }
}
