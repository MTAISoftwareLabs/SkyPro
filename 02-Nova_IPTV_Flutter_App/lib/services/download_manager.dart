import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../repository/models/downloaded_movie.dart';

const String kStorageDownloadedMovies = 'downloaded_movies_v1';

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(hours: 6),
      followRedirects: true,
      validateStatus: (s) => s != null && s >= 200 && s < 400,
    ),
  );

  final Map<String, CancelToken> _cancelTokens = {};
  Directory? _rootDir;

  /// التحميلات تُحفظ داخل مجلد التطبيق الخاص (Application Support) —
  /// لا نحتاج صلاحية Storage/الوسائط من النظام، ولا نطلبها عند الإقلاع.
  Future<Directory> _ensureRoot() async {
    if (_rootDir != null) return _rootDir!;
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}${Platform.pathSeparator}downloads');
    final movies = Directory('${root.path}${Platform.pathSeparator}movies');
    final thumbs = Directory('${root.path}${Platform.pathSeparator}thumbs');
    if (!await movies.exists()) await movies.create(recursive: true);
    if (!await thumbs.exists()) await thumbs.create(recursive: true);
    _rootDir = root;
    return root;
  }

  Future<Directory> moviesDir() async {
    final root = await _ensureRoot();
    return Directory('${root.path}${Platform.pathSeparator}movies');
  }

  Future<Directory> thumbsDir() async {
    final root = await _ensureRoot();
    return Directory('${root.path}${Platform.pathSeparator}thumbs');
  }

  List<DownloadedMovie> loadAll() {
    final raw = GetStorage().read(kStorageDownloadedMovies);
    if (raw is! List) return [];
    final out = <DownloadedMovie>[];
    for (final e in raw) {
      if (e is Map) {
        out.add(DownloadedMovie.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  Future<void> _saveAll(List<DownloadedMovie> items) async {
    await GetStorage().write(
      kStorageDownloadedMovies,
      items.map((e) => e.toJson()).toList(),
    );
  }

  bool isAlreadyDownloaded(String streamId) {
    return loadAll().any((e) => e.streamId == streamId);
  }

  String _randomTempName() {
    final r = Random();
    final n = List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
    return 'dl_$n';
  }

  String normalizeExt(String? ext) {
    var e = (ext ?? 'mp4').trim().toLowerCase();
    if (e.startsWith('.')) e = e.substring(1);
    if (e.isEmpty) e = 'mp4';
    return e;
  }

  Future<DownloadedMovie> downloadMovie({
    required String streamId,
    required String name,
    required String streamIcon,
    required String videoUrl,
    required String containerExtension,
    void Function(double progress)? onProgress,
  }) async {
    if (streamId.trim().isEmpty || videoUrl.trim().isEmpty) {
      throw StateError('invalid_download');
    }
    if (isAlreadyDownloaded(streamId)) {
      throw StateError('already_download');
    }
    if (_cancelTokens.containsKey(streamId)) {
      throw StateError('already_download');
    }

    final movies = await moviesDir();
    final thumbs = await thumbsDir();
    final ext = normalizeExt(containerExtension);
    final tempName = _randomTempName();
    final videoPath =
        '${movies.path}${Platform.pathSeparator}$tempName.$ext';
    final posterPath =
        '${thumbs.path}${Platform.pathSeparator}$tempName.jpg';

    final token = CancelToken();
    _cancelTokens[streamId] = token;

    try {
      await _dio.download(
        videoUrl,
        videoPath,
        cancelToken: token,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        },
      );

      final icon = streamIcon.trim();
      if (icon.isNotEmpty &&
          (icon.startsWith('http://') || icon.startsWith('https://'))) {
        try {
          await _dio.download(icon, posterPath, cancelToken: token);
        } catch (_) {}
      }

      final file = File(videoPath);
      final size = await file.exists() ? await file.length() : 0;
      final item = DownloadedMovie(
        streamId: streamId,
        name: name,
        streamIcon: streamIcon,
        videoUrl: videoUrl,
        containerExtension: ext,
        tempName: tempName,
        localVideoPath: videoPath,
        localPosterPath: await File(posterPath).exists() ? posterPath : '',
        fileSizeBytes: size,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      final all = loadAll()..insert(0, item);
      await _saveAll(all);
      onProgress?.call(1);
      return item;
    } finally {
      _cancelTokens.remove(streamId);
    }
  }

  Future<void> cancel(String streamId) async {
    final token = _cancelTokens.remove(streamId);
    token?.cancel('cancelled');
  }

  Future<void> delete(DownloadedMovie item) async {
    final all = loadAll().where((e) => e.streamId != item.streamId).toList();
    await _saveAll(all);
    try {
      final v = File(item.localVideoPath);
      if (await v.exists()) await v.delete();
    } catch (_) {}
    try {
      if (item.localPosterPath.isNotEmpty) {
        final p = File(item.localPosterPath);
        if (await p.exists()) await p.delete();
      }
    } catch (_) {}
  }

  Future<List<DownloadedMovie>> reconcileWithDisk() async {
    final all = loadAll();
    final kept = <DownloadedMovie>[];
    for (final item in all) {
      final f = File(item.localVideoPath);
      if (await f.exists()) {
        kept.add(item);
      }
    }
    if (kept.length != all.length) {
      await _saveAll(kept);
    }
    return kept;
  }

  Future<({double availableGb, double totalGb, bool known})> storageStats() async {
    try {
      if (Platform.isAndroid) {
        final result = await Process.run('df', ['-k', '/storage/emulated/0']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).trim().split('\n');
          if (lines.length >= 2) {
            final parts =
                lines.last.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
            if (parts.length >= 4) {
              final totalKb = double.tryParse(parts[1]) ?? 0;
              final availKb = double.tryParse(parts[3]) ?? 0;
              if (totalKb > 0) {
                return (
                  availableGb: availKb / (1024 * 1024),
                  totalGb: totalKb / (1024 * 1024),
                  known: true,
                );
              }
            }
          }
        }
      }
    } catch (_) {}

    try {
      final movies = await moviesDir();
      var used = 0;
      await for (final e in movies.list(recursive: true, followLinks: false)) {
        if (e is File) used += await e.length();
      }
      final usedGb = used / (1024 * 1024 * 1024);
      return (availableGb: usedGb, totalGb: usedGb + 8.0, known: false);
    } catch (_) {
      return (availableGb: 0.0, totalGb: 0.0, known: false);
    }
  }
}
