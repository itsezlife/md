import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const wideTable = '''
| Path |
| --- |
| packages/flutter/lib/src/material/scrollbar_theme.dart |
| packages/flutter/lib/src/material/animated_icons/animated_icons.dart |
''';

  MarkdownThemeData scrollableTheme() => MarkdownThemeData(
        textStyle: const TextStyle(fontSize: 14),
        builder: (block, theme) {
          if (block case MD$Table(
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

  testWidgets(
    'BlockPainter\$ScrollableTable clips wide table to maxWidth and pans',
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
      expect(markdown, findsOneWidget);
      expect(tester.getSize(markdown).width, lessThanOrEqualTo(180));

      final center = tester.getCenter(markdown);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(120, 0)),
      );
      await tester.pump();
      expect(tester.getSize(markdown).width, lessThanOrEqualTo(180));
    },
  );

  test('default BlockPainter\$Table reports content wider than viewport', () {
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
    expect(painter.canPanHorizontally, isFalse);
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
    expect(painter.applyScrollDelta(40), isTrue);
    expect(painter.applyScrollDelta(40), isTrue);
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

  testWidgets('table pan survives surface dispose and remount', (tester) async {
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

    expect(controller.tableScrollOffset(documentId, 0), greaterThan(0));

    await tester.pumpWidget(mount(false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(mount(true));
    await tester.pumpAndSettle();

    expect(controller.tableScrollOffset(documentId, 0), greaterThan(0));
    controller.dispose();
  });
}
