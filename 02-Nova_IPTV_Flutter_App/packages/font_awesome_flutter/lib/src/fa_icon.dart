// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';

/// Creates an Icon Widget that works for non-material Icons, such as the
/// Font Awesome Icons.
///
/// The default [Icon] Widget from the Material package assumes all Icons are
/// square in size and wraps all Icons in a square SizedBox Widget. Icons from
/// the FontAwesome package are often wider than they are tall, which causes
/// alignment and cutoff issues.
///
/// This Widget does not wrap the icons in a fixed square box, which allows the
/// icons to render based on their size.
///
/// This is basically a copy of flutter's original `Icon` widget, but with the
/// `SizedBox` and `Center` widgets removed.
///
/// Original source code:
/// https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/icon.dart
class FaIcon extends Icon {
  /// Creates an icon.
  const FaIcon(
    super.icon, {
    super.key,
    super.size,
    super.fill,
    super.weight,
    super.grade,
    super.opticalSize,
    super.color,
    super.shadows,
    super.semanticLabel,
    super.textDirection,
    super.applyTextScaling,
    super.blendMode,
    super.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    assert(this.textDirection != null || debugCheckHasDirectionality(context));
    final TextDirection textDirection =
        this.textDirection ?? Directionality.of(context);

    final IconThemeData iconTheme = IconTheme.of(context);

    final bool applyTextScaling =
        this.applyTextScaling ?? iconTheme.applyTextScaling ?? false;

    final double tentativeIconSize = size ?? iconTheme.size ?? kDefaultFontSize;

    final double iconSize = applyTextScaling
        ? MediaQuery.textScalerOf(context).scale(tentativeIconSize)
        : tentativeIconSize;

    final double? iconFill = fill ?? iconTheme.fill;

    final double? iconWeight = weight ?? iconTheme.weight;

    final double? iconGrade = grade ?? iconTheme.grade;

    final double? iconOpticalSize = opticalSize ?? iconTheme.opticalSize;

    final List<Shadow>? iconShadows = shadows ?? iconTheme.shadows;

    final IconData? icon = this.icon;
    if (icon == null) {
      return Semantics(
        label: semanticLabel,
        child: SizedBox(width: iconSize, height: iconSize),
      );
    }

    final double iconOpacity = iconTheme.opacity ?? 1.0;
    Color? iconColor = color ?? iconTheme.color!;
    Paint? foreground;
    if (iconOpacity != 1.0) {
      iconColor = iconColor.withValues(alpha: iconColor.a * iconOpacity);
    }
    if (blendMode != null) {
      foreground = Paint()
        ..blendMode = blendMode!
        ..color = iconColor;
      // Cannot provide both a color and a foreground.
      iconColor = null;
    }

    final TextStyle fontStyle = TextStyle(
      fontVariations: <FontVariation>[
        if (iconFill != null) FontVariation('FILL', iconFill),
        if (iconWeight != null) FontVariation('wght', iconWeight),
        if (iconGrade != null) FontVariation('GRAD', iconGrade),
        if (iconOpticalSize != null) FontVariation('opsz', iconOpticalSize),
      ],
      inherit: false,
      color: iconColor,
      fontSize: iconSize,
      fontFamily: icon.fontFamily,
      fontWeight: fontWeight,
      package: icon.fontPackage,
      fontFamilyFallback: icon.fontFamilyFallback,
      shadows: iconShadows,
      height:
          1.0, // Makes sure the font's body is vertically centered within the iconSize x iconSize square.
      leadingDistribution: TextLeadingDistribution.even,
      foreground: foreground,
    );

    Widget iconWidget = RichText(
      overflow: TextOverflow.visible, // Never clip.
      textDirection:
          textDirection, // Since we already fetched it for the assert...
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: fontStyle,
      ),
    );

    if (icon.matchTextDirection) {
      switch (textDirection) {
        case TextDirection.rtl:
          iconWidget = Transform(
            transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1),
            alignment: Alignment.center,
            transformHitTests: false,
            child: iconWidget,
          );
        case TextDirection.ltr:
          break;
      }
    }

    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(child: iconWidget),
    );
  }
}
