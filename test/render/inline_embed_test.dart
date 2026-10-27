import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/block_painter.dart' show inlineSpanAt;
import 'package:flutter_md/src/render/embed_offset_map.dart';
import 'package:flutter_md/src/render/inline_embeds.dart';
import 'package:flutter_md/src/render/markdown_painter.dart';
import 'package:flutter_md/src/render/markdown_render_object.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_inline_embed_resolver.dart';

/// Tests run in Ahem: the font is `fontSize` tall, three quarters of it above
/// the baseline and a quarter below, and every glyph is a `fontSize` square.
const double _fontSize = 13;

MarkdownThemeData _theme([double fontSize = _fontSize]) => MarkdownThemeData(
      textStyle: TextStyle(fontSize: fontSize),
    );

MD$Paragraph _paragraphOf(String source) =>
    Markdown.fromString(source).blocks.first as MD$Paragraph;

/// A paragraph of [source] laid out at [width], its embeds resolved by
/// [resolver] (none when null).
BlockPainter$Paragraph _paragraph(
  String source, {
  FakeInlineEmbedResolver? resolver,
  double devicePixelRatio = 1,
  double width = 400,
  double fontSize = _fontSize,
}) {
  final host = resolver == null
      ? null
      : MarkdownEmbedHost(
          resolver: resolver,
          devicePixelRatio: devicePixelRatio,
        );
  final painter = BlockPainter$Paragraph(
    spans: _paragraphOf(source).spans,
    theme: _theme(fontSize),
    inlineEmbeds: host,
  )..layout(width);
  addTearDown(painter.dispose);
  return painter;
}

/// The room the paragraph reserved for the [index]th embed.
Rect _layoutBox(BlockPainter$Paragraph block, int index) {
  final entry = MarkdownEmbedOffsets.of(block.painter).entries[index];
  return block.painter.inlinePlaceholderBoxes![entry.placeholderIndex].toRect();
}

/// The square the [index]th embed is drawn into.
Rect _paintRect(BlockPainter$Paragraph block, int index) {
  final entry = MarkdownEmbedOffsets.of(block.painter).entries[index];
  return entry.span!.paintRectFor(_layoutBox(block, index));
}

/// Hosts a [MarkdownRenderObject] with an embed resolver, which the public
/// [MarkdownWidget] does not take yet.
class _EmbedBody extends LeafRenderObjectWidget {
  const _EmbedBody({
    required this.markdown,
    required this.resolver,
    this.controller,
    this.documentId,
    this.devicePixelRatio = 1,
  });

  final Markdown markdown;
  final MarkdownInlineEmbedResolver? resolver;
  final MarkdownSelectionController? controller;
  final Object? documentId;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => MarkdownRenderObject(
        markdown: markdown,
        theme: _theme(),
        embedResolver: resolver,
        devicePixelRatio: devicePixelRatio,
      )..updateSelection(controller, documentId, markdown: markdown);

  @override
  void updateRenderObject(
    BuildContext context,
    MarkdownRenderObject renderObject,
  ) {
    renderObject
      ..updateSelection(controller, documentId, markdown: markdown)
      ..update(
        markdown: markdown,
        theme: _theme(),
        embedResolver: resolver,
        devicePixelRatio: devicePixelRatio,
      );
  }
}

Widget _app(Widget body, {double width = 400}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: body),
      ),
    );

void main() {
  group('inline embed: size', () {
    test('the font of the probe is the one the tests expect', () {
      final resolver = FakeInlineEmbedResolver();
      _paragraph('a ![x](emoji:1) b', resolver: resolver);
      final metrics = resolver.metricsSeen.single;
      expect(metrics.fontSize, _fontSize);
      expect(metrics.ascent, closeTo(9.75, 1e-6));
      expect(metrics.descent, closeTo(3.25, 1e-6));
    });

    // 1.2 x 13 = 15.6 logical pixels, rounded to whole device pixels.
    for (final (dpr, side) in <(double, double)>[
      (1, 16),
      (2, 15.5),
      (3, 47 / 3),
    ]) {
      test('the box is 1.2 x (ascent + descent) at device pixel ratio $dpr',
          () {
        final resolver = FakeInlineEmbedResolver();
        final block = _paragraph(
          'a ![x](emoji:1) b',
          resolver: resolver,
          devicePixelRatio: dpr,
        );
        expect(_paintRect(block, 0).width, closeTo(side, 1e-5));
        expect(_paintRect(block, 0).height, closeTo(side, 1e-5));
        expect(_layoutBox(block, 0).width, closeTo(side, 1e-5));
        expect(resolver.resolved.single.size, Size(side, side));
      });
    }

    test('two embeds in one paragraph share one size and one metrics', () {
      final resolver = FakeInlineEmbedResolver();
      final block = _paragraph(
        'a ![x](emoji:1) b ![y](emoji:2) c',
        resolver: resolver,
      );
      expect(_paintRect(block, 0).size, _paintRect(block, 1).size);
      expect(resolver.metricsSeen, hasLength(2));
      expect(resolver.metricsSeen[0], resolver.metricsSeen[1]);
    });

    test('the font is probed without the line height', () {
      final resolver = FakeInlineEmbedResolver();
      final spans = _paragraphOf('a ![x](emoji:1) b').spans;
      final host = MarkdownEmbedHost(resolver: resolver, devicePixelRatio: 1);
      final tall = BlockPainter$Paragraph(
        spans: spans,
        theme: MarkdownThemeData(
          textStyle: const TextStyle(fontSize: _fontSize, height: 3),
        ),
        inlineEmbeds: host,
      )..layout(400);
      addTearDown(tall.dispose);
      final metrics = resolver.metricsSeen.single;
      expect(metrics.ascent + metrics.descent, closeTo(_fontSize, 1e-6));
    });

    test('the paragraph is exactly as tall with an embed as without', () {
      final plain = _paragraph('a x b');
      final embedded = _paragraph(
        'a ![x](emoji:1) b',
        resolver: FakeInlineEmbedResolver(),
      );
      expect(embedded.painter.computeLineMetrics(), hasLength(1));
      expect(
        embedded.painter.computeLineMetrics().single.height,
        plain.painter.computeLineMetrics().single.height,
      );
      expect(embedded.size.height, plain.size.height);
    });

    test('a taller line is as tall with the embed as without it', () {
      // `height: 2` stretches the line; the embed does not stretch it further.
      MarkdownThemeData tall() => MarkdownThemeData(
            textStyle: const TextStyle(fontSize: _fontSize, height: 2),
          );
      final withEmbed = BlockPainter$Paragraph(
        spans: _paragraphOf('a ![x](emoji:1) b').spans,
        theme: tall(),
        inlineEmbeds: MarkdownEmbedHost(
          resolver: FakeInlineEmbedResolver(),
          devicePixelRatio: 1,
        ),
      )..layout(400);
      final without = BlockPainter$Paragraph(
        spans: _paragraphOf('a x b').spans,
        theme: tall(),
      )..layout(400);
      addTearDown(withEmbed.dispose);
      addTearDown(without.dispose);
      expect(withEmbed.size.height, without.size.height);
    });

    test('the embed is centred on its line', () {
      final block = _paragraph(
        'a ![x](emoji:1) b',
        resolver: FakeInlineEmbedResolver(),
      );
      final line = block.painter.computeLineMetrics().single;
      final rect = _paintRect(block, 0);
      // The line spans [0, line.height] here; the embed overflows it evenly.
      expect(rect.center.dy, closeTo(line.height / 2, 1.0));
      expect(rect.top, lessThan(0));
      expect(rect.bottom, greaterThan(line.height));
    });

    test('the embed takes its width from the left of what follows it', () {
      final plain = _paragraph('a x b');
      final embedded = _paragraph(
        'a ![x](emoji:1) b',
        resolver: FakeInlineEmbedResolver(),
      );
      // "a " is two Ahem squares; then the 16-wide embed instead of one glyph.
      expect(_layoutBox(embedded, 0).left, 2 * _fontSize);
      expect(embedded.size.width, plain.size.width - _fontSize + 16);
    });
  });

  group('inline embed: rendered text and selection', () {
    const source = 'a ![xyz](emoji:1) b';

    BlockPainter$Paragraph embedded() =>
        _paragraph(source, resolver: FakeInlineEmbedResolver());

    test('the rendered text is the alt text, as the model says', () {
      final block = embedded();
      expect(block.renderedText, 'a xyz b');
      expect(
        block.renderedText,
        markdownBlockRenderedText(_paragraphOf(source)),
      );
      expect(block.painter.plainText, 'a ￼ b');
    });

    test('a position on the embed lands inside its alt, in either half', () {
      final block = embedded();
      final box = _layoutBox(block, 0);
      // The selection normalises the boundary; the block only has to say the
      // pointer is over the embed, so the embed is in a drag either way.
      for (final point in <Offset>[
        box.centerLeft + const Offset(2, 0),
        box.centerRight - const Offset(2, 0),
        // The square pokes out above the room the paragraph reserved.
        Offset(box.center.dx + 3, _paintRect(block, 0).top + 0.2),
      ]) {
        final (offset, _) = block.positionAndAffinityForLocal(point);
        expect(offset, greaterThan(2), reason: '$point');
        expect(offset, lessThan(5), reason: '$point');
      }
    });

    test('an alt of one code unit has no inside: the nearer edge', () {
      final block = _paragraph(
        'a ![x](emoji:1) b',
        resolver: FakeInlineEmbedResolver(),
      );
      final box = _layoutBox(block, 0);
      expect(
        block.positionAndAffinityForLocal(box.centerLeft + const Offset(2, 0)),
        (2, TextAffinity.downstream),
      );
      expect(
        block
            .positionAndAffinityForLocal(box.centerRight - const Offset(2, 0))
            .$1,
        3,
      );
      expect(block.atomicRanges, isEmpty);
    });

    test('the atomic ranges are the alt texts', () {
      final block = _paragraph(
        'a ![xy](emoji:1) b ![zzz](emoji:2)',
        resolver: FakeInlineEmbedResolver(),
      );
      expect(block.atomicRanges, const <TextRange>[
        TextRange(start: 2, end: 4),
        TextRange(start: 7, end: 10),
      ]);
    });

    test('positions around the embed map through the alt', () {
      final block = embedded();
      // Past the end of the text: the end of the rendered text.
      expect(
        block.positionAndAffinityForLocal(const Offset(399, 6)).$1,
        block.renderedText.length,
      );
      expect(block.positionAndAffinityForLocal(const Offset(1, 6)).$1, 0);
    });

    test('a range with a boundary inside the alt selects the whole embed', () {
      final block = embedded();
      final whole = block.boxesForRange(2, 5);
      expect(whole, hasLength(1));
      expect(whole.single, _layoutBox(block, 0));
      expect(block.boxesForRange(3, 4), whole);
      expect(block.boxesForRange(2, 4), whole);
      expect(block.boxesForRange(3, 5), whole);
      // A range that ends inside the alt takes the embed along with the text.
      expect(block.boxesForRange(0, 4), block.boxesForRange(0, 5));
      expect(block.boxesForRange(4, 7), block.boxesForRange(2, 7));
      // A range that only touches the embed does not.
      expect(block.boxesForRange(0, 2).single.right, _layoutBox(block, 0).left);
    });

    test('the caret sits at the edges of the alt, never inside it', () {
      final block = embedded();
      final box = _layoutBox(block, 0);
      expect(block.caretRectFor(2, TextAffinity.downstream).left, box.left);
      expect(block.caretRectFor(5, TextAffinity.downstream).left, box.right);
      expect(block.caretRectFor(3, TextAffinity.downstream).left, box.left);
      expect(
        block
            .caretRectFor(block.renderedText.length, TextAffinity.upstream)
            .left,
        block.painter.width,
      );
    });

    test('a word select on the embed takes the whole alt', () {
      final block = embedded();
      final box = _layoutBox(block, 0);
      expect(
        block.wordBoundaryForLocal(box.center),
        const TextRange(start: 2, end: 5),
      );
      // Beside it, words are the words of the painter in rendered offsets.
      expect(block.wordBoundaryForLocal(const Offset(1, 6)).start, 0);
    });

    test('hit-testing the embed box returns the embed span', () {
      final block = embedded();
      final box = _layoutBox(block, 0);
      for (final point in <Offset>[
        box.center,
        box.centerLeft + const Offset(1, 0),
        box.centerRight - const Offset(1, 0),
        Offset(box.center.dx, _paintRect(block, 0).top + 0.2),
      ]) {
        final span = inlineSpanAt(block.painter, point);
        expect(span, isA<MarkdownEmbedSpan>(), reason: '$point');
        expect((span! as MarkdownEmbedSpan).target.alt, 'xyz');
      }
      expect(inlineSpanAt(block.painter, const Offset(1, 6)), isA<TextSpan>());
    });

    test('the cached glyph boxes still see the embed as ink', () {
      final block = embedded();
      expect(block.hitsRenderedTextAt(_layoutBox(block, 0).center), isTrue);
    });
  });

  group('inline embed: alt text is atomic through the controller', () {
    // "a " is 26px of Ahem; the 16px embed spans x 26..42, its near half
    // 26..34 and its far half 34..42; " b" follows.
    const source = 'a ![xyz](emoji:1) b';

    Future<MarkdownSelectionController> pump(
      WidgetTester tester, {
      String text = source,
    }) async {
      final resolver = FakeInlineEmbedResolver();
      final controller = MarkdownSelectionController(
        formatter: MarkdownSelectionFormatter.plain,
      )..setDocuments(<MarkdownDocumentRef>[
          MarkdownDocumentRef(id: 'd', model: Markdown.fromString(text)),
        ]);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownSelectionScope(
              controller: controller,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  child: _EmbedBody(
                    markdown: Markdown.fromString(text),
                    resolver: resolver,
                    controller: controller,
                    documentId: 'd',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    Future<void> drag(WidgetTester tester, double from, double to) async {
      final top = tester.getTopLeft(find.byType(_EmbedBody));
      final g = await tester.startGesture(
        top + Offset(from, 6),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveTo(top + Offset(to, 6));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await tester.pumpAndSettle();
    }

    MarkdownSelection range(int base, int extent) => MarkdownSelection(
          base: MarkdownPosition(documentId: 'd', blockIndex: 0, offset: base),
          extent:
              MarkdownPosition(documentId: 'd', blockIndex: 0, offset: extent),
        );

    testWidgets('copy of the whole body yields the alt text', (tester) async {
      final controller = await pump(tester);
      controller.selectAll();
      expect(controller.getText(), 'a xyz b');
    });

    for (final (name, to) in <(String, double)>[
      ('near half', 30),
      ('far half', 40),
    ]) {
      testWidgets(
          'a drag ending in the $name of the embed copies the whole '
          'alt', (tester) async {
        final controller = await pump(tester);
        await drag(tester, 1, to);
        expect(controller.getText(), 'a xyz');
        expect(controller.rangeFor('d', 0), const TextRange(start: 0, end: 5));
      });

      testWidgets(
          'a drag from the right ending in the $name of the embed '
          'copies the whole alt', (tester) async {
        final controller = await pump(tester);
        await drag(tester, 80, to);
        expect(controller.getText(), 'xyz b');
        expect(controller.rangeFor('d', 0), const TextRange(start: 2, end: 7));
      });

      testWidgets(
          'a drag starting in the $name of the embed copies the whole '
          'alt, to the right and to the left', (tester) async {
        final controller = await pump(tester);
        await drag(tester, to, 80);
        expect(controller.getText(), 'xyz b');
        await drag(tester, to, 1);
        expect(controller.getText(), 'a xyz');
      });
    }

    testWidgets('a drag that ends before the embed leaves it out',
        (tester) async {
      final controller = await pump(tester);
      await drag(tester, 1, 10);
      expect(controller.getText(), 'a');
      await drag(tester, 80, 50);
      expect(controller.getText(), 'b');
    });

    testWidgets('adjacent embeds are each whole', (tester) async {
      // Embeds at x 26..42 ("xy") and 42..58 ("zw"), then " b".
      final controller =
          await pump(tester, text: 'a ![xy](emoji:1)![zw](emoji:2) b');
      await drag(tester, 1, 30);
      expect(controller.getText(), 'a xy');
      await drag(tester, 1, 50);
      expect(controller.getText(), 'a xyzw');
      await drag(tester, 34, 50);
      expect(controller.getText(), 'xyzw');
      await drag(tester, 50, 34);
      expect(controller.getText(), 'xyzw');
      await drag(tester, 50, 80);
      expect(controller.getText(), 'zw b');
    });

    testWidgets('a range set from outside never copies a partial alt',
        (tester) async {
      final controller = await pump(tester);
      // 'a xyz b': the alt is 2..5.
      controller.selection = range(3, 7);
      expect(controller.getText(), 'xyz b');
      controller.selection = range(7, 3);
      expect(controller.getText(), 'xyz b');
      controller.selection = range(0, 4);
      expect(controller.getText(), 'a xyz');
      controller.selection = range(4, 0);
      expect(controller.getText(), 'a xyz');
      controller.selection = range(3, 4);
      expect(controller.getText(), 'xyz');
      expect(controller.rangeFor('d', 0), const TextRange(start: 2, end: 5));
      controller.selection = range(1, 3);
      expect(controller.getText(), ' xyz');
      final content = controller.selectedContent();
      expect(content.documents.single.blocks.single.text, ' xyz');
      expect(content.documents.single.blocks.single.renderedRange,
          const TextRange(start: 1, end: 5));
    });

    testWidgets('a boundary on the edge of the alt is left alone',
        (tester) async {
      final controller = await pump(tester);
      controller.selection = range(2, 5);
      expect(controller.getText(), 'xyz');
      controller.selection = range(0, 2);
      expect(controller.getText(), 'a ');
      controller.selection = range(5, 7);
      expect(controller.getText(), ' b');
    });

    testWidgets('a collapsed selection inside an alt selects nothing',
        (tester) async {
      final controller = await pump(tester);
      controller.selection = range(3, 3);
      expect(controller.getText(), '');
    });

    testWidgets('the selection stays whole once the embed is unmounted',
        (tester) async {
      final controller = await pump(tester);
      controller.selection = range(3, 7);
      await tester.pumpWidget(const SizedBox());
      expect(controller.getText(), 'xyz b');
    });

    testWidgets('a new model forgets the ranges of the old one',
        (tester) async {
      final controller = await pump(tester);
      controller.putDocument('d', Markdown.fromString('a xyz b'));
      controller.selection = range(3, 7);
      expect(controller.getText(), 'yz b');
    });

    testWidgets('a double click on the embed selects its alt', (tester) async {
      final controller = await pump(tester);
      final top = tester.getTopLeft(find.byType(_EmbedBody));
      final at = top + const Offset(34, 6);
      final first =
          await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await first.up();
      await tester.pump(const Duration(milliseconds: 50));
      final second =
          await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await second.up();
      await tester.pumpAndSettle();
      expect(controller.getText(), 'xyz');
    });
  });

  group('inline embed: unresolved targets are today\'s alt text', () {
    // The reference: a body with no resolver at all.
    BlockPainter$Paragraph reference(String source) => _paragraph(source);

    void expectSameLayout(BlockPainter$Paragraph actual, String source) {
      final expected = reference(source);
      expect(actual.painter.plainText, expected.painter.plainText);
      expect(actual.renderedText, expected.renderedText);
      expect(actual.size, expected.size);
      expect(
        actual.boxesForRange(0, actual.renderedText.length),
        expected.boxesForRange(0, expected.renderedText.length),
      );
      expect(MarkdownEmbedOffsets.of(actual.painter).isIdentity, isTrue);
    }

    test('a scheme the resolver does not know', () {
      const source = 'a ![xyz](other:1) b';
      final resolver = FakeInlineEmbedResolver();
      final block = _paragraph(source, resolver: resolver);
      expectSameLayout(block, source);
      expect(resolver.resolved, isEmpty);
    });

    test('a resolver that answers null', () {
      const source = 'a ![xyz](emoji:1) b';
      final resolver = FakeInlineEmbedResolver(schemes: const <String>{});
      final block = _paragraph(source, resolver: resolver);
      expectSameLayout(block, source);
    });

    test('a source with no scheme, and one that is a web address', () {
      for (final source in <String>[
        'a ![xyz](picture.png) b',
        'a ![xyz](https://example.com/p.png) b',
        'a ![xyz]() b',
      ]) {
        final resolver = FakeInlineEmbedResolver();
        final block = _paragraph(source, resolver: resolver);
        expectSameLayout(block, source);
        expect(resolver.resolved, isEmpty, reason: source);
      }
    });

    test('no resolver at all', () {
      const source = 'a ![xyz](emoji:1) b';
      final block = _paragraph(source);
      expect(block.renderedText, 'a xyz b');
      expect(MarkdownEmbedOffsets.of(block.painter).isIdentity, isTrue);
      expect(block.painter.inlinePlaceholderBoxes, anyOf(isNull, isEmpty));
    });

    test('an unresolved embed stays among resolved ones, in order', () {
      final block = _paragraph(
        'a ![x](emoji:1) b ![yy](other:2) c ![z](emoji:3)',
        resolver: FakeInlineEmbedResolver(),
      );
      expect(block.renderedText, 'a x b yy c z');
      expect(MarkdownEmbedOffsets.of(block.painter).entries, hasLength(2));
      expect(block.painter.plainText, 'a ￼ b yy c ￼');
    });
  });

  group('inline embed: blocks other than a paragraph', () {
    test('a list item, a quote, an alert and a heading reserve room', () {
      for (final source in <String>[
        '- one ![xyz](emoji:1) two',
        '> one ![xyz](emoji:1) two',
        '> [!NOTE]\n> one ![xyz](emoji:1) two',
        '# one ![xyz](emoji:1) two',
        '| h |\n| - |\n| one ![xyz](emoji:1) two |',
        '> - one ![xyz](emoji:1) two',
      ]) {
        final resolver = FakeInlineEmbedResolver();
        final markdown = Markdown.fromString(source);
        final painter = MarkdownPainter(
          markdown: markdown,
          theme: _theme(),
          embedResolver: resolver,
        )..layout(maxWidth: 400);
        addTearDown(painter.dispose);
        expect(resolver.resolved, hasLength(1), reason: source);
        final (_, offset, _) = painter.positionAndAffinityForLocal(
          const Offset(399, 6),
        )!;
        // The pointer past the text is the end of the block's rendered text,
        // whatever the block, and that text has the alt in it.
        expect(
          offset,
          markdownBlockRenderedText(markdown.blocks.first).length,
          reason: source,
        );
        expect(offset, greaterThanOrEqualTo('one xyz two'.length));
      }
    });
  });

  group('inline embed: lifetime', () {
    const source = 'a ![x](emoji:1) b ![y](emoji:2)';

    testWidgets(
        'every embed is disposed once, after a model change and '
        'after the widget is removed', (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(
        _app(_EmbedBody(
          markdown: Markdown.fromString(source),
          resolver: resolver,
        )),
      );
      expect(resolver.resolved, hasLength(2));
      expect(resolver.live, hasLength(2));

      await tester.pumpWidget(
        _app(_EmbedBody(
          markdown: Markdown.fromString('c ![z](emoji:3)'),
          resolver: resolver,
        )),
      );
      expect(resolver.resolved, hasLength(3));
      expect(
          resolver.resolved.take(2).every((e) => e.disposeCount == 1), isTrue);
      expect(resolver.live.single.target.alt, 'z');

      await tester.pumpWidget(_app(const SizedBox()));
      expect(resolver.live, isEmpty);
      expect(resolver.resolved.map((e) => e.disposeCount), [1, 1, 1]);
    });

    testWidgets('a list that lays out again does not keep the old embeds',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      final markdown = Markdown.fromString('- ![x](emoji:1) one\n- two');
      await tester.pumpWidget(
        _app(_EmbedBody(markdown: markdown, resolver: resolver), width: 300),
      );
      await tester.pumpWidget(
        _app(_EmbedBody(markdown: markdown, resolver: resolver), width: 200),
      );
      expect(resolver.resolved.length, greaterThan(1));
      expect(resolver.live, hasLength(1));
      expect(resolver.resolved.every((e) => e.disposeCount <= 1), isTrue);
      await tester.pumpWidget(_app(const SizedBox()));
      expect(resolver.resolved.every((e) => e.disposeCount == 1), isTrue);
    });

    testWidgets('a table that lays out again does not keep the old embeds',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      final markdown = Markdown.fromString(
        '| h |\n| - |\n| ![x](emoji:1) |',
      );
      await tester.pumpWidget(
        _app(_EmbedBody(markdown: markdown, resolver: resolver), width: 300),
      );
      await tester.pumpWidget(
        _app(_EmbedBody(markdown: markdown, resolver: resolver), width: 200),
      );
      expect(resolver.live, hasLength(1));
      expect(resolver.resolved.every((e) => e.disposeCount <= 1), isTrue);
    });

    testWidgets('a new resolver replaces the embeds of the old one',
        (tester) async {
      final first = FakeInlineEmbedResolver();
      final second = FakeInlineEmbedResolver();
      final markdown = Markdown.fromString(source);
      await tester.pumpWidget(
        _app(_EmbedBody(markdown: markdown, resolver: first)),
      );
      await tester.pumpWidget(
        _app(_EmbedBody(markdown: markdown, resolver: second)),
      );
      expect(first.live, isEmpty);
      expect(first.resolved.map((e) => e.disposeCount), [1, 1]);
      expect(second.live, hasLength(2));
      await tester.pumpWidget(
        _app(_EmbedBody(markdown: markdown, resolver: null)),
      );
      expect(second.live, isEmpty);
    });

    testWidgets('a change of device pixel ratio makes embeds of the new size',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      final markdown = Markdown.fromString('a ![x](emoji:1)');
      await tester.pumpWidget(
        _app(_EmbedBody(markdown: markdown, resolver: resolver)),
      );
      await tester.pumpWidget(
        _app(_EmbedBody(
          markdown: markdown,
          resolver: resolver,
          devicePixelRatio: 2,
        )),
      );
      expect(resolver.resolved.map((e) => e.size.width), [16, 15.5]);
      expect(resolver.live, hasLength(1));
    });

    testWidgets('a font change rebuilds and disposes without a leak',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(
        _app(_EmbedBody(
          markdown: Markdown.fromString(source),
          resolver: resolver,
        )),
      );
      final ro =
          tester.renderObject(find.byType(_EmbedBody)) as MarkdownRenderObject;
      ro.debugPainter.invalidateLayout();
      expect(
          resolver.resolved.take(2).every((e) => e.disposeCount == 1), isTrue);
      expect(resolver.live, hasLength(2));
    });
  });
}
