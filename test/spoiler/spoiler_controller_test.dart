import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkdownSpoilerController', () {
    test('a document is hidden until it is revealed', () {
      final controller = MarkdownSpoilerController();
      addTearDown(controller.dispose);

      expect(controller.isRevealed('a'), isFalse);
      controller.reveal('a');
      expect(controller.isRevealed('a'), isTrue);
    });

    test('revealing document A leaves document B hidden', () {
      final controller = MarkdownSpoilerController();
      addTearDown(controller.dispose);

      controller.reveal('a');

      expect(controller.isRevealed('a'), isTrue);
      expect(controller.isRevealed('b'), isFalse);
    });

    test('the reveal origin is kept per document', () {
      final controller = MarkdownSpoilerController();
      addTearDown(controller.dispose);

      controller
        ..reveal('a', origin: const Offset(10, 20))
        ..reveal('b');

      expect(controller.revealOriginOf('a'), const Offset(10, 20));
      expect(controller.revealOriginOf('b'), isNull);
      expect(controller.revealOriginOf('c'), isNull);
    });

    test('reveal notifies once and is idempotent', () {
      final controller = MarkdownSpoilerController();
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);

      expect(controller.reveal('a', origin: const Offset(1, 1)), isTrue);
      expect(controller.reveal('a', origin: const Offset(9, 9)), isFalse);

      expect(notified, 1);
      expect(controller.revealOriginOf('a'), const Offset(1, 1));
    });

    test('hide forgets a document and notifies only when it changed', () {
      final controller = MarkdownSpoilerController();
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);

      controller.hide('a');
      expect(notified, 0);

      controller.reveal('a', origin: const Offset(1, 1));
      controller.hide('a');

      expect(controller.isRevealed('a'), isFalse);
      expect(controller.revealOriginOf('a'), isNull);
      expect(notified, 2);
    });

    test('animate defaults on and notifies when it changes', () {
      final controller = MarkdownSpoilerController();
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);

      expect(controller.animate, isTrue);
      controller.animate = true;
      expect(notified, 0);
      controller.animate = false;
      expect(controller.animate, isFalse);
      expect(notified, 1);
    });
  });
}
