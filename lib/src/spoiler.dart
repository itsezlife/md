import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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
