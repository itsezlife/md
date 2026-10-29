import 'dart:async' show scheduleMicrotask;
import 'dart:collection' show LinkedHashMap;
import 'dart:math' as math;
import 'dart:ui' as ui show ParagraphBuilder, PlaceholderAlignment;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart' as meta show internal;

import '../image.dart';
import 'chip.dart';
import 'embed_offset_map.dart';

/// An inline slot in a [TextSpan] tree where a [MarkdownImage] is painted.
///
/// [paragraphFromMarkdownSpans] emits one for every image (and link icon) a
/// [MarkdownThemeData.imageResolver] resolves. A [TextPainter] whose text holds
/// one must be laid out with [layoutMarkdownText] and painted with
/// [paintMarkdownText].
///
/// In the painter's text the slot is a single object replacement character,
/// while in the Markdown model it stands for [modelText] (the alt text, or
/// nothing for a link icon); the selection mixins translate between the two,
/// so selection offsets stay those of `markdownBlockRenderedText`.
class MarkdownImageSpan extends PlaceholderSpan {
  /// Creates a slot for [image] standing for [modelText] in the model, inside
  /// text styled by [textStyle].
  MarkdownImageSpan({
    required this.image,
    required this.request,
    required this.modelText,
    required this.textStyle,
    this.recognizer,
  }) : super(alignment: image.alignment);

  /// The picture painted in this slot.
  final MarkdownImage image;

  /// The request [image] was resolved for.
  final MarkdownImageRequest request;

  /// The model text this slot replaces: the alt text of an image, empty for a
  /// link icon.
  final String modelText;

  /// The effective style of the surrounding text.
  final TextStyle textStyle;

  /// The recognizer fired by a tap on the slot (a link icon opens its link).
  final GestureRecognizer? recognizer;

  /// The constraints of the last [layoutMarkdownText] of this slot.
  MarkdownImageConstraints? get constraints => _spanConstraints[this];

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    final index = builder.placeholderCount;
    if (dimensions != null && index < dimensions.length) {
      final d = dimensions[index];
      builder.addPlaceholder(
        d.size.width,
        d.size.height,
        d.alignment,
        baseline: d.baseline,
        baselineOffset: d.baselineOffset,
      );
      return;
    }
    // Laid out with a plain `TextPainter.layout` (a custom painter that skips
    // [layoutMarkdownText]): reserve a text-sized square so the text still
    // lays out; nothing is painted in it.
    final side = textScaler.scale(textStyle.fontSize ?? kDefaultFontSize);
    builder.addPlaceholder(side, side, ui.PlaceholderAlignment.middle);
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
    // Like a TextSpan: an upstream position belongs to the character before
    // it, a downstream one to the character after it.
    final target = position.affinity == TextAffinity.upstream
        ? position.offset - 1
        : position.offset;
    if (target == offset.value) return this;
    offset.increment(1);
    return null;
  }

  @override
  int? codeUnitAtVisitor(int index, Accumulator offset) {
    final local = index - offset.value;
    offset.increment(1);
    return local == 0 ? PlaceholderSpan.placeholderCodeUnit : null;
  }

  @override
  RenderComparison compareTo(InlineSpan other) => identical(this, other)
      ? RenderComparison.identical
      : RenderComparison.layout;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownImageSpan &&
          identical(other.image, image) &&
          other.modelText == modelText &&
          other.textStyle == textStyle &&
          other.recognizer == recognizer;

  @override
  int get hashCode => Object.hash(image, modelText, textStyle, recognizer);

  @override
  bool debugAssertIsValid() => true;
}

/// The constraints each slot was last measured under ([InlineSpan]s are
/// immutable, so the layout state lives beside them).
final Expando<MarkdownImageConstraints> _spanConstraints =
    Expando<MarkdownImageConstraints>('markdownImageConstraints');

/// Lays out [painter] like [TextPainter.layout], first measuring every
/// [MarkdownImageSpan] in its text so the line reserves room for them.
///
/// Use it instead of `painter.layout(...)` for text built with
/// [paragraphFromMarkdownSpans].
void layoutMarkdownText(
  TextPainter painter, {
  double minWidth = 0,
  double maxWidth = double.infinity,
}) {
  final map = _mapOf(painter);
  final placeholders = map.placeholders;
  if (placeholders.isNotEmpty) {
    final textScaler = painter.textScaler;
    final textDirection = painter.textDirection ?? TextDirection.ltr;
    final pool = MarkdownImagePool._active;
    painter.setPlaceholderDimensions(<PlaceholderDimensions>[
      for (final span in placeholders)
        if (span is MarkdownImageSpan)
          _measure(span, maxWidth, textScaler, textDirection, pool)
        else
          PlaceholderDimensions.empty,
    ]);
  }
  painter.layout(minWidth: minWidth, maxWidth: maxWidth);
}

PlaceholderDimensions _measure(
  MarkdownImageSpan span,
  double maxWidth,
  TextScaler textScaler,
  TextDirection textDirection,
  MarkdownImagePool? pool,
) {
  final constraints = _spanConstraints[span] = MarkdownImageConstraints(
    maxWidth: maxWidth,
    textStyle: span.textStyle,
    textScaler: textScaler,
    textDirection: textDirection,
  );
  final measured = span.image.layout(constraints);
  pool?._recordLayout(span.image, constraints, measured);
  final size = _slotSize(measured);
  final alignment = span.alignment;
  final onBaseline = alignment == ui.PlaceholderAlignment.baseline ||
      alignment == ui.PlaceholderAlignment.aboveBaseline ||
      alignment == ui.PlaceholderAlignment.belowBaseline;
  return PlaceholderDimensions(
    size: size,
    alignment: alignment,
    baseline: onBaseline ? TextBaseline.alphabetic : null,
    baselineOffset: onBaseline ? size.height : null,
  );
}

/// Sanitizes a measured slot size. A `0 × 0` placeholder trips a SkParagraph
/// bug (its box collapses to `Rect.zero` at the paragraph origin), so an empty
/// slot keeps a hairline width.
Size _slotSize(Size size) {
  double clean(double v) => v.isFinite && v > 0 ? v : 0;
  final width = clean(size.width), height = clean(size.height);
  if (width == 0 && height == 0) return const Size(0.01, 0);
  return Size(width, height);
}

/// Paints [painter] like [TextPainter.paint] at [offset], then every
/// [MarkdownImage] of its text into the slot reserved by [layoutMarkdownText].
/// Inline chips (their fills under the text, their glyphs over it) are
/// painted too.
void paintMarkdownText(TextPainter painter, Canvas canvas, Offset offset) =>
    painter.paintWithChips(canvas, offset);

/// Paints every [MarkdownImage] of [painter]'s text into the slot reserved by
/// [layoutMarkdownText], [painter] itself painted at [offset].
@meta.internal
void paintMarkdownImages(TextPainter painter, Canvas canvas, Offset offset) {
  final placeholders = _mapOf(painter).placeholders;
  if (placeholders.isEmpty) return;
  final boxes = painter.inlinePlaceholderBoxes;
  if (boxes == null) return;
  final count = math.min(boxes.length, placeholders.length);
  for (var i = 0; i < count; i++) {
    final span = placeholders[i];
    if (span is! MarkdownImageSpan) continue;
    final constraints = _spanConstraints[span];
    if (constraints == null) continue;
    span.image.paint(canvas, boxes[i].toRect().shift(offset), constraints);
  }
}

/// The recognizer of the span under a tap — a [TextSpan]'s own, or a link
/// icon's — or null.
@meta.internal
GestureRecognizer? markdownSpanRecognizer(InlineSpan? span) => switch (span) {
      TextSpan(:final recognizer) => recognizer,
      MarkdownImageSpan(:final recognizer) => recognizer,
      _ => null,
    };

/// The span under [local] (text-painter coordinates): the placeholder (a
/// picture or an inline embed) whose box contains it, else the span at the
/// nearest text position.
///
/// The nearest-position lookup alone misses placeholders: past the middle of
/// a slot it lands after the placeholder, on the neighbouring text.
@meta.internal
InlineSpan? markdownSpanAtLocal(TextPainter painter, Offset local) {
  final entry = MarkdownEmbedOffsets.of(painter).entryAt(painter, local);
  if (entry != null) return entry.span ?? entry.image;
  return painter.text?.getSpanForPosition(painter.getPositionForOffset(local));
}

/// The text position, in model offsets, nearest to [local] (text-painter
/// coordinates).
///
/// On a picture it is the edge of the slot on the hit side, in either text
/// direction — the nearest-caret lookup alone resolves a whole right-to-left
/// slot to its end.
///
/// Over an inline embed (the room it reserved or the square it is drawn
/// into, which pokes out above and below) the offset is *inside* its alt
/// text, whichever half of the embed the point is in, so the embed takes part
/// in the selection whichever way the drag goes: the selection snaps a first
/// boundary down to the alt's start and a last boundary up to its end. An alt
/// of fewer than two code units has no inside, and the point resolves to the
/// nearer edge.
@meta.internal
(int, TextAffinity) markdownPositionForLocal(
  TextPainter painter,
  Offset local,
) {
  final offsets = MarkdownEmbedOffsets.of(painter);
  final entry = offsets.entryAt(painter, local);
  if (entry == null) {
    final position = painter.getPositionForOffset(local);
    return (offsets.toRendered(position.offset), position.affinity);
  }
  if (entry.span != null && entry.alt.length >= 2) {
    return (entry.renderedStart + 1, TextAffinity.downstream);
  }
  final box = painter.inlinePlaceholderBoxes![entry.placeholderIndex];
  final leftHalf = local.dx < (box.left + box.right) / 2;
  final before = leftHalf == (box.direction == TextDirection.ltr);
  return before
      ? (entry.renderedStart, TextAffinity.downstream)
      : (entry.renderedEnd, TextAffinity.upstream);
}

/// The word range, in model offsets, at [local] (text-painter coordinates).
/// A picture or an inline embed is a word of its own: its whole alt text. A
/// link icon selects the first word of its label.
@meta.internal
TextRange markdownWordBoundary(TextPainter painter, Offset local) {
  final offsets = MarkdownEmbedOffsets.of(painter);
  final entry = offsets.entryAt(painter, local);
  var offset = -1;
  if (entry != null) {
    final image = entry.image;
    if (image == null ||
        image.request.kind != MarkdownImageKind.linkIcon ||
        image.request.text.isEmpty) {
      // A picture is one word; an icon without a label selects nothing.
      return TextRange(start: entry.renderedStart, end: entry.renderedEnd);
    }
    offset = entry.painterStart + 1; // The label follows its icon.
  }
  if (offset < 0) offset = painter.getPositionForOffset(local).offset;
  final word = painter.getWordBoundary(TextPosition(offset: offset));
  return TextRange(
    start: offsets.toRendered(word.start),
    end: offsets.toRendered(word.end),
  );
}

// --- Model ↔ painter offsets ---------------------------------------------
//
// One map serves pictures, inline embeds and chips: [MarkdownEmbedOffsets].

/// The model text of [painter]: its plain text with every placeholder
/// replaced by the model text it stands for (a picture's alt text, an embed's
/// alt, nothing for a link icon or a chip glyph).
@meta.internal
String markdownModelText(TextPainter painter) =>
    MarkdownEmbedOffsets.of(painter).renderedText(painter.plainText);

/// Whether [span] contains a [MarkdownImageSpan] (a picture or link icon).
@meta.internal
bool markdownSpanHasImages(InlineSpan? span) {
  var found = false;
  span?.visitChildren((child) => !(found = child is MarkdownImageSpan));
  return found;
}

/// Maps a model offset of [painter]'s text to a painter offset. An offset
/// strictly inside an alt text snaps to the slot's start, or to its end when
/// [end] is set (the end of a range), so a range touching any part of the alt
/// text covers the whole picture.
@meta.internal
int markdownPainterOffset(TextPainter painter, int model, {bool end = false}) =>
    MarkdownEmbedOffsets.of(painter).toPainter(model, end: end);

/// Maps a painter offset of [painter]'s text to a model offset.
@meta.internal
int markdownModelOffset(TextPainter painter, int offset) =>
    MarkdownEmbedOffsets.of(painter).toRendered(offset);

final class _TextMap {
  _TextMap(this.text, this.placeholders);

  /// The painter text this map was built from (identity cache key).
  final InlineSpan? text;

  /// Every placeholder of the text, in paragraph order.
  final List<PlaceholderSpan> placeholders;
}

final Expando<_TextMap> _textMaps = Expando<_TextMap>('markdownTextMap');

_TextMap _mapOf(TextPainter painter) {
  final text = painter.text;
  final cached = _textMaps[painter];
  if (cached != null && identical(cached.text, text)) return cached;
  final placeholders = <PlaceholderSpan>[];
  text?.visitChildren((span) {
    if (span is PlaceholderSpan) placeholders.add(span);
    return true;
  });
  return _textMaps[painter] = _TextMap(text, placeholders);
}

// --- Ownership --------------------------------------------------------------

/// Owns the [MarkdownImage]s of one rendered document.
///
/// While [run] executes (the painter building and laying out its blocks),
/// [resolveMarkdownImage] routes requests here: a request seen before returns
/// the same image, so repeated pictures and streaming rebuilds reuse one
/// loaded image. Images no block asked for since the last [nextGeneration]
/// are disposed by [sweep]. A `null` resolution is remembered too: a request
/// is resolved once per resolver while it stays in the document.
///
/// Each image's notifications are turned into [onChanged] — `true` when an
/// occurrence's measured size changed (re-layout), `false` for a repaint.
@meta.internal
final class MarkdownImagePool {
  /// Creates a pool reporting image changes to [onChanged].
  MarkdownImagePool(this.onChanged);

  /// Called when an owned image changed; `relayout` when its size did.
  final void Function(bool relayout) onChanged;

  static MarkdownImagePool? _active;

  final Map<MarkdownImageRequest, _PoolEntry> _byRequest =
      <MarkdownImageRequest, _PoolEntry>{};
  final Map<MarkdownImage, _PoolEntry> _byImage =
      LinkedHashMap<MarkdownImage, _PoolEntry>.identity();

  int _generation = 0;
  bool _changedWhileActive = false;
  bool _disposed = false;

  /// The number of live images, for tests.
  @visibleForTesting
  int get length => _byImage.length;

  /// Runs [body] with this pool receiving image requests.
  T run<T>(T Function() body) {
    final previous = _active;
    _active = this;
    try {
      return body();
    } finally {
      _active = previous;
      if (_changedWhileActive) {
        _changedWhileActive = false;
        // A notification during layout cannot mark the render object dirty
        // (it is being laid out); re-check right after.
        scheduleMicrotask(() {
          if (!_disposed) onChanged(_sizesChanged());
        });
      }
    }
  }

  /// Starts a new document generation: images not requested again before the
  /// next [sweep] are disposed.
  void nextGeneration() => _generation++;

  /// Forgets the measured sizes; a layout records them again.
  void clearLayouts() {
    for (final entry in _byImage.values) {
      entry.layouts.clear();
    }
  }

  MarkdownImage? _resolve(
    MarkdownImageResolver resolver,
    MarkdownImageRequest request,
  ) {
    final known = _byRequest[request];
    if (known != null) {
      known.generation = _generation;
      return known.image;
    }
    final image = _callResolver(resolver, request);
    final entry = _PoolEntry(image, _generation);
    _byRequest[request] = entry;
    if (image != null) {
      final previous = _byImage[image];
      if (previous != null) {
        // A resolver handed out an instance it already returned: share it.
        previous.generation = _generation;
        _byRequest[request] = previous;
        return image;
      }
      _byImage[image] = entry;
      image.addListener(entry.listener = () => _handleChange(entry));
    }
    return image;
  }

  void _recordLayout(
    MarkdownImage image,
    MarkdownImageConstraints constraints,
    Size size,
  ) =>
      _byImage[image]?.layouts[constraints] = size;

  void _handleChange(_PoolEntry entry) {
    if (_disposed) return;
    if (identical(_active, this)) {
      _changedWhileActive = true;
      return;
    }
    onChanged(_entryChangedSize(entry));
  }

  bool _entryChangedSize(_PoolEntry entry) {
    final image = entry.image;
    if (image == null) return false;
    for (final MapEntry(key: constraints, value: size)
        in entry.layouts.entries) {
      if (image.layout(constraints) != size) return true;
    }
    return false;
  }

  bool _sizesChanged() => _byImage.values.any(_entryChangedSize);

  /// Disposes every image not requested in the current generation.
  void sweep() {
    _byRequest.removeWhere((_, entry) => entry.generation < _generation);
    final stale = <_PoolEntry>[
      for (final entry in _byImage.values)
        if (entry.generation < _generation) entry,
    ];
    for (final entry in stale) {
      _byImage.remove(entry.image);
      entry.dispose();
    }
  }

  /// Disposes every image (a new resolver makes them all stale).
  void clear() {
    for (final entry in _byImage.values) {
      entry.dispose();
    }
    _byImage.clear();
    _byRequest.clear();
  }

  /// Disposes every image and stops reporting changes.
  void dispose() {
    _disposed = true;
    clear();
  }
}

final class _PoolEntry {
  _PoolEntry(this.image, this.generation);

  final MarkdownImage? image;
  int generation;
  VoidCallback? listener;
  final Map<MarkdownImageConstraints, Size> layouts =
      <MarkdownImageConstraints, Size>{};

  void dispose() {
    final image = this.image;
    if (image == null) return;
    final listener = this.listener;
    if (listener != null) image.removeListener(listener);
    image.dispose();
  }
}

/// Resolves [request] through the pool of the document being built or laid
/// out, or straight through [resolver] outside one.
@meta.internal
MarkdownImage? resolveMarkdownImage(
  MarkdownImageResolver resolver,
  MarkdownImageRequest request,
) {
  final pool = MarkdownImagePool._active;
  return pool == null
      ? _callResolver(resolver, request)
      : pool._resolve(resolver, request);
}

/// Calls [resolver], reporting a throw and rendering the alt text instead.
MarkdownImage? _callResolver(
  MarkdownImageResolver resolver,
  MarkdownImageRequest request,
) {
  try {
    return resolver(request);
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'flutter_md',
      context: ErrorDescription('resolving $request'),
    ));
    return null;
  }
}
