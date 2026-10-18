/// The dialect a host writes: how every spelling a markdown writer for a chat
/// body emits parses.
///
/// A chat host stores a message as markdown it writes from its own rich text,
/// and this package renders what that string says. The two sides cannot share
/// code, so they share a grammar, and this file is where the package pins its
/// half: each fixture is a string in the writer's dialect with the blocks and
/// spans the parser must read from it. A spelling the parser stops reading
/// (a scheme dropped, an escape no longer taken back) fails here, not on a
/// screen.
///
/// The fixtures are strings, not a writer's output: the writer lives in
/// another repository and this package depends on nothing of it. The writer's
/// own tests cover the other direction (rich text to string and back).
///
/// A spelling the parser reads differently from what the writer means is not
/// hidden: it sits in the "known gaps" group, which pins today's reading, so a
/// parser fix fails those cases and moves them into the table above.
library;

import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

// --- The shape of a parse, as lines ---

/// A text as a quoted literal, line breaks written out.
String _quote(String text) => '"${text.replaceAll('\n', r'\n')}"';

/// One span: `"text"`, then `<styles>` and `{extra}` when it has any.
///
/// Styles are joined with `+` in name order. Extra keeps what a reader of the
/// span acts on; `type` (the style says it) and `url` (a copy of `href` or
/// `src`) are left out.
String _span(MD$Span span) {
  final styles = span.style.styles.toList()..sort();
  final extra = <String>[
    for (final key in (span.extra?.keys.toList() ?? <String>[])..sort())
      if (key != 'type' && key != 'url') '$key: ${span.extra![key]}',
  ];
  return '${_quote(span.text)}'
      '${styles.isEmpty ? '' : '<${styles.join('+')}>'}'
      '${extra.isEmpty ? '' : '{${extra.join(', ')}}'}';
}

String _spans(List<MD$Span> spans) => spans.map(_span).join(' | ');

/// The lines of [blocks]: one per paragraph, quote, code block and gap, a
/// header and one line per item for a list. Nesting is indented two spaces.
List<String> _lines(List<MD$Block> blocks, [String indent = '']) => [
      for (final block in blocks) ..._blockLines(block, indent),
    ];

List<String> _blockLines(MD$Block block, String indent) => switch (block) {
      MD$Paragraph(:final spans) => ['${indent}p: ${_spans(spans)}'],
      MD$Quote(:final blocks, :final spans) when blocks.isEmpty => [
          '${indent}q: ${_spans(spans)}',
        ],
      MD$Quote(:final blocks) => [
          '${indent}q:',
          ..._lines(blocks, '$indent  '),
        ],
      MD$Code(:final language, :final text) => [
          '${indent}code${_language(language)}: ${_quote(text)}',
        ],
      MD$List(:final items) => [
          '${indent}list:',
          ..._items(items, '$indent  '),
        ],
      MD$Spacer() => ['${indent}gap'],
      _ => ['$indent${block.type}: ${_quote(block.text)}'],
    };

String _language(String? language) =>
    language == null || language.isEmpty ? '' : '($language)';

List<String> _items(List<MD$ListItem> items, String indent) => [
      for (final item in items) ...[
        '$indent${item.marker} ${_spans(item.spans)}',
        ..._items(item.children, '$indent  '),
      ],
    ];

/// What the parser reads from [markdown], as lines.
List<String> _read(String markdown) =>
    _lines(markdownDecoder.convert(markdown).blocks);

/// Expects each of [cases] (`markdown -> lines`) to read as written.
void _conform(Map<String, List<String>> cases) {
  for (final MapEntry(key: markdown, value: lines) in cases.entries) {
    test(markdown.replaceAll('\n', r'\n'), () {
      expect(_read(markdown), lines, reason: markdown);
    });
  }
}

const _thumbsUp = '\u{1F44D}';
const _family = '\u{1F468}‍\u{1F469}‍\u{1F467}';

void main() => group('Dialect conformance', () {
      group('styles', () {
        _conform({
          'a **bold** b': ['p: "a " | "bold"<bold> | " b"'],
          'an *italic*': ['p: "an " | "italic"<italic>'],
          'an __underline__ x': [
            'p: "an " | "underline"<underline> | " x"',
          ],
          'x ~~gone~~': ['p: "x " | "gone"<strikethrough>'],
          'a ||hidden|| b': ['p: "a " | "hidden"<spoiler> | " b"'],
          'c `code` d': ['p: "c " | "code"<monospace> | " d"'],
        });

        group('nest and overlap as toggles', () {
          _conform({
            // The writer's last-opened-first-closed order for equal ranges.
            '***x***': ['p: "x"<bold+italic>'],
            // A style inside a longer one.
            '**a*bc*d**': [
              'p: "a"<bold> | "bc"<bold+italic> | "d"<bold>',
            ],
            // Partial overlap is written as plain toggles, no splitting.
            '**ab*cd**ef*': [
              'p: "ab"<bold> | "cd"<bold+italic> | "ef"<italic>',
            ],
            // Code sits inside other styles and holds no markup of its own.
            '**a`b`c**': [
              'p: "a"<bold> | "b"<bold+monospace> | "c"<bold>',
            ],
            '`a*b_c`': ['p: "a*b_c"<monospace>'],
            // A space at the edge of code is part of the code.
            '` a`': ['p: " a"<monospace>'],
          });
        });

        group('emoji travel as their characters', () {
          _conform({
            'hi $_thumbsUp!': ['p: "hi $_thumbsUp!"'],
            _family: ['p: "$_family"'],
            '☂️ umbrella': ['p: "☂️ umbrella"'],
            '**$_thumbsUp** x': ['p: "$_thumbsUp"<bold> | " x"'],
          });
        });
      });

      group('links', () {
        _conform({
          '[go](https://a.b) there': [
            'p: "go"<link>{href: https://a.b} | " there"',
          ],
          '[mail](mailto:a@b.c)': ['p: "mail"<link>{href: mailto:a@b.c}'],
          // A destination with whitespace is written between angle brackets.
          '[t](<https://x/a b>)': ['p: "t"<link>{href: https://x/a b}'],
          // A link cannot hold markers, so the writer cuts it at every style
          // boundary and the pieces read as adjacent link spans.
          '[a](u)**[b](u)**[c](u)': [
            'p: "a"<link>{href: u} | "b"<bold+link>{href: u} | '
                '"c"<link>{href: u}',
          ],
          '[a](u)**[bc](u)d**': [
            'p: "a"<link>{href: u} | "bc"<bold+link>{href: u} | '
                '"d"<bold>',
          ],
          // A bang before a link is escaped so the link does not become an
          // image.
          r'wow\![x](u)': ['p: "wow!" | "x"<link>{href: u}'],
          // Nothing bare is detected: only a written link is a link.
          'see https://example.com and www.example.com or @alice': [
            'p: "see https://example.com and www.example.com or @alice"',
          ],
        });
      });

      group('mention-class targets', () {
        _conform({
          'hi [@alice](mention:alice)!': [
            'p: "hi " | "@alice"<mention>'
                '{id: alice, name: @alice, scheme: mention} | "!"',
          ],
          'hi [@a](username:a)': [
            'p: "hi " | "@a"<mention>{name: a, scheme: username}',
          ],
          'see [#t](hashtag:t)': [
            'p: "see " | "#t"<mention>{name: t, scheme: hashtag}',
          ],
          // Inside a style, the bit sits beside the style's.
          '**[@a](mention:1)**': [
            'p: "@a"<bold+mention>{id: 1, name: @a, scheme: mention}',
          ],
          // A mention-class span is never also a link.
          '[@a](mention:1) [x](https://a.b)': [
            'p: "@a"<mention>{id: 1, name: @a, scheme: mention} | " " | '
                '"x"<link>{href: https://a.b}',
          ],
          // An image keeps its image style whatever its scheme.
          '![a](mention:1)': ['p: "a"<image>{src: mention:1}'],
        });
      });

      group('inline embeds', () {
        _conform({
          'a![$_thumbsUp](unicode:1F44D)b': [
            'p: "a" | "$_thumbsUp"<image>{src: unicode:1F44D} | "b"',
          ],
          '![:)](document:5368)': ['p: ":)"<image>{src: document:5368}'],
          '![x](<external:a b>)': ['p: "x"<image>{src: external:a b}'],
          // The alt text of a joined sequence stays whole.
          '![$_family](unicode:1F468-200D-1F469-200D-1F467)': [
            'p: "$_family"<image>'
                '{src: unicode:1F468-200D-1F469-200D-1F467}',
          ],
          // Two embeds side by side, and one inside a style.
          '![a](document:1)![b](document:2)': [
            'p: "a"<image>{src: document:1} | "b"<image>{src: document:2}',
          ],
          '**![$_thumbsUp](unicode:1F44D)** x': [
            'p: "$_thumbsUp"<bold+image>{src: unicode:1F44D} | " x"',
          ],
        });
      });

      group('escaped specials read as typed', () {
        _conform({
          r'a\*b\`c\[d\]e\\f': ['p: "a*b`c[d]e\\f"'],
          r'\_x\_': ['p: "_x_"'],
          // An underscore inside a word is never emphasis and is not escaped.
          'snake_case_name': ['p: "snake_case_name"'],
          r'snake\_\_case': ['p: "snake__case"'],
          // A run of ~ | = escapes only where a pair could form.
          r'a\~\~b': ['p: "a~~b"'],
          r'a\|\|b': ['p: "a||b"'],
          r'x\=\=y': ['p: "x==y"'],
          'a ~~ b || c == d': ['p: "a ~~ b || c == d"'],
          '~ | =': ['p: "~ | ="'],
          // A ~ next to a written marker is escaped so it cannot join it.
          r'\~~~x~~': ['p: "~" | "x"<strikethrough>'],
          // Escapes inside a style.
          r'**a\*b**': ['p: "a*b"<bold>'],
          // A block marker is escaped only at the start of a line.
          r'\# no': ['p: "# no"'],
          r'\- no': ['p: "- no"'],
          r'\+ no': ['p: "+ no"'],
          r'\> no': ['p: "> no"'],
          r'\| no': ['p: "| no"'],
          r'1\. no': ['p: "1. no"'],
          r'12\) no': ['p: "12) no"'],
          r'\~\~\~': ['p: "~~~"'],
          'ok\n\\# no\n  \\- no': ['p: "ok\\n# no\\n  - no"'],
          'a # b - c > d 1. e': ['p: "a # b - c > d 1. e"'],
        });
      });

      group('quotes', () {
        _conform({
          // A quote after a plain line starts a block of its own.
          'a\n> b\n> c': ['p: "a"', 'q: "b\\nc"'],
          // A blank line ends the quote when text follows.
          '> q\n\nrest': ['q: "q"', 'gap', 'p: "rest"'],
          // An empty line inside a quote is a bare marker.
          '> a\n>\n> b': ['q: "a\\n\\nb"'],
          // Styles inside the quote.
          '> a**b**': ['q: "a" | "b"<bold>'],
          '> [@a](mention:1) hi': [
            'q: "@a"<mention>{id: 1, name: @a, scheme: mention} | " hi"',
          ],
        });
      });

      group('code blocks', () {
        _conform({
          '```\nplain\n```': ['code: "plain"'],
          '```dart\nvar a = 1;\n```': ['code(dart): "var a = 1;"'],
          // A language is letters, digits and + # . _ -.
          '```c++\nint x;\n```': ['code(c++): "int x;"'],
          '```c#\nvar x;\n```': ['code(c#): "var x;"'],
          '```objective-c\nx;\n```': ['code(objective-c): "x;"'],
          // Nothing inside a fence is markup.
          '```\na*b _c_ [x](y) **z**\n```': [
            'code: "a*b _c_ [x](y) **z**"',
          ],
          // A multi-line body keeps its line breaks.
          '```\none\n\ntwo\n```': ['code: "one\\n\\ntwo"'],
          // An unclosed fence runs to the end.
          '```dart\nunclosed': ['code(dart): "unclosed"'],
          // A fence between text lines is its own block.
          'before\n```\ncode\n```\nafter': [
            'p: "before"',
            'code: "code"',
            'p: "after"',
          ],
          // Two blocks on neighbouring lines stay two.
          '```a\nx\n```\n```b\ny\n```': ['code(a): "x"', 'code(b): "y"'],
        });
      });

      group('lists', () {
        _conform({
          '- one\n- two': ['list:', '  - "one"', '  - "two"'],
          '1. one\n2. two': ['list:', '  1. "one"', '  2. "two"'],
          // Two spaces a level, bullets and numbers mixed.
          '- a\n  - b\n    1. c\n      - d': [
            'list:',
            '  - "a"',
            '    - "b"',
            '      1. "c"',
            '        - "d"',
          ],
          // The writer numbers a run from 1; a bullet ends a numbered run, a
          // shallower item ends the deeper runs.
          '1. a\n2. b\n- x\n1. c\n  1. d\n  2. e\n2. f\n  1. g': [
            'list:',
            '  1. "a"',
            '  2. "b"',
            '  - "x"',
            '  1. "c"',
            '    1. "d"',
            '    2. "e"',
            '  2. "f"',
            '    1. "g"',
          ],
          // A plain line between items ends the list.
          '1. a\nplain\n1. b': [
            'list:',
            '  1. "a"',
            'p: "plain"',
            'list:',
            '  1. "b"',
          ],
          // Styles inside an item.
          '1. one **two**': ['list:', '  1. "one " | "two"<bold>'],
          '- [@a](mention:1) x': [
            'list:',
            '  - "@a"<mention>{id: 1, name: @a, scheme: mention} | " x"',
          ],
          // Text that looks like a marker is escaped and stays text.
          '\\- x\n3\\. x': ['p: "- x\\n3. x"'],
          // A list followed by a blank line and text.
          '- a\n- b\n\nplain': [
            'list:',
            '  - "a"',
            '  - "b"',
            'gap',
            'p: "plain"',
          ],
        });
      });

      // Spellings the writer emits that the parser does not read back as
      // meant. Each case pins what the parser reads today and says what the
      // writer means; a parser fix fails the case, and the case moves into
      // the table above with the expectation in its comment.
      group('known gaps', () {
        test('a soft break inside a list item ends the list', () {
          // Means: one list, the first item "one\ncontinued".
          expect(_read('- one  \ncontinued\n- next'), [
            'list:',
            '  - "one"',
            'p: "continued"',
            'list:',
            '  - "next"',
          ]);
        });

        test('a link label keeps the backslashes of its escapes', () {
          // Means: "a]b" and "@a_b" with no backslash; a label is not
          // unescaped the way paragraph text is.
          expect(_read(r'[a\]b](u)'), [r'p: "a\]b"<link>{href: u}']);
          expect(_read(r'[@a\_b](mention:x)'), [
            r'p: "@a\_b"<mention>{id: x, name: @a\_b, scheme: mention}',
          ]);
          expect(_read(r'![a\]b](document:1)'), [
            r'p: "a\]b"<image>{src: document:1}',
          ]);
        });

        test('a destination keeps the backslashes of escaped parentheses', () {
          // Means: href https://x/a_(b).
          expect(_read(r'[t](https://x/a_\(b\))'), [
            r'p: "t"<link>{href: https://x/a_\(b\)}',
          ]);
        });

        test('a code span with a longer fence is not one', () {
          // Means: "a`b" as code (the fence is one backtick longer than any
          // run inside), and "`a" padded by a space on both sides.
          expect(_read('``a`b``'), [
            'p: "``a" | "b"<monospace> | "`"',
          ]);
          expect(_read('`` `a ``'), [
            'p: "`` " | "a "<monospace> | "`"',
          ]);
        });

        test('a fence longer than three backticks is not one', () {
          // Means: the code "code ``` x"; a body that holds a run of
          // backticks is fenced with a longer one.
          expect(_read('````\ncode ``` x\n````'), ['code(`): "code ``` x"']);
          expect(_read('```a`b``c```'), ['code(a`b``c```): ""']);
        });

        test('an embed inside a link is not read as an embed', () {
          // Means: a link whose label holds an embed; the parser closes the
          // label at the embed's own bracket.
          expect(_read('**[a](u)[![$_thumbsUp](unicode:1F44D)](u)**'), [
            'p: "a"<bold+link>{href: u} | '
                '"![$_thumbsUp"<bold+link>{href: unicode:1F44D} | '
                '"](u)"<bold>',
          ]);
        });
      });
    });
