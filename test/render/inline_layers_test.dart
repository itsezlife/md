// Inline pictures beside the fork's inline layer: embeds, spoilers and chips
// share one paragraph, one placeholder order and one offset map.
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render.dart';
import 'package:flutter_md/src/render/embed_offset_map.dart';
import 'package:flutter_md/src/render/inline_embeds.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_inline_embed_resolver.dart';

const String _obj = '￼';

/// Resolves every image and link to a fixed-size picture.
final class _Picture extends MarkdownImage {
  @override
  Size layout(MarkdownImageConstraints constraints) => const Size(40, 30);

  @override
  void paint(Canvas canvas, Rect rect, MarkdownImageConstraints constraints) {}
}

final class _Resolver {
  final List<MarkdownImageRequest> requests = <MarkdownImageRequest>[];

  MarkdownImage? call(MarkdownImageRequest request) {
    requests.add(request);
    return _Picture();
  }
}

MarkdownThemeData _theme(_Resolver resolver) => MarkdownThemeData(
      textStyle: const TextStyle(fontSize: 14),
      imageResolver: resolver.call,
    );

List<MD$Span> _spans(String source) =>
    Markdown.fromString(source).blocks.whereType<MD$Paragraph>().first.spans;

void main() {
  group('inline layers', () {
    test('an image inside a spoiler stays its alt text', () {
      final resolver = _Resolver();
      final p = BlockPainter$Paragraph(
        spans: _spans('a ||![cat](c.png)|| b'),
        theme: _theme(resolver),
      )..layout(400);
      addTearDown(p.dispose);
      expect(resolver.requests, isEmpty);
      expect(p.painter.plainText, 'a cat b');
      expect(p.renderedText, 'a cat b');
    });

    test('an embed wins over a picture for the same image', () {
      final resolver = _Resolver();
      final embeds = FakeInlineEmbedResolver();
      final host = MarkdownEmbedHost(resolver: embeds, devicePixelRatio: 1);
      addTearDown(host.disposeAll);
      final p = BlockPainter$Paragraph(
        spans: _spans('a ![:wave:](emoji:1) ![cat](c.png) b'),
        theme: _theme(resolver),
        inlineEmbeds: host,
      )..layout(400);
      addTearDown(p.dispose);
      expect(embeds.resolved, hasLength(1));
      expect(resolver.requests.map((r) => r.url), <String>['c.png']);
      expect(p.painter.plainText, 'a $_obj $_obj b');
      expect(p.renderedText, 'a :wave: cat b');
      // Both placeholders are entries of the one map, in paragraph order.
      final entries = MarkdownEmbedOffsets.of(p.painter).entries;
      expect(entries.map((e) => e.placeholderIndex), <int>[0, 1]);
      expect(entries.first.span, isNotNull);
      expect(entries.last.image, isNotNull);
      // An offset inside the picture's alt text snaps to the slot's start,
      // or, as a range end, past it.
      expect(markdownPainterOffset(p.painter, 10), 4);
      expect(markdownPainterOffset(p.painter, 11, end: true), 5);
    });

    test('a chip before a picture keeps both offset spaces in step', () {
      final resolver = _Resolver();
      final spans = <MD$Span>[
        const MD$Span(start: 0, end: 2, text: 'x '),
        MD$Span.chip(start: 2, text: 'Label', target: 'chip:1'),
        const MD$Span(start: 7, end: 8, text: ' '),
        const MD$Span(
          start: 8,
          end: 11,
          text: 'cat',
          style: MD$Style.image,
          extra: <String, Object?>{'type': 'image', 'url': 'c.png'},
        ),
      ];
      final p = BlockPainter$Paragraph(spans: spans, theme: _theme(resolver))
        ..layout(400);
      addTearDown(p.dispose);
      expect(resolver.requests, hasLength(1));
      expect(p.renderedText, 'x Label cat');
      expect(markdownModelText(p.painter), 'x Label cat');
      // The picture is the painter's last code unit and the model's last
      // three, wherever the chip's room put it.
      final last = p.painter.plainText.length;
      expect(markdownModelOffset(p.painter, last), 11);
      expect(markdownModelOffset(p.painter, last - 1), 8);
    });
  });
}
