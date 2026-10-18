import 'dart:ui' show Canvas, Color, Paint, Rect, Size, VoidCallback;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/rendering.dart' show Matrix4;
import 'package:flutter_md/flutter_md.dart';

/// One embed [FakeInlineEmbedResolver] made: records how often it was disposed
/// and what [paint] was asked of it.
final class FakeInlineEmbed extends ChangeNotifier
    implements MarkdownInlineEmbed {
  /// Creates an embed for [target] of [size].
  FakeInlineEmbed(this.target, this.size);

  /// What the embed was resolved for.
  final MarkdownInlineEmbedTarget target;

  @override
  final Size size;

  @override
  bool get visible => _visible;
  @override
  set visible(bool value) {
    _visible = value;
    visibleChanges.add(value);
  }

  bool _visible = true;

  /// Every value [visible] was set to, in order.
  final List<bool> visibleChanges = <bool>[];

  /// What [visible] read when [dispose] first ran.
  bool? visibleWhenDisposed;

  /// Every [paint] call, in order: the rectangle, the context and the canvas
  /// transform at the time (a panned block moves the embed with it).
  final List<
      ({
        Rect rect,
        MarkdownInlineEmbedPaintContext context,
        Matrix4 transform,
      })> paints = <({
    Rect rect,
    MarkdownInlineEmbedPaintContext context,
    Matrix4 transform,
  })>[];

  /// Says that what [paint] draws is different now.
  void fire() => notifyListeners();

  /// How many times [dispose] was called.
  int disposeCount = 0;

  /// Whether [dispose] was called at least once.
  bool get isDisposed => disposeCount > 0;

  /// Fills the rectangle with the tint (opaque black without one), so a
  /// golden shows where, and in what colour, the embed was painted.
  @override
  void paint(
    Canvas canvas,
    Rect rect,
    MarkdownInlineEmbedPaintContext context,
  ) {
    paints.add((
      rect: rect,
      context: context,
      transform: Matrix4.fromFloat64List(canvas.getTransform()),
    ));
    canvas.drawRect(
      rect,
      Paint()
        ..color = (context.tint ?? const Color(0xFF000000))
            .withValues(alpha: context.opacity),
    );
  }

  @override
  void dispose() {
    if (disposeCount == 0) visibleWhenDisposed = _visible;
    disposeCount++;
    // ChangeNotifier asserts on a second dispose; the contract here is
    // idempotent, and the count is what the tests look at.
    if (disposeCount == 1) super.dispose();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!isDisposed) super.addListener(listener);
  }
}

/// A resolver of fixed behaviour for the fork's own tests: it knows the
/// schemes in [schemes], answers null for the rest, and keeps every embed it
/// made.
///
/// The embed is [size] square, or, when [size] is null, the square the size
/// rule gives for the metrics the body passed, as a real resolver would size
/// it.
final class FakeInlineEmbedResolver implements MarkdownInlineEmbedResolver {
  /// Creates a resolver for [schemes].
  FakeInlineEmbedResolver({
    this.schemes = const <String>{'emoji'},
    this.size,
  });

  /// The schemes this resolver answers for.
  final Set<String> schemes;

  /// The fixed size of every embed, or null for the size rule.
  final Size? size;

  /// Every embed made, in order.
  final List<FakeInlineEmbed> resolved = <FakeInlineEmbed>[];

  /// Every metrics value the body passed, in order.
  final List<MarkdownInlineEmbedMetrics> metricsSeen =
      <MarkdownInlineEmbedMetrics>[];

  /// Embeds that were not disposed.
  Iterable<FakeInlineEmbed> get live => resolved.where((e) => !e.isDisposed);

  @override
  MarkdownInlineEmbed? resolve(
    MarkdownInlineEmbedTarget target,
    MarkdownInlineEmbedMetrics metrics,
  ) {
    if (!schemes.contains(target.scheme)) return null;
    metricsSeen.add(metrics);
    final side = metrics.extent;
    final embed = FakeInlineEmbed(target, size ?? Size(side, side));
    resolved.add(embed);
    return embed;
  }
}
