import 'dart:io' show Directory;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/markdown_render_object.dart';
import 'package:flutter_test/flutter_test.dart';

/// The selection highlight reads as one patch per line, whatever it covers
/// (text, an emoji run drawn larger than the text, an inline embed): the same
/// top and bottom, no seams between neighbours, behind everything it covers.
///
/// These tests read pixels, not rectangles, so they hold the user's symptom
/// (boxes of different heights, a tint over an embed, a patch over a spoiler
/// that shows where the emoji are) and not one way of drawing it.
///
/// Tests run in Ahem: every glyph is a `fontSize` square. The text is
/// transparent, so what is on the canvas is the selection colour (opaque
/// green, so a pixel is either in the highlight or it is not) and the embeds
/// (opaque red).
const double _fontSize = 13;
const Color _green = Color(0xFF00B000);
const Color _red = Color(0xFFFF0000);
const Color _white = Color(0xFFFFFFFF);

/// Marks `[` to `]` as an emoji, as a host's scanner marks the sequences it
/// knows; the brackets stay in the text.
Iterable<TextRange> _bracketed(String text) sync* {
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '[') start = i;
    if (text[i] == ']' && start >= 0) {
      yield TextRange(start: start, end: i + 1);
      start = -1;
    }
  }
}

/// An embed that paints its whole square opaque red, whatever the context.
final class _RedEmbed extends ChangeNotifier implements MarkdownInlineEmbed {
  _RedEmbed(this.size);

  @override
  final Size size;

  @override
  bool visible = true;

  /// The last rectangle [paint] was given, after the canvas transform.
  Rect? lastRect;

  @override
  void paint(
    ui.Canvas canvas,
    Rect rect,
    MarkdownInlineEmbedPaintContext context,
  ) {
    lastRect = rect;
    canvas.drawRect(
      rect,
      Paint()..color = _red.withValues(alpha: context.opacity),
    );
  }
}

final class _RedEmbeds implements MarkdownInlineEmbedResolver {
  final List<_RedEmbed> made = <_RedEmbed>[];

  @override
  MarkdownInlineEmbed? resolve(
    MarkdownInlineEmbedTarget target,
    MarkdownInlineEmbedMetrics metrics,
  ) {
    final embed = _RedEmbed(Size.square(metrics.extent));
    made.add(embed);
    return embed;
  }
}

MarkdownThemeData _theme({
  TextDirection direction = TextDirection.ltr,
  double? height,
  double emojiScale = 1.2,
  Color ink = const Color(0x00000000),
}) =>
    MarkdownThemeData(
      textStyle: TextStyle(
        fontSize: _fontSize,
        color: ink,
        height: height,
      ),
      textDirection: direction,
      emojiRuns: _bracketed,
      emojiScale: emojiScale,
    );

/// The pixels of a body, read in the body's own coordinates: a row above the
/// first line (an embed pokes out there) is negative.
final class _Shot {
  _Shot(this.width, this.height, this._bytes, this.embeds);

  /// Room round the body, in pixels, so nothing that pokes out is cut.
  static const int pad = 4;

  /// The body's size, without the [pad].
  final int width;
  final int height;
  final ByteData _bytes;
  final List<_RedEmbed> embeds;

  Iterable<int> get xs =>
      Iterable<int>.generate(width + 2 * pad, (i) => i - pad);
  Iterable<int> get ys =>
      Iterable<int>.generate(height + 2 * pad, (i) => i - pad);

  Color at(int x, int y) {
    final i = ((y + pad) * (width + 2 * pad) + (x + pad)) * 4;
    return Color.fromARGB(
      _bytes.getUint8(i + 3),
      _bytes.getUint8(i),
      _bytes.getUint8(i + 1),
      _bytes.getUint8(i + 2),
    );
  }

  bool isGreen(int x, int y) => at(x, y) == _green;
  bool isRed(int x, int y) => at(x, y) == _red;
  bool isWhite(int x, int y) => at(x, y) == _white;

  /// Whether the pixel has been drawn on at all (an antialiased edge counts).
  bool isInk(int x, int y) => !isWhite(x, y);

  bool _solid(int x, int y) => isGreen(x, y) || isRed(x, y);

  /// The rows of column [x] that are green.
  List<int> greenRows(int x) => <int>[
        for (final y in ys)
          if (isGreen(x, y)) y,
      ];

  /// The columns of row [y] that have been drawn on.
  List<int> inkColumns(int y) => <int>[
        for (final x in xs)
          if (isInk(x, y)) x,
      ];

  /// Blended pixels with the same solid colour on both sides: a seam inside
  /// a patch. An antialiased edge has another colour on one side (white, or
  /// the embed's red against the highlight's green), so it is not one.
  List<String> seams() {
    bool same(int x0, int y0, int x1, int y1) =>
        _solid(x0, y0) && at(x0, y0) == at(x1, y1);
    return <String>[
      for (final y in ys)
        for (final x in xs)
          if (x > -pad &&
              y > -pad &&
              x < width + pad - 1 &&
              y < height + pad - 1 &&
              !_solid(x, y) &&
              !isWhite(x, y) &&
              (same(x - 1, y, x + 1, y) || same(x, y - 1, x, y + 1)))
            '($x, $y) ${at(x, y)}',
    ];
  }
}

final GlobalKey _shotKey = GlobalKey();

/// The body of [source] with [range] selected (all of it without one).
Future<_Shot> _shoot(
  WidgetTester tester,
  String source, {
  TextDirection direction = TextDirection.ltr,
  double width = 400,
  double? lineHeight,
  double emojiScale = 1.2,
  MarkdownSpoilerController? spoilers,
  (int, int)? range,
  Color ink = const Color(0x00000000),
  Color? selectionColor = _green,
  double devicePixelRatio = 1,
}) async {
  final model = Markdown.fromString(source);
  final controller = MarkdownSelectionController()
    ..selectionColor = selectionColor
    ..setDocuments(<MarkdownDocumentRef>[
      MarkdownDocumentRef(id: 'd', model: model),
    ]);
  addTearDown(controller.dispose);
  final resolver = _RedEmbeds();
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _shotKey,
          child: ColoredBox(
            color: _white,
            child: Padding(
              padding: const EdgeInsets.all(_Shot.pad * 1.0),
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: MediaQueryData(devicePixelRatio: devicePixelRatio),
                  child: MarkdownWidget(
                    markdown: model,
                    theme: _theme(
                      direction: direction,
                      height: lineHeight,
                      emojiScale: emojiScale,
                      ink: ink,
                    ),
                    embedResolver: resolver,
                    controller: controller,
                    spoilerController: spoilers,
                    documentId: 'd',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final last = model.blocks.length - 1;
  final lastLength = markdownBlockRenderedText(model.blocks[last]).length;
  controller.selection = MarkdownSelection(
    base: MarkdownPosition(
      documentId: 'd',
      blockIndex: 0,
      offset: range?.$1 ?? 0,
    ),
    extent: MarkdownPosition(
      documentId: 'd',
      blockIndex: range == null ? last : 0,
      offset: range?.$2 ?? lastLength,
    ),
  );
  await tester.pump();
  await tester.pump();
  final body = tester.getSize(find.byType(MarkdownWidget));
  final boundary =
      _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final shot = _Shot(
    body.width.round(),
    body.height.round(),
    bytes,
    resolver.made,
  );
  image.dispose();
  return shot;
}

/// An embed's rectangle, in the body's own coordinates.
Rect _rectOf(_RedEmbed embed) => embed.lastRect!;

void main() {
  group('selection highlight', () {
    // One line holding every kind of content the highlight has to cover: plain
    // text, an emoji run (drawn 1.2 x the font), an embed (the custom emoji).
    const mixed = 'ab [e] cd ![xy](emoji:1) ef [f] gh';
    final lineHeight = _fontSize.round();

    testWidgets('one line: one rectangle as tall as the line, over everything',
        (tester) async {
      final shot = await _shoot(tester, mixed);

      // The line is `_fontSize` tall (an emoji run's line is pinned to the
      // text's), and the highlight is exactly that tall wherever it is.
      var covered = 0;
      for (final x in shot.xs) {
        final rows = shot.greenRows(x);
        if (rows.isEmpty) continue;
        covered++;
        expect(
          rows,
          [for (var y = 0; y < lineHeight; y++) y],
          reason: 'column $x',
        );
      }
      expect(covered, greaterThan(100));
    });

    testWidgets('one line: no seam or gap between runs', (tester) async {
      final shot = await _shoot(tester, mixed);

      for (var y = 0; y < lineHeight; y++) {
        final xs = shot.inkColumns(y);
        expect(xs, isNotEmpty, reason: 'row $y');
        expect(xs.last - xs.first + 1, xs.length,
            reason: 'row $y has a gap in the highlight');
      }
      expect(shot.seams(), isEmpty);
    });

    testWidgets('an embed is drawn as it is, with no tint over it',
        (tester) async {
      final shot = await _shoot(tester, mixed);

      final rect = _rectOf(shot.embeds.single);
      for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
        for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
          expect(shot.isRed(x, y), isTrue,
              reason: '($x, $y) in the embed is ${shot.at(x, y)}');
        }
      }
    });

    testWidgets('the highlight is behind the embed: it shows round it',
        (tester) async {
      final shot = await _shoot(tester, mixed);

      // The embed is 16 tall in a line of 13: it pokes out above and below the
      // highlight, which is the line, and the pixels beside it are green.
      final rect = _rectOf(shot.embeds.single);
      expect(shot.isGreen(rect.left.floor() - 1, 6), isTrue);
      expect(shot.isGreen(rect.right.ceil() + 1, 6), isTrue);
      expect(shot.isWhite(rect.center.dx.round(), rect.top.floor() - 1), true);
    });

    testWidgets('a selection from the middle of a run is as tall as a line',
        (tester) async {
      // From inside 'cd' to inside the second emoji run.
      final shot = await _shoot(tester, mixed, range: (9, 21));

      for (final x in shot.xs) {
        final rows = shot.greenRows(x);
        if (rows.isEmpty) continue;
        expect(rows, [for (var y = 0; y < lineHeight; y++) y],
            reason: 'column $x');
      }
    });

    for (final direction in TextDirection.values) {
      testWidgets('${direction.name}: one rectangle across the line',
          (tester) async {
        final shot = await _shoot(tester, mixed, direction: direction);

        for (var y = 0; y < lineHeight; y++) {
          final xs = shot.inkColumns(y);
          expect(xs, isNotEmpty, reason: 'row $y');
          expect(xs.last - xs.first + 1, xs.length, reason: 'row $y has a gap');
        }
        for (final x in shot.xs) {
          final rows = shot.greenRows(x);
          if (rows.isEmpty) continue;
          expect(rows, [for (var y = 0; y < lineHeight; y++) y],
              reason: 'column $x');
        }
        expect(shot.seams(), isEmpty);
      });
    }

    testWidgets('wrapped lines: lines touch, with no seam between them',
        (tester) async {
      // A fractional line height, so a seam between two lines would show.
      final shot = await _shoot(
        tester,
        'aaaa [e] bb ![xy](emoji:1) cc dd [f] ee ff gg',
        width: 130,
        lineHeight: 1.3,
      );

      expect(shot.height, greaterThan(2 * lineHeight));
      // Column 2 is inside every line's highlight: it is covered from the top
      // of the first line to the bottom of the last, with nothing in between.
      final covered = [
        for (var y = 0; y < shot.height; y++)
          if (shot.isGreen(2, y)) y,
      ];
      expect(covered.length, greaterThanOrEqualTo(shot.height - 1));
      expect(shot.seams(), isEmpty);
    });

    testWidgets('mixed direction: still one rectangle across the line',
        (tester) async {
      final shot = await _shoot(
        tester,
        'ab \u05D0\u05D1\u05D2 [e] ![xy](emoji:1) cd \u05D3\u05D4 ef',
      );

      for (var y = 0; y < lineHeight; y++) {
        final xs = shot.inkColumns(y);
        expect(xs.last - xs.first + 1, xs.length, reason: 'row $y has a gap');
      }
      for (final x in shot.xs) {
        final rows = shot.greenRows(x);
        if (rows.isEmpty) continue;
        expect(rows, [for (var y = 0; y < lineHeight; y++) y],
            reason: 'column $x');
      }
      expect(shot.seams(), isEmpty);
    });

    testWidgets('wrapped right to left: lines touch, with no seam',
        (tester) async {
      final shot = await _shoot(
        tester,
        'aaaa [e] bb ![xy](emoji:1) cc dd [f] ee ff gg',
        direction: TextDirection.rtl,
        width: 130,
        lineHeight: 1.3,
      );

      expect(shot.height, greaterThan(2 * lineHeight));
      final right = shot.width - 3;
      final covered = [
        for (var y = 0; y < shot.height; y++)
          if (shot.isGreen(right, y)) y,
      ];
      expect(covered.length, greaterThanOrEqualTo(shot.height - 1));
      expect(shot.seams(), isEmpty);
    });

    testWidgets('a fenced code block: one rectangle per line, lines touch',
        (tester) async {
      // Code paints its highlight above its own fill, with a style run for
      // every token: the rectangles must still be the lines, whole.
      const source = '```dart\nvoid main() {\n  print(1);\n}\n```';
      final model = Markdown.fromString(source);
      final controller = MarkdownSelectionController()
        ..setDocuments(<MarkdownDocumentRef>[
          MarkdownDocumentRef(id: 'd', model: model),
        ]);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: MarkdownWidget(
                markdown: model,
                theme: _theme(),
                controller: controller,
                documentId: 'd',
              ),
            ),
          ),
        ),
      );
      final text = markdownBlockRenderedText(model.blocks.first);
      final render = tester.renderObject<MarkdownRenderObject>(
        find.byType(MarkdownWidget),
      );

      final rects = render.debugPainter.localBoxesForRange(0, 0, text.length);

      expect(rects, hasLength(3));
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].height, rects.first.height);
        if (i > 0) expect(rects[i].top, closeTo(rects[i - 1].bottom, 1e-6));
      }
    });

    group('in a block with chrome', () {
      // The highlight is behind the embed there too: a block that paints an
      // opaque fill (a table, a code fence) puts its highlight above the glyph
      // picture, and still no tint reaches an embed.
      const sources = <String, String>{
        'a quote': '> ab ![xy](emoji:1) cd [e]',
        'a list': '- ab ![xy](emoji:1) cd [e]\n- ef',
        'a table': '| a | ![xy](emoji:1) |\n|---|---|\n| [e] | c |',
        'a heading': '# ab ![xy](emoji:1) cd',
        'an alert': '> [!NOTE]\n> ab ![xy](emoji:1) cd',
      };
      for (final MapEntry(key: name, value: source) in sources.entries) {
        testWidgets('$name: an embed is drawn as it is', (tester) async {
          final shot = await _shoot(tester, source);

          final rect = _rectOf(shot.embeds.single);
          for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
            for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
              expect(shot.isRed(x, y), isTrue,
                  reason: '($x, $y) in the embed is ${shot.at(x, y)}');
            }
          }
        });
      }
    });

    group('goldens', () {
      // The aggregate entrypoint runs from test/, so a bare golden path would
      // resolve there; pin the comparator to this file and put it back.
      late GoldenFileComparator previous;
      setUpAll(() {
        previous = goldenFileComparator;
        goldenFileComparator = LocalFileComparator(
          Uri.file(
            '${Directory.current.path}/test/render/'
            'selection_highlight_test.dart',
          ),
        );
      });
      tearDownAll(() => goldenFileComparator = previous);

      // The text is a faint grey, so the highlight shows through the Ahem
      // squares, and the emoji run (1.2 x the font) pokes out of the line.
      const ink = Color(0x33000000);
      for (final direction in TextDirection.values) {
        testWidgets('text, an emoji run and an embed, ${direction.name}',
            (tester) async {
          await _shoot(
            tester,
            'ab [e] cd ![xy](emoji:1) ef [f] gh',
            direction: direction,
            width: 480,
            ink: ink,
            selectionColor: null,
            devicePixelRatio: 3,
          );
          await expectLater(
            find.byKey(_shotKey),
            matchesGoldenFile('goldens/selection_line_${direction.name}.png'),
          );
        });
      }

      testWidgets('wrapped lines with a line height', (tester) async {
        await _shoot(
          tester,
          'aaaa [e] bb ![xy](emoji:1) cc dd [f] ee ff gg',
          width: 130,
          lineHeight: 1.3,
          ink: ink,
          selectionColor: null,
          devicePixelRatio: 3,
        );
        await expectLater(
          find.byKey(_shotKey),
          matchesGoldenFile('goldens/selection_wrapped.png'),
        );
      });
    });

    group('over a hidden spoiler', () {
      late MarkdownSpoilerController spoilers;
      setUp(() => spoilers = MarkdownSpoilerController(animate: false));
      tearDown(() => spoilers.dispose());

      testWidgets('every position is the same rectangle, an embed is hidden',
          (tester) async {
        final shot = await _shoot(
          tester,
          'a ||bc [e] de ![xy](emoji:1) fg|| h',
          spoilers: spoilers,
        );

        // Nothing red: the embed is hidden, and no tint is drawn over where
        // it is.
        for (final y in shot.ys) {
          for (final x in shot.xs) {
            expect(shot.isRed(x, y), isFalse, reason: '($x, $y)');
          }
        }
        // One rectangle: every column that has the highlight has it on the
        // same rows, as many as the line is tall, so the emoji's position
        // cannot be told from the text's.
        for (final x in shot.xs) {
          final rows = shot.greenRows(x);
          if (rows.isEmpty) continue;
          expect(rows, [for (var y = 0; y < lineHeight; y++) y],
              reason: 'column $x');
        }
        expect(shot.seams(), isEmpty);
      });
    });
  });
}
