import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/highlight.dart';
import 'package:flutter_md/highlight/dart.dart';
import 'package:flutter_md/highlight/themes.dart';
import 'package:flutter_md/src/render.dart' show MarkdownRenderObject;
import 'package:flutter_test/flutter_test.dart';

/// Code from [MarkdownHighlighter.backgroundFrom] on is shown plain at once
/// and colored once it is tokenized in a background isolate.
void main() {
  const base = TextStyle(fontSize: 14, color: Color(0xFF000000));
  final code = "final greeting = 'hello'; // a comment\n" * 200;

  MarkdownHighlighter highlighter() => MarkdownHighlighter(
        languages: {'dart': HighlightDart.grammar},
        theme: HighlightThemes.githubDark,
        backgroundFrom: 1000,
      );

  /// Lets the background isolates of [tester] run, until [done] or a
  /// generous limit.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('long code is plain at once, then colored', (tester) async {
    final h = highlighter();
    final first = h.highlight(code, 'dart', base);
    expect(first, hasLength(1));
    expect((first.single as TextSpan).text, code);

    List<InlineSpan> latest = first;
    await settle(tester, () {
      latest = h.highlight(code, 'dart', base);
      return latest.length > 1;
    });
    expect(latest.length, greaterThan(1));
    expect(TextSpan(children: latest).toPlainText(), code);
  });

  testWidgets('short code is colored at once', (tester) async {
    final spans = highlighter().highlight('final x = 1;', 'dart', base);
    expect(spans.length, greaterThan(1));
  });

  testWidgets('a body builds the block again, colored', (tester) async {
    final markdown = Markdown.fromString('Some text.\n\n```dart\n$code```\n');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: MarkdownWidget(
              markdown: markdown,
              theme: MarkdownThemeData(
                textStyle: base,
                highlighter: highlighter(),
              ),
            ),
          ),
        ),
      ),
    );
    final render =
        tester.renderObject<MarkdownRenderObject>(find.byType(MarkdownWidget));
    int runs() {
      final block = render.debugPainter.debugBlockPainters
          .whereType<BlockPainter$Code>()
          .single;
      return (block.painter.text! as TextSpan).children!.length;
    }

    expect(runs(), 1);
    final text = render.debugPainter.debugBlockPainters.first;
    await settle(tester, () => runs() > 1);
    expect(runs(), greaterThan(1));
    // Only the code block was built again.
    expect(render.debugPainter.debugBlockPainters.first, same(text));
  });
}
