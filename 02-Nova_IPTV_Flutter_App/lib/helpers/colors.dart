part of 'helpers.dart';

// SkyPro brand palette.
const Color kSkyProBlack = Color(0xFF000000);
const Color kSkyProBlue = Color(0xFF007BFF);
const Color kSkyProSilver = Color(0xFFE0E0E0);

/// SkyPro accent color.
Color get kColorPrimary => kSkyProBlue;

/// Keep the accent consistent with the supplied SkyPro logo.
Color get kColorPrimaryDark => kSkyProBlue;

/// لون التركيز (Focus) عند التنقل بالريموت — نفس لون الثيم النشط.
Color get kColorFocus => kColorPrimary;

/// لون العنصر المختار/النشط في متصفح البث (فئة / قناة قيد التشغيل).
/// Selected live-browser items use the SkyPro accent.
Color get kLiveBrowserSelectedColor => kSkyProBlue;

Color get kLiveBrowserSelectedFill =>
    kLiveBrowserSelectedColor.withValues(alpha: 0.15);

Color get kLiveBrowserSelectedBorder =>
    kLiveBrowserSelectedColor.withValues(alpha: 0.8);

// Black surfaces; subtle differences are reserved for elevation only.
const Color kColorBack = kSkyProBlack;
const Color kColorBackDark = Color(0xFF080808);

const Color kColorCardLight = Color(0xFF101010);
const Color kColorCardDark = Color(0xFF080808);
const Color kColorCardDarkness = kSkyProBlack;

/// App bars use the pure-black brand surface.
const Color kColorAppBar = kSkyProBlack;

const Color kColorHint = kSkyProSilver;
const Color kColorHintGrey = kSkyProSilver;
const Color kColorFontLight = kSkyProSilver;

/// The SkyPro background stays pure black.
LinearGradient get kDecorBackgroundGradient => const LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kSkyProBlack, kSkyProBlack, kSkyProBlack],
  stops: [0.0, 0.48, 1.0],
);

/// خلفية الشاشات: تدرج داكن ثابت. صورة `bg_main` تُستخدم فقط في [WelcomeScreen].
BoxDecoration get kDecorBackground {
  return BoxDecoration(gradient: kDecorBackgroundGradient);
}

BoxDecoration get kDecorIconCircle => BoxDecoration(
  shape: BoxShape.circle,
  gradient: LinearGradient(colors: [kColorPrimaryDark, kColorPrimary]),
);
