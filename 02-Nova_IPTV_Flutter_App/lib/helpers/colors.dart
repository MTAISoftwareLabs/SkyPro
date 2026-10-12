part of 'helpers.dart';

// ألوان الثيم الأصلي (ذهبي + أسود)
const Color _kOriginalPrimary = Color(0xFFF5C242);
const Color _kOriginalPrimaryDark = Color(0xFFC79A27);

/// لون التمييز الأساسي حسب ثيم الشاشة الرئيسية (من السيرفر).
Color get kColorPrimary {
  switch (getActiveHomeThemeKey()) {
    case 'netflix_red':
      return const Color(0xFFE53935);
    case 'ramadan_gold':
      return const Color(0xFF81C784);
    case 'sports_sky':
      return const Color(0xFF4FC3F7);
    case 'halloween_orange':
      return const Color(0xFFFF9800);
    case 'purple':
      return const Color(0xFFB026FF);
    default:
      return _kOriginalPrimary;
  }
}

/// درجة أغمق للتدرجات والعناصر الثانوية.
Color get kColorPrimaryDark {
  switch (getActiveHomeThemeKey()) {
    case 'netflix_red':
      return const Color(0xFFC62828);
    case 'ramadan_gold':
      return const Color(0xFF43A047);
    case 'sports_sky':
      return const Color(0xFF0288D1);
    case 'halloween_orange':
      return const Color(0xFFF57C00);
    case 'purple':
      return const Color(0xFF7B2CBF);
    default:
      return _kOriginalPrimaryDark;
  }
}

/// لون التركيز (Focus) عند التنقل بالريموت — نفس لون الثيم النشط.
Color get kColorFocus => kColorPrimary;

/// لون العنصر المختار/النشط في متصفح البث (فئة / قناة قيد التشغيل).
/// Sports Sky: أصفر (ذهبي) — متميز عن التركيز الأزرق. باقي الثيمات: أزرق فاتح.
Color get kLiveBrowserSelectedColor {
  if (getActiveHomeThemeKey() == 'sports_sky') {
    return _kOriginalPrimary;
  }
  return const Color(0xFF5EB3FF);
}

Color get kLiveBrowserSelectedFill =>
    kLiveBrowserSelectedColor.withValues(alpha: 0.15);

Color get kLiveBrowserSelectedBorder =>
    kLiveBrowserSelectedColor.withValues(alpha: 0.8);

// خلفية كحلية داكنة (ليست أسود صافياً) — الثيم الأصلي
const Color kColorBack = Color(0xFF0A0F1C);
const Color kColorBackDark = Color(0xFF151C2E);

// ألوان الكروت بدرجات كحلية متوافقة مع الخلفية
const Color kColorCardLight = Color(0xFF1C2538);
const Color kColorCardDark = Color(0xFF141B2C);
const Color kColorCardDarkness = Color(0xFF0A0F1C);

/// الشريط العلوي (شعار + اسم التطبيق + بحث) — نفس أعلى تدرج الخلفية، ليس أسود.
const Color kColorAppBar = Color(0xFF18233A);

// ألوان النصوص الثانوية / الـ Hint
const Color kColorHint = Color(0xFF8A8D98);
const Color kColorHintGrey = Color(0xFF757575);
const Color kColorFontLight = Color(0xFFFFFFFF);

/// تدرج الخلفية الافتراضي: كحلي من الأعلى نحو الأسفل.
LinearGradient get kDecorBackgroundGradient => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF18233A),
        Color(0xFF0E1628),
        Color(0xFF070B16),
      ],
      stops: [0.0, 0.48, 1.0],
    );

/// خلفية الشاشات: تدرج داكن ثابت. صورة `bg_main` تُستخدم فقط في [WelcomeScreen].
BoxDecoration get kDecorBackground {
  return BoxDecoration(gradient: kDecorBackgroundGradient);
}

BoxDecoration get kDecorIconCircle => BoxDecoration(
  shape: BoxShape.circle,
  gradient: LinearGradient(
    colors: [kColorPrimaryDark, kColorPrimary],
  ),
);
