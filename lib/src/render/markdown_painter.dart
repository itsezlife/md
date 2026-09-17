//ignore_for_file: unnecessary_import

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart' as meta show internal;

import '../markdown.dart';
import '../nodes.dart';
import '../selection.dart';
import '../theme.dart';
import 'block_painter.dart';
import 'blocks/alert.dart';
import 'blocks/code.dart';
import 'blocks/divider.dart';
import 'blocks/heading.dart';
import 'blocks/list.dart';
import 'blocks/paragraph.dart';
import 'blocks/quote.dart';
import 'blocks/spacer.dart';
import 'blocks/table.dart';

/// A painter for rendering markdown content via blocks and spans.
@meta.internal
class MarkdownPainter {
  /// Creates a [MarkdownPainter] instance.
  MarkdownPainter({
    required Markdown markdown,
    required MarkdownThemeData theme,
  })  : _markdown = markdown,
        _theme = theme,
        _isEmpty = markdown.isEmpty,
        _size = Size.zero {
    _rebuild();
  }

  /// Is the markdown entity empty?
  bool get isEmpty => _isEmpty;
  bool _isEmpty;

  /// Current markdown entity to render.
  Markdown _markdown;

  /// Current theme for the markdown widget.
  MarkdownThemeData _theme;

  /// The size of the painted markdown content.
  Size get size => _size;
  Size _size;

  /// Indicates if the layout needs to be recalculated.
  bool _needsLayout = true;

  Float32List _blockOffsets = Float32List(0);
  List<BlockPainter> _blockPainters = const <BlockPainter>[];

  /// Source `Markdown.blocks` index for each painter (differs from the painter
  /// index whenever a `blockFilter` drops blocks).
  List<int> _sourceIndices = const <int>[];

  /// Horizontal pan offsets for [HorizontallyPannableBlock]s, keyed by source
  /// block index. Survives [_rebuild] via content-anchored remapping so a
  /// theme / model identity change does not snap the viewport back to zero.
  /// Remount across engine recycle uses [MarkdownSelectionController] via
  /// [_selectionController].
  final Map<int, double> _horizontalPanBySource = <int, double>{};

  MarkdownSelectionController? _selectionController;
  Object? _documentId;

  /// Callback when block painters are disposed/replaced (active pan must stop).
  VoidCallback? onPaintersRebuilt;

  /// Wires the selection registry used to persist horizontal pans across
  /// surface dispose / remount. Pass nulls when the widget is non-selectable.
  /// Clears the local pan map when the controller / document identity changes
  /// so a rebind cannot poison the new document with stale local offsets.
  void bindHorizontalPanStore(
    MarkdownSelectionController? controller,
    Object? documentId,
  ) {
    if (!identical(controller, _selectionController) ||
        documentId != _documentId) {
      _horizontalPanBySource.clear();
      // Drop live pan immediately so a same-markdown documentId swap cannot
      // keep the previous offset until (or unless) layout runs.
      for (final painter in _blockPainters) {
        if (painter is HorizontallyPannableBlock) {
          painter.restoreScrollOffset(0);
        }
      }
    }
    _selectionController = controller;
    _documentId = documentId;
  }

  static BlockPainter _defaultBlockBuilder(
    MD$Block block,
    MarkdownThemeData theme,
  ) =>
      block.map<BlockPainter>(
        paragraph: (p) => BlockPainter$Paragraph(
          spans: p.spans,
          theme: theme,
        ),
        heading: (h) => BlockPainter$Heading(
          level: h.level,
          spans: h.spans,
          theme: theme,
        ),
        quote: (q) => BlockPainter$Quote(
          spans: q.spans,
          indent: q.indent,
          theme: theme,
        ),
        code: (c) => BlockPainter$Code(
          language: c.language,
          text: c.text,
          theme: theme,
        ),
        list: (l) => BlockPainter$List(
          items: l.items,
          theme: theme,
        ),
        divider: (d) => BlockPainter$Divider(
          theme: theme,
        ),
        table: (t) => BlockPainter$Table(
          header: t.header,
          rows: t.rows,
          alignments: t.alignments,
          theme: theme,
        ),
        alert: (a) => BlockPainter$Alert(
          alert: a.alert,
          spans: a.spans,
          theme: theme,
        ),
        spacer: (s) => BlockPainter$Spacer(
          count: s.count,
          theme: theme,
        ),
      );

  /// Rebuilds the block painters from the markdown blocks.
  /// This method is called whenever the markdown or theme changes.
  /// [preHarvested] supplies pans captured against the previous model (required
  /// when [_markdown] was already swapped before rebuild).
  void _rebuild({
    Map<int, (double offset, String text)>? preHarvested,
  }) {
    final harvested = preHarvested ?? _harvestHorizontalPans();
    for (final painter in _blockPainters) {
      painter.dispose();
    }
    onPaintersRebuilt?.call();
    _needsLayout = true; // Mark that layout needs to be recalculated.
    _size = Size.zero; // Reset size before rebuilding.
    final filter = _theme.blockFilter;
    final builder = _theme.builder ?? _defaultBlockBuilder;
    final blocks = _markdown.blocks;
    final painters = <BlockPainter>[];
    final sources = <int>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (filter != null && !filter(block)) continue;
      painters
          .add(builder(block, _theme) ?? _defaultBlockBuilder(block, _theme));
      sources.add(i);
    }
    _blockPainters = painters;
    _sourceIndices = sources;
    _blockOffsets = Float32List(_blockPainters.length);
    _remapHorizontalPans(harvested, blocks);
  }

  /// Harvests live pans with their rendered-text identity for remapping.
  Map<int, (double offset, String text)> _harvestHorizontalPans() {
    final out = <int, (double, String)>{};
    for (var i = 0; i < _blockPainters.length; i++) {
      final painter = _blockPainters[i];
      if (painter is! HorizontallyPannableBlock) continue;
      final source = _sourceIndices[i];
      if (painter.scrollOffset <= 0) continue;
      final text = markdownBlockRenderedText(_markdown.blocks[source]);
      out[source] = (painter.scrollOffset, text);
    }
    return out;
  }

  /// Restores harvested pans onto new painters by matching rendered text
  /// (content-anchored), falling back to the same source index when text
  /// still matches. Drops unmatched entries.
  void _remapHorizontalPans(
    Map<int, (double offset, String text)> harvested,
    List<MD$Block> blocks,
  ) {
    _horizontalPanBySource.clear();
    if (harvested.isEmpty) return;

    final usedOld = <int>{};
    for (var i = 0; i < _blockPainters.length; i++) {
      if (_blockPainters[i] is! HorizontallyPannableBlock) continue;
      final source = _sourceIndices[i];
      final newText = markdownBlockRenderedText(blocks[source]);

      // Prefer same-index when content still matches (streaming append).
      final same = harvested[source];
      if (same != null && same.$2 == newText && !usedOld.contains(source)) {
        _horizontalPanBySource[source] = same.$1;
        usedOld.add(source);
        continue;
      }

      // Content-anchored: find an unused harvested entry with equal text.
      for (final MapEntry(:key, :value) in harvested.entries) {
        if (usedOld.contains(key)) continue;
        if (value.$2 != newText) continue;
        _horizontalPanBySource[source] = value.$1;
        usedOld.add(key);
        break;
      }
    }
  }

  /// Records the live pan of [block] under its source block index so a later
  /// [_rebuild] or remount can [HorizontallyPannableBlock.restoreScrollOffset].
  void rememberHorizontalPan(HorizontallyPannableBlock block) {
    for (var i = 0; i < _blockPainters.length; i++) {
      if (!identical(_blockPainters[i], block)) continue;
      final source = _sourceIndices[i];
      if (block.scrollOffset > 0) {
        _horizontalPanBySource[source] = block.scrollOffset;
      } else {
        _horizontalPanBySource.remove(source);
      }
      final controller = _selectionController;
      final documentId = _documentId;
      if (controller != null && documentId != null) {
        controller.setHorizontalPanOffset(
          documentId,
          source,
          block.scrollOffset,
        );
      }
      return;
    }
  }

  double? _savedHorizontalPan(int sourceIndex) {
    final local = _horizontalPanBySource[sourceIndex];
    if (local != null) return local;
    final controller = _selectionController;
    final documentId = _documentId;
    if (controller == null || documentId == null) return null;
    return controller.horizontalPanOffset(documentId, sourceIndex);
  }

  /// Binary-searches the painter index whose vertical band contains [dy].
  int _blockIndexForDy(double dy) {
    var min = 0;
    var max = _blockOffsets.length;
    var idx = 0;
    while (min < max) {
      final mid = min + ((max - min) >> 1);
      final offset = _blockOffsets[mid];
      if (offset > dy) {
        max = mid;
      } else {
        idx = mid;
        if (offset == dy) break;
        min = mid + 1;
      }
    }
    return idx;
  }

  /// Maps a content-local [local] offset to `(sourceBlockIndex, offset)`, or
  /// null if the hit block does not support selection.
  (int, int)? positionForLocal(Offset local) {
    if (_blockPainters.isEmpty) return null;
    final idx = _blockIndexForDy(local.dy);
    final painter = _blockPainters[idx];
    if (painter is! SelectableBlockPainter) return null;
    final blockLocal = Offset(local.dx, local.dy - _blockOffsets[idx]);
    final len = painter.renderedText.length;
    final offset = painter.offsetForLocalPosition(blockLocal).clamp(0, len);
    return (_sourceIndices[idx], offset);
  }

  /// Maps a content-local [local] point to the word range at it, as
  /// `(sourceBlockIndex, TextRange)`, or null if the hit block is not
  /// selectable. Uses the platform word segmentation of the underlying painter.
  (int, TextRange)? wordBoundaryForLocal(Offset local) {
    if (_blockPainters.isEmpty) return null;
    final idx = _blockIndexForDy(local.dy);
    final painter = _blockPainters[idx];
    if (painter is! SelectableBlockPainter) return null;
    final blockLocal = Offset(local.dx, local.dy - _blockOffsets[idx]);
    final range = painter.wordBoundaryForLocal(blockLocal);
    final len = painter.renderedText.length;
    return (
      _sourceIndices[idx],
      TextRange(
        start: range.start.clamp(0, len),
        end: range.end.clamp(0, len),
      ),
    );
  }

  /// Whether an actionable link sits under a content-local [local] point.
  bool isLinkAtLocal(Offset local) {
    if (_blockPainters.isEmpty) return false;
    final idx = _blockIndexForDy(local.dy);
    final painter = _blockPainters[idx];
    if (painter is! SelectableBlockPainter) return false;
    final blockLocal = Offset(local.dx, local.dy - _blockOffsets[idx]);
    return painter.isLinkAtLocal(blockLocal);
  }

  /// The horizontally pannable block under [local], if any.
  HorizontallyPannableBlock? pannableBlockAt(Offset local) {
    if (_needsLayout || _isEmpty || _blockPainters.isEmpty) return null;
    if (local.dx < 0 ||
        local.dx >= _size.width ||
        local.dy < 0 ||
        local.dy >= _size.height) {
      return null;
    }
    final idx = _blockIndexForDy(local.dy);
    if (idx < 0 || idx >= _blockPainters.length) return null;
    final painter = _blockPainters[idx];
    if (painter is! HorizontallyPannableBlock || !painter.canPanHorizontally) {
      return null;
    }
    final top = _blockOffsets[idx];
    if (local.dy < top || local.dy >= top + painter.size.height) return null;
    if (local.dx > painter.size.width) return null;
    return painter;
  }

  /// Paints the selection highlight of every selectable block, using [rangeOf]
  /// to look up the selected rendered range for a source block index.
  /// Highlights for [HorizontallyPannableBlock]s are clipped to the block
  /// viewport so scrolled-off selection does not paint into neighboring UI.
  void paintHighlight(
    Canvas canvas,
    TextRange? Function(int sourceIndex) rangeOf,
    Paint paint,
  ) {
    for (var i = 0; i < _blockPainters.length; i++) {
      final painter = _blockPainters[i];
      if (painter is! SelectableBlockPainter) continue;
      final range = rangeOf(_sourceIndices[i]);
      if (range == null || range.start >= range.end) continue;
      final top = _blockOffsets[i];
      final boxes = painter.boxesForRange(range.start, range.end);
      if (painter is HorizontallyPannableBlock) {
        final viewport = Rect.fromLTWH(
          0,
          top,
          painter.size.width,
          painter.size.height,
        );
        canvas.save();
        canvas.clipRect(viewport);
        for (final rect in boxes) {
          canvas.drawRect(rect.shift(Offset(0, top)), paint);
        }
        canvas.restore();
      } else {
        for (final rect in boxes) {
          canvas.drawRect(rect.shift(Offset(0, top)), paint);
        }
      }
    }
  }

  /// Content-local rectangles covering the selection described by [rangeOf], in
  /// reading order. Same geometry [paintHighlight] draws, collected instead of
  /// painted — used to position selection handles, the magnifier and toolbar.
  /// Pannable-block boxes are intersected with the block viewport.
  List<Rect> selectionBoxes(TextRange? Function(int sourceIndex) rangeOf) {
    final out = <Rect>[];
    for (var i = 0; i < _blockPainters.length; i++) {
      final painter = _blockPainters[i];
      if (painter is! SelectableBlockPainter) continue;
      final range = rangeOf(_sourceIndices[i]);
      if (range == null || range.start >= range.end) continue;
      final top = _blockOffsets[i];
      final shift = Offset(0, top);
      if (painter is HorizontallyPannableBlock) {
        final viewport = Rect.fromLTWH(
          0,
          top,
          painter.size.width,
          painter.size.height,
        );
        for (final rect in painter.boxesForRange(range.start, range.end)) {
          final shifted = rect.shift(shift);
          final clipped = shifted.intersect(viewport);
          if (!clipped.isEmpty) out.add(clipped);
        }
      } else {
        for (final rect in painter.boxesForRange(range.start, range.end)) {
          out.add(rect.shift(shift));
        }
      }
    }
    return out;
  }

  /// Update the painter with new values.
  /// If the values are the same,
  /// no update is required and the method returns false.
  bool update({
    required Markdown markdown,
    required MarkdownThemeData theme,
  }) {
    if (identical(_markdown, markdown) && identical(_theme, theme))
      return false;
    // Harvest against the *current* model before swapping — otherwise
    // content-anchored remap would key pans by the new blocks' text.
    final harvested = _harvestHorizontalPans();
    _lastSize = null;
    _lastPicture = null;
    _markdown = markdown;
    _theme = theme;
    _isEmpty = markdown.isEmpty;
    _rebuild(preHarvested: harvested);
    return true; // Indicate that the painter was updated.
  }

  /// Invalidate cached layouts when system fonts change.
  /// This forces TextPainters to recreate their layouts with new fonts.
  void invalidateLayout() {
    _needsLayout = true;
    _lastSize = null;
    _lastPicture = null;
    // Dispose and rebuild all block painters to recreate TextPainters
    // with the new system fonts (_rebuild harvests horizontal pans first).
    _rebuild();
  }

  /// Layouts the markdown content with the given width.
  Size layout({required double maxWidth}) {
    if (_isEmpty) {
      _size = Size.zero;
      _needsLayout = false; // No need to layout if the markdown is empty.
      return _size; // If the markdown is empty, return zero size.
    }
    var width = .0, height = .0;
    final blocks = _blockPainters;
    if (_blockOffsets.length != blocks.length) {
      // Resize the block sizes array
      // if it does not match the number of painters.
      _blockOffsets = Float32List(blocks.length);
    }
    final offsets = _blockOffsets;
    for (var i = 0; i < blocks.length; i++) {
      offsets[i] = height;
      final block = blocks[i];
      final size = block.layout(maxWidth);
      if (block case final HorizontallyPannableBlock pannable) {
        final source = _sourceIndices[i];
        final saved = _savedHorizontalPan(source) ?? 0.0;
        pannable.restoreScrollOffset(saved);
        // Sync clamped value back to both stores (maxScroll may have shrunk).
        rememberHorizontalPan(pannable);
      }
      width = math.max(width, size.width);
      height += size.height;
    }
    _needsLayout = false; // No need to layout if the markdown is empty.
    return _size = Size(width, height);
  }

  /// Routes a tap-down / tap-up to the block under the pointer, re-basing the
  /// event's position into that block's local space (only taps are handled; the
  /// block painters use it to fire link recognizers).
  void handleEvent(PointerEvent event) {
    if (_blockPainters.isEmpty) return;
    if (event is! PointerDownEvent && event is! PointerUpEvent) return;

    final pos = event.localPosition;
    final idx = _blockIndexForDy(pos.dy);
    final blockLocal = Offset(pos.dx, pos.dy - _blockOffsets[idx]);
    switch (event) {
      case final PointerDownEvent down:
        _blockPainters[idx].handleTapDown(_rebased(down, blockLocal));
      case final PointerUpEvent up:
        _blockPainters[idx].handleTapUp(_rebased(up, blockLocal));
    }
  }

  /// Copies [event] with its position moved to [localPosition] (block-local),
  /// preserving every other pointer field. `PointerEvent` has no `copyWith`, so
  /// the passthrough is spelled out; the return type follows the input type.
  static T _rebased<T extends PointerEvent>(T event, Offset localPosition) {
    final rebased = switch (event) {
      PointerUpEvent() => PointerUpEvent(
          position: localPosition,
          viewId: event.viewId,
          timeStamp: event.timeStamp,
          pointer: event.pointer,
          kind: event.kind,
          device: event.device,
          buttons: event.buttons,
          obscured: event.obscured,
          pressure: event.pressure,
          pressureMin: event.pressureMin,
          pressureMax: event.pressureMax,
          distanceMax: event.distanceMax,
          size: event.size,
          radiusMajor: event.radiusMajor,
          radiusMinor: event.radiusMinor,
          radiusMin: event.radiusMin,
          radiusMax: event.radiusMax,
          orientation: event.orientation,
          tilt: event.tilt,
          embedderId: event.embedderId,
        ),
      _ => PointerDownEvent(
          position: localPosition,
          viewId: event.viewId,
          timeStamp: event.timeStamp,
          pointer: event.pointer,
          kind: event.kind,
          device: event.device,
          buttons: event.buttons,
          obscured: event.obscured,
          pressure: event.pressure,
          pressureMin: event.pressureMin,
          pressureMax: event.pressureMax,
          distanceMax: event.distanceMax,
          size: event.size,
          radiusMajor: event.radiusMajor,
          radiusMinor: event.radiusMinor,
          radiusMin: event.radiusMin,
          radiusMax: event.radiusMax,
          orientation: event.orientation,
          tilt: event.tilt,
          embedderId: event.embedderId,
        ),
    };
    return rebased as T;
  }

  /// The last size and picture used for painting.
  /// This is used to avoid unnecessary recreation of the canvas picture.
  /// If the size is the same as the last painted size,
  Size? _lastSize;

  /// The last picture used for painting,
  /// to avoid unnecessary recreation of the canvas picture.
  /// If the size is the same as the last painted size,
  /// we can reuse the last picture.
  Picture? _lastPicture;

  /// The markdown content to paint.
  ///
  /// Non-pannable blocks are recorded into a cached [Picture] keyed by size.
  /// [HorizontallyPannableBlock]s are painted live afterward (clip + translate
  /// inside each painter) so pan/fling never invalidates the glyph cache.
  void paint(Canvas canvas, Size size) {
    assert(
      !_needsLayout,
      'MarkdownPainter.paint() called without layout.',
    );
    assert(
      size.isFinite,
      'MarkdownPainter.paint() called with non-finite size: $size',
    );

    // Do not paint if the markdown is empty,
    // or if the size is empty or infinite.
    if (_isEmpty || size.isEmpty || size.isInfinite) return;

    if (_lastSize == size && _lastPicture != null) {
      // Reuse the glyph cache; pannable blocks still paint live below.
      canvas.drawPicture(_lastPicture!);
    } else {
      final recorder = PictureRecorder();
      final $canvas = Canvas(recorder);

      // Record only non-pannable blocks — pan offset must not be baked in.
      var overflow = _size.height > size.height;
      var offset = .0;
      for (var painter in _blockPainters) {
        if (overflow && offset > size.height) {
          break;
        }
        if (painter is! HorizontallyPannableBlock) {
          painter.paint($canvas, size, offset);
        }
        offset += painter.size.height;
      }

      final picture = recorder.endRecording();
      canvas.drawPicture(picture);
      _lastSize = size;
      _lastPicture?.dispose();
      _lastPicture = picture;
    }

    _paintPannableBlocks(canvas, size);
  }

  /// Paints [HorizontallyPannableBlock]s on the live canvas (outside the
  /// document [Picture]) so scroll offset changes only need [markNeedsPaint].
  void _paintPannableBlocks(Canvas canvas, Size size) {
    var overflow = _size.height > size.height;
    for (var i = 0; i < _blockPainters.length; i++) {
      final painter = _blockPainters[i];
      final offset = _blockOffsets[i];
      if (overflow && offset > size.height) break;
      if (painter is HorizontallyPannableBlock) {
        painter.paint(canvas, size, offset);
      }
    }
  }

  /// Whether the document glyph [Picture] is currently cached for [size].
  /// Exposed for tests asserting pan does not invalidate the cache.
  @visibleForTesting
  bool hasCachedPictureFor(Size size) =>
      _lastSize == size && _lastPicture != null;

  /// Live [HorizontallyPannableBlock] at painter index [painterIndex], if any.
  /// Exposed for tests asserting remount / remapped pan offsets.
  @visibleForTesting
  HorizontallyPannableBlock? pannablePainterAt(int painterIndex) {
    if (painterIndex < 0 || painterIndex >= _blockPainters.length) {
      return null;
    }
    final p = _blockPainters[painterIndex];
    return p is HorizontallyPannableBlock ? p : null;
  }

  /// Source-index → pan map after layout restore (tests).
  @visibleForTesting
  Map<int, double> get debugHorizontalPanBySource =>
      Map<int, double>.unmodifiable(_horizontalPanBySource);

  void dispose() {
    _lastPicture?.dispose();
    _lastPicture = null;
    _horizontalPanBySource.clear();
    onPaintersRebuilt = null;
    for (final painter in _blockPainters) {
      painter.dispose();
    }
    _blockPainters = const <BlockPainter>[];
  }
}
