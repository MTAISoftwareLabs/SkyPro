part of 'helpers.dart';

class MyThemApp {
  static TextStyle _sys(
    Color color,
    double size, {
    FontWeight weight = FontWeight.normal,
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: weight,
      fontFamily: 'Roboto',
    );
  }

  static TextTheme _systemTextTheme() {
    return TextTheme(
      displayLarge: _sys(kColorFontLight, 24.sp, weight: FontWeight.bold),
      displayMedium: _sys(kColorFontLight, 22.sp, weight: FontWeight.bold),
      displaySmall: _sys(kColorFontLight, 20.sp, weight: FontWeight.bold),
      headlineMedium: _sys(kColorFontLight, 18.sp, weight: FontWeight.bold),
      headlineSmall: _sys(kColorFontLight, 16.sp, weight: FontWeight.bold),
      titleLarge: _sys(kColorFontLight, 14.sp, weight: FontWeight.bold),
      titleMedium: _sys(kColorFontLight, 18.sp),
      titleSmall: _sys(kColorFontLight, 16.sp),
    );
  }

  static TextTheme _googleTextTheme() {
    return GoogleFonts.robotoTextTheme().copyWith(
      displayLarge: GoogleFonts.roboto(
        color: kColorFontLight,
        fontSize: 24.sp,
        fontWeight: FontWeight.bold,
      ),
      displayMedium: GoogleFonts.roboto(
        color: kColorFontLight,
        fontSize: 22.sp,
        fontWeight: FontWeight.bold,
      ),
      displaySmall: GoogleFonts.roboto(
        color: kColorFontLight,
        fontSize: 20.sp,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: GoogleFonts.roboto(
        color: kColorFontLight,
        fontSize: 18.sp,
        fontWeight: FontWeight.bold,
      ),
      headlineSmall: GoogleFonts.roboto(
        color: kColorFontLight,
        fontSize: 16.sp,
        fontWeight: FontWeight.bold,
      ),
      titleLarge: GoogleFonts.roboto(
        color: kColorFontLight,
        fontSize: 14.sp,
        fontWeight: FontWeight.bold,
      ),
      titleMedium: GoogleFonts.roboto(
        color: kColorFontLight,
        fontSize: 18.sp,
      ),
      titleSmall: GoogleFonts.roboto(color: kColorFontLight, fontSize: 16.sp),
    );
  }

  static ThemeData themeData(BuildContext context) {
    return ThemeData.dark().copyWith(
      colorScheme: ColorScheme.dark(
        primary: kColorPrimary,
        secondary: kColorPrimary,
        surface: kColorCardLight,
        onPrimary: Colors.black,
        onSurface: kColorFontLight,
      ),
      scaffoldBackgroundColor: kColorBack,
      canvasColor: kColorBackDark,
      primaryColor: kColorPrimary,
      focusColor: kColorFocus,
      hintColor: kColorHint,
      // أجهزة ضعيفة: خط النظام بدل تنزيل Google Fonts عند الإقلاع.
      textTheme: AppPerf.instance.useSystemFonts
          ? _systemTextTheme()
          : _googleTextTheme(),
    );
  }
}
