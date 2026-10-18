import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart' as meta show internal;

import '../inline_embed.dart';

/// The inline span of one resolved [MarkdownInlineEmbed]: a placeholder that
/// takes the embed's room in its paragraph and paints nothing itself.
///
/// Not a `WidgetSpan`: there is no widget and no child render object, only a
/// box in the paragraph layout that the painter draws the embed into.
///
/// The span is one U+FFFC code unit in the [TextPainter]'s text while the
/// reference reads as [MarkdownInlineEmbedTarget.alt] everywhere else, which is
/// what the offset map in `embed_offset_map.dart` bridges.
@meta.internal
final class MarkdownEmbedSpan extends PlaceholderSpan {
  /// Reserves room for [embed], whose reference is [target].
  ///
  /// The box is `embed.size.width` wide and `layoutHeight` tall, centred on
  /// the middle of the line ([ui.PlaceholderAlignment.middle]). `layoutHeight`
  /// is the font's height, not the embed's: the taller embed is drawn
  /// centred on that box and overflows it by the same amount above and
  /// below, so the line is exactly as tall as it is without the embed.
  const MarkdownEmbedSpan({
    required this.embed,
    required this.target,
    required this.layoutHeight,
    super.style,
  }) : super(alignment: ui.PlaceholderAlignment.middle);

  /// The embed this span makes room for. Owned by the `MarkdownEmbedHost`
  /// that resolved it, not by the span.
  final MarkdownInlineEmbed embed;

  /// What the reference asked for; its [MarkdownInlineEmbedTarget.alt] is the
  /// text selection and copy see in place of the placeholder.
  final MarkdownInlineEmbedTarget target;

  /// Height of the layout box, logical pixels.
  final double layoutHeight;

  /// The rectangle the embed is drawn into, given the layout [box] the
  /// paragraph reserved for this span: [embed]'s size, centred on [box].
  Rect paintRectFor(Rect box) => Rect.fromCenter(
        center: box.center,
        width: embed.size.width,
        height: embed.size.height,
      );

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    final hasStyle = style != null;
    if (hasStyle) {
      builder.pushStyle(style!.getTextStyle(textScaler: textScaler));
    }
    // The size is the embed's own, in logical pixels: it was derived from the
    // already scaled font, so the text scaler must not scale it again and
    // [dimensions] (which a `RenderParagraph` fills for widgets) is not used.
    builder.addPlaceholder(embed.size.width, layoutHeight, alignment);
    if (hasStyle) builder.pop();
  }

  @override
  bool visitChildren(InlineSpanVisitor visitor) => visitor(this);

  @override
  bool visitDirectChildren(InlineSpanVisitor visitor) => true;

  @override
  InlineSpan? getSpanForPositionVisitor(
    TextPosition position,
    Accumulator offset,
  ) {
    if (position.offset == offset.value) return this;
    offset.increment(1);
    return null;
  }

  @override
  int? codeUnitAtVisitor(int index, Accumulator offset) {
    final localOffset = index - offset.value;
    offset.increment(1);
    return localOffset == 0 ? PlaceholderSpan.placeholderCodeUnit : null;
  }

  @override
  RenderComparison compareTo(InlineSpan other) {
    if (identical(this, other)) return RenderComparison.identical;
    if (other is! MarkdownEmbedSpan) return RenderComparison.layout;
    if (!identical(embed, other.embed) ||
        layoutHeight != other.layoutHeight ||
        (style == null) != (other.style == null)) {
      return RenderComparison.layout;
    }
    return style?.compareTo(other.style!) ?? RenderComparison.identical;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownEmbedSpan &&
          super == other &&
          identical(other.embed, embed) &&
          other.layoutHeight == layoutHeight;

  @override
  int get hashCode =>
      Object.hash(super.hashCode, identityHashCode(embed), layoutHeight);

  // [PlaceholderSpan] asserts false here to steer callers to `WidgetSpan`; this
  // is the intended subclass.
  @override
  bool debugAssertIsValid() => true;
}

/// Owns every [MarkdownInlineEmbed] a markdown body resolved.
///
/// One host serves one `MarkdownPainter`. Block painters ask it for embeds
/// while they build their paragraphs, and the painter disposes what is left on
/// a model rebuild and on its own dispose. A block painter that rebuilds its
/// paragraphs on every layout (lists, tables) releases the old ones first, so
/// an embed never outlives the paragraph that reserved room for it.
@meta.internal
final class MarkdownEmbedHost {
  /// Creates a host that resolves through [resolver] for a display of
  /// [devicePixelRatio].
  MarkdownEmbedHost({
    required this.resolver,
    required this.devicePixelRatio,
  });

  /// Where every embed comes from.
  final MarkdownInlineEmbedResolver resolver;

  /// Pixels per logical pixel; embeds are sized to whole device pixels.
  final double devicePixelRatio;

  // Identity, not equality: an embed implementation is free to define `==`.
  final Set<MarkdownInlineEmbed> _live = Set<MarkdownInlineEmbed>.identity();

  /// A new embed for [target], or null when the resolver does not know it.
  /// The host owns the result.
  MarkdownInlineEmbed? resolve(
    MarkdownInlineEmbedTarget target,
    MarkdownInlineEmbedMetrics metrics,
  ) {
    final embed = resolver.resolve(target, metrics);
    if (embed != null) _live.add(embed);
    return embed;
  }

  /// Disposes every embed whose placeholder is in [text]. A no-op for ones
  /// already released, so a paragraph may be released twice.
  void releaseIn(InlineSpan? text) {
    if (text == null || _live.isEmpty) return;
    text.visitChildren((span) {
      if (span is MarkdownEmbedSpan && _live.remove(span.embed)) {
        span.embed.dispose();
      }
      return true;
    });
  }

  /// Disposes everything still held. The host stays usable.
  void disposeAll() {
    if (_live.isEmpty) return;
    final embeds = List<MarkdownInlineEmbed>.of(_live);
    _live.clear();
    for (final embed in embeds) {
      embed.dispose();
    }
  }
}
