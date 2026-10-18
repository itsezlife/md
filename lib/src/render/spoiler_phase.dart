import 'dart:ui';

import 'package:meta/meta.dart' as meta show immutable, internal;

/// Where a document's spoilers stand, as the painter draws them.
///
/// A closed set rather than flags: "revealing" only makes sense with an
/// origin and a progress, and "hidden with a progress" is not a state.
/// [MarkdownPainter] reads it; the render object decides it from the
/// [MarkdownSpoilerController] and its reveal animation.
@meta.internal
@meta.immutable
sealed class SpoilerPhase {
  const SpoilerPhase();
}

/// Spoiler runs are concealed and covered by the fill. The state of a document
/// the controller has not revealed.
@meta.internal
final class SpoilerPhase$Hidden extends SpoilerPhase {
  /// Creates the hidden phase.
  const SpoilerPhase$Hidden();

  @override
  bool operator ==(Object other) => other is SpoilerPhase$Hidden;

  @override
  int get hashCode => (SpoilerPhase$Hidden).hashCode;
}

/// The reveal ripple is running: a circle grown from [origin] shows the
/// revealed text inside it and keeps the hidden form outside.
@meta.internal
final class SpoilerPhase$Revealing extends SpoilerPhase {
  /// Creates a ripple at [progress] (0 to 1, already eased) from the
  /// painter-local [origin]; a null origin ripples from the middle of the
  /// spoilers.
  const SpoilerPhase$Revealing({required this.progress, this.origin});

  /// Where the ripple starts, in painter-local coordinates.
  final Offset? origin;

  /// How far the circle has grown, 0 (nothing) to 1 (covers every spoiler).
  final double progress;

  @override
  bool operator ==(Object other) =>
      other is SpoilerPhase$Revealing &&
      other.origin == origin &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(origin, progress);
}

/// Spoiler runs show their text, as a document with no spoilers does. Also the
/// state of a painter that has no controller to ask.
@meta.internal
final class SpoilerPhase$Revealed extends SpoilerPhase {
  /// Creates the revealed phase.
  const SpoilerPhase$Revealed();

  @override
  bool operator ==(Object other) => other is SpoilerPhase$Revealed;

  @override
  int get hashCode => (SpoilerPhase$Revealed).hashCode;
}
