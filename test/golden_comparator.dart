import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compares against goldens next to [testFile], one set per host OS.
///
/// Text and antialiasing rasterize differently on each OS, so one set of
/// images cannot hold on every host. The set recorded on macOS sits right in
/// the key's directory (`goldens/x.png`); any other host reads and writes its
/// own beside it (`goldens/linux/x.png`). Record a set with
/// `--update-goldens` on that host (Linux: in the CI container).
///
/// Pinning [testFile] also makes the keys resolve next to the test whichever
/// entrypoint runs it: the aggregate one runs from `test/`.
class PlatformGoldenComparator extends LocalFileComparator {
  /// Compares against goldens next to [testFile], forgiving up to [tolerance]
  /// (a fraction, `0.005` is half a percent) of the pixels.
  PlatformGoldenComparator(super.testFile, {this.tolerance = 0});

  /// The fraction of differing pixels a comparison still passes with.
  final double tolerance;

  @override
  Uri getTestUri(Uri key, int? version) {
    final uri = super.getTestUri(key, version);
    if (Platform.isMacOS) return uri;
    final path = uri.path;
    final slash = path.lastIndexOf('/');
    return uri.replace(
      path: '${path.substring(0, slash + 1)}${Platform.operatingSystem}/'
          '${path.substring(slash + 1)}',
    );
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}
