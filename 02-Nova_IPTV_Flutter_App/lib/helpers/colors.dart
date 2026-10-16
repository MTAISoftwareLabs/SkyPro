part of 'helpers.dart';

// SkyPro official brand palette: Cinematic Neon Blue & Luxury Platinum Silver
const Color kSkyProBlack = Color(0xFF030712);
const Color kSkyProBlue = Color(0xFF00ABFB);
const Color kSkyProNeonBlue = Color(0xFF00D2FF);
const Color kSkyProDeepBlue = Color(0xFF0052D9);
const Color kSkyProSilver = Color(0xFFE2E8F0);
const Color kSkyProSilverBright = Color(0xFFF8FAFC);
const Color kSkyProSilverMuted = Color(0xFF94A3B8);

/// SkyPro accent color.
Color get kColorPrimary => kSkyProBlue;

/// Keep the accent consistent with the supplied SkyPro logo.
Color get kColorPrimaryDark => kSkyProDeepBlue;

/// لون التركيز (Focus) عند التنقل بالريموت — نفس لون الثيم النشط.
Color get kColorFocus => kSkyProNeonBlue;

/// لون العنصر المختار/النشط في متصفح البث (فئة / قناة قيد التشغيل).
Color get kLiveBrowserSelectedColor => kSkyProNeonBlue;

Color get kLiveBrowserSelectedFill =>
    kLiveBrowserSelectedColor.withValues(alpha: 0.18);

Color get kLiveBrowserSelectedBorder =>
    kLiveBrowserSelectedColor.withValues(alpha: 0.85);

// Black surfaces; subtle differences are reserved for elevation only.
const Color kColorBack = kSkyProBlack;
const Color kColorBackDark = Color(0xFF060913);

const Color kColorCardLight = Color(0xFF0F172A);
const Color kColorCardDark = Color(0xFF090D16);
const Color kColorCardDarkness = kSkyProBlack;

/// App bars use the pure-black brand surface.
const Color kColorAppBar = kSkyProBlack;

const Color kColorHint = kSkyProSilverMuted;
const Color kColorHintGrey = kSkyProSilverMuted;
const Color kColorFontLight = kSkyProSilver;

/// The SkyPro background stays deep obsidian with subtle cosmic depth.
LinearGradient get kDecorBackgroundGradient => const LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF02040A), Color(0xFF050B14), Color(0xFF02040A)],
  stops: [0.0, 0.5, 1.0],
);

/// خلفية الشاشات: تدرج داكن ثابت. صورة `bg_main` تُستخدم فقط في [WelcomeScreen].
BoxDecoration get kDecorBackground {
  return BoxDecoration(gradient: kDecorBackgroundGradient);
}

BoxDecoration get kDecorIconCircle => BoxDecoration(
  shape: BoxShape.circle,
  gradient: LinearGradient(
    colors: [kSkyProDeepBlue, kSkyProNeonBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
);
