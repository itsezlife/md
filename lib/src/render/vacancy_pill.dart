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

/// A vacancy pill: the icon run and the title run, and the fill painted behind
/// both. The text of the title is the whole of the pill's rendered text.
@meta.internal
final class MarkdownPillSpan extends TextSpan {
  /// Creates a pill of [title] filled with [background].
  MarkdownPillSpan({
    required String title,
    required TextStyle style,
    required this.background,
    required this.muted,
    IconData? icon,
    double? iconSize,
    double? gap,
    this.radius,
    double? horizontalPadding,
    GestureRecognizer? recognizer,
  })  : padding =
            horizontalPadding ?? (style.fontSize ?? kDefaultFontSize) * 0.3,
        super(
          children: <InlineSpan>[
            MarkdownPillGlyphSpan(
              style: style,
              icon: icon ?? Icons.work_outline_rounded,
              gap: gap,
              size: iconSize,
              recognizer: recognizer,
            ),
            TextSpan(text: title, style: style, recognizer: recognizer),
          ],
        );

  /// The fill behind the pill.
  final Color background;

  /// Whether the pill stands for a reference that is not resolved yet.
  final bool muted;

  /// The corner radius of the fill; null for fully rounded ends.
  final double? radius;

  /// How far the fill reaches past the content on each side.
  final double padding;

  /// Code units the icon takes in the painter's text.
  int get glyphLength => (children!.first as TextSpan).text!.length;
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
      final split = range.start + pill.glyphLength;
      List<Rect> rects(int from, int to) => getBoxesForSelection(
            TextSelection(baseOffset: from, extentOffset: to),
            boxHeightStyle: BoxHeightStyle.tight,
          ).map((b) => b.toRect()).toList();
      // The height of the fill is the title's line, so an icon larger than the
      // text widens a fill but never grows it into the lines around it.
      // Boxes of one line are told apart by their centre, not by an equal top.
      final lines = <Rect>[];
      for (final rect in rects(split, range.end)) {
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
      for (final glyph in rects(range.start, split)) {
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
      for (final r in lines) {
        final rect =
            Rect.fromLTRB(r.left - pad, r.top, r.right + pad, r.bottom);
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
