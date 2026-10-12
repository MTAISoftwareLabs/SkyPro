import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../repository/api/api.dart';
import '../../../../repository/locale/catalog_disk_cache.dart';
import '../../../../repository/locale/catalog_fingerprint.dart';
import '../../../../repository/models/category.dart';
import '../../../../repository/models/user.dart';

part 'movie_caty_event.dart';
part 'movie_caty_state.dart';

class MovieCatyBloc extends Bloc<MovieCatyEvent, MovieCatyState> {
  final IpTvApi api;

  MovieCatyBloc(this.api) : super(MovieCatyInitial()) {
    on<ResetMovieCatySession>((event, emit) async {
      emit(MovieCatyInitial());
    });
    on<HydrateMovieCategories>((event, emit) async {
      if (event.categories.isEmpty) return;
      emit(MovieCatySuccess(event.categories));
    });
    on<GetMovieCategories>((event, emit) async {
      final prev = state;
      final keepUi =
          prev is MovieCatySuccess && prev.categories.isNotEmpty;
      if (!keepUi) {
        emit(MovieCatyLoading());
      }

      var result = await api.getCategories(
        "get_vod_categories",
        userOverride: event.user,
      );
      if (result.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        result = await api.getCategories(
          "get_vod_categories",
          userOverride: event.user,
        );
      }

      if (result.isEmpty && keepUi) return;
      emit(MovieCatySuccess(result));
      if (result.isNotEmpty) {
        final user = event.user ?? LocaleApi.getUserSync();
        final userKey = _userKey(user);
        if (userKey.isNotEmpty) {
          final fp = CatalogFingerprint.categories(result);
          final prevFp = await CatalogDiskCache.getFingerprint(
            userKey,
            '${CatalogDiskCache.kindMovies}_cats',
          );
          if (prevFp != fp) {
            CatalogDiskCache.writeCategories(
              userKey,
              CatalogDiskCache.kindMovies,
              result,
            );
          }
        }
      }
    });
  }

  static String _userKey(UserModel? user) {
    if (user == null) return '';
    return '${user.serverInfo?.serverUrl ?? ''}_${user.userInfo?.username ?? ''}';
  }
}
