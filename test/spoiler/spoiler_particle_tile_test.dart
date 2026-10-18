import 'dart:math';
import 'dart:ui';

import 'package:flutter_md/src/render/spoiler_particle_tile.dart';
import 'package:flutter_test/flutter_test.dart';

const _ink = Color(0xFF0D47A1);
const _paper = Color(0xFFFFFFFF);

/// A renderer that counts and otherwise renders for real.
class _CountingRenderer {
  int calls = 0;

  Image call(Picture picture, int size) {
    calls++;
    return picture.toImageSync(size, size);
  }
}

void _fillOnce(
  SpoilerParticleTile tile, {
  int? frame,
  int spoilers = 1,
}) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  for (var i = 0; i < spoilers; i++) {
    tile.fill(
      canvas,
      SpoilerParticleTile.shapeOf(Rect.fromLTWH(10, 10.0 + i * 20, 90, 16)),
      SpoilerParticleTile.phaseOf(i),
      frame: frame,
    );
  }
  recorder.endRecording().dispose();
}

void main() {
  tearDown(SpoilerParticleTiles.debugReset);

  group('SpoilerParticleTile', () {
    test('renders once per frame however many spoilers fill from it', () {
      final renderer = _CountingRenderer();
      final tile = SpoilerParticleTile(
        color: _ink,
        devicePixelRatio: 2,
        random: Random(1),
        renderer: renderer.call,
      );
      addTearDown(tile.dispose);

      _fillOnce(tile, frame: 0, spoilers: 20);
      expect(renderer.calls, 1);
      _fillOnce(tile, frame: 0, spoilers: 20);
      expect(renderer.calls, 1);

      _fillOnce(tile, frame: 1, spoilers: 20);
      _fillOnce(tile, frame: 1, spoilers: 5);
      expect(renderer.calls, 2);
      _fillOnce(tile, frame: 2, spoilers: 1);
      expect(renderer.calls, 3);
      expect(tile.debugRenderCount, 3);
    });

    test('renders at the device pixel ratio', () {
      Size? asked;
      final tile = SpoilerParticleTile(
        color: _ink,
        devicePixelRatio: 2.5,
        random: Random(1),
        renderer: (picture, size) {
          asked = Size(size.toDouble(), size.toDouble());
          return picture.toImageSync(size, size);
        },
      );
      addTearDown(tile.dispose);

      _fillOnce(tile, frame: 0);

      expect(asked, const Size(320, 320));
    });

    test('a frame moves the dust on; the same frame does not', () {
      final tile = SpoilerParticleTile(
        color: _ink,
        devicePixelRatio: 1,
        random: Random(1),
      );
      addTearDown(tile.dispose);
      _fillOnce(tile, frame: 0);
      final start = tile.debugField.positionOf(3);

      _fillOnce(tile, frame: 0);
      expect(tile.debugField.positionOf(3), start);

      _fillOnce(tile, frame: 3);
      expect(tile.debugField.positionOf(3), isNot(start));
    });

    test('a stalled clock moves the dust by a bounded step', () {
      final a = SpoilerParticleTile(
        color: _ink,
        devicePixelRatio: 1,
        random: Random(1),
      );
      final b = SpoilerParticleTile(
        color: _ink,
        devicePixelRatio: 1,
        random: Random(1),
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      _fillOnce(a, frame: 0);
      _fillOnce(b, frame: 0);

      _fillOnce(a, frame: 8);
      _fillOnce(b, frame: 8000);

      expect(a.debugField.positionOf(5), b.debugField.positionOf(5));
    });

    test('a null frame renders once and never again', () {
      final renderer = _CountingRenderer();
      final tile = SpoilerParticleTile(
        color: _ink,
        devicePixelRatio: 2,
        random: Random(1),
        renderer: renderer.call,
      );
      addTearDown(tile.dispose);

      for (var i = 0; i < 5; i++) {
        _fillOnce(tile);
      }

      expect(renderer.calls, 1);
    });

    test('keeps the previous image only until the next is made', () {
      final images = <Image>[];
      final tile = SpoilerParticleTile(
        color: _ink,
        devicePixelRatio: 1,
        random: Random(1),
        renderer: (picture, size) {
          final image = picture.toImageSync(size, size);
          images.add(image);
          return image;
        },
      );
      addTearDown(tile.dispose);

      _fillOnce(tile, frame: 0);
      _fillOnce(tile, frame: 1);
      _fillOnce(tile, frame: 2);

      expect(images, hasLength(3));
      expect(images[0].debugDisposed, isTrue);
      expect(images[1].debugDisposed, isTrue);
      expect(images[2].debugDisposed, isFalse);

      tile.dispose();
      expect(images[2].debugDisposed, isTrue);
    });

    test('without toImageSync the tile is static and nothing is thrown', () {
      var calls = 0;
      final tile = SpoilerParticleTile(
        color: _ink,
        devicePixelRatio: 2,
        random: Random(1),
        renderer: (picture, size) {
          calls++;
          throw UnsupportedError('toImageSync');
        },
      );
      addTearDown(tile.dispose);

      expect(() => _fillOnce(tile, frame: 0, spoilers: 3), returnsNormally);
      expect(tile.isStatic, isTrue);
      expect(tile.unsupported, isA<UnsupportedError>());

      for (var frame = 1; frame < 6; frame++) {
        _fillOnce(tile, frame: frame, spoilers: 3);
      }
      // It asked once, was refused, and never asked again.
      expect(calls, 1);
      expect(tile.debugRenderCount, 1);
    });

    test('both forms paint dust inside the patch and none outside', () async {
      Future<List<int>> shot(SpoilerTileImageRenderer renderer) async {
        final tile = SpoilerParticleTile(
          color: _ink,
          devicePixelRatio: 1,
          random: Random(4),
          renderer: renderer,
        );
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder)
          ..drawRect(
            const Rect.fromLTWH(0, 0, 100, 40),
            Paint()..color = _paper,
          );
        tile.fill(
          canvas,
          SpoilerParticleTile.shapeOf(const Rect.fromLTWH(4, 4, 92, 32)),
          Offset.zero,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 40);
        final bytes = await image.toByteData();
        image.dispose();
        picture.dispose();
        tile.dispose();
        return bytes!.buffer.asUint8List().toList();
      }

      // Pixels (x, y) other than paper, as indices into the RGBA bytes.
      Set<(int, int)> inked(List<int> rgba) => <(int, int)>{
            for (var i = 0; i < rgba.length; i += 4)
              if (rgba[i] != 0xFF || rgba[i + 1] != 0xFF)
                ((i ~/ 4) % 100, (i ~/ 4) ~/ 100),
          };

      final live = inked(await shot((p, s) => p.toImageSync(s, s)));
      final still = inked(
        await shot((picture, size) => throw UnsupportedError('x')),
      );

      for (final dust in [live, still]) {
        expect(dust, isNotEmpty);
        // The patch is (4, 4) to (96, 36), rounded at the corners.
        expect(
          dust.every((p) => p.$1 >= 4 && p.$1 < 96 && p.$2 >= 4 && p.$2 < 36),
          isTrue,
        );
        expect(dust.contains((4, 4)), isFalse, reason: 'the corner is clipped');
      }
      // Both draw the same field; the live one samples it from an image.
      expect(live.length, closeTo(still.length, still.length * 0.2));
    });

    test('phases differ between neighbouring spoilers and stay in the tile',
        () {
      final phases = <Offset>{
        for (var i = 0; i < 128; i++) SpoilerParticleTile.phaseOf(i),
      };

      expect(phases, hasLength(128));
      for (final p in phases) {
        expect(p.dx, inInclusiveRange(0, 127));
        expect(p.dy, inInclusiveRange(0, 127));
      }
    });
  });

  group('SpoilerParticleTiles', () {
    test('one tile per colour and pixel ratio', () {
      final a = SpoilerParticleTiles.acquire(_ink, 2);
      final b = SpoilerParticleTiles.acquire(_ink, 2);
      final otherColor = SpoilerParticleTiles.acquire(_paper, 2);
      final otherRatio = SpoilerParticleTiles.acquire(_ink, 3);

      expect(b, same(a));
      expect(otherColor, isNot(same(a)));
      expect(otherRatio, isNot(same(a)));
      expect(SpoilerParticleTiles.debugLiveCount, 3);
    });

    test('the last release disposes the tile; the next acquire makes a new',
        () {
      final a = SpoilerParticleTiles.acquire(_ink, 2);
      SpoilerParticleTiles.acquire(_ink, 2);

      SpoilerParticleTiles.release(a);
      expect(a.debugDisposed, isFalse);
      SpoilerParticleTiles.release(a);
      expect(a.debugDisposed, isTrue);
      expect(SpoilerParticleTiles.debugLiveCount, 0);

      expect(SpoilerParticleTiles.acquire(_ink, 2), isNot(same(a)));
    });

    test('releasing a tile the registry does not hold is a no-op', () {
      final held = SpoilerParticleTiles.acquire(_ink, 2);
      final stranger = SpoilerParticleTile(color: _ink, devicePixelRatio: 2);
      addTearDown(stranger.dispose);

      SpoilerParticleTiles.release(stranger);

      expect(held.debugDisposed, isFalse);
      expect(SpoilerParticleTiles.debugLiveCount, 1);
    });
  });
}
