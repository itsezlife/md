import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/markdown_painter.dart';
import 'package:flutter_md/src/render/markdown_render_object.dart';
import 'package:flutter_md/src/render/spoiler_phase.dart';
import 'package:flutter_test/flutter_test.dart';

Key _key(Object id) => ValueKey<Object>(id);

const _plain = 'before ||secret|| after';
const _link = 'before ||see [the link](https://x.example) here|| after';

MarkdownThemeData _theme({void Function(String, String)? onLinkTap}) =>
    MarkdownThemeData(
      textStyle: const TextStyle(fontSize: 14),
      onLinkTap: onLinkTap,
    );

Widget _body(
  List<(Object id, String source)> documents,
  MarkdownSpoilerController? spoilers, {
  MarkdownThemeData? theme,
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: direction,
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

/// Global centre of the first spoiler rect of document [id].
Offset _spoilerCenter(WidgetTester tester, Object id) =>
    tester.getTopLeft(find.byKey(_key(id))) +
    _painterOf(tester, id).spoilerRects.first.center;

void main() {
  group('MarkdownWidget spoilers', () {
    testWidgets('a widget with no controller paints spoilers as text',
        (tester) async {
      await tester.pumpWidget(_body([('a', _plain)], null));

      expect(
          _painterOf(tester, 'a').spoilerPhase, isA<SpoilerPhase$Revealed>());
    });

    testWidgets('with a controller the document starts hidden', (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(_body([('a', _plain)], spoilers));

      expect(_painterOf(tester, 'a').spoilerPhase, isA<SpoilerPhase$Hidden>());
    });

    testWidgets('a tap on a hidden spoiler reveals from the tap point',
        (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(_body([('a', _plain)], spoilers));
      final point = _spoilerCenter(tester, 'a');

      await tester.tapAt(point);

      expect(spoilers.isRevealed('a'), isTrue);
      expect(spoilers.revealOriginOf('a'), point);
    });

    testWidgets('a tap outside a spoiler reveals nothing', (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(_body([('a', _plain)], spoilers));

      await tester
          .tapAt(tester.getTopLeft(find.byKey(_key('a'))) + const Offset(2, 8));

      expect(spoilers.isRevealed('a'), isFalse);
    });

    testWidgets('a drag that starts on a spoiler does not reveal it',
        (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(_body([('a', _plain)], spoilers));
      final point = _spoilerCenter(tester, 'a');

      final gesture = await tester.startGesture(point);
      await gesture.moveBy(const Offset(60, 0));
      await gesture.up();

      expect(spoilers.isRevealed('a'), isFalse);
    });

    testWidgets('revealing document A leaves document B hidden',
        (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(
        _body([('a', _plain), ('b', _plain)], spoilers),
      );

      await tester.tapAt(_spoilerCenter(tester, 'a'));
      await tester.pumpAndSettle();

      expect(
          _painterOf(tester, 'a').spoilerPhase, isA<SpoilerPhase$Revealed>());
      expect(_painterOf(tester, 'b').spoilerPhase, isA<SpoilerPhase$Hidden>());
    });

    testWidgets('two widgets of one document reveal together', (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                for (final key in const ['one', 'two'])
                  SizedBox(
                    width: 300,
                    child: MarkdownWidget(
                      key: _key(key),
                      markdown: Markdown.fromString(_plain),
                      theme: _theme(),
                      documentId: 'shared',
                      spoilerController: spoilers,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      expect(
          _painterOf(tester, 'one').spoilerPhase, isA<SpoilerPhase$Hidden>());
      expect(
          _painterOf(tester, 'two').spoilerPhase, isA<SpoilerPhase$Hidden>());

      await tester.tapAt(_spoilerCenter(tester, 'one'));
      await tester.pump();

      expect(_painterOf(tester, 'one').spoilerPhase,
          isA<SpoilerPhase$Revealing>());
      expect(_painterOf(tester, 'two').spoilerPhase,
          isA<SpoilerPhase$Revealing>());
      await tester.pumpAndSettle();
      expect(
          _painterOf(tester, 'one').spoilerPhase, isA<SpoilerPhase$Revealed>());
      expect(
          _painterOf(tester, 'two').spoilerPhase, isA<SpoilerPhase$Revealed>());
    });

    testWidgets('state survives disposing and re-mounting the widget',
        (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(_body([('a', _plain)], spoilers));
      await tester.tapAt(_spoilerCenter(tester, 'a'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_body([('a', _plain)], spoilers));

      // Revealed on the first frame, no ripple: the document was seen already.
      expect(
          _painterOf(tester, 'a').spoilerPhase, isA<SpoilerPhase$Revealed>());
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a link inside a hidden spoiler reveals, not activates',
        (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      final taps = <String>[];
      await tester.pumpWidget(
        _body(
          [('a', _link)],
          spoilers,
          theme: _theme(onLinkTap: (title, url) => taps.add(url)),
        ),
      );
      // The spoiler is one patch; its middle is on the link text.
      final point = _spoilerCenter(tester, 'a');

      await tester.tapAt(point);
      await tester.pumpAndSettle();

      expect(spoilers.isRevealed('a'), isTrue);
      expect(taps, isEmpty);

      await tester.tapAt(point);

      expect(taps, ['https://x.example']);
    });

    testWidgets('hide brings the spoiler back', (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(_body([('a', _plain)], spoilers));
      await tester.tapAt(_spoilerCenter(tester, 'a'));
      await tester.pumpAndSettle();

      spoilers.hide('a');
      await tester.pump();

      expect(_painterOf(tester, 'a').spoilerPhase, isA<SpoilerPhase$Hidden>());
    });
  });

  group('MarkdownWidget spoiler reveal motion', () {
    testWidgets('the ripple runs for 300 ms from the tap point',
        (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(_body([('a', _plain)], spoilers));
      final local = _painterOf(tester, 'a').spoilerRects.first.center;

      await tester.tapAt(_spoilerCenter(tester, 'a'));
      await tester.pump(); // first frame of the ticker
      var phase = _painterOf(tester, 'a').spoilerPhase;
      expect(phase, isA<SpoilerPhase$Revealing>());
      expect((phase as SpoilerPhase$Revealing).origin, local);
      expect(phase.progress, 0);

      await tester.pump(const Duration(milliseconds: 150));
      phase = _painterOf(tester, 'a').spoilerPhase;
      expect(phase, isA<SpoilerPhase$Revealing>());
      expect(
          (phase as SpoilerPhase$Revealing).progress, inExclusiveRange(0, 1));

      await tester.pump(const Duration(milliseconds: 160));
      expect(
          _painterOf(tester, 'a').spoilerPhase, isA<SpoilerPhase$Revealed>());
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('motion off: one frame, no ripple', (tester) async {
      final spoilers = MarkdownSpoilerController(animate: false);
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(_body([('a', _plain)], spoilers));

      await tester.tapAt(_spoilerCenter(tester, 'a'));
      await tester.pump();

      expect(
          _painterOf(tester, 'a').spoilerPhase, isA<SpoilerPhase$Revealed>());
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('platform reduced motion: one frame, no ripple',
        (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(
        _body([('a', _plain)], spoilers, disableAnimations: true),
      );

      await tester.tapAt(_spoilerCenter(tester, 'a'));
      await tester.pump();

      expect(
          _painterOf(tester, 'a').spoilerPhase, isA<SpoilerPhase$Revealed>());
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('removing the widget mid-ripple leaves no ticker',
        (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      await tester.pumpWidget(_body([('a', _plain)], spoilers));
      await tester.tapAt(_spoilerCenter(tester, 'a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(const SizedBox());

      expect(tester.hasRunningAnimations, isFalse);
      spoilers.hide('a'); // must not call into a disposed render object
    });
  });
  group('MarkdownWidget spoiler reveal cost', () {
    testWidgets('a reveal lays out nothing and records two pictures at most',
        (tester) async {
      final spoilers = MarkdownSpoilerController();
      addTearDown(spoilers.dispose);
      final layouts = <int>[];
      final theme = MarkdownThemeData(
        textStyle: const TextStyle(fontSize: 14),
        builder: (block, theme) => block is MD$Paragraph
            ? _CountingParagraph(spans: block.spans, theme: theme, log: layouts)
            : null,
      );
      await tester.pumpWidget(_body([('a', _plain)], spoilers, theme: theme));
      final painter = _painterOf(tester, 'a');
      expect(layouts, [1]);
      expect(painter.debugPictureRecordings, 1);

      await tester.tapAt(_spoilerCenter(tester, 'a'));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(painter.debugCachedPictureCount, lessThanOrEqualTo(2));
      }

      expect(painter.spoilerPhase, isA<SpoilerPhase$Revealed>());
      expect(layouts, [1], reason: 'a reveal must not lay out again');
      expect(painter.debugPictureRecordings, 2);
      expect(painter.debugCachedPictureCount, 1);
    });
  });
}

class _CountingParagraph extends BlockPainter$Paragraph {
  _CountingParagraph({
    required super.spans,
    required super.theme,
    required this.log,
  });

  final List<int> log;

  @override
  Size layout(double width) {
    log.add(log.length + 1);
    return super.layout(width);
  }
}
