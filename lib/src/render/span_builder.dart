//ignore_for_file: unnecessary_import

import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../nodes.dart';
import '../theme.dart';

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
        span.style.contains(MD$Style.highlight)) {
      return true;
    }
  }
  return false;
}

/// Helper function to create a [TextSpan] from markdown spans.
/// This function filters the spans based on the theme's span filter,
/// and applies the appropriate text style to each span.
///
/// With [revealed] false the `||spoiler||` runs get a transparent colour (see
/// [MarkdownParagraphSpan]); their metrics are the revealed ones, so no glyph
/// moves between the two forms. The default shows the text, as before.
TextSpan paragraphFromMarkdownSpans({
  required Iterable<MD$Span> spans,
  required MarkdownThemeData theme,
  TextStyle? textStyle,
  bool revealed = true,
}) {
  final style = textStyle ?? theme.textStyle;
  final spanFilter = theme.spanFilter;
  final filtered = spanFilter != null ? spans.where(spanFilter) : spans;
  // With an explicit block style, merge it under each span's own style;
  // otherwise the span style stands alone (the block style is applied once, on
  // the parent TextSpan below).
  final merge = textStyle != null;
  TextSpan mapper(MD$Span span) => TextSpan(
        text: span.text,
        style: merge
            ? theme.textStyleFor(span.style).merge(style)
            : theme.textStyleFor(span.style),
        recognizer: switch (span.style) {
          final s when s.contains(MD$Style.link) =>
            _buildTapRecognizer(span, theme.onLinkTap),
          final s when s.contains(MD$Style.mention) =>
            _buildMentionRecognizer(span, theme.onMentionTap),
          _ => null,
        },
      );
  final children = <InlineSpan>[];
  final spoilerChildren = <int>[];
  final spoilerRanges = <TextRange>[];
  var offset = 0;
  for (final span in filtered) {
    if (span.style.contains(MD$Style.spoiler)) {
      spoilerChildren.add(children.length);
      final end = offset + span.text.length;
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
    children.add(mapper(span));
    offset += span.text.length;
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
