/// The escapes of a link label and a link destination read back as the
/// characters they stand for.
///
/// A chat host writes a label with the same backslash escapes it writes
/// anywhere else in a body (`[a\*b](u)`), so a parser that kept the
/// backslashes painted them, and a hashtag read `\#tag`. The label of a link,
/// a mention-class span and an image is unescaped like paragraph text; the
/// destination is unescaped the way CommonMark reads it.
library;

import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

import 'link_label_rows.dart';

List<MD$Span> _spans(String markdown) =>
    (markdownDecoder.convert(markdown).blocks.single as MD$Paragraph).spans;

MD$Span _only(String markdown) =>
    _spans(markdown).singleWhere((span) => span.extra != null);

String _joined(List<MD$Span> spans) => spans.map((s) => s.text).join();

void main() {
  group('Link label escapes', () {
    test('an escaped marker reads as the character', () {
      final span = _only(r'[a\*b](u)');
      expect(span.text, 'a*b');
      expect(span.extra?['href'], 'u');
    });

    test('a hashtag label has no backslash', () {
      final span = _only(r'[\#tag](hashtag:tag)');
      expect(span.text, '#tag');
      expect(span.style.contains(MD$Style.mention), isTrue);
      expect(span.extra, containsPair('name', 'tag'));
    });

    test('a mention label has no backslash, in its name either', () {
      final span = _only(r'[\_x\_](mention:1)');
      expect(span.text, '_x_');
      expect(span.extra, containsPair('id', '1'));
      expect(span.extra, containsPair('name', '_x_'));
    });

    test('an escaped bracket does not end the label', () {
      expect(_only(r'[a\]b](u)').text, 'a]b');
      expect(_only(r'[a\[b](u)').text, 'a[b');
      expect(_only(r'[\[x\]](u)').text, '[x]');
    });

    test('an image label is unescaped too', () {
      final span = _only(r'![a\]b](document:1)');
      expect(span.style.contains(MD$Style.image), isTrue);
      expect(span.text, 'a]b');
    });

    test('an escaped backslash is one backslash and ends no escape', () {
      expect(_only(r'[a\\](u)').text, r'a\');
      expect(_only(r'[a\\*b](u)').text, r'a\*b');
      expect(_only(r'[\\\*](u)').text, r'\*');
    });

    test('a backslash before a character that is not escapable stays', () {
      expect(_only(r'[a\b](u)').text, r'a\b');
      expect(_only(r'[C:\dir](u)').text, r'C:\dir');
    });

    test('a backslash before a surrogate pair or a ZWJ sequence stays', () {
      const emoji = '\u{1F468}\u200D\u{1F469}';
      expect(_only('[a\\$emoji](u)').text, 'a\\$emoji');
      expect(_only('[\\$emoji\\*](u)').text, '\\$emoji*');
    });

    test('right-to-left letters and marks around an escape are kept', () {
      expect(_only('[\u05D0\\_\u05D1\u200F](u)').text, '\u05D0_\u05D1\u200F');
    });

    test('a label with no escape is the label', () {
      expect(_only('[plain label](u)').text, 'plain label');
    });

    test('emphasis written around a label still merges with the link', () {
      final spans = _spans(r'**[a\*b](u)** c');
      expect(spans.first.text, 'a*b');
      expect(spans.first.style.contains(MD$Style.bold), isTrue);
      expect(spans.first.style.contains(MD$Style.link), isTrue);
      expect(_joined(spans), 'a*b c');
    });

    test('a list item, a quote and a table cell read a label alike', () {
      final blocks = markdownDecoder
          .convert('- [\\#a](hashtag:a)\n\n> [\\#b](hashtag:b)\n\n'
              '| h |\n|---|\n| [\\#c](hashtag:c) |')
          .blocks;
      final list = blocks.whereType<MD$List>().single;
      final quote = blocks.whereType<MD$Quote>().single;
      final table = blocks.whereType<MD$Table>().single;
      expect(_joined(list.items.single.spans), '#a');
      expect(_joined(quote.spans), '#b');
      expect(_joined(table.rows.single.cells.single), '#c');
    });

    test('the span still covers the whole source of the link', () {
      const source = r'[a\*b](u)';
      final span = _only(source);
      expect(span.start, 0);
      expect(span.end, source.length);
    });
  });

  group('Link label escapes, as a writer writes them', () {
    for (final (markdown, before, label, after, kind) in labelRows) {
      test(markdown.replaceAll('\n', r'\n'), () {
        final spans = _spans(markdown);
        expect(_joined(spans), '$before$label$after', reason: markdown);
        final span = spans.singleWhere((s) => s.extra != null);
        expect(span.text, label, reason: markdown);
        switch (kind) {
          case 'link':
            expect(span.style.contains(MD$Style.link), isTrue);
            expect(span.extra, containsPair('href', 'https://a.b'));
          case 'mention':
            expect(span.style.contains(MD$Style.mention), isTrue);
            expect(span.extra, containsPair('id', '7'));
            expect(span.extra, containsPair('name', label));
          case 'hashtag':
            expect(span.style.contains(MD$Style.mention), isTrue);
            expect(span.extra, containsPair('scheme', 'hashtag'));
            expect(span.extra, containsPair('name', 't'));
          case 'username':
            expect(span.style.contains(MD$Style.mention), isTrue);
            expect(span.extra, containsPair('scheme', 'username'));
            expect(span.extra, containsPair('name', 'u'));
          case 'image':
            expect(span.style.contains(MD$Style.image), isTrue);
            expect(span.extra, containsPair('src', 'document:5'));
          default:
            fail('Unknown kind $kind');
        }
      });
    }

    test('the table covers every kind and every escaped character', () {
      expect({
        for (final row in labelRows) row.$5
      }, {
        'link',
        'mention',
        'hashtag',
        'username',
        'image',
      });
      for (final unit in r'\*`[]_~|'.split('')) {
        expect(
          labelRows.any((row) => row.$3.contains(unit)),
          isTrue,
          reason: 'no label holds $unit',
        );
      }
    });
  });

  group('Link destination escapes', () {
    test('an escaped parenthesis is a parenthesis', () {
      expect(
          _only(r'[t](https://x/a_\(b\))').extra?['href'], 'https://x/a_(b)');
      expect(_only(r'[t](a\)b)').extra?['url'], 'a)b');
    });

    test('a balanced pair of parentheses is part of the destination', () {
      expect(_only('[t](https://x/a_(b))').extra?['href'], 'https://x/a_(b)');
    });

    test('an escaped backslash is one backslash', () {
      expect(_only(r'[t](a\\b)').extra?['href'], r'a\b');
    });

    test('a backslash before a letter stays', () {
      expect(_only(r'[t](C:\dir)').extra?['href'], r'C:\dir');
    });

    test('an angle-bracketed destination takes back its escapes', () {
      expect(
          _only(r'[t](<https://x/a b\>c>)').extra?['href'], 'https://x/a b>c');
      expect(_only(r'[t](<https://x/a\>b>)').extra?['href'], 'https://x/a>b');
      expect(_only(r'[t](<a b\\c>)').extra?['href'], r'a b\c');
      expect(_only(r'[t](<a\<b c>)').extra?['href'], 'a<b c');
    });

    test('a title after an angle-bracketed destination is still read', () {
      final span = _only(r'[t](<a\>b> "title")');
      expect(span.extra?['href'], 'a>b');
      expect(span.extra?['alt'], 'title');
    });

    test('a mention id is unescaped like any destination', () {
      final span = _only(r'[@a](mention:a\_b)');
      expect(span.extra, containsPair('id', 'a_b'));
    });

    test('an image source is unescaped', () {
      final span = _only(r'![x](<external:a b\>c>)');
      expect(span.extra?['src'], 'external:a b>c');
    });
  });
}
