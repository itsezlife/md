import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/markdown_render_object.dart';
import 'package:flutter_md/src/render/spoiler_particle_tile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compares against the files next to this test, whichever entrypoint runs
/// it, and forgives antialiasing noise at the ripple's circle edge (a fraction
/// of a percent of the pixels) so the same files hold on every platform.
class _SpoilerGoldenComparator extends LocalFileComparator {
  _SpoilerGoldenComparator(super.testFile);

  static const double _tolerance = 0.005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _tolerance) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}

/// A paragraph that draws a fake embed over the `#` in its text, the way a
/// live embed pass would: fully visible when the spoiler is revealed, absent
/// while it is hidden.
class _EmbedParagraph extends BlockPainter$Paragraph {
  _EmbedParagraph({required super.spans, required super.theme});

  @override
  void paint(Canvas canvas, Size size, double offset) {
    super.paint(canvas, size, offset);
    if (!spoilersRevealed) return;
    final at = renderedText.indexOf('#');
    final box = painter
        .getBoxesForSelection(
            TextSelection(baseOffset: at, extentOffset: at + 1))
        .first
        .toRect();
    canvas.drawRect(
      box.shift(Offset(0, offset)).deflate(1),
      Paint()..color = const Color(0xFFE65100),
    );
  }
}

const _source = 'Hello ||secret # words that wrap|| and a tail of text';

Future<void> _pumpBody(
  WidgetTester tester,
  MarkdownSpoilerController spoilers,
  TextDirection direction,
) async {
  tester.view
    ..physicalSize = const Size(320, 120)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: direction,
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: MarkdownWidget(
                markdown: Markdown.fromString(_source),
                documentId: 'doc',
                spoilerController: spoilers,
                theme: MarkdownThemeData(
                  textStyle:
                      const TextStyle(fontSize: 14, color: Color(0xFF0D47A1)),
                  textDirection: direction,
                  builder: (block, theme) => block is MD$Paragraph
                      ? _EmbedParagraph(spans: block.spans, theme: theme)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _twoLines =
    'Hello ||secret words that wrap onto a second line|| and a tail';

/// A hidden spoiler over two lines with the dust standing still (motion off)
/// and a seeded field, so the picture is the same on every run.
Future<void> _pumpDust(
  WidgetTester tester, {
  required Color ink,
  required Color paper,
}) async {
  tester.view
    ..physicalSize = const Size(220, 100)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final spoilers = MarkdownSpoilerController(animate: false);
  addTearDown(spoilers.dispose);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: paper,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: MarkdownWidget(
                markdown: Markdown.fromString(_twoLines),
                documentId: 'doc',
                spoilerController: spoilers,
                theme: MarkdownThemeData(
                  textStyle: TextStyle(fontSize: 14, color: ink),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('spoiler goldens', () {
    late GoldenFileComparator previous;

    setUpAll(() {
      previous = goldenFileComparator;
      goldenFileComparator = _SpoilerGoldenComparator(
        Uri.file('${Directory.current.path}/test/spoiler/spoiler_golden.dart'),
      );
    });

    tearDownAll(() => goldenFileComparator = previous);

    // The dust of every picture here comes from one seeded field.
    setUp(() => SpoilerParticleTiles.debugConfigure(random: () => Random(7)));
    tearDown(SpoilerParticleTiles.debugReset);

    group('static dust tile', () {
      testWidgets('dark text on light', (tester) async {
        await _pumpDust(
          tester,
          ink: const Color(0xFF0D47A1),
          paper: Colors.white,
        );

        await expectLater(
          find.byKey(const ValueKey('shot')),
          matchesGoldenFile('goldens/dust_light.png'),
        );
      });

      testWidgets('light text on dark', (tester) async {
        await _pumpDust(
          tester,
          ink: const Color(0xFFE3F2FD),
          paper: const Color(0xFF121212),
        );

        await expectLater(
          find.byKey(const ValueKey('shot')),
          matchesGoldenFile('goldens/dust_dark.png'),
        );
      });
    });

    for (final direction in TextDirection.values) {
      final name = direction.name;

      testWidgets('hidden, mid-ripple and revealed ($name)', (tester) async {
        final spoilers = MarkdownSpoilerController();
        addTearDown(spoilers.dispose);
        await _pumpBody(tester, spoilers, direction);
        final shot = find.byKey(const ValueKey('shot'));

        await expectLater(shot, matchesGoldenFile('goldens/hidden_$name.png'));

        final render = tester.renderObject(find.byType(MarkdownWidget))
            as MarkdownRenderObject;
        final spoiler = render.debugPainter.spoilerRects.first;
        await tester.tapAt(
          tester.getTopLeft(find.byType(MarkdownWidget)) + spoiler.center,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        await expectLater(
          shot,
          matchesGoldenFile('goldens/ripple_150ms_$name.png'),
        );

        await tester.pump(const Duration(milliseconds: 300));

        await expectLater(
          shot,
          matchesGoldenFile('goldens/revealed_$name.png'),
        );
      });
    }
  });
}
