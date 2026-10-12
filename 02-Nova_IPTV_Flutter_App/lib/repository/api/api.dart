import 'dart:convert';
import 'dart:developer';
import 'dart:io' show File;
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mehdi_iptv/repository/models/channel_movie.dart';
import 'package:mehdi_iptv/repository/m3u_parser.dart';
import 'package:mehdi_iptv/repository/ss_iptv_catalog.dart';
import 'package:mehdi_iptv/core/runtime_seal.dart';

import '../../helpers/home_perf_logger.dart';
import '../../helpers/home_recent_isolate_fetch.dart';
import '../../helpers/home_recent_parser.dart';
import '../../helpers/helpers.dart';

import '../models/category.dart';
import '../models/channel_live.dart';
import '../models/channel_serie.dart';
import '../models/epg.dart';
import '../models/movie_detail.dart';
import '../models/serie_details.dart';
import '../models/user.dart';
import '../models/watching.dart';

part '../locale/locale.dart';
part 'auth.dart';
part 'iptv.dart';
part '../locale/favorites.dart';

// ✅ Timeouts مناسبة للواي فاي والـ 4G مع دعم الضغط
final _dio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 25),
    sendTimeout: const Duration(seconds: 12),
    headers: {
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
      'Connection': 'keep-alive',
    },
  ),
);
final locale = GetStorage();
final favoritesLocale = GetStorage("favorites");
