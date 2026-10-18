import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart' as meta show internal;

import '../spoiler.dart';
import 'spoiler_particle_field.dart';

/// Turns a recorded tile into an image of `size` by `size` pixels.
///
/// The default is [Picture.toImageSync]: GPU-resident, no decode and no async
/// gap, so the tile can be re-rendered inside a frame. A test passes its own
/// to count renders or to stand in for a renderer that lacks it.
@meta.internal
typedef SpoilerTileImageRenderer = Image Function(Picture picture, int size);

Image _toImageSync(Picture picture, int size) =>
    picture.toImageSync(size, size);

/// Corner radius of a spoiler patch in dp (Android clips its dust to 3 dp).
const double _kSpoilerRadius = 3;

/// A stalled clock must not teleport the dust: at most this many frames of
/// simulation per render.
const int _kMaxStepFrames = 8;

/// One live particle tile: a [SpoilerParticleField] rendered to an image that
/// every hidden spoiler samples through an `ImageShader` in repeat mode.
///
/// This is Android's `SpoilerEffectBitmapFactory` as a *live* tile. The cost
/// of the dust is one render of this tile per tick, however many spoilers are
/// on screen; each spoiler only draws a rect with the shader.
///
/// The tile is rendered **lazily**: on the first [fill] of a frame, never
/// from a timer of its own. A tick nobody paints costs nothing, and a frame
/// with twenty spoilers renders once.
///
/// Where the renderer cannot make an image synchronously (an engine without
/// [Picture.toImageSync]) the tile is **static**: the frame-0 dust, kept as a
/// [Picture] and drawn tiled, rendered once and never again. Hidden spoilers
/// then stand still instead of failing. That is an expected capability gap,
/// not an error, so it is recorded in [unsupported] rather than reported.
@meta.internal
final class SpoilerParticleTile {
  /// Creates a tile of [color] dust for a display of [devicePixelRatio].
  ///
  /// Use [SpoilerParticleTiles.acquire] in production: one tile per
  /// `(color, devicePixelRatio)` is shared by every spoiler.
  SpoilerParticleTile({
    required this.color,
    required this.devicePixelRatio,
    math.Random? random,
    SpoilerTileImageRenderer renderer = _toImageSync,
  })  : _renderer = renderer,
        _field = SpoilerParticleField(random: random ?? math.Random()),
        _pixels = (SpoilerParticleField.defaultSide * devicePixelRatio)
            .round()
            .clamp(1, 4096);

  /// The dust colour: the text colour of the document.
  final Color color;

  /// The pixel ratio the image is rendered at.
  final double devicePixelRatio;

  final SpoilerTileImageRenderer _renderer;
  final SpoilerParticleField _field;
  final int _pixels;

  Image? _image;
  Paint? _paint;
  Picture? _stillPicture;
  int? _frame;
  bool _static = false;
  Object? _unsupported;
  bool _disposed = false;
  int _renderCount = 0;

  /// Whether the tile is the frame-0 [Picture] and will never change.
  bool get isStatic => _static;

  /// Why the renderer could not make an image, if it could not.
  Object? get unsupported => _unsupported;

  /// How many times the tile was rendered. Exposed for tests asserting one
  /// render per tick however many spoilers paint it.
  @visibleForTesting
  int get debugRenderCount => _renderCount;

  /// Whether [dispose] ran. Exposed for tests asserting a theme change frees
  /// the old tile.
  @visibleForTesting
  bool get debugDisposed => _disposed;

  /// The particles. Exposed for tests of the simulation through the tile.
  @visibleForTesting
  SpoilerParticleField get debugField => _field;

  /// Where on the tile the pattern starts for the [index]th spoiler of a
  /// document, in dp.
  ///
  /// Neighbouring spoilers sample different parts of the tile, so their dust
  /// does not line up. The steps are odd, hence coprime with the tile side:
  /// a document cycles through every offset before repeating one.
  static Offset phaseOf(int index) => Offset(
        (index * 47) % SpoilerParticleField.defaultSide,
        (index * 89) % SpoilerParticleField.defaultSide,
      );

  /// Covers [shape] with dust, clipped to its rounded corners, with the
  /// pattern shifted by [phase].
  ///
  /// [frame] is the host clock's frame number (see
  /// [MarkdownSpoilerController.fillFrame]): the first fill that names a new
  /// one renders the tile for it, every later fill of that frame reuses the
  /// image. Null asks for the tile as it is (rendered once if it never was),
  /// which is what a spoiler with motion off wants.
  void fill(Canvas canvas, RRect shape, Offset phase, {int? frame}) {
    assert(!_disposed, 'SpoilerParticleTile used after dispose.');
    _ensureRendered(frame);
    canvas
      ..save()
      ..clipRRect(shape)
      ..translate(phase.dx, phase.dy);
    // The pattern is anchored to the canvas, so drawing the rect moved back
    // by [phase] under a canvas moved forward by it leaves the rect where it
    // is and slides only the pattern.
    final bounds = shape.outerRect.shift(-phase);
    final paint = _paint;
    if (paint != null) {
      canvas.drawRect(bounds, paint);
    } else {
      _drawStillTiled(canvas, bounds);
    }
    canvas.restore();
  }

  /// The corner radius of a spoiler patch.
  static RRect shapeOf(Rect rect) =>
      RRect.fromRectAndRadius(rect, const Radius.circular(_kSpoilerRadius));

  void _ensureRendered(int? frame) {
    if (_static) return;
    final rendered = _frame;
    if (_image == null) {
      // First render: the field as it was made, whatever frame asked.
      _frame = frame;
    } else if (frame == null || frame == rendered) {
      return;
    } else {
      // A new frame: move the dust on by the frames the clock advanced
      // (at least one: a clock that restarted still moves it).
      final steps =
          rendered == null ? 1 : (frame - rendered).clamp(1, _kMaxStepFrames);
      _field.advance(steps / MarkdownSpoilerController.fillFrameRate);
      _frame = frame;
    }
    _renderImage();
  }

  void _renderImage() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)..scale(_pixels / _field.side);
    _field.paint(canvas, color);
    final picture = recorder.endRecording();
    try {
      final image = _renderer(picture, _pixels);
      _image?.dispose();
      _image = image;
      _paint = Paint()
        ..shader = ImageShader(
          image,
          TileMode.repeated,
          TileMode.repeated,
          _pixelsToDp(),
          filterQuality: FilterQuality.none,
        );
      _renderCount++;
    } on Object catch (error) {
      _unsupported = error;
      _useStillPicture();
    } finally {
      picture.dispose();
    }
  }

  /// One image pixel is `1 / devicePixelRatio` dp.
  Float64List _pixelsToDp() {
    final s = 1 / devicePixelRatio;
    return Float64List.fromList(<double>[
      s, 0, 0, 0, //
      0, s, 0, 0, //
      0, 0, 1, 0, //
      0, 0, 0, 1, //
    ]);
  }

  void _useStillPicture() {
    _static = true;
    _image?.dispose();
    _image = null;
    _paint = null;
    final recorder = PictureRecorder();
    _field.paint(Canvas(recorder), color);
    _stillPicture = recorder.endRecording();
    _renderCount++;
  }

  void _drawStillTiled(Canvas canvas, Rect bounds) {
    final picture = _stillPicture;
    if (picture == null) return;
    final side = _field.side;
    final firstX = (bounds.left / side).floor();
    final lastX = (bounds.right / side).ceil();
    final firstY = (bounds.top / side).floor();
    final lastY = (bounds.bottom / side).ceil();
    for (var x = firstX; x < lastX; x++) {
      for (var y = firstY; y < lastY; y++) {
        canvas
          ..save()
          ..translate(x * side, y * side)
          ..drawPicture(picture)
          ..restore();
      }
    }
  }

  /// Releases the image and the still picture.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _image?.dispose();
    _image = null;
    _paint = null;
    _stillPicture?.dispose();
    _stillPicture = null;
  }
}

/// The process's spoiler tiles: one per `(color, devicePixelRatio)`, shared by
/// every [MarkdownWidget] and created on the first spoiler that needs it.
///
/// A holder counts its users: [acquire] before drawing, [release] when the
/// document is revealed, its theme changes or it is disposed. The last release
/// disposes the tile, so a theme change replaces it and a screen with no hidden
/// spoiler holds no image. At most two images are alive in the process during
/// a hand-over (about 0.5 MB at a pixel ratio of 2).
@meta.internal
abstract final class SpoilerParticleTiles {
  static final Map<(int, double), ({SpoilerParticleTile tile, int users})>
      _live = <(int, double), ({SpoilerParticleTile tile, int users})>{};

  static math.Random Function() _random = math.Random.new;
  static SpoilerTileImageRenderer _renderer = _toImageSync;

  /// The tile for [color] at [devicePixelRatio], made if no one holds it, with
  /// one more user.
  static SpoilerParticleTile acquire(Color color, double devicePixelRatio) {
    final key = (color.toARGB32(), devicePixelRatio);
    final held = _live[key];
    if (held != null) {
      _live[key] = (tile: held.tile, users: held.users + 1);
      return held.tile;
    }
    final tile = SpoilerParticleTile(
      color: color,
      devicePixelRatio: devicePixelRatio,
      random: _random(),
      renderer: _renderer,
    );
    _live[key] = (tile: tile, users: 1);
    return tile;
  }

  /// Gives [tile] up; the last user disposes it.
  static void release(SpoilerParticleTile tile) {
    final key = (tile.color.toARGB32(), tile.devicePixelRatio);
    final held = _live[key];
    if (held == null || !identical(held.tile, tile)) return;
    if (held.users > 1) {
      _live[key] = (tile: tile, users: held.users - 1);
      return;
    }
    _live.remove(key);
    tile.dispose();
  }

  /// How many tiles are alive. Exposed for tests.
  @visibleForTesting
  static int get debugLiveCount => _live.length;

  /// Makes later tiles from a seeded [random] and a stand-in [renderer].
  /// Exposed for tests; undone by [debugReset].
  @visibleForTesting
  static void debugConfigure({
    math.Random Function()? random,
    SpoilerTileImageRenderer? renderer,
  }) {
    if (random != null) _random = random;
    if (renderer != null) _renderer = renderer;
  }

  /// Disposes every tile and restores the production sources. Exposed for
  /// tests, which share one process with each other.
  @visibleForTesting
  static void debugReset() {
    for (final held in _live.values) {
      held.tile.dispose();
    }
    _live.clear();
    _random = math.Random.new;
    _renderer = _toImageSync;
  }
}
