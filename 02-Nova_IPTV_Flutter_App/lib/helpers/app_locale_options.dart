part of 'helpers.dart';

/// لغة واجهة التطبيق (الاسم الأصلي + علم الدولة).
class AppUiLanguage {
  const AppUiLanguage({
    required this.code,
    required this.nativeName,
    required this.flagEmoji,
  });

  final String code;
  final String nativeName;
  final String flagEmoji;
}

/// اللغات المدعومة في واجهة التطبيق.
const List<AppUiLanguage> kAppUiLanguages = [
  AppUiLanguage(code: 'ar', nativeName: 'العربية', flagEmoji: '🇸🇦'),
  AppUiLanguage(code: 'en', nativeName: 'English', flagEmoji: '🇬🇧'),
  AppUiLanguage(code: 'fr', nativeName: 'Français', flagEmoji: '🇫🇷'),
  AppUiLanguage(code: 'es', nativeName: 'Español', flagEmoji: '🇪🇸'),
  AppUiLanguage(code: 'zh', nativeName: '中文', flagEmoji: '🇨🇳'),
  AppUiLanguage(code: 'it', nativeName: 'Italiano', flagEmoji: '🇮🇹'),
  AppUiLanguage(code: 'fa', nativeName: 'فارسی', flagEmoji: '🇮🇷'),
];

AppUiLanguage? appUiLanguageByCode(String? code) {
  final c = (code ?? '').trim().toLowerCase();
  if (c.isEmpty) return null;
  for (final lang in kAppUiLanguages) {
    if (lang.code == c) return lang;
  }
  return null;
}

String currentAppLanguageCode() {
  return Get.locale?.languageCode ??
      GetStorage().read(kStorageLocale) as String? ??
      'en';
}

AppUiLanguage currentAppUiLanguage() {
  return appUiLanguageByCode(currentAppLanguageCode()) ?? kAppUiLanguages[1];
}

/// أيقونة علم اللغة (إيموجي داخل إطار دائري خفيف).
class AppLangFlagIcon extends StatelessWidget {
  const AppLangFlagIcon({
    super.key,
    required this.code,
    this.size = 28,
  });

  final String code;
  final double size;

  static String flagEmojiFor(String code) {
    return appUiLanguageByCode(code)?.flagEmoji ?? '🌐';
  }

  @override
  Widget build(BuildContext context) {
    final emoji = flagEmojiFor(code);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Center(
          child: Text(
            emoji,
            style: TextStyle(fontSize: size * 0.56, height: 1),
          ),
        ),
      ),
    );
  }
}
