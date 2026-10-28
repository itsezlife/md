import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// How an inline chip ([MD$Style.chip]) looks: a text run with an optional
/// leading glyph on a tinted, rounded fill.
///
/// Every field is optional; a `null` field takes the default named in its
/// documentation. The value is immutable and goes into
/// `MarkdownThemeData.chipStyle`.
@immutable
final class MarkdownChipStyle {
  /// Creates a chip style.
  const MarkdownChipStyle({
    this.color,
    this.background,
    this.mutedColor,
    this.mutedBackground,
    this.icon,
    this.iconSize,
    this.gap,
    this.radius,
    this.horizontalPadding,
    this.margin,
    this.fontWeight,
  });

  /// The colour of the chip's glyph and label. When `null`, the theme's link
  /// colour.
  final Color? color;

  /// The fill behind the chip. When `null`, [color] at 14% opacity.
  final Color? background;

  /// The glyph and label colour of a muted chip. When `null`, the text colour
  /// at 55% opacity.
  final Color? mutedColor;

  /// The fill behind a muted chip. When `null`, the muted colour at 10%
  /// opacity.
  final Color? mutedBackground;

  /// The leading glyph. When `null`, the chip has no glyph.
  final IconData? icon;

  /// The size of the glyph. When `null`, the text font size.
  final double? iconSize;

  /// The gap between the glyph and the label. When `null`, 0.3 em.
  final double? gap;

  /// The corner radius of the fill. When `null`, the ends are fully rounded.
  final double? radius;

  /// The room inside the fill, before the first run and after the label. Real
  /// layout: the text is pushed by it. When `null`, 0.3 em.
  final double? horizontalPadding;

  /// The room outside the fill on each side, which the text flows past. Real
  /// layout, like [horizontalPadding]. When `null`, 0.
  final double? margin;

  /// The weight of the chip's runs. When `null`, the weight of the
  /// surrounding text.
  final FontWeight? fontWeight;

  /// A copy with the given fields replaced; a `null` argument keeps the
  /// current value.
  MarkdownChipStyle copyWith({
    Color? color,
    Color? background,
    Color? mutedColor,
    Color? mutedBackground,
    IconData? icon,
    double? iconSize,
    double? gap,
    double? radius,
    double? horizontalPadding,
    double? margin,
    FontWeight? fontWeight,
  }) =>
      MarkdownChipStyle(
        color: color ?? this.color,
        background: background ?? this.background,
        mutedColor: mutedColor ?? this.mutedColor,
        mutedBackground: mutedBackground ?? this.mutedBackground,
        icon: icon ?? this.icon,
        iconSize: iconSize ?? this.iconSize,
        gap: gap ?? this.gap,
        radius: radius ?? this.radius,
        horizontalPadding: horizontalPadding ?? this.horizontalPadding,
        margin: margin ?? this.margin,
        fontWeight: fontWeight ?? this.fontWeight,
      );

  /// Linearly interpolates between [a] and [b]. The glyph switches at the
  /// midpoint. A `null` side is an empty style.
  static MarkdownChipStyle? lerp(
    MarkdownChipStyle? a,
    MarkdownChipStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null && b == null) return null;
    return MarkdownChipStyle(
      color: Color.lerp(a?.color, b?.color, t),
      background: Color.lerp(a?.background, b?.background, t),
      mutedColor: Color.lerp(a?.mutedColor, b?.mutedColor, t),
      mutedBackground: Color.lerp(a?.mutedBackground, b?.mutedBackground, t),
      icon: t < 0.5 ? a?.icon : b?.icon,
      iconSize: lerpDouble(a?.iconSize, b?.iconSize, t),
      gap: lerpDouble(a?.gap, b?.gap, t),
      radius: lerpDouble(a?.radius, b?.radius, t),
      horizontalPadding:
          lerpDouble(a?.horizontalPadding, b?.horizontalPadding, t),
      margin: lerpDouble(a?.margin, b?.margin, t),
      fontWeight: FontWeight.lerp(a?.fontWeight, b?.fontWeight, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownChipStyle &&
          other.color == color &&
          other.background == background &&
          other.mutedColor == mutedColor &&
          other.mutedBackground == mutedBackground &&
          other.icon == icon &&
          other.iconSize == iconSize &&
          other.gap == gap &&
          other.radius == radius &&
          other.horizontalPadding == horizontalPadding &&
          other.margin == margin &&
          other.fontWeight == fontWeight;

  @override
  int get hashCode => Object.hash(
        color,
        background,
        mutedColor,
        mutedBackground,
        icon,
        iconSize,
        gap,
        radius,
        horizontalPadding,
        margin,
        fontWeight,
      );

  @override
  String toString() => 'MarkdownChipStyle('
      'color: $color, background: $background, icon: $icon, '
      'iconSize: $iconSize, gap: $gap, radius: $radius, '
      'horizontalPadding: $horizontalPadding, margin: $margin, '
      'fontWeight: $fontWeight)';
}
