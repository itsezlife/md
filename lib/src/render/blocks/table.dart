//ignore_for_file: unnecessary_import

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:meta/meta.dart' as meta show internal;

import '../../nodes.dart';
import '../../theme.dart';
import '../block_painter.dart';
import '../inline_embeds.dart';
import '../inline_image.dart';
import '../span_builder.dart';

/// Viewport pan for a clipped overflowing table.
///
/// Owned only when the painter is pannable ([BlockPainter$ScrollableTable]).
/// [scrollOffset] `0` is the **leading** edge of the content in
/// [textDirection]: left in LTR, right in RTL (Flutter horizontal scroll).
final class _TablePanState {
  double scrollOffset = 0.0;
  double maxScroll = 0.0;
  double contentWidth = 0.0;

  bool get canPan => maxScroll > 0.0;

  /// Viewport-local → content-local.
  Offset toContent(Offset local, TextDirection direction) {
    final shift = direction == TextDirection.rtl
        ? maxScroll - scrollOffset
        : scrollOffset;
    return Offset(local.dx + shift, local.dy);
  }

  /// Content-local boxes → viewport-local.
  List<Rect> toViewport(List<Rect> boxes, TextDirection direction) {
    if (scrollOffset == 0.0 && direction == TextDirection.ltr) return boxes;
    final dx = direction == TextDirection.rtl
        ? -(maxScroll - scrollOffset)
        : -scrollOffset;
    if (dx == 0.0) return boxes;
    return <Rect>[for (final box in boxes) box.shift(Offset(dx, 0))];
  }

  /// Canvas translation applied inside the clipped viewport.
  double paintTranslationX(TextDirection direction) =>
      direction == TextDirection.rtl
          ? -maxScroll + scrollOffset
          : -scrollOffset;

  bool applyDelta(double deltaDx) {
    if (!canPan || deltaDx == 0.0) return false;
    final next = (scrollOffset + deltaDx).clamp(0.0, maxScroll);
    if (next == scrollOffset) return false;
    scrollOffset = next;
    return true;
  }

  void restore(double offset) {
    if (!canPan) {
      scrollOffset = 0.0;
      return;
    }
    scrollOffset = offset.clamp(0.0, maxScroll);
  }

  void updateExtents({
    required double contentWidth,
    required double viewportWidth,
  }) {
    this.contentWidth = contentWidth;
    if (contentWidth > viewportWidth + 0.5) {
      maxScroll = contentWidth - viewportWidth;
      scrollOffset = scrollOffset.clamp(0.0, maxScroll);
    } else {
      maxScroll = 0.0;
      scrollOffset = 0.0;
    }
  }
}

/// A class for painting a table block in markdown.
///
/// Wide column minima may exceed the layout max width (historical overflow).
/// For clip + pan, use [BlockPainter$ScrollableTable].
class BlockPainter$Table
    with ParagraphGestureHandler, MultiPainterSelectable
    implements BlockPainter, PannedContent {
  /// Creates a table painter for the [header] row and data [rows], with
  /// per-column [alignments], styled by [theme].
  BlockPainter$Table({
    required MD$TableRow header,
    required List<MD$TableRow> rows,
    required MarkdownThemeData theme,
    List<MD$TableColumnAlign> alignments = const <MD$TableColumnAlign>[],
    MarkdownEmbedHost? inlineEmbeds,
  }) : this._(
          header: header,
          rows: rows,
          theme: theme,
          alignments: alignments,
          inlineEmbeds: inlineEmbeds,
          pan: null,
        );

  /// Pannable layout — used by [BlockPainter$ScrollableTable].
  BlockPainter$Table._pannable({
    required MD$TableRow header,
    required List<MD$TableRow> rows,
    required MarkdownThemeData theme,
    List<MD$TableColumnAlign> alignments = const <MD$TableColumnAlign>[],
    MarkdownEmbedHost? inlineEmbeds,
  }) : this._(
          header: header,
          rows: rows,
          theme: theme,
          alignments: alignments,
          inlineEmbeds: inlineEmbeds,
          pan: _TablePanState(),
        );

  BlockPainter$Table._({
    required this.header,
    required this.rows,
    required this.theme,
    required this.alignments,
    required this.inlineEmbeds,
    required _TablePanState? pan,
  })  : _pan = pan,
        columns = header.cells.length,
        _columnWidths = List<double>.filled(header.cells.length, 0.0),
        _rowHeights = List<double>.filled(rows.length + 1, 0.0),
        _borderPaint = Paint()
          ..color = theme.dividerColor ?? const Color(0x1F000000)
          ..style = PaintingStyle.stroke
          ..isAntiAlias = false
          ..strokeWidth = 1.0,
        _rowBackgroundPaint = Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = false
          ..color =
              theme.surfaceColor ?? const Color.fromARGB(255, 235, 235, 235);

  /// Zebra row fills (and cell inline chrome) sit in the content [Picture];
  /// highlight must paint above that picture or it disappears under the fill.
  @override
  bool get selectionHighlightAboveCachedContent => true;

  /// Non-null only for [BlockPainter$ScrollableTable]. Keeps pan geometry off
  /// the default overflowing table.
  final _TablePanState? _pan;

  /// Padding for table cells.
  static const double padding = 8.0;

  /// The theme for the markdown table.
  final MarkdownThemeData theme;

  /// Where the cells' inline embeds come from, if the body has any.
  ///
  /// A painter a theme `builder` made has no way to be given the host, which
  /// is internal; `MarkdownPainter` sets it, before the first layout, on one
  /// that has none. Nothing else writes it.
  @meta.internal
  MarkdownEmbedHost? inlineEmbeds;

  /// The number of columns in the table.
  final int columns;

  /// The per-column alignment derived from the delimiter row.
  final List<MD$TableColumnAlign> alignments;

  /// Resolves the alignment for column [c], defaulting to
  /// [MD$TableColumnAlign.none] when unspecified.
  MD$TableColumnAlign _columnAlign(int c) => c >= 0 && c < alignments.length
      ? alignments[c]
      : MD$TableColumnAlign.none;

  /// The horizontal offset of a cell's text within its column, honoring the
  /// column alignment (falling back to centered headers and start-aligned
  /// data: left for left-to-right text, right for right-to-left).
  double _cellHorizontalPadding(int r, int c, double painterWidth) =>
      switch (_columnAlign(c)) {
        MD$TableColumnAlign.left => padding,
        MD$TableColumnAlign.center => (_columnWidths[c] - painterWidth) / 2,
        MD$TableColumnAlign.right => _columnWidths[c] - painterWidth - padding,
        MD$TableColumnAlign.none => (r == 0)
            ? (_columnWidths[c] - painterWidth) / 2
            : (_rtl ? _columnWidths[c] - painterWidth - padding : padding),
      };

  /// Whether the last layout mirrored the table for right-to-left text: the
  /// first column on the right, and the table against the right edge.
  bool _rtl = false;

  /// Block-local x of the table's left border.
  double _tableLeft = 0;

  /// Block-local x of each column's left edge.
  List<double> _columnLefts = const <double>[];

  final List<double> _columnWidths;
  final List<double> _rowHeights;
  final Paint _borderPaint;
  final Paint _rowBackgroundPaint;

  Float32List? _borderPoints;

  /// The header row of the table.
  final MD$TableRow header;

  /// The rows of the table.
  final List<MD$TableRow> rows;

  @override
  Size get size => _size;
  Size _size = Size.zero;

  List<List<TextPainter>> _cellPainters = const [];

  @override
  List<SelectableFragment> get fragments {
    if (_fragments == null) _rebuildFragments();
    return _fragments!;
  }

  List<SelectableFragment>? _fragments = const <SelectableFragment>[];

  @override
  String get renderedText {
    if (_renderedText == null) _rebuildFragments();
    return _renderedText!;
  }

  String? _renderedText = '';

  /// The width of the last layout, when it can be reused as is.
  double? _laidOutWidth;

  /// The natural and minimum column widths, once measured. They do not depend
  /// on the layout width unless the table holds pictures.
  List<double>? _naturalWidths;
  List<double>? _minimumWidths;

  /// Last span hit by the tap down event.
  InlineSpan? _lastSpan;

  bool get _canPanHorizontally => _pan?.canPan ?? false;

  double get _scrollOffset => _pan?.scrollOffset ?? 0.0;

  double get _maxScroll => _pan?.maxScroll ?? 0.0;

  Offset _toContent(Offset local) {
    final pan = _pan;
    if (pan == null) return local;
    return pan.toContent(local, theme.textDirection);
  }

  /// Pans content by [deltaDx] (positive reveals content on the trailing side).
  /// Returns true when the offset changed.
  bool _applyScrollDelta(double deltaDx) => _pan?.applyDelta(deltaDx) ?? false;

  /// Restores a previously saved pan after [layout] (clamped to the new max).
  void _restoreScrollOffset(double offset) => _pan?.restore(offset);

  // Selection / hit geometry is authored in content space; map viewport-local
  // pointers in and map boxes back out so chrome tracks the clipped paint.

  @override
  (int, TextAffinity) positionAndAffinityForLocal(Offset local) =>
      super.positionAndAffinityForLocal(_toContent(local));

  @override
  int offsetForLocalPosition(Offset local) =>
      super.offsetForLocalPosition(_toContent(local));

  @override
  Rect caretRectFor(int offset, TextAffinity affinity) {
    final rect = super.caretRectFor(offset, affinity);
    final pan = _pan;
    if (pan == null) return rect;
    return pan.toViewport(<Rect>[rect], theme.textDirection).first;
  }

  @override
  List<Rect> boxesForRange(int start, int end) {
    final boxes = super.boxesForRange(start, end);
    final pan = _pan;
    if (pan == null) return boxes;
    return pan.toViewport(boxes, theme.textDirection);
  }

  @override
  List<Rect> get spoilerRects {
    final rects = super.spoilerRects;
    final pan = _pan;
    if (pan == null) return rects;
    return pan.toViewport(rects, theme.textDirection);
  }

  @override
  TextRange wordBoundaryForLocal(Offset local) =>
      super.wordBoundaryForLocal(_toContent(local));

  @override
  bool isLinkAtLocal(Offset local) => super.isLinkAtLocal(_toContent(local));

  @override
  bool hitsRenderedTextAt(Offset local) {
    if (local.dx < 0 ||
        local.dx > _size.width ||
        local.dy < 0 ||
        local.dy > _size.height) {
      return false;
    }
    return super.hitsRenderedTextAt(_toContent(local));
  }

  @override
  void handleTapDown(PointerDownEvent event) {
    _lastSpan = null; // Reset the span on tap down.
    final span = _getSpanForOffset(_toContent(event.localPosition));
    if (span != null) {
      _lastSpan = span;
    }
  }

  @override
  void handleTapUp(PointerUpEvent event) {
    if (_lastSpan == null) return; // No span was hit on tap down.
    final span = _getSpanForOffset(_toContent(event.localPosition));
    if (span != null && _lastSpan == span) {
      // If the span is the same as the one hit on tap down,
      // call the tap recognizer.
      if (markdownSpanRecognizer(span) case TapGestureRecognizer(:final onTap))
        onTap?.call();
    }
    _lastSpan = null; // Clear the span after handling the tap.
  }

  InlineSpan? _getSpanForOffset(Offset position) {
    double currentY = 0.0;

    for (int r = 0; r < _cellPainters.length; r++) {
      final rowHeight = _rowHeights[r];

      if (position.dy >= currentY && position.dy < currentY + rowHeight) {
        // In this row.
        for (int c = 0; c < _cellPainters[r].length; c++) {
          final painter = _cellPainters[r][c];
          final columnLeft = _columnLefts[c];
          if (painter.text == null ||
              position.dx < columnLeft ||
              position.dx >= columnLeft + _columnWidths[c]) continue;

          // In this cell.
          final verticalPadding = (rowHeight - painter.height) / 2;
          final horizontalPadding = _cellHorizontalPadding(r, c, painter.width);

          final painterOffset = Offset(
            columnLeft + horizontalPadding,
            currentY + verticalPadding,
          );
          final localPosition = position - painterOffset;

          // Check if inside the actual painted text area.
          if (localPosition.dx < 0 ||
              localPosition.dx > painter.width ||
              localPosition.dy < 0 ||
              localPosition.dy > painter.height) continue;

          return markdownSpanAtLocal(painter, localPosition);
        }
      }
      currentY += rowHeight;
    }
    return null;
  }

  @override
  Size layout(double width) {
    if (columns < 1) return _size = Size.zero;

    // Pictures can change size between two layouts at one width.
    if (width == _laidOutWidth) return _size;
    final fixedContent = theme.imageResolver == null;
    _laidOutWidth = fixedContent ? width : null;

    final allRows = [header, ...rows];
    final headerStyle = theme.textStyle.copyWith(fontWeight: FontWeight.bold);

    // The painters are built once: the text of a cell is the same at any width.
    if (_cellPainters.isEmpty) {
      _cellPainters = List.generate(allRows.length, (r) {
        final row = allRows[r];
        return List.generate(columns, (c) {
          if (c >= row.cells.length) {
            return TextPainter(textDirection: theme.textDirection);
          }
          return TextPainter(
            text: paragraphFromMarkdownSpans(
              spans: row.cells[c],
              theme: theme,
              textStyle: r == 0 ? headerStyle : null,
              embeds: inlineEmbeds,
              revealed: spoilersRevealed,
            ),
            textAlign: switch (_columnAlign(c)) {
              MD$TableColumnAlign.left => TextAlign.left,
              MD$TableColumnAlign.center => TextAlign.center,
              MD$TableColumnAlign.right => TextAlign.right,
              MD$TableColumnAlign.none =>
                (r == 0) ? TextAlign.center : TextAlign.start,
            },
            textDirection: theme.textDirection,
            textScaler: theme.textScaler,
          );
        });
      });
    }

    final naturalWidths = _naturalWidths ?? _measureNaturalWidths(width);
    if (fixedContent) _naturalWidths = naturalWidths;

    // A table that fits keeps its natural widths, so the minimum widths, which
    // cost a paragraph per cell, are only measured for one that does not.
    if (naturalWidths.reduce((a, b) => a + b) <= width) {
      _columnWidths.setAll(0, naturalWidths);
    } else {
      final minWidths = _minimumWidths ?? _minWidths(headerStyle);
      if (fixedContent) _minimumWidths = minWidths;
      _columnWidths.setAll(
        0,
        _distributeWidths(naturalWidths, minWidths, width),
      );
    }

    final totalWidth = _columnWidths.reduce((a, b) => a + b);

    // Column positions: left to right, or mirrored for right-to-left text so
    // the first column sits on the right and the table hugs the right edge.
    _rtl = theme.textDirection == TextDirection.rtl && width.isFinite;
    // A pannable table that overflows keeps its content space from 0: the pan
    // puts the leading edge in view, in either direction.
    final pan = _pan;
    pan?.updateExtents(contentWidth: totalWidth, viewportWidth: width);
    final panning = pan?.canPan ?? false;
    // A table too wide to fit overflows past the end edge, so its first
    // columns stay in view: to the right for LTR, to the left (negative x)
    // for RTL.
    _tableLeft = _rtl && !panning ? width - totalWidth : 0.0;
    final lefts = List<double>.filled(columns, 0.0);
    var columnStart = 0.0;
    for (var c = 0; c < columns; c++) {
      lefts[c] = _rtl
          ? _tableLeft + totalWidth - columnStart - _columnWidths[c]
          : columnStart;
      columnStart += _columnWidths[c];
    }
    _columnLefts = lefts;

    // Layout painters with final widths and calculate row heights

    double totalHeight = 0.0;
    for (int r = 0; r < allRows.length; r++) {
      double rowHeight = 0.0;
      for (int c = 0; c < columns; c++) {
        final painter = _cellPainters[r][c];
        if (painter.text == null) continue;
        layoutMarkdownText(
          painter,
          maxWidth: math.max(0.0, _columnWidths[c] - padding * 2),
        );
        rowHeight = math.max(
          rowHeight,
          painter.height,
        );
      }

      _rowHeights[r] = rowHeight + padding * 2;
      totalHeight += _rowHeights[r];
    }

    // Cache border points
    final points = Float32List(((allRows.length - 1) + (columns - 1)) * 4);
    var pointIndex = 0;
    // Horizontal lines
    double lineY = 0;
    for (int r = 0; r < allRows.length - 1; r++) {
      lineY += _rowHeights[r];
      points[pointIndex++] = _tableLeft;
      points[pointIndex++] = lineY;
      points[pointIndex++] = _tableLeft + totalWidth;
      points[pointIndex++] = lineY;
    }
    // Vertical lines, between column c and the next one in reading order.
    for (int c = 0; c < columns - 1; c++) {
      final lineX = _rtl ? lefts[c] : lefts[c] + _columnWidths[c];
      points[pointIndex++] = lineX;
      points[pointIndex++] = 0;
      points[pointIndex++] = lineX;
      points[pointIndex++] = totalHeight;
    }
    _borderPoints = points;

    _fragments = null;
    _renderedText = null;

    // Scrollable variant: clip to [width] and pan when column minima overflow.
    if (panning) return _size = Size(width, totalHeight);
    return _size = Size(totalWidth, totalHeight);
  }

  /// Lays out each cell once and returns the width each column would take
  /// without wrapping, padding included.
  List<double> _measureNaturalWidths(double width) {
    final natural = List<double>.filled(columns, 0.0);
    // The natural width of a paragraph does not depend on the width it is laid
    // out at, but a finite one spares centered text a second pass, and a cell
    // that fits its column keeps this layout. A picture does scale with it.
    final measureWidth = theme.imageResolver == null && width.isFinite
        ? math.max(0.0, width)
        : double.infinity;
    for (final row in _cellPainters) {
      for (var c = 0; c < columns; c++) {
        final painter = row[c];
        if (painter.text == null) continue;
        layoutMarkdownText(painter, maxWidth: measureWidth);
        natural[c] = math.max(
          natural[c],
          painter.maxIntrinsicWidth + padding * 2,
        );
      }
    }
    return natural;
  }

  /// The width of each column's longest word plus padding, which the column
  /// can not usefully shrink below.
  List<double> _minWidths(TextStyle headerStyle) {
    final minWidths = List<double>.filled(columns, 0.0);
    for (var r = 0; r < _cellPainters.length; r++) {
      final style = r == 0 ? headerStyle : null;
      for (var c = 0; c < columns; c++) {
        // A row may hold fewer cells than the table has columns.
        if (_cellPainters[r][c].text == null) continue;
        // Pictures scale down to the column, so their alt text (U+FFFC in the
        // painter) does not count.
        final cellText =
            _cellPainters[r][c].plainText.replaceAll('\uFFFC', ' ');
        final longestWord = cellText
            .split(_whitespace)
            .reduce((a, b) => a.length > b.length ? a : b);
        final wordPainter = TextPainter(
          text: TextSpan(text: longestWord, style: style),
          textDirection: theme.textDirection,
        )..layout();
        minWidths[c] = math.max(minWidths[c], wordPainter.width + padding * 2);
        wordPainter.dispose();
      }
    }
    return minWidths;
  }

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Rebuilds the selectable fragments (row-major: cells joined by `\t`, rows by
  /// `\n`) so they line up with `markdownBlockRenderedText`. Only the cells that
  /// exist in the source row contribute text, matching the painted cells.
  void _rebuildFragments() {
    final allRows = [header, ...rows];
    final frags = <SelectableFragment>[];
    final text = StringBuffer();
    var rowTop = 0.0;
    for (var r = 0; r < allRows.length; r++) {
      if (r > 0) text.write('\n');
      final cells = allRows[r].cells;
      for (var c = 0; c < columns; c++) {
        if (c < cells.length) {
          if (c > 0) text.write('\t');
          final painter = _cellPainters[r][c];
          final verticalPadding = (_rowHeights[r] - painter.height) / 2;
          final horizontalPadding = _cellHorizontalPadding(r, c, painter.width);
          final origin = Offset(
            _columnLefts[c] + horizontalPadding,
            rowTop + verticalPadding,
          );
          frags.add(SelectableFragment(painter, origin, text.length));
          text.write(markdownModelText(painter));
        }
      }
      rowTop += _rowHeights[r];
    }
    _fragments = frags;
    _renderedText = text.toString();
  }

  @override
  bool pushPanTransform(Canvas canvas, double offset) {
    final pan = _pan;
    if (pan == null || !pan.canPan) return false;
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, offset, _size.width, _size.height))
      ..translate(pan.paintTranslationX(theme.textDirection), 0);
    return true;
  }

  @override
  void paint(Canvas canvas, Size size, double offset) {
    // If the width is less than required do not paint anything.
    if (columns < 1) return;

    final pan = _pan;
    final panning = pushPanTransform(canvas, offset);

    final paintWidth = panning ? pan!.contentWidth : _size.width;
    double currentY = offset;

    for (int r = 0; r < _cellPainters.length; r++) {
      final rowHeight = _rowHeights[r];

      // Draw background for even data rows.
      if (r % 2 == 0 && r != 0) {
        canvas.drawRect(
          Rect.fromLTWH(_tableLeft, currentY, paintWidth, rowHeight),
          _rowBackgroundPaint,
        );
      }

      for (int c = 0; c < columns; c++) {
        final painter = _cellPainters[r][c];
        if (painter.text == null) continue;

        final verticalPadding = (rowHeight - painter.height) / 2;
        final horizontalPadding = _cellHorizontalPadding(r, c, painter.width);

        paintMarkdownText(
          painter,
          canvas,
          Offset(
            _columnLefts[c] + horizontalPadding,
            currentY + verticalPadding,
          ),
        );
      }
      currentY += rowHeight;
    }

    // Draw inner borders
    if (_borderPoints != null) {
      canvas.save();
      canvas.translate(0, offset);
      canvas.drawRawPoints(PointMode.lines, _borderPoints!, _borderPaint);
      canvas.restore();
    }

    // Draw outer borders
    canvas.drawRect(
      Rect.fromLTWH(
        _tableLeft,
        offset,
        paintWidth,
        _size.height,
      ),
      _borderPaint,
    );

    if (panning) canvas.restore();
  }

  @override
  void dispose() {
    // The embeds their paragraphs reserved room for go with the painters.
    for (final row in _cellPainters) {
      for (final painter in row) {
        inlineEmbeds?.releaseIn(painter.text);
        painter.dispose();
      }
    }
    _cellPainters = const [];
    _laidOutWidth = null;
    _fragments = const <SelectableFragment>[];
    _renderedText = '';
  }

  /// Helper function to distribute widths among columns, respecting minimums.
  /// If total minimum width exceeds availableWidth,
  /// it returns the minimum widths as-is,
  /// implying that the content will overflow and require scrolling.
  List<double> _distributeWidths(
      List<double> natural, List<double> min, double availableWidth) {
    final totalNatural = natural.reduce((a, b) => a + b);
    final totalMin = min.reduce((a, b) => a + b);

    if (totalNatural <= availableWidth) {
      return natural;
    }

    if (totalMin <= availableWidth) {
      final remainingSpace = availableWidth - totalMin;
      final extraSpacePerColumn = [
        for (var i = 0; i < natural.length; i++) natural[i] - min[i]
      ];
      final totalExtraSpace = extraSpacePerColumn.reduce((a, b) => a + b);

      if (totalExtraSpace <= 0.001) return min;

      return [
        for (var i = 0; i < natural.length; i++)
          min[i] + remainingSpace * (extraSpacePerColumn[i] / totalExtraSpace)
      ];
    }
    return min;
  }
}

/// Table that clips to the layout width and pans when columns overflow.
///
/// Return this from [MarkdownThemeData.builder]. [BlockPainter$Table] still
/// overflows the old way.
///
/// Implements [HorizontallyPannableBlock]. Touch drag and pointer scroll are
/// wired by the render object; mouse and stylus keep selection gestures.
///
/// Set [enabled] to `false` to keep the clip without taking the gesture. Useful
/// as a per-block gate. [restoreScrollOffset] still applies when disabled so
/// layout does not write `0` into the pan store and wipe a sibling message's
/// offset in a chat list.
///
/// `0` pan is the leading edge for [MarkdownThemeData.textDirection] (right
/// side in RTL, like a horizontal [Scrollable]).
final class BlockPainter$ScrollableTable extends BlockPainter$Table
    implements HorizontallyPannableBlock {
  /// Creates a horizontally pannable table painter.
  ///
  /// With [enabled] false, [canPanHorizontally] stays false and
  /// [applyScrollDelta] is a no-op. Clip layout and [restoreScrollOffset] still
  /// run.
  BlockPainter$ScrollableTable({
    required super.header,
    required super.rows,
    required super.theme,
    super.alignments,
    super.inlineEmbeds,
    this.enabled = true,
  }) : super._pannable();

  /// When false, refuse new pan; clipped layout and restore stay on.
  final bool enabled;

  @override
  bool get canPanHorizontally => enabled && _canPanHorizontally;

  @override
  double get scrollOffset => _scrollOffset;

  @override
  double get maxScrollExtent => _maxScroll;

  @override
  bool applyScrollDelta(double deltaDx) {
    if (!enabled) return false;
    return _applyScrollDelta(deltaDx);
  }

  @override
  void restoreScrollOffset(double offset) {
    // Always apply. Layout restores then syncs the store. Zeroing while
    // disabled would push 0 into the controller and clear a live pan on
    // another body that shares the store.
    _restoreScrollOffset(offset);
  }
}
