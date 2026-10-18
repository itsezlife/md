import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

/// The TextSpan children built for one paragraph holding a link, a mention
/// and a hashtag, resolved against a theme whose links are underlined.
List<TextSpan> _paint(TextDirection direction) {
  final theme = MarkdownThemeData(
    textStyle: const TextStyle(fontSize: 14),
    textDirection: direction,
    linkColor: Colors.blue,
    linkStyle: const TextStyle(decoration: TextDecoration.underline),
    mentionColor: Colors.teal,
  );
  final md = Markdown.fromString(
    '[link](https://a.b) [@name](mention:1) [#tag](hashtag:tag)',
  );
  final paragraph = md.blocks.single as MD$Paragraph;
  final root = paragraphFromMarkdownSpans(spans: paragraph.spans, theme: theme);
  return root.children!.cast<TextSpan>();
}

void main() => group('Mention paint', () {
      for (final direction in TextDirection.values) {
        test('link underlined, mention and hashtag coloured ($direction)', () {
          final spans = _paint(direction);
          TextStyle of(String text) =>
              spans.firstWhere((s) => s.text == text).style!;

          expect(of('link').decoration, TextDecoration.underline);
          expect(of('link').color, Colors.blue);
          for (final text in ['@name', '#tag']) {
            expect(of(text).color, Colors.teal, reason: text);
            expect(of(text).decoration, isNull, reason: text);
          }
        });
      }
    });
