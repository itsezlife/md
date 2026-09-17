//ignore_for_file: unnecessary_import

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../nodes.dart';
import '../../theme.dart';
import '../block_painter.dart';
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
    implements BlockPainter {
  /// Creates a table painter for the [header] row and data [rows], with
  /// per-column [alignments], styled by [theme].
  BlockPainter$Table({
    required MD$TableRow header,
    required List<MD$TableRow> rows,
    required MarkdownThemeData theme,
    List<MD$TableColumnAlign> alignments = const <MD$TableColumnAlign>[],
  }) : this._(
          header: header,
          rows: rows,
          theme: theme,
          alignments: alignments,
          pan: null,
        );

  /// Pannable layout — used by [BlockPainter$ScrollableTable].
  BlockPainter$Table._pannable({
    required MD$TableRow header,
    required List<MD$TableRow> rows,
    required MarkdownThemeData theme,
    List<MD$TableColumnAlign> alignments = const <MD$TableColumnAlign>[],
  }) : this._(
          header: header,
          rows: rows,
          theme: theme,
          alignments: alignments,
          pan: _TablePanState(),
        );

  BlockPainter$Table._({
    required this.header,
    required this.rows,
    required this.theme,
    required this.alignments,
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

  /// Non-null only for [BlockPainter$ScrollableTable]. Keeps pan geometry off
  /// the default overflowing table.
  final _TablePanState? _pan;

  /// Padding for table cells.
  static const double padding = 8.0;

  /// The theme for the markdown table.
  final MarkdownThemeData theme;

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
  /// column alignment (falling back to centered headers / left-aligned data).
  double _cellHorizontalPadding(int r, int c, double painterWidth) =>
      switch (_columnAlign(c)) {
        MD$TableColumnAlign.left => padding,
        MD$TableColumnAlign.center => (_columnWidths[c] - painterWidth) / 2,
        MD$TableColumnAlign.right => _columnWidths[c] - painterWidth - padding,
        MD$TableColumnAlign.none =>
          (r == 0) ? (_columnWidths[c] - painterWidth) / 2 : padding,
      };

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
  List<SelectableFragment> get fragments => _fragments;
  List<SelectableFragment> _fragments = const <SelectableFragment>[];

  @override
  String get renderedText => _renderedText;
  String _renderedText = '';

  /// Last span hit by the tap down event.
  TextSpan? _lastSpan;

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
  int offsetForLocalPosition(Offset local) =>
      super.offsetForLocalPosition(_toContent(local));

  @override
  List<Rect> boxesForRange(int start, int end) {
    final boxes = super.boxesForRange(start, end);
    final pan = _pan;
    if (pan == null) return boxes;
    return pan.toViewport(boxes, theme.textDirection);
  }

  @override
  TextRange wordBoundaryForLocal(Offset local) =>
      super.wordBoundaryForLocal(_toContent(local));

  @override
  bool isLinkAtLocal(Offset local) => super.isLinkAtLocal(_toContent(local));

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
      if (span case TextSpan(recognizer: TapGestureRecognizer(:var onTap)))
        onTap?.call();
    }
    _lastSpan = null; // Clear the span after handling the tap.
  }

  TextSpan? _getSpanForOffset(Offset position) {
    double currentY = 0.0;

    for (int r = 0; r < _cellPainters.length; r++) {
      final rowHeight = _rowHeights[r];
      double currentX = 0.0;

      if (position.dy >= currentY && position.dy < currentY + rowHeight) {
        // In this row.
        for (int c = 0; c < _cellPainters[r].length; c++) {
          final painter = _cellPainters[r][c];
          if (painter.text == null) {
            currentX += _columnWidths[c];
            continue;
          }
          final columnWidth = _columnWidths[c];

          if (position.dx >= currentX && position.dx < currentX + columnWidth) {
            // In this cell.
            final verticalPadding = (rowHeight - painter.height) / 2;
            final horizontalPadding =
                _cellHorizontalPadding(r, c, painter.width);

            final painterOffset = Offset(
                currentX + horizontalPadding, currentY + verticalPadding);
            final localPosition = position - painterOffset;

            // Check if inside the actual painted text area.
            if (localPosition.dx < 0 ||
                localPosition.dx > painter.width ||
                localPosition.dy < 0 ||
                localPosition.dy > painter.height) {
              currentX += columnWidth;
              continue;
            }

            final textPosition = painter.getPositionForOffset(localPosition);
            final span = painter.text!.getSpanForPosition(textPosition);
            if (span is TextSpan) {
              return span;
            }
            return null; // Found cell, but no span.
          }
          currentX += columnWidth;
        }
      }
      currentY += rowHeight;
    }
    return null;
  }

  @override
  Size layout(double width) {
    if (columns < 1) return _size = Size.zero;

    // Dispose old painters
    for (final row in _cellPainters) {
      for (final painter in row) {
        painter.dispose();
      }
    }

    final allRows = [header, ...rows];
    final naturalWidths = List<double>.filled(columns, 0.0);
    final minWidths = List<double>.filled(columns, 0.0);

    // Create painters for each row and column and calculate natural widths
    _cellPainters = List.generate(allRows.length, (r) {
      final row = allRows[r];
      return List.generate(columns, (c) {
        if (c >= row.cells.length) {
          return TextPainter(textDirection: theme.textDirection);
        }
        final cell = row.cells[c];
        final style = (r == 0)
            ? theme.textStyle.copyWith(fontWeight: FontWeight.bold)
            : null;
        final textPainter = TextPainter(
          text: paragraphFromMarkdownSpans(
              spans: cell, theme: theme, textStyle: style),
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

        // Calculate natural width
        textPainter.layout(maxWidth: double.infinity);
        naturalWidths[c] =
            math.max(naturalWidths[c], textPainter.width + padding * 2);

        // Calculate min width (longest word)
        final cellText = cell.map((s) => s.text).join();
        final words = cellText.split(RegExp(r'\s+'));
        if (words.isNotEmpty) {
          final longestWord =
              words.reduce((a, b) => a.length > b.length ? a : b);
          final wordPainter = TextPainter(
            text: TextSpan(text: longestWord, style: style),
            textDirection: theme.textDirection,
          )..layout();
          minWidths[c] =
              math.max(minWidths[c], wordPainter.width + padding * 2);
          wordPainter.dispose();
        }

        return textPainter;
      });
    });

    _columnWidths.setAll(0, _distributeWidths(naturalWidths, minWidths, width));

    final totalWidth = _columnWidths.reduce((a, b) => a + b);

    // Layout painters with final widths and calculate row heights

    double totalHeight = 0.0;
    for (int r = 0; r < allRows.length; r++) {
      double rowHeight = 0.0;
      for (int c = 0; c < columns; c++) {
        final painter = _cellPainters[r][c];
        if (painter.text == null) continue;
        painter.layout(maxWidth: math.max(0.0, _columnWidths[c] - padding * 2));
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
      points[pointIndex++] = 0;
      points[pointIndex++] = lineY;
      points[pointIndex++] = totalWidth;
      points[pointIndex++] = lineY;
    }
    // Vertical lines
    double lineX = 0;
    for (int c = 0; c < columns - 1; c++) {
      lineX += _columnWidths[c];
      points[pointIndex++] = lineX;
      points[pointIndex++] = 0;
      points[pointIndex++] = lineX;
      points[pointIndex++] = totalHeight;
    }
    _borderPoints = points;

    _rebuildFragments(allRows);

    final pan = _pan;
    if (pan != null) {
      // Scrollable variant: clip to [width] and pan when column minima
      // overflow.
      pan.updateExtents(contentWidth: totalWidth, viewportWidth: width);
      if (pan.canPan) {
        return _size = Size(width, totalHeight);
      }
    }
    return _size = Size(totalWidth, totalHeight);
  }

  /// Rebuilds the selectable fragments (row-major: cells joined by `\t`, rows by
  /// `\n`) so they line up with `markdownBlockRenderedText`. Only the cells that
  /// exist in the source row contribute text, matching the painted cells.
  void _rebuildFragments(List<MD$TableRow> allRows) {
    final frags = <SelectableFragment>[];
    final text = StringBuffer();
    var rowTop = 0.0;
    for (var r = 0; r < allRows.length; r++) {
      if (r > 0) text.write('\n');
      final cells = allRows[r].cells;
      var colLeft = 0.0;
      for (var c = 0; c < columns; c++) {
        if (c < cells.length) {
          if (c > 0) text.write('\t');
          final painter = _cellPainters[r][c];
          final verticalPadding = (_rowHeights[r] - painter.height) / 2;
          final horizontalPadding = _cellHorizontalPadding(r, c, painter.width);
          final origin =
              Offset(colLeft + horizontalPadding, rowTop + verticalPadding);
          frags.add(SelectableFragment(painter, origin, text.length));
          text.write(painter.plainText);
        }
        colLeft += _columnWidths[c];
      }
      rowTop += _rowHeights[r];
    }
    _fragments = frags;
    _renderedText = text.toString();
  }

  @override
  void paint(Canvas canvas, Size size, double offset) {
    // If the width is less than required do not paint anything.
    if (columns < 1) return;

    final pan = _pan;
    final panning = pan != null && pan.canPan;
    if (panning) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, offset, _size.width, _size.height));
      canvas.translate(pan.paintTranslationX(theme.textDirection), 0);
    }

    final paintWidth = panning ? pan.contentWidth : _size.width;
    double currentY = offset;

    for (int r = 0; r < _cellPainters.length; r++) {
      final rowHeight = _rowHeights[r];
      double currentX = 0;

      // Draw background for even data rows.
      if (r % 2 == 0 && r != 0) {
        canvas.drawRect(
          Rect.fromLTWH(0, currentY, paintWidth, rowHeight),
          _rowBackgroundPaint,
        );
      }

      for (int c = 0; c < columns; c++) {
        final painter = _cellPainters[r][c];
        if (painter.text == null) {
          currentX += _cellPainters[r].length > c ? _columnWidths[c] : 0;
          continue;
        }

        final verticalPadding = (rowHeight - painter.height) / 2;
        final horizontalPadding = _cellHorizontalPadding(r, c, painter.width);

        painter.paint(
          canvas,
          Offset(
            currentX + horizontalPadding,
            currentY + verticalPadding,
          ),
        );
        currentX += _columnWidths[c];
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
      Rect.fromLTRB(
        0,
        offset,
        paintWidth,
        offset + _size.height,
      ),
      _borderPaint,
    );

    if (panning) canvas.restore();
  }

  @override
  void dispose() {
    for (final row in _cellPainters) {
      for (final painter in row) {
        painter.dispose();
      }
    }
    _cellPainters = const [];
    _fragments = const <SelectableFragment>[];
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
