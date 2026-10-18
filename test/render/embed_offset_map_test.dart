import 'package:flutter/painting.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/embed_offset_map.dart';
import 'package:flutter_md/src/render/inline_embeds.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_inline_embed_resolver.dart';

void main() {
  group('MarkdownEmbedOffsets', () {
    // A paragraph whose text is the literals and embeds in order; an `alt`
    // string is an embed, a plain string is text.
    InlineSpan paragraph(List<Object> parts) => TextSpan(
          children: [
            for (final part in parts)
              if (part is _Alt)
                MarkdownEmbedSpan(
                  embed: FakeInlineEmbed(
                    MarkdownInlineEmbedTarget(
                      scheme: 'emoji',
                      id: '1',
                      alt: part.text,
                    ),
                    const Size(10, 10),
                  ),
                  target: MarkdownInlineEmbedTarget(
                    scheme: 'emoji',
                    id: '1',
                    alt: part.text,
                  ),
                  layoutHeight: 8,
                )
              else
                TextSpan(text: part as String),
          ],
        );

    String painterText(InlineSpan span) => span.toPlainText(
          includeSemanticsLabels: false,
        );

    test('a paragraph with no embed is the identity', () {
      final span = paragraph(['plain ', 'text']);
      final map = MarkdownEmbedOffsets.ofSpan(span);
      expect(map.isIdentity, isTrue);
      expect(map.renderedText(painterText(span)), 'plain text');
      for (var i = 0; i <= 10; i++) {
        expect(map.toRendered(i), i);
        expect(map.toPainter(i), i);
        expect(map.toPainter(i, end: true), i);
      }
      expect(map.snap(const TextRange(start: 2, end: 5)),
          const TextRange(start: 2, end: 5));
    });

    test('a null span is the identity', () {
      expect(MarkdownEmbedOffsets.ofSpan(null).isIdentity, isTrue);
    });

    test('a multi-unit alt widens the text and shifts what follows', () {
      final span = paragraph(['ab', const _Alt('xyz'), 'c']);
      final map = MarkdownEmbedOffsets.ofSpan(span);
      expect(painterText(span).length, 4);
      expect(map.renderedText(painterText(span)), 'abxyzc');
      expect(map.renderedLength(4), 6);
      expect(
        [for (var p = 0; p <= 4; p++) map.toRendered(p)],
        [0, 1, 2, 5, 6],
      );
      expect(
        [0, 1, 2, 5, 6].map(map.toPainter).toList(),
        [0, 1, 2, 3, 4],
      );
    });

    test('an offset inside the alt snaps outward by the role it plays', () {
      final map = MarkdownEmbedOffsets.ofSpan(
        paragraph(['ab', const _Alt('xyz'), 'c']),
      );
      for (final inside in [3, 4]) {
        expect(map.toPainter(inside), 2, reason: 'a start before the embed');
        expect(map.toPainter(inside, end: true), 3,
            reason: 'an end after the embed');
      }
      expect(
        map.snap(const TextRange(start: 3, end: 4)),
        const TextRange(start: 2, end: 5),
      );
      expect(
        map.snap(const TextRange(start: 1, end: 3)),
        const TextRange(start: 1, end: 5),
      );
      expect(
        map.snap(const TextRange(start: 4, end: 6)),
        const TextRange(start: 2, end: 6),
      );
      expect(
        map.snap(const TextRange(start: 0, end: 2)),
        const TextRange(start: 0, end: 2),
        reason: 'a range that ends at the embed does not take it',
      );
    });

    test('surrogate pairs and ZWJ sequences count as their code units', () {
      const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
      expect(family.length, 8);
      final span = paragraph(['\u{1F600}', const _Alt(family), '\u{1F600}']);
      final map = MarkdownEmbedOffsets.ofSpan(span);
      expect(painterText(span).length, 5);
      expect(map.renderedText(painterText(span)), '\u{1F600}$family\u{1F600}');
      // Painter boundaries: 0, 2 | embed | 3, 5 -> rendered 0, 2, 10, 12.
      expect(
        [0, 2, 3, 5].map(map.toRendered).toList(),
        [0, 2, 10, 12],
      );
      expect(
        map.snap(const TextRange(start: 5, end: 6)),
        const TextRange(start: 2, end: 10),
      );
    });

    test('an embed at the start, at the end and two side by side', () {
      final span = paragraph(
          [const _Alt('ab'), const _Alt('cde'), 'x', const _Alt('f')]);
      final map = MarkdownEmbedOffsets.ofSpan(span);
      final text = painterText(span);
      expect(text.length, 4);
      expect(map.renderedText(text), 'abcdexf');
      expect([for (var p = 0; p <= 4; p++) map.toRendered(p)], [0, 2, 5, 6, 7]);
      expect([0, 2, 5, 6, 7].map(map.toPainter).toList(), [0, 1, 2, 3, 4]);
      expect(map.entries.map((e) => (e.painterStart, e.renderedStart)),
          [(0, 0), (1, 2), (3, 6)]);
    });

    test('every rendered boundary survives the round trip', () {
      final span = paragraph([
        'a',
        const _Alt('\u{1F600}'),
        const _Alt('b'),
        '\u{1F468}‍\u{1F469}',
        const _Alt('xyz'),
      ]);
      final map = MarkdownEmbedOffsets.ofSpan(span);
      final text = painterText(span);
      final length = map.renderedLength(text.length);
      final embedded = <(int, int)>[
        for (final e in map.entries) (e.renderedStart, e.renderedEnd),
      ];
      for (var r = 0; r <= length; r++) {
        final interior = embedded.any((range) => r > range.$1 && r < range.$2);
        if (interior) continue;
        expect(map.toRendered(map.toPainter(r)), r, reason: 'offset $r');
        expect(map.toRendered(map.toPainter(r, end: true)), r,
            reason: 'offset $r as an end');
      }
      for (var p = 0; p <= text.length; p++) {
        expect(map.toPainter(map.toRendered(p)), p, reason: 'painter $p');
      }
    });

    test('an empty alt takes a placeholder and no rendered text', () {
      final span = paragraph(['a', const _Alt(''), 'b']);
      final map = MarkdownEmbedOffsets.ofSpan(span);
      expect(map.renderedText(painterText(span)), 'ab');
      expect(map.renderedLength(3), 2);
      expect([for (var p = 0; p <= 3; p++) map.toRendered(p)], [0, 1, 1, 2]);
      expect(map.toPainter(1), 1);
      expect(map.toPainter(2), 3);
    });

    test('the map of a painter follows its text', () {
      final first = paragraph(['ab', const _Alt('xyz')]);
      final painter = TextPainter(
        text: first,
        textDirection: TextDirection.ltr,
      );
      expect(MarkdownEmbedOffsets.of(painter).entries, hasLength(1));
      expect(
          identical(MarkdownEmbedOffsets.of(painter),
              MarkdownEmbedOffsets.of(painter)),
          isTrue);
      painter.text = const TextSpan(text: 'plain');
      expect(MarkdownEmbedOffsets.of(painter).isIdentity, isTrue);
      painter.dispose();
    });
  });
}

/// Marks an embed with this alt text in [paragraph]'s parts.
final class _Alt {
  const _Alt(this.text);

  final String text;
}
