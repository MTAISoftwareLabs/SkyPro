import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/cupertino.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mehdi_iptv/core/runtime_seal.dart';

import '../../../helpers/helpers.dart';

part 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit()
      : super(
          SettingsState(
            isDemo: GetStorage().read(kStorageDemoSession) == true,
          ),
        );

  void updateStatusAccount(bool isDemo) {
    changeDeviceOrient();
    GetStorage().write(kStorageDemoSession, isDemo);
    emit(state.copyWith(isDemo: isDemo));
  }

  void getSettingsCode() async {
    try {
      RuntimeSeal.touchQuiet();
    } catch (e) {
      debugPrint("Error: $e");
    }
  }
}
