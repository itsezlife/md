//ignore_for_file: unnecessary_import

import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show MouseTrackerAnnotation;
import 'package:meta/meta.dart' as meta show internal;

import '../inline_embed.dart';
import '../markdown.dart';
import '../selection.dart';
import '../spoiler.dart';
import '../theme.dart';
import 'block_painter.dart';
import 'markdown_painter.dart';
import 'spoiler_phase.dart';

/// Default color used to paint the selection highlight under the glyphs.
const Color _kSelectionColor = Color(0x552196F3);

@meta.internal
class MarkdownRenderObject extends RenderBox
    implements MarkdownSelectionSurface, MouseTrackerAnnotation {
  MarkdownRenderObject({
    required Markdown markdown,
    required MarkdownThemeData theme,
    MarkdownCursorResolver? cursorResolver,
    MarkdownInlineEmbedResolver? embedResolver,
    double devicePixelRatio = 1.0,
  })  : _theme = theme,
        _cursorResolver = cursorResolver,
        _painter = MarkdownPainter(
          markdown: markdown,
          theme: theme,
          embedResolver: embedResolver,
          devicePixelRatio: devicePixelRatio,
        ) {
    _painter.onPaintersRebuilt = _onPaintersRebuilt;
  }

  /// Painter for rendering markdown content.
  final MarkdownPainter _painter;

  MarkdownThemeData _theme;
  MarkdownCursorResolver? _cursorResolver;

  MarkdownCursorResolver? get _effectiveCursorResolver =>
      _cursorResolver ?? _theme.cursorResolver;

  /// The selection controller this render object participates in, if any.
  MarkdownSelectionController? _controller;

  /// The stable document id used to anchor selection positions.
  Object? _documentId;

  final Paint _highlightPaint = Paint()..color = _kSelectionColor;

  // Selection-handle leader layers pushed during paint so native handles
  // (drawn by the scope's SelectionOverlay) follow the content as it scrolls.
  // [LayerHandle] keeps a single LeaderLayer per link across paints (matches
  // RenderEditable) so stale leaders cannot linger and double-up chrome.
  LayerLink? _startHandleLink;
  Offset? _startHandleLocal;
  LayerLink? _endHandleLink;
  Offset? _endHandleLocal;
  final LayerHandle<LeaderLayer> _startHandleLayer = LayerHandle<LeaderLayer>();
  final LayerHandle<LeaderLayer> _endHandleLayer = LayerHandle<LeaderLayer>();

  /// Touch pan over a [HorizontallyPannableBlock]. Mouse / stylus / trackpad
  /// keep selection TapAndPan (or pointer scroll); a competing HorizontalDrag
  /// on those kinds would steal cell selection.
  HorizontalDragGestureRecognizer? _horizontalPan;
  HorizontallyPannableBlock? _panningBlock;

  /// Ballistic fling after a touch drag ends.
  Ticker? _ballisticTicker;
  Simulation? _ballisticSimulation;
  HorizontallyPannableBlock? _ballisticBlock;
  Duration _ballisticStart = Duration.zero;

  // --- Spoilers ---

  /// Which documents are revealed, and the id this surface is one of. Null
  /// when the widget has no controller or no document id: spoilers then paint
  /// as ordinary text.
  MarkdownSpoilerController? _spoilerController;
  Object? _spoilerDocumentId;

  /// The platform asked for reduced motion; the controller's own switch is read
  /// live.
  bool _reduceMotion = false;

  /// Drives the reveal ripple. A raw [Ticker] like the fling's: muted with
  /// [TickerMode], and a muted ripple is finished rather than left half-drawn.
  Ticker? _rippleTicker;

  /// A pointer that went down on a hidden spoiler and has not come up yet.
  ({int pointer, Offset local})? _spoilerTap;

  /// Whether [paint] will push a start and/or end [LeaderLayer] this frame.
  ///
  /// Drives [alwaysNeedsCompositing]; keep it in lockstep with the conditions
  /// in [paint] or a leader can be pushed without a composited layer for it.
  bool get _pushesHandleLeaderLayers =>
      (_startHandleLink != null && _startHandleLocal != null) ||
      (_endHandleLink != null && _endHandleLocal != null);

  /// Mirrors [TickerMode.valuesOf(context).enabled] from the [MarkdownWidget]
  /// element. Offstage / disabled routes mute the fling ticker without a
  /// State [TickerProvider].
  bool _tickerModeEnabled = true;

  /// Syncs ambient [TickerMode] from the widget. Stops an in-flight fling when
  /// the mode turns off.
  @meta.internal
  void setTickerModeEnabled(bool enabled) {
    if (_tickerModeEnabled == enabled) return;
    _tickerModeEnabled = enabled;
    _ballisticTicker?.muted = !_tickerModeEnabled || !attached;
    _rippleTicker?.muted = !_tickerModeEnabled || !attached;
    if (!enabled) {
      _stopBallistic();
      _ballisticTicker?.stop();
      _finishRipple();
    }
  }

  /// Whether this surface currently owns a start and/or end handle leader.
  @visibleForTesting
  bool get debugHasSelectionHandleLeaders => _pushesHandleLeaderLayers;

  void _onSelectionChange() {
    if (!_disposed) markNeedsPaint();
  }

  bool _disposed = false;

  void _onPaintersRebuilt() {
    _stopHorizontalPanGesture();
  }

  void _stopHorizontalPanGesture() {
    _panningBlock = null;
    _stopBallistic();
  }

  void _stopBallistic() {
    _ballisticTicker?.stop();
    _ballisticSimulation = null;
    _ballisticBlock = null;
  }

  void _attachController({Markdown? markdown}) {
    final controller = _controller;
    final id = _documentId;
    if (controller == null || id == null) return;
    controller.addListener(_onSelectionChange);
    if (attached) {
      // Mounted surfaces must exist in the registry so [rangeFor] / ordering
      // can resolve them. AppMarkdown also putDocuments; this heals races where
      // the RO attaches before (or without) an app-level registration.
      //
      // [markdown] is the model of the *incoming* document when a recycled
      // element is rewired onto another id — [_painter] still holds the
      // outgoing one until [update] runs.
      controller.putDocument(id, markdown ?? _painter.markdown);
      controller.attachSurface(this);
    }
  }

  void _detachController() {
    final controller = _controller;
    if (controller == null) return;
    controller.removeListener(_onSelectionChange);
    controller.detachSurface(this);
    _clearSelectionHandleLayers();
  }

  /// Wires (or rewires) this render object to a selection [controller] under
  /// [documentId]. Passing a null controller makes it non-selectable (inert).
  ///
  /// [markdown] is the model the *incoming* [documentId] should be healed with.
  /// It matters when a list recycles this render object from one message onto
  /// another: the painter still holds the outgoing model at that point, and
  /// registering it under the incoming id would overwrite that document's
  /// registry entry with the wrong body.
  ///
  /// Must run **before** [update] on a rewire so the registry write that
  /// [update] performs lands on the new id.
  @meta.internal
  void updateSelection(
    MarkdownSelectionController? controller,
    Object? documentId, {
    Markdown? markdown,
  }) {
    if (identical(controller, _controller) && documentId == _documentId) {
      _painter.bindHorizontalPanStore(controller, documentId);
      return;
    }
    _detachController();
    _controller = controller;
    _documentId = documentId;
    _painter.bindHorizontalPanStore(controller, documentId);
    _attachController(markdown: markdown);
    if (attached) {
      // Rebind clears local pans — relayout so painters restore from the new
      // store (or zero) instead of keeping a stale live scrollOffset.
      markNeedsLayout();
      markNeedsCompositingBitsUpdate();
      markNeedsPaint();
    }
  }

  // --- Spoilers ---

  /// Wires (or rewires) this surface to the [controller] that says whether
  /// [documentId] is revealed. A null controller or id leaves spoilers painted
  /// as ordinary text.
  ///
  /// A document that is already revealed when this runs (a remount, a second
  /// widget of it) shows revealed at once; only a reveal that happens while
  /// mounted ripples.
  @meta.internal
  void updateSpoilers(
    MarkdownSpoilerController? controller,
    Object? documentId, {
    bool reduceMotion = false,
  }) {
    _reduceMotion = reduceMotion;
    final bound = controller != null && documentId != null;
    final nextController = bound ? controller : null;
    final nextId = bound ? documentId : null;
    if (identical(nextController, _spoilerController) &&
        nextId == _spoilerDocumentId) {
      return;
    }
    _spoilerController?.removeListener(_onSpoilerChange);
    _stopRipple();
    _spoilerController = nextController;
    _spoilerDocumentId = nextId;
    nextController?.addListener(_onSpoilerChange);
    _syncSpoilerPhase(animate: false);
  }

  void _onSpoilerChange() {
    if (_disposed) return;
    _syncSpoilerPhase(animate: true);
  }

  /// Whether a reveal may move: the host allows it, the platform does not ask
  /// for less, and there is a clock to run it on.
  bool get _spoilerMotion =>
      (_spoilerController?.animate ?? true) &&
      !_reduceMotion &&
      _tickerModeEnabled &&
      attached;

  void _syncSpoilerPhase({required bool animate}) {
    final controller = _spoilerController;
    final id = _spoilerDocumentId;
    if (controller == null || id == null) {
      _stopRipple();
      _setSpoilerPhase(const SpoilerPhase$Revealed());
      return;
    }
    if (!controller.isRevealed(id)) {
      _stopRipple();
      _setSpoilerPhase(const SpoilerPhase$Hidden());
      return;
    }
    // Already rippling or revealed: nothing more to do.
    if (_painter.spoilerPhase is! SpoilerPhase$Hidden) return;
    if (animate && _spoilerMotion && _painter.hasSpoilers) {
      _startRipple(controller.revealOriginOf(id));
    } else {
      _setSpoilerPhase(const SpoilerPhase$Revealed());
    }
  }

  void _setSpoilerPhase(SpoilerPhase phase) {
    if (_painter.setSpoilerPhase(phase) && attached && !_disposed) {
      markNeedsPaint();
    }
  }

  void _startRipple(Offset? globalOrigin) {
    final ticker = _rippleTicker ??= Ticker(
      _onRippleTick,
      debugLabel: 'md.spoiler.reveal',
    );
    ticker.muted = !_tickerModeEnabled || !attached;
    if (ticker.isActive) ticker.stop();
    _rippleOrigin = globalOrigin == null ? null : globalToLocal(globalOrigin);
    _setSpoilerPhase(
        SpoilerPhase$Revealing(origin: _rippleOrigin, progress: 0));
    ticker.start();
  }

  Offset? _rippleOrigin;

  void _onRippleTick(Duration elapsed) {
    final t = elapsed.inMicroseconds /
        MarkdownSpoilerController.revealDuration.inMicroseconds;
    if (t >= 1.0) {
      _finishRipple();
      return;
    }
    _setSpoilerPhase(
      SpoilerPhase$Revealing(
        origin: _rippleOrigin,
        progress: Curves.easeOut.transform(t),
      ),
    );
  }

  void _stopRipple() {
    _rippleTicker?.stop();
    _rippleOrigin = null;
  }

  /// Ends a running ripple on the revealed picture.
  void _finishRipple() {
    if (_painter.spoilerPhase is! SpoilerPhase$Revealing) return;
    _stopRipple();
    _setSpoilerPhase(const SpoilerPhase$Revealed());
  }

  /// Turns a tap on a hidden spoiler into a reveal. Returns whether [event]
  /// was consumed: a pointer that went down on a hidden spoiler is not
  /// forwarded to the blocks at all, so a link or embed under the spoiler does
  /// not fire - the tap reveals instead, as in Telegram iOS. The same tap after
  /// the reveal reaches the link.
  bool _handleSpoilerTap(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        // Only the primary button taps; a secondary click opens the host's
        // context menu and must not unveil what is under it.
        if (_spoilerController == null ||
            event.buttons & kPrimaryButton == 0 ||
            !_painter.hiddenSpoilerAt(event.localPosition)) {
          _spoilerTap = null;
          return false;
        }
        _spoilerTap = (pointer: event.pointer, local: event.localPosition);
        return true;
      case PointerUpEvent():
        final tap = _spoilerTap;
        if (tap == null || tap.pointer != event.pointer) return false;
        _spoilerTap = null;
        final slop = computePanSlop(event.kind, null);
        if ((event.localPosition - tap.local).distance <= slop &&
            _painter.hiddenSpoilerAt(event.localPosition)) {
          _spoilerController?.reveal(
            _spoilerDocumentId!,
            origin: event.position,
          );
        }
        return true;
      case PointerCancelEvent():
        _spoilerTap = null;
        return false;
      default:
        return false;
    }
  }

  // --- MarkdownSelectionSurface ---

  @override
  Object get documentId => _documentId!;

  @override
  Rect get globalBounds => localToGlobal(Offset.zero) & size;

  @override
  MarkdownPosition? positionForGlobal(Offset globalPosition) {
    final hit = hitForGlobal(globalPosition);
    return hit?.$1;
  }

  @override
  (MarkdownPosition, TextAffinity)? hitForGlobal(Offset globalPosition) {
    final id = _documentId;
    if (id == null) return null;
    final local = globalToLocal(globalPosition);
    final hit = _painter.positionAndAffinityForLocal(local);
    if (hit == null) return null;
    return (
      MarkdownPosition(
        documentId: id,
        blockIndex: hit.$1,
        offset: hit.$2,
      ),
      hit.$3,
    );
  }

  @override
  bool hitsSelectableGlyphs(Offset globalPosition) {
    if (_documentId == null) return false;
    final bounds = globalBounds;
    if (bounds.isEmpty || !bounds.contains(globalPosition)) return false;
    return _painter.isSelectableAtLocal(globalToLocal(globalPosition));
  }

  @override
  bool isLinkAtGlobal(Offset globalPosition) {
    if (_documentId == null) return false;
    final bounds = globalBounds;
    if (bounds.isEmpty || !bounds.contains(globalPosition)) return false;
    return _painter.isLinkAtLocal(globalToLocal(globalPosition));
  }

  @override
  Rect? caretRectFor(MarkdownPosition position, TextAffinity affinity) {
    final id = _documentId;
    if (id == null || position.documentId != id) return null;
    return _painter.caretRectFor(
        position.blockIndex, position.offset, affinity);
  }

  @override
  (int, int, int)? wordBoundaryForGlobal(Offset globalPosition) {
    if (_documentId == null) return null;
    final wb = _painter.wordBoundaryForLocal(globalToLocal(globalPosition));
    if (wb == null) return null;
    return (wb.$1, wb.$2.start, wb.$2.end);
  }

  @override
  List<Rect> globalSelectionRects() {
    final local = localSelectionRects();
    if (local.isEmpty) return const <Rect>[];
    final origin = localToGlobal(Offset.zero);
    return <Rect>[for (final rect in local) rect.shift(origin)];
  }

  @override
  List<Rect> localSelectionRects() {
    final controller = _controller;
    final id = _documentId;
    if (controller == null || id == null) return const <Rect>[];
    return _painter.selectionBoxes((s) => controller.rangeFor(id, s));
  }

  @override
  List<Rect> localBoxesForRange(
    int blockIndex,
    int startOffset,
    int endOffset,
  ) =>
      _painter.localBoxesForRange(blockIndex, startOffset, endOffset);

  @override
  void setSelectionHandleLayers({
    LayerLink? startLink,
    Offset? startLocal,
    LayerLink? endLink,
    Offset? endLocal,
  }) {
    var changed = false;
    if (!identical(startLink, _startHandleLink) ||
        startLocal != _startHandleLocal) {
      _startHandleLink = startLink;
      _startHandleLocal = startLocal;
      changed = true;
    }
    if (!identical(endLink, _endHandleLink) || endLocal != _endHandleLocal) {
      _endHandleLink = endLink;
      _endHandleLocal = endLocal;
      changed = true;
    }
    if (!changed || _disposed || !attached) return;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get hasSelectionHandleLeaders =>
      _startHandleLink != null || _endHandleLink != null;

  @override
  void clearSelectionHandleLayersIfLinked({
    required LayerLink startLink,
    required LayerLink endLink,
  }) {
    final clearStart = identical(_startHandleLink, startLink);
    final clearEnd = identical(_endHandleLink, endLink);
    if (!clearStart && !clearEnd) return;
    setSelectionHandleLayers(
      startLink: clearStart ? null : _startHandleLink,
      startLocal: clearStart ? null : _startHandleLocal,
      endLink: clearEnd ? null : _endHandleLink,
      endLocal: clearEnd ? null : _endHandleLocal,
    );
  }

  void _clearSelectionHandleLayers() {
    _startHandleLink = null;
    _startHandleLocal = null;
    _endHandleLink = null;
    _endHandleLocal = null;
    _startHandleLayer.layer = null;
    _endHandleLayer.layer = null;
  }

  @override
  void repaintSelection() {
    if (!_disposed && attached) markNeedsPaint();
  }

  // --- MouseTrackerAnnotation (cursor over links and selectable text) ---

  /// Currently resolved hover cursor, or null when pointer is not hovering.
  MouseCursor? _hoverCursor;

  MouseCursor _resolveCursorAt(Offset local) {
    final resolver = _effectiveCursorResolver;
    if (resolver != null) {
      final hit = _painter.blockAtLocal(local);
      final (blockIndex, block) = hit ?? (null, null);
      final custom = resolver(local, blockIndex, block);
      if (custom != null) return custom;
    }
    if (_painter.isLinkAtLocal(local) || _painter.hiddenSpoilerAt(local)) {
      return SystemMouseCursors.click;
    }
    if (_controller != null && _painter.isSelectableAtLocal(local)) {
      return SystemMouseCursors.text;
    }
    return MouseCursor.defer;
  }

  void _updateHoverCursor(Offset local) {
    final next = _resolveCursorAt(local);
    if (next != _hoverCursor) {
      _hoverCursor = next;
      if (!_disposed && attached) markNeedsPaint();
    }
  }

  void _clearHoverCursor() {
    if (_hoverCursor != null) {
      _hoverCursor = null;
      if (!_disposed && attached) markNeedsPaint();
    }
  }

  /// Presents the dynamically resolved cursor if hovered, the click (hand)
  /// cursor over links, the text (I-beam) cursor while this document
  /// participates in a selection controller (so users see the content is
  /// selectable), and otherwise defers to what is behind it.
  @override
  MouseCursor get cursor =>
      _hoverCursor ??
      (_controller != null ? SystemMouseCursors.text : MouseCursor.defer);

  @override
  void Function(PointerEnterEvent)? get onEnter => null;

  @override
  void Function(PointerExitEvent)? get onExit => _handlePointerExit;

  void _handlePointerExit(PointerExitEvent event) => _clearHoverCursor();

  @override
  bool get validForMouseTracker => !_disposed && attached;

  /// Current size of the render box.
  @override
  Size get size => _size;
  Size _size = Size.zero;

  @override
  bool get isRepaintBoundary => _controller != null;

  @override
  bool get alwaysNeedsCompositing => _pushesHandleLeaderLayers;

  @override
  bool get sizedByParent => false;

  @override
  set size(Size value) {
    final prev = super.hasSize ? super.size : null;
    super.size = value;
    if (prev == value) return;
    _size = value;
  }

  @override
  void debugResetSize() {
    super.debugResetSize();
    if (!super.hasSize) return;
    _size = super.size;
  }

  // Measuring the content requires laying out the block [TextPainter]s, so this
  // delegates to `_painter.layout(...)` which populates the painter's cached
  // layout as a side effect (not a "pure" dry layout). [performLayout] re-runs
  // the same layout, so the cached state is always finalized before [paint].
  // Horizontal pan is not committed here — a tentative maxWidth must not clamp
  // the durable remount store.
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
        _painter.layout(
          maxWidth: constraints.maxWidth,
          commitHorizontalPan: false,
        ),
      );

  @override
  void performLayout() {
    // Set the size of the render box to match the painter's size.
    size =
        constraints.constrain(_painter.layout(maxWidth: constraints.maxWidth));
    // The controller keeps these for as long as the document lives, so a
    // selection is whole for copy and highlight while this surface is
    // unmounted too.
    final controller = _controller;
    final id = _documentId;
    if (controller != null && id != null) {
      controller.reportAtomicRanges(id, _painter.atomicRanges());
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTestChildren(
    BoxHitTestResult result, {
    required Offset position,
  }) =>
      false;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    var hitTarget = false;
    if (size.contains(position)) {
      hitTarget = hitTestSelf(position);
      result.add(BoxHitTestEntry(this, position));
    }
    return hitTarget;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    // Track hover so the cursor can switch to custom resolved cursors or the
    // hand over links. A repaint prompts MouseTracker to re-read [cursor] (same
    // mechanism as RenderMouseRegion); we only repaint when the cursor state
    // actually flips.
    if (event is PointerHoverEvent) {
      _updateHoverCursor(event.localPosition);
    }
    if (event is PointerScrollEvent) {
      // Nested in a vertical list: only claim when horizontal wins the delta.
      final dx = event.scrollDelta.dx;
      final dy = event.scrollDelta.dy;
      if (dx != 0.0 && dx.abs() >= dy.abs()) {
        _panHorizontally(event.localPosition, dx);
      }
    } else if (event is PointerDownEvent) {
      _maybeArmHorizontalPan(event);
    }
    if (_handleSpoilerTap(event)) return;
    _painter.handleEvent(event);
  }

  void _maybeArmHorizontalPan(PointerDownEvent event) {
    // Mouse / stylus / trackpad use TapAndPan on the selection scope (or
    // PointerScrollEvent for wheel/trackpad). Touch is the only kind that
    // arms HorizontalDrag here — otherwise stylus selection fights pan.
    if (event.kind != PointerDeviceKind.touch) return;
    // A new pointer cancels any in-flight ballistic fling.
    _stopBallistic();
    final block = _painter.pannableBlockAt(event.localPosition);
    if (block == null) return;
    _panningBlock = block;
    var pan = _horizontalPan;
    if (pan == null) {
      pan = HorizontalDragGestureRecognizer()
        ..dragStartBehavior = DragStartBehavior.down
        ..onUpdate = (details) {
          final t = _panningBlock;
          if (t == null) return;
          // Finger moving left reveals content on the right.
          if (t.applyScrollDelta(-details.delta.dx)) {
            _painter.rememberHorizontalPan(t);
            markNeedsPaint();
          }
        }
        ..onEnd = (details) {
          final t = _panningBlock;
          _panningBlock = null;
          final velocity = details.primaryVelocity;
          if (t == null || velocity == null || velocity == 0.0) return;
          // Finger fling left (negative dx velocity) reveals trailing content
          // (positive scroll delta) — invert for scroll axis.
          _startBallistic(t, -velocity);
        }
        ..onCancel = () {
          _panningBlock = null;
        };
      _horizontalPan = pan;
    }
    pan.addPointer(event);
  }

  bool _panHorizontally(Offset local, double deltaDx) {
    final block = _painter.pannableBlockAt(local);
    if (block == null) return false;
    if (!block.applyScrollDelta(deltaDx)) return false;
    _painter.rememberHorizontalPan(block);
    markNeedsPaint();
    return true;
  }

  void _startBallistic(HorizontallyPannableBlock block, double velocity) {
    if (!block.canPanHorizontally || velocity.abs() < 50.0) return;
    _stopBallistic();
    _ballisticBlock = block;
    _ballisticSimulation = ClampingScrollSimulation(
      position: block.scrollOffset,
      velocity: velocity,
    );
    // Raw [Ticker] (no Element [TickerProvider]): muted from [TickerMode] via
    // [setTickerModeEnabled], and when detached.
    _ballisticTicker ??= Ticker(_onBallisticTick, debugLabel: 'md.pan.fling');
    _ballisticTicker!.muted = !_tickerModeEnabled || !attached;
    _ballisticStart = Duration.zero;
    _ballisticTicker!.start();
  }

  void _onBallisticTick(Duration elapsed) {
    if (!attached || _disposed || !_tickerModeEnabled) {
      _stopBallistic();
      _ballisticTicker?.stop();
      return;
    }
    if (_ballisticStart == Duration.zero) {
      _ballisticStart = elapsed;
    }
    final simulation = _ballisticSimulation;
    final block = _ballisticBlock;
    if (simulation == null || block == null) {
      _stopBallistic();
      return;
    }
    final t = (elapsed - _ballisticStart).inMicroseconds /
        Duration.microsecondsPerSecond;
    final next = simulation.x(t).clamp(0.0, block.maxScrollExtent);
    final delta = next - block.scrollOffset;
    if (delta != 0.0 && block.applyScrollDelta(delta)) {
      _painter.rememberHorizontalPan(block);
      if (!_disposed && attached) markNeedsPaint();
    }
    if (simulation.isDone(t) || !block.canPanHorizontally) {
      _stopBallistic();
      // Ticker.stop does not dispose; keep for reuse.
      _ballisticTicker?.stop();
    }
  }

  /// Handles system font changes by marking the render object as needing layout
  void _handleSystemFontsChange() {
    // Invalidate cached layouts in painter and all block painters
    _painter.invalidateLayout();
    // Request new layout and paint
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ballisticTicker?.muted = !_tickerModeEnabled || !attached;
    _rippleTicker?.muted = !_tickerModeEnabled || !attached;
    PaintingBinding.instance.systemFonts.addListener(_handleSystemFontsChange);
    _painter.bindHorizontalPanStore(_controller, _documentId);
    final controller = _controller;
    final id = _documentId;
    if (controller != null && id != null) {
      controller.putDocument(id, _painter.markdown);
      controller.attachSurface(this);
    }
  }

  /// Updates the render object with a new values.
  /// This method should be called whenever the markdown or theme changes.
  @meta.internal
  void update({
    required Markdown markdown,
    required MarkdownThemeData theme,
    MarkdownCursorResolver? cursorResolver,
    MarkdownInlineEmbedResolver? embedResolver,
    double devicePixelRatio = 1.0,
  }) {
    _theme = theme;
    if (_cursorResolver != cursorResolver) {
      _cursorResolver = cursorResolver;
      _clearHoverCursor();
    }
    if (_painter.update(
      markdown: markdown,
      theme: theme,
      embedResolver: embedResolver,
      devicePixelRatio: devicePixelRatio,
    )) {
      // Mark the render object as needing layout.
      markNeedsLayout();
    }
    final controller = _controller;
    final id = _documentId;
    if (controller != null && id != null) {
      controller.putDocument(id, markdown);
    }
  }

  /// The internal painter — tests use this to assert pan / picture cache.
  @visibleForTesting
  MarkdownPainter get debugPainter => _painter;

  @override
  @protected
  void detach() {
    _stopBallistic();
    _ballisticTicker?.muted = true;
    // A muted ticker would strand the ripple half-drawn; end it revealed.
    _rippleTicker?.muted = true;
    _finishRipple();
    PaintingBinding.instance.systemFonts
        .removeListener(_handleSystemFontsChange);
    _controller?.detachSurface(this);
    // Drop leaders before leaving the tree so a detached surface cannot keep
    // LayerLinks alive and produce ghost / double handles after remount churn.
    _clearSelectionHandleLayers();
    _clearHoverCursor();
    super.detach();
  }

  @override
  @protected
  void dispose() {
    _disposed = true;
    _spoilerController?.removeListener(_onSpoilerChange);
    _spoilerController = null;
    _rippleTicker?.dispose();
    _rippleTicker = null;
    _controller?.removeListener(_onSelectionChange);
    _clearSelectionHandleLayers();
    _stopBallistic();
    _ballisticTicker?.dispose();
    _ballisticTicker = null;
    _horizontalPan?.dispose();
    _horizontalPan = null;
    _panningBlock = null;
    super.dispose();
    _painter.dispose();
  }

  @override
  @protected
  void paint(PaintingContext context, Offset offset) {
    if (_painter.isEmpty)
      return; // If the markdown is empty, do not paint anything.

    final canvas = context.canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    //..clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Selection highlight stays outside the cached content Picture (S7: drag /
    // streaming/pan never rebuilds the glyph cache). Paint order matches
    // SelectableRegion: highlight under glyphs so text stays sharp, then a
    // second pass above opaque block chrome (code fences, table zebra rows,
    // inline monospace/highlight) so the tint stays visible there.
    final controller = _controller;
    final id = _documentId;
    TextRange? rangeOf(int source) => controller != null && id != null
        ? controller.rangeFor(id, source)
        : null;
    if (controller != null && id != null) {
      _highlightPaint.color = controller.selectionColor ?? _kSelectionColor;
      _painter.paintHighlight(canvas, rangeOf, _highlightPaint);
    }

    _painter.paint(canvas, size);

    if (controller != null && id != null) {
      _painter.paintHighlight(
        canvas,
        rangeOf,
        _highlightPaint,
        aboveCachedContentOnly: true,
      );
    }

    canvas.restore();

    // Push handle leader layers (empty layers) so the scope's SelectionOverlay
    // handles follow this content as it scrolls.
    final startLink = _startHandleLink;
    final startLocal = _startHandleLocal;
    if (startLink != null && startLocal != null) {
      _startHandleLayer.layer = LeaderLayer(
        link: startLink,
        offset: offset + startLocal,
      );
      context.pushLayer(_startHandleLayer.layer!, _paintNothing, Offset.zero);
    } else {
      _startHandleLayer.layer = null;
    }
    final endLink = _endHandleLink;
    final endLocal = _endHandleLocal;
    if (endLink != null && endLocal != null) {
      _endHandleLayer.layer = LeaderLayer(
        link: endLink,
        offset: offset + endLocal,
      );
      context.pushLayer(_endHandleLayer.layer!, _paintNothing, Offset.zero);
    } else {
      _endHandleLayer.layer = null;
    }
  }
}

/// A no-op paint callback for pushing childless [LeaderLayer]s.
void _paintNothing(PaintingContext context, Offset offset) {}
