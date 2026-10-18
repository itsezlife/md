import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/markdown_painter.dart';
import 'package:flutter_md/src/render/markdown_render_object.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_inline_embed_resolver.dart';

/// Tests run in Ahem: every glyph is a `fontSize` square, so `a ` is 26 logical
/// pixels, and the 16 pixel embed of a 13 pixel font starts at x 26.
const double _fontSize = 13;
const Color _ink = Color(0xFF112233);

MarkdownThemeData _theme({
  TextDirection direction = TextDirection.ltr,
  BlockPainter? Function(MD$Block, MarkdownThemeData)? builder,
}) =>
    MarkdownThemeData(
      textStyle: const TextStyle(fontSize: _fontSize, color: _ink),
      textDirection: direction,
      builder: builder,
    );

// One theme per direction, for the same reason: a new theme rebuilds.
final Map<TextDirection, MarkdownThemeData> _themes =
    <TextDirection, MarkdownThemeData>{
  for (final d in TextDirection.values) d: _theme(direction: d),
};

final Map<String, Markdown> _models = <String, Markdown>{};

final GlobalKey _bodyKey = GlobalKey(debugLabel: 'body');

/// A body of [source] shown through the public [MarkdownWidget].
Widget _app(
  String source,
  MarkdownInlineEmbedResolver? resolver, {
  double width = 400,
  double? height,
  TextDirection direction = TextDirection.ltr,
  MarkdownSelectionController? controller,
  MarkdownSpoilerController? spoilers,
  double devicePixelRatio = 1,
  MarkdownThemeData? theme,
  Key? key,
}) {
  Widget body = MarkdownWidget(
    key: key ?? _bodyKey,
    // The same model for the same text: a rebuild with a model that is
    // `identical` keeps the painters, and so the embeds.
    markdown: _models.putIfAbsent(source, () => Markdown.fromString(source)),
    theme: theme ?? _themes[direction],
    embedResolver: resolver,
    controller: controller,
    documentId: controller == null && spoilers == null ? null : 'd',
    spoilerController: spoilers,
  );
  body = MediaQuery(
    data: MediaQueryData(devicePixelRatio: devicePixelRatio),
    child: body,
  );
  return Directionality(
    textDirection: direction,
    child: ColoredBox(
      color: Colors.white,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, height: height, child: body),
      ),
    ),
  );
}

MarkdownRenderObject _render(WidgetTester tester) =>
    tester.renderObject<MarkdownRenderObject>(find.byType(MarkdownWidget));

MarkdownPainter _painter(WidgetTester tester) => _render(tester).debugPainter;

extension on FakeInlineEmbed {
  /// Where the last paint put the middle of the embed, after the transform.
  Offset get lastCentre {
    final p = this.paints.last;
    return MatrixUtils.transformPoint(p.transform, p.rect.center);
  }
}

void main() {
  group('embed paint: the live pass', () {
    testWidgets('an embed is painted into its square, in the text colour',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(_app('a ![ab](emoji:1) b', resolver));
      final embed = resolver.resolved.single;
      expect(embed.paints, hasLength(1));
      final paint = embed.paints.single;
      // 1.2 x 13 = 15.6, rounded to 16; centred on a line 13 tall.
      expect(paint.rect, const Rect.fromLTWH(26, -1.5, 16, 16));
      expect(paint.context.tint, _ink);
      expect(paint.context.opacity, 1);
    });

    testWidgets('the tint is the colour of the text the embed sits in',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      const red = Color(0xFFAA0000);
      await tester.pumpWidget(
        _app(
          '# ![ab](emoji:1)',
          resolver,
          theme: _theme().copyWith(
            h1Style: const TextStyle(fontSize: _fontSize, color: red),
          ),
        ),
      );
      expect(resolver.resolved.single.paints.single.context.tint, red);
    });

    testWidgets('a repaint draws it again where it was', (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(_app('a ![ab](emoji:1) b', resolver));
      final embed = resolver.resolved.single;
      embed.fire();
      await tester.pump();
      expect(embed.paints, hasLength(2));
      expect(embed.paints.last.rect, embed.paints.first.rect);
    });

    testWidgets('an invisible embed is not painted', (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(_app('a ![ab](emoji:1) b', resolver));
      final embed = resolver.resolved.single..visible = false;
      embed.fire();
      await tester.pump();
      expect(embed.paints, hasLength(1));
    });

    testWidgets(
        'embeds in a list, a quote and a table are painted where '
        'a hit finds them', (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(
        _app(
          '- one\n- two ![ab](emoji:1)\n\n'
          '> quoted ![cd](emoji:2)\n\n'
          '| h | i |\n| - | - |\n| x | ![ef](emoji:3) |',
          resolver,
        ),
      );
      final painter = _painter(tester);
      final kinds = <String, Type>{};
      for (final embed in resolver.resolved) {
        expect(embed.paints, hasLength(1), reason: embed.target.alt);
        final (index, block) = painter.blockAtLocal(embed.lastCentre)!;
        kinds[embed.target.alt] = block.runtimeType;
        // The alt has two code units; a hit on the embed lands inside it.
        final hit = painter.positionForLocal(embed.lastCentre)!;
        expect(hit.$1, index);
        final text = painter.markdown.blocks[index];
        expect(text, isA<MD$Block>());
        expect(hit.$2, greaterThan(0));
      }
      expect(kinds, {'ab': MD$List, 'cd': MD$Quote, 'ef': MD$Table});
    });

    testWidgets('a pannable table paints its embeds under the pan',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      // Wide cells in a narrow box: the table overflows and pans.
      const source = '| aaaaaaaa | bbbbbbbb | cccccccc |\n'
          '| - | - | - |\n'
          '| ![ab](emoji:1) | ![cd](emoji:2) | ![ef](emoji:3) |';
      BlockPainter? Function(MD$Block, MarkdownThemeData) pannable() =>
          (block, theme) => block is MD$Table
              ? BlockPainter$ScrollableTable(
                  header: block.header,
                  rows: block.rows,
                  alignments: block.alignments,
                  theme: theme,
                )
              : null;
      await tester.pumpWidget(
        _app(
          source,
          resolver,
          width: 100,
          theme: _theme(builder: pannable()),
        ),
      );
      final embed = resolver.resolved.last;
      final before = embed.lastCentre;
      final table = _painter(tester).pannablePainterAt(0)!;
      expect(table.canPanHorizontally, isTrue);
      table.applyScrollDelta(30);
      _render(tester).markNeedsPaint();
      await tester.pump();
      expect(embed.paints, hasLength(2));
      // The rectangle is the cell's; the pan moves the canvas it is drawn on.
      expect(embed.paints.last.rect, embed.paints.first.rect);
      expect(embed.lastCentre.dx, closeTo(before.dx - 30, 1e-6));
    });
  });

  group('embed paint: the glyph picture and layout', () {
    testWidgets(
        'an embed that signals on 100 frames records the picture once '
        'and lays out once', (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(_app('a ![ab](emoji:1) b', resolver));
      final embed = resolver.resolved.single;
      final painter = _painter(tester);
      expect(painter.debugPictureRecordings, 1);
      expect(painter.debugLayoutCount, 1);
      for (var i = 0; i < 100; i++) {
        embed.fire();
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(embed.paints, hasLength(101));
      expect(painter.debugPictureRecordings, 1);
      expect(painter.debugLayoutCount, 1);
    });

    testWidgets('a body without an embed pays nothing for the pass',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(_app('plain text', resolver));
      expect(resolver.resolved, isEmpty);
      expect(_painter(tester).hasEmbeds, isFalse);
    });
  });

  group('embed paint: invalidation', () {
    testWidgets('embeds that signal in one frame ask for one paint',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(
        _app(
          'a ![ab](emoji:1) b ![cd](emoji:2)\n\n- ![ef](emoji:3)\n\n'
          '![gh](emoji:4) ![ij](emoji:5)',
          resolver,
        ),
      );
      final render = _render(tester);
      expect(resolver.resolved, hasLength(5));
      final before = render.debugEmbedPaintRequests;
      for (final embed in resolver.resolved) {
        embed.fire();
        embed.fire();
      }
      expect(render.debugEmbedPaintRequests, before + 1);
      await tester.pump();
      for (final embed in resolver.resolved) {
        expect(embed.paints, hasLength(2));
      }
      // The next frame asks again.
      resolver.resolved.first.fire();
      expect(render.debugEmbedPaintRequests, before + 2);
      await tester.pump();
    });
  });

  group('embed paint: visibility', () {
    // Two paragraphs of one 13 pixel line each; the second starts at y 13.
    const source = 'a ![ab](emoji:1)\n\nb ![cd](emoji:2)';

    testWidgets(
        'an embed below the painted height is hidden, and shown again '
        'when the height returns', (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(_app(source, resolver, height: 40));
      expect(resolver.resolved.map((e) => e.visible), [true, true]);
      await tester.pumpWidget(_app(source, resolver, height: 5));
      // The model did not change: the same embeds are kept.
      expect(resolver.resolved, hasLength(2));
      expect(resolver.resolved.map((e) => e.visible), [true, false]);
      final paints = resolver.resolved.last.paints.length;
      resolver.resolved.last.fire();
      await tester.pump();
      expect(resolver.resolved.last.paints, hasLength(paints));
      await tester.pumpWidget(_app(source, resolver, height: 40));
      expect(resolver.resolved.map((e) => e.visible), [true, true]);
    });

    testWidgets('removing the widget hides the embeds before it disposes them',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(_app(source, resolver));
      await tester.pumpWidget(const SizedBox());
      for (final embed in resolver.resolved) {
        expect(embed.visibleChanges.last, isFalse);
        expect(embed.visibleWhenDisposed, isFalse);
        expect(embed.disposeCount, 1);
      }
    });

    testWidgets('an embed whose widget moves in the tree is shown again',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      Widget host(bool deep) => Directionality(
            textDirection: TextDirection.ltr,
            child: deep
                ? Padding(
                    padding: EdgeInsets.zero,
                    child: _app(source, resolver),
                  )
                : _app(source, resolver),
          );
      await tester.pumpWidget(host(false));
      await tester.pumpWidget(host(true));
      // A reparented render object is detached and attached again.
      expect(resolver.resolved.every((e) => e.visible), isTrue);
      expect(resolver.live, hasLength(2));
      final embed = resolver.resolved.first;
      final count = embed.paints.length;
      embed.fire();
      await tester.pump();
      expect(embed.paints.length, greaterThan(count));
    });
  });

  group('embed paint: the resolver parameter', () {
    testWidgets('replacing it disposes the old embeds and resolves anew',
        (tester) async {
      final first = FakeInlineEmbedResolver();
      final second = FakeInlineEmbedResolver();
      await tester.pumpWidget(_app('a ![ab](emoji:1) b', first));
      await tester.pumpWidget(_app('a ![ab](emoji:1) b', second));
      expect(first.live, isEmpty);
      expect(first.resolved.map((e) => e.disposeCount), [1]);
      expect(second.live, hasLength(1));
      expect(second.resolved.single.paints, hasLength(1));
    });

    testWidgets('the same resolver on a rebuild keeps its embeds',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(_app('a ![ab](emoji:1) b', resolver));
      await tester.pumpWidget(_app('a ![ab](emoji:1) b', resolver));
      expect(resolver.resolved, hasLength(1));
      expect(resolver.live, hasLength(1));
    });

    testWidgets('the device pixel ratio comes from MediaQuery', (tester) async {
      final resolver = FakeInlineEmbedResolver();
      await tester.pumpWidget(
        _app('a ![ab](emoji:1) b', resolver, devicePixelRatio: 2),
      );
      expect(resolver.metricsSeen.single.devicePixelRatio, 2);
      // 15.6 x 2 = 31.2, rounded to 31 device pixels.
      expect(resolver.resolved.single.size, const Size(15.5, 15.5));
      await tester.pumpWidget(_app('a ![ab](emoji:1) b', resolver));
      expect(resolver.metricsSeen.last.devicePixelRatio, 1);
      expect(resolver.resolved.last.size, const Size(16, 16));
    });
  });

  group('embed paint: spoilers', () {
    testWidgets('a hidden spoiler hides its embed; revealing paints it',
        (tester) async {
      final resolver = FakeInlineEmbedResolver();
      final spoilers = MarkdownSpoilerController(animate: false);
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(
        _app('a ||b ![ab](emoji:1) c||', resolver, spoilers: spoilers),
      );
      final embed = resolver.resolved.single;
      expect(embed.paints, isEmpty);
      spoilers.reveal('d');
      await tester.pump();
      await tester.pump();
      expect(embed.paints, isNotEmpty);
      expect(embed.paints.last.context.opacity, 1);
    });
  });

  group('embed paint: goldens', () {
    const source = 'a ![ab](emoji:1) b ![cd](emoji:2) c';
    const shot = ValueKey<String>('shot');

    // The aggregate entrypoint runs from test/, so a bare golden path would
    // resolve there; pin the comparator to this file and put it back.
    late GoldenFileComparator previous;
    setUpAll(() {
      previous = goldenFileComparator;
      goldenFileComparator = LocalFileComparator(
        Uri.file(
          '${Directory.current.path}/test/render/embed_paint_test.dart',
        ),
      );
    });
    tearDownAll(() => goldenFileComparator = previous);

    // A 3x display and a box just big enough for the line, so the image is
    // the paragraph and little else.
    Widget framed(
      WidgetTester tester,
      TextDirection direction, {
      MarkdownSelectionController? controller,
    }) {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      return Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: shot,
          child: SizedBox(
            width: 200,
            height: 20,
            child: _app(
              source,
              FakeInlineEmbedResolver(),
              width: 200,
              height: 20,
              direction: direction,
              controller: controller,
              devicePixelRatio: 3,
            ),
          ),
        ),
      );
    }

    for (final direction in TextDirection.values) {
      testWidgets('two embeds in a paragraph, ${direction.name}',
          (tester) async {
        await tester.pumpWidget(framed(tester, direction));
        await expectLater(
          find.byKey(shot),
          matchesGoldenFile('goldens/embeds_${direction.name}.png'),
        );
      });
    }

    testWidgets('a selection across one embed tints it', (tester) async {
      final controller = MarkdownSelectionController()
        ..setDocuments(<MarkdownDocumentRef>[
          MarkdownDocumentRef(id: 'd', model: Markdown.fromString(source)),
        ]);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        framed(tester, TextDirection.ltr, controller: controller),
      );
      // Rendered text 'a ab b cd c': select 'ab b' (2..6), the first embed
      // and the text after it; the second embed stays unselected.
      controller.selection = const MarkdownSelection(
        base: MarkdownPosition(documentId: 'd', blockIndex: 0, offset: 2),
        extent: MarkdownPosition(documentId: 'd', blockIndex: 0, offset: 6),
      );
      await tester.pump();
      await expectLater(
        find.byKey(shot),
        matchesGoldenFile('goldens/embeds_selected.png'),
      );
    });
  });
}
