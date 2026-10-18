import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render/markdown_render_object.dart';
import 'package:flutter_md/src/render/spoiler_phase.dart';
import 'package:flutter_test/flutter_test.dart';

// Rendered text: `before ` is 0..7, the spoiler `secret` 7..13.
const _source = 'before ||secret|| after';

void main() {
  group('a selection over a hidden spoiler', () {
    late MarkdownSelectionController selection;
    late MarkdownSpoilerController spoilers;

    setUp(() {
      selection = MarkdownSelectionController();
      spoilers = MarkdownSpoilerController(animate: false);
    });
    tearDown(() {
      selection.dispose();
      spoilers.dispose();
    });

    Future<MarkdownRenderObject> pumpSelected(WidgetTester tester) async {
      selection.setDocuments([
        MarkdownDocumentRef(id: 'a', model: Markdown.fromString(_source)),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: MarkdownSelectionScope(
                  controller: selection,
                  child: MarkdownWidget(
                    markdown: Markdown.fromString(_source),
                    theme: MarkdownThemeData(
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                    documentId: 'a',
                    spoilerController: spoilers,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      selection.selection = const MarkdownSelection(
        base: MarkdownPosition(documentId: 'a', blockIndex: 0, offset: 0),
        extent: MarkdownPosition(documentId: 'a', blockIndex: 0, offset: 20),
      );
      await tester.pump();
      return tester.renderObject(find.byType(MarkdownWidget))
          as MarkdownRenderObject;
    }

    testWidgets('does not reveal the spoiler', (tester) async {
      final render = await pumpSelected(tester);

      expect(render.debugPainter.spoilerPhase, isA<SpoilerPhase$Hidden>());
      expect(spoilers.isRevealed('a'), isFalse);
    });

    testWidgets('is tinted under the dust, so the dust stays on top', (
      tester,
    ) async {
      final render = await pumpSelected(tester);

      // The tint first, under the glyphs; the spoiler pass (a clip to the
      // patch, then the fill) after the glyph picture, over the tint.
      expect(
        render,
        paints
          ..rect(color: selection.selectionColor)
          ..clipRRect()
          ..rect(),
      );
    });
  });
}
