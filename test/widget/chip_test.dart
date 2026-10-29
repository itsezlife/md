import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/chip.dart';
import 'package:flutter_md/src/render/text_offset_map.dart';
import 'package:flutter_md/src/render/span_builder.dart';
import 'package:flutter_test/flutter_test.dart';

const _ink = Color(0xFF00695C);
const _fill = Color(0x2200695C);
const _muted = Color(0xFF9E9E9E);
const _mutedFill = Color(0x229E9E9E);

MarkdownThemeData _theme({
  void Function(String, String)? onChipTap,
  void Function(String, String)? onLinkTap,
  void Function(String, String?, String)? onMentionTap,
  IconData? icon = Icons.star,
}) =>
    MarkdownThemeData(
      textStyle: const TextStyle(fontSize: 14),
      chipStyle: MarkdownChipStyle(
        color: _ink,
        background: _fill,
        mutedColor: _muted,
        mutedBackground: _mutedFill,
        icon: icon,
      ),
      onChipTap: onChipTap,
      onLinkTap: onLinkTap,
      onMentionTap: onMentionTap,
    );

List<MD$Span> _spans({bool muted = false}) => [
      const MD$Span(start: 0, end: 4, text: 'Hey '),
      MD$Span.chip(
        start: 4,
        text: 'Chip label',
        target: 'chip:1',
        muted: muted,
      ),
      const MD$Span(start: 14, end: 19, text: ' done'),
    ];

TextSpan _build(MarkdownThemeData theme, {bool muted = false}) =>
    paragraphFromMarkdownSpans(spans: _spans(muted: muted), theme: theme);

TextSpan _labelOf(MarkdownChipSpan chip) =>
    chip.children!.whereType<TextSpan>().singleWhere(
        (c) => c is! MarkdownChipGlyphSpan && c is! MarkdownChipSpacerSpan);

MarkdownChipSpan _chipOf(TextSpan root) =>
    root.children!.whereType<MarkdownChipSpan>().single;

void main() => group('Inline chip', () {
      test('the style is a public bit, exclusive of link and mention', () {
        expect(MD$Style.values, contains(MD$Style.chip));
        expect(MD$Style.chip.styles, {'chip'});
        final span = MD$Span.chip(start: 0, text: 'T', target: 'chip:1');
        expect(span.style, MD$Style.chip);
        expect(span.style.contains(MD$Style.link), isFalse);
        expect(span.style.contains(MD$Style.mention), isFalse);
        expect(span.extra, containsPair('type', 'chip'));
        expect(span.extra, containsPair('target', 'chip:1'));
        expect(span.extra, containsPair('muted', false));
      });

      test('paints a glyph, the label and a tinted fill from the style', () {
        final chip = _chipOf(_build(_theme()));
        expect(chip.background, _fill);
        expect(chip.muted, isFalse);
        final glyph = chip.children!.whereType<MarkdownChipGlyphSpan>().single;
        final label = _labelOf(chip);
        expect(glyph.color, _ink);
        expect(glyph.style!.fontFamily, Icons.star.fontFamily);
        expect(label.text, 'Chip label');
        expect(label.style!.color, _ink);
      });

      test('without an icon the chip has no glyph', () {
        final root = _build(_theme(icon: null));
        final chip = _chipOf(root);
        expect(chip.glyph, isNull);
        expect(chip.glyphLength, 0);
        expect(chip.children!.whereType<MarkdownChipGlyphSpan>(), isEmpty);
        final block = BlockPainter$Paragraph(
          spans: _spans(),
          theme: _theme(icon: null),
        )..layout(300);
        expect(block.painter.chipBoxes, hasLength(1));
        expect(block.painter.chipGlyphBoxes, isEmpty);
        expect(block.renderedText, 'Hey Chip label done');
        block.dispose();
      });

      test('the muted variant has its own colours', () {
        final chip = _chipOf(_build(_theme(), muted: true));
        expect(chip.muted, isTrue);
        expect(chip.background, _mutedFill);
        expect(_labelOf(chip).style!.color, _muted);
      });

      test('a font weight applies to the label, not the glyph', () {
        final root = _build(MarkdownThemeData(
          textStyle: const TextStyle(fontSize: 14),
          chipStyle: const MarkdownChipStyle(
            icon: Icons.star,
            fontWeight: FontWeight.w500,
          ),
        ));
        final chip = _chipOf(root);
        expect(_labelOf(chip).style!.fontWeight, FontWeight.w500);
        expect(chip.glyph!.style!.fontWeight, FontWeight.normal);
      });

      test('a tap fires only the chip callback, with target and label', () {
        final taps = <String>[];
        final root = _build(_theme(
          onChipTap: (target, label) => taps.add('$target|$label'),
          onLinkTap: (_, __) => taps.add('link'),
          onMentionTap: (_, __, ___) => taps.add('mention'),
        ));
        final chip = _chipOf(root);
        for (final child in chip.children!
            .cast<TextSpan>()
            .where((c) => c is! MarkdownChipSpacerSpan)) {
          (child.recognizer! as TapGestureRecognizer).onTap!();
        }
        expect(taps, ['chip:1|Chip label', 'chip:1|Chip label']);
      });

      test('without a callback the chip has no recognizer', () {
        final chip = _chipOf(_build(_theme()));
        for (final child in chip.children!.cast<TextSpan>()) {
          expect(child.recognizer, isNull);
        }
      });

      test('copy and selection see the label only', () {
        final root = _build(_theme());
        final chip = _chipOf(root);
        final g = chip.leadLength;
        final painterText = root.toPlainText(includeSemanticsLabels: false);
        // Glyph and room are code units of the painter's text, none of the
        // rendered.
        expect(painterText.length, 19 + chip.markerLength);
        final map = MarkdownTextOffsets.ofSpan(root);
        expect(map.renderedText(painterText), 'Hey Chip label done');
        expect(map.renderedLength(painterText.length), 19);
        expect(map.toPainter(4), 4);
        expect(map.toPainter(5), 5 + g);
        expect(map.toPainter(14), 14 + g);
        expect(map.toPainter(14, end: true), 14 + chip.markerLength);
        expect(map.toRendered(5 + g), 5);
        expect(map.toRendered(4 + g), 4);
      });

      test('a paragraph lays out and selects across the chip', () {
        final block = BlockPainter$Paragraph(
          spans: _spans(),
          theme: _theme(),
        )..layout(300);
        expect(block.renderedText, 'Hey Chip label done');
        expect(block.boxesForRange(0, 19), isNotEmpty);
        // Selecting the label alone covers the glyph and the label.
        final label = block.boxesForRange(4, 14).first;
        final all = block.boxesForRange(0, 19).first;
        expect(label.width, lessThan(all.width));
        expect(label.left, greaterThanOrEqualTo(all.left));
        // The fill is one rounded rect behind glyph and label.
        final fills = block.painter.chipBoxes;
        expect(fills, hasLength(1));
        expect(fills.single.$2, _fill);
        expect(fills.single.$1.left, lessThanOrEqualTo(label.left + .01));
        expect(fills.single.$1.right, greaterThanOrEqualTo(label.right - .01));
        block.dispose();
      });

      test('the glyph family does not inherit a host font package', () {
        const host = TextStyle(
          fontFamily: 'Geist',
          package: 'app_ui',
          fontSize: 14,
        );
        // The bug: copyWith keeps the host package for the icon family.
        final broken = host.copyWith(
          fontFamily: Icons.star.fontFamily,
          package: Icons.star.fontPackage,
        );
        expect(broken.fontFamily, 'packages/app_ui/MaterialIcons');
        final glyph = MarkdownChipGlyphSpan(style: host, icon: Icons.star);
        expect(glyph.style!.fontFamily, 'MaterialIcons');
        expect(glyph.style!.fontFamilyFallback, isNull);
        final themed = paragraphFromMarkdownSpans(
          spans: _spans(),
          theme: MarkdownThemeData(
            textStyle: host,
            chipStyle: const MarkdownChipStyle(
              icon: IconData(
                0xe000,
                fontFamily: 'CustomIcons',
                fontPackage: 'custom_icons',
              ),
            ),
          ),
        );
        final g =
            _chipOf(themed).children!.whereType<MarkdownChipGlyphSpan>().single;
        expect(g.style!.fontFamily, 'packages/custom_icons/CustomIcons');
        expect(g.text, String.fromCharCode(0xe000));
      });

      test('icon, size and gap are themable; copy stays the label', () {
        final theme = MarkdownThemeData(
          textStyle: const TextStyle(fontSize: 14),
          chipStyle: const MarkdownChipStyle(
            icon: Icons.star,
            iconSize: 18,
            gap: 4,
          ),
        );
        final root = _build(theme);
        final glyph =
            _chipOf(root).children!.whereType<MarkdownChipGlyphSpan>().single;
        expect(glyph.text, String.fromCharCode(Icons.star.codePoint));
        expect(glyph.style!.fontSize, 18);
        expect(glyph.style!.letterSpacing, 4);
        final painterText = root.toPlainText(includeSemanticsLabels: false);
        final map = MarkdownTextOffsets.ofSpan(root);
        expect(map.renderedText(painterText), 'Hey Chip label done');
      });

      test('radius is themable and the fill height ignores a big glyph', () {
        BlockPainter$Paragraph para(MarkdownThemeData t) =>
            BlockPainter$Paragraph(spans: _spans(), theme: t)..layout(300);
        final plain = para(_theme());
        final round = plain.painter.chipBoxes.single.$1;
        expect(round.tlRadiusX, closeTo(round.height / 2, 0.01));
        final boxy = para(MarkdownThemeData(
          textStyle: const TextStyle(fontSize: 14),
          chipStyle: const MarkdownChipStyle(
            icon: Icons.star,
            radius: 6,
            iconSize: 22,
            horizontalPadding: 8,
          ),
        ));
        final r = boxy.painter.chipBoxes.single.$1;
        expect(r.tlRadiusX, 6);
        expect(r.height, closeTo(round.height, 1.0));
        plain.dispose();
        boxy.dispose();
      });

      test('a wrapped chip gets one fill per line, none overlapping', () {
        final block = BlockPainter$Paragraph(
          spans: [
            MD$Span.chip(
              start: 0,
              text: 'Chip with a long wrapped label',
              target: 'chip:1',
            ),
          ],
          theme: _theme(),
        )..layout(120);
        final fills = block.painter.chipBoxes;
        expect(fills.length, greaterThan(1));
        for (var i = 1; i < fills.length; i++) {
          expect(fills[i].$1.top,
              greaterThanOrEqualTo(fills[i - 1].$1.bottom - 0.5));
        }
        block.dispose();
      });

      test('the selection tint is painted above the chip fill', () {
        expect(markdownSpansPaintOpaqueBackground(_spans()), isTrue);
      });

      test('chip style: copyWith, lerp, equality', () {
        const a = MarkdownChipStyle(color: Colors.red, radius: 2, gap: 2);
        const b = MarkdownChipStyle(color: Colors.blue, radius: 6, gap: 6);
        expect(a.copyWith(radius: 3).radius, 3);
        expect(a.copyWith(radius: 3).color, Colors.red);
        expect(
            a, const MarkdownChipStyle(color: Colors.red, radius: 2, gap: 2));
        expect(
            a.hashCode,
            const MarkdownChipStyle(color: Colors.red, radius: 2, gap: 2)
                .hashCode);
        expect(a, isNot(b));
        expect(MarkdownChipStyle.lerp(a, b, .5)!.radius, 4);
        expect(MarkdownChipStyle.lerp(null, null, .5), isNull);
        final t0 =
            MarkdownThemeData(textStyle: const TextStyle(), chipStyle: a);
        final t1 = t0.copyWith(chipStyle: b, onChipTap: (_, __) {});
        expect(t1.chipStyle, b);
        expect(t1.copyWith(clearOnChipTap: true).onChipTap, isNull);
        final mid = t0.lerp(t1, .5) as MarkdownThemeData;
        expect(mid.chipStyle!.gap, 4);
      });

      group('glyph is centred on the label', () {
        // Ahem is the font flutter_test paints with; the repo ships no other
        // font in its test assets.
        for (final fontSize in [14.0, 20.0]) {
          for (final iconSize in [14.0, 24.0]) {
            test('font $fontSize, icon $iconSize', () {
              final block = BlockPainter$Paragraph(
                spans: [
                  const MD$Span(start: 0, end: 2, text: 'A '),
                  MD$Span.chip(start: 2, text: 'Label', target: 'chip:1'),
                ],
                theme: MarkdownThemeData(
                  textStyle: TextStyle(fontFamily: 'Ahem', fontSize: fontSize),
                  chipStyle: MarkdownChipStyle(
                    icon: Icons.star,
                    iconSize: iconSize,
                    gap: 4,
                  ),
                ),
              )..layout(600);
              final painter = block.painter;
              final text =
                  painter.text!.toPlainText(includeSemanticsLabels: false);
              final l0 = text.indexOf('Label');
              final label = painter
                  .getBoxesForSelection(
                    TextSelection(baseOffset: l0, extentOffset: l0 + 5),
                    boxHeightStyle: BoxHeightStyle.tight,
                  )
                  .map((b) => b.toRect())
                  .reduce((a, b) => a.expandToInclude(b));
              final glyphs = painter.chipGlyphBoxes;
              expect(glyphs, hasLength(1));
              final glyph = glyphs.single.$1;
              expect(glyph.center.dy, closeTo(label.center.dy, 1.0));
              expect(glyph.height, closeTo(iconSize, 1.0));
              // The fill is as tall as the label's line, whatever the glyph.
              final fill = painter.chipBoxes.single.$1;
              expect(fill.top, closeTo(label.top, .01));
              expect(fill.bottom, closeTo(label.bottom, .01));
              // The glyph sits inside the fill, before the label.
              expect(glyph.left, greaterThanOrEqualTo(fill.left));
              expect(glyph.right, lessThanOrEqualTo(label.left + .01));
              block.dispose();
            });
          }
        }
      });

      group('real padding and margin', () {
        const pad = 6.0;
        const margin = 2.0;
        MarkdownThemeData theme() => MarkdownThemeData(
              textStyle: const TextStyle(fontSize: 14),
              chipStyle: const MarkdownChipStyle(
                color: _ink,
                background: _fill,
                icon: Icons.star,
                horizontalPadding: pad,
                margin: margin,
              ),
            );

        BlockPainter$Paragraph para(List<MD$Span> spans, double width) =>
            BlockPainter$Paragraph(spans: spans, theme: theme())..layout(width);

        MD$Span chipSpan(int start, String text) =>
            MD$Span.chip(start: start, text: text, target: 'chip:$start');

        // Painter offsets of one char: its box in the paragraph.
        Rect box(BlockPainter$Paragraph b, int i) => b.painter
            .getBoxesForSelection(
                TextSelection(baseOffset: i, extentOffset: i + 1))
            .first
            .toRect();

        test('word, fill and label are spaced by margin and padding', () {
          final b = para([
            const MD$Span(start: 0, end: 4, text: 'Hey '),
            chipSpan(4, 'Chip'),
            const MD$Span(start: 8, end: 9, text: ','),
          ], 400);
          final fill = b.painter.chipBoxes.single.$1;
          final word = box(b, 3); // the space after Hey
          // (a) preceding word's right edge to the fill: at least the margin.
          expect(fill.left - word.right, greaterThanOrEqualTo(margin - .01));
          // (b) fill edge to the label: at least the padding, both sides.
          final text =
              b.painter.text!.toPlainText(includeSemanticsLabels: false);
          final t0 = text.indexOf('Chip');
          final label = b.painter
              .getBoxesForSelection(
                  TextSelection(baseOffset: t0, extentOffset: t0 + 4))
              .map((e) => e.toRect())
              .reduce((a, c) => a.expandToInclude(c));
          expect(label.left - fill.left, greaterThanOrEqualTo(pad - .01));
          expect(fill.right - label.right, greaterThanOrEqualTo(pad - .01));
          // (c) the comma starts at the fill's right edge plus the margin.
          final comma = box(b, text.indexOf(','));
          expect(comma.left - fill.right, closeTo(margin, .01));
          b.dispose();
        });

        test('two chips separated by a comma do not touch', () {
          final b = para([
            chipSpan(0, 'First chip'),
            const MD$Span(start: 10, end: 12, text: ', '),
            chipSpan(12, 'Next'),
          ], 600);
          final fills = b.painter.chipBoxes;
          expect(fills, hasLength(2));
          final text =
              b.painter.text!.toPlainText(includeSemanticsLabels: false);
          final comma = box(b, text.indexOf(','));
          expect(comma.left, greaterThanOrEqualTo(fills[0].$1.right));
          expect(comma.right, lessThanOrEqualTo(fills[1].$1.left));
          expect(fills[1].$1.left - fills[0].$1.right, greaterThan(2 * margin));
          b.dispose();
        });

        test('copy and selection text stay the label', () {
          final spans = [
            const MD$Span(start: 0, end: 4, text: 'Hey '),
            chipSpan(4, 'Chip'),
            const MD$Span(start: 8, end: 9, text: ','),
          ];
          final b = para(spans, 400);
          expect(b.renderedText, 'Hey Chip,');
          // A range over the chip is the painter range of the label and the
          // room around it; the offsets round-trip.
          final map = MarkdownTextOffsets.of(b.painter);
          final text =
              b.painter.text!.toPlainText(includeSemanticsLabels: false);
          expect(map.renderedText(text), 'Hey Chip,');
          expect(map.toRendered(map.toPainter(4)), 4);
          expect(map.toRendered(map.toPainter(8, end: true)), 8);
          expect(map.toPainter(8, end: true), text.indexOf(','));
          b.dispose();
        });

        test('a wrapped chip is padded at its real start and end only', () {
          final b = para([
            const MD$Span(start: 0, end: 4, text: 'Hey '),
            chipSpan(4, 'Chip with a long wrapped label'),
          ], 200);
          final fills = b.painter.chipBoxes;
          expect(fills.length, greaterThan(1));
          final text =
              b.painter.text!.toPlainText(includeSemanticsLabels: false);
          final first = box(b, text.indexOf('Chip'));
          expect(first.left - fills.first.$1.left, greaterThanOrEqualTo(pad));
          final last = box(b, text.indexOf('label'));
          final lastEnd = box(b, text.indexOf('label') + 4);
          expect(last.left, greaterThanOrEqualTo(fills.last.$1.left));
          expect(fills.last.$1.right - lastEnd.right,
              greaterThanOrEqualTo(pad - .01));
          // Middle lines run to the text edge: the fill starts at the line.
          for (var i = 1; i < fills.length; i++) {
            expect(fills[i].$1.left, greaterThanOrEqualTo(-.01));
          }
          b.dispose();
        });
      });
    });
