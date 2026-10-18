import 'dart:ui' show Canvas, Color, Rect, Size;

import 'package:flutter/foundation.dart' show Listenable;
import 'package:meta/meta.dart' show immutable;

/// What a [MarkdownInlineEmbed] is painted with besides its rectangle: the
/// colour of the text it sits in and the opacity of the text.
@immutable
final class MarkdownInlineEmbedPaintContext {
  /// Creates a context; the default is the embed's own colours, fully opaque.
  const MarkdownInlineEmbedPaintContext({this.tint, this.opacity = 1})
      : assert(opacity >= 0 && opacity <= 1, 'opacity must be within 0..1');

  /// The text colour, for an embed that is tinted by it (a template asset).
  /// Null leaves an embed in its own colours.
  final Color? tint;

  /// Opacity of the whole paint, 0 to 1.
  final double opacity;
}

/// What a body asks a [MarkdownInlineEmbedResolver] about: the target of an
/// image in the text, split the way the markup spells it.
///
/// For `![alt](unicode:1F44D)` the [scheme] is `unicode`, the [id] `1F44D` and
/// the [alt] the text shown where the embed cannot be (and copied, selected and
/// read aloud in its place).
@immutable
final class MarkdownInlineEmbedTarget {
  /// Creates a target.
  const MarkdownInlineEmbedTarget({
    required this.scheme,
    required this.id,
    required this.alt,
  });

  /// Splits the `scheme:id` [source] of an image, or returns null when
  /// [source] has no scheme (no colon, or something that is not a scheme
  /// before it) and so names nothing a resolver could know.
  static MarkdownInlineEmbedTarget? tryParse(String source, String alt) {
    final colon = source.indexOf(':');
    if (colon <= 0) return null;
    final scheme = source.substring(0, colon);
    if (!_scheme.hasMatch(scheme)) return null;
    return MarkdownInlineEmbedTarget(
      scheme: scheme,
      id: source.substring(colon + 1),
      alt: alt,
    );
  }

  // RFC 3986 `scheme`. Anything else before a colon is part of a path.
  static final RegExp _scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*$');

  /// The scheme of the target, without the colon.
  final String scheme;

  /// Everything after the scheme's colon.
  final String id;

  /// The alternative text of the reference.
  final String alt;

  @override
  bool operator ==(Object other) =>
      other is MarkdownInlineEmbedTarget &&
      other.scheme == scheme &&
      other.id == id &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(scheme, id, alt);

  @override
  String toString() => 'MarkdownInlineEmbedTarget($scheme:$id, alt: $alt)';
}

/// What a body knows about the text an embed is set in, so the resolver can
/// size it.
///
/// A body computes one value per paragraph style and hands the same one to
/// every embed of that paragraph, so [extent] is the one size they all share.
@immutable
final class MarkdownInlineEmbedMetrics {
  /// Creates metrics for text of [fontSize] logical pixels, whose font reaches
  /// [ascent] above and [descent] below the baseline, at [devicePixelRatio].
  const MarkdownInlineEmbedMetrics({
    required this.fontSize,
    required this.ascent,
    required this.descent,
    required this.devicePixelRatio,
  }) : assert(
          fontSize > 0 && ascent >= 0 && descent >= 0 && devicePixelRatio > 0,
          'metrics need a positive font size and density',
        );

  /// How much taller than the font an embed is: Android's rule, so a custom
  /// emoji reads at the size it has there.
  static const double extentScale = 1.2;

  /// Font size of the text around the embed, logical pixels.
  final double fontSize;

  /// Distance from the baseline up to the top of the font, logical pixels.
  final double ascent;

  /// Distance from the baseline down to the bottom of the font, logical
  /// pixels.
  final double descent;

  /// Pixels per logical pixel of the display the body is shown on.
  final double devicePixelRatio;

  /// The side of the square an embed takes in this text: [extentScale] times
  /// the font's height, rounded to whole device pixels so the embed is
  /// rasterised at the size it is shown.
  double get extent =>
      (extentScale * (ascent + descent) * devicePixelRatio).roundToDouble() /
      devicePixelRatio;

  @override
  bool operator ==(Object other) =>
      other is MarkdownInlineEmbedMetrics &&
      other.fontSize == fontSize &&
      other.ascent == ascent &&
      other.descent == descent &&
      other.devicePixelRatio == devicePixelRatio;

  @override
  int get hashCode => Object.hash(fontSize, ascent, descent, devicePixelRatio);

  @override
  String toString() => 'MarkdownInlineEmbedMetrics($fontSize, '
      'ascent: $ascent, descent: $descent, x$devicePixelRatio)';
}

/// A painter-based thing set inside text: it has a size, paints itself into a
/// rectangle the body gives it, and says when what it paints has changed.
///
/// This is the contract a markdown body lays out and paints; it carries no
/// widget and no asset type, and this package knows no implementation of it.
/// A body asks its [MarkdownInlineEmbedResolver] for one per reference,
/// reserves [size] in the text, calls [paint] while painting, repaints when it
/// hears the [Listenable] signal, and calls [dispose] when the text goes away.
/// The alternative text of the reference, not the embed, is what copy,
/// selection and accessibility use.
///
/// ## Contract
///
/// - [size] is the size the body reserves; it does not change over the
///   embed's life. [paint] may be given a rectangle of another size and scales
///   to it.
/// - The signal (the [Listenable]) means "what [paint] draws is different
///   now"; it carries nothing and is silent after [dispose].
/// - [paint] draws only inside the rectangle and nothing at all after
///   [dispose]. It is called during painting and does not schedule work.
/// - [visible] is true on creation. A body sets it false for an embed that is
///   scrolled out of view or hidden, so an animated one stops costing ticks.
/// - [dispose] is idempotent and gives back everything the embed holds.
abstract interface class MarkdownInlineEmbed implements Listenable {
  /// The logical size the body reserves for the embed.
  Size get size;

  /// Whether the body shows the embed.
  bool get visible;
  set visible(bool value);

  /// Paints the embed into [rect] of [canvas].
  void paint(
    Canvas canvas,
    Rect rect,
    MarkdownInlineEmbedPaintContext context,
  );

  /// Gives back what the embed holds. Idempotent.
  void dispose();
}

/// Turns a target in text into the [MarkdownInlineEmbed] that draws it.
///
/// A host registers one where it sets up a body; the body owns every embed the
/// resolver returns and disposes it.
abstract interface class MarkdownInlineEmbedResolver {
  /// A new embed for [target] in text of [metrics], or null when this resolver
  /// does not know the target (the body then shows the alternative text). Each
  /// call returns an embed of its own: disposing one never affects another
  /// made for the same target.
  MarkdownInlineEmbed? resolve(
    MarkdownInlineEmbedTarget target,
    MarkdownInlineEmbedMetrics metrics,
  );
}
