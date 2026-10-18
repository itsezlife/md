//ignore_for_file: unnecessary_import

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart' as meta show internal;

import '../inline_embed.dart';
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
import 'embed_offset_map.dart';
import 'inline_embeds.dart';
import 'spoiler_particle_tile.dart';
import 'spoiler_phase.dart';

/// A painter for rendering markdown content via blocks and spans.
@meta.internal
class MarkdownPainter {
  /// Creates a [MarkdownPainter] instance.
  MarkdownPainter({
    required Markdown markdown,
    required MarkdownThemeData theme,
    MarkdownInlineEmbedResolver? embedResolver,
    double devicePixelRatio = 1.0,
  })  : _markdown = markdown,
        _theme = theme,
        _devicePixelRatio = devicePixelRatio,
        _isEmpty = markdown.isEmpty,
        _size = Size.zero {
    _embeds = _hostFor(embedResolver, devicePixelRatio);
    _rebuild();
  }

  /// Owns every embed the block painters resolved; null when the body has no
  /// resolver. Embeds are disposed whenever the block painters that reserved
  /// room for them are: on a rebuild and on [dispose].
  MarkdownEmbedHost? _embeds;

  /// Called when an embed says that what it paints has changed. The owner
  /// repaints; nothing is laid out again and the glyph picture stays.
  VoidCallback? onEmbedSignal;

  MarkdownEmbedHost? _hostFor(
    MarkdownInlineEmbedResolver? resolver,
    double devicePixelRatio,
  ) =>
      resolver == null
          ? null
          : MarkdownEmbedHost(
              resolver: resolver,
              devicePixelRatio: devicePixelRatio,
              onSignal: () => onEmbedSignal?.call(),
            );

  /// Whether any inline embed is alive in the blocks.
  bool get hasEmbeds => !(_embeds?.isEmpty ?? true);

  /// The pixel ratio embeds and the spoiler dust are rendered at.
  double _devicePixelRatio;

  /// Is the markdown entity empty?
  bool get isEmpty => _isEmpty;
  bool _isEmpty;

  /// Current markdown entity to render.
  Markdown _markdown;

  /// The markdown model currently painted by this painter.
  Markdown get markdown => _markdown;

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
  /// Remount across engine recycle uses [MarkdownHorizontalPanStore] via
  /// [_panStore].
  final Map<int, double> _horizontalPanBySource = <int, double>{};

  MarkdownHorizontalPanStore? _panStore;
  Object? _documentId;

  /// Callback when block painters are disposed/replaced (active pan must stop).
  VoidCallback? onPaintersRebuilt;

  /// Wires the pan store used to persist horizontal pans across surface dispose
  /// / remount. Pass nulls when the widget has no document id. Clears the local
  /// pan map when the store / document identity changes so a rebind cannot
  /// poison the new document with stale local offsets.
  void bindHorizontalPanStore(
    MarkdownHorizontalPanStore? store,
    Object? documentId,
  ) {
    if (!identical(store, _panStore) || documentId != _documentId) {
      _horizontalPanBySource.clear();
      // Drop live pan immediately so a same-markdown documentId swap cannot
      // keep the previous offset until (or unless) layout runs.
      for (final painter in _blockPainters) {
        if (painter is HorizontallyPannableBlock) {
          painter.restoreScrollOffset(0);
        }
      }
    }
    _panStore = store;
    _documentId = documentId;
  }

  /// Builds a block nested inside a quote / alert body.
  ///
  /// Routes through [MarkdownThemeData.builder] like a top-level block does —
  /// a host that replaces the code painter (a fence with a copy button, say)
  /// expects the same painter inside `> …` as outside it.
  static BlockPainter _nestedBlockBuilder(
    MD$Block block,
    MarkdownThemeData theme,
    MarkdownEmbedHost? embeds,
  ) =>
      _adopt(theme.builder?.call(block, theme), embeds) ??
      _defaultBlockBuilder(block, theme, embeds);

  /// Hands [embeds] to a list or table a theme builder made, which could not
  /// be given the host (it is internal) and builds its paragraphs at layout.
  /// Painters that build theirs in the constructor stay as they were made.
  static BlockPainter? _adopt(
      BlockPainter? painter, MarkdownEmbedHost? embeds) {
    switch (painter) {
      case BlockPainter$Table(inlineEmbeds: null):
        painter.inlineEmbeds = embeds;
      case BlockPainter$List(inlineEmbeds: null):
        painter.inlineEmbeds = embeds;
      default:
    }
    return painter;
  }

  static BlockPainter _defaultBlockBuilder(
    MD$Block block,
    MarkdownThemeData theme,
    MarkdownEmbedHost? embeds,
  ) =>
      block.map<BlockPainter>(
        paragraph: (p) => BlockPainter$Paragraph(
          spans: p.spans,
          theme: theme,
          inlineEmbeds: embeds,
        ),
        heading: (h) => BlockPainter$Heading(
          level: h.level,
          spans: h.spans,
          theme: theme,
          inlineEmbeds: embeds,
        ),
        quote: (q) => BlockPainter$Quote(
          spans: q.spans,
          indent: q.indent,
          theme: theme,
          inlineEmbeds: embeds,
          children: [
            for (final child in q.blocks)
              _nestedBlockBuilder(
                child,
                BlockPainter$Quote.inheritFrom(theme, child),
                embeds,
              ),
          ],
        ),
        code: (c) => BlockPainter$Code(
          language: c.language,
          text: c.text,
          theme: theme,
        ),
        list: (l) => BlockPainter$List(
          items: l.items,
          theme: theme,
          inlineEmbeds: embeds,
        ),
        divider: (d) => BlockPainter$Divider(
          theme: theme,
        ),
        table: (t) => BlockPainter$Table(
          header: t.header,
          rows: t.rows,
          alignments: t.alignments,
          theme: theme,
          inlineEmbeds: embeds,
        ),
        alert: (a) => BlockPainter$Alert(
          alert: a.alert,
          spans: a.spans,
          theme: theme,
          inlineEmbeds: embeds,
          children: [
            for (final child in a.blocks)
              _nestedBlockBuilder(child, theme, embeds),
          ],
        ),
        spacer: (s) => BlockPainter$Spacer(
          count: s.count,
          theme: theme,
        ),
      );

  /// Rebuilds the block painters from the markdown blocks.
  /// This method is called whenever the markdown or theme changes.
  /// [preHarvested] / [oldBlocks] supply pans captured against the previous
  /// model (required when [_markdown] was already swapped before rebuild).
  void _rebuild({
    Map<int, double>? preHarvested,
    List<MD$Block>? oldBlocks,
  }) {
    final harvested = preHarvested ?? _harvestHorizontalPanOffsets();
    final previousBlocks = oldBlocks ?? _markdown.blocks;
    for (final painter in _blockPainters) {
      painter.dispose();
    }
    _embeds?.disposeAll();
    onPaintersRebuilt?.call();
    _needsLayout = true; // Mark that layout needs to be recalculated.
    _size = Size.zero; // Reset size before rebuilding.
    // The indices below name the painters just disposed; [layout] refills them.
    _spoilerBlocks = const <int>{};
    _staticSpoilerRects.clear();
    final filter = _theme.blockFilter;
    final embeds = _embeds;
    final blocks = _markdown.blocks;
    final painters = <BlockPainter>[];
    final sources = <int>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (filter != null && !filter(block)) continue;
      painters.add(
        _adopt(_theme.builder?.call(block, _theme), embeds) ??
            _defaultBlockBuilder(block, _theme, embeds),
      );
      sources.add(i);
    }
    _blockPainters = painters;
    _sourceIndices = sources;
    _blockOffsets = Float32List(_blockPainters.length);
    _horizontalPanBySource
      ..clear()
      ..addAll(
        remapHorizontalPanOffsets(
          byBlock: harvested,
          oldBlocks: previousBlocks,
          newBlocks: blocks,
        ),
      );
  }

  /// Harvests live pans keyed by source block index.
  Map<int, double> _harvestHorizontalPanOffsets() {
    final out = <int, double>{};
    for (var i = 0; i < _blockPainters.length; i++) {
      final painter = _blockPainters[i];
      if (painter is! HorizontallyPannableBlock) continue;
      final source = _sourceIndices[i];
      if (painter.scrollOffset <= 0) continue;
      out[source] = painter.scrollOffset;
    }
    return out;
  }

  /// Records the live pan of [block] under its source block index so a later
  /// [_rebuild] or remount can [HorizontallyPannableBlock.restoreScrollOffset].
  ///
  /// When the block cannot pan (fits width, or a host gate refused gestures)
  /// a zero live offset must **not** clear the durable controller entry —
  /// otherwise a temporary fit or `enabled: false` rebuild wipes remount state.
  void rememberHorizontalPan(HorizontallyPannableBlock block) {
    for (var i = 0; i < _blockPainters.length; i++) {
      if (!identical(_blockPainters[i], block)) continue;
      final source = _sourceIndices[i];
      if (block.scrollOffset > 0) {
        _horizontalPanBySource[source] = block.scrollOffset;
      } else {
        _horizontalPanBySource.remove(source);
      }
      final store = _panStore;
      final documentId = _documentId;
      if (store == null || documentId == null) return;
      if (block.scrollOffset > 0) {
        store.setHorizontalPanOffset(
          documentId,
          source,
          block.scrollOffset,
        );
      } else if (block.canPanHorizontally) {
        // User scrolled back to the leading edge while still overflowing.
        store.setHorizontalPanOffset(documentId, source, 0);
      }
      // else: not pannable — leave the durable store alone.
      return;
    }
  }

  /// After a committing layout, rewrite the controller map from live painters
  /// so orphan indices from a putDocument/remount race cannot linger. Entries
  /// for live blocks that are temporarily not pannable are preserved.
  void syncHorizontalPanStore() {
    final store = _panStore;
    final documentId = _documentId;
    final existing = (store != null && documentId != null)
        ? store.horizontalPanOffsets(documentId)
        : null;
    final next = <int, double>{};
    _horizontalPanBySource.clear();
    for (var i = 0; i < _blockPainters.length; i++) {
      final painter = _blockPainters[i];
      if (painter is! HorizontallyPannableBlock) continue;
      final source = _sourceIndices[i];
      if (painter.scrollOffset > 0) {
        next[source] = painter.scrollOffset;
        _horizontalPanBySource[source] = painter.scrollOffset;
      } else if (painter.canPanHorizontally) {
        // Leading edge while overflowing — durable clear via [next] omit.
      } else {
        final kept = existing?[source];
        if (kept != null && kept > 0) next[source] = kept;
      }
    }
    if (store != null && documentId != null) {
      store.replaceHorizontalPanOffsets(documentId, next);
    }
  }

  double? _savedHorizontalPan(int sourceIndex) {
    final local = _horizontalPanBySource[sourceIndex];
    if (local != null) return local;
    final store = _panStore;
    final documentId = _documentId;
    if (store == null || documentId == null) return null;
    return store.horizontalPanOffset(documentId, sourceIndex);
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
    final hit = positionAndAffinityForLocal(local);
    return hit == null ? null : (hit.$1, hit.$2);
  }

  /// Like [positionForLocal] but also returns the soft-wrap [TextAffinity].
  (int, int, TextAffinity)? positionAndAffinityForLocal(Offset local) {
    if (_blockPainters.isEmpty) return null;
    final idx = _blockIndexForDy(local.dy);
    final painter = _blockPainters[idx];
    if (painter is! SelectableBlockPainter) return null;
    final blockLocal = Offset(local.dx, local.dy - _blockOffsets[idx]);
    final len = painter.renderedText.length;
    final (offset, affinity) = painter.positionAndAffinityForLocal(blockLocal);
    return (_sourceIndices[idx], offset.clamp(0, len), affinity);
  }

  /// Block-local caret rect for a source block [sourceIndex] at [offset] with
  /// [affinity], shifted into content-local coordinates. Null when the block
  /// is not painted or not selectable.
  Rect? caretRectFor(int sourceIndex, int offset, TextAffinity affinity) {
    for (var i = 0; i < _blockPainters.length; i++) {
      if (_sourceIndices[i] != sourceIndex) continue;
      final painter = _blockPainters[i];
      if (painter is! SelectableBlockPainter) return null;
      return painter
          .caretRectFor(offset, affinity)
          .shift(Offset(0, _blockOffsets[i]));
    }
    return null;
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

  /// Resolves the source block index and [MD$Block] at [local], or `null` if
  /// the point lies outside any painted block.
  (int, MD$Block)? blockAtLocal(Offset local) {
    if (_needsLayout || _isEmpty || _blockPainters.isEmpty) return null;
    if (local.dx < 0 ||
        local.dx >= _size.width ||
        local.dy < 0 ||
        local.dy >= _size.height) {
      return null;
    }
    final idx = _blockIndexForDy(local.dy);
    if (idx < 0 || idx >= _blockPainters.length) return null;
    final sourceIndex = _sourceIndices[idx];
    if (sourceIndex < 0 || sourceIndex >= _markdown.blocks.length) return null;
    return (sourceIndex, _markdown.blocks[sourceIndex]);
  }

  /// Whether the content under [local] belongs to selectable **glyph** ink
  /// (not empty max-width gutter to the right of a short line).
  bool isSelectableAtLocal(Offset local) {
    if (_needsLayout || _isEmpty || _blockPainters.isEmpty) return false;
    if (local.dx < 0 ||
        local.dx >= _size.width ||
        local.dy < 0 ||
        local.dy >= _size.height) {
      return false;
    }
    final idx = _blockIndexForDy(local.dy);
    if (idx < 0 || idx >= _blockPainters.length) return false;
    final painter = _blockPainters[idx];
    if (painter is! SelectableBlockPainter) return false;
    final blockLocal = Offset(local.dx, local.dy - _blockOffsets[idx]);
    return painter.hitsRenderedTextAt(blockLocal);
  }

  /// Paints the selection highlight of every selectable block, using [rangeOf]
  /// to look up the selected rendered range for a source block index.
  ///
  /// When [aboveCachedContentOnly] is true, only blocks that report
  /// [SelectableBlockPainter.selectionHighlightAboveCachedContent] are painted
  /// (opaque chrome that would hide an under-content highlight).
  /// Highlights for [HorizontallyPannableBlock]s are clipped to the block
  /// viewport so scrolled-off selection does not paint into neighboring UI.
  void paintHighlight(
    Canvas canvas,
    TextRange? Function(int sourceIndex) rangeOf,
    Paint paint, {
    bool aboveCachedContentOnly = false,
  }) {
    for (var i = 0; i < _blockPainters.length; i++) {
      final painter = _blockPainters[i];
      if (painter is! SelectableBlockPainter) continue;
      if (aboveCachedContentOnly !=
          painter.selectionHighlightAboveCachedContent) {
        continue;
      }
      final range = rangeOf(_sourceIndices[i]);
      if (range == null || range.start >= range.end) continue;
      final top = _blockOffsets[i];
      // One path for the block, drawn once: where two rectangles touch (the
      // lines of a paragraph, the runs of one line) there is no seam, and
      // where they overlap a translucent tint is not drawn twice.
      final shape = Path();
      for (final rect in painter.boxesForRange(range.start, range.end)) {
        shape.addRect(rect.shift(Offset(0, top)));
      }
      if (painter is HorizontallyPannableBlock) {
        canvas
          ..save()
          ..clipRect(
            Rect.fromLTWH(0, top, painter.size.width, painter.size.height),
          )
          ..drawPath(shape, paint)
          ..restore();
      } else {
        canvas.drawPath(shape, paint);
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

  /// Content-local rectangles covering the rendered text range
  /// `[startOffset, endOffset]` within the block at [blockIndex] (a source
  /// index in [Markdown.blocks]).
  ///
  /// Queries the cached block painter directly without re-layout, shifting
  /// rects by the block's vertical offset. Returns an empty list when the
  /// block is not painted, not selectable, or if `startOffset >= endOffset`.
  /// Pannable-block boxes are intersected with the block viewport.
  List<Rect> localBoxesForRange(
    int blockIndex,
    int startOffset,
    int endOffset,
  ) {
    if (_needsLayout || _isEmpty || _blockPainters.isEmpty) {
      return const <Rect>[];
    }
    if (startOffset >= endOffset) return const <Rect>[];
    for (var i = 0; i < _blockPainters.length; i++) {
      if (_sourceIndices[i] != blockIndex) continue;
      final painter = _blockPainters[i];
      if (painter is! SelectableBlockPainter) return const <Rect>[];
      final len = painter.renderedText.length;
      final start = startOffset.clamp(0, len);
      final end = endOffset.clamp(0, len);
      if (start >= end) return const <Rect>[];
      final top = _blockOffsets[i];
      final boxes = painter.boxesForRange(start, end);
      if (boxes.isEmpty) return const <Rect>[];
      final shift = Offset(0, top);
      if (painter is HorizontallyPannableBlock) {
        final viewport = Rect.fromLTWH(
          0,
          top,
          painter.size.width,
          painter.size.height,
        );
        final out = <Rect>[];
        for (final rect in boxes) {
          final clipped = rect.shift(shift).intersect(viewport);
          if (!clipped.isEmpty) out.add(clipped);
        }
        return out;
      }
      return <Rect>[
        for (final rect in boxes) rect.shift(shift),
      ];
    }
    return const <Rect>[];
  }

  /// The rendered ranges of every block that a selection boundary never
  /// splits (the alt text of each inline embed), by source block index.
  /// Empty when no block has an embed. Only valid after [layout].
  Map<int, List<TextRange>> atomicRanges() {
    Map<int, List<TextRange>>? out;
    for (var i = 0; i < _blockPainters.length; i++) {
      final painter = _blockPainters[i];
      final ranges = switch (painter) {
        SelectableTextBlock() => painter.atomicRanges,
        MultiPainterSelectable() => painter.atomicRanges,
        _ => const <TextRange>[],
      };
      if (ranges.isEmpty) continue;
      (out ??= <int, List<TextRange>>{})[_sourceIndices[i]] = ranges;
    }
    return out ?? const <int, List<TextRange>>{};
  }

  /// Update the painter with new values.
  /// If the values are the same,
  /// no update is required and the method returns false.
  ///
  /// A different [embedResolver] or [devicePixelRatio] rebuilds the blocks:
  /// the embeds they hold were made for the old ones.
  bool update({
    required Markdown markdown,
    required MarkdownThemeData theme,
    MarkdownInlineEmbedResolver? embedResolver,
    double devicePixelRatio = 1.0,
  }) {
    _devicePixelRatio = devicePixelRatio;
    final previousEmbeds = _embeds;
    final embedsChanged = !identical(previousEmbeds?.resolver, embedResolver) ||
        (previousEmbeds != null &&
            previousEmbeds.devicePixelRatio != devicePixelRatio);
    if (identical(_markdown, markdown) &&
        identical(_theme, theme) &&
        !embedsChanged) {
      _dropFillTileIfStale();
      return false;
    }
    if (embedsChanged) _embeds = _hostFor(embedResolver, devicePixelRatio);
    // Harvest against the *current* model before swapping — otherwise
    // content-anchored remap would key pans by the new blocks' text.
    final oldBlocks = _markdown.blocks;
    final harvested = _harvestHorizontalPanOffsets();
    _dropPictures();
    _markdown = markdown;
    _theme = theme;
    _dropFillTileIfStale();
    _isEmpty = markdown.isEmpty;
    _rebuild(preHarvested: harvested, oldBlocks: oldBlocks);
    // The old host's embeds are in painters that _rebuild just disposed.
    if (embedsChanged) previousEmbeds?.disposeAll();
    return true; // Indicate that the painter was updated.
  }

  /// Invalidate cached layouts when system fonts change.
  /// This forces TextPainters to recreate their layouts with new fonts.
  void invalidateLayout() {
    _needsLayout = true;
    _dropPictures();
    // Dispose and rebuild all block painters to recreate TextPainters
    // with the new system fonts (_rebuild harvests horizontal pans first).
    _rebuild();
  }

  /// Layouts the markdown content with the given width.
  ///
  /// When [commitHorizontalPan] is false (dry layout), pans are neither
  /// restored nor written to the durable store — a tentative narrower width
  /// must not clamp remount state before [performLayout] commits.
  Size layout({
    required double maxWidth,
    bool commitHorizontalPan = true,
  }) {
    _layoutCount++;
    if (_isEmpty) {
      _size = Size.zero;
      _needsLayout = false; // No need to layout if the markdown is empty.
      _findSpoilerBlocks();
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
      if (commitHorizontalPan) {
        if (block case final HorizontallyPannableBlock pannable) {
          final source = _sourceIndices[i];
          final saved = _savedHorizontalPan(source) ?? 0.0;
          pannable.restoreScrollOffset(saved);
        }
      }
      width = math.max(width, size.width);
      height += size.height;
    }
    if (commitHorizontalPan) {
      // Restore already applied above; rewrite local + controller from live
      // painters (drops orphan indices, keeps durable pans while !canPan).
      syncHorizontalPanStore();
    }
    _needsLayout = false; // No need to layout if the markdown is empty.
    _findSpoilerBlocks();
    return _size = Size(width, height);
  }

  /// Vertical positions where each visual text line ends, top-down.
  ///
  /// Positions are absolute in the laid-out content. Runs sharing a bottom
  /// edge — cells of a table row, a list bullet and its first line — count as
  /// one line. Blocks without text (spacer, divider) contribute no line of
  /// their own; their height still shows in the positions after them.
  ///
  /// Only valid after [layout].
  List<double> textLineBottoms() {
    if (_isEmpty) return const <double>[];
    final blocks = _blockPainters;
    if (_blockOffsets.length != blocks.length) return const <double>[];
    final bottoms = <double>[];
    for (var i = 0; i < blocks.length; i++) {
      final top = _blockOffsets[i];
      for (final (painter, offset, _) in _textFragments(blocks[i])) {
        var bottom = top + offset.dy;
        for (final line in painter.computeLineMetrics()) {
          bottom += line.height;
          bottoms.add(bottom);
        }
      }
    }
    bottoms.sort();
    final lines = <double>[];
    for (final bottom in bottoms) {
      // Runs of one line round to slightly different bottoms; a cut may only
      // land where every run on that line has ended.
      if (lines.isNotEmpty && bottom - lines.last < 1) {
        lines[lines.length - 1] = bottom;
        continue;
      }
      lines.add(bottom);
    }
    return lines;
  }

  /// Selectable text runs of [block], as `(painter, block-local origin, the
  /// index of the run's first character in the block's rendered text)`.
  static Iterable<(TextPainter, Offset, int)> _textFragments(
    BlockPainter block,
  ) {
    if (block is SelectableTextBlock) {
      return <(TextPainter, Offset, int)>[
        (
          block.selectionPainter,
          block.selectionOrigin,
          0,
        )
      ];
    }
    if (block is MultiPainterSelectable) {
      return block.fragments.map((f) => (f.painter, f.origin, f.textStart));
    }
    return const <(TextPainter, Offset, int)>[];
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

  // --- Spoilers -------------------------------------------------------------

  SpoilerPhase _spoilerPhase = const SpoilerPhase$Revealed();

  /// How the document's spoilers are drawn. [SpoilerPhase$Revealed] until the
  /// render object, which owns the [MarkdownSpoilerController] binding, says
  /// otherwise: without a controller there is nothing to hide behind.
  SpoilerPhase get spoilerPhase => _spoilerPhase;

  /// Moves the spoilers to [phase]. Returns whether it changed (the caller
  /// repaints). Never lays out and never records: the pictures are swapped on
  /// the next [paint].
  bool setSpoilerPhase(SpoilerPhase phase) {
    if (_spoilerPhase == phase) return false;
    _spoilerPhase = phase;
    return true;
  }

  /// Painter indices of the blocks with a spoiler run; set by [layout].
  Set<int> _spoilerBlocks = const <int>{};

  /// Content-local spoiler rects of the non-pannable blocks, by painter index.
  /// Valid until the next [layout]; pannable blocks move, so they are asked
  /// every time.
  final Map<int, List<Rect>> _staticSpoilerRects = <int, List<Rect>>{};

  /// Whether any block has a spoiler. Valid after [layout].
  bool get hasSpoilers => _spoilerBlocks.isNotEmpty;

  void _findSpoilerBlocks() {
    _staticSpoilerRects.clear();
    _spoilerBlocks = <int>{
      for (var i = 0; i < _blockPainters.length; i++)
        if (_blockPainters[i] case final SpoilerBlockPainter block
            when block.hasSpoilers)
          i,
    };
  }

  /// Content-local rectangles of every spoiler run, in reading order (a panned
  /// block's rects are panned and clipped to its viewport). Empty before
  /// layout and without a spoiler.
  List<Rect> get spoilerRects =>
      _needsLayout ? const <Rect>[] : _spoilerRects();

  List<Rect> _spoilerRects() {
    final out = <Rect>[];
    for (final i in _spoilerBlocks) {
      final block = _blockPainters[i] as SpoilerBlockPainter;
      out.addAll(
        block is HorizontallyPannableBlock
            ? _blockSpoilerRects(i, block)
            : _staticSpoilerRects[i] ??= _blockSpoilerRects(i, block),
      );
    }
    return out;
  }

  List<Rect> _blockSpoilerRects(int index, SpoilerBlockPainter block) {
    final shift = Offset(0, _blockOffsets[index]);
    final rects = <Rect>[
      for (final rect in block.spoilerRects) rect.shift(shift)
    ];
    if (block is! HorizontallyPannableBlock) return rects;
    final viewport = shift & block.size;
    return <Rect>[
      for (final rect in rects)
        if (rect.overlaps(viewport)) rect.intersect(viewport),
    ];
  }

  /// Whether [local] (content-local) is on a spoiler that is still hidden.
  /// During the ripple the document already counts as revealed.
  bool hiddenSpoilerAt(Offset local) {
    if (_needsLayout || _spoilerPhase is! SpoilerPhase$Hidden) return false;
    for (final rect in _spoilerRects()) {
      if (rect.contains(local)) return true;
    }
    return false;
  }

  /// The opacity an inline embed painted at the content-local [rect] must
  /// have: 0 while a spoiler hides it, the ripple's progress while it
  /// reveals, 1 anywhere else.
  ///
  /// The embeds themselves are painted by a live pass; this is the spoiler's
  /// half of that contract (Android's `insideSpoiler`).
  double embedOpacityAt(Rect rect) {
    if (_needsLayout || _spoilerBlocks.isEmpty) return 1;
    final inside = _spoilerRects().any((r) => r.contains(rect.center));
    if (!inside) return 1;
    return switch (_spoilerPhase) {
      SpoilerPhase$Hidden() => 0,
      SpoilerPhase$Revealing(:final progress) => progress,
      SpoilerPhase$Revealed() => 1,
    };
  }

  /// The dust tile this painter holds a share of, while any spoiler of it is
  /// hidden. One per `(text colour, pixel ratio)` in the process, so a screen
  /// of twenty hidden spoilers renders one tile.
  SpoilerParticleTile? _fillTile;

  /// The dust frame to paint, from the host's clock; null keeps the dust
  /// still (motion off, or no clock).
  int? _fillFrame;

  /// Sets the dust frame the next [paint] shows. Never lays out, never
  /// records a glyph picture; the render object repaints on it.
  void setSpoilerFillFrame(int? frame) => _fillFrame = frame;

  Color get _fillColor => _theme.textStyle.color ?? const Color(0xFF000000);

  /// The tile held now, if any. Exposed for tests asserting sharing and
  /// release.
  @visibleForTesting
  SpoilerParticleTile? get debugFillTile => _fillTile;

  /// Gives the tile up when the text colour or pixel ratio it was made for is
  /// no longer the painter's; the next fill takes the right one. A theme
  /// object that changed without changing colour keeps its tile - the dust
  /// would otherwise jump on every rebuild of a host that makes its theme in
  /// `build`.
  void _dropFillTileIfStale() {
    final tile = _fillTile;
    if (tile == null) return;
    if (tile.color == _fillColor &&
        tile.devicePixelRatio == _devicePixelRatio) {
      return;
    }
    _releaseFillTile();
  }

  void _releaseFillTile() {
    final tile = _fillTile;
    if (tile == null) return;
    _fillTile = null;
    SpoilerParticleTiles.release(tile);
  }

  /// The live pass over each spoiler that is still hidden: the particle tile,
  /// clipped to the spoiler's rounded rect. It is drawn above the glyph
  /// pictures and outside the ripple circle; nothing here records a picture.
  void _paintSpoilerFill(
    Canvas canvas,
    SpoilerPhase phase,
    _SpoilerRipple? ripple,
  ) {
    if (phase is SpoilerPhase$Revealed || _spoilerBlocks.isEmpty) {
      _releaseFillTile();
      return;
    }
    final tile = _fillTile ??=
        SpoilerParticleTiles.acquire(_fillColor, _devicePixelRatio);
    canvas.save();
    if (ripple != null) canvas.clipPath(ripple.hiddenSpoilers);
    var index = 0;
    for (final rect in _spoilerRects()) {
      tile.fill(
        canvas,
        SpoilerParticleTile.shapeOf(rect),
        SpoilerParticleTile.phaseOf(index++),
        frame: _fillFrame,
      );
    }
    canvas.restore();
  }

  // --- Glyph pictures -------------------------------------------------------

  /// The size both glyph pictures were recorded for.
  Size? _lastSize;

  /// The glyph picture with spoilers shown. The only picture a document with
  /// no spoiler (or a revealed one) ever has.
  Picture? _revealedPicture;

  /// The glyph picture with spoilers concealed. Dropped once the document is
  /// revealed: at most two pictures exist per size, and only while a ripple
  /// needs both.
  Picture? _hiddenPicture;

  int _pictureRecordings = 0;

  void _dropPictures() {
    _lastSize = null;
    _revealedPicture?.dispose();
    _revealedPicture = null;
    _hiddenPicture?.dispose();
    _hiddenPicture = null;
  }

  /// The glyph picture for [revealed], recorded on first use at [size].
  ///
  /// Only non-pannable blocks are recorded - pan offset must not be baked in.
  /// Each block is put in the requested spoiler state first; that is a
  /// paint-only text swap, never a layout.
  Picture _pictureFor(bool revealed, Size size) {
    final cached = revealed ? _revealedPicture : _hiddenPicture;
    if (cached != null) return cached;
    final recorder = PictureRecorder();
    final $canvas = Canvas(recorder);

    var overflow = _size.height > size.height;
    var offset = .0;
    for (var painter in _blockPainters) {
      if (overflow && offset > size.height) {
        break;
      }
      if (painter is! HorizontallyPannableBlock) {
        if (painter is SpoilerBlockPainter) painter.spoilersRevealed = revealed;
        painter.paint($canvas, size, offset);
      }
      offset += painter.size.height;
    }

    final picture = recorder.endRecording();
    _pictureRecordings++;
    if (revealed) {
      _revealedPicture = picture;
    } else {
      _hiddenPicture = picture;
    }
    return picture;
  }

  /// The markdown content to paint.
  ///
  /// Non-pannable blocks are recorded into cached glyph [Picture]s keyed by
  /// size. [HorizontallyPannableBlock]s are painted live afterward (clip +
  /// translate inside each painter) so pan/fling never invalidates the glyph
  /// cache. The spoiler fill is a live pass too, above the pictures: neither a
  /// fill repaint nor a ripple frame records a picture.
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

    if (_lastSize != size) {
      _dropPictures();
      _lastSize = size;
    }

    // A document with no spoiler has no phase: it is always "revealed".
    final phase =
        _spoilerBlocks.isEmpty ? const SpoilerPhase$Revealed() : _spoilerPhase;
    final ripple = phase is SpoilerPhase$Revealing
        ? _SpoilerRipple(phase, _spoilerRects(), size)
        : null;
    switch (phase) {
      case SpoilerPhase$Revealed():
        canvas.drawPicture(_pictureFor(true, size));
        _hiddenPicture?.dispose();
        _hiddenPicture = null;
      case SpoilerPhase$Hidden():
        canvas.drawPicture(_pictureFor(false, size));
      case SpoilerPhase$Revealing():
        // Inside the circle (and a spoiler) the revealed picture; everywhere
        // else the hidden one. The two clips are complementary, so nothing is
        // drawn twice - a translucent block background would otherwise
        // darken inside the circle.
        canvas
          ..save()
          ..clipPath(ripple!.outside)
          ..drawPicture(_pictureFor(false, size))
          ..restore()
          ..save()
          ..clipPath(ripple.inside)
          ..drawPicture(_pictureFor(true, size))
          ..restore();
    }

    _paintPannableBlocks(canvas, size, phase, ripple);
    _paintSpoilerFill(canvas, phase, ripple);
  }

  /// Paints [HorizontallyPannableBlock]s on the live canvas (outside the
  /// document [Picture]) so scroll offset changes only need [markNeedsPaint].
  ///
  /// A pannable block with spoilers is put in the state the [phase] asks for
  /// right before it paints; during a ripple it paints twice, once per side of
  /// the circle.
  void _paintPannableBlocks(
    Canvas canvas,
    Size size,
    SpoilerPhase phase,
    _SpoilerRipple? ripple,
  ) {
    var overflow = _size.height > size.height;
    for (var i = 0; i < _blockPainters.length; i++) {
      final painter = _blockPainters[i];
      final offset = _blockOffsets[i];
      if (overflow && offset > size.height) break;
      if (painter is! HorizontallyPannableBlock) continue;
      if (!_spoilerBlocks.contains(i)) {
        painter.paint(canvas, size, offset);
        continue;
      }
      // Only blocks that report a spoiler are in [_spoilerBlocks].
      final spoiler = painter as SpoilerBlockPainter;
      switch (phase) {
        case SpoilerPhase$Revealed():
          spoiler.spoilersRevealed = true;
          painter.paint(canvas, size, offset);
        case SpoilerPhase$Hidden():
          spoiler.spoilersRevealed = false;
          painter.paint(canvas, size, offset);
        case SpoilerPhase$Revealing():
          spoiler.spoilersRevealed = false;
          canvas
            ..save()
            ..clipPath(ripple!.outside);
          painter.paint(canvas, size, offset);
          canvas.restore();
          spoiler.spoilersRevealed = true;
          canvas
            ..save()
            ..clipPath(ripple.inside);
          painter.paint(canvas, size, offset);
          canvas.restore();
      }
    }
  }

  // --- Inline embeds: the live pass ---

  /// Paints every visible inline embed into the square its placeholder
  /// reserved, on the live canvas after the glyph [Picture] and the selection
  /// highlight.
  ///
  /// This is the third pass beside the cached picture and the pannable blocks:
  /// the placeholder paints nothing into the picture, so an embed that
  /// animates costs a repaint and never a re-recording or a layout. Blocks past
  /// the painted height are skipped by the guard that bounds the picture.
  ///
  /// An embed is never tinted: the highlight is behind it (as behind a glyph),
  /// so an opaque embed shows as it is and a transparent one shows the
  /// highlight through, and a hidden spoiler leaves nothing where an embed
  /// was. Android paints a selection under its emoji spans and images the
  /// same way (`ChatMessageCell` draws the selection, then the text layout
  /// with the spans).
  void paintEmbeds(Canvas canvas, Size size) {
    final host = _embeds;
    if (host == null || host.isEmpty) return;
    if (_needsLayout || _isEmpty || size.isEmpty || size.isInfinite) return;
    final overflow = _size.height > size.height;
    for (var i = 0; i < _blockPainters.length; i++) {
      final top = _blockOffsets[i];
      if (overflow && top > size.height) break;
      final block = _blockPainters[i];
      final panned = switch (block) {
        final PannedContent pannable => pannable.pushPanTransform(canvas, top),
        _ => false,
      };
      for (final (painter, origin, _) in _textFragments(block)) {
        final offsets = MarkdownEmbedOffsets.of(painter);
        if (offsets.isIdentity) continue;
        final boxes = painter.inlinePlaceholderBoxes;
        if (boxes == null) continue;
        final shift = origin + Offset(0, top);
        for (final entry in offsets.entries) {
          final embed = entry.span.embed;
          if (!embed.visible || entry.placeholderIndex >= boxes.length) {
            continue;
          }
          final rect = entry.span
              .paintRectFor(boxes[entry.placeholderIndex].toRect())
              .shift(shift);
          // A spoiler hides its embeds the way it hides glyphs (0 hidden, the
          // ripple's progress while revealing).
          final opacity = embedOpacityAt(rect);
          if (opacity > 0) {
            embed.paint(
                canvas, rect, _paintContextFor(painter, entry, opacity));
          }
        }
      }
      if (panned) canvas.restore();
    }
  }

  // The context of the last embed painted: a run of embeds in one colour and
  // opacity (nearly always all of them) shares one value instead of one each
  // per frame.
  MarkdownInlineEmbedPaintContext? _paintContext;

  // The tint is the colour of the text the embed sits in: its own span's, else
  // the paragraph's.
  MarkdownInlineEmbedPaintContext _paintContextFor(
    TextPainter painter,
    MarkdownEmbedEntry entry,
    double opacity,
  ) {
    final color = entry.span.style?.color ?? painter.text?.style?.color;
    final cached = _paintContext;
    if (cached != null && cached.tint == color && cached.opacity == opacity) {
      return cached;
    }
    return _paintContext =
        MarkdownInlineEmbedPaintContext(tint: color, opacity: opacity);
  }

  /// Sets [MarkdownInlineEmbed.visible] of every embed to whether its block is
  /// within the painted height [size] (the guard [paint] uses). Called after
  /// layout, not while painting: an embed may react to the change by
  /// scheduling a repaint, which a paint must not.
  void syncEmbedVisibility(Size size) {
    final host = _embeds;
    if (host == null || host.isEmpty || _needsLayout || _isEmpty) return;
    final overflow = _size.height > size.height;
    for (var i = 0; i < _blockPainters.length; i++) {
      final visible = !(overflow && _blockOffsets[i] > size.height);
      for (final (painter, _, _) in _textFragments(_blockPainters[i])) {
        for (final entry in MarkdownEmbedOffsets.of(painter).entries) {
          final embed = entry.span.embed;
          if (embed.visible != visible) embed.visible = visible;
        }
      }
    }
  }

  /// Hides every embed, for a painter that is leaving the tree.
  void hideEmbeds() => _embeds?.setAllVisible(visible: false);

  /// How many times [layout] ran. Exposed for tests asserting that an embed
  /// never lays the document out again.
  @visibleForTesting
  int get debugLayoutCount => _layoutCount;
  int _layoutCount = 0;

  /// Whether a glyph [Picture] is currently cached for [size].
  /// Exposed for tests asserting pan does not invalidate the cache.
  @visibleForTesting
  bool hasCachedPictureFor(Size size) =>
      _lastSize == size && (_revealedPicture != null || _hiddenPicture != null);

  /// How many glyph pictures have been recorded since this painter was made.
  /// Exposed for tests asserting a live pass never re-records.
  @visibleForTesting
  int get debugPictureRecordings => _pictureRecordings;

  /// How many glyph pictures are cached right now (at most two).
  @visibleForTesting
  int get debugCachedPictureCount =>
      (_revealedPicture == null ? 0 : 1) + (_hiddenPicture == null ? 0 : 1);

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
    _dropPictures();
    _releaseFillTile();
    _horizontalPanBySource.clear();
    onPaintersRebuilt = null;
    for (final painter in _blockPainters) {
      painter.dispose();
    }
    _blockPainters = const <BlockPainter>[];
    _embeds?.disposeAll();
  }
}

/// The geometry of one ripple frame, in content-local coordinates.
///
/// The circle grows from the tap point until it covers the farthest corner of
/// any spoiler (Android grows it to the diagonal of all spoiler bounds). It is
/// intersected with the spoiler rects: outside them the hidden and revealed
/// pictures are identical, so only the spoilers need to differ.
final class _SpoilerRipple {
  _SpoilerRipple(SpoilerPhase$Revealing phase, List<Rect> rects, Size size) {
    final region = Path();
    Rect? bounds;
    for (final rect in rects) {
      region.addRect(rect);
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    final origin = phase.origin ?? bounds?.center ?? Offset.zero;
    var farthest = 0.0;
    for (final rect in rects) {
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ]) {
        farthest = math.max(farthest, (corner - origin).distance);
      }
    }
    final circle = Path()
      ..addOval(
        Rect.fromCircle(center: origin, radius: farthest * phase.progress),
      );
    inside = Path.combine(PathOperation.intersect, region, circle);
    outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      inside,
    );
    hiddenSpoilers = Path.combine(PathOperation.difference, region, circle);
  }

  /// Spoiler area already revealed: the revealed picture shows here.
  late final Path inside;

  /// Everything else: the hidden picture shows here.
  late final Path outside;

  /// Spoiler area the circle has not reached: the fill still covers it.
  late final Path hiddenSpoilers;
}
