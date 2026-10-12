import 'package:get_storage/get_storage.dart';

import '../../core/opensubtitles_config.dart';
import '../../core/tmdb_config.dart';

const String kPanelTmdbApiKeyStorage = 'panel_tmdb_api_key';
const String kPanelOpensubtitlesApiKeyStorage = 'panel_opensubtitles_api_key';
const String kPanelOpensubtitlesUsernameStorage =
    'panel_opensubtitles_username';
const String kPanelOpensubtitlesPasswordStorage =
    'panel_opensubtitles_password';

/// TMDB API key from admin panel (GetStorage), with local fallback.
String get effectiveTmdbApiKey {
  final remote =
      (GetStorage().read(kPanelTmdbApiKeyStorage) as String?)?.trim();
  if (remote != null && remote.isNotEmpty) return remote;
  return kTmdbApiKeyFallback;
}

/// OpenSubtitles API key (Api-Key header) from admin panel.
String get effectiveOpensubtitlesApiKey {
  final remote =
      (GetStorage().read(kPanelOpensubtitlesApiKeyStorage) as String?)?.trim();
  if (remote != null && remote.isNotEmpty) return remote;
  return kOpensubtitlesApiKeyFallback;
}

String get effectiveOpensubtitlesUsername {
  final remote =
      (GetStorage().read(kPanelOpensubtitlesUsernameStorage) as String?)
          ?.trim();
  if (remote != null && remote.isNotEmpty) return remote;
  return kOpensubtitlesUsernameFallback;
}

String get effectiveOpensubtitlesPassword {
  final remote =
      (GetStorage().read(kPanelOpensubtitlesPasswordStorage) as String?)
          ?.trim();
  if (remote != null && remote.isNotEmpty) return remote;
  return kOpensubtitlesPasswordFallback;
}

Future<void> persistPanelApiKeysFromResponse(Map<String, dynamic> raw) async {
  final box = GetStorage();
  final tmdb = (raw['tmdb_api_key'] as String? ?? '').trim();
  final osApiKey =
      (raw['opensubtitles_api_key'] as String? ?? '').trim();
  final osUsername =
      (raw['opensubtitles_username'] as String? ?? '').trim();
  final osPassword =
      (raw['opensubtitles_password'] as String? ?? '').trim();

  if (tmdb.isNotEmpty) {
    await box.write(kPanelTmdbApiKeyStorage, tmdb);
  }
  if (osApiKey.isNotEmpty) {
    await box.write(kPanelOpensubtitlesApiKeyStorage, osApiKey);
  }
  if (osUsername.isNotEmpty) {
    await box.write(kPanelOpensubtitlesUsernameStorage, osUsername);
  }
  if (osPassword.isNotEmpty) {
    await box.write(kPanelOpensubtitlesPasswordStorage, osPassword);
  }
}
