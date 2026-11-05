import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'inline_embed.dart';
import 'markdown.dart';
import 'render/markdown_painter.dart';
import 'theme.dart';

/// Keeps the painters of markdown bodies that left the tree, so a body that
/// comes back paints from its laid-out text instead of building and laying
/// it out again.
///
/// A list that scrolls bodies out and back (a chat) otherwise pays for every
/// return twice: the leaving body disposes its paragraphs and the returning
/// one builds and lays them out from scratch. A kept painter is reused by the
/// next body that shows the same [Markdown] instance; laid out again at the
/// same width, its paragraphs do no work. The painters a body would change
/// (another theme, another resolver) it rebuilds as it would its own.
///
/// Holds at most [capacity] painters, the least recently kept dropped (and
/// disposed) first. Bodies find the cache through [MarkdownPainterCacheScope].
final class MarkdownPainterCache {
  /// A cache of up to [capacity] painters.
  MarkdownPainterCache({this.capacity = 64}) : assert(capacity >= 0);

  /// How many painters are kept.
  final int capacity;

  // Keyed by identity: a host parses a message once and shows that instance.
  final LinkedHashMap<Markdown, MarkdownPainter> _painters =
      LinkedHashMap<Markdown, MarkdownPainter>.identity();

  // The markdown of every body showing now, so [prepare] does not lay out a
  // second painter for a body that has one.
  final Set<Markdown> _shown = Set<Markdown>.identity();

  /// How many painters are kept now.
  int get length => _painters.length;

  /// The kept painter of [markdown] for a body about to show it, removed from
  /// the cache, or null. The body gives it back with [keep].
  MarkdownPainter? take(Markdown markdown) {
    _shown.add(markdown);
    return _painters.remove(markdown);
  }

  /// Lays out a painter for [markdown] ahead of the body that will show it,
  /// at [maxWidth], with the theme, resolver and pixel ratio that body will
  /// have, and keeps it. Nothing happens when one is kept or a body shows
  /// [markdown] already.
  ///
  /// The body takes it whatever its inputs; it keeps the laid-out text only
  /// when its theme paints like [theme], so a host prepares with the theme
  /// objects its bodies use.
  void prepare(
    Markdown markdown, {
    required MarkdownThemeData theme,
    required double maxWidth,
    MarkdownInlineEmbedResolver? embedResolver,
    double devicePixelRatio = 1.0,
  }) {
    if (capacity == 0 ||
        _shown.contains(markdown) ||
        _painters.containsKey(markdown)) {
      return;
    }
    final painter = MarkdownPainter(
      markdown: markdown,
      theme: theme,
      embedResolver: embedResolver,
      devicePixelRatio: devicePixelRatio,
    )..layout(maxWidth: maxWidth);
    _store(painter);
  }

  /// Whether a painter for [markdown] is kept.
  bool holds(Markdown markdown) => _painters.containsKey(markdown);

  /// Keeps [painter] for the next body that shows its markdown. Its owner
  /// must not use it again.
  void keep(MarkdownPainter painter) {
    _shown.remove(painter.markdown);
    painter
      ..onPaintersRebuilt = null
      ..onEmbedSignal = null
      ..onImageChanged = null
      ..hideEmbeds();
    if (capacity == 0) {
      painter.dispose();
      return;
    }
    _store(painter);
  }

  void _store(MarkdownPainter painter) {
    // Two bodies of one markdown left: the older painter goes.
    _painters.remove(painter.markdown)?.dispose();
    _painters[painter.markdown] = painter;
    while (_painters.length > capacity) {
      _painters.remove(_painters.keys.first)!.dispose();
    }
  }

  /// Disposes every kept painter.
  void clear() {
    _shown.clear();
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }
}

/// Gives the markdown bodies below it [cache] to keep and reuse their
/// painters through.
///
/// The owner of [cache] calls [MarkdownPainterCache.clear] when done with it.
class MarkdownPainterCacheScope extends InheritedWidget {
  /// Shares [cache] with the bodies in [child].
  const MarkdownPainterCacheScope({
    required this.cache,
    required super.child,
    super.key,
  });

  /// The cache the bodies below keep their painters in.
  final MarkdownPainterCache cache;

  /// The cache of the nearest scope, or null outside one.
  static MarkdownPainterCache? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MarkdownPainterCacheScope>()
      ?.cache;

  @override
  bool updateShouldNotify(MarkdownPainterCacheScope oldWidget) =>
      !identical(cache, oldWidget.cache);
}
