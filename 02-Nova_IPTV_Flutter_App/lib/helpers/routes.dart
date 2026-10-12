part of 'helpers.dart';

const String screenSplash = "/";
const String screenLicenseInvalid = "/license-invalid";
const String screenEntry = "/entry";
const String screenHomeBootstrap = "/home-bootstrap";
const String screenWelcome = "/welcome";
const String screenRegister = "/register";
const String screenSettings = "/settings";
const String screenManageAccounts = "/manage-accounts";
const String screenFavourite = "/favourite";
const String screenCatchUp = "/catchup";
const String screenDownloads = "/downloads";
const String screenNotifications = "/notifications";
const String screenAddPlaylist = "/add-playlist";
const String screenPlaylistCode = "/playlist-code";
const String screenLiveCategories = "/categories-live";
const String screenMovieCategories = "/categories-movie";
const String screenSeriesCategories = "/categories-series";

/// انتقال صفحات الدخول والرئيسية والأقسام — fade قصير على TV/stick.
Transition get kEntryPageTransition => Transition.fadeIn;

Duration get kEntryPageTransitionDuration {
  if (AppPerf.instance.isTelevisionLike || AppPerf.instance.isLite) {
    return const Duration(milliseconds: 200);
  }
  return const Duration(milliseconds: 280);
}
