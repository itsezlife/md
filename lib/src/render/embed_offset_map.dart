import 'package:flutter/painting.dart';
import 'package:meta/meta.dart' as meta show internal;

import 'inline_embeds.dart';

/// Where one embed sits in a paragraph, in both offset spaces.
@meta.internal
final class MarkdownEmbedEntry {
  const MarkdownEmbedEntry._({
    required this.span,
    required this.placeholderIndex,
    required this.painterStart,
    required this.renderedStart,
    required this.alt,
  });

  /// The placeholder span.
  final MarkdownEmbedSpan span;

  /// Index of the placeholder among the paragraph's placeholders, which is
  /// its index in `TextPainter.inlinePlaceholderBoxes`.
  final int placeholderIndex;

  /// Offset of the placeholder's U+FFFC in the painter's text.
  final int painterStart;

  /// Offset where the alt text starts in the rendered text.
  final int renderedStart;

  /// The alt text the placeholder stands for.
  final String alt;

  /// Offset just past the alt text in the rendered text.
  int get renderedEnd => renderedStart + alt.length;

  /// Whether a selection of [range] (rendered offsets of this paragraph)
  /// takes the embed in.
  ///
  /// The alt text is atomic, so a selection covers it whole or not at all. An
  /// embed with no alt text has no text to cover; it is in when the selection
  /// reaches past it on both sides.
  bool isCoveredBy(TextRange range) {
    if (range.start >= range.end) return false;
    if (alt.isEmpty) {
      return range.start < renderedStart && renderedEnd < range.end;
    }
    return range.start <= renderedStart && renderedEnd <= range.end;
  }
}

/// The two offset spaces of a paragraph with embeds, and the map between them.
///
/// The `TextPainter` lays out one U+FFFC code unit per embed, but selection,
/// copy and hit-testing speak the block's *rendered text*, where the embed is
/// its alt text and may be any number of code units (the model's span text,
/// see `markdownBlockRenderedText`). This value converts offsets between
/// the two, and is the identity for a paragraph with no embed.
///
/// The alt text is atomic: no offset the map hands to the painter lies inside
/// it. A rendered offset strictly inside an alt text maps to the embed's near
/// edge when it starts a range and to the far edge when it ends one.
@meta.internal
final class MarkdownEmbedOffsets {
  const MarkdownEmbedOffsets._(this.entries);

  /// The map of a paragraph without embeds.
  static const MarkdownEmbedOffsets identity =
      MarkdownEmbedOffsets._(<MarkdownEmbedEntry>[]);

  /// The map of [text], the span a `TextPainter` was given.
  factory MarkdownEmbedOffsets.ofSpan(InlineSpan? text) {
    if (text == null) return identity;
    final entries = <MarkdownEmbedEntry>[];
    var painterOffset = 0;
    var placeholders = 0;
    var shift = 0; // rendered minus painter offset, before the next embed.
    void walk(InlineSpan span) {
      switch (span) {
        case TextSpan(:final text, :final children):
          painterOffset += text?.length ?? 0;
          if (children != null) children.forEach(walk);
        case MarkdownEmbedSpan():
          entries.add(MarkdownEmbedEntry._(
            span: span,
            placeholderIndex: placeholders,
            painterStart: painterOffset,
            renderedStart: painterOffset + shift,
            alt: span.target.alt,
          ));
          shift += span.target.alt.length - 1;
          placeholders++;
          painterOffset++;
        case PlaceholderSpan():
          placeholders++;
          painterOffset++;
        default:
          painterOffset +=
              span.toPlainText(includeSemanticsLabels: false).length;
      }
    }

    walk(text);
    return entries.isEmpty ? identity : MarkdownEmbedOffsets._(entries);
  }

  /// The map of [painter]'s current text.
  ///
  /// Read on every pointer move, so it is remembered per painter and only
  /// rebuilt when the painter is given another text.
  factory MarkdownEmbedOffsets.of(TextPainter painter) {
    final text = painter.text;
    final cached = _cache[painter];
    if (cached != null && identical(cached.text, text)) return cached.offsets;
    final offsets = MarkdownEmbedOffsets.ofSpan(text);
    _cache[painter] = _Cached(text, offsets);
    return offsets;
  }

  static final Expando<_Cached> _cache = Expando<_Cached>('embedOffsets');

  /// The embeds of the paragraph, in text order.
  final List<MarkdownEmbedEntry> entries;

  /// Whether the paragraph has no embed, so both spaces are the same.
  bool get isIdentity => entries.isEmpty;

  /// The rendered text for a painter text of [painterText]: each U+FFFC an
  /// embed stands for becomes its alt text.
  String renderedText(String painterText) {
    if (isIdentity) return painterText;
    final out = StringBuffer();
    var from = 0;
    for (final entry in entries) {
      out
        ..write(painterText.substring(from, entry.painterStart))
        ..write(entry.alt);
      from = entry.painterStart + 1;
    }
    return (out..write(painterText.substring(from))).toString();
  }

  /// Length of the rendered text for a painter text of [painterLength].
  int renderedLength(int painterLength) {
    var length = painterLength;
    for (final entry in entries) {
      length += entry.alt.length - 1;
    }
    return length;
  }

  /// The rendered offset of the painter offset [painterOffset].
  int toRendered(int painterOffset) {
    var shift = 0;
    for (final entry in entries) {
      if (entry.painterStart >= painterOffset) break;
      shift += entry.alt.length - 1;
    }
    return painterOffset + shift;
  }

  /// The painter offset of the rendered offset [renderedOffset].
  ///
  /// An offset strictly inside an alt text is not an offset of the painter;
  /// it lands on the embed's start, or, for the [end] of a range, just past it.
  int toPainter(int renderedOffset, {bool end = false}) {
    var shift = 0;
    for (final entry in entries) {
      if (renderedOffset <= entry.renderedStart) break;
      if (renderedOffset < entry.renderedEnd) {
        return end ? entry.painterStart + 1 : entry.painterStart;
      }
      shift += entry.alt.length - 1;
    }
    return renderedOffset - shift;
  }

  /// The embed whose box holds [local], a point in [painter]'s coordinates,
  /// or null. The box is the room the paragraph reserved united with the
  /// square the embed is drawn into, which pokes out above and below it.
  ///
  /// Needs [painter] laid out.
  MarkdownEmbedEntry? entryAt(TextPainter painter, Offset local) {
    if (isIdentity) return null;
    final boxes = painter.inlinePlaceholderBoxes;
    if (boxes == null) return null;
    for (final entry in entries) {
      if (entry.placeholderIndex >= boxes.length) continue;
      final box = boxes[entry.placeholderIndex].toRect();
      if (box.contains(local) || entry.span.paintRectFor(box).contains(local)) {
        return entry;
      }
    }
    return null;
  }

  /// [range] grown to cover every alt text it only partly covers.
  TextRange snap(TextRange range) {
    if (isIdentity) return range;
    var start = range.start;
    var end = range.end;
    for (final entry in entries) {
      if (start > entry.renderedStart && start < entry.renderedEnd) {
        start = entry.renderedStart;
      }
      if (end > entry.renderedStart && end < entry.renderedEnd) {
        end = entry.renderedEnd;
      }
    }
    return TextRange(start: start, end: end);
  }
}

final class _Cached {
  const _Cached(this.text, this.offsets);

  final InlineSpan? text;
  final MarkdownEmbedOffsets offsets;
}
