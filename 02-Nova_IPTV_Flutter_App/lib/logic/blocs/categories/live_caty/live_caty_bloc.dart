import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../repository/api/api.dart';
import '../../../../repository/locale/catalog_disk_cache.dart';
import '../../../../repository/locale/catalog_fingerprint.dart';
import '../../../../repository/models/category.dart';
import '../../../../repository/models/user.dart';

part 'live_caty_event.dart';
part 'live_caty_state.dart';

class LiveCatyBloc extends Bloc<LiveCatyEvent, LiveCatyState> {
  final IpTvApi api;

  LiveCatyBloc(this.api) : super(LiveCatyInitial()) {
    on<ResetLiveCatySession>((event, emit) async {
      emit(LiveCatyInitial());
    });
    on<HydrateLiveCategories>((event, emit) async {
      if (event.categories.isEmpty) return;
      emit(LiveCatySuccess(event.categories));
    });
    on<GetLiveCategories>((event, emit) async {
      final prev = state;
      final keepUi = prev is LiveCatySuccess && prev.categories.isNotEmpty;
      if (!keepUi) {
        emit(LiveCatyLoading());
      }

      final result = await api.getCategories(
        "get_live_categories",
        userOverride: event.user,
      );
      if (result.isEmpty && keepUi) return;
      emit(LiveCatySuccess(result));
      if (result.isNotEmpty) {
        final user = event.user ?? LocaleApi.getUserSync();
        final userKey = _userKey(user);
        if (userKey.isNotEmpty) {
          final fp = CatalogFingerprint.categories(result);
          final prevFp = await CatalogDiskCache.getFingerprint(
            userKey,
            '${CatalogDiskCache.kindLive}_cats',
          );
          if (prevFp != fp) {
            CatalogDiskCache.writeCategories(
              userKey,
              CatalogDiskCache.kindLive,
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
