part of 'auth_bloc.dart';

@immutable
abstract class AuthEvent {}

class AuthRegister extends AuthEvent {
  final String username;
  final String password;
  final String domain;
  final String? displayName;
  final String? serverHostForPanel;
  /// `username_password` (افتراضي) أو `playlist_code` عند الدخول من كود التفعيل.
  final String loginMethod;

  AuthRegister(
    this.username,
    this.password,
    this.domain, {
    this.displayName,
    this.serverHostForPanel,
    this.loginMethod = 'username_password',
  });
}

class AuthGetUser extends AuthEvent {}

class AuthLogOut extends AuthEvent {}

/// تعليق الجلسة الحالية لإضافة حساب جديد دون مسح الحسابات المحفوظة.
class AuthPrepareAddAccount extends AuthEvent {}

/// إنهاء الجلسة الحالية دون تسجيل خروج كامل ولا تبديل حساب تلقائي.
class AuthClearSession extends AuthEvent {}

/// تبديل إلى حساب محفوظ
class AuthSwitchAccount extends AuthEvent {
  final String accountId;

  AuthSwitchAccount(this.accountId);
}

/// تسجيل الدخول بوضع Playlist فقط (رابط M3U بدون username/password)
class AuthUsePlaylist extends AuthEvent {
  final String playlistUrl;
  final String? displayName;

  AuthUsePlaylist(this.playlistUrl, {this.displayName});
}
