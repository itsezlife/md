//ignore_for_file: unnecessary_import

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../inline_embed.dart';
import '../nodes.dart';
import '../theme.dart';
import 'inline_embeds.dart';

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
/// With [embeds], an image span whose `src` names an embed its resolver knows
/// becomes a placeholder that takes the embed's room in the paragraph (see
/// [MarkdownEmbedSpan]). Any other image span, and every image span when
/// [embeds] is null, stays the alt text it always was.
TextSpan paragraphFromMarkdownSpans({
  required Iterable<MD$Span> spans,
  required MarkdownThemeData theme,
  TextStyle? textStyle,
  MarkdownEmbedHost? embeds,
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
    return TextSpan(
      text: span.text,
      style: spanStyle,
      recognizer: switch (span.style) {
        final s when s.contains(MD$Style.link) =>
          _buildTapRecognizer(span, theme.onLinkTap),
        final s when s.contains(MD$Style.mention) =>
          _buildMentionRecognizer(span, theme.onMentionTap),
        _ => null,
      },
    );
  }

  return TextSpan(
    style: textStyle ?? theme.textStyle,
    children: filtered.map<InlineSpan>(mapper).toList(growable: false),
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
