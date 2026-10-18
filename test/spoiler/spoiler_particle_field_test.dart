import 'dart:math';

import 'package:flutter_md/src/render/spoiler_particle_field.dart';
import 'package:flutter_test/flutter_test.dart';

SpoilerParticleField _field([int seed = 1]) =>
    SpoilerParticleField(random: Random(seed));

/// Float32 storage rounds; compare with a hair of slack.
const _eps = 1e-3;

void main() {
  group('SpoilerParticleField', () {
    test('holds about 0.09 particles per dp squared of the tile', () {
      final field = _field();

      const area =
          SpoilerParticleField.defaultSide * SpoilerParticleField.defaultSide;
      expect(field.count, (0.09 * area).round());
      expect(field.count, inInclusiveRange(1400, 1600));
    });

    test('density scales the count', () {
      final field = SpoilerParticleField(
        random: Random(1),
        density: 0.045,
      );

      expect(field.count, closeTo(_field().count / 2, 1));
    });

    test('alpha classes are 0.3, 0.6 and 1.0, chosen about uniformly', () {
      final field = _field();
      final seen = List<int>.filled(3, 0);

      for (var i = 0; i < field.count; i++) {
        seen[field.alphaClassOf(i)]++;
      }

      expect(SpoilerParticleField.alphas, <double>[0.3, 0.6, 1.0]);
      for (final n in seen) {
        expect(n / field.count, closeTo(1 / 3, 0.06));
      }
    });

    test('strokes are 1.2 dp for alphas 0.3 and 0.6 and 1.4 dp for 1.0', () {
      expect(SpoilerParticleField.strokeWidths, <double>[1.2, 1.2, 1.4]);
      final strokes = <double, double>{
        for (var i = 0; i < 3; i++)
          SpoilerParticleField.alphas[i]: SpoilerParticleField.strokeWidths[i],
      };

      expect(strokes[0.3], 1.2);
      expect(strokes[0.6], 1.2);
      expect(strokes[1.0], 1.4);
    });

    test('speeds are 4 to 10 dp/s and lives 1 to 3 s, at start and after', () {
      final field = _field();

      void check() {
        for (var i = 0; i < field.count; i++) {
          final speed = field.velocityOf(i).distance;
          expect(speed, inInclusiveRange(4 - _eps, 10 + _eps));
          expect(field.lifeOf(i), inInclusiveRange(1 - _eps, 3 + _eps));
          expect(field.ageOf(i), lessThan(field.lifeOf(i)));
        }
      }

      check();
      for (var step = 0; step < 200; step++) {
        field.advance(1 / 30);
      }
      check();
    });

    test('particles start at every point of their life', () {
      final field = _field();
      var young = 0;
      for (var i = 0; i < field.count; i++) {
        if (field.ageOf(i) / field.lifeOf(i) < 0.5) young++;
      }

      expect(young / field.count, closeTo(0.5, 0.06));
    });

    test('advance moves a particle by velocity times time', () {
      final field = _field();
      // A particle far from every edge that outlives the step.
      final i = List<int>.generate(field.count, (i) => i).firstWhere((i) {
        final p = field.positionOf(i);
        return p.dx > 40 &&
            p.dx < 80 &&
            p.dy > 40 &&
            p.dy < 80 &&
            field.ageOf(i) + 0.2 < field.lifeOf(i);
      });
      final before = field.positionOf(i);
      final velocity = field.velocityOf(i);

      field.advance(0.2);

      final moved = field.positionOf(i) - before;
      expect(moved.dx, closeTo(velocity.dx * 0.2, 0.01));
      expect(moved.dy, closeTo(velocity.dy * 0.2, 0.01));
    });

    test('a particle that outlives its life respawns inside the tile', () {
      final field = _field();

      field.advance(SpoilerParticleField.maxLife + 0.1);

      for (var i = 0; i < field.count; i++) {
        expect(field.ageOf(i), 0);
        final p = field.positionOf(i);
        expect(p.dx, inInclusiveRange(0, field.side));
        expect(p.dy, inInclusiveRange(0, field.side));
      }
    });

    test('a particle that leaves through one edge re-enters at the other', () {
      final field = _field();

      for (var step = 0; step < 600; step++) {
        field.advance(1 / 30);
        for (var i = 0; i < field.count; i++) {
          final p = field.positionOf(i);
          expect(p.dx, inInclusiveRange(0, field.side));
          expect(p.dy, inInclusiveRange(0, field.side));
        }
      }
    });

    test('the same seed gives the same dust', () {
      final a = _field(7)..advance(0.5);
      final b = _field(7)..advance(0.5);
      final c = _field(8)..advance(0.5);

      expect(a.positionOf(10), b.positionOf(10));
      expect(a.positionOf(10), isNot(c.positionOf(10)));
    });
  });
}
