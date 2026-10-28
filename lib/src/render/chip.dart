import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart' as meta show internal;

import '../nodes.dart';
import '../theme.dart';

/// The leading glyph of a chip: one code unit of the painter's text that the
/// rendered text (selection, copy) does not have. The offset map in
/// `embed_offset_map.dart` bridges the two.
///
/// The run only reserves the glyph's room (its advance and the [gap] after
/// it) and is transparent: the glyph itself is drawn by
/// [MarkdownChipPainter.paintWithChips], centred on the label's line box. An
/// icon font's ascent and descent differ from the text font's, so a glyph
/// left on the shared baseline sits visibly high or low next to the label.
@meta.internal
final class MarkdownChipGlyphSpan extends TextSpan {
  /// Creates the glyph run of a chip set in [style].
  ///
  /// The glyph style is built fresh, not as a `copyWith` of [style]: a host
  /// style that carries a font `package` would otherwise keep it, and the
  /// icon family would resolve to `packages/<host>/<icon family>`, which does
  /// not exist (a tofu box). [gap] is the space after the glyph, [size] its
  /// font size (the text size when `null`).
  MarkdownChipGlyphSpan({
    required TextStyle style,
    required this.icon,
    double? gap,
    double? size,
    super.recognizer,
  })  : color = style.color ?? const Color(0xFF000000),
        super(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            inherit: false,
            // Transparent: see the class comment.
            color: const Color(0x00000000),
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
            // The gap between the glyph and the label.
            letterSpacing: gap ?? (style.fontSize ?? kDefaultFontSize) * 0.3,
            decoration: TextDecoration.none,
          ),
        );

  /// The glyph.
  final IconData icon;

  /// The colour the glyph is drawn in.
  final Color color;

  /// A painter for the glyph alone: a square-ish em box, no gap, in [color].
  TextPainter glyphPainter(TextPainter host) {
    final base = style!;
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          inherit: false,
          color: color,
          fontSize: base.fontSize,
          fontFamily: base.fontFamily,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
          // One em box, whatever the host's line height: the box is centred
          // on the label, not the glyph's baseline.
          height: 1,
          leadingDistribution: TextLeadingDistribution.even,
          locale: base.locale,
          decoration: TextDecoration.none,
        ),
      ),
      textDirection: host.textDirection,
      textScaler: host.textScaler,
    )..layout();
  }
}

/// A run of room beside a chip's content: one zero-width code unit
/// (U+2062 INVISIBLE TIMES) whose letter spacing is the room. Like the icon, it
/// is painter text the rendered text (selection, copy) does not have.
///
/// The code unit is a format character (its own grapheme, so a selection edge
/// can sit next to it) of the alphabetic line-break class: text may still wrap
/// before the chip, and the run never splits from the chip's content. A
/// combining mark (U+200C) would be glued to the previous glyph and make that
/// glyph's selection box wrong.
@meta.internal
final class MarkdownChipSpacerSpan extends TextSpan {
  /// Creates [width] of room; [trailing] is true after the chip's content.
  MarkdownChipSpacerSpan({
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

  /// Whether the run follows the chip's content.
  final bool trailing;
}

/// An inline chip: spacers, the glyph run (if any), the label run and
/// spacers, and the fill painted behind glyph and label (and the padding
/// spacers between). The label is the whole of the chip's rendered text.
@meta.internal
final class MarkdownChipSpan extends TextSpan {
  /// Creates a chip of [label] filled with [background].
  factory MarkdownChipSpan({
    required String label,
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
    MarkdownChipSpacerSpan spacer(double w, {required bool trailing}) =>
        MarkdownChipSpacerSpan(style: style, width: w, trailing: trailing);
    final glyph = icon == null
        ? null
        : MarkdownChipGlyphSpan(
            style: style,
            icon: icon,
            gap: gap,
            size: iconSize,
            recognizer: recognizer,
          );
    final lead = <TextSpan>[
      if (mar > 0) spacer(mar, trailing: false),
      if (pad > 0) spacer(pad, trailing: false),
      if (glyph != null) glyph,
    ];
    final trail = <TextSpan>[
      if (pad > 0) spacer(pad, trailing: true),
      if (mar > 0) spacer(mar, trailing: true),
    ];
    return MarkdownChipSpan._(
      children: <InlineSpan>[
        ...lead,
        TextSpan(text: label, style: style, recognizer: recognizer),
        ...trail,
      ],
      background: background,
      muted: muted,
      radius: radius,
      padding: pad,
      margin: mar,
      glyph: glyph,
      leadLength: lead.fold(0, (n, c) => n + c.text!.length),
      trailLength: trail.length,
      leadMarginLength: mar > 0 ? 1 : 0,
    );
  }

  const MarkdownChipSpan._({
    required List<InlineSpan> super.children,
    required this.background,
    required this.muted,
    required this.radius,
    required this.padding,
    required this.margin,
    required this.glyph,
    required this.leadLength,
    required this.trailLength,
    required this.leadMarginLength,
  });

  /// The fill behind the chip.
  final Color background;

  /// Whether the chip is shown in its muted colours.
  final bool muted;

  /// The corner radius of the fill; null for fully rounded ends.
  final double? radius;

  /// Room inside the fill, before the first run and after the label. Real
  /// layout: the text is pushed by it.
  final double padding;

  /// Room outside the fill on each side. Real layout, like [padding].
  final double margin;

  /// The leading glyph run; null for a chip without a glyph.
  final MarkdownChipGlyphSpan? glyph;

  /// Code units of the painter's text before the label: margin and padding
  /// room, and the glyph.
  final int leadLength;

  /// Code units of the painter's text after the label: padding and margin room.
  final int trailLength;

  /// Code units of the leading margin room (0 or 1).
  final int leadMarginLength;

  /// Code units the glyph takes in the painter's text (0 or 1 or 2).
  int get glyphLength => glyph?.text!.length ?? 0;

  /// Code units of the painter's text that the rendered text does not have:
  /// everything but the label.
  int get markerLength => leadLength + trailLength;
}

/// Builds the chip of a [MD$Style.chip] [span] in text of [style].
@meta.internal
MarkdownChipSpan buildChip(
  MD$Span span,
  TextStyle style,
  MarkdownThemeData theme,
) {
  final extra = span.extra;
  final muted = extra?['muted'] == true;
  final target = extra?['target'];
  final onTap = theme.onChipTap;
  final chipStyle = theme.chipStyle;
  final Color color;
  final Color background;
  if (muted) {
    color = chipStyle?.mutedColor ??
        (style.color ?? theme.linkColor ?? Colors.grey).withValues(alpha: .55);
    background = chipStyle?.mutedBackground ?? color.withValues(alpha: .1);
  } else {
    color = chipStyle?.color ?? theme.linkColor ?? Colors.indigo;
    background = chipStyle?.background ?? color.withValues(alpha: .14);
  }
  final recognizer = onTap != null && target is String
      ? (TapGestureRecognizer()..onTap = () => onTap(target, span.text))
      : null;
  return MarkdownChipSpan(
    label: span.text,
    style: style.copyWith(color: color, fontWeight: chipStyle?.fontWeight),
    background: background,
    muted: muted,
    icon: chipStyle?.icon,
    iconSize: chipStyle?.iconSize,
    gap: chipStyle?.gap,
    radius: chipStyle?.radius,
    horizontalPadding: chipStyle?.horizontalPadding,
    margin: chipStyle?.margin,
    recognizer: recognizer,
  );
}

/// Chip ranges of one painter text, in painter offsets.
final Expando<List<(TextRange, MarkdownChipSpan)>> _ranges =
    Expando<List<(TextRange, MarkdownChipSpan)>>('chipRanges');

List<(TextRange, MarkdownChipSpan)> _chipRanges(InlineSpan root) {
  final cached = _ranges[root];
  if (cached != null) return cached;
  final out = <(TextRange, MarkdownChipSpan)>[];
  var offset = 0;
  void walk(InlineSpan span) {
    if (span is MarkdownChipSpan) {
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

/// Where one chip sits in a laid-out painter.
class _ChipGeometry {
  _ChipGeometry(this.chip, this.lines, this.glyphBoxes);

  final MarkdownChipSpan chip;

  /// One rect per line the chip crosses: the label's tight line box, widened
  /// to take in the glyph's room.
  final List<Rect> lines;

  /// The glyph's own boxes (room before the label), empty without a glyph.
  final List<Rect> glyphBoxes;
}

/// Chip fills and glyphs for a laid-out `TextPainter`.
extension MarkdownChipPainter on TextPainter {
  List<_ChipGeometry> _chipGeometry() {
    final root = text;
    if (root == null) return const <_ChipGeometry>[];
    final ranges = _chipRanges(root);
    final out = <_ChipGeometry>[];
    for (final (range, chip) in ranges) {
      final pad = chip.padding;
      // The fill reaches from the leading padding room to the trailing one;
      // the margin rooms outside it are not filled.
      final glyphStart =
          range.start + chip.leadMarginLength + (pad > 0 ? 1 : 0);
      final labelStart = range.start + chip.leadLength;
      final labelEnd = range.end - chip.trailLength;
      List<Rect> rects(int from, int to) => from >= to
          ? const <Rect>[]
          : getBoxesForSelection(
              TextSelection(baseOffset: from, extentOffset: to),
              boxHeightStyle: BoxHeightStyle.tight,
            ).map((b) => b.toRect()).toList();
      // The height of the fill is the label's line, so a glyph larger than the
      // text widens a fill but never grows it into the lines around it.
      // Boxes of one line are told apart by their centre, not by an equal top.
      final lines = <Rect>[];
      for (final rect in rects(labelStart, labelEnd)) {
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
      final glyphBoxes = rects(glyphStart, labelStart);
      for (final glyph in glyphBoxes) {
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
      out.add(_ChipGeometry(chip, lines, glyphBoxes));
    }
    return out;
  }

  /// Painter-local rounded rects of the chips, one per line a chip crosses,
  /// with the fill each is painted in. Valid after layout.
  List<(RRect, Color)> get chipBoxes => _fills(_chipGeometry());

  List<(RRect, Color)> _fills(List<_ChipGeometry> geometry) {
    final out = <(RRect, Color)>[];
    for (final g in geometry) {
      final chip = g.chip;
      final pad = chip.padding;
      final lines = g.lines;
      // The padding is real room, at the chip's own start and end only: a
      // line a wrap cuts short has the fill run to its edge.
      for (var i = 0; i < lines.length; i++) {
        final r = lines[i];
        final rect = Rect.fromLTRB(
          i == 0 ? r.left - pad : r.left,
          r.top,
          i == lines.length - 1 ? r.right + pad : r.right,
          r.bottom,
        );
        final radius = chip.radius == null
            ? rect.height / 2
            : chip.radius!.clamp(0.0, rect.height / 2);
        out.add((RRect.fromRectXY(rect, radius, radius), chip.background));
      }
    }
    return out;
  }

  /// Painter-local rects where the chips' glyphs are drawn, with the glyph
  /// run each belongs to. The vertical centre of each rect is the vertical
  /// centre of the label's line box, so the glyph is centred on the label
  /// whatever the icon font's own ascent and descent are. Valid after layout.
  List<(Rect, MarkdownChipGlyphSpan)> get chipGlyphBoxes =>
      _glyphs(_chipGeometry());

  List<(Rect, MarkdownChipGlyphSpan)> _glyphs(List<_ChipGeometry> geometry) {
    final out = <(Rect, MarkdownChipGlyphSpan)>[];
    for (final g in geometry) {
      final glyph = g.chip.glyph;
      if (glyph == null || g.glyphBoxes.isEmpty || g.lines.isEmpty) continue;
      final slot = g.glyphBoxes.first;
      // The label line the glyph belongs to: the nearest one to its slot.
      var line = g.lines.first;
      for (final l in g.lines) {
        if ((l.center.dy - slot.center.dy).abs() <
            (line.center.dy - slot.center.dy).abs()) {
          line = l;
        }
      }
      final glyphPainter = glyph.glyphPainter(this);
      final size = glyphPainter.size;
      glyphPainter.dispose();
      final left = textDirection == TextDirection.rtl
          ? slot.right - size.width
          : slot.left;
      out.add((
        Rect.fromLTWH(
          left,
          line.center.dy - size.height / 2,
          size.width,
          size.height,
        ),
        glyph,
      ));
    }
    return out;
  }

  /// Paints the chip fills, then the text, then the chip glyphs: use in place
  /// of `paint` for text that may hold a chip.
  void paintWithChips(Canvas canvas, Offset offset) {
    final geometry = _chipGeometry();
    if (geometry.isEmpty) {
      paint(canvas, offset);
      return;
    }
    for (final (rrect, color) in _fills(geometry)) {
      canvas.drawRRect(rrect.shift(offset), Paint()..color = color);
    }
    paint(canvas, offset);
    for (final (rect, glyph) in _glyphs(geometry)) {
      final glyphPainter = glyph.glyphPainter(this);
      glyphPainter.paint(canvas, offset + rect.topLeft);
      glyphPainter.dispose();
    }
  }
}
