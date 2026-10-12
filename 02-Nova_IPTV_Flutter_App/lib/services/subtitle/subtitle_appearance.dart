import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

/// تفضيلات مظهر الترجمة (حجم / لون / خلفية) — تُحفظ محلياً وتُطبَّق على المشغّل.
class SubtitleAppearance {
  const SubtitleAppearance({
    required this.fontSize,
    required this.fontColor,
    required this.backgroundEnabled,
    required this.backgroundColor,
  });

  final double fontSize;
  final Color fontColor;
  final bool backgroundEnabled;
  final Color backgroundColor;

  static const double minFontSize = 12;
  static const double maxFontSize = 36;
  static const double defaultFontSize = 18;

  static const SubtitleAppearance defaults = SubtitleAppearance(
    fontSize: defaultFontSize,
    fontColor: Colors.white,
    backgroundEnabled: false,
    backgroundColor: Color(0x99000000),
  );

  /// لوحة ألوان النص (تُفتح من زر «المزيد»).
  static const List<Color> fontColorPalette = [
    Colors.white,
    Color(0xFFF5F5F5),
    Color(0xFFFFF59D),
    Color(0xFFFFEB3B),
    Color(0xFFFFD54F),
    Color(0xFFFFB74D),
    Color(0xFFFF8A65),
    Color(0xFFEF5350),
    Color(0xFF81D4FA),
    Color(0xFF4FC3F7),
    Color(0xFF29B6F6),
    Color(0xFF80CBC4),
    Color(0xFFA5D6A7),
    Color(0xFFCE93D8),
    Color(0xFFB39DDB),
    Color(0xFFF48FB1),
  ];

  /// لوحة ألوان الخلفية (شفافية مريحة للقراءة، ليست كلها أسود).
  static const List<Color> backgroundColorPalette = [
    Color(0x66000000),
    Color(0x99000000),
    Color(0xCC000000),
    Color(0x6637474F),
    Color(0x9937474F),
    Color(0x661A237E),
    Color(0x991A237E),
    Color(0x660D47A1),
    Color(0x990D47A1),
    Color(0x664A148C),
    Color(0x994A148C),
    Color(0x663E2723),
    Color(0x993E2723),
    Color(0x661B5E20),
    Color(0x991B5E20),
    Color(0x66B71C1C),
    Color(0x99B71C1C),
    Color(0x66FFFFFF),
  ];

  SubtitleAppearance copyWith({
    double? fontSize,
    Color? fontColor,
    bool? backgroundEnabled,
    Color? backgroundColor,
  }) {
    return SubtitleAppearance(
      fontSize: (fontSize ?? this.fontSize).clamp(minFontSize, maxFontSize),
      fontColor: fontColor ?? this.fontColor,
      backgroundEnabled: backgroundEnabled ?? this.backgroundEnabled,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }

  BetterPlayerSubtitlesConfiguration toBetterPlayerConfig({
    double bottomPadding = 28,
  }) {
    return BetterPlayerSubtitlesConfiguration(
      fontSize: fontSize,
      fontColor: fontColor,
      fontFamily: 'Cairo',
      outlineEnabled: true,
      outlineColor: Colors.black.withValues(alpha: 0.85),
      outlineSize: fontSize >= 24 ? 2.4 : 2.0,
      backgroundColor:
          backgroundEnabled ? backgroundColor : Colors.transparent,
      leftPadding: 14,
      rightPadding: 14,
      bottomPadding: bottomPadding,
      alignment: Alignment.center,
    );
  }

  /// خيارات libVLC لتأثير تقريبي على الترجمة الأصلية (VLC).
  List<String> toVlcFreetypeExtras() {
    final size = fontSize.round().clamp(12, 36);
    final fg = _vlcColorInt(fontColor);
    final extras = <String>[
      ':freetype-rel-fontsize=$size',
      ':freetype-color=$fg',
      ':freetype-bold=1',
    ];
    if (backgroundEnabled) {
      extras.addAll([
        ':freetype-background-opacity=${_vlcOpacity(backgroundColor)}',
        ':freetype-background-color=${_vlcColorInt(backgroundColor)}',
      ]);
    } else {
      extras.add(':freetype-background-opacity=0');
    }
    return extras;
  }

  static int _vlcColorInt(Color c) {
    // libVLC: 0xBBGGRR (بدون ألفا)
    final r = (c.r * 255).round() & 0xFF;
    final g = (c.g * 255).round() & 0xFF;
    final b = (c.b * 255).round() & 0xFF;
    return (b << 16) | (g << 8) | r;
  }

  static int _vlcOpacity(Color c) {
    return ((c.a * 255).round()).clamp(0, 255);
  }
}

class SubtitleAppearanceService {
  SubtitleAppearanceService._();
  static final SubtitleAppearanceService instance =
      SubtitleAppearanceService._();

  static const _kFontSize = 'subtitle_appearance_font_size';
  static const _kFontColor = 'subtitle_appearance_font_color';
  static const _kBgEnabled = 'subtitle_appearance_bg_enabled';
  static const _kBgColor = 'subtitle_appearance_bg_color';

  GetStorage get _box => GetStorage();

  SubtitleAppearance load() {
    final d = SubtitleAppearance.defaults;
    final sizeRaw = _box.read(_kFontSize);
    final size = sizeRaw is num ? sizeRaw.toDouble() : d.fontSize;
    final fontArgb = _readArgb(_kFontColor, d.fontColor);
    final bgArgb = _readArgb(_kBgColor, d.backgroundColor);
    final bgOn = _box.read(_kBgEnabled);
    return SubtitleAppearance(
      fontSize: size.clamp(
        SubtitleAppearance.minFontSize,
        SubtitleAppearance.maxFontSize,
      ),
      fontColor: Color(fontArgb),
      backgroundEnabled: bgOn is bool ? bgOn : d.backgroundEnabled,
      backgroundColor: Color(bgArgb),
    );
  }

  Future<void> save(SubtitleAppearance appearance) async {
    await _box.write(_kFontSize, appearance.fontSize);
    await _box.write(_kFontColor, appearance.fontColor.toARGB32());
    await _box.write(_kBgEnabled, appearance.backgroundEnabled);
    await _box.write(_kBgColor, appearance.backgroundColor.toARGB32());
  }

  int _readArgb(String key, Color fallback) {
    final raw = _box.read(key);
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return fallback.toARGB32();
  }
}
