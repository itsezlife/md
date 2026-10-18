import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/markdown_painter.dart';
import 'package:flutter_md/src/render/spoiler_phase.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = 'before ||secret words|| after\n\nplain second paragraph';

MarkdownPainter _painter(
  String source, {
  double width = 300,
  MarkdownThemeData? theme,
}) =>
    _painterFor(Markdown.fromString(source), width: width, theme: theme);

MarkdownPainter _painterFor(
  Markdown markdown, {
  double width = 300,
  MarkdownThemeData? theme,
}) {
  final painter = MarkdownPainter(
    markdown: markdown,
    theme: theme ?? MarkdownThemeData(textStyle: const TextStyle(fontSize: 14)),
  )..layout(maxWidth: width);
  addTearDown(painter.dispose);
  return painter;
}

void _paint(MarkdownPainter painter) {
  final recorder = PictureRecorder();
  painter.paint(Canvas(recorder), painter.size);
  recorder.endRecording().dispose();
}

void main() {
  group('MarkdownPainter spoiler pictures', () {
    test('a painter with no phase shows spoilers as ordinary text', () {
      final painter = _painter(_source);

      expect(painter.spoilerPhase, isA<SpoilerPhase$Revealed>());
      expect(painter.hiddenSpoilerAt(const Offset(60, 8)), isFalse);
    });

    test('hidden records one picture and repaints record none', () {
      final painter = _painter(_source)
        ..setSpoilerPhase(const SpoilerPhase$Hidden());

      _paint(painter);
      _paint(painter);
      _paint(painter);

      expect(painter.debugPictureRecordings, 1);
      expect(painter.debugCachedPictureCount, 1);
    });

    test('a reveal holds hidden and revealed, never a third picture', () {
      final painter = _painter(_source)
        ..setSpoilerPhase(const SpoilerPhase$Hidden());
      _paint(painter);

      for (final progress in [0.1, 0.4, 0.8]) {
        painter.setSpoilerPhase(
          SpoilerPhase$Revealing(progress: progress, origin: Offset.zero),
        );
        _paint(painter);
        expect(painter.debugCachedPictureCount, 2);
      }
      // hidden once, revealed once; frames of the ripple record nothing.
      expect(painter.debugPictureRecordings, 2);

      painter.setSpoilerPhase(const SpoilerPhase$Revealed());
      _paint(painter);
      _paint(painter);

      expect(painter.debugCachedPictureCount, 1);
      expect(painter.debugPictureRecordings, 2);
    });

    test('a document with no spoiler records one picture in any phase', () {
      final painter = _painter('just text, nothing hidden')
        ..setSpoilerPhase(const SpoilerPhase$Hidden());

      _paint(painter);
      painter.setSpoilerPhase(
        const SpoilerPhase$Revealing(progress: 0.5, origin: Offset.zero),
      );
      _paint(painter);

      expect(painter.debugPictureRecordings, 1);
      expect(painter.debugCachedPictureCount, 1);
      expect(painter.hasSpoilers, isFalse);
    });

    test('a new model drops both pictures', () {
      final painter = _painter(_source)
        ..setSpoilerPhase(
          const SpoilerPhase$Revealing(progress: 0.5, origin: Offset.zero),
        );
      _paint(painter);
      expect(painter.debugCachedPictureCount, 2);

      painter.update(
        markdown: Markdown.fromString('||new||'),
        theme: MarkdownThemeData(textStyle: const TextStyle(fontSize: 14)),
      );

      expect(painter.debugCachedPictureCount, 0);
    });

    test('setSpoilerPhase reports whether the phase changed', () {
      final painter = _painter(_source);

      expect(painter.setSpoilerPhase(const SpoilerPhase$Revealed()), isFalse);
      expect(painter.setSpoilerPhase(const SpoilerPhase$Hidden()), isTrue);
      expect(painter.setSpoilerPhase(const SpoilerPhase$Hidden()), isFalse);
    });
  });

  group('MarkdownPainter spoiler geometry', () {
    test('only a hidden spoiler is hit, and only inside its rect', () {
      final painter = _painter(_source);
      final rect = painter.spoilerRects.single;

      painter.setSpoilerPhase(const SpoilerPhase$Hidden());
      expect(painter.hiddenSpoilerAt(rect.center), isTrue);
      expect(painter.hiddenSpoilerAt(Offset(rect.right + 4, rect.center.dy)),
          isFalse);
      expect(painter.hiddenSpoilerAt(Offset(2, rect.center.dy)), isFalse);

      painter.setSpoilerPhase(const SpoilerPhase$Revealed());
      expect(painter.hiddenSpoilerAt(rect.center), isFalse);
    });

    test('spoiler rects do not move when the phase changes', () {
      final painter = _painter(_source);
      final before = painter.spoilerRects;

      painter.setSpoilerPhase(const SpoilerPhase$Hidden());
      _paint(painter);
      painter.setSpoilerPhase(const SpoilerPhase$Revealed());
      _paint(painter);

      expect(painter.spoilerRects, before);
    });

    test('an embed under a spoiler is transparent until the reveal', () {
      final painter = _painter(_source);
      final inside = painter.spoilerRects.single.deflate(2);
      const outside = Rect.fromLTWH(0, 40, 10, 10);

      painter.setSpoilerPhase(const SpoilerPhase$Hidden());
      expect(painter.embedOpacityAt(inside), 0);
      expect(painter.embedOpacityAt(outside), 1);

      painter.setSpoilerPhase(
        const SpoilerPhase$Revealing(progress: 0.25, origin: Offset.zero),
      );
      expect(painter.embedOpacityAt(inside), 0.25);
      expect(painter.embedOpacityAt(outside), 1);

      painter.setSpoilerPhase(const SpoilerPhase$Revealed());
      expect(painter.embedOpacityAt(inside), 1);
    });
  });

  group('a table with a spoiler', () {
    // The parser does not read `||` inside a table cell (the pipes split it),
    // so the model is built by hand.
    const spoiler = MD$Span(
      start: 0,
      end: 12,
      text: 'hidden words',
      style: MD$Style.spoiler,
    );
    const plain = MD$Span(start: 0, end: 15, text: 'plain cell text');
    const row = MD$TableRow(text: '', cells: [
      [spoiler],
      [plain],
    ]);
    const tableMarkdown = Markdown(
      markdown: '',
      blocks: [
        MD$Table(text: '', header: row, rows: [row]),
      ],
    );

    MarkdownThemeData scrollable() => MarkdownThemeData(
          textStyle: const TextStyle(fontSize: 14),
          builder: (block, theme) => block is MD$Table
              ? BlockPainter$ScrollableTable(
                  header: block.header,
                  rows: block.rows,
                  alignments: block.alignments,
                  theme: theme,
                )
              : null,
        );

    test('paints live in every phase and keeps two pictures at most', () {
      // Narrower than the columns so the table pans.
      final painter =
          _painterFor(tableMarkdown, width: 90, theme: scrollable());
      expect(painter.hasSpoilers, isTrue);
      expect(painter.spoilerRects, isNotEmpty);

      painter.setSpoilerPhase(const SpoilerPhase$Hidden());
      _paint(painter);
      painter.setSpoilerPhase(
        const SpoilerPhase$Revealing(progress: 0.5, origin: Offset.zero),
      );
      _paint(painter);
      painter.setSpoilerPhase(const SpoilerPhase$Revealed());
      _paint(painter);

      // The pannable table paints outside the pictures; they hold nothing of
      // it, and no phase re-records them.
      expect(painter.debugPictureRecordings, lessThanOrEqualTo(3));
    });

    test('the default table finds its spoiler too', () {
      final painter = _painterFor(tableMarkdown);

      expect(painter.hasSpoilers, isTrue);
      painter.setSpoilerPhase(const SpoilerPhase$Hidden());
      _paint(painter);
      expect(painter.debugPictureRecordings, 1);
      expect(
          painter.hiddenSpoilerAt(painter.spoilerRects.first.center), isTrue);
    });

    test('its spoiler rects follow the pan and stay in the viewport', () {
      final painter =
          _painterFor(tableMarkdown, width: 90, theme: scrollable());
      final block = painter.pannablePainterAt(0)!;
      final before = painter.spoilerRects;

      block.applyScrollDelta(20);

      for (final rect in painter.spoilerRects) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(block.size.width));
      }
      expect(painter.spoilerRects, isNot(before));
    });
  });

  group('spoiler blocks keep their layout', () {
    final theme = MarkdownThemeData(textStyle: const TextStyle(fontSize: 14));

    test('paragraph: every glyph box is the same hidden and revealed', () {
      final block = BlockPainter$Paragraph(
        spans: (Markdown.fromString('a ||b c d e f|| g h i j k l m n o p')
                .blocks
                .first as MD$Paragraph)
            .spans,
        theme: theme,
      );
      addTearDown(block.dispose);
      final size = block.layout(80);
      final revealed = [
        for (var i = 0; i < block.renderedText.length; i++)
          block.boxesForRange(i, i + 1),
      ];

      block.spoilersRevealed = false;

      expect(block.size, size);
      expect(block.hasSpoilers, isTrue);
      for (var i = 0; i < block.renderedText.length; i++) {
        expect(block.boxesForRange(i, i + 1), revealed[i], reason: 'glyph $i');
      }
    });

    test('a spoiler in a list item, quote and alert is found', () {
      for (final source in const [
        '- one ||two||',
        '> one ||two||',
        '> [!NOTE]\n> one ||two||',
        '> ```\n> code\n> ```\n>\n> one ||two||',
      ]) {
        final painter = _painter(source);
        expect(painter.hasSpoilers, isTrue, reason: source);
        expect(painter.spoilerRects, isNotEmpty, reason: source);
        final before = painter.spoilerRects;
        painter.setSpoilerPhase(const SpoilerPhase$Hidden());
        _paint(painter);
        expect(painter.spoilerRects, before, reason: source);
      }
    });
  });
}
