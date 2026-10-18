import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart' as meta show internal;

/// The particles of one spoiler dust tile: where they are, how they move and
/// how they look. Pure simulation plus one draw call; no image, no clock.
///
/// The numbers are Android's `SpoilerEffect`, measured in the prototype (the
/// decision is recorded in the rich-text architecture notes): round points of
/// three alpha classes drifting in random directions and respawning
/// uniformly. A particle that leaves the tile re-enters on the opposite edge,
/// so the tile repeats without a seam.
///
/// Positions are in **tile dp** (a square of [side]); the caller scales the
/// canvas to pixels. Time enters only through [advance].
@meta.internal
final class SpoilerParticleField {
  /// Creates a field of `density * side * side` particles, each at a random
  /// point of its life.
  ///
  /// [random] is the only source of randomness: a seeded one makes the field,
  /// and so a golden, repeatable.
  SpoilerParticleField({
    required math.Random random,
    this.side = defaultSide,
    double density = defaultDensity,
  })  : _random = random,
        count = (density * side * side).round() {
    _x = Float32List(count);
    _y = Float32List(count);
    _vx = Float32List(count);
    _vy = Float32List(count);
    _age = Float32List(count);
    _life = Float32List(count);
    _alphaClass = Uint8List(count);
    _edgeCopies = Float32List(count * _kMaxEdgeCopies * 2);
    for (var i = 0; i < count; i++) {
      _spawn(i);
      // Staggered, so the whole field does not expire in the same frame.
      _age[i] = _random.nextDouble() * _life[i];
    }
  }

  /// Side of the square tile in dp (Android: 100-150, floor 80).
  static const double defaultSide = 128;

  /// Particles per dp squared: between Android's per-entity cap
  /// (`width / 6 dp * 30`, cap 150) and its tile factory, about 1500 per
  /// default tile.
  static const double defaultDensity = 0.09;

  /// Alpha of each class; a particle picks a class uniformly.
  static const List<double> alphas = <double>[0.3, 0.6, 1.0];

  /// Stroke width in dp of each alpha class (1.2 for 0.3 and 0.6, 1.4 for 1.0).
  static const List<double> strokeWidths = <double>[1.2, 1.2, 1.4];

  /// Slowest and fastest drift in dp per second.
  static const double minSpeed = 4;

  /// See [minSpeed].
  static const double maxSpeed = 10;

  /// Shortest and longest life in seconds.
  static const double minLife = 1;

  /// See [minLife].
  static const double maxLife = 3;

  /// Side of the square tile in dp.
  final double side;

  /// How many particles the tile holds.
  final int count;

  final math.Random _random;
  late final Float32List _x;
  late final Float32List _y;
  late final Float32List _vx;
  late final Float32List _vy;
  late final Float32List _age;
  late final Float32List _life;
  late final Uint8List _alphaClass;

  /// Scratch for [paint]: a point plus the copies that wrap past an edge.
  late final Float32List _edgeCopies;

  /// Position in tile dp of particle [i].
  Offset positionOf(int i) => Offset(_x[i], _y[i]);

  /// Drift of particle [i] in dp per second.
  Offset velocityOf(int i) => Offset(_vx[i], _vy[i]);

  /// Seconds particle [i] lives for, from its respawn.
  double lifeOf(int i) => _life[i];

  /// Seconds particle [i] has lived.
  double ageOf(int i) => _age[i];

  /// Index into [alphas] and [strokeWidths] of particle [i].
  int alphaClassOf(int i) => _alphaClass[i];

  void _spawn(int i) {
    final angle = _random.nextDouble() * 2 * math.pi;
    final speed = minSpeed + _random.nextDouble() * (maxSpeed - minSpeed);
    _x[i] = _random.nextDouble() * side;
    _y[i] = _random.nextDouble() * side;
    _vx[i] = math.cos(angle) * speed;
    _vy[i] = math.sin(angle) * speed;
    _life[i] = minLife + _random.nextDouble() * (maxLife - minLife);
    _alphaClass[i] = _random.nextInt(alphas.length);
    _age[i] = 0;
  }

  /// Moves every particle on by [seconds]; one that outlived its life
  /// respawns somewhere else in the tile.
  void advance(double seconds) {
    for (var i = 0; i < count; i++) {
      _age[i] += seconds;
      if (_age[i] >= _life[i]) {
        _spawn(i);
        continue;
      }
      // `%` on a double is non-negative, so a particle leaving through one
      // edge comes back through the other.
      _x[i] = (_x[i] + _vx[i] * seconds) % side;
      _y[i] = (_y[i] + _vy[i] * seconds) % side;
    }
  }

  /// Draws the field into [canvas], in tile dp, in one `drawRawPoints` per
  /// alpha class.
  ///
  /// [color] is the text colour; its own alpha scales each class. A point
  /// closer to an edge than its radius is drawn again on the far side, so the
  /// repeated tile shows whole dots at the seam.
  void paint(Canvas canvas, Color color) {
    for (var cls = 0; cls < alphas.length; cls++) {
      final radius = strokeWidths[cls] / 2;
      var n = 0;
      for (var i = 0; i < count; i++) {
        if (_alphaClass[i] != cls) continue;
        n = _writeWithEdgeCopies(n, _x[i], _y[i], radius);
      }
      if (n == 0) continue;
      canvas.drawRawPoints(
        PointMode.points,
        Float32List.sublistView(_edgeCopies, 0, n * 2),
        Paint()
          ..color = color.withValues(alpha: color.a * alphas[cls])
          ..strokeWidth = strokeWidths[cls]
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Writes the point and its wrapped copies at point index [n]; returns the
  /// next free index. The scratch is sized for the worst case (a corner).
  int _writeWithEdgeCopies(int n, double x, double y, double radius) {
    final wrapX = x < radius
        ? side
        : x > side - radius
            ? -side
            : 0.0;
    final wrapY = y < radius
        ? side
        : y > side - radius
            ? -side
            : 0.0;
    n = _write(n, x, y);
    if (wrapX != 0) n = _write(n, x + wrapX, y);
    if (wrapY != 0) n = _write(n, x, y + wrapY);
    if (wrapX != 0 && wrapY != 0) n = _write(n, x + wrapX, y + wrapY);
    return n;
  }

  int _write(int n, double x, double y) {
    _edgeCopies[n * 2] = x;
    _edgeCopies[n * 2 + 1] = y;
    return n + 1;
  }
}

/// A point has at most four images: itself and one wrap per axis.
const int _kMaxEdgeCopies = 4;
