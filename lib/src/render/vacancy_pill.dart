import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart' as meta show internal;

import '../nodes.dart';
import '../theme.dart';

/// The briefcase glyph of a vacancy pill: one code unit of the painter's text
/// that the rendered text (selection, copy) does not have. The offset map in
/// `embed_offset_map.dart` bridges the two.
@meta.internal
final class MarkdownPillGlyphSpan extends TextSpan {
  /// Creates the icon run of a pill set in [style].
  MarkdownPillGlyphSpan({required TextStyle style, super.recognizer})
      : super(
          text: String.fromCharCode(Icons.work_outline_rounded.codePoint),
          style: style.copyWith(
            fontFamily: Icons.work_outline_rounded.fontFamily,
            package: Icons.work_outline_rounded.fontPackage,
            fontWeight: FontWeight.normal,
            fontStyle: FontStyle.normal,
            fontFamilyFallback: const <String>[],
            // The gap between the icon and the title.
            letterSpacing: (style.fontSize ?? kDefaultFontSize) * 0.3,
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
    GestureRecognizer? recognizer,
  }) : super(
          children: <InlineSpan>[
            MarkdownPillGlyphSpan(style: style, recognizer: recognizer),
            TextSpan(text: title, style: style, recognizer: recognizer),
          ],
        );

  /// The rounded fill behind the pill.
  final Color background;

  /// Whether the pill stands for a reference that is not resolved yet.
  final bool muted;

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
    recognizer: recognizer,
  );
}

/// Pill ranges of one painter text, in painter offsets.
final Expando<List<(TextRange, Color)>> _ranges =
    Expando<List<(TextRange, Color)>>('pillRanges');

List<(TextRange, Color)> _pillRanges(InlineSpan root) {
  final cached = _ranges[root];
  if (cached != null) return cached;
  final out = <(TextRange, Color)>[];
  var offset = 0;
  void walk(InlineSpan span) {
    if (span is MarkdownPillSpan) {
      final start = offset;
      span.children?.forEach(walk);
      out.add((TextRange(start: start, end: offset), span.background));
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
    final pad = (root.style?.fontSize ?? kDefaultFontSize) * 0.3;
    final out = <(RRect, Color)>[];
    for (final (range, color) in ranges) {
      final boxes = getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
        boxHeightStyle: BoxHeightStyle.tight,
      );
      Rect? line;
      void flush() {
        if (line == null) return;
        final r = line!;
        final rect = Rect.fromLTRB(
          r.left - pad,
          r.top,
          r.right + pad,
          r.bottom,
        );
        out.add((
          RRect.fromRectXY(rect, rect.height / 2, rect.height / 2),
          color,
        ));
        line = null;
      }

      for (final box in boxes) {
        final rect = box.toRect();
        if (line != null && (line!.top - rect.top).abs() > 0.5) flush();
        line = line?.expandToInclude(rect) ?? rect;
      }
      flush();
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
