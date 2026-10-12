import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../repository/models/downloaded_movie.dart';
import '../../../services/download_manager.dart';

part 'downloads_state.dart';

class DownloadsCubit extends Cubit<DownloadsState> {
  DownloadsCubit() : super(DownloadsState.initial()) {
    unawaited(refresh());
  }

  final _manager = DownloadManager.instance;

  Future<void> refresh() async {
    emit(state.copyWith(loading: true));
    final items = await _manager.reconcileWithDisk();
    final storage = await _manager.storageStats();
    if (isClosed) return;
    emit(
      state.copyWith(
        items: items,
        loading: false,
        availableGb: storage.availableGb,
        totalGb: storage.totalGb,
        storageKnown: storage.known,
      ),
    );
  }

  Future<String?> enqueueMovieDownload({
    required String streamId,
    required String name,
    required String streamIcon,
    required String videoUrl,
    required String containerExtension,
  }) async {
    if (_manager.isAlreadyDownloaded(streamId) || state.isDownloaded(streamId)) {
      return 'already_download';
    }
    if (state.isDownloading(streamId)) return 'already_download';

    final active = Set<String>.from(state.activeStreamIds)..add(streamId);
    final progress = Map<String, double>.from(state.progressByStreamId)
      ..[streamId] = 0;
    emit(state.copyWith(activeStreamIds: active, progressByStreamId: progress));

    try {
      await _manager.downloadMovie(
        streamId: streamId,
        name: name,
        streamIcon: streamIcon,
        videoUrl: videoUrl,
        containerExtension: containerExtension,
        onProgress: (p) {
          if (isClosed) return;
          final next = Map<String, double>.from(state.progressByStreamId)
            ..[streamId] = p;
          emit(state.copyWith(progressByStreamId: next));
        },
      );
      await refresh();
      final activeDone = Set<String>.from(state.activeStreamIds)..remove(streamId);
      final progressDone = Map<String, double>.from(state.progressByStreamId)
        ..remove(streamId);
      emit(
        state.copyWith(
          activeStreamIds: activeDone,
          progressByStreamId: progressDone,
        ),
      );
      return null;
    } on DioException catch (e) {
      final activeDone = Set<String>.from(state.activeStreamIds)..remove(streamId);
      final progressDone = Map<String, double>.from(state.progressByStreamId)
        ..remove(streamId);
      emit(
        state.copyWith(
          activeStreamIds: activeDone,
          progressByStreamId: progressDone,
        ),
      );
      if (CancelToken.isCancel(e)) return 'download_cancelled';
      return 'download_failed';
    } catch (e) {
      final activeDone = Set<String>.from(state.activeStreamIds)..remove(streamId);
      final progressDone = Map<String, double>.from(state.progressByStreamId)
        ..remove(streamId);
      emit(
        state.copyWith(
          activeStreamIds: activeDone,
          progressByStreamId: progressDone,
        ),
      );
      final msg = e.toString();
      if (msg.contains('already_download')) return 'already_download';
      return 'download_failed';
    }
  }

  Future<void> cancelDownload(String streamId) async {
    await _manager.cancel(streamId);
    final active = Set<String>.from(state.activeStreamIds)..remove(streamId);
    final progress = Map<String, double>.from(state.progressByStreamId)
      ..remove(streamId);
    emit(state.copyWith(activeStreamIds: active, progressByStreamId: progress));
  }

  Future<void> deleteItem(DownloadedMovie item) async {
    await _manager.delete(item);
    await refresh();
  }

  String playablePath(DownloadedMovie item) {
    final path = item.localVideoPath;
    if (path.isEmpty) return '';
    if (path.startsWith('file:')) return path;
    return Uri.file(path, windows: Platform.isWindows).toString();
  }
}
