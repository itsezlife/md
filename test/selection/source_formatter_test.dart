import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

MarkdownSelectionController _controller(
  String source, {
  MarkdownSelectionFormatter? formatter,
}) {
  final controller = formatter == null
      ? MarkdownSelectionController()
      : MarkdownSelectionController(formatter: formatter);
  return controller
    ..setDocuments(<MarkdownDocumentRef>[
      MarkdownDocumentRef(id: 'doc', model: Markdown.fromString(source)),
    ]);
}

/// Everything in [source] selected, copied with [formatter] (or the default).
String _copyAll(String source, {MarkdownSelectionFormatter? formatter}) {
  final controller = _controller(source, formatter: formatter)..selectAll();
  return controller.getText();
}

/// The rendered-text range [from, to) of block 0 of [source], copied.
String _copySlice(String source, int from, int to) {
  final controller = _controller(source)
    ..selection = MarkdownSelection(
      base: MarkdownPosition(documentId: 'doc', blockIndex: 0, offset: from),
      extent: MarkdownPosition(documentId: 'doc', blockIndex: 0, offset: to),
    );
  return controller.getText();
}

/// What a parse of [markdown] means, free of source offsets: per block, its
/// type and its spans as text, style bits and extra, adjacent runs of the same
/// style merged (a split in the source carries no meaning).
String _meaning(String markdown) => <Object?>[
      for (final block in Markdown.fromString(markdown).blocks)
        if (block is! MD$Spacer) _blockMeaning(block),
    ].toString();

Object? _blockMeaning(MD$Block block) => block.map<Object?>(
      paragraph: (p) => ('paragraph', _runs(p.spans)),
      heading: (h) => ('heading', h.level, _runs(h.spans)),
      quote: (q) => ('quote', _runs(q.spans)),
      code: (c) => ('code', c.language, c.text),
      list: (l) => ('list', [for (final i in l.items) _runs(i.spans)]),
      divider: (_) => 'divider',
      table: (t) => ('table', t.text),
      alert: (a) => ('alert', a.alert, _runs(a.spans)),
      spacer: (_) => 'spacer',
    );

List<Object?> _runs(List<MD$Span> spans) {
  final merged = <(String, int, Map<String, Object?>?)>[];
  for (final span in spans) {
    final last = merged.isEmpty ? null : merged.last;
    if (last != null &&
        last.$2 == span.style.value &&
        span.extra == null &&
        last.$3 == null) {
      merged[merged.length - 1] = (last.$1 + span.text, last.$2, null);
    } else {
      merged.add((span.text, span.style.value, span.extra));
    }
  }
  return merged;
}

/// [spans] as one fully selected paragraph, copied with the default formatter.
String _copySpans(List<MD$Span> spans) {
  final text = spans.map((s) => s.text).join();
  return const MarkdownSourceFormatter().format(
    MarkdownSelectedContent(
      documents: <MarkdownSelectedDocument>[
        MarkdownSelectedDocument(
          documentId: 'doc',
          blocks: <MarkdownSelectedBlock>[
            MarkdownSelectedBlock(
              blockIndex: 0,
              type: 'paragraph',
              text: text,
              renderedRange: TextRange(start: 0, end: text.length),
              block: MD$Paragraph(text: text, spans: spans),
            ),
          ],
        ),
      ],
    ),
  );
}

MD$Span _span(String text, [MD$Style style = MD$Style.none]) =>
    MD$Span(start: 0, end: text.length, text: text, style: style);

// --- Generated paragraphs ---

const List<String> _words = <String>[
  'ab', 'x_y', '2*3', 'a]b', '[k', 'é', 'a`b', 'a~b', 'a|b', 'a=b', 'a!', //
  'b_', '_c', 'x**y', 'a~~b', 'a||b', 'a==b', 'e.g.', '1.5',
];

const List<MD$Style> _markStyles = <MD$Style>[
  MD$Style.italic,
  MD$Style.bold,
  MD$Style.strikethrough,
  MD$Style.spoiler,
  MD$Style.highlight,
  MD$Style.monospace,
];

MD$Span _generatedAtom(Random random, MD$Style marks) =>
    switch (random.nextInt(4)) {
      0 => MD$Span(
          start: 0,
          end: 3,
          text: 'lnk',
          style: marks.add(MD$Style.link),
          extra: const <String, Object?>{
            'type': 'link',
            'href': 'https://a.b/c_d',
            'url': 'https://a.b/c_d',
          },
        ),
      1 => MD$Span(
          start: 0,
          end: 4,
          text: '@Ann',
          style: marks.add(MD$Style.mention),
          extra: const <String, Object?>{
            'type': 'mention',
            'scheme': 'mention',
            'id': '42',
            'name': '@Ann',
          },
        ),
      2 => MD$Span(
          start: 0,
          end: 4,
          text: '#tag',
          style: marks.add(MD$Style.mention),
          extra: const <String, Object?>{
            'type': 'mention',
            'scheme': 'hashtag',
            'name': 'tag',
          },
        ),
      _ => MD$Span(
          start: 0,
          end: 3,
          text: 'alt',
          style: marks.add(MD$Style.image),
          extra: const <String, Object?>{
            'type': 'image',
            'src': 'emoji:5',
            'url': 'emoji:5',
          },
        ),
    };

/// Spans of a few words each, styled at random; a style change falls on a
/// word edge, the only place an underline can be written.
List<MD$Span> _generatedSpans(Random random) {
  final spans = <MD$Span>[];
  final count = 1 + random.nextInt(6);
  for (var i = 0; i < count; i++) {
    var marks = MD$Style.none;
    for (final style in _markStyles) {
      if (random.nextInt(4) == 0) marks = marks.add(style);
    }
    final gap = i == count - 1 ? '' : ' ';
    if (random.nextInt(5) == 0) {
      // Code is not made of `[` or `` ` ``: the parser reads a link out of a
      // `[` inside a code span, and has no way to write a backtick in one.
      spans
        ..add(_generatedAtom(random, marks.remove(MD$Style.monospace)))
        ..add(_span(gap));
      continue;
    }
    final word = _words[random.nextInt(_words.length)] + gap;
    if (word.contains('`') || word.contains('[')) {
      marks = marks.remove(MD$Style.monospace);
    }
    if (random.nextInt(4) == 0) marks = marks.add(MD$Style.underline);
    spans.add(_span(word, marks));
  }
  return spans;
}

/// One entry per character: the character and its style, without the style of
/// whitespace (it is written outside the marks) and without underline (it may
/// be dropped, see the group below).
List<(String, int)> _perCharacter(List<MD$Span> spans) => <(String, int)>[
      for (final span in spans)
        for (final unit in span.text.split(''))
          (
            unit,
            unit.trim().isEmpty
                ? 0
                : span.style.remove(MD$Style.underline).value,
          ),
    ];

void main() {
  group('MarkdownSelectionFormatter.plain and the default', () {
    test('a controller without a formatter copies markdown', () {
      expect(_copyAll('**bold** and *it*'), '**bold** and *it*');
    });

    test('a controller can still be given the plain formatter by name', () {
      expect(
        _copyAll(
          '**bold** and *it*',
          formatter: MarkdownSelectionFormatter.plain,
        ),
        'bold and it',
      );
    });

    test('plain is the old text-only formatter', () {
      expect(
          MarkdownSelectionFormatter.plain, isA<MarkdownPlainTextFormatter>());
    });

    test('MarkdownSelectedContent.toPlainText stays plain', () {
      final content = (_controller('**a**')..selectAll()).selectedContent();
      expect(content.toPlainText(), 'a');
    });
  });

  group('MarkdownSourceFormatter - inline styles', () {
    test('each style writes its dialect marker', () {
      expect(_copyAll('**b**'), '**b**');
      expect(_copyAll('*i*'), '*i*');
      expect(_copyAll('__u__'), '__u__');
      expect(_copyAll('~~s~~'), '~~s~~');
      expect(_copyAll('||p||'), '||p||');
      expect(_copyAll('==h=='), '==h==');
      expect(_copyAll('`c`'), '`c`');
    });

    test('an underscore italic is written with an asterisk', () {
      expect(_copyAll('_i_'), '*i*');
    });

    test('bold italic is written as one run of markers', () {
      expect(_copyAll('***x***'), '***x***');
    });

    test('a link writes label and destination', () {
      expect(
        _copyAll('see [site](https://a.b/c) now'),
        'see [site](https://a.b/c) now',
      );
    });

    test('a link keeps its title', () {
      expect(_copyAll('[s](https://a.b "T")'), '[s](https://a.b "T")');
    });

    test('a destination with a space is written in angle brackets', () {
      expect(_copyAll('[s](<https://a.b/c d>)'), '[s](<https://a.b/c d>)');
    });

    test('a styled link writes the marks around the link', () {
      expect(_copyAll('**[x](https://a.b)**'), '**[x](https://a.b)**');
    });

    test('mention-class spans write their scheme, not a URL', () {
      expect(_copyAll('[@Ann](mention:42)'), '[@Ann](mention:42)');
      expect(_copyAll('[@bob](username:bob)'), '[@bob](username:bob)');
      expect(_copyAll('[#tag](hashtag:tag)'), '[#tag](hashtag:tag)');
    });

    test('an image span writes its alt and source', () {
      expect(_copyAll('![smile](emoji:5)'), '![smile](emoji:5)');
    });

    test('code keeps its content unescaped', () {
      expect(_copyAll('`a*b_c`'), '`a*b_c`');
    });

    test('code nested in bold is written inside the bold marks', () {
      expect(_copyAll('**a `c` b**'), '**a `c` b**');
    });

    test('whitespace at the edge of a styled run stays outside the marks', () {
      // `** x**` would not open: a marker must be followed by non-space.
      expect(_copySlice('a **b c** d', 2, 5), '**b c**');
      expect(_copySlice('a **b c** d', 1, 5), ' **b c**');
      expect(_copySlice('a **b c** d', 2, 6), '**b c** ');
    });
  });

  group('MarkdownSourceFormatter - escapes', () {
    test('literal markers are backslash escaped', () {
      expect(_copyAll(r'2\*3 \`k\` \[y\] a\\b'), r'2\*3 \`k\` \[y\] a\\b');
    });

    test('an underscore is escaped outside a word, left inside one', () {
      expect(_copyAll(r'snake_case \_lead'), r'snake_case \_lead');
    });

    test('line-start block markers are escaped', () {
      expect(_copyAll(r'\- not a list'), r'\- not a list');
      expect(_copyAll(r'1\. not ordered'), r'1\. not ordered');
      expect(_copyAll(r'\# not heading'), r'\# not heading');
      expect(_copyAll(r'\> not quote'), r'\> not quote');
    });

    test('a literal marker run is escaped', () {
      expect(_copyAll(r'\~\~x\~\~'), r'\~\~x\~\~');
      expect(_copyAll(r'\|\|x\|\|'), r'\|\|x\|\|');
    });

    test('a bang before a link is escaped so it stays a link', () {
      expect(
        _copyAll(r'wow\![x](https://a.b)'),
        r'wow\![x](https://a.b)',
      );
    });
  });

  group('MarkdownSourceFormatter - blocks', () {
    test('block structure of the markup formatter is kept', () {
      expect(_copyAll('# T **x**'), '# T **x**');
      expect(_copyAll('- one\n- **two**'), '- one\n- **two**');
      expect(_copyAll('> q *i*'), '> q *i*');
      expect(_copyAll('```dart\nvar a = 1;\n```'), '```dart\nvar a = 1;\n```');
    });

    test('code that holds a fence gets a longer one', () {
      const content = MarkdownSelectedContent(
        documents: <MarkdownSelectedDocument>[
          MarkdownSelectedDocument(
            documentId: 'doc',
            blocks: <MarkdownSelectedBlock>[
              MarkdownSelectedBlock(
                blockIndex: 0,
                type: 'code',
                text: '```\nx',
                renderedRange: TextRange(start: 0, end: 5),
                block: MD$Code(language: 'dart', text: '```\nx'),
              ),
            ],
          ),
        ],
      );
      expect(
        const MarkdownSourceFormatter().format(content),
        '````dart\n```\nx\n````',
      );
    });
  });

  group('MarkdownSourceFormatter - partial selection', () {
    test('a selection inside a styled run keeps the style', () {
      // Rendered text: "hello bold world"; "ld" is the end of the bold run.
      expect(_copySlice('hello **bold** world', 8, 10), '**ld**');
    });

    test('a selection that starts inside a run closes and reopens marks', () {
      // "ab" bold + "cd" italic + "ef" plain; select from 1 to 5.
      expect(_copySlice('**ab***cd*ef', 1, 5), '**b***cd*e');
    });

    test('a slice across several styles and atoms keeps each of them', () {
      // Rendered: "x ab cd ef l code tail"; 3..20 is "b cd ef l code ta".
      expect(
        _copySlice('x **ab *cd* ef** [l](https://a.b) `code` tail', 3, 20),
        '**b *cd* ef** [l](https://a.b) `code` ta',
      );
    });

    test('a partial heading is copied without its marker', () {
      expect(_copySlice('# Big **title**', 2, 9), 'g **title**');
    });
  });

  group('MarkdownSourceFormatter - what the parser cannot read back', () {
    test('whitespace at the edge of a styled span is written outside', () {
      expect(
        _copySpans(<MD$Span>[_span(' b ', MD$Style.bold), _span('c')]),
        ' **b** c',
      );
    });

    test('an underline that ends inside a word is dropped, the text kept', () {
      expect(
        _copySpans(<MD$Span>[_span('ab', MD$Style.underline), _span('cd')]),
        'abcd',
      );
    });

    test('an underline that starts inside a word is dropped, the text kept',
        () {
      expect(
        _copySpans(<MD$Span>[_span('ab'), _span('cd', MD$Style.underline)]),
        'abcd',
      );
    });

    test('an underline at word edges is kept', () {
      expect(
        _copySpans(<MD$Span>[
          _span('ab '),
          _span('cd', MD$Style.underline),
          _span(' ef'),
        ]),
        'ab __cd__ ef',
      );
    });

    test('code that holds a backtick is written as plain text', () {
      expect(
        _copySpans(<MD$Span>[_span('a`b', MD$Style.monospace)]),
        r'a\`b',
      );
    });

    test('code is closed and reopened around another change of marks', () {
      expect(
        _copySpans(<MD$Span>[
          _span('a', MD$Style.monospace.add(MD$Style.bold)),
          _span('b', MD$Style.monospace),
        ]),
        '**`a`**`b`',
      );
    });

    test('an exclamation mark before a mention does not make an image', () {
      const mention = MD$Span(
        start: 0,
        end: 4,
        text: '@Ann',
        style: MD$Style.mention,
        extra: <String, Object?>{
          'type': 'mention',
          'scheme': 'mention',
          'id': '42',
          'name': '@Ann',
        },
      );
      expect(
        _copySpans(<MD$Span>[_span('hi!'), mention]),
        r'hi\![@Ann](mention:42)',
      );
    });
  });

  group('MarkdownSourceFormatter - partial blocks other than a paragraph', () {
    test('a slice of a list keeps its inline styles and loses its markers', () {
      // Rendered: "one\ntwo\nnested\nthree"; 0..7 is "one\ntwo".
      expect(_copySlice('- **one**\n- *two*\n  - nested\n- three', 0, 7),
          '**one**\n*two*');
    });

    test('a slice of a table keeps its cell separators', () {
      expect(
        _copySlice('| **A** | B |\n|---|---|\n| 1 | 2 |', 0, 3),
        '**A**\tB',
      );
    });

    test('a slice of a code block is copied as it is', () {
      expect(_copySlice('```\na*b_c\n```', 0, 3), 'a*b');
    });
  });

  group('MarkdownSourceFormatter - spoilers', () {
    test('hidden spoiler text is copied revealed, marks kept', () {
      expect(_copyAll('a ||secret|| b'), 'a ||secret|| b');
    });

    test('a spoiler around bold keeps both', () {
      expect(_meaning(_copyAll('||s **l**||')), _meaning('||s **l**||'));
    });
  });

  group('MarkdownSourceFormatter - self round trip', () {
    const corpus = <String>[
      '**bold** *italic* __under__ ~~strike~~ ||spoiler|| ==hi== `code`',
      '***bold italic*** and **bold *nested italic* end**',
      '**a*b**c*',
      'see [site](https://a.b/c) and [t](https://a.b "Title")',
      '**[bold link](https://a.b)** and *[it](https://c.d)*',
      '[@Ann](mention:42) [@bob](username:bob) [#tag](hashtag:tag)',
      '**[@Ann](mention:42)** said hi',
      'a ![smile](emoji:5) b',
      r'\*x\* a\_b \`k\` \[y\] 2\*3 \\ done',
      r'\- not list',
      r'1\. not ordered',
      r'\# not heading',
      r'\> not quote',
      r'\~\~x\~\~ \|\|y\|\| \=\=z\=\=',
      '||secret **loud**|| tail',
      'one **bold\nstill bold** end',
      '`a` and **`b` bold code** ok',
      r'wow\![x](https://a.b)',
      '# Title **x**',
      '- one\n- **two** [l](https://a.b)\n  - nested *it*',
      '> quote **b**',
      'plain with snake_case and 3*4',
      'a ***b** c* d',
    ];

    for (final source in corpus) {
      test(source.replaceAll('\n', r'\n'), () {
        final copied = _copyAll(source);
        expect(
          _meaning(copied),
          _meaning(source),
          reason: 'copied as: $copied',
        );
      });
    }
  });

  group('MarkdownSourceFormatter - generated paragraphs', () {
    // Whatever the words, styles and atoms, the copy of any slice parses to
    // the slice's characters with their styles. Underline is the one style
    // that may go missing (see above), so it is left out of the comparison.
    test('every slice reads back as the slice', () {
      final random = Random(7);
      for (var n = 0; n < 1500; n++) {
        final spans = _generatedSpans(random);
        final text = spans.map((s) => s.text).join();
        final from = random.nextBool() ? random.nextInt(text.length) : 0;
        final to = from == 0 && random.nextBool()
            ? text.length
            : from + 1 + random.nextInt(text.length - from);
        final selected = _perCharacter(spans).sublist(from, to);
        if (selected.every((c) => c.$1.trim().isEmpty)) continue;

        final copied = const MarkdownSourceFormatter().format(
          MarkdownSelectedContent(
            documents: <MarkdownSelectedDocument>[
              MarkdownSelectedDocument(
                documentId: 'doc',
                blocks: <MarkdownSelectedBlock>[
                  MarkdownSelectedBlock(
                    blockIndex: 0,
                    type: 'paragraph',
                    text: text.substring(from, to),
                    renderedRange: TextRange(start: from, end: to),
                    block: MD$Paragraph(text: text, spans: spans),
                  ),
                ],
              ),
            ],
          ),
        );
        final blocks = Markdown.fromString(copied).blocks;
        final reason =
            'spans: ${spans.map((s) => '${s.text}:${s.style.styles}')}, '
            'slice $from..$to, copied as: $copied';
        expect(blocks.single, isA<MD$Paragraph>(), reason: reason);
        final back = _perCharacter((blocks.single as MD$Paragraph).spans);
        // A paragraph drops the whitespace around it.
        List<(String, int)> trim(List<(String, int)> chars) {
          var start = 0;
          var end = chars.length;
          while (start < end && chars[start].$1.trim().isEmpty) {
            start++;
          }
          while (end > start && chars[end - 1].$1.trim().isEmpty) {
            end--;
          }
          return chars.sublist(start, end);
        }

        expect(trim(back), trim(selected), reason: reason);
      }
    });
  });

  group('MarkdownSourceFormatter - wiring', () {
    test('is the controller default and can be replaced', () {
      final controller = MarkdownSelectionController();
      expect(controller.formatter, isA<MarkdownSourceFormatter>());
    });

    test('keeps the separators of the markup formatter', () {
      final controller = MarkdownSelectionController()
        ..setDocuments(<MarkdownDocumentRef>[
          MarkdownDocumentRef(id: 'a', model: Markdown.fromString('**x**')),
          MarkdownDocumentRef(id: 'b', model: Markdown.fromString('*y*')),
        ])
        ..selectAll();
      expect(controller.getText(), '**x**\n\n*y*');
    });

    testWidgets('Ctrl+C puts markdown on the clipboard by default', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      // Reset in a finally: the framework checks foundation variables before
      // user tear-downs run.
      try {
        final controller = _controller('**bold** and [a link](https://a.b)')
          ..selectAll();
        final focus = FocusNode();
        addTearDown(focus.dispose);
        final data = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') data.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownSelectionScope(
                controller: controller,
                focusNode: focus,
                child: SizedBox(
                  width: 400,
                  child: MarkdownWidget(
                    markdown: controller.documents.single.model,
                    documentId: 'doc',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        focus.requestFocus();
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(
          data.single.arguments['text'],
          '**bold** and [a link](https://a.b)',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('an empty selection formats to an empty string', () {
      expect(_controller('**x**').getText(), isEmpty);
    });
  });
}
