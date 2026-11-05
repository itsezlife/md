import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'markdown.dart';
import 'render/markdown_painter.dart';

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

  /// How many painters are kept now.
  int get length => _painters.length;

  /// The kept painter of [markdown], removed from the cache, or null.
  MarkdownPainter? take(Markdown markdown) => _painters.remove(markdown);

  /// Keeps [painter] for the next body that shows its markdown. Its owner
  /// must not use it again.
  void keep(MarkdownPainter painter) {
    painter
      ..onPaintersRebuilt = null
      ..onEmbedSignal = null
      ..onImageChanged = null
      ..hideEmbeds();
    if (capacity == 0) {
      painter.dispose();
      return;
    }
    // Two bodies of one markdown left: the older painter goes.
    _painters.remove(painter.markdown)?.dispose();
    _painters[painter.markdown] = painter;
    while (_painters.length > capacity) {
      _painters.remove(_painters.keys.first)!.dispose();
    }
  }

  /// Disposes every kept painter.
  void clear() {
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
