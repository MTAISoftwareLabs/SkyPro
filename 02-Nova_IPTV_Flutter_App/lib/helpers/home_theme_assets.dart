part of 'helpers.dart';

/// Home screen theme: colors come from [kColorPrimary], and only the main
/// background image is swapped. Other theme PNGs were unused and removed.
class HomeThemeAssets {
  final String? mainBackground;

  const HomeThemeAssets({this.mainBackground});
}

const Set<String> _allowedHomeThemes = <String>{
  'original',
  'netflix_red',
  'ramadan_gold',
  'sports_sky',
  'halloween_orange',
  'purple',
};

List<String> get allowedHomeThemes => _allowedHomeThemes.toList(growable: false);

const Map<String, HomeThemeAssets> homeThemeAssetsByKey =
    <String, HomeThemeAssets>{
  'original': HomeThemeAssets(),
  'netflix_red': HomeThemeAssets(
    mainBackground: 'assets/themes/netflix_red/bg_main.png',
  ),
  'ramadan_gold': HomeThemeAssets(
    mainBackground: 'assets/themes/ramadan_gold/bg_main.png',
  ),
  'sports_sky': HomeThemeAssets(
    mainBackground: 'assets/themes/sport/bg_main.png',
  ),
  'halloween_orange': HomeThemeAssets(
    mainBackground: 'assets/themes/hallowen/bg_main.png',
  ),
  'purple': HomeThemeAssets(
    mainBackground: 'assets/themes/purple/bg_main.png',
  ),
};

/// Reads active home theme from app settings stored during activation/login.
/// Safe fallback: unknown/missing values => `original`.
String getActiveHomeThemeKey() {
  final box = GetStorage();
  final v = box.read('home_theme');
  if (v is String && _allowedHomeThemes.contains(v)) return v;
  return 'original';
}

/// يزيد عند كل تغيير للثيم لإعادة بناء `MaterialApp` والألوان العامة فوراً.
final ValueNotifier<int> homeThemeRevision = ValueNotifier<int>(0);

void setActiveHomeThemeKey(String key) {
  if (_allowedHomeThemes.contains(key)) {
    GetStorage().write('home_theme', key);
    homeThemeRevision.value++;
  }
}

HomeThemeAssets getActiveHomeThemeAssets() {
  final key = getActiveHomeThemeKey();
  return homeThemeAssetsByKey[key] ?? homeThemeAssetsByKey['original']!;
}

/// Small helper to build a decoration with an optional background image.
/// If `backgroundAsset` is missing/empty => return `fallback` unchanged.
BoxDecoration buildDecorationWithOptionalImage({
  required BoxDecoration fallback,
  required String? backgroundAsset,
  BoxFit fit = BoxFit.cover,
}) {
  final asset = backgroundAsset?.trim();
  if (asset == null || asset.isEmpty) return fallback;

  return BoxDecoration(
    color: fallback.color,
    borderRadius: fallback.borderRadius ?? BorderRadius.zero,
    border: fallback.border,
    image: DecorationImage(
      image: AssetImage(asset),
      fit: fit,
    ),
  );
}
