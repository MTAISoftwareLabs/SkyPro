import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../helpers/app_perf.dart';

final http.Client iptvImageHttpClient = () {
  final inner = HttpClient()
    ..maxConnectionsPerHost = 20
    ..idleTimeout = const Duration(seconds: 30);
  return IOClient(inner);
}();

final CacheManager iptvImageCacheManager = CacheManager(
  Config(
    'iptv_image_cache',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 800,
    fileService: HttpFileService(httpClient: iptvImageHttpClient),
  ),
);

/// روابط محمّلة في كاش القرص (bootstrap / All) — لا إعادة تنزيل.
final Set<String> _iptvDiskWarmDone = <String>{};

/// روابط مفكوكة في ذاكرة Flutter — لا إعادة precache بين All ↔ فئة.
final Set<String> _iptvMemoryWarmDone = <String>{};

void clearIptvImageWarmRegistry() {
  _iptvDiskWarmDone.clear();
  _iptvMemoryWarmDone.clear();
}

String _normUrl(String raw) => raw.trim();

Future<bool> isIptvImageDiskCached(String url) async {
  final u = _normUrl(url);
  if (u.isEmpty) return false;
  if (_iptvDiskWarmDone.contains(u)) return true;
  try {
    final f = await iptvImageCacheManager.getFileFromCache(u);
    if (f != null) {
      _iptvDiskWarmDone.add(u);
      return true;
    }
  } catch (_) {}
  return false;
}

bool isIptvImageMemoryWarm(String url) {
  final u = _normUrl(url);
  return u.isNotEmpty && _iptvMemoryWarmDone.contains(u);
}

void _markDiskWarm(String url) {
  final u = _normUrl(url);
  if (u.isNotEmpty) _iptvDiskWarmDone.add(u);
}

void _markMemoryWarm(String url) {
  final u = _normUrl(url);
  if (u.isEmpty) return;
  _iptvMemoryWarmDone.add(u);
  _iptvDiskWarmDone.add(u);
}

List<String> _collectUrls(List<String> raw, int limit) {
  final urls = <String>[];
  for (final item in raw) {
    if (urls.length >= limit) break;
    final url = _normUrl(item);
    if (url.isEmpty) continue;
    urls.add(url);
  }
  return urls;
}

/// أبعاد فك التشفير = الحجم المنطقي × DPR.
(int, int) iptvMemCachePx(
  BuildContext context,
  double logicalWidth,
  double logicalHeight,
) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final w = (logicalWidth * dpr).round().clamp(1, 2048);
  final h = (logicalHeight * dpr).round().clamp(1, 2048);
  return (w, h);
}

/// أولوية فك الصور — visible (grid) قبل background (precache/warming).
enum IptvDecodePriority {
  visible,
  background,
}

class _DecodeSlotRequest {
  _DecodeSlotRequest(this.priority, this.completer);
  final IptvDecodePriority priority;
  final Completer<void> completer;
}

/// بوابة decode عالمية — يحدّ concurrent decode عبر التطبيق.
class IptvImageDecodeGate {
  IptvImageDecodeGate._();
  static final IptvImageDecodeGate instance = IptvImageDecodeGate._();

  int _activeVisible = 0;
  int _activeBackground = 0;
  final List<_DecodeSlotRequest> _waiters = <_DecodeSlotRequest>[];

  int get maxSlots => AppPerf.instance.imageConcurrentFetches.clamp(2, 4);

  int get _visibleReserved => maxSlots >= 3 ? 2 : 1;

  int get _activeTotal => _activeVisible + _activeBackground;

  Future<T> run<T>(
    Future<T> Function() op, {
    required IptvDecodePriority priority,
  }) async {
    await _acquire(priority);
    try {
      return await op();
    } finally {
      _release(priority);
    }
  }

  Future<void> _acquire(IptvDecodePriority priority) {
    if (_canRunNow(priority)) {
      _grant(priority);
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(_DecodeSlotRequest(priority, completer));
    return completer.future;
  }

  int _slotsAvailableFor(IptvDecodePriority priority) {
    final free = maxSlots - _activeTotal;
    if (free <= 0) return 0;
    if (priority == IptvDecodePriority.visible) return free;
    final reserve =
        (_visibleReserved - _activeVisible).clamp(0, _visibleReserved);
    return (free - reserve).clamp(0, free);
  }

  bool _canRunNow(IptvDecodePriority priority) {
    if (_slotsAvailableFor(priority) <= 0) return false;
    if (priority == IptvDecodePriority.background &&
        _waiters.any((w) => w.priority == IptvDecodePriority.visible)) {
      return false;
    }
    return true;
  }

  void _grant(IptvDecodePriority priority) {
    if (priority == IptvDecodePriority.visible) {
      _activeVisible++;
    } else {
      _activeBackground++;
    }
  }

  void _release(IptvDecodePriority priority) {
    if (priority == IptvDecodePriority.visible) {
      _activeVisible = (_activeVisible - 1).clamp(0, maxSlots);
    } else {
      _activeBackground = (_activeBackground - 1).clamp(0, maxSlots);
    }
    _pumpWaiters();
  }

  void _pumpWaiters() {
    _waiters.sort(
      (a, b) => a.priority.index.compareTo(b.priority.index),
    );
    var i = 0;
    while (i < _waiters.length) {
      final req = _waiters[i];
      if (!_canRunNow(req.priority)) {
        i++;
        continue;
      }
      _waiters.removeAt(i);
      _grant(req.priority);
      req.completer.complete();
    }
  }
}

ImageProvider iptvPosterImageProvider(
  String url, {
  int? memCacheWidth,
  int? memCacheHeight,
}) {
  final base = CachedNetworkImageProvider(
    url,
    cacheManager: iptvImageCacheManager,
  );
  if (memCacheWidth != null && memCacheHeight != null) {
    return ResizeImage(
      base,
      width: memCacheWidth,
      height: memCacheHeight,
    );
  }
  return base;
}

/// فك بوستر grid — أولوية visible عبر [IptvImageDecodeGate].
Future<void> iptvDecodePosterForDisplay(
  BuildContext context,
  String url, {
  int? memCacheWidth,
  int? memCacheHeight,
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (!context.mounted || url.trim().isEmpty) return;
  final provider = iptvPosterImageProvider(
    url,
    memCacheWidth: memCacheWidth,
    memCacheHeight: memCacheHeight,
  );
  await IptvImageDecodeGate.instance.run(
    () => precacheImage(provider, context).timeout(timeout),
    priority: IptvDecodePriority.visible,
  );
  _markMemoryWarm(url);
}

/// تحميل ملفات الصور إلى كاش القرص فقط — بدون فك في الذاكرة (سلس على bootstrap).
Future<int> warmIptvImagesToDisk(
  List<String> imageUrls, {
  int limit = 200,
  int concurrency = 3,
  void Function(int done, int total)? onProgress,
  Duration? maxDuration,
  Duration perFileTimeout = const Duration(seconds: 8),
}) async {
  final urls = _collectUrls(imageUrls, limit);
  if (urls.isEmpty) return 0;

  final started = DateTime.now();
  final total = urls.length;
  var done = 0;
  var downloaded = 0;
  final workers = concurrency.clamp(1, 6);
  var next = 0;

  Future<void> report() async {
    onProgress?.call(done, total);
    if (done % 4 == 0) {
      await SchedulerBinding.instance.endOfFrame;
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> worker() async {
    while (true) {
      if (maxDuration != null &&
          DateTime.now().difference(started) >= maxDuration) {
        return;
      }
      final i = next++;
      if (i >= urls.length) return;
      final url = urls[i];
      try {
        if (await isIptvImageDiskCached(url)) {
          // موجود — لا تنزيل.
        } else {
          await iptvImageCacheManager
              .downloadFile(url)
              .timeout(perFileTimeout);
          downloaded++;
          _markDiskWarm(url);
        }
      } catch (_) {}
      done++;
      await report();
    }
  }

  await Future.wait(List.generate(workers, (_) => worker()));
  onProgress?.call(done, total);
  return downloaded;
}

/// تسخين صور IPTV — يتخطّى ما في القرص/الذاكرة (All → فئة بدون إعادة تحميل).
Future<void> precacheIptvPosters(
  BuildContext context,
  List<String> imageUrls, {
  int limit = 20,
  bool decodeIntoMemory = true,
  int concurrency = 3,
}) async {
  if (!context.mounted) return;

  final collected = _collectUrls(imageUrls, limit);
  if (collected.isEmpty) return;

  if (!decodeIntoMemory) {
    final needDisk = <String>[];
    for (final url in collected) {
      if (await isIptvImageDiskCached(url)) continue;
      needDisk.add(url);
    }
    if (needDisk.isEmpty) return;
    await warmIptvImagesToDisk(
      needDisk,
      limit: needDisk.length,
      concurrency: concurrency,
    );
    return;
  }

  final needMemory = <String>[];
  for (final url in collected) {
    if (isIptvImageMemoryWarm(url)) continue;
    needMemory.add(url);
  }
  if (needMemory.isEmpty) return;

  final workers = concurrency.clamp(1, 6);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      if (!context.mounted) return;
      final i = next++;
      if (i >= needMemory.length) return;
      final url = needMemory[i];
      if (isIptvImageMemoryWarm(url)) continue;
      try {
        await IptvImageDecodeGate.instance.run(
          () => precacheImage(
            CachedNetworkImageProvider(
              url,
              cacheManager: iptvImageCacheManager,
            ),
            context,
          ).timeout(const Duration(seconds: 4)),
          priority: IptvDecodePriority.background,
        );
        _markMemoryWarm(url);
      } catch (_) {}
    }
  }

  await Future.wait(List.generate(workers, (_) => worker()));
}
