import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/span_builder.dart'
    show MarkdownSpoilerPainter;
import 'package:flutter_test/flutter_test.dart';

/// Tests run in Ahem: every glyph is a `fontSize` square, three quarters of
/// it above the baseline and a quarter below, so the font is exactly
/// `fontSize` tall and an emoji run at `emojiScale` x the font's height is a
/// square of `emojiScale * fontSize`.
const double _fontSize = 10;

/// Marks `[` to `]` as an emoji, the way a host's scanner marks the sequences
/// it knows; the brackets stay in the text, so the offsets are plain.
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

MarkdownThemeData _theme({
  MarkdownEmojiRuns? emojiRuns,
  double emojiScale = 1,
  double? height,
}) =>
    MarkdownThemeData(
      textStyle: TextStyle(fontSize: _fontSize, height: height),
      emojiRuns: emojiRuns,
      emojiScale: emojiScale,
    );

BlockPainter$Paragraph _paragraph(String source, MarkdownThemeData theme) {
  final block = Markdown.fromString(source).blocks.first as MD$Paragraph;
  final painter = BlockPainter$Paragraph(spans: block.spans, theme: theme)
    ..layout(400);
  addTearDown(painter.dispose);
  return painter;
}

List<TextBox> _boxes(BlockPainter$Paragraph block, int from, int to) =>
    block.painter.getBoxesForSelection(
      TextSelection(baseOffset: from, extentOffset: to),
    );

void main() {
  group('emoji runs', () {
    test('a run is drawn at emojiScale x the font height, text is not', () {
      final block = _paragraph(
        'ab [e] cd',
        _theme(emojiRuns: _bracketed, emojiScale: 1.5),
      );

      // Text: Ahem squares of the font size. The run: three Ahem squares at
      // 15 (the brackets and the letter).
      expect(_boxes(block, 0, 1).single.right, closeTo(10, 1e-6));
      expect(
        _boxes(block, 3, 6).fold<double>(0, (w, b) => w + b.right - b.left),
        closeTo(45, 1e-6),
      );
    });

    test('a scale of 1 leaves a run at the font height', () {
      final block = _paragraph('ab [e] cd', _theme(emojiRuns: _bracketed));

      expect(
        _boxes(block, 3, 6).fold<double>(0, (w, b) => w + b.right - b.left),
        closeTo(30, 1e-6),
      );
    });

    test('no scanner, no change: the paragraph is what it was', () {
      final plain = _paragraph('ab [e] cd', _theme(emojiScale: 1.5));

      expect(plain.painter.text!.toPlainText(), 'ab [e] cd');
      expect(
        _boxes(plain, 3, 6).fold<double>(0, (w, b) => w + b.right - b.left),
        closeTo(30, 1e-6),
      );
    });

    for (final height in [null, 1.5]) {
      test(
          'a line with a run is as tall as one without '
          '(height $height)', () {
        final without = _paragraph('ab cd ef', _theme(height: height));
        final withRun = _paragraph(
          'ab [e] ef',
          _theme(emojiRuns: _bracketed, emojiScale: 1.5, height: height),
        );

        expect(withRun.painter.height, closeTo(without.painter.height, 1e-6));
      });
    }

    test('the text is the same, offset for offset', () {
      final block = _paragraph(
        '**b[1]** [2]![x](emoji:1)',
        _theme(emojiRuns: _bracketed, emojiScale: 1.5),
      );

      expect(block.painter.text!.toPlainText(), 'b[1] [2]x');
    });

    test('a link keeps its recognizer on the run inside it', () {
      final taps = <String>[];
      final theme = MarkdownThemeData(
        textStyle: const TextStyle(fontSize: _fontSize),
        emojiRuns: (text) => [
          for (var i = 0; i < text.length; i++)
            if (text[i] == '\u2605') TextRange(start: i, end: i + 1),
        ],
        emojiScale: 1.5,
        onLinkTap: (title, url) => taps.add(url),
      );
      // A star stands for an emoji; the label's own markup is not the test's.
      final block = _paragraph('[a \u2605 b](https://x.test)', theme);

      final span = block.painter.text!.getSpanForPosition(
        const TextPosition(offset: 2),
      )! as TextSpan;
      (span.recognizer! as TapGestureRecognizer).onTap!();

      expect(taps, ['https://x.test']);
    });

    test('a spoiler with a run keeps its range and hides the run too', () {
      final block = _paragraph(
        'x ||a [e] b|| y',
        _theme(emojiRuns: _bracketed, emojiScale: 1.5),
      );

      expect(block.painter.hasSpoilers, isTrue);
      block.painter.setSpoilersRevealed(false);
      expect(block.painter.text!.toPlainText(), 'x a [e] b y');
      expect(block.painter.spoilerBoxes, isNotEmpty);
    });
  });
}
