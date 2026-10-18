import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart' as meta show internal;

/// Which documents have their `||spoilers||` revealed, and where the reveal
/// started.
///
/// Pass one to [MarkdownWidget.spoilerController] (it is keyed by
/// [MarkdownWidget.documentId], like [MarkdownSelectionController]). A document
/// whose id is not revealed paints its spoiler runs hidden: glyphs keep their
/// place but are not drawn, and a fill covers them. A widget with no
/// controller (or no document id) has nowhere to keep that state and paints
/// spoilers as ordinary text.
///
/// The scope is the **whole document**: one tap reveals every spoiler of it at
/// once, as every Telegram client does. The state lives here, not in a widget:
/// a remount (an edit-morph twin, list virtualisation) finds the document still
/// revealed, and a second widget showing the same document (a quote of it)
/// reveals in the same frame. It is in memory only and never persisted.
///
/// Nothing re-hides a document on its own. In particular a selection dismissal
/// does not (that is an iOS-only behaviour, and it would fight the engine's
/// text selection); [hide] exists for a host that decides otherwise, or that
/// forgets a document.
///
/// **Taps.** A tap on a hidden spoiler reveals its document, from the tap
/// point, and is absorbed: a link or embed under the spoiler does not fire. The
/// host tunes that with two settings the controller holds for every body that
/// shares it. [tapReveals] turns the reveal off while the host takes taps for
/// itself (a message selection, where a tap toggles the row and Android leaves
/// the spoiler hidden); the tap is still absorbed. [tapTimeout] bounds how long
/// the press may last: a press held past it is a long press, which belongs to
/// the host's own gesture (the message menu, a selection), so its release
/// reveals nothing. Both are read when the pointer comes up.
///
/// **The dust clock.** Hidden spoilers are covered by moving particles. The
/// package owns no clock for them: the host calls [advance] with a monotonic
/// time (the shared playback clock of the app, a `Ticker`'s elapsed) and every
/// hidden spoiler paints the next frame. [wantsTicks] says whether anything
/// is listening, so the host can stop its clock while no hidden spoiler is
/// mounted. Without [advance] the dust stands still; the same happens when
/// [animate] is off.
///
/// Kept apart from [MarkdownSelectionController]: that one anchors a selection
/// over a registry of models, this one holds one bit per document, and the two
/// change for different reasons.
class MarkdownSpoilerController extends ChangeNotifier {
  /// Creates a controller with every document hidden.
  ///
  /// [animate] is the host's motion setting: when false a reveal is immediate
  /// (no ripple) and the fill stays static.
  MarkdownSpoilerController({bool animate = true}) : _animate = animate;

  /// How long the reveal ripple takes to cover the document's spoilers.
  static const Duration revealDuration = Duration(milliseconds: 300);

  /// How many times a second the dust moves (Android: 30). [advance] may be
  /// called more often; frames in between are skipped.
  static const int fillFrameRate = 30;

  final Map<Object, Offset?> _revealed = <Object, Offset?>{};

  bool _animate;

  /// Whether spoilers may move: the reveal ripple runs and the fill animates.
  ///
  /// Turn it off for the host's reduced-motion setting. A widget also stays
  /// still when the platform asks for it ([MediaQueryData.disableAnimations]),
  /// whatever this says.
  bool get animate => _animate;
  set animate(bool value) {
    if (_animate == value) return;
    _animate = value;
    notifyListeners();
  }

  bool _tapReveals = true;

  /// Whether a tap on a hidden spoiler reveals its document. True by default.
  ///
  /// A host in a mode where a tap means something else (a message selection)
  /// sets it false. The tap is still absorbed, so nothing under the spoiler
  /// fires; only the reveal is skipped. [reveal] and [hide] are not affected,
  /// and a selection that enters a spoiler still reveals through the host.
  bool get tapReveals => _tapReveals;
  set tapReveals(bool value) {
    if (_tapReveals == value) return;
    _tapReveals = value;
    // The hand cursor over a hidden spoiler follows it from the next move.
    notifyListeners();
  }

  /// The longest press that still counts as a tap on a hidden spoiler; a press
  /// held longer reveals nothing. [kLongPressTimeout] by default, the point
  /// where Android (`ViewConfiguration.getLongPressTimeout`) and Qt touch
  /// (`startDragTime`) start a long press. Telegram iOS starts it at 0.3 s.
  /// Null puts no limit on a hold, the desktop mouse click.
  ///
  /// Measured on the pointer's own timestamps, so it holds under a stalled
  /// frame; a host that changes it does not have to rebuild anything.
  Duration? tapTimeout = kLongPressTimeout;

  // --- Dust clock -----------------------------------------------------------

  final ValueNotifier<int> _fillFrames = ValueNotifier<int>(0);
  final ValueNotifier<bool> _wantsTicks = ValueNotifier<bool>(false);
  Duration _elapsed = Duration.zero;
  int _fillSurfaces = 0;
  bool _disposed = false;

  /// Moves the dust to [elapsed], a time that only grows (a `Ticker`'s
  /// elapsed, or the shared clock of the host).
  ///
  /// The dust moves at [fillFrameRate]: a call that stays within the frame
  /// already shown changes nothing, so a 60 fps clock may call it every frame.
  /// With no hidden spoiler mounted nobody listens and it costs one
  /// comparison.
  void advance(Duration elapsed) {
    _elapsed = elapsed;
    _fillFrames.value = fillFrameAt(elapsed);
  }

  /// The frame number of [elapsed]: the dust of two times in one frame is the
  /// same dust.
  static int fillFrameAt(Duration elapsed) =>
      elapsed.inMicroseconds * fillFrameRate ~/ Duration.microsecondsPerSecond;

  /// The time of the last [advance].
  Duration get elapsed => _elapsed;

  /// The dust frame the last [advance] arrived at.
  int get fillFrame => _fillFrames.value;

  /// Changes with every new dust frame; the hidden spoilers repaint on it.
  @meta.internal
  ValueListenable<int> get fillFrames => _fillFrames;

  /// Whether a hidden spoiler is mounted that would move on the next frame.
  ///
  /// False when none is, when [animate] is off, and for a spoiler the platform
  /// keeps still. A host runs its clock only while this is true, and calls
  /// [advance] from it.
  ValueListenable<bool> get wantsTicks => _wantsTicks;

  /// A hidden spoiler that moves has been mounted. Pair with
  /// [removeFillSurface].
  @meta.internal
  void addFillSurface() {
    _fillSurfaces++;
    _wantsTicks.value = true;
  }

  /// The counterpart of [addFillSurface].
  @meta.internal
  void removeFillSurface() {
    assert(_fillSurfaces > 0, 'removeFillSurface without addFillSurface.');
    _fillSurfaces--;
    // A surface can outlive the controller by a frame at teardown.
    if (!_disposed) _wantsTicks.value = _fillSurfaces > 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _fillFrames.dispose();
    _wantsTicks.dispose();
    super.dispose();
  }

  /// Whether the spoilers of document [documentId] are revealed.
  bool isRevealed(Object documentId) => _revealed.containsKey(documentId);

  /// The global position the reveal of [documentId] started from, or null when
  /// the document is hidden or was revealed without a position (a selection
  /// that entered a spoiler).
  ///
  /// Global, not widget-local, so every widget that shows the document can
  /// start its ripple from the same screen point.
  Offset? revealOriginOf(Object documentId) => _revealed[documentId];

  /// Reveals the spoilers of [documentId], rippling out from the global point
  /// [origin] when given. Returns whether anything changed; revealing a
  /// revealed document is a no-op and keeps its first origin.
  bool reveal(Object documentId, {Offset? origin}) {
    if (_revealed.containsKey(documentId)) return false;
    _revealed[documentId] = origin;
    notifyListeners();
    return true;
  }

  /// Hides the spoilers of [documentId] again. Returns whether anything
  /// changed.
  bool hide(Object documentId) {
    if (!_revealed.containsKey(documentId)) return false;
    _revealed.remove(documentId);
    notifyListeners();
    return true;
  }
}
