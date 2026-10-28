//ignore_for_file: unnecessary_import

import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../inline_embed.dart';
import '../nodes.dart';
import '../theme.dart';
import 'inline_embeds.dart';
import 'vacancy_pill.dart';

export 'vacancy_pill.dart' show MarkdownPillPainter;

/// Builds a tap recognizer for the given markdown span.
TapGestureRecognizer? _buildTapRecognizer(
  MD$Span span,
  void Function(String title, String url)? onTap,
) {
  if (onTap == null) return null;
  if (span.extra case <String, Object?>{'url': String url}) {
    return TapGestureRecognizer()
      ..onTap = () {
        onTap(span.extra?['alt']?.toString() ?? span.text, url);
      };
  }
  return null;
}

/// Builds a tap recognizer that reports a mention-class span's scheme, id and
/// name, read from the parser's `extra` rather than from any URL.
TapGestureRecognizer? _buildMentionRecognizer(
  MD$Span span,
  void Function(String scheme, String? id, String name)? onTap,
) {
  if (onTap == null) return null;
  if (span.extra
      case <String, Object?>{
        'scheme': String scheme,
        'name': String name,
      }) {
    final id = span.extra?['id'];
    return TapGestureRecognizer()
      ..onTap = () => onTap(scheme, id is String ? id : null, name);
  }
  return null;
}

/// Whether any of [spans] paints an opaque / translucent fill behind glyphs
/// (`monospace` / `highlight` backgrounds from [MarkdownThemeData]). Used to
/// decide whether the selection tint must paint *above* the cached content
/// picture so those fills do not hide it.
bool markdownSpansPaintOpaqueBackground(Iterable<MD$Span> spans) {
  for (final span in spans) {
    if (span.style.contains(MD$Style.monospace) ||
        span.style.contains(MD$Style.highlight) ||
        span.style.contains(MD$Style.vacancy)) {
      return true;
    }
  }
  return false;
}

/// Helper function to create a [TextSpan] from markdown spans.
/// This function filters the spans based on the theme's span filter,
/// and applies the appropriate text style to each span.
///
/// With [embeds], an image span whose `src` names an embed its resolver knows
/// becomes a placeholder that takes the embed's room in the paragraph (see
/// [MarkdownEmbedSpan]). Any other image span, and every image span when
/// [embeds] is null, stays the alt text it always was.
///
/// With [revealed] false the `||spoiler||` runs get a transparent colour (see
/// [MarkdownParagraphSpan]); their metrics are the revealed ones, so no glyph
/// moves between the two forms. The default shows the text, as before.
TextSpan paragraphFromMarkdownSpans({
  required Iterable<MD$Span> spans,
  required MarkdownThemeData theme,
  TextStyle? textStyle,
  MarkdownEmbedHost? embeds,
  bool revealed = true,
}) {
  final style = textStyle ?? theme.textStyle;
  final spanFilter = theme.spanFilter;
  final filtered = spanFilter != null ? spans.where(spanFilter) : spans;
  // With an explicit block style, merge it under each span's own style;
  // otherwise the span style stands alone (the block style is applied once, on
  // the parent TextSpan below).
  final merge = textStyle != null;
  // Every embed of the paragraph shares one size, so the font is probed once,
  // on the first embed, and not at all in a paragraph without one.
  MarkdownInlineEmbedMetrics? metrics;
  // The same goes for the style of an emoji run: one per paragraph.
  TextStyle? emojiStyle;
  InlineSpan mapper(MD$Span span) {
    final spanStyle = merge
        ? theme.textStyleFor(span.style).merge(style)
        : theme.textStyleFor(span.style);
    if (embeds != null && span.style.contains(MD$Style.image)) {
      final target = MarkdownInlineEmbedTarget.tryParse(
        span.extra?['src']?.toString() ?? '',
        span.text,
      );
      if (target != null) {
        final probed = metrics ??= _probeMetrics(
          style,
          theme,
          embeds.devicePixelRatio,
        );
        final embed = embeds.resolve(target, probed);
        if (embed != null) {
          return MarkdownEmbedSpan(
            embed: embed,
            target: target,
            layoutHeight: probed.ascent + probed.descent,
            style: spanStyle,
          );
        }
      }
    }
    if (span.style.contains(MD$Style.vacancy)) {
      return buildVacancyPill(span, spanStyle, theme);
    }
    final recognizer = switch (span.style) {
      final s when s.contains(MD$Style.link) =>
        _buildTapRecognizer(span, theme.onLinkTap),
      final s when s.contains(MD$Style.mention) =>
        _buildMentionRecognizer(span, theme.onMentionTap),
      _ => null,
    };
    final scanner = theme.emojiRuns;
    final runs = scanner == null
        ? const <TextRange>[]
        : _validRuns(scanner(span.text), span.text.length);
    if (runs.isEmpty) {
      return TextSpan(
        text: span.text,
        style: spanStyle,
        recognizer: recognizer,
      );
    }
    // The span's own style stays on the parent; only the emoji pieces differ,
    // so a link, a bold or a spoiler colour reaches them by inheritance. The
    // recognizer goes on every piece: a position resolves to the deepest span.
    final runStyle = emojiStyle ??= _emojiRunStyle(style, theme);
    final pieces = <InlineSpan>[];
    var at = 0;
    for (final run in runs) {
      if (run.start > at) {
        pieces.add(TextSpan(
          text: span.text.substring(at, run.start),
          recognizer: recognizer,
        ));
      }
      pieces.add(TextSpan(
        text: span.text.substring(run.start, run.end),
        style: runStyle,
        recognizer: recognizer,
      ));
      at = run.end;
    }
    if (at < span.text.length) {
      pieces.add(TextSpan(
        text: span.text.substring(at),
        recognizer: recognizer,
      ));
    }
    return TextSpan(style: spanStyle, children: pieces);
  }

  final children = <InlineSpan>[];
  final spoilerChildren = <int>[];
  final spoilerRanges = <TextRange>[];
  var offset = 0;
  for (final span in filtered) {
    final child = mapper(span);
    // Offsets are the painter's own: an embed placeholder is one code unit
    // however long its alt text is (the offset map bridges that for selection).
    // A pill's icon is one more code unit of the painter's text.
    final end = offset +
        (child is MarkdownPillSpan
            ? span.text.length + child.markerLength
            : child is TextSpan
                ? span.text.length
                : 1);
    if (span.style.contains(MD$Style.spoiler)) {
      spoilerChildren.add(children.length);
      // One spoiler is usually several spans (`||a **b** c||`); a fill covers
      // it as one run.
      if (spoilerRanges.isNotEmpty && spoilerRanges.last.end == offset) {
        spoilerRanges.last = TextRange(
          start: spoilerRanges.last.start,
          end: end,
        );
      } else {
        spoilerRanges.add(TextRange(start: offset, end: end));
      }
    }
    children.add(child);
    offset = end;
  }
  if (spoilerChildren.isEmpty) {
    return TextSpan(
      style: textStyle ?? theme.textStyle,
      children: children,
    );
  }
  final revealedSpan = MarkdownParagraphSpan._(
    style: textStyle ?? theme.textStyle,
    children: children,
    spoilerChildren: spoilerChildren,
    spoilerRanges: spoilerRanges,
    revealed: true,
  );
  return revealed ? revealedSpan : revealedSpan.withSpoilers(revealed: false);
}

/// The [TextSpan] [paragraphFromMarkdownSpans] returns when the paragraph has
/// a `||spoiler||`: the revealed and the hidden form of one text, and where
/// the spoilers sit in it.
///
/// A hidden spoiler is the same text with a transparent colour, not a
/// different string and not a different font, so every glyph box is identical
/// in both forms. Swapping them on a laid-out `TextPainter` is a paint-only
/// change: Flutter keeps the layout and rebuilds only the paragraph it paints.
/// That is what lets a reveal swap glyph pictures without a relayout.
///
/// Paragraphs with no spoiler stay plain [TextSpan]s.
// The counterpart cache is a lazily built memo of an otherwise immutable value.
// ignore: must_be_immutable
final class MarkdownParagraphSpan extends TextSpan {
  MarkdownParagraphSpan._({
    required super.style,
    required List<InlineSpan> super.children,
    required List<int> spoilerChildren,
    required this.spoilerRanges,
    required this.revealed,
  }) : _spoilerChildren = spoilerChildren;

  /// The text ranges of the spoilers, in [toPlainText] offsets, adjacent runs
  /// merged, in reading order.
  final List<TextRange> spoilerRanges;

  /// Whether the spoiler runs show their text.
  final bool revealed;

  /// Indices in [children] of the spans that belong to a spoiler.
  final List<int> _spoilerChildren;

  /// The other form of the same paragraph, built on first use.
  ///
  /// Cached on both sides so flipping back and forth allocates nothing and
  /// hands `TextPainter.text` the very instance it held before.
  MarkdownParagraphSpan? _counterpart;

  /// This paragraph with its spoilers shown or concealed per [revealed].
  MarkdownParagraphSpan withSpoilers({required bool revealed}) {
    if (revealed == this.revealed) return this;
    return _counterpart ??= _buildCounterpart();
  }

  MarkdownParagraphSpan _buildCounterpart() {
    final source = children!;
    final next = MarkdownParagraphSpan._(
      style: style,
      children: List<InlineSpan>.of(source),
      spoilerChildren: _spoilerChildren,
      spoilerRanges: spoilerRanges,
      revealed: !revealed,
    );
    final target = next.children!;
    for (final i in _spoilerChildren) {
      final child = source[i];
      // Only text can be made transparent; an inline placeholder is hidden by
      // its own painter (the live pass fades it under the spoiler).
      if (child is! TextSpan) continue;
      target[i] = revealed ? _concealed(child) : child;
    }
    next._counterpart = this;
    return next;
  }

  /// Colour, decoration colour and background only: any other change would be
  /// a layout change to `TextPainter`, which must not happen on a reveal. (A
  /// text shadow therefore stays; the fill covers it.)
  static TextSpan _concealed(TextSpan span) {
    const clear = Color(0x00000000);
    final base = span.style ?? const TextStyle();
    return TextSpan(
      text: span.text,
      recognizer: span.recognizer,
      children: span.children,
      style: base.copyWith(
        color: clear,
        decorationColor: clear,
        backgroundColor: clear,
      ),
    );
  }
}

/// The spoiler side of a `TextPainter` whose text came from
/// [paragraphFromMarkdownSpans].
extension MarkdownSpoilerPainter on TextPainter {
  /// Whether the painter's text has any `||spoiler||` run.
  bool get hasSpoilers {
    final span = text;
    return span is MarkdownParagraphSpan && span.spoilerRanges.isNotEmpty;
  }

  /// Shows or conceals the spoiler runs without a relayout. A no-op for a
  /// painter with no spoiler.
  void setSpoilersRevealed(bool revealed) {
    final span = text;
    if (span is! MarkdownParagraphSpan) return;
    text = span.withSpoilers(revealed: revealed);
  }

  /// Painter-local boxes of the spoiler runs: one rect per line a spoiler
  /// crosses, as tall as the line. Valid after layout; empty without a
  /// spoiler.
  ///
  /// `getBoxesForSelection` returns a box per style run (`||a **b** c||` is
  /// three), so boxes that touch on one line are joined: the fill must read as
  /// one patch, with no seam where the style changes.
  List<Rect> get spoilerBoxes {
    final span = text;
    if (span is! MarkdownParagraphSpan) return const <Rect>[];
    final rects = <Rect>[];
    for (final range in span.spoilerRanges) {
      final boxes = getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
        boxHeightStyle: BoxHeightStyle.max,
      );
      for (final box in boxes) {
        var rect = box.toRect();
        // Joining can chain (a, c, then the b between them), so re-scan.
        for (var i = 0; i < rects.length;) {
          final other = rects[i];
          final sameLine = (other.top - rect.top).abs() < 0.5 &&
              (other.bottom - rect.bottom).abs() < 0.5;
          if (sameLine &&
              other.left <= rect.right + 0.5 &&
              rect.left <= other.right + 0.5) {
            rect = rect.expandToInclude(other);
            rects.removeAt(i);
          } else {
            i++;
          }
        }
        rects.add(rect);
      }
    }
    return rects;
  }
}

/// The in-bounds, ordered, non-empty ranges of [runs] for a text of [length]
/// code units.
///
/// A scanner is the host's code, and a range outside the text would throw
/// inside a build, so a range that is empty, backwards, out of bounds or
/// overlapping the one before is dropped, not trusted.
List<TextRange> _validRuns(Iterable<TextRange> runs, int length) {
  final valid = <TextRange>[];
  var floor = 0;
  for (final run in runs) {
    if (!run.isValid || run.isCollapsed) continue;
    if (run.start < floor || run.end > length) continue;
    valid.add(run);
    floor = run.end;
  }
  return valid;
}

/// The style of an emoji run in text of [style]: a font size that makes the
/// emoji's square [MarkdownThemeData.emojiScale] times the font's height, and
/// the line height of the text around it.
///
/// A colour emoji font draws its glyph into a square of the font size, however
/// tall the line is, so the font size of the run is the wanted square. The
/// run's own line would be the emoji font's, taller than the text's, and every
/// emoji would add to the line's height with its size; `height` pins it to the
/// text's line, which is the style's own multiple of the font size or, without
/// one, the font's ascent plus descent. What remains is what an emoji at the
/// font size always did: the emoji font splits that line with a deeper descent
/// than the text's, so a line that holds one can be a pixel taller than a line
/// of text alone, whatever the glyph's size.
TextStyle _emojiRunStyle(TextStyle style, MarkdownThemeData theme) {
  final metrics = _probeMetrics(style, theme, 1);
  final fontHeight = metrics.ascent + metrics.descent;
  final square = fontHeight * theme.emojiScale;
  final line = switch (style.height) {
    final multiple? => multiple * metrics.fontSize,
    null => fontHeight,
  };
  return TextStyle(
    // `fontSize` is scaled again by the paragraph's text scaler, and `square`
    // is already in scaled pixels: undo it, so the glyph is `square` on screen.
    fontSize: (style.fontSize ?? kDefaultFontSize) * square / metrics.fontSize,
    height: line / square,
  );
}

/// The font metrics an embed in text of [style] is sized from.
///
/// Read from a one-line probe layout of the font alone: Android sizes its
/// embeds from the font's ascent and descent, so a `TextStyle.height` that
/// stretches the line must not stretch the embed. The probe therefore carries
/// only what picks the font, not the line height, letter spacing or colour.
MarkdownInlineEmbedMetrics _probeMetrics(
  TextStyle style,
  MarkdownThemeData theme,
  double devicePixelRatio,
) {
  final fontSize = style.fontSize ?? kDefaultFontSize;
  final probe = TextPainter(
    text: TextSpan(
      text: 'x',
      style: TextStyle(
        fontFamily: style.fontFamily,
        fontFamilyFallback: style.fontFamilyFallback,
        fontSize: fontSize,
        fontWeight: style.fontWeight,
        fontStyle: style.fontStyle,
        fontFeatures: style.fontFeatures,
        fontVariations: style.fontVariations,
        locale: style.locale,
      ),
    ),
    textDirection: theme.textDirection,
    textScaler: theme.textScaler,
  )..layout();
  final line = probe.computeLineMetrics().first;
  probe.dispose();
  return MarkdownInlineEmbedMetrics(
    fontSize: theme.textScaler.scale(fontSize),
    ascent: line.ascent,
    descent: line.descent,
    devicePixelRatio: devicePixelRatio,
  );
}
