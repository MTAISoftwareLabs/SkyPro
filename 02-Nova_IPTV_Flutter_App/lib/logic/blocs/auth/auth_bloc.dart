import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mehdi_iptv/core/runtime_seal.dart';
import 'package:mehdi_iptv/helpers/app_cache_clearer.dart';
import 'package:mehdi_iptv/repository/api/activation_api.dart';
import 'package:mehdi_iptv/repository/locale/saved_accounts.dart';
import 'package:mehdi_iptv/services/parental_control_service.dart';
import 'package:mehdi_iptv/repository/api/api.dart';
import 'package:mehdi_iptv/repository/models/user.dart';

import '../../../helpers/helpers.dart';

part 'auth_event.dart';
part 'auth_state.dart';

Future<void> _syncPanelLogin({
  required String username,
  required String password,
  String? serverHost,
  String? displayName,
}) async {
  await ActivationApi().syncDeviceLoginToPanel(
    username: username,
    password: password,
    serverHost: serverHost,
    displayName: displayName,
  );
}

void _applyLiveFormatFromUser(UserModel user) {
  syncXtreamLiveFormatFromLogin(user.userInfo?.allowedOutputFormats);
}

/// رفض الدخول إن كان السيرفر يرفض الحساب أو انتهت مدة الاشتراك.
bool _isXtreamLoginRejected(UserModel user) {
  return shouldBlockExpiredIptvSession(
    expDate: user.userInfo?.expDate,
    status: user.userInfo?.status,
    username: user.userInfo?.username,
    password: user.userInfo?.password,
  );
}

/// إن كان الرابط من نوع Xtream (يوزر/باسورد في الاستعلام)، نُرجع السيرفر الأساسي + الاعتمادات لاستخدام [player_api.php] مثل تسجيل الدخول اليدوي.
// يستخدم [parseXtreamCredentialsFromUrl] من helpers.dart

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthApi authApi;

  AuthBloc(this.authApi) : super(AuthInitial()) {
    on<AuthRegister>((event, emit) async {
      emit(AuthLoading());

      final user = await authApi
          .registerUser(
            event.username,
            event.password,
            event.domain,
            "test",
          )
          .timeout(
            const Duration(seconds: 35),
            onTimeout: () => null,
          );

      if (user != null) {
        // تأكيد إضافي: player_api صالح + اشتراك غير منتهٍ قبل أي حفظ/دخول.
        if (_isXtreamLoginRejected(user)) {
          emit(AuthFailed("could not login!!"));
          return;
        }
        await AppCacheClearer.clearApiAndDisk();
        final addingNew =
            GetStorage().read(kStorageAddingNewAccount) == true;
        final method =
            event.loginMethod.trim().isNotEmpty
                ? event.loginMethod.trim()
                : 'username_password';
        await GetStorage().write(kStorageLoginMethod, method);
        await GetStorage().remove(kStorageAddingNewAccount);
        await GetStorage().remove(kStorageSuppressPlaylistAutoLogin);
        final displayName =
            (event.displayName ?? '').trim().isNotEmpty
                ? event.displayName!.trim()
                : event.username.trim();
        // ثبّت اليوزر/الباس من الإدخال — بعض الـ API لا تُرجع الباس
        final apiServer =
            (user.serverInfo?.serverUrl ?? '').trim().isNotEmpty
                ? user.serverInfo!.serverUrl!.trim()
                : event.domain.trim();
        final ensured = UserModel(
          userInfo: UserInfo(
            username: event.username.trim().isNotEmpty
                ? event.username.trim()
                : (user.userInfo?.username ?? ''),
            password: event.password.trim().isNotEmpty
                ? event.password.trim()
                : (user.userInfo?.password ?? ''),
            message: user.userInfo?.message ?? '',
            auth: user.userInfo?.auth ?? '1',
            status: user.userInfo?.status ?? 'Active',
            expDate: user.userInfo?.expDate,
            isTrial: user.userInfo?.isTrial ?? '',
            activeCons: user.userInfo?.activeCons ?? '',
            createdAt: user.userInfo?.createdAt ?? '',
            maxConnections: user.userInfo?.maxConnections ?? '',
            allowedOutputFormats: user.userInfo?.allowedOutputFormats,
          ),
          serverInfo: ServerInfo(
            serverUrl: apiServer,
            url: user.serverInfo?.url ?? '',
            port: user.serverInfo?.port ?? '',
            httpsPort: user.serverInfo?.httpsPort ?? '',
            serverProtocol: user.serverInfo?.serverProtocol ?? '',
            rtmpPort: user.serverInfo?.rtmpPort ?? '',
            timezone: user.serverInfo?.timezone ?? '',
            timestampNow: user.serverInfo?.timestampNow ?? '',
            timeNow: user.serverInfo?.timeNow ?? '',
            process: user.serverInfo?.process ?? '',
          ),
        );
        if (_isXtreamLoginRejected(ensured)) {
          emit(AuthFailed("could not login!!"));
          return;
        }
        await LocaleApi.saveUser(ensured);
        await SavedAccountsRepository.upsertFromLogin(
          user: ensured,
          displayName: displayName,
          loginMethod: method,
          serverDomain: apiServer.isNotEmpty ? apiServer : event.domain,
          forceNewProfile: addingNew,
        );
        await SavedAccountsRepository.dedupeEquivalentAccounts();
        changeDeviceOrient();
        await Future.delayed(const Duration(milliseconds: 300));
        RuntimeSeal.touchQuiet();
        unawaited(_syncPanelLogin(
          username: event.username,
          password: event.password,
          serverHost: (event.serverHostForPanel ?? event.domain).trim(),
          displayName: displayName,
        ));
        _applyLiveFormatFromUser(ensured);
        emit(AuthSuccess(ensured));
      } else {
        // كل طرق الدخول (يدوي / كود / get.php): لا دخول ناعم بدون player_api صالح.
        emit(AuthFailed("could not login!!"));
      }
    });

    on<AuthGetUser>((event, emit) async {
      emit(AuthLoading());

      final localeUser = await LocaleApi.getUser();

      if (localeUser != null) {
        if (shouldBlockExpiredIptvSession(
          expDate: localeUser.userInfo?.expDate,
          status: localeUser.userInfo?.status,
          username: localeUser.userInfo?.username,
          password: localeUser.userInfo?.password,
        )) {
          await GetStorage().write(kStorageIptvServerExpiredKick, true);
          await GetStorage().write(kStorageSuppressPlaylistAutoLogin, true);
          await LocaleApi.logOut();
          emit(AuthFailed('subscription_expired'));
          return;
        }
        await SavedAccountsRepository.migrateCurrentUserIfNeeded();
        await SavedAccountsRepository.dedupeEquivalentAccounts();
        RuntimeSeal.touchQuiet();
        _applyLiveFormatFromUser(localeUser);
        emit(AuthSuccess(localeUser));
      } else {
        emit(AuthFailed("could not login!!"));
      }
    });

    on<AuthUsePlaylist>((event, emit) async {
      emit(AuthLoading());
      try {
      final url = event.playlistUrl.trim();
      if (url.isEmpty) {
        emit(AuthFailed("رابط القائمة غير صالح"));
        return;
      }
      // سيرفر فقط بدون اعتمادات: ليس قائمة M3U — يجب إدخال يوزر/باس أولاً
      if (isXtreamHostOnlyUrl(url)) {
        emit(AuthFailed("host_only_needs_credentials"));
        return;
      }
      IpTvApi.clearM3UCache();
      IpTvApi.clearApiCaches();
      await AppCacheClearer.clearApiAndDisk();

      final xtream = parseXtreamCredentialsFromUrl(url);
      if (xtream != null) {
        // روابط get.php مع يوزر/باسورد = Xtream (أفلام+مسلسلات+قنوات عبر player_api)
        var user = await authApi.registerUser(
          xtream.username,
          xtream.password,
          xtream.serverBase,
          'playlist_code',
        );
        if (user != null) {
          // احتفظ برابط السيرفر من الـ API إن وُجد — أدق من serverBase في الرابط
          final apiServer =
              (user.serverInfo?.serverUrl ?? '').trim().isNotEmpty
                  ? user.serverInfo!.serverUrl!.trim()
                  : xtream.serverBase;
          user = UserModel(
            userInfo: UserInfo(
              username: xtream.username,
              password: xtream.password,
              message: user.userInfo?.message ?? '',
              auth: user.userInfo?.auth ?? '1',
              status: user.userInfo?.status ?? 'Active',
              expDate: user.userInfo?.expDate,
              isTrial: user.userInfo?.isTrial ?? '',
              activeCons: user.userInfo?.activeCons ?? '',
              createdAt: user.userInfo?.createdAt ?? '',
              maxConnections: user.userInfo?.maxConnections ?? '',
              allowedOutputFormats: user.userInfo?.allowedOutputFormats,
            ),
            serverInfo: ServerInfo(
              serverUrl: apiServer,
              url: user.serverInfo?.url ?? '',
              port: user.serverInfo?.port ?? '',
              httpsPort: user.serverInfo?.httpsPort ?? '',
              serverProtocol: user.serverInfo?.serverProtocol ?? '',
              rtmpPort: user.serverInfo?.rtmpPort ?? '',
              timezone: user.serverInfo?.timezone ?? '',
              timestampNow: user.serverInfo?.timestampNow ?? '',
              timeNow: user.serverInfo?.timeNow ?? '',
              process: user.serverInfo?.process ?? '',
            ),
          );
          if (_isXtreamLoginRejected(user)) {
            emit(AuthFailed("could not login!!"));
            return;
          }
          await LocaleApi.saveUser(user);
        } else {
          // اعتمادات خاطئة / سيرفر مرفوض / اشتراك منتهٍ — لا دخول ناعم.
          emit(AuthFailed("could not login!!"));
          return;
        }
        await GetStorage().write(kStorageLoginMethod, 'playlist_code');
        final addingNew =
            GetStorage().read(kStorageAddingNewAccount) == true;
        await GetStorage().remove(kStorageAddingNewAccount);
        await GetStorage().remove(kStorageSuppressPlaylistAutoLogin);
        final display =
            (event.displayName ?? '').trim().isNotEmpty
                ? event.displayName!.trim()
                : xtream.username;
        final serverDomain =
            (user.userInfo?.username ?? '').trim().isNotEmpty
                ? (user.serverInfo?.serverUrl ?? xtream.serverBase)
                : url;
        await SavedAccountsRepository.upsertFromLogin(
          user: user,
          displayName: display,
          loginMethod: 'playlist_code',
          serverDomain: serverDomain,
          forceNewProfile: addingNew,
        );
        await SavedAccountsRepository.dedupeEquivalentAccounts();
        changeDeviceOrient();
        await Future.delayed(const Duration(milliseconds: 300));
        unawaited(_syncPanelLogin(
          username: xtream.username,
          password: xtream.password,
          serverHost: serverDomain.trim(),
          displayName: display,
        ));
        _applyLiveFormatFromUser(user);
        emit(AuthSuccess(user));
        return;
      }

      // رابط M3U حقيقي بدون يوزر/باسورد في الاستعلام — يجب أن يُحمَّل بنجاح.
      final playlistOk = await IpTvApi()
          .validatePlaylistUrl(url)
          .timeout(const Duration(seconds: 40), onTimeout: () => false);
      if (!playlistOk) {
        emit(AuthFailed("could not login!!"));
        return;
      }
      await GetStorage().write(kStorageLoginMethod, 'playlist_code');
      final addingNewPlaylist =
          GetStorage().read(kStorageAddingNewAccount) == true;
      await GetStorage().remove(kStorageAddingNewAccount);
      await GetStorage().remove(kStorageSuppressPlaylistAutoLogin);
      final user = UserModel(
        userInfo: UserInfo(
          username: '',
          password: '',
          message: '',
          auth: '1',
          status: 'Active',
          expDate: null,
          isTrial: '',
          activeCons: '',
          createdAt: '',
          maxConnections: '',
          allowedOutputFormats: null,
        ),
        serverInfo: ServerInfo(
          serverUrl: url,
          url: '',
          port: '',
          httpsPort: '',
          serverProtocol: '',
          rtmpPort: '',
          timezone: '',
          timestampNow: '',
          timeNow: '',
          process: '',
        ),
      );
      await LocaleApi.saveUser(user);
      final playlistName = (event.displayName ?? '').trim();
      await SavedAccountsRepository.upsertFromLogin(
        user: user,
        displayName: playlistName.isEmpty ? 'Playlist' : playlistName,
        loginMethod: 'playlist_code',
        serverDomain: url,
        forceNewProfile: addingNewPlaylist,
      );
      await SavedAccountsRepository.dedupeEquivalentAccounts();
      changeDeviceOrient();
      _applyLiveFormatFromUser(user);
      emit(AuthSuccess(user));
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('AuthUsePlaylist error: $e');
        }
        emit(AuthFailed("could not login!!"));
      }
    });

    on<AuthSwitchAccount>((event, emit) async {
      final account = SavedAccountsRepository.findById(event.accountId);
      if (account == null) {
        emit(AuthFailed("could not login!!"));
        return;
      }
      emit(AuthLoading());
      await AppCacheClearer.clearApiAndDisk();
      IpTvApi.clearM3UCache();
      IpTvApi.clearApiCaches();

      // قوائم الويب / M3U / playlist_code
      if (account.loginMethod == 'playlist_code' &&
          account.serverUrl.trim().isNotEmpty) {
        final url = account.serverUrl.trim();
        final savedUser = account.username.trim();
        final savedPass = account.password.trim();

        // Playlist code → Xtream: يُحفظ الـ host فقط + username/password.
        // لا نرفض host-only إذا كانت بيانات الاعتماد محفوظة في الحساب.
        if (isXtreamHostOnlyUrl(url)) {
          if (savedUser.isEmpty || savedPass.isEmpty) {
            emit(AuthFailed("host_only_needs_credentials"));
            return;
          }
          final loaded = await authApi.registerUser(
            savedUser,
            savedPass,
            url,
            'playlist_code',
          );
          if (loaded == null || _isXtreamLoginRejected(loaded)) {
            emit(AuthFailed("could not login!!"));
            return;
          }
          await LocaleApi.saveUser(loaded);
          await GetStorage().write(kStorageLoginMethod, 'playlist_code');
          await GetStorage().remove(kStorageAddingNewAccount);
          await GetStorage().remove(kStorageSuppressPlaylistAutoLogin);
          await SavedAccountsRepository.setActiveAccountId(account.id);
          await SavedAccountsRepository.upsertFromLogin(
            user: loaded,
            displayName: account.displayName,
            loginMethod: 'playlist_code',
            serverDomain: url,
          );
          changeDeviceOrient();
          await Future.delayed(const Duration(milliseconds: 300));
          _applyLiveFormatFromUser(loaded);
          emit(AuthSuccess(loaded));
          return;
        }

        late final UserModel user;
        final xtream = parseXtreamCredentialsFromUrl(url);
        if (xtream != null) {
          var loaded = await authApi.registerUser(
            xtream.username,
            xtream.password,
            xtream.serverBase,
            'playlist_code',
          );
          if (loaded != null) {
            final apiServer =
                (loaded.serverInfo?.serverUrl ?? '').trim().isNotEmpty
                    ? loaded.serverInfo!.serverUrl!.trim()
                    : xtream.serverBase;
            loaded = UserModel(
              userInfo: UserInfo(
                username: xtream.username,
                password: xtream.password,
                message: loaded.userInfo?.message ?? '',
                auth: loaded.userInfo?.auth ?? '1',
                status: loaded.userInfo?.status ?? 'Active',
                expDate: loaded.userInfo?.expDate,
                isTrial: loaded.userInfo?.isTrial ?? '',
                activeCons: loaded.userInfo?.activeCons ?? '',
                createdAt: loaded.userInfo?.createdAt ?? '',
                maxConnections: loaded.userInfo?.maxConnections ?? '',
                allowedOutputFormats: loaded.userInfo?.allowedOutputFormats,
              ),
              serverInfo: ServerInfo(
                serverUrl: apiServer,
                url: loaded.serverInfo?.url ?? '',
                port: loaded.serverInfo?.port ?? '',
                httpsPort: loaded.serverInfo?.httpsPort ?? '',
                serverProtocol: loaded.serverInfo?.serverProtocol ?? '',
                rtmpPort: loaded.serverInfo?.rtmpPort ?? '',
                timezone: loaded.serverInfo?.timezone ?? '',
                timestampNow: loaded.serverInfo?.timestampNow ?? '',
                timeNow: loaded.serverInfo?.timeNow ?? '',
                process: loaded.serverInfo?.process ?? '',
              ),
            );
            if (_isXtreamLoginRejected(loaded)) {
              emit(AuthFailed("could not login!!"));
              return;
            }
            user = loaded;
          } else {
            emit(AuthFailed("could not login!!"));
            return;
          }
        } else {
          final playlistOk = await IpTvApi().validatePlaylistUrl(url);
          if (!playlistOk) {
            emit(AuthFailed("could not login!!"));
            return;
          }
          user = UserModel(
            userInfo: UserInfo(
              username: '',
              password: '',
              message: '',
              auth: '1',
              status: 'Active',
              expDate: null,
              isTrial: '',
              activeCons: '',
              createdAt: '',
              maxConnections: '',
              allowedOutputFormats: null,
            ),
            serverInfo: ServerInfo(
              serverUrl: url,
              url: '',
              port: '',
              httpsPort: '',
              serverProtocol: '',
              rtmpPort: '',
              timezone: '',
              timestampNow: '',
              timeNow: '',
              process: '',
            ),
          );
        }

        await LocaleApi.saveUser(user);
        await GetStorage().write(kStorageLoginMethod, 'playlist_code');
        await GetStorage().remove(kStorageAddingNewAccount);
        await GetStorage().remove(kStorageSuppressPlaylistAutoLogin);
        await SavedAccountsRepository.setActiveAccountId(account.id);
        await SavedAccountsRepository.updateWebAccountSession(
          accountId: account.id,
          user: user,
          serverUrl: url,
        );
        changeDeviceOrient();
        await Future.delayed(const Duration(milliseconds: 300));
        _applyLiveFormatFromUser(user);
        emit(AuthSuccess(user));
        return;
      }

      final user = await authApi.registerUser(
        account.username,
        account.password,
        account.serverUrl,
        'switch',
      );
      if (user != null && !_isXtreamLoginRejected(user)) {
        await GetStorage().write(kStorageLoginMethod, account.loginMethod);
        await GetStorage().remove(kStorageAddingNewAccount);
        await SavedAccountsRepository.upsertFromLogin(
          user: user,
          displayName: account.displayName,
          loginMethod: account.loginMethod,
          serverDomain: account.serverUrl,
        );
        changeDeviceOrient();
        await Future.delayed(const Duration(milliseconds: 200));
        _applyLiveFormatFromUser(user);
        emit(AuthSuccess(user));
      } else {
        emit(AuthFailed("could not login!!"));
      }
    });

    on<AuthPrepareAddAccount>((event, emit) async {
      final box = GetStorage();
      await LocaleApi.logOut();
      await box.write(kStorageSuppressPlaylistAutoLogin, true);
      await box.remove('activation_auto_enabled');
      await box.remove('activation_auto_username');
      await box.remove('activation_auto_password');
      await box.remove('activation_auto_domain');
      await box.remove('activation_domain');
      ParentalControlService.instance.clearSessionAccess();
      IpTvApi.clearM3UCache();
      IpTvApi.clearApiCaches();
      emit(AuthInitial());
    });

    on<AuthClearSession>((event, emit) async {
      await LocaleApi.logOut();
      ParentalControlService.instance.clearSessionAccess();
      emit(AuthInitial());
    });

    on<AuthLogOut>((event, emit) async {
      // مباشرة قبل أي await حتى لا تبقى شاشة الدخول عالقة في landscape بعد المشغّل.
      changeDeviceOrientBack();
      final box = GetStorage();
      await box.remove(kStorageLoginMethod);
      await box.write(kStorageSuppressPlaylistAutoLogin, true);
      await box.remove('activation_auto_enabled');
      await box.remove('activation_auto_username');
      await box.remove('activation_auto_password');
      await box.remove('activation_auto_domain');
      await box.remove('activation_domain');
      await box.remove('activation_just_added_playlist');
      IpTvApi.clearM3UCache();
      IpTvApi.clearApiCaches();
      await AppCacheClearer.clearApiAndDisk();
      await LocaleApi.logOut();
      emit(AuthFailed("LogOut"));
    });
  }
}
