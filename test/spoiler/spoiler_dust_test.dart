import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/markdown_painter.dart';
import 'package:flutter_md/src/render/markdown_render_object.dart';
import 'package:flutter_md/src/render/spoiler_particle_tile.dart';
import 'package:flutter_test/flutter_test.dart';

Key _key(Object id) => ValueKey<Object>(id);

const _hidden = 'before ||secret words|| after';
const _plain = 'nothing hidden here';

/// Renders for real and counts how often.
class _Renders {
  int count = 0;

  ui.Image call(ui.Picture picture, int size) {
    count++;
    return picture.toImageSync(size, size);
  }
}

MarkdownThemeData _theme([Color color = const Color(0xFF0D47A1)]) =>
    MarkdownThemeData(textStyle: TextStyle(fontSize: 14, color: color));

Widget _body(
  List<(Object id, String source)> documents,
  MarkdownSpoilerController spoilers, {
  MarkdownThemeData? theme,
  bool disableAnimations = false,
}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (id, source) in documents)
                  MarkdownWidget(
                    key: _key(id),
                    markdown: Markdown.fromString(source),
                    theme: theme ?? _theme(),
                    documentId: id,
                    spoilerController: spoilers,
                  ),
              ],
            ),
          ),
        ),
      ),
    );

MarkdownPainter _painterOf(WidgetTester tester, Object id) =>
    (tester.renderObject(find.byKey(_key(id))) as MarkdownRenderObject)
        .debugPainter;

List<(Object, String)> _documents(int n) => [
      for (var i = 0; i < n; i++) ('doc$i', _hidden),
    ];

/// One dust frame later, as a host's clock would deliver it.
Duration _frame(int n) => Duration(microseconds: n * 1000000 ~/ 30 + 1);

void main() {
  late _Renders renders;
  late MarkdownSpoilerController spoilers;

  setUp(() {
    renders = _Renders();
    SpoilerParticleTiles.debugConfigure(
      random: () => Random(1),
      renderer: renders.call,
    );
    spoilers = MarkdownSpoilerController();
  });

  tearDown(() {
    spoilers.dispose();
    SpoilerParticleTiles.debugReset();
  });

  group('spoiler dust', () {
    testWidgets('every widget shares one tile per colour and pixel ratio',
        (tester) async {
      await tester.pumpWidget(_body(_documents(4), spoilers));

      final tiles = {
        for (var i = 0; i < 4; i++) _painterOf(tester, 'doc$i').debugFillTile,
      };

      expect(tiles, hasLength(1));
      expect(tiles.single, isNotNull);
      expect(SpoilerParticleTiles.debugLiveCount, 1);
    });

    testWidgets('a theme colour change replaces the tile and disposes the old',
        (tester) async {
      await tester.pumpWidget(_body(_documents(2), spoilers));
      final old = _painterOf(tester, 'doc0').debugFillTile!;

      await tester.pumpWidget(
        _body(_documents(2), spoilers, theme: _theme(const Color(0xFFFFFFFF))),
      );
      final next = _painterOf(tester, 'doc0').debugFillTile!;

      expect(next, isNot(same(old)));
      expect(next.color, const Color(0xFFFFFFFF));
      expect(old.debugDisposed, isTrue);
      expect(_painterOf(tester, 'doc1').debugFillTile, same(next));
      expect(SpoilerParticleTiles.debugLiveCount, 1);
    });

    testWidgets('a new theme object of the same colour keeps the tile',
        (tester) async {
      await tester.pumpWidget(_body(_documents(1), spoilers));
      final tile = _painterOf(tester, 'doc0').debugFillTile!;

      await tester.pumpWidget(
        _body(_documents(1), spoilers, theme: _theme()),
      );

      expect(_painterOf(tester, 'doc0').debugFillTile, same(tile));
      expect(tile.debugDisposed, isFalse);
      expect(renders.count, 1);
    });

    testWidgets('a revealed document gives the tile up', (tester) async {
      spoilers.animate = false;
      await tester.pumpWidget(_body(_documents(2), spoilers));
      expect(SpoilerParticleTiles.debugLiveCount, 1);

      spoilers.reveal('doc0');
      await tester.pump();
      expect(SpoilerParticleTiles.debugLiveCount, 1);

      spoilers.reveal('doc1');
      await tester.pump();
      expect(SpoilerParticleTiles.debugLiveCount, 0);
    });

    testWidgets('unmounting the last hidden spoiler frees the tile',
        (tester) async {
      await tester.pumpWidget(_body(_documents(2), spoilers));

      await tester.pumpWidget(_body(const [], spoilers));

      expect(SpoilerParticleTiles.debugLiveCount, 0);
    });

    testWidgets('one render per tick, however many spoilers are on screen',
        (tester) async {
      await tester.pumpWidget(_body(_documents(20), spoilers));
      expect(renders.count, 1);

      for (var frame = 1; frame <= 5; frame++) {
        spoilers.advance(_frame(frame));
        await tester.pump();
        expect(renders.count, 1 + frame);
      }
    });

    testWidgets('a clock faster than the dust rate repaints once per frame',
        (tester) async {
      await tester.pumpWidget(_body(_documents(3), spoilers));

      // 60 fps for one second: 30 dust frames.
      for (var i = 1; i <= 60; i++) {
        spoilers.advance(Duration(microseconds: i * 1000000 ~/ 60));
        await tester.pump();
      }

      expect(renders.count, 1 + 30);
    });

    testWidgets('a tick records no glyph picture', (tester) async {
      await tester.pumpWidget(_body(_documents(2), spoilers));
      final painter = _painterOf(tester, 'doc0');
      final recordings = painter.debugPictureRecordings;

      for (var frame = 1; frame <= 10; frame++) {
        spoilers.advance(_frame(frame));
        await tester.pump();
      }

      expect(painter.debugPictureRecordings, recordings);
      expect(painter.debugCachedPictureCount, 1);
    });
  });

  group('spoiler dust clock', () {
    testWidgets('no tick is wanted while no hidden spoiler is mounted',
        (tester) async {
      expect(spoilers.wantsTicks.value, isFalse);

      spoilers.advance(_frame(1));
      await tester.pump();
      expect(renders.count, 0);

      await tester.pumpWidget(_body([('p', _plain)], spoilers));
      expect(spoilers.wantsTicks.value, isFalse);
    });

    testWidgets('a hidden spoiler wants ticks until it is revealed',
        (tester) async {
      final seen = <bool>[];
      spoilers.wantsTicks
          .addListener(() => seen.add(spoilers.wantsTicks.value));

      await tester.pumpWidget(_body([('a', _hidden)], spoilers));
      expect(spoilers.wantsTicks.value, isTrue);

      spoilers.reveal('a');
      await tester.pump();
      // The ripple still shows dust over what it has not reached.
      expect(spoilers.wantsTicks.value, isTrue);

      await tester.pump(const Duration(milliseconds: 400));
      expect(spoilers.wantsTicks.value, isFalse);
      expect(seen, <bool>[true, false]);
    });

    testWidgets('unmounting ends the wish', (tester) async {
      await tester.pumpWidget(_body([('a', _hidden)], spoilers));
      expect(spoilers.wantsTicks.value, isTrue);

      await tester.pumpWidget(_body(const [], spoilers));

      expect(spoilers.wantsTicks.value, isFalse);
    });

    testWidgets('two hidden documents count as two until both are gone',
        (tester) async {
      await tester.pumpWidget(_body(_documents(2), spoilers));

      await tester.pumpWidget(_body(_documents(1), spoilers));
      expect(spoilers.wantsTicks.value, isTrue);

      await tester.pumpWidget(_body(const [], spoilers));
      expect(spoilers.wantsTicks.value, isFalse);
    });

    testWidgets('motion off renders exactly once and wants no tick',
        (tester) async {
      spoilers.animate = false;
      await tester.pumpWidget(_body(_documents(5), spoilers));

      for (var frame = 1; frame <= 10; frame++) {
        spoilers.advance(_frame(frame));
        await tester.pump();
      }

      expect(spoilers.wantsTicks.value, isFalse);
      expect(renders.count, 1);
    });

    testWidgets('turning motion off stops the dust where it is',
        (tester) async {
      await tester.pumpWidget(_body(_documents(2), spoilers));
      spoilers.advance(_frame(1));
      await tester.pump();
      expect(renders.count, 2);

      spoilers.animate = false;
      await tester.pump();
      expect(spoilers.wantsTicks.value, isFalse);

      spoilers.advance(_frame(2));
      await tester.pump();
      expect(renders.count, 2);

      spoilers.animate = true;
      await tester.pump();
      expect(spoilers.wantsTicks.value, isTrue);
      spoilers.advance(_frame(3));
      await tester.pump();
      expect(renders.count, 3);
    });

    testWidgets('the platform asking for less keeps the dust still',
        (tester) async {
      await tester.pumpWidget(
        _body(_documents(2), spoilers, disableAnimations: true),
      );

      spoilers.advance(_frame(1));
      await tester.pump();

      expect(spoilers.wantsTicks.value, isFalse);
      expect(renders.count, 1);
    });

    testWidgets('a muted TickerMode keeps the dust still', (tester) async {
      await tester.pumpWidget(
        TickerMode(enabled: false, child: _body(_documents(1), spoilers)),
      );

      spoilers.advance(_frame(1));
      await tester.pump();

      expect(spoilers.wantsTicks.value, isFalse);
      expect(renders.count, 1);
    });

    testWidgets('without a host clock the dust is the first frame',
        (tester) async {
      await tester.pumpWidget(_body(_documents(3), spoilers));
      await tester.pump(const Duration(seconds: 2));

      expect(renders.count, 1);
      expect(spoilers.fillFrame, 0);
    });

    test('frames follow the time at the dust rate', () {
      expect(MarkdownSpoilerController.fillFrameRate, 30);
      expect(MarkdownSpoilerController.fillFrameAt(Duration.zero), 0);
      expect(
        MarkdownSpoilerController.fillFrameAt(
          const Duration(milliseconds: 33),
        ),
        0,
      );
      expect(
        MarkdownSpoilerController.fillFrameAt(
          const Duration(milliseconds: 34),
        ),
        1,
      );
      expect(
        MarkdownSpoilerController.fillFrameAt(const Duration(seconds: 1)),
        30,
      );
    });

    test('advance keeps the time it was given', () {
      spoilers.advance(const Duration(milliseconds: 250));

      expect(spoilers.elapsed, const Duration(milliseconds: 250));
      expect(spoilers.fillFrame, 7);
    });
  });

  group('spoiler dust without toImageSync', () {
    testWidgets('the static tile is used and no exception reaches the frame',
        (tester) async {
      var asked = 0;
      SpoilerParticleTiles.debugConfigure(
        renderer: (picture, size) {
          asked++;
          throw UnsupportedError('toImageSync');
        },
      );

      await tester.pumpWidget(_body(_documents(3), spoilers));
      for (var frame = 1; frame <= 5; frame++) {
        spoilers.advance(_frame(frame));
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
      final tile = _painterOf(tester, 'doc0').debugFillTile!;
      expect(tile.isStatic, isTrue);
      expect(tile.unsupported, isA<UnsupportedError>());
      expect(asked, 1);
      expect(tile.debugRenderCount, 1);
    });
  });
}
