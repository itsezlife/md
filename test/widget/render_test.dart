import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a [MarkdownWidget] for [source] inside a sized, themed scaffold and
/// returns the tester for further inspection.
Future<void> _pumpMarkdown(
  WidgetTester tester,
  String source, {
  MarkdownThemeData? theme,
  void Function(String title, String url)? onLinkTap,
  void Function(String scheme, String? id, String name)? onMentionTap,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MarkdownTheme(
          data: theme ??
              MarkdownThemeData(
                textStyle: const TextStyle(fontSize: 14),
                onLinkTap: onLinkTap,
                onMentionTap: onMentionTap,
                textDirection: textDirection,
              ),
          child: Center(
            child: SizedBox(
              width: 400,
              child: MarkdownWidget(markdown: Markdown.fromString(source)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Size _mdSize(WidgetTester tester) =>
    tester.renderObject<RenderBox>(find.byType(MarkdownWidget)).size;

void main() {
  group('MarkdownWidget rendering', () {
    testWidgets('renders a rich document without exceptions', (tester) async {
      const source = '# Heading\n\n'
          'A paragraph with **bold**, _italic_, `code`, ~~strike~~, '
          '==mark==, ||spoiler|| and a [link](https://example.com).\n\n'
          '> A blockquote\n\n'
          '```dart\nvoid main() {}\n```\n\n'
          '- one\n- two\n  - nested\n\n'
          '1. first\n2. second\n\n'
          '| A | B |\n|:--|--:|\n| 1 | 2 |\n\n'
          '---\n';
      await _pumpMarkdown(tester, source);
      expect(tester.takeException(), isNull);
      expect(_mdSize(tester).height, greaterThan(0));
    });

    testWidgets('empty markdown produces zero size', (tester) async {
      await _pumpMarkdown(tester, '');
      expect(tester.takeException(), isNull);
      // Width is constrained by the parent SizedBox; the content height is 0.
      expect(_mdSize(tester).height, 0);
    });

    group('GitHub alerts render', () {
      for (final type in ['NOTE', 'TIP', 'IMPORTANT', 'WARNING', 'CAUTION']) {
        testWidgets('$type alert', (tester) async {
          await _pumpMarkdown(
            tester,
            '> [!$type]\n> Body of the $type alert with **bold**.',
          );
          expect(tester.takeException(), isNull);
          expect(_mdSize(tester).height, greaterThan(0));
        });
      }

      testWidgets('marker-only alert still lays out', (tester) async {
        await _pumpMarkdown(tester, '> [!WARNING]');
        expect(tester.takeException(), isNull);
        expect(_mdSize(tester).height, greaterThan(0));
      });
    });

    testWidgets('quote with nested fenced code renders', (tester) async {
      await _pumpMarkdown(
        tester,
        '> Before the fence.\n'
        '>\n'
        '> ```bash\n'
        '> echo ok\n'
        '> ```\n'
        '>\n'
        '> After the fence.',
        theme: MarkdownThemeData(
          textStyle: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14),
          quoteStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(_mdSize(tester).height, greaterThan(0));
    });

    test('nested quote prose children inherit quoteStyle', () {
      const quoteColor = Color(0xFF9E9E9E);
      const bodyColor = Color(0xFFFFFFFF);
      final theme = MarkdownThemeData(
        textStyle: const TextStyle(color: bodyColor, fontSize: 14),
        quoteStyle: const TextStyle(color: quoteColor, fontSize: 14),
      );
      final md = Markdown.fromString(
        '> prose line\n'
        '> ```\n'
        '> code\n'
        '> ```',
      );
      final quote = md.blocks.single as MD$Quote;
      final para = quote.blocks.whereType<MD$Paragraph>().single;
      final code = quote.blocks.whereType<MD$Code>().single;

      final proseTheme = BlockPainter$Quote.inheritFrom(theme, para);
      final codeTheme = BlockPainter$Quote.inheritFrom(theme, code);
      expect(proseTheme.textStyle.color, quoteColor);
      expect(codeTheme.textStyle.color, bodyColor);

      final painter = BlockPainter$Paragraph(
        spans: para.spans,
        theme: proseTheme,
      )..layout(400);
      final root = painter.painter.text! as TextSpan;
      expect(root.style?.color, quoteColor);
    });

    testWidgets('aligned tables render without exceptions', (tester) async {
      await _pumpMarkdown(
        tester,
        '| Left | Center | Right |\n'
        '| :--- | :----: | ----: |\n'
        '| a    | b      | c     |\n'
        '| longer text | x | y |',
      );
      expect(tester.takeException(), isNull);
      expect(_mdSize(tester).height, greaterThan(0));
    });

    testWidgets('inline math renders', (tester) async {
      await _pumpMarkdown(tester, r'The angle $\alpha \leq \beta$ holds.');
      expect(tester.takeException(), isNull);
      expect(_mdSize(tester).height, greaterThan(0));
    });

    testWidgets('thematic break variants render', (tester) async {
      await _pumpMarkdown(tester, 'a\n\n---\n\nb\n\n***\n\nc\n\n___\n\nd');
      expect(tester.takeException(), isNull);
      expect(_mdSize(tester).height, greaterThan(0));
    });

    testWidgets('tapping a link invokes onLinkTap', (tester) async {
      final tapped = <String>[];
      await _pumpMarkdown(
        tester,
        '[click me](https://example.com)',
        onLinkTap: (title, url) => tapped.add(url),
      );
      // The whole first line is the link; tap near its start.
      final topLeft = tester.getTopLeft(find.byType(MarkdownWidget));
      await tester.tapAt(topLeft + const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(tapped, ['https://example.com']);
    });

    group('mention-class taps', () {
      // The spans of the line, in order, each a fixed-width run in the test
      // font; the tap lands in the middle of the run under test.
      Future<void> tapRun(WidgetTester tester, double dx) async {
        final topLeft = tester.getTopLeft(find.byType(MarkdownWidget));
        await tester.tapAt(topLeft + Offset(dx, 8));
        await tester.pumpAndSettle();
      }

      for (final (source, scheme, id, name) in [
        ('[@abcdefgh](mention:42)', 'mention', '42', '@abcdefgh'),
        ('[@abcdefgh](username:abc)', 'username', null, 'abc'),
        ('[#abcdefgh](hashtag:tag)', 'hashtag', null, 'tag'),
      ]) {
        testWidgets('$scheme fires onMentionTap, never onLinkTap',
            (tester) async {
          final mentions = <(String, String?, String)>[];
          final links = <String>[];
          await _pumpMarkdown(
            tester,
            source,
            onLinkTap: (title, url) => links.add(url),
            onMentionTap: (s, i, n) => mentions.add((s, i, n)),
          );
          await tapRun(tester, 8);
          expect(mentions, [(scheme, id, name)]);
          expect(links, isEmpty);
        });
      }

      testWidgets('an RTL paragraph fires onMentionTap too', (tester) async {
        final mentions = <(String, String?, String)>[];
        await _pumpMarkdown(
          tester,
          '[@abcdefgh](mention:42)',
          textDirection: TextDirection.rtl,
          onMentionTap: (s, i, n) => mentions.add((s, i, n)),
        );
        final size = _mdSize(tester);
        final topLeft = tester.getTopLeft(find.byType(MarkdownWidget));
        await tester.tapAt(topLeft + Offset(size.width - 8, 8));
        await tester.pumpAndSettle();
        expect(mentions, [('mention', '42', '@abcdefgh')]);
      });

      testWidgets('a plain link still fires onLinkTap only', (tester) async {
        final mentions = <String>[];
        final links = <String>[];
        await _pumpMarkdown(
          tester,
          '[click me](https://example.com)',
          onLinkTap: (title, url) => links.add(url),
          onMentionTap: (s, i, n) => mentions.add(n),
        );
        await tapRun(tester, 8);
        expect(links, ['https://example.com']);
        expect(mentions, isEmpty);
      });

      testWidgets('a mention with no onMentionTap taps nothing',
          (tester) async {
        final links = <String>[];
        await _pumpMarkdown(
          tester,
          '[@abcdefgh](mention:42)',
          onLinkTap: (title, url) => links.add(url),
        );
        await tapRun(tester, 8);
        expect(links, isEmpty);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('updating markdown relayouts', (tester) async {
      await _pumpMarkdown(tester, 'short');
      final firstHeight = _mdSize(tester).height;
      await _pumpMarkdown(tester, 'line one\n\nline two\n\nline three');
      expect(tester.takeException(), isNull);
      expect(_mdSize(tester).height, greaterThan(firstHeight));
    });

    testWidgets('custom link style is applied via theme', (tester) async {
      await _pumpMarkdown(
        tester,
        '[styled](https://example.com)',
        theme: MarkdownThemeData(
          textStyle: const TextStyle(fontSize: 14),
          linkStyle: const TextStyle(
              color: Colors.red, decoration: TextDecoration.underline),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(_mdSize(tester).height, greaterThan(0));
    });
  });
}
