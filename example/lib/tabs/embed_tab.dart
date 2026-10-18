import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_md/flutter_md.dart';

const String _source = '''
# Inline embeds

A pulsing dot ![dot](pulse:a) sits in this line, and another
![dot](pulse:b) one too. Each is drawn by a live pass every frame; the glyphs
around them are a cached picture that is never re-recorded while they animate.

- a list item ![dot](pulse:c) with an embed
- an image the resolver does not know ![not found](https://example.com/x.png)

> a quote with ![dot](pulse:d) one

Drag across a dot to select it: the selection and copy see its alt text, and
the tint is painted over the dot.''';

/// Shows the live embed pass with a fake animated resolver: every `pulse:`
/// image becomes a dot that breathes in the colour of the text around it.
class EmbedTab extends StatefulWidget {
  /// Creates the tab.
  const EmbedTab({super.key});

  @override
  State<EmbedTab> createState() => _EmbedTabState();
}

class _EmbedTabState extends State<EmbedTab>
    with SingleTickerProviderStateMixin {
  late final _PulseResolver _resolver = _PulseResolver(createTicker);
  final Markdown _markdown = Markdown.fromString(_source);
  final MarkdownSelectionController _selection = MarkdownSelectionController();

  @override
  void initState() {
    super.initState();
    _selection.setDocuments(<MarkdownDocumentRef>[
      MarkdownDocumentRef(id: 'embeds', model: _markdown),
    ]);
  }

  @override
  void dispose() {
    _resolver.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MarkdownSelectionScope(
    controller: _selection,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        MarkdownWidget(
          markdown: _markdown,
          controller: _selection,
          documentId: 'embeds',
          // The app-wide theme drops image spans; this page keeps them.
          theme: MarkdownThemeData.mergeTheme(Theme.of(context)),
          embedResolver: _resolver,
        ),
      ],
    ),
  );
}

/// Resolves `pulse:` targets and drives all of its embeds from one ticker, so
/// the animation costs one tick per frame however many dots are on screen.
final class _PulseResolver implements MarkdownInlineEmbedResolver {
  _PulseResolver(Ticker Function(TickerCallback) createTicker) {
    _ticker = createTicker(_tick)..start();
  }

  late final Ticker _ticker;
  final Set<_PulseEmbed> _live = <_PulseEmbed>{};
  Duration _elapsed = Duration.zero;

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    // A hidden or disposed embed is not woken: an embed scrolled out of view
    // stops costing repaints.
    for (final embed in _live.toList()) {
      if (embed.visible) embed.wake();
    }
  }

  double get phase => _elapsed.inMilliseconds / 1000 * 2 * math.pi;

  @override
  MarkdownInlineEmbed? resolve(
    MarkdownInlineEmbedTarget target,
    MarkdownInlineEmbedMetrics metrics,
  ) {
    if (target.scheme != 'pulse') return null;
    final embed = _PulseEmbed(this, Size.square(metrics.extent));
    _live.add(embed);
    return embed;
  }

  void dispose() => _ticker.dispose();
}

final class _PulseEmbed extends ChangeNotifier implements MarkdownInlineEmbed {
  _PulseEmbed(this._owner, this.size);

  final _PulseResolver _owner;
  bool _disposed = false;

  @override
  final Size size;

  @override
  bool visible = true;

  void wake() => notifyListeners();

  @override
  void paint(
    ui.Canvas canvas,
    ui.Rect rect,
    MarkdownInlineEmbedPaintContext context,
  ) {
    if (_disposed) return;
    final scale = 0.6 + 0.2 * math.sin(_owner.phase);
    canvas.drawCircle(
      rect.center,
      rect.shortestSide / 2 * scale,
      Paint()
        ..color = (context.tint ?? Colors.blue).withValues(
          alpha: context.opacity,
        ),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _owner._live.remove(this);
    super.dispose();
  }
}
