import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/embed_offset_map.dart';
import 'package:flutter_md/src/render/span_builder.dart';
import 'package:flutter_md/src/render/vacancy_pill.dart';
import 'package:flutter_test/flutter_test.dart';

const _pill = Color(0xFF00695C);
const _fill = Color(0x2200695C);
const _muted = Color(0xFF9E9E9E);
const _mutedFill = Color(0x229E9E9E);

MarkdownThemeData _theme({
  void Function(String, String)? onVacancyTap,
  void Function(String, String)? onLinkTap,
  void Function(String, String?, String)? onMentionTap,
}) =>
    MarkdownThemeData(
      textStyle: const TextStyle(fontSize: 14),
      vacancyPillColor: _pill,
      vacancyPillBackground: _fill,
      vacancyPillMutedColor: _muted,
      vacancyPillMutedBackground: _mutedFill,
      onVacancyTap: onVacancyTap,
      onLinkTap: onLinkTap,
      onMentionTap: onMentionTap,
    );

List<MD$Span> _spans({bool muted = false}) => [
      const MD$Span(start: 0, end: 4, text: 'Hey '),
      MD$Span.vacancy(
        start: 4,
        title: 'Flutter Dev',
        target: 'vref:V1',
        muted: muted,
      ),
      const MD$Span(start: 15, end: 20, text: ' done'),
    ];

TextSpan _build(MarkdownThemeData theme, {bool muted = false}) =>
    paragraphFromMarkdownSpans(spans: _spans(muted: muted), theme: theme);

MarkdownPillSpan _pillOf(TextSpan root) =>
    root.children!.whereType<MarkdownPillSpan>().single;

void main() => group('Vacancy pill', () {
      test('the style is a public bit, exclusive of link and mention', () {
        expect(MD$Style.values, contains(MD$Style.vacancy));
        expect(MD$Style.vacancy.styles, {'vacancy'});
        final span = MD$Span.vacancy(start: 0, title: 'T', target: 'vref:V1');
        expect(span.style, MD$Style.vacancy);
        expect(span.style.contains(MD$Style.link), isFalse);
        expect(span.style.contains(MD$Style.mention), isFalse);
        expect(span.extra, containsPair('target', 'vref:V1'));
      });

      test('paints an icon, the title and a tinted fill from theme tokens', () {
        final pill = _pillOf(_build(_theme()));
        expect(pill.background, _fill);
        expect(pill.muted, isFalse);
        final [glyph, title] = pill.children!.cast<TextSpan>();
        expect(glyph, isA<MarkdownPillGlyphSpan>());
        expect(glyph.style!.color, _pill);
        expect(glyph.style!.fontFamily, Icons.work_outline_rounded.fontFamily);
        expect(title.text, 'Flutter Dev');
        expect(title.style!.color, _pill);
      });

      test('the muted variant has its own tokens', () {
        final pill = _pillOf(_build(_theme(), muted: true));
        expect(pill.muted, isTrue);
        expect(pill.background, _mutedFill);
        expect((pill.children!.last as TextSpan).style!.color, _muted);
      });

      test('a tap fires only the vacancy callback, with target and title', () {
        final taps = <String>[];
        final root = _build(_theme(
          onVacancyTap: (target, title) => taps.add('$target|$title'),
          onLinkTap: (_, __) => taps.add('link'),
          onMentionTap: (_, __, ___) => taps.add('mention'),
        ));
        final pill = _pillOf(root);
        for (final child in pill.children!.cast<TextSpan>()) {
          (child.recognizer! as TapGestureRecognizer).onTap!();
        }
        expect(taps, ['vref:V1|Flutter Dev', 'vref:V1|Flutter Dev']);
      });

      test('without a callback the pill has no recognizer', () {
        final pill = _pillOf(_build(_theme()));
        for (final child in pill.children!.cast<TextSpan>()) {
          expect(child.recognizer, isNull);
        }
      });

      test('copy and selection see the title only', () {
        final root = _build(_theme());
        final g = _pillOf(root).glyphLength;
        final painterText = root.toPlainText(includeSemanticsLabels: false);
        // The icon is code units of the painter's text, none of the rendered.
        expect(painterText.length, 20 + g);
        final map = MarkdownEmbedOffsets.ofSpan(root);
        expect(map.renderedText(painterText), 'Hey Flutter Dev done');
        expect(map.renderedLength(painterText.length), 20);
        expect(map.toPainter(4), 4);
        expect(map.toPainter(5), 5 + g);
        expect(map.toPainter(15, end: true), 15 + g);
        expect(map.toRendered(5 + g), 5);
        expect(map.toRendered(4 + g), 4);
      });

      test('a paragraph lays out and selects across the pill', () {
        final block = BlockPainter$Paragraph(
          spans: _spans(),
          theme: _theme(),
        )..layout(300);
        expect(block.renderedText, 'Hey Flutter Dev done');
        final boxes = block.boxesForRange(0, 20);
        expect(boxes, isNotEmpty);
        // Selecting the title alone covers the icon and the title.
        final title = block.boxesForRange(4, 15).first;
        final all = block.boxesForRange(0, 20).first;
        expect(title.width, lessThan(all.width));
        expect(title.left, greaterThanOrEqualTo(all.left));
        // The fill is one rounded rect behind icon and title.
        final fills = block.painter.pillBoxes;
        expect(fills, hasLength(1));
        expect(fills.single.$2, _fill);
        expect(fills.single.$1.left, lessThanOrEqualTo(title.left));
        expect(fills.single.$1.right, greaterThanOrEqualTo(title.right));
        block.dispose();
      });

      test('the selection tint is painted above the pill fill', () {
        expect(markdownSpansPaintOpaqueBackground(_spans()), isTrue);
      });
    });
