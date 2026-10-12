import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../repository/api/api.dart';
import '../../../../repository/locale/catalog_disk_cache.dart';
import '../../../../repository/locale/catalog_fingerprint.dart';
import '../../../../repository/models/category.dart';
import '../../../../repository/models/user.dart';

part 'series_caty_event.dart';
part 'series_caty_state.dart';

class SeriesCatyBloc extends Bloc<SeriesCatyEvent, SeriesCatyState> {
  final IpTvApi api;
  SeriesCatyBloc(this.api) : super(SeriesCatyInitial()) {
    on<ResetSeriesCatySession>((event, emit) async {
      emit(SeriesCatyInitial());
    });
    on<HydrateSeriesCategories>((event, emit) async {
      if (event.categories.isEmpty) return;
      emit(SeriesCatySuccess(event.categories));
    });
    on<GetSeriesCategories>((event, emit) async {
      final prev = state;
      final keepUi =
          prev is SeriesCatySuccess && prev.categories.isNotEmpty;
      // لا تمسح قائمة الفئات المعروضة أثناء إعادة الجلب.
      if (!keepUi) {
        emit(SeriesCatyLoading());
      }

      var result = await api.getCategories(
        "get_series_categories",
        userOverride: event.user,
      );
      if (result.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        result = await api.getCategories(
          "get_series_categories",
          userOverride: event.user,
        );
      }

      // لا تستبدل فئات ناجحة بنتيجة فارغة مؤقتة.
      if (result.isEmpty && keepUi) return;
      // لا تثبت Success فارغ إن أمكن الإبقاء على Loading لإعادة المحاولة من الشاشة
      if (result.isEmpty && !keepUi) {
        emit(SeriesCatySuccess(const []));
        return;
      }
      emit(SeriesCatySuccess(result));
      if (result.isNotEmpty) {
        final user = event.user ?? LocaleApi.getUserSync();
        final userKey = _userKey(user);
        if (userKey.isNotEmpty) {
          final fp = CatalogFingerprint.categories(result);
          final prevFp = await CatalogDiskCache.getFingerprint(
            userKey,
            '${CatalogDiskCache.kindSeries}_cats',
          );
          if (prevFp != fp) {
            CatalogDiskCache.writeCategories(
              userKey,
              CatalogDiskCache.kindSeries,
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
