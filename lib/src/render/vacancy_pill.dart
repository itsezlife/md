import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart' as meta show internal;

import '../nodes.dart';
import '../theme.dart';

/// The icon glyph of a vacancy pill: one code unit of the painter's text that
/// the rendered text (selection, copy) does not have. The offset map in
/// `embed_offset_map.dart` bridges the two.
@meta.internal
final class MarkdownPillGlyphSpan extends TextSpan {
  /// Creates the icon run of a pill set in [style].
  ///
  /// The glyph style is built fresh, not as a `copyWith` of [style]: a host
  /// style that carries a font `package` would otherwise keep it, and the
  /// icon family would resolve to `packages/<host>/<icon family>`, which does
  /// not exist (a tofu box). [gap] is the space after the icon, [size] its
  /// font size (the text size when `null`).
  MarkdownPillGlyphSpan({
    required TextStyle style,
    required IconData icon,
    double? gap,
    double? size,
    super.recognizer,
  }) : super(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            inherit: false,
            color: style.color,
            backgroundColor: style.backgroundColor,
            fontSize: size ?? style.fontSize ?? kDefaultFontSize,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontWeight: FontWeight.normal,
            fontStyle: FontStyle.normal,
            height: style.height,
            textBaseline: style.textBaseline,
            leadingDistribution: style.leadingDistribution,
            locale: style.locale,
            // The gap between the icon and the title.
            letterSpacing: gap ?? (style.fontSize ?? kDefaultFontSize) * 0.3,
            decoration: TextDecoration.none,
          ),
        );
}

/// A run of room beside a vacancy pill's content: one zero-width code unit
/// (U+2062 INVISIBLE TIMES) whose letter spacing is the room. Like the icon, it
/// is painter text the rendered text (selection, copy) does not have.
///
/// The code unit is a format character (its own grapheme, so a selection edge
/// can sit next to it) of the alphabetic line-break class: text may still wrap
/// before the pill, and the run never splits from the pill's content. A
/// combining mark (U+200C) would be glued to the previous glyph and make that
/// glyph's selection box wrong.
@meta.internal
final class MarkdownPillSpacerSpan extends TextSpan {
  /// Creates [width] of room; [trailing] is true after the pill's content.
  MarkdownPillSpacerSpan({
    required TextStyle style,
    required double width,
    required this.trailing,
  }) : super(
          text: '\u2062',
          style: TextStyle(
            inherit: false,
            color: style.color,
            fontSize: style.fontSize ?? kDefaultFontSize,
            fontFamily: style.fontFamily,
            fontWeight: style.fontWeight,
            fontStyle: style.fontStyle,
            height: style.height,
            textBaseline: style.textBaseline,
            leadingDistribution: style.leadingDistribution,
            locale: style.locale,
            letterSpacing: width,
            decoration: TextDecoration.none,
          ),
        );

  /// Whether the run follows the pill's content.
  final bool trailing;
}

/// A vacancy pill: spacers, the icon run, the title run and spacers, and the
/// fill painted behind icon and title (and the padding spacers between). The
/// text of the title is the whole of the pill's rendered text.
@meta.internal
final class MarkdownPillSpan extends TextSpan {
  /// Creates a pill of [title] filled with [background].
  factory MarkdownPillSpan({
    required String title,
    required TextStyle style,
    required Color background,
    required bool muted,
    IconData? icon,
    double? iconSize,
    double? gap,
    double? radius,
    double? horizontalPadding,
    double? margin,
    GestureRecognizer? recognizer,
  }) {
    final pad = horizontalPadding ?? (style.fontSize ?? kDefaultFontSize) * 0.3;
    final mar = margin ?? 0;
    MarkdownPillSpacerSpan spacer(double w, {required bool trailing}) =>
        MarkdownPillSpacerSpan(style: style, width: w, trailing: trailing);
    final lead = <TextSpan>[
      if (mar > 0) spacer(mar, trailing: false),
      if (pad > 0) spacer(pad, trailing: false),
      MarkdownPillGlyphSpan(
        style: style,
        icon: icon ?? Icons.work_outline_rounded,
        gap: gap,
        size: iconSize,
        recognizer: recognizer,
      ),
    ];
    final trail = <TextSpan>[
      if (pad > 0) spacer(pad, trailing: true),
      if (mar > 0) spacer(mar, trailing: true),
    ];
    return MarkdownPillSpan._(
      children: <InlineSpan>[
        ...lead,
        TextSpan(text: title, style: style, recognizer: recognizer),
        ...trail,
      ],
      background: background,
      muted: muted,
      radius: radius,
      padding: pad,
      margin: mar,
      leadLength: lead.fold(0, (n, c) => n + c.text!.length),
      trailLength: trail.length,
      leadMarginLength: mar > 0 ? 1 : 0,
      glyphLength: lead.last.text!.length,
    );
  }

  const MarkdownPillSpan._({
    required List<InlineSpan> super.children,
    required this.background,
    required this.muted,
    required this.radius,
    required this.padding,
    required this.margin,
    required this.leadLength,
    required this.trailLength,
    required this.leadMarginLength,
    required this.glyphLength,
  });

  /// The fill behind the pill.
  final Color background;

  /// Whether the pill stands for a reference that is not resolved yet.
  final bool muted;

  /// The corner radius of the fill; null for fully rounded ends.
  final double? radius;

  /// Room inside the fill, before the icon and after the title. Real layout:
  /// the text is pushed by it.
  final double padding;

  /// Room outside the fill on each side. Real layout, like [padding].
  final double margin;

  /// Code units of the painter's text before the title: margin and padding
  /// room, and the icon.
  final int leadLength;

  /// Code units of the painter's text after the title: padding and margin room.
  final int trailLength;

  /// Code units of the leading margin room (0 or 1).
  final int leadMarginLength;

  /// Code units the icon takes in the painter's text.
  final int glyphLength;

  /// Code units of the painter's text that the rendered text does not have:
  /// everything but the title.
  int get markerLength => leadLength + trailLength;
}

/// Builds the pill of a [MD$Style.vacancy] [span] in text of [style].
@meta.internal
MarkdownPillSpan buildVacancyPill(
  MD$Span span,
  TextStyle style,
  MarkdownThemeData theme,
) {
  final extra = span.extra;
  final muted = extra?['muted'] == true;
  final target = extra?['target'];
  final onTap = theme.onVacancyTap;
  final Color color;
  final Color background;
  if (muted) {
    color = theme.vacancyPillMutedColor ??
        (style.color ?? theme.linkColor ?? Colors.grey).withValues(alpha: .55);
    background =
        theme.vacancyPillMutedBackground ?? color.withValues(alpha: .1);
  } else {
    color = theme.vacancyPillColor ?? theme.linkColor ?? Colors.indigo;
    background = theme.vacancyPillBackground ?? color.withValues(alpha: .14);
  }
  final recognizer = onTap != null && target is String
      ? (TapGestureRecognizer()..onTap = () => onTap(target, span.text))
      : null;
  return MarkdownPillSpan(
    title: span.text,
    style: style.copyWith(color: color),
    background: background,
    muted: muted,
    icon: theme.vacancyPillIcon,
    iconSize: theme.vacancyPillIconSize,
    gap: theme.vacancyPillGap,
    radius: theme.vacancyPillRadius,
    horizontalPadding: theme.vacancyPillHorizontalPadding,
    margin: theme.vacancyPillMargin,
    recognizer: recognizer,
  );
}

/// Pill ranges of one painter text, in painter offsets.
final Expando<List<(TextRange, MarkdownPillSpan)>> _ranges =
    Expando<List<(TextRange, MarkdownPillSpan)>>('pillRanges');

List<(TextRange, MarkdownPillSpan)> _pillRanges(InlineSpan root) {
  final cached = _ranges[root];
  if (cached != null) return cached;
  final out = <(TextRange, MarkdownPillSpan)>[];
  var offset = 0;
  void walk(InlineSpan span) {
    if (span is MarkdownPillSpan) {
      final start = offset;
      span.children?.forEach(walk);
      out.add((TextRange(start: start, end: offset), span));
      return;
    }
    if (span is TextSpan) {
      offset += span.text?.length ?? 0;
      span.children?.forEach(walk);
    } else if (span is PlaceholderSpan) {
      offset++;
    } else {
      offset += span.toPlainText(includeSemanticsLabels: false).length;
    }
  }

  walk(root);
  return _ranges[root] = out;
}

/// Pill fills for a laid-out `TextPainter`.
extension MarkdownPillPainter on TextPainter {
  /// Painter-local rounded rects of the pills, one per line a pill crosses,
  /// with the fill each is painted in. Valid after layout.
  List<(RRect, Color)> get pillBoxes {
    final root = text;
    if (root == null) return const <(RRect, Color)>[];
    final ranges = _pillRanges(root);
    if (ranges.isEmpty) return const <(RRect, Color)>[];
    final out = <(RRect, Color)>[];
    for (final (range, pill) in ranges) {
      final pad = pill.padding;
      // The fill reaches from the leading padding room to the trailing one;
      // the margin rooms outside it are not filled.
      final glyphStart =
          range.start + pill.leadMarginLength + (pad > 0 ? 1 : 0);
      final titleStart = range.start + pill.leadLength;
      final titleEnd = range.end - pill.trailLength;
      List<Rect> rects(int from, int to) => getBoxesForSelection(
            TextSelection(baseOffset: from, extentOffset: to),
            boxHeightStyle: BoxHeightStyle.tight,
          ).map((b) => b.toRect()).toList();
      // The height of the fill is the title's line, so an icon larger than the
      // text widens a fill but never grows it into the lines around it.
      // Boxes of one line are told apart by their centre, not by an equal top.
      final lines = <Rect>[];
      for (final rect in rects(titleStart, titleEnd)) {
        final i = lines.indexWhere(
          (l) => rect.center.dy >= l.top && rect.center.dy <= l.bottom,
        );
        if (i < 0) {
          lines.add(rect);
        } else {
          lines[i] = lines[i].expandToInclude(rect);
        }
      }
      if (lines.isEmpty) continue;
      for (final glyph in rects(glyphStart, titleStart)) {
        final i = lines.indexWhere(
          (l) => glyph.center.dy >= l.top && glyph.center.dy <= l.bottom,
        );
        if (i < 0) continue;
        final l = lines[i];
        lines[i] = Rect.fromLTRB(
          glyph.left < l.left ? glyph.left : l.left,
          l.top,
          glyph.right > l.right ? glyph.right : l.right,
          l.bottom,
        );
      }
      // The padding is real room, at the pill's own start and end only: a
      // line a wrap cuts short has the fill run to its edge.
      for (var i = 0; i < lines.length; i++) {
        final r = lines[i];
        final rect = Rect.fromLTRB(
          i == 0 ? r.left - pad : r.left,
          r.top,
          i == lines.length - 1 ? r.right + pad : r.right,
          r.bottom,
        );
        final radius = pill.radius == null
            ? rect.height / 2
            : pill.radius!.clamp(0.0, rect.height / 2);
        out.add((RRect.fromRectXY(rect, radius, radius), pill.background));
      }
    }
    return out;
  }

  /// Paints the pill fills, then the text: use in place of `paint` for text
  /// that may hold a pill.
  void paintWithPills(Canvas canvas, Offset offset) {
    for (final (rrect, color) in pillBoxes) {
      canvas.drawRRect(rrect.shift(offset), Paint()..color = color);
    }
    paint(canvas, offset);
  }
}
