import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/markdown_render_object.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const wideTable = '''
| Path |
| --- |
| packages/flutter/lib/src/material/scrollbar_theme.dart |
| packages/flutter/lib/src/material/animated_icons/animated_icons.dart |
''';

  const otherWideTable = '''
| Name |
| --- |
| packages/flutter/lib/src/cupertino/nav_bar.dart |
| packages/flutter/lib/src/cupertino/button.dart |
''';

  MarkdownThemeData scrollableTheme() => MarkdownThemeData(
        textStyle: const TextStyle(fontSize: 14),
        builder: (block, theme) {
          if (block
              case MD$Table(
                :final header,
                :final rows,
                :final alignments,
              )) {
            return BlockPainter$ScrollableTable(
              header: header,
              rows: rows,
              alignments: alignments,
              theme: theme,
            );
          }
          return null;
        },
      );

  MarkdownRenderObject renderObject(WidgetTester tester) =>
      tester.renderObject(find.byType(MarkdownWidget)) as MarkdownRenderObject;

  List<HorizontallyPannableBlock> allPans(WidgetTester tester) {
    final painter = renderObject(tester).debugPainter;
    final out = <HorizontallyPannableBlock>[];
    for (var i = 0; i < 64; i++) {
      final p = painter.pannablePainterAt(i);
      if (p != null) out.add(p);
    }
    return out;
  }

  HorizontallyPannableBlock? livePan(WidgetTester tester) {
    final pans = allPans(tester);
    return pans.isEmpty ? null : pans.first;
  }

  BlockPainter$ScrollableTable liveTable(WidgetTester tester) =>
      livePan(tester)! as BlockPainter$ScrollableTable;

  testWidgets(
    'ScrollableTable clips wide table and pans content',
    (tester) async {
      final md = Markdown.fromString(wideTable);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: MarkdownWidget(
                  markdown: md,
                  theme: scrollableTheme(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markdown = find.byType(MarkdownWidget);
      expect(tester.getSize(markdown).width, lessThanOrEqualTo(180));

      final pan = liveTable(tester);
      expect(pan.canPanHorizontally, isTrue);
      expect(pan.scrollOffset, 0);

      final before = pan.offsetForLocalPosition(const Offset(20, 10));
      final center = tester.getCenter(markdown);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(120, 0),
        ),
      );
      await tester.pump();

      expect(tester.getSize(markdown).width, lessThanOrEqualTo(180));
      expect(pan.scrollOffset, greaterThan(0));
      final after = pan.offsetForLocalPosition(const Offset(20, 10));
      expect(after, isNot(before));
    },
  );

  test('default BlockPainter\$Table is not HorizontallyPannableBlock', () {
    final md = Markdown.fromString(wideTable);
    final table = md.blocks.whereType<MD$Table>().single;
    final painter = BlockPainter$Table(
      header: table.header,
      rows: table.rows,
      alignments: table.alignments,
      theme: MarkdownThemeData(textStyle: const TextStyle(fontSize: 14)),
    );
    final size = painter.layout(180);
    expect(size.width, greaterThan(180));
    expect(painter, isNot(isA<HorizontallyPannableBlock>()));
    painter.dispose();
  });

  test('BlockPainter\$ScrollableTable reports viewport width and can pan', () {
    final md = Markdown.fromString(wideTable);
    final table = md.blocks.whereType<MD$Table>().single;
    final painter = BlockPainter$ScrollableTable(
      header: table.header,
      rows: table.rows,
      alignments: table.alignments,
      theme: MarkdownThemeData(textStyle: const TextStyle(fontSize: 14)),
    );
    final size = painter.layout(180);
    expect(size.width, 180);
    expect(painter, isA<HorizontallyPannableBlock>());
    expect(painter.canPanHorizontally, isTrue);
    expect(painter.maxScrollExtent, greaterThan(0));
    expect(painter.applyScrollDelta(40), isTrue);
    expect(painter.scrollOffset, 40);
    expect(painter.applyScrollDelta(40), isTrue);
    expect(painter.scrollOffset, 80);
    painter.dispose();
  });

  test('restoreScrollOffset reapplies pan after a fresh layout', () {
    final md = Markdown.fromString(wideTable);
    final table = md.blocks.whereType<MD$Table>().single;
    final t = MarkdownThemeData(textStyle: const TextStyle(fontSize: 14));
    final first = BlockPainter$ScrollableTable(
      header: table.header,
      rows: table.rows,
      alignments: table.alignments,
      theme: t,
    )..layout(180);
    expect(first.applyScrollDelta(90), isTrue);
    final saved = first.scrollOffset;
    expect(saved, greaterThan(0));
    first.dispose();

    final second = BlockPainter$ScrollableTable(
      header: table.header,
      rows: table.rows,
      alignments: table.alignments,
      theme: t,
    )..layout(180);
    second.restoreScrollOffset(saved);
    expect(second.scrollOffset, saved);
    second.dispose();
  });

  testWidgets('pan survives remount on live painter and controller',
      (tester) async {
    final md = Markdown.fromString(wideTable);
    final controller = MarkdownSelectionController();
    const documentId = 42;

    Widget mount(bool show) => MaterialApp(
          home: Scaffold(
            body: show
                ? SizedBox(
                    width: 180,
                    child: MarkdownWidget(
                      markdown: md,
                      theme: scrollableTheme(),
                      controller: controller,
                      documentId: documentId,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        );

    await tester.pumpWidget(mount(true));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(MarkdownWidget));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(160, 0)),
    );
    await tester.pump();

    final saved = controller.horizontalPanOffset(documentId, 0);
    expect(saved, greaterThan(0));
    expect(livePan(tester)!.scrollOffset, saved);

    await tester.pumpWidget(mount(false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(mount(true));
    await tester.pumpAndSettle();

    expect(controller.horizontalPanOffset(documentId, 0), saved);
    expect(livePan(tester)!.scrollOffset, saved);
    controller.dispose();
  });

  testWidgets('pan does not invalidate document glyph Picture', (tester) async {
    final md = Markdown.fromString('''
Hello

$wideTable
''');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: MarkdownWidget(
              markdown: md,
              theme: scrollableTheme(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = renderObject(tester).debugPainter;
    final size = renderObject(tester).size;
    // Force a paint to populate the cache.
    renderObject(tester).markNeedsPaint();
    await tester.pump();
    expect(painter.hasCachedPictureFor(size), isTrue);

    final pan = livePan(tester)!;
    final before = pan.scrollOffset;
    final center = tester.getCenter(find.byType(MarkdownWidget));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(100, 0)),
    );
    await tester.pump();

    expect(pan.scrollOffset, greaterThan(before));
    expect(painter.hasCachedPictureFor(size), isTrue);
  });

  testWidgets('selection boxes for pannable block stay in viewport',
      (tester) async {
    final md = Markdown.fromString(wideTable);
    final controller = MarkdownSelectionController()..putDocument(1, md);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: MarkdownWidget(
              markdown: md,
              theme: scrollableTheme(),
              controller: controller,
              documentId: 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pan = liveTable(tester);
    final len = pan.renderedText.length;
    controller.selection = MarkdownSelection(
      base: const MarkdownPosition(documentId: 1, blockIndex: 0, offset: 0),
      extent: MarkdownPosition(documentId: 1, blockIndex: 0, offset: len),
    );
    expect(pan.applyScrollDelta(80), isTrue);
    await tester.pump();

    final boxes = renderObject(tester).localSelectionRects();
    final viewport = Rect.fromLTWH(0, 0, pan.size.width, pan.size.height);
    for (final box in boxes) {
      expect(viewport.overlaps(box) || viewport.contains(box.center), isTrue);
      expect(box.left, greaterThanOrEqualTo(-0.5));
      expect(box.right, lessThanOrEqualTo(pan.size.width + 0.5));
    }
    controller.dispose();
  });

  testWidgets('rebind to new documentId does not leak local pan',
      (tester) async {
    final md = Markdown.fromString(wideTable);
    final controller = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: MarkdownWidget(
              markdown: md,
              theme: scrollableTheme(),
              controller: controller,
              documentId: 'a',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(MarkdownWidget));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(120, 0)),
    );
    await tester.pump();
    final offsetA = controller.horizontalPanOffset('a', 0)!;
    expect(offsetA, greaterThan(0));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: MarkdownWidget(
              markdown: md,
              theme: scrollableTheme(),
              controller: controller,
              documentId: 'b',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Doc B must not inherit A's pan via stale local store.
    expect(controller.horizontalPanOffset('b', 0) ?? 0.0, 0.0);
    expect(livePan(tester)!.scrollOffset, 0.0);
    // Doc A entry remains until explicitly cleared.
    expect(controller.horizontalPanOffset('a', 0), offsetA);
    controller.dispose();
  });

  testWidgets('insert before table remaps pan by content', (tester) async {
    final tableOnly = Markdown.fromString(wideTable);
    final withIntro = Markdown.fromString('Intro\n\n$wideTable');
    final controller = MarkdownSelectionController()..putDocument(1, tableOnly);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: MarkdownWidget(
              markdown: tableOnly,
              theme: scrollableTheme(),
              controller: controller,
              documentId: 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(MarkdownWidget));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(140, 0)),
    );
    await tester.pump();
    final saved = livePan(tester)!.scrollOffset;
    expect(saved, greaterThan(0));

    controller.putDocument(1, withIntro);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: MarkdownWidget(
              markdown: withIntro,
              theme: scrollableTheme(),
              controller: controller,
              documentId: 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Table is now source index 2 (paragraph + spacer + table) or 1 —
    // content-anchored remapping should restore the pan on the table painter.
    expect(livePan(tester)!.scrollOffset, saved);
    expect(
      controller.horizontalPanOffset(1, 0) ?? 0.0,
      0.0,
    );
    final remapped = allPans(tester).single.scrollOffset;
    expect(remapped, saved);
    controller.dispose();
  });

  testWidgets('two scrollable tables keep independent pans', (tester) async {
    final md = Markdown.fromString('$wideTable\n\n$otherWideTable');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: MarkdownWidget(
              markdown: md,
              theme: scrollableTheme(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pans = allPans(tester);
    expect(pans.length, 2);
    expect(pans[0].applyScrollDelta(60), isTrue);
    expect(pans[1].applyScrollDelta(30), isTrue);
    expect(pans[0].scrollOffset, 60);
    expect(pans[1].scrollOffset, 30);

    // Swap order in the model — remapping should keep each table's pan.
    final swapped = Markdown.fromString('$otherWideTable\n\n$wideTable');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: MarkdownWidget(
              markdown: swapped,
              theme: scrollableTheme(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final after = allPans(tester);
    expect(after.length, 2);
    // First painter is now otherWideTable (had 30); second is wideTable (60).
    expect(after[0].scrollOffset, 30);
    expect(after[1].scrollOffset, 60);
  });

  testWidgets('touch drag fling continues offset after pointer up',
      (tester) async {
    final md = Markdown.fromString(wideTable);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: MarkdownWidget(
              markdown: md,
              theme: scrollableTheme(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pan = livePan(tester)!;
    final box = tester.getRect(find.byType(MarkdownWidget));
    final start = Offset(box.center.dx + 40, box.center.dy);
    final end = Offset(box.center.dx - 80, box.center.dy);

    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(end);
    await tester.pump(const Duration(milliseconds: 16));
    final afterDrag = pan.scrollOffset;
    expect(afterDrag, greaterThan(0));
    await gesture.up();
    // Allow ballistic ticks.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));
    // Fling may or may not advance further depending on velocity; offset must
    // remain valid and not regress to zero from a cancelled orphan.
    expect(pan.scrollOffset, greaterThanOrEqualTo(afterDrag - 0.5));
    expect(pan.scrollOffset, lessThanOrEqualTo(pan.maxScrollExtent));
  });

  test('controller remaps pan offsets on putDocument', () {
    final a = Markdown.fromString(wideTable);
    final b = Markdown.fromString('Intro\n\n$wideTable');
    final controller = MarkdownSelectionController()
      ..putDocument(1, a)
      ..setHorizontalPanOffset(1, 0, 55);
    expect(controller.horizontalPanOffset(1, 0), 55);

    controller.putDocument(1, b);
    expect(controller.horizontalPanOffset(1, 0), isNull);
    // Find which index holds the remapped offset.
    var found = false;
    for (var i = 0; i < b.blocks.length; i++) {
      if (controller.horizontalPanOffset(1, i) == 55) {
        found = true;
        break;
      }
    }
    expect(found, isTrue);
    controller.dispose();
  });
}
