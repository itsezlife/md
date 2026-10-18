import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/painting.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/span_builder.dart';
import 'package:flutter_test/flutter_test.dart';

MD$Paragraph _paragraph(String source) =>
    Markdown.fromString(source).blocks.first as MD$Paragraph;

TextPainter _laidOut(TextSpan span, {double width = 120}) => TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);

void main() {
  group('paragraphFromMarkdownSpans(revealed:)', () {
    const source = 'before ||a hidden **bold** run|| after, and more text '
        'to make the paragraph wrap onto a second line';
    final theme = MarkdownThemeData(textStyle: const TextStyle(fontSize: 14));

    test('every glyph keeps its box when the spoiler is hidden', () {
      final spans = _paragraph(source).spans;
      final revealed = _laidOut(
        paragraphFromMarkdownSpans(spans: spans, theme: theme),
      );
      final hidden = _laidOut(
        paragraphFromMarkdownSpans(
          spans: spans,
          theme: theme,
          revealed: false,
        ),
      );

      expect(hidden.plainText, revealed.plainText);
      expect(hidden.size, revealed.size);
      for (var i = 0; i < revealed.plainText.length; i++) {
        final selection = TextSelection(baseOffset: i, extentOffset: i + 1);
        expect(
          hidden.getBoxesForSelection(selection),
          revealed.getBoxesForSelection(selection),
          reason: 'glyph $i moved',
        );
      }
    });

    test('hidden spoiler runs are transparent, other runs are untouched', () {
      final spans = _paragraph(source).spans;
      final hidden = paragraphFromMarkdownSpans(
        spans: spans,
        theme: theme,
        revealed: false,
      );
      final revealed = paragraphFromMarkdownSpans(spans: spans, theme: theme);

      for (var i = 0; i < spans.length; i++) {
        final hiddenChild = hidden.children![i] as TextSpan;
        final revealedChild = revealed.children![i] as TextSpan;
        if (spans[i].style.contains(MD$Style.spoiler)) {
          expect(hiddenChild.style?.color, const Color(0x00000000));
          expect(hiddenChild.text, revealedChild.text);
        } else {
          expect(hiddenChild.style, revealedChild.style);
        }
      }
    });

    test('revealed is the default and equals today\'s output', () {
      final spans = _paragraph(source).spans;
      final byDefault = paragraphFromMarkdownSpans(spans: spans, theme: theme);
      final explicit = paragraphFromMarkdownSpans(
        spans: spans,
        theme: theme,
        revealed: true,
      );

      expect(byDefault.toPlainText(), explicit.toPlainText());
      expect(
        [for (final c in byDefault.children!) (c as TextSpan).style],
        [for (final c in explicit.children!) (c as TextSpan).style],
      );
    });

    test('a spoiler run keeps its link recognizer when hidden', () {
      final spans = _paragraph('||see [here](https://x.example) now||').spans;
      final hidden = paragraphFromMarkdownSpans(
        spans: spans,
        theme: MarkdownThemeData(
          textStyle: const TextStyle(fontSize: 14),
          onLinkTap: (_, __) {},
        ),
        revealed: false,
      );

      final link = hidden.children!
          .cast<TextSpan>()
          .singleWhere((s) => s.text == 'here');
      expect(link.recognizer, isNotNull);
      expect(link.style?.color, const Color(0x00000000));
    });

    test('a paragraph without a spoiler is a plain TextSpan', () {
      final span = paragraphFromMarkdownSpans(
        spans: _paragraph('no spoilers **here**').spans,
        theme: theme,
        revealed: false,
      );

      expect(span.runtimeType, TextSpan);
    });
  });

  group('TextPainter spoiler extension', () {
    final theme = MarkdownThemeData(textStyle: const TextStyle(fontSize: 14));

    TextPainter painterFor(String source, {double width = 400}) => _laidOut(
          paragraphFromMarkdownSpans(
            spans: _paragraph(source).spans,
            theme: theme,
          ),
          width: width,
        );

    test('swapping hidden and revealed needs no layout', () {
      final painter = painterFor('x ||secret|| y');
      final size = painter.size;
      final boxes = painter.getBoxesForSelection(
        const TextSelection(baseOffset: 2, extentOffset: 8),
      );

      painter.setSpoilersRevealed(false);
      expect(painter.size, size); // `size` asserts the layout is still valid
      painter.setSpoilersRevealed(true);

      expect(painter.size, size);
      expect(
        painter.getBoxesForSelection(
          const TextSelection(baseOffset: 2, extentOffset: 8),
        ),
        boxes,
      );
    });

    test('spoilerBoxes cover exactly the spoiler glyphs', () {
      final painter = painterFor('x ||secret|| y');

      expect(painter.hasSpoilers, isTrue);
      expect(
        painter.spoilerBoxes,
        painter
            .getBoxesForSelection(
              const TextSelection(baseOffset: 2, extentOffset: 8),
              boxHeightStyle: BoxHeightStyle.max,
            )
            .map((b) => b.toRect())
            .toList(),
      );
    });

    test('the style runs of one spoiler join into one box per line', () {
      final painter = painterFor('||a **b** c||');

      expect(painter.hasSpoilers, isTrue);
      expect(painter.spoilerBoxes.length, 1);
    });

    test('a plain painter has no spoilers', () {
      final painter = painterFor('nothing hidden');

      expect(painter.hasSpoilers, isFalse);
      expect(painter.spoilerBoxes, isEmpty);
      painter.setSpoilersRevealed(false); // no-op, must not throw
    });
  });
}
