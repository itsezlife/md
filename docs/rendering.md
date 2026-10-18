# Rendering layer

Files: `lib/src/render.dart` (a re-export barrel), `lib/src/render/**`,
`lib/src/theme.dart`, `lib/src/widget.dart`. The layer paints the model onto a
canvas via one `RenderBox` and a list of `BlockPainter`s — **no widget per block**.

## File map (`lib/src/render/`)

`render.dart` is a **barrel** (`library;` + `export` lines) so legacy
`import 'src/render.dart'` keeps resolving; it has no code.

| File | Contents |
|---|---|
| `block_painter.dart` | The framework: `BlockPainter`, `SelectableBlockPainter`, `HorizontallyPannableBlock`, mixins `SelectableTextBlock` / `MultiPainterSelectable` / `ParagraphGestureHandler`, class `SelectableFragment`, `PannedContent` (`@meta.internal`: the pan transform a block gives the live embed pass), private `_distanceToRect`. |
| `span_builder.dart` | `paragraphFromMarkdownSpans({spans, theme, textStyle, revealed})` → `TextSpan` (a `MarkdownParagraphSpan` when the paragraph has a `\|\|spoiler\|\|`); the `TextPainter` extension `MarkdownSpoilerPainter`; private tap recognizers (`onLinkTap` from `span.extra['url']` for a link, `onMentionTap` from the scheme, id and name in `extra` for a mention-class span; neither fires under a hidden spoiler). |
| `spoiler_particle_field.dart` / `spoiler_particle_tile.dart` | `SpoilerParticleField` (the dust simulation) and `SpoilerParticleTile` / `SpoilerParticleTiles` (the live tile image and its per-process registry). |
| `spoiler_phase.dart` | `SpoilerPhase` (`$Hidden` / `$Revealing` / `$Revealed`) — what the painter draws for the document's spoilers. |
| `inline_embeds.dart` | `MarkdownEmbedSpan` (the placeholder span of one embed) and `MarkdownEmbedHost` (owns the embeds a painter resolved and forwards their signals), both `@meta.internal`. |
| `embed_offset_map.dart` | `MarkdownEmbedOffsets`: the map between painter text offsets and rendered text offsets (`@meta.internal`). |
| `markdown_painter.dart` | `MarkdownPainter` (`@meta.internal`) — the orchestrator. |
| `markdown_render_object.dart` | `MarkdownRenderObject` (`@meta.internal`) — the `RenderBox`, also a `MarkdownSelectionSurface`; plus `_paintNothing`. |
| `../spoiler.dart` | `MarkdownSpoilerController` — which documents are revealed; public. |
| `blocks/*.dart` | `BlockPainter$Paragraph, $Heading, $Quote, $Alert, $Code, $List` (+ private `_ListItemMetrics`), `$Table`, `$ScrollableTable`, `$Divider`, `$Spacer`. |

## Render flow

`MarkdownWidget` (`LeafRenderObjectWidget`) → `createRenderObject` builds a
`MarkdownRenderObject` then `updateSelection(controller, documentId)`;
`updateRenderObject` calls `updateSelection(...)` then `update(markdown, theme)`
(bind pan store before model rebuild). Theme resolution: explicit `theme` →
`MarkdownTheme.maybeOf(context)` → a default
from `DefaultTextStyle`/`Directionality`/`MediaQuery.textScaler`.

`MarkdownRenderObject` (a `RenderBox`, not `sizedByParent`) owns one
`MarkdownPainter`. `computeDryLayout`/`performLayout` both do
`constraints.constrain(_painter.layout(maxWidth: constraints.maxWidth))`.

`MarkdownPainter`:

- **Build** (`_rebuild`): reads `theme.blockFilter` and `theme.builder ??
  _defaultBlockBuilder`; for each non-filtered block appends
  `builder(block, theme) ?? _defaultBlockBuilder(block, theme)` to
  `_blockPainters`, records the true `Markdown.blocks` index in `_sourceIndices`,
  sizes `_blockOffsets`. Harvests horizontal pans with rendered-text identity and
  remaps them content-anchored onto the new painters. `_defaultBlockBuilder` is a
  `block.map(...)` to the default `BlockPainter$*` constructors (tables use
  non-pannable `$Table`; opt into `$ScrollableTable` via `builder`).
- **Layout:** per-block, top-to-bottom. Writes each block's top-`y` into
  `_blockOffsets[i]`, calls `block.layout(maxWidth)`, restores horizontal pan from
  the local map or controller, accumulates height, tracks max width. **No
  inter-block spacing** is added — a `MD$Spacer` block supplies gaps.
- **Paint:** guarded by `!_needsLayout`. **Non-pannable glyphs are cached in a
  `ui.Picture` keyed by `(size, revealed)`** — if `_lastSize == size`, the picture
  for the document's spoiler state is replayed via `drawPicture`; otherwise it
  re-records only non-`HorizontallyPannableBlock` painters. A document without a
  spoiler has one picture; one with spoilers has the hidden picture, the
  revealed one once revealed, and both only while the reveal ripple runs. Pannable
  blocks always paint live afterward (each applies its own clip + translate). The
  cache is nulled only by `update` (model/theme change) and `invalidateLayout`
  (system fonts). An overflow guard stops emitting blocks past the viewport
  height.
- **Paint order**, back to front (`MarkdownRenderObject.paint`). Only the second
  step is recorded; everything else is drawn live each frame:
  1. the selection tint under the glyphs;
  2. the glyph picture for `(size, revealed)` (during a ripple, the hidden
     picture outside the circle and the revealed one inside it);
  3. the pannable blocks (clip and translate, so a pan moves no picture);
  4. the spoiler pass: the dust fill over each hidden spoiler, and the ripple
     (see [Spoilers](#spoilers));
  5. the embeds pass (see [Inline embeds](#inline-embeds)), each embed at the
     opacity its spoiler leaves it;
  6. the selection tint above opaque chrome, over code fences, table fills and
     embeds.
  A mention has no step of its own: it is colour and no underline on a text run,
  so it lives in step 2 or 3 with the rest of the text.
- **Hit-testing** (`_blockIndexForDy`): **binary search** over `_blockOffsets`.
  `positionForLocal` maps a content-local offset → `(sourceBlockIndex, textOffset)`
  (null if the hit block isn't a `SelectableBlockPainter`). `handleEvent` routes
  tap-down/up to the block, re-basing the pointer into block-local space (a manual
  `PointerEvent` clone, since `PointerEvent` has no `copyWith`). Touch/stylus
  horizontal drag and pointer-scroll pan hit `pannableBlockAt`; drag-end may start
  a `ClampingScrollSimulation` ballistic fling (cancelled on pointer-down / rebuild).
- **System fonts:** `MarkdownRenderObject.attach` listens on
  `PaintingBinding.instance.systemFonts`; a change calls `invalidateLayout` (nulls
  the cache, disposes+rebuilds every block painter so `TextPainter`s re-layout) +
  `markNeedsLayout`.

## Inline embeds

`![alt](scheme:id)` can be laid out as a real inline object. The contract is in
`lib/src/inline_embed.dart` and public: `MarkdownInlineEmbed` (size, `visible`,
`paint(canvas, rect, context)`, a `Listenable` signal, idempotent `dispose`),
`MarkdownInlineEmbedResolver`, `MarkdownInlineEmbedTarget` (`scheme`, `id`,
`alt`) and `MarkdownInlineEmbedMetrics` (`fontSize`, `ascent`, `descent`,
`devicePixelRatio`, and `extent`, the size rule). The package knows no
implementation; a host adapts its own asset type to it and hands it over as
`MarkdownWidget.embedResolver` (the device pixel ratio comes from `MediaQuery`).

- **Room.** `paragraphFromMarkdownSpans(embeds: …)` turns an image span whose
  `src` has a scheme the resolver answers for into a `MarkdownEmbedSpan`: a
  `PlaceholderSpan` (`PlaceholderAlignment.middle`), not a `WidgetSpan`. The
  default block painters take the host as `inlineEmbeds` (paragraph, heading,
  quote, alert, list, table).
- **Size.** Android's rule: a square of `1.2 × (ascent + descent)` of the
  paragraph font, rounded to device pixels (`MarkdownInlineEmbedMetrics.extent`).
  The font is probed once per paragraph, on its first embed, from a one-line
  layout that carries only the font family, size, weight and style (not
  `TextStyle.height`); every embed of the paragraph gets that one metrics
  value. The resolver sizes the embed from it; the span reserves the embed's
  width and the *font's* height, and the square is centred on that box, so the
  line is as tall as without the embed and the embed overflows it by about a
  tenth above and below. Paragraph paint does not clip.
- **Unresolved.** No resolver, a scheme it returns `null` for, or a `src`
  without a scheme: the span stays the plain `TextSpan` of its alt text.
- **Ownership.** `MarkdownPainter` holds one `MarkdownEmbedHost` per resolver
  and disposes everything it resolved when it rebuilds its block painters (new
  model or theme, system fonts, a new resolver or pixel ratio) and on
  `dispose`. `$List` and `$Table` build their paragraphs on every layout, so
  they release the previous ones first.
- **Paint.** `MarkdownPainter.paintEmbeds` is the third pass, run by the render
  object right after `_painter.paint` and before the above-content tint. It walks
  each block's text fragments, reads `TextPainter.inlinePlaceholderBoxes` through
  `MarkdownEmbedOffsets`, and calls `embed.paint(canvas, span.paintRectFor(box),
  context)`. The context's tint is the colour of the text the embed sits in (its
  span's, else the paragraph's); its opacity is `embedOpacityAt(rect)` (0 under a
  hidden spoiler, the ripple's progress while revealing, 1 elsewhere). The
  placeholder paints nothing into the picture. A block that pans (`PannedContent`,
  the table) is clipped and translated first, so an embed moves with its cell.
  A selection tints an embed it covers *over* the embed, because an opaque embed
  hides the under-glyph tint; blocks that already tint above the picture are left
  to that pass.
- **Invalidation.** `MarkdownEmbedHost` subscribes to each embed it resolves and
  unsubscribes before it disposes it. A signal reaches the render object, which
  coalesces the frame's signals into one `markNeedsPaint`
  (`_embedPaintPending`, cleared by the paint that answers it). A signal never
  re-records the glyph picture and never lays out.
- **Visibility.** After each layout (not during paint: an embed may react to the
  change by scheduling a repaint) `syncEmbedVisibility` sets
  `MarkdownInlineEmbed.visible` to whether the embed's block is inside the
  painted height, the guard the picture uses; `detach` sets it false before the
  embeds are disposed and `attach` sets it again. The fork adds no other pause
  layer: the asset cache owns the global ones. Note that "painted height" is the
  render object's own size: a message that a list scrolls partly out of view is
  still visible here, and one the list drops is detached.
- **Builders.** A list or table a theme `builder` returns is given the host by
  `MarkdownPainter` (they build their paragraphs at layout), so a
  `$ScrollableTable` has embeds too. A custom painter that builds its paragraph
  itself has no host to ask: the host is internal, so it shows alt text.
- **Offsets.** The placeholder is one U+FFFC in the painter text and its alt
  text is the span text in `renderedText`. `SelectableTextBlock` and
  `MultiPainterSelectable` convert through `MarkdownEmbedOffsets` (identity for
  a paragraph without embeds); see [selection](selection.md#inline-embeds).
  `SelectableFragment.length` and `.renderedText` are in rendered terms.

## The `BlockPainter` framework

`BlockPainter` — every painter implements this:

```dart
abstract final Size size;                            // valid only after layout()
void handleTapDown(PointerDownEvent event);          // block-LOCAL coords
void handleTapUp(PointerUpEvent event);
Size layout(double width);                           // measure at width; sets size
void paint(Canvas canvas, Size size, double offset); // size = full content size; offset = block top-y
void dispose();
```

Coordinate contract: taps arrive in **block-local** space; `paint`'s `offset` is
the block's top-`y` in the content, and `size` is the full content size (blocks
use `size.width` for full-width backgrounds/rules and to bail when too narrow).

`SelectableBlockPainter implements BlockPainter` adds selection:

```dart
String get renderedText;                    // MUST equal markdownBlockRenderedText(block)
int offsetForLocalPosition(Offset local);   // block-local → rendered-text index
List<Rect> boxesForRange(int start, int end);// block-local highlight rects for [start, end)
bool get selectionHighlightAboveCachedContent; // true ⇒ also paint highlight above Picture
```

Two mixins implement it for you:

- **`SelectableTextBlock`** — a block backed by a **single `TextPainter`**. Supply
  `TextPainter get selectionPainter` and optionally override `Offset get
  selectionOrigin` (default `Offset.zero`) when glyphs aren't at the block origin.
  It derives `renderedText`, `offsetForLocalPosition`, `boxesForRange` for you.
- **`MultiPainterSelectable`** — a block whose text spans **several
  `TextPainter`s** at different origins (lists, tables). Supply
  `List<SelectableFragment> get fragments` (in rendered-text order, each
  `textStart` matching the linearization; the gaps are the `\n`/`\t` separators)
  and `renderedText`. `SelectableFragment` is `(TextPainter painter, Offset
  origin, int textStart)`.

`ParagraphGestureHandler` — mix in for link taps: `hitTestInlineSpanWithPointerEvent(event,
painter)` resolves the `InlineSpan` under a pointer so `handleTapDown`/`handleTapUp`
can match down and up on the same span before firing its recognizer.

`paragraphFromMarkdownSpans({spans, theme, textStyle})` → `TextSpan` — the public
helper that applies `theme.spanFilter`, maps each `MD$Span` via
`theme.textStyleFor(span.style)` (merged under `textStyle` if given), and attaches
a link recognizer (from `theme.onLinkTap` + `span.extra['url']`) or, for a
mention-class span, a mention recognizer (from `theme.onMentionTap` +
`span.extra['scheme'/'id'/'name']`; `onLinkTap` never fires for it). **Use it**
for any custom text block so filters/styles/link-taps stay consistent.

### Recipe: a custom block painter

```dart
class MyBlock with ParagraphGestureHandler, SelectableTextBlock implements BlockPainter {
  MyBlock({required List<MD$Span> spans, required this.theme})
      : painter = TextPainter(
          text: paragraphFromMarkdownSpans(spans: spans, theme: theme),
          textDirection: theme.textDirection, textScaler: theme.textScaler);

  final MarkdownThemeData theme;
  final TextPainter painter;
  @override TextPainter get selectionPainter => painter;   // SelectableTextBlock hook

  Size _size = Size.zero;
  @override Size get size => _size;

  @override Size layout(double width) { painter.layout(maxWidth: width); return _size = painter.size; }
  @override void paint(Canvas c, Size s, double dy) { /* decorate */ painter.paint(c, Offset(0, dy)); }
  @override void handleTapDown(PointerDownEvent e) {/* see BlockPainter$Paragraph */}
  @override void handleTapUp(PointerUpEvent e) {/* ... */}
  @override void dispose() => painter.dispose();
}
```

Wire it in via the theme:

```dart
MarkdownThemeData(
  builder: (block, theme) => block is MD$Paragraph ? MyBlock(spans: block.spans, theme: theme) : null,
);
```

Returning `null` falls back to the default painter for that block. For
many-painter blocks (custom lists/tables), mix in `MultiPainterSelectable` instead
and expose `fragments` + `renderedText`.

> **Offset-space rule:** if your block is selectable, `renderedText` (and each
> fragment's `textStart`) must match `markdownBlockRenderedText(block)` (see
> [selection](selection.md)), or hit-testing, highlight, and copied text will
> disagree.

## Default block painters

- **`$Paragraph`** — one `TextPainter` from spans, painted at `(0, offset)`;
  selectable + link taps; no decoration.
- **`$Heading`** — like `$Paragraph`, styled by `theme.headingStyleFor(level)`.
- **`$Quote`** — body styled `theme.quoteStyle ?? textStyle`; one vertical accent
  bar per `indent` level (`lineIndent = 10`, `dividerColor`); text shifted right
  by `lineIndent + indent*lineIndent` (also its `selectionOrigin`).
- **`$Alert`** — GitHub admonition: tinted rounded background (accent α 0.10),
  left accent bar (width 4), bold colored title above body (`alert.title`,
  `alertColorFor(type)`); body selectable via `selectionOrigin`.
- **`$Code`** — monospace `TextPainter` (raw text, no span parsing); rounded
  `surfaceColor` background (radius = padding 8); taps are no-ops; **no link taps**.
- **`$List`** — recursive nested items (`_baseIndent = 8`, `_levelIndent = 16` per
  depth); bullet glyph `☑`/`☐` for task items, else `•`/ordered marker; each item
  is a bullet + content `TextPainter`; `MultiPainterSelectable`, items joined `\n`.
- **`$Table`** — per-cell `TextPainter` (bold header), per-column alignment;
  column widths via `_distributeWidths` (natural if they fit, else shrink toward
  per-column min = longest-word width, else overflow); zebra rows, cached inner
  grid + outer border; `MultiPainterSelectable`, cells joined `\t`, rows `\n`.
  Default `$Table` may overflow the max width (historical). Opt-in
  `$ScrollableTable` implements `HorizontallyPannableBlock` (clip + pan).
- **`$Divider`** — one horizontal line across `size.width`; not selectable.
- **`$Spacer`** — blank vertical gap `Size(0, fontSize * count)`; `paint` is a
  no-op; not selectable.

`$Divider`/`$Spacer` are not selectable; `$Code` is selectable but has no link
taps; only `$List`/`$Table` use `MultiPainterSelectable`.

## Spoilers

`||x||` parses to `MD$Style.spoiler` (any inline can carry it: a link or an
image inside a spoiler keeps both bits). It paints hidden until the document is
revealed.

- **State.** `MarkdownSpoilerController` (`ChangeNotifier`) holds the revealed
  `documentId`s and the global point each reveal started from. Pass it as
  `MarkdownWidget.spoilerController` (keyed by `documentId`, like the selection
  controller). One bit per **document**: a tap reveals every spoiler of it. It
  outlives widgets, so a remount finds the document revealed and a second widget
  of the document reveals with the first. In memory only; nothing re-hides on its
  own. No controller or no `documentId` → spoilers paint as ordinary text.
- **Hidden text keeps its place.** `paragraphFromMarkdownSpans(revealed: false)`
  gives each spoiler run a transparent colour (and decoration / background
  colour) and nothing else, so every glyph box equals the revealed one. The
  result is a `MarkdownParagraphSpan` that carries both forms and the spoiler
  ranges; flipping a laid-out `TextPainter` between them
  (`TextPainter.setSpoilersRevealed`) is a paint-only text change, so Flutter
  keeps the layout. `SelectableTextBlock` and `MultiPainterSelectable` implement
  `SpoilerBlockPainter` (`spoilersRevealed`, `spoilerRects`), which covers the
  default painters; a painter that implements neither shows spoilers as text.
- **Two pictures at most.** `MarkdownPainter` caches a glyph picture per
  `(size, revealed)`: hidden while hidden, revealed once revealed, both only for
  the length of a ripple. A reveal swaps pictures; it never lays out.
- **Live passes.** The fill over each hidden spoiler (`spoilerRects`, outside the
  glyph pictures) and the ripple are painted every frame without touching the
  pictures.
- **Dust.** The fill is Android's particle dust as one **live tile**: a 128 dp
  `SpoilerParticleField` (0.09 particles / dp², round points of alpha 0.3, 0.6,
  1.0 and stroke 1.2 / 1.2 / 1.4 dp, 4–10 dp/s, life 1–3 s, respawning
  uniformly) rendered by `Picture.toImageSync` at the display's pixel ratio.
  Every hidden spoiler fills its rect, clipped to a 3 dp rounded rect, through
  an `ImageShader` of that image (`TileMode.repeated`, `FilterQuality.none`,
  a per-spoiler pattern offset). The cost of the dust is one tile render per
  dust frame however many spoilers are on screen; the render happens on the
  first fill of a frame, never on a timer of its own. `SpoilerParticleTiles`
  keeps one tile per `(text colour, pixel ratio)` per process, counted by the
  painters that use it: the last release disposes it, so a theme colour change
  replaces it and a screen with no hidden spoiler holds no image. Where the
  engine has no `toImageSync` the tile is **static**: the frame-0 dust as a
  `Picture`, drawn tiled, rendered once.
- **Dust clock.** The package owns no ticker for the dust.
  `MarkdownSpoilerController.advance(elapsed)` takes the host's monotonic clock
  (the root viewport passes the shared playback clock); the dust moves at
  `fillFrameRate` (30) whatever the clock's rate. `wantsTicks` is true while a
  hidden (or rippling) spoiler that may move is mounted, so the host runs its
  clock only then. With no `advance`, `animate == false`,
  `MediaQuery.disableAnimationsOf` or a muted `TickerMode`, the dust is the
  tile as first rendered and nothing repaints it.
- **Ripple.** ~300 ms (`MarkdownSpoilerController.revealDuration`): outside a
  circle grown from the tap point, the hidden picture and the fill; inside it
  (clipped to the spoiler rects) the revealed picture. The radius reaches the
  farthest corner of any spoiler of the document. The render object runs it on a
  raw `Ticker` (muted with `TickerMode`; a muted ripple ends revealed). Motion
  off (`MarkdownSpoilerController.animate = false`, or
  `MediaQuery.disableAnimationsOf`) reveals in the same frame.
- **Taps.** A pointer that goes down on a hidden spoiler is not forwarded to the
  blocks: the tap reveals (if it comes up within the pan slop and within
  `MarkdownSpoilerController.tapTimeout`, `kLongPressTimeout` by default, on the
  pointer's own timestamps), so `onLinkTap` / `onMentionTap` do not fire for a
  link under a spoiler. The same tap after the reveal does. A press held past the
  timeout is a long press, the host's gesture, and reveals nothing (`null` puts
  no limit on a hold: the desktop mouse click). `tapReveals = false` skips the
  reveal while the pointer is still absorbed, for a host whose taps mean
  something else (message selection: Android leaves the spoiler hidden there);
  both settings are read at the pointer up.
  `MarkdownSpoilerController.reveal(documentId)` with no origin is the entry for
  a text selection that enters a spoiler; it ripples from the middle of the
  spoilers.
- **Embeds.** `MarkdownPainter.embedOpacityAt(rect)` is the spoiler's half of the
  inline embed contract: 0 under a hidden spoiler, the ripple's progress while
  revealing, 1 elsewhere.

## Theme customization (`MarkdownThemeData`)

`MarkdownThemeData implements ThemeExtension<MarkdownThemeData>` — put it in
`ThemeData.extensions` (it `lerp`s; non-lerpable fields switch at `t < 0.5`) or
provide it through the `MarkdownTheme` inherited widget (`MarkdownTheme.of/maybeOf`).
`MarkdownThemeData.mergeTheme(ThemeData, ...)` derives one from a Material theme.

Render-override hooks:

- **`builder`** `BlockPainter? Function(MD$Block, MarkdownThemeData)` — custom
  painter per block; `null` ⇒ default.
- **`blockFilter`** `bool Function(MD$Block)` — drop a whole block before painters
  are built; `_sourceIndices` keeps selection anchored to the real model index.
- **`spanFilter`** `bool Function(MD$Span)` — filter inline spans. **Caveat:
  dropping text-bearing spans shifts the painter's offset space vs the model, so
  the highlight stays right but copied text can misalign. Avoid dropping
  text-bearing spans when selection is enabled.**
- **`emojiRuns`** `Iterable<TextRange> Function(String)` + **`emojiScale`** —
  draw the emoji of a text larger than its letters. A colour emoji font draws
  its glyph into a square of the font size, shorter than the line (SF is about
  1.18 times its size tall) and shorter than an inline embed (1.2 times the
  font's height). With a scanner each range it reports is a child `TextSpan` of
  its own whose font size makes the glyph `emojiScale` times the font's height
  (ascent plus descent, the same probe the embeds use), and whose `height` is
  the text's line, so the emoji does not add to the line's height beyond what
  an emoji at the font size already did (the emoji font's deeper descent can
  make a line one pixel taller). The plain text, its offsets, the spoiler
  ranges and the recognizers are those of the text without a scanner: the
  split span keeps the parent's style and the recognizer goes on every piece.
  The package ships no emoji table: the host's scanner is the one that also
  decides what its messages count as emoji. Ranges that are empty, out of
  bounds or overlapping are dropped. Default `null`: no change.
- **`cursorResolver`** `MouseCursor? Function(Offset, int?, MD$Block?)` —
  dynamically resolves hover mouse cursors per local offset, hit block index,
  and hit block model, falling back to default link/text/defer cursors when null.
  Can also be supplied directly to `MarkdownWidget.cursorResolver`.

Styling: `textStyle`, per-level `h1Style..h6Style` (+ cached `headingStyleFor`),
`textStyleFor(MD$Style)` (cached mapping of the bitmask → bold/italic/underline/
strikethrough/monospace + highlight/monospace backgrounds + link color),
`linkColor`/`linkStyle`, `mentionColor` (mention-class text; follows
`linkColor` when null, never underlined), `surfaceColor` (code/table/quote backgrounds),
`highlightBackgroundColor`, `monospaceBackgroundColor`,
`monospaceFontFamily`/`monospaceFontFamilyFallback` (platform-resolved by
default — `monospace` on Android/Fuchsia/Linux/web, `Menlo` on iOS/macOS,
`Consolas` on Windows, from `ThemeData.platform` under `mergeTheme`; one knob
for both inline `` `code` `` and fenced blocks, and `textStyle`'s own fallback
chain is appended after it), `dividerColor`,
`alertColors` (+ built-in GitHub palette fallback via `alertColorFor`),
`textDirection`, `textScaler`, `onLinkTap`, and `onMentionTap`.

## Public vs internal

Public (in `flutter_md.dart`'s `show` list): the framework
(`BlockPainter`, `SelectableBlockPainter`, `HorizontallyPannableBlock`,
`SelectableTextBlock`,
`MultiPainterSelectable`, `SelectableFragment`, `ParagraphGestureHandler`,
`paragraphFromMarkdownSpans`, `SpoilerBlockPainter`) and the default painters
(`BlockPainter$Paragraph … $Spacer`, plus opt-in `$ScrollableTable`). Internal (`@meta.internal`, only via
`src/render.dart`): `MarkdownPainter`, `MarkdownRenderObject`.

## Invariants (repeated from [architecture](architecture.md), owned here)

- Glyphs cached in a `ui.Picture` keyed by `(size, revealed)`; reused on repaint; nulled only on
  `update`/`invalidateLayout`. **Pannable blocks paint outside that Picture.**
- **Selection highlight is painted outside the glyph [Picture] cache**, in two
  passes matching `SelectableRegion` / `SelectionArea`: first **under** the
  content picture (sharp text — no washed-out overlay), then **above** only for
  blocks that paint opaque chrome (`selectionHighlightAboveCachedContent`, e.g.
  code fences, table zebra rows, and blocks whose spans use monospace/highlight
  backgrounds) so the tint stays visible there. Drags/streaming/pan never rebuild
  the glyph cache. Color = `controller.selectionColor ?? _kSelectionColor`
  (`0x552196F3`). Pannable-block highlights are clipped to the block viewport.
- **An embed, a spoiler or a mention never re-records the picture per frame.**
  - *Embed:* it paints in a live pass; a signal repaints, a change of resolver or
    pixel ratio rebuilds.
  - *Spoiler:* at most two glyph pictures exist per size (hidden, revealed); the
    fill pass and the ripple are live passes above them, and a reveal swaps
    pictures without laying out.
  - *Mention:* it is a text style (the mention colour, no underline) resolved
    when the paragraph is built, so it adds no live paint; only which callback a
    tap reaches differs from a link.
- `isRepaintBoundary => controller != null`; `alwaysNeedsCompositing` when the
  surface owns a start and/or end handle `LeaderLayer`.
- Handle `LeaderLayer`s are pushed in `paint` via `LayerHandle` (only when a
  scope supplied start/end `LayerLink` + local offset) so native handles follow
  scrolling content. Links clear on detach so remount / virtualization cannot
  leave ghost leaders.
