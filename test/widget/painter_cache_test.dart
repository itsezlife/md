import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/src/render.dart' show MarkdownRenderObject;
import 'package:flutter_test/flutter_test.dart';

final MarkdownThemeData _theme = MarkdownThemeData(
  textStyle: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
);

Widget _body(
  Markdown markdown, {
  MarkdownPainterCache? cache,
  MarkdownThemeData? theme,
  Key? key,
}) {
  Widget body = Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 300,
      child:
          MarkdownWidget(key: key, markdown: markdown, theme: theme ?? _theme),
    ),
  );
  if (cache != null) {
    body = MarkdownPainterCacheScope(cache: cache, child: body);
  }
  return Directionality(textDirection: TextDirection.ltr, child: body);
}

MarkdownRenderObject _render(WidgetTester tester) =>
    tester.renderObject<MarkdownRenderObject>(find.byType(MarkdownWidget));

void main() {
  final markdown = Markdown.fromString('Hello **world**, and a longer line.');

  testWidgets('a body that comes back paints from the painter it left', (
    tester,
  ) async {
    final cache = MarkdownPainterCache();
    addTearDown(cache.clear);
    await tester.pumpWidget(_body(markdown, cache: cache, key: const Key('a')));
    final painter = _render(tester).debugPainter;
    final size = tester.getSize(find.byType(MarkdownWidget));

    await tester.pumpWidget(const SizedBox());
    expect(cache.length, 1);

    // A new body, a new render object: the same markdown instance.
    await tester.pumpWidget(_body(markdown, cache: cache, key: const Key('b')));
    expect(_render(tester).debugPainter, same(painter));
    expect(cache.length, 0);
    expect(tester.getSize(find.byType(MarkdownWidget)), size);
  });

  testWidgets('without a scope a body keeps nothing', (tester) async {
    await tester.pumpWidget(_body(markdown, key: const Key('a')));
    final painter = _render(tester).debugPainter;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_body(markdown, key: const Key('b')));
    expect(_render(tester).debugPainter, isNot(same(painter)));
  });

  testWidgets('a kept painter takes the theme of the body it joins', (
    tester,
  ) async {
    final cache = MarkdownPainterCache();
    addTearDown(cache.clear);
    await tester.pumpWidget(_body(markdown, cache: cache, key: const Key('a')));
    final small = tester.getSize(find.byType(MarkdownWidget));
    await tester.pumpWidget(const SizedBox());

    final large = MarkdownThemeData(
      textStyle: const TextStyle(fontSize: 28, color: Color(0xFF000000)),
    );
    await tester.pumpWidget(
      _body(markdown, cache: cache, theme: large, key: const Key('b')),
    );
    expect(
      tester.getSize(find.byType(MarkdownWidget)).height,
      greaterThan(small.height),
    );
  });

  testWidgets('the cache drops its oldest painter past capacity', (
    tester,
  ) async {
    final cache = MarkdownPainterCache(capacity: 1);
    addTearDown(cache.clear);
    final other = Markdown.fromString('Another body');
    await tester.pumpWidget(_body(markdown, cache: cache, key: const Key('a')));
    await tester.pumpWidget(_body(other, cache: cache, key: const Key('b')));
    await tester.pumpWidget(const SizedBox());
    expect(cache.length, 1);
    expect(cache.take(markdown), isNull);
    expect(cache.take(other), isNotNull);
  });

  testWidgets('two bodies of one markdown do not share a painter', (
    tester,
  ) async {
    final cache = MarkdownPainterCache();
    addTearDown(cache.clear);
    await tester.pumpWidget(_body(markdown, cache: cache, key: const Key('a')));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MarkdownPainterCacheScope(
          cache: cache,
          child: Column(
            children: [
              MarkdownWidget(markdown: markdown, theme: _theme),
              MarkdownWidget(markdown: markdown, theme: _theme),
            ],
          ),
        ),
      ),
    );
    final renders = tester
        .renderObjectList<MarkdownRenderObject>(find.byType(MarkdownWidget))
        .toList();
    expect(renders[0].debugPainter, isNot(same(renders[1].debugPainter)));
  });

  testWidgets('a body paints from the painter prepared for it', (
    tester,
  ) async {
    final cache = MarkdownPainterCache();
    addTearDown(cache.clear);
    cache.prepare(markdown, theme: _theme, maxWidth: 300);
    expect(cache.holds(markdown), isTrue);
    final prepared = cache.take(markdown)!;
    // Give it back as a body that left would.
    cache.keep(prepared);

    await tester.pumpWidget(_body(markdown, cache: cache));
    expect(_render(tester).debugPainter, same(prepared));
  });

  testWidgets('nothing is prepared for a markdown a body shows', (
    tester,
  ) async {
    final cache = MarkdownPainterCache();
    addTearDown(cache.clear);
    await tester.pumpWidget(_body(markdown, cache: cache));
    cache.prepare(markdown, theme: _theme, maxWidth: 300);
    expect(cache.holds(markdown), isFalse);

    // Once the body leaves, its own painter is kept.
    await tester.pumpWidget(const SizedBox());
    expect(cache.holds(markdown), isTrue);
  });
}
