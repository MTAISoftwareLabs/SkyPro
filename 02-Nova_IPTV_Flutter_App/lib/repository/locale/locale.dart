part of '../api/api.dart';

class LocaleApi {
  static Future<bool> saveUser(UserModel user) async {
    try {
      await locale.write("user", user.toJson());
      final exp = user.userInfo?.expDate?.trim();
      if (exp != null && exp.isNotEmpty && exp != 'null') {
        await GetStorage().write('cached_iptv_exp_date', exp);
      }
      RuntimeSeal.touchQuiet();
      return true;
    } catch (e) {
      debugPrint("Error save User: $e");
      return false;
    }
  }

  static Future<UserModel?> getUser() async {
    try {
      RuntimeSeal.touchQuiet();
      return getUserSync();
    } catch (e) {
      debugPrint("Error save User: $e");
      return null;
    }
  }

  static UserModel? getUserSync() {
    try {
      final user = locale.read("user");

      if (user is Map) {
        final map = Map<String, dynamic>.from(user);
        final serverInfo =
            map['server_info'] is Map
                ? Map<String, dynamic>.from(map['server_info'] as Map)
                : <String, dynamic>{};
        final domain =
            (serverInfo['server_url'] ?? map['server_url'] ?? '').toString();
        return UserModel.fromJson(map, domain);
      }
      return null;
    } catch (e) {
      debugPrint("Error read User: $e");
      return null;
    }
  }

  static Future<bool> logOut() async {
    try {
      await locale.remove("user");
      await locale.remove("saved_login_username");
      await locale.remove("saved_login_password");
      await GetStorage().remove('login_method');
      await GetStorage().remove('cached_iptv_exp_date');
      // بعد تسجيل الخروج لا نُبقي بيانات الدخول التلقائي من playlist
      await GetStorage().remove("activation_auto_username");
      await GetStorage().remove("activation_auto_password");
      await GetStorage().remove("activation_auto_domain");
      await GetStorage().remove("activation_auto_enabled");
      await GetStorage().remove("activation_domain");
      return true;
    } catch (e) {
      debugPrint("Error LogOut User: $e");
      return false;
    }
  }
}
