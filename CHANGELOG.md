## 0.8.1

A host whose theme `builder` makes a new painter on every call can hand those
painters to the body again. The release tag is `v0.8.1`; depend on it by git
ref as described under 0.3.0's *Fork status*.

### Rendering
- **ADDED**: `MarkdownThemeData.disposeBuiltPainters` (default `false`;
  constructor, `mergeTheme`, `copyWith`, `lerp`). When set, `MarkdownPainter.update`
  disposes the painters `builder` made that the update replaces, as it did
  before 0.8.0, instead of leaving them to the garbage collector. Leave it off
  for a builder that keeps a painter and returns it again.

## 0.8.0

Merges upstream `DoctorinaAI/md` `0.3.1` into the fork. The upstream release
notes are in its `0.3.1` changelog and [docs/benchmarks.md](docs/benchmarks.md);
what follows is what the fork gains and where the two lines had to be
reconciled. The release tag is `v0.8.0`; depend on it by git ref as described
under 0.3.0's *Fork status*.

### From upstream
- **ADDED**: `Markdown.fromStringAsync` and `MarkdownDecoder.convertAsync`
  parse a long document in slices (4 ms by default), pausing until the end of
  the frame when one is on the way. The result equals that of the sync parse.
- **FIXED**: hostile input no longer freezes the parser: more than 65535 links
  in one paragraph, unclosed emphasis and backticks, tables that fail
  validation, spaces in a heading, deeply nested `>` and unclosed math braces
  are all linear now. Fenced code is re-parsed as nested blocks down to 32
  quote levels.
- **IMPROVED**: streaming. `MarkdownPainter.update` keeps the painters of the
  unchanged leading blocks and records only what follows them; a rebuild with
  equal text and theme values lays nothing out. Applies to a theme without
  `builder`, `imageResolver`, `blockFilter` or `spanFilter`.
- **IMPROVED**: lists and tables keep their text painters across layouts; a
  table that fits skips the longest-word pass; list items share bullet
  painters.
- **CHANGED**: `MarkdownHighlighter.highlight` returns one flat span per run
  painted alike and caches its latest results. Code reading nested token spans
  sees flat ones.
- **CHANGED**: `paragraphFromMarkdownSpans` leaves `style` null on an unstyled
  plain text child, which inherits the parent's style. Embeds, pictures and
  chips keep their resolved style.
- **ADDED**: on-device benchmarks (`benchmark_compare/`). Upstream's GitHub
  Pages workflow for the example app is not taken: the fork has no Pages site.

### Reconciled
- **CHANGED**: painter reuse covers the fork's theme fields: `paintsLike` also
  compares `mentionColor`, `chipStyle`, `onMentionTap`, `onChipTap`,
  `cursorResolver`, `emojiRuns` and `emojiScale`. A new embed resolver or
  pixel ratio still rebuilds every block.
- **CHANGED**: a partial rebuild disposes the inline embeds of the painters it
  drops (through the same text the embed pass paints) and keeps those of the
  painters it keeps. Lists and tables release their embeds when disposed, not
  on every layout, since their paragraphs now outlive a layout. Before the
  first layout of a document with embeds, an update rebuilds every block.
- **CHANGED**: the recorded prefix that streaming reuses holds only the
  revealed glyphs of non-pannable blocks: the hidden spoiler picture is
  recorded whole, and pannable blocks still paint live.
- **CHANGED**: `MarkdownPainter.update` no longer disposes painters a theme
  `builder` made (upstream's rule: the host may still hold them); `dispose`
  and a system font change still do. The fork disposed them on every update.
- **FIXED**: the quote-after-a-list check copied every block parsed so far for
  each line that starts with a space; it now walks back from the end, so long
  documents stay linear.

## 0.7.1

A selection cleared while a `MarkdownSelectionScope` was being torn down threw.
The release tag is `v0.7.1`; depend on it by git ref as described under
0.3.0's *Fork status*.

### Selection
- **FIXED**: "Looking up a deactivated widget's ancestor is unsafe" from the
  scope's controller listener. Upstream 0.3.0 made that listener read
  `Theme.of(context)` on every clear (to keep a desktop right-click menu open),
  and a host that clears or re-registers documents from a widget's `dispose`
  (a chat body leaving the list) notifies while the scope above it is
  deactivated. The scope now reads the platform in `didChangeDependencies`.

## 0.7.0

Merges upstream `DoctorinaAI/md` `0.3.0` into the fork. The upstream release
notes are in its `0.3.0` changelog and
[docs/migration/0.2.x-to-0.3.x.md](docs/migration/0.2.x-to-0.3.x.md); what
follows is what the fork gains and where the two lines had to be reconciled.
The release tag is `v0.7.0`; depend on it by git ref as described under
0.3.0's *Fork status*.

### From upstream
- **ADDED**: inline images and link icons through
  `MarkdownThemeData.imageResolver` (`MarkdownImage`, `MarkdownImageResolver`,
  `MarkdownProviderImage`, `MarkdownProviderImageResolver`,
  `MarkdownImageSpan`, `layoutMarkdownText`, `paintMarkdownText`). Opt-in:
  without a resolver an image is its alt text, as before. `copyWith` clears the
  resolver with `clearImageResolver`, like the fork's other callbacks.
- **FIXED**: right-to-left layout. Paragraphs, headings, lists, quotes, alerts
  and tables sit against the right edge; a too-wide table overflows to the
  left; selection handles orient by the text they sit on; a dry layout no
  longer leaves its measured positions behind.
- **FIXED**: syntax highlighting: greedy rules match across earlier tokens,
  tokenizing is linear, and the GitHub themes colour diffs.
- **FIXED**: list items at uneven indents are kept; fenced code in quotes and
  alerts parses as nested blocks in more spellings (indented, nested quotes);
  nested quote / alert children route through `MarkdownThemeData.builder` and
  open their links. `BlockPainter$Quote` / `$Alert` take `blocks:`.
- **FIXED**: selection: the desktop context menu survives an overlay sync,
  chrome resets when a reconcile changes the selection, the registry write of
  a recycled element lands on the incoming document id.

### Reconciled
- **CHANGED**: one offset map for every placeholder. The fork's map, renamed
  `MarkdownTextOffsets` (`text_offset_map.dart`, `@meta.internal`; it was
  `MarkdownEmbedOffsets`), now also maps pictures and link icons, and
  upstream's model ↔ painter helpers (`markdownModelText`,
  `markdownPainterOffset`, …) read it, so embeds, pictures and chip glyphs
  agree in one paragraph. The rendered text is built once per laid-out text,
  as upstream's map did, and a picture's alt text is atomic in the controller
  like an embed's, so a keyboard step no longer stops inside it (upstream's
  known limitation). A picture keeps
  upstream's hit rule (the edge on the hit side); an embed keeps the fork's
  (inside its alt text).
- **CHANGED**: `paintMarkdownText` paints chip fills and glyphs too
  (`paintWithChips` paints pictures), so either call draws the whole text.
- **CHANGED**: an inline embed wins over a picture for the same image, and
  nothing inside a `||spoiler||` becomes a picture or gets a link icon: a
  hidden spoiler conceals text by colour, which a picture is not.
- **CHANGED**: a pannable table (`BlockPainter$ScrollableTable`) that
  overflows keeps its content space from 0 in right-to-left text; its pan
  shows the leading edge. A table that does not pan uses upstream's RTL
  overflow to the left. RTL table columns are now mirrored, so the first
  column is on the right.
- **CHANGED**: `boxesForRange` keeps the fork's one rectangle per line, link
  icons included.
- **ADDED**: the example's Selection tab shows pictures, a link icon and
  spoilers: a `MarkdownSpoilerController` with a `Ticker` dust clock, revealed
  by a tap or by a selection that reaches a spoiler.
- **CHANGED**: goldens are kept per host OS (`goldens/` for macOS,
  `goldens/linux/` for CI, see `docs/development.md`); the fork's goldens had
  only a macOS set, so they failed on the Linux runner.
- **KEPT**: `clampMarkdownToLines` / `MarkdownLineClamp` and
  `MarkdownPainter.textLineBottoms`, which upstream moved to a branch.
- **CHANGED**: the right-to-left embed and selection goldens moved to the
  right edge with the RTL fix. Upstream's new tests that assert copied text
  read it through `MarkdownSelectionFormatter.plain`, since the fork copies
  markdown source by default.

## 0.6.0

The inline chip is one style object, has no glyph unless a host asks for one,
and its glyph is centred on the label. The release tag is `v0.6.0`; depend on
it by git ref as described under 0.3.0's *Fork status*.

### Spans
- **CHANGED**: the 0.5.x chip theme fields and tap callback are replaced, not
  deprecated. `MD$Style.chip` (same bit) and `MD$Span.chip(start:, text:,
  target:, muted:)` build the span; `extra` holds `type: 'chip'`, `target` and
  `muted`. `MarkdownThemeData.chipStyle` takes one immutable
  `MarkdownChipStyle` (`color`, `background`, `mutedColor`, `mutedBackground`,
  `icon`, `iconSize`, `gap`, `radius`, `horizontalPadding`, `margin`,
  `fontWeight`; const constructor, `copyWith`, `lerp`, `==`). A tap calls
  `MarkdownThemeData.onChipTap(target, label)`; `copyWith` clears it with
  `clearOnChipTap`.
- **CHANGED**: a chip has no glyph by default (`icon` is `null`; there is no
  Material icon default). Radius stays fully rounded, horizontal padding 0.3 em,
  margin 0, and the colours derive from `linkColor`.
- **ADDED**: `MarkdownChipStyle.fontWeight` applies to the chip's runs (the
  label and the room around it), not the glyph.
- **FIXED**: the chip's glyph was not vertically centred on the label: an icon
  font's ascent and descent differ from the text font's, so on the shared
  baseline the glyph sat high or low. The glyph run now only reserves its
  room (transparent, same offsets as before); `paintWithChips` draws the glyph
  centred on the label's line box. The fill height, the line height and the
  selection geometry are unchanged. The new `chipGlyphBoxes` lists where the
  glyphs are drawn.
- **CHANGED**: internal renamed to match: `MarkdownChipSpan`,
  `MarkdownChipGlyphSpan`, `MarkdownChipSpacerSpan`, `buildChip`,
  `MarkdownChipPainter.chipBoxes` and `paintWithChips`.

## 0.5.1

The inline chip glyph showed a tofu box in a host whose text style carries a
font package, and the chip is now themable. The release tag is `v0.5.1`; depend
on it by git ref as described under 0.3.0's *Fork status*.

### Spans
- **FIXED**: the chip glyph rendered as a tofu box when the host text style had
  a `package` (a font from a host package). The glyph style was a `copyWith`
  of the host style, and `copyWith(package: null)` keeps the host package, so
  the family became `packages/<host>/MaterialIcons`. The glyph style is now
  built fresh from the icon's own `fontFamily` and `fontPackage`.
- **FIXED**: the fill of a chip is as tall as the label's line, so a larger
  glyph never grows it into neighbouring lines, and lines of a wrapped chip are
  told apart by overlap, not by an equal top.
- **ADDED**: theme fields for the chip's icon, radius (default fully rounded),
  icon size (default the font size), gap (default 0.3 em) and horizontal
  padding (default 0.3 em), all in `copyWith` and `lerp`.
- **CHANGED**: the chip's horizontal padding is real layout, not paint only:
  zero-width code units (U+2062, letter-spaced) push the text inside the fill,
  so the fill no longer overlaps the preceding word or a following comma. A
  wrapped chip is padded at its real start and end only.
- **ADDED**: a chip margin (default 0): room outside the fill on each side
  that the text flows past. The room is painter text the rendered text does not
  have, like the glyph, so copy and selection still see the label; a selection
  that ends at the label takes in the trailing room.

## 0.5.0

An inline chip: a span a host builds, with a leading glyph, a label and a
tinted rounded fill. The release tag is `v0.5.0`; depend on it by git ref as
described under 0.3.0's *Fork status*.

### Spans
- **ADDED**: `MD$Style` bit for the chip and a span factory that builds it. The
  chip is built from a span, not parsed from markdown, and is exclusive with
  `link` and `mention`. It is text: it wraps, selects and copies as its label
  (the glyph is not text, so a plain copy is the label). Colours come from the
  theme, with a muted pair for a chip that is not active yet. A tap calls a
  dedicated theme callback with the chip's target and label, never `onLinkTap`
  or `onMentionTap`; `copyWith` clears it with a `clearOn...Tap` flag. A chip
  is as tall as its line: a host that needs a 48 dp hit target pads the block.
- **CHANGED**: the selection tint is drawn above the glyph picture for text
  with a chip, as for highlight and code fills. The offset map treats the
  chip's glyph as painter text with no rendered text.

## 0.4.5

A theme can drop a callback through `copyWith`, and a selection edge never
stops inside an emoji. The release tag is `v0.4.5`; depend on it by git ref as
described under 0.3.0's *Fork status*.

### Theme
- **ADDED**: `MarkdownThemeData.copyWith` can remove a callback. A `null`
  argument keeps the current value, so `copyWith(onLinkTap: null)` left the
  link handler in place and a host had to rebuild the theme field by field.
  Pass `clearOnLinkTap: true` instead; `clearOnMentionTap`, `clearBlockFilter`,
  `clearSpanFilter`, `clearBuilder`, `clearCursorResolver` and `clearEmojiRuns`
  do the same for the other callbacks. A flag and a new value for the same
  callback assert.

### Selection
- **FIXED**: a character step (Shift+Arrow, and the nudge that keeps a
  dragged handle off the other one) moved one UTF-16 code unit, so it could
  stop inside an emoji: the selection then held half a surrogate pair, and a
  surface that maps offsets to whole items could not place the handle. It
  now steps one grapheme. Adds a dependency on `characters`.

## 0.4.4

A quote indented under a list item rendered as a paragraph with a literal `>`.
The release tag is `v0.4.4`; depend on it by git ref as described under 0.3.0's
*Fork status*.

### Parser
- **FIXED**: a `>` quote that is indented rendered as a paragraph with a
  literal `>` in it. This is what a quote under a list item looks like
  (`1. Compare:` then `   > **bold** quote`), and a quote indented by one to
  three spaces. Before, only a line whose first character was `>` opened a
  quote. After, up to three leading spaces are allowed, and right after a list
  any indent is, since a quote in a list item sits at the item's content
  offset. Continuation lines follow the same rule; four spaces away from a list
  are still text.
- **CHANGED**: such a quote after a list is `MD$Quote.indent` `2` (a top-level
  quote stays `1`), so a renderer can set it in to the list's text edge. It is
  still a sibling block after the list, not nested in the item: `MD$ListItem`
  holds inline spans only. The stock `BlockPainter$Quote` draws a second bar for
  `indent: 2`. A host that must not see it can map the quote to `1` in
  `MarkdownThemeData.builder`.

## 0.4.3

Before this change a selection painted a box for every run of the text, each as
tall as the run: an emoji drawn larger than the text, a text run and an inline
embed's placeholder were three different heights, a line stretched by
`TextStyle.height` left a gap above and below each, and an embed the selection
covered was tinted a second time *over* the embed. Over a hidden spoiler that
drew a different patch at the emoji's positions than at the text's, so the
selection showed where the emoji were. After it, a selection is one rectangle per
line, the line's whole height, behind everything it covers (glyphs, emoji runs
and embeds alike), and an embed is never tinted. Hosts that read the rectangles
(`MarkdownSelectionController.localSelectionRects`, `MarkdownSelectionSurface`'s
box queries) get the same rectangles the render object draws.
The release tag is `v0.4.3`; depend on it by git ref as described under 0.3.0's
*Fork status*.

### Selection
- **CHANGED**: `SelectableBlockPainter.boxesForRange` of the default painters
  (`SelectableTextBlock`, `MultiPainterSelectable`) returns, for each line, one
  rectangle as tall as the line (`BoxHeightStyle.max`) from the first selected
  glyph to the last, with the runs of the line joined, instead of one box per
  style run at the run's own height. Neighbouring lines touch, so a multi-line
  selection is one block of rectangles. A custom `SelectableBlockPainter` that
  implements `boxesForRange` itself is not changed.
- **CHANGED**: the highlight is drawn as one `Path` per block, so no seam shows
  where two rectangles meet and a translucent tint is not drawn twice where they
  overlap.
- **FIXED**: a selection no longer tints an inline embed it covers. The embeds
  pass is the last, after the above-content highlight too, and draws the embed
  as it is; the highlight shows through a transparent embed and round an opaque
  one, as Telegram Android (selection, then the text layout with its emoji spans
  and images), iOS (the highlight node is below the text node) and Desktop (the
  selection fill is drawn before each emoji) do.
- **FIXED**: a selection over a hidden spoiler is the same rectangle at every
  position, so the patch no longer shows where the emoji and embeds are.
- **CHANGED**: `MarkdownPainter.paintEmbeds` (`@internal`) lost its selection
  parameters; it never tints.

## 0.4.2

Before this release a unicode emoji in a body was drawn at the font size, which a
colour emoji font fits into a square smaller than the line, so it looked small
beside an inline embed (1.2 times the font's height) and beside other platforms'
clients. After it, a host that supplies an emoji scanner has each emoji run drawn
at the font's height times a scale it chooses, with the line's height unchanged.
The release tag is `v0.4.2`; depend on it by git ref as described under 0.3.0's
*Fork status*. A selection over a hidden spoiler stays tinted under the dust and
reveals nothing; a test pins the draw order.

### Theme
- **ADDED**: `MarkdownThemeData.emojiRuns` (`MarkdownEmojiRuns`, a scanner of the
  emoji in a text, from the host) and `emojiScale` (default 1). With a scanner,
  each emoji run is drawn at `emojiScale` times the font's height (ascent plus
  descent) instead of the font size, in a line as tall as the text's: a colour
  emoji font draws its glyph into a square of the font size, which is smaller
  than the line, and an inline embed (1.2 times the font's height) beside it
  looked 40 % larger. Without a scanner nothing changes, and the text, its
  offsets, selection, spoiler ranges and link recognizers are the same with
  one.

## 0.4.1

Before this release a body a chat host wrote showed backslashes: its writer
escapes a label the way it escapes any text, and the parser kept the label as
the raw source, so `[\#tag](hashtag:tag)` painted `\#tag`, `[a\*b](u)` painted
`a\*b`, and a wiki-style url the writer had parenthesised
(`[t](https://a.b/c_\(d\))`) opened `https://a.b/c_\(d\)`. A hidden spoiler
also revealed on the release of any press, however long, and in a mode where a
tap means something else. After it, a label and a destination read the way
paragraph text and CommonMark read an escape, and the host decides when a tap on
a spoiler is a reveal. The release tag is `v0.4.1`; depend on it by git ref as
described under 0.3.0's *Fork status*.

### Parser
- **FIXED**: a link, mention-class or image label takes its backslash escapes
  back, the set paragraph text takes (`` ! # $ ( ) * + - . = > [ \ ] _ ` { | } ~ ``),
  so `[a\]b](u)` is the label `a]b`, `[\_x\_](mention:1)` has the text and the
  `name` `_x_`, and `[\#tag](hashtag:tag)` is `#tag`. A backslash before any
  other character stays. `MD$Span.start` / `end` are unchanged: a label span
  still covers its whole `[..](..)` source, and `text` is the unescaped label.
- **FIXED**: a link or image destination takes its escapes back the CommonMark
  way, a backslash before any ASCII punctuation: `[t](a\)b)` has the url `a)b`,
  not `a\)b`, and `<...>` is closed by the first `>` a backslash has not
  escaped. The old reading was locked by `regression_test.dart` as a by-product
  of the 0.1.0 scan for the closing parenthesis, not as a decision; it opened
  every url the chat host's writer parenthesised (`https://a.b/c_(d)` is written
  `c_\(d\)`) at a path that does not exist. A mention id (`mention:a\_b`) and an
  image source are destinations and are unescaped alike.
- **Breaking for consumers**: `extra['href']`, `extra['url']`, `extra['src']`
  and `extra['id']` of a span, and the span's `text` and `extra['name']`, no
  longer hold the backslashes of an escape. Code that stripped them itself must
  stop: a url that really holds `\(` would lose its backslash a second time, and
  a mention id that holds a backslash before punctuation now reads without it.
  The parser golden is unchanged. The dialect conformance table gains the label
  and destination rows, and its known gaps lose them.

### Spoilers
- **ADDED**: `MarkdownSpoilerController.tapReveals` (default true). While false a
  tap on a hidden spoiler reveals nothing, and is still absorbed, so no link or
  embed under the spoiler fires. A host in a message selection turns it off
  there, as Telegram Android does (`ChatMessageCell` takes no spoiler touch
  when `canPerformActions()` is false). `reveal` and `hide` are not affected.
  The hand cursor over a hidden spoiler follows it from the next pointer move.
- **ADDED**: `MarkdownSpoilerController.tapTimeout` (default
  `kLongPressTimeout`, 500 ms; null for no limit). A press held longer is a long
  press, which belongs to the host (the message menu, a selection), and its
  release reveals nothing; it is measured on the pointer events' own
  timestamps, so a stalled frame does not turn a tap into a long press.
  Existing code that held a spoiler for more than half a second and let go to
  reveal it must now tap, or set `tapTimeout = null`, which is the desktop mouse
  click. Android and Qt touch start a long press at that point, Telegram iOS
  at 0.3 s (set `tapTimeout` for it).
- **FIXED**: a pointer up delivered to a disposed `MarkdownRenderObject` threw a
  `RangeError` out of the spoiler tap handler when the pointer had gone down on
  a hidden spoiler. A host that remounts the body between down and up (a long
  press that starts a selection) hit it on every release; the up is now ignored
  by the disposed object and the remounted body, which never saw the down,
  reveals nothing.

## 0.4.0

Before this release a chat body was text and chrome: `![alt](src)` drew its alt
text, `[@alice](mention:42)` was a link that fired `onLinkTap` and carried a
URL-shaped string for the host to sniff, `||x||` was readable plain text, and a
copy (`Ctrl/Cmd+C`, the toolbar's Copy, `getText()`) lost every mark. After it,
the three inline things a chat message holds are part of the package: a
sticker or custom emoji takes room in its line and animates, a mention is a
span style of its own, a spoiler is hidden behind moving dust until a tap
reveals it, and a copy is markdown the same parser reads back. None of it
re-records the cached glyph picture: embeds, dust and ripple are live passes
drawn around it, and a mention is a text style. A host that passes no resolver
and no spoiler controller sees the 0.3.0 rendering, with the exceptions listed
under **Breaking vs 0.3.0**. The release tag is `v0.4.0`; depend on it by git ref
as described under 0.3.0's *Fork status*.

### Inline embeds
- **ADDED**: the embed contract, `MarkdownInlineEmbed`,
  `MarkdownInlineEmbedResolver`, `MarkdownInlineEmbedTarget` (scheme, id, alt),
  `MarkdownInlineEmbedMetrics` (`fontSize`, `ascent`, `descent`,
  `devicePixelRatio`, `extent`) and the paint context. The package knows no
  implementation: a host adapts its own asset type to the contract, the way a
  theme hands over colours.
- **ADDED**: `MarkdownWidget.embedResolver`. An image span whose `src` has a
  scheme the resolver answers for becomes a real inline object: a
  `PlaceholderSpan` (not a `WidgetSpan`, so nothing is built per embed) of
  `1.2 × (ascent + descent)` of the paragraph font, rounded to device pixels, the
  same for every embed of a paragraph and centred on the line, so a line with an
  embed is as tall as one without. The resolver must be a stable instance: a new
  one disposes every embed of the old and resolves again. No resolver, a scheme
  it returns `null` for, or a `src` without a scheme keeps the alt text as
  ordinary text; there is no broken mark.
- **ADDED**: a live paint pass for embeds, after the glyph picture and the
  pannable blocks and before the selection tint above them. An embed's signal
  coalesces into one `markNeedsPaint` per frame per render object; it never
  lays out and never re-records the picture (a test counts the recordings over
  100 signalling frames). `MarkdownInlineEmbed.visible` follows whether the
  embed's block is inside the painted height and goes false before dispose. The
  device pixel ratio comes from `MediaQuery`. Embeds in a list or a table paint
  under that block's clip and pan with their cell. A custom painter that builds
  its own paragraph in a constructor gets no embeds, because the host that owns
  them is internal.
- **ADDED**: alt text is atomic for selection. The placeholder is one U+FFFC in
  the painter's text while the rendered text holds the alt (any number of code
  units), so `SelectableTextBlock` and `MultiPainterSelectable` convert through
  an offset map that is the identity for a paragraph without embeds. The
  controller keeps the alt ranges per document and moves the first boundary of a
  range that falls inside one down to its start and the last up to its end: a
  drag that ends on an embed takes all of it, and copy yields the whole alt,
  also while the message is scrolled out and unmounted.
- **CHANGED**: `SelectableFragment.length` and `.renderedText` are in rendered
  terms. For a block with embeds a painter's `plainText` is no longer its
  rendered text; read `renderedText`.

### Mentions
- **ADDED**: `MD$Style.mention` (`1 << 9`), `MarkdownThemeData.mentionColor` (the
  link colour when null) and `onMentionTap(scheme, id, name)`.
- **CHANGED**: a link whose destination scheme is `mention:`, `username:` or
  `hashtag:` is no longer a link. The parser reads the scheme once and the span
  carries it in `extra` (`scheme`, `name`, and `id` for `mention:`); the span is
  never both `link` and `mention`. It paints in the mention colour with no
  underline and a tap calls `onMentionTap`, never `onLinkTap`. `![a](mention:1)`
  stays an image, `[x](https://a.b)` and `[x](mailto:a@b.c)` stay links. The
  spellings on the wire do not change.

### Spoilers
- **ADDED**: `MarkdownSpoilerController`, passed as
  `MarkdownWidget.spoilerController` together with `documentId`. One bit per
  document: a tap reveals every spoiler of the message. It outlives widgets, so
  a remount (an edit's twin, list virtualization) keeps the state and a quote of
  the same document reveals with the original. It is in memory only and nothing
  re-hides it; `reveal(documentId)` without an origin is the entry for a host
  whose text selection enters a hidden spoiler.
- **ADDED**: hidden text stays where it is. A hidden run gets a transparent
  colour and nothing else, so every glyph box equals the revealed one and a
  reveal swaps pictures without a layout. The painter keeps a glyph picture per
  `(size, revealed)`, two at most, and the fill and ripple are live passes above
  them.
- **ADDED**: a ripple reveal of about 300 ms (`revealDuration`) from the tap
  point, the hidden picture outside the circle and the revealed one inside it,
  reaching the farthest spoiler of the document. Embeds inside a spoiler paint
  at opacity 0 and fade in with it. Motion off (`animate = false`, or
  `MediaQuery.disableAnimationsOf`) reveals in the same frame.
- **ADDED**: Android's particle dust as the fill: one 128 dp tile, simulated once
  per dust frame into a `Picture.toImageSync` image and sampled by every hidden
  spoiler through an `ImageShader`, so the cost is one tile render however many
  spoilers are on screen. One tile per `(text colour, pixel ratio)` per process,
  disposed with its last user; where the engine has no `toImageSync` the frame-0
  dust is drawn static. The package owns no ticker: the host feeds
  `MarkdownSpoilerController.advance(elapsed)` from its clock while `wantsTicks`
  is true (`fillFrameRate` is 30), and with no clock the dust holds still. The
  raster cost of many hidden spoilers on web renderers and a low-end Android
  device has not been measured yet.
- **CHANGED**: a tap on a hidden spoiler is taken by the spoiler and reveals; it
  is not forwarded to the blocks, so a link or mention under it does not fire
  `onLinkTap` / `onMentionTap` until the same tap lands after the reveal. A
  parser limit stays: inside a table cell `||` is a cell delimiter.

### Copy as markdown by default
Before this change a copy was plain text: `**bold** and [a link](https://a.b)`
copied as `bold and a link`. After it, the default copy is markdown source, so a
host that shows the copy as text, or pastes it into another markdown reader,
keeps the formatting.

- **ADDED**: `MarkdownSourceFormatter`, a `MarkdownSelectionFormatter` that
  writes the inline layer as markdown: `**bold**`, `*italic*`, `__underline__`,
  `~~strike~~`, `||spoiler||` (a hidden spoiler is copied revealed, marks
  kept), `==highlight==`, `` `code` ``, `[x](url)`, `[@x](mention:id)`,
  `[@x](username:x)`, `[#x](hashtag:x)` and `![alt](src)`. Literal `\ * ` [ ]`,
  underscores outside words, runs of `~ | =` and line-start block markers are
  backslash-escaped, so the copy parses back to the spans it came from. A fully
  selected block keeps its structure (it extends `MarkdownMarkupFormatter`); a
  selection that starts or ends inside a styled run closes and reopens the
  marks.
- **ADDED**: `MarkdownSelectionFormatter.plain`, the text-only formatter by name.
- **CHANGED (breaking for copy output)**: `MarkdownSelectionController`'s
  default `formatter` is `MarkdownSourceFormatter` (was
  `MarkdownPlainTextFormatter`). Blocks are now joined with a blank line (the
  markup formatter's separator), not a newline. A host that wants the old text
  passes `MarkdownSelectionFormatter.plain`:
  `MarkdownSelectionController(formatter: MarkdownSelectionFormatter.plain)`.
  Code that asserted a copied string, or a clipboard value, will see markers.
- **CHANGED**: where the parser cannot read a span back, the copy keeps the text
  and drops the style: whitespace at the edge of a styled run is written outside
  the marks, a code run holding a backtick is plain text, and an underline that
  starts or ends inside a word is dropped (the parser's `__` must sit at a word
  boundary).
- **CHANGED**: the parser reads `\~`, `\|`, `\=` and `\>` as the literal
  character (they kept their backslash), `\!` before `[` no longer makes the
  link an image, and a closing marker right after an escaped marker of its own
  kind (`**a\***`) closes. Text that contained one of those backslashes now
  loses it.

### The grammar a host writes is pinned
- **ADDED**: `test/parser/dialect_conformance_test.dart`, string fixtures for
  every spelling a chat host writes from its rich text (styles and their
  toggled nesting, links cut at style boundaries, the three mention-class
  schemes, `![alt](unicode:…)` / `document:` / `external:` embeds, escaped
  specials, quote lines, fenced code blocks, and lists at two spaces a level),
  each with the blocks and spans it must parse to. A spelling the parser stops
  reading fails there and not on a screen. The fixtures are strings, not a
  writer's output, because the writer lives in another repository.
- **KNOWN GAPS**, pinned by the same file as today's behaviour so a fix flips
  them: a soft break inside a list item (`"- one  \ncontinued"`) ends the list;
  backslash escapes inside a link label or destination keep their backslash
  (`[a\]b](u)`, `[t](https://x/a_\(b\))`, the latter locked by an existing
  regression test, so a URL with parentheses written by a host keeps its
  backslashes), and an escaped `>` still closes an angle-bracketed destination;
  a code span fenced by two or more
  backticks and a code fence longer than three are not read as code; an embed
  inside a link label is read as a link that ends at the embed's bracket.
- **DOCS**: `rendering.md` states the paint order (selection tint under the
  glyphs, glyph picture for `(size, revealed)`, pannable blocks, spoiler fill and
  ripple, embeds, selection tint above chrome) and the invariant that an embed, a
  spoiler or a mention never re-records the picture per frame; `selection.md`
  covers the offset map, atomic alt text, copy through a hidden spoiler and the
  default formatter; `parser.md` the mention bit and the three schemes;
  `architecture.md` the embed contract and `MarkdownSpoilerController` on the
  public surface; the README lists the three features.

### Breaking vs 0.3.0
Source-breaking only for hosts that implement the render / selection extension
points or read span metadata. Hosts that only use `MarkdownWidget` /
`MarkdownSelectionScope` see three behaviour changes: the copy, mention links
and, once they pass a resolver or controller, embeds and spoilers.

- **Copy is markdown.** `getText()`, the toolbar's Copy and `Ctrl/Cmd+C` write
  `MarkdownSourceFormatter` output, blocks separated by a blank line. Pass
  `MarkdownSelectionFormatter.plain` for the old text.
- **Mention-scheme links no longer fire `onLinkTap`.** `[x](mention:…)`,
  `[x](username:…)` and `[x](hashtag:…)` are `MD$Style.mention` spans without
  `link`, `href` or `url` in `extra`; code that looked for them under
  `MD$Style.link`, or opened their destination, must read `scheme` / `id` /
  `name` and set `onMentionTap`. A host with no `onMentionTap` gets inert text
  where it had a tappable link.
- **Image spans with a resolver are no longer laid out as text.** With
  `embedResolver` set, a resolved image span is one U+FFFC in the painter's text
  and a square in the line. Painters that index a `TextPainter` with rendered
  offsets of a block with embeds must go through `renderedText` /
  `MarkdownEmbedOffsets` (the mixins do). Without a resolver nothing changes.
- **`||x||` hides when a controller and `documentId` are given.** Without them
  it stays plain text, as before.
- **Parser escapes.** `\~ \| \= \>` lose their backslash (see above).
- **Extension points.** `SelectableTextBlock` and `MultiPainterSelectable` also
  implement `SpoilerBlockPainter` (`spoilersRevealed`, `spoilerRects`);
  `paragraphFromMarkdownSpans` takes `revealed` and `embeds`; a custom painter
  that builds a paragraph in its constructor shows alt text and a plain spoiler.
  `MarkdownSelectionSurface` and `SelectableBlockPainter` gain no abstract
  members.

## 0.3.0

Before this release the package was `0.2.0` from upstream: selection worked
across blocks, but a chat host had to build its own chrome (handles, toolbar,
autoscroll) around it, tables overflowed instead of panning, fenced code inside
a quote collapsed into inline monospace, and the scroll surface was assumed to
be a `Scrollable`. After it, the selection chrome, autoscroll, hit testing and
multi-body registry are the engine's own and run against any scroll protocol,
wide tables pan, and nested fences survive. The sections below say what each
change does; **Breaking vs 0.2.0** says what an existing consumer must touch.
Hosts that only use `MarkdownWidget` / `MarkdownSelectionScope` are unaffected.

### Fork status

This repository is `itsezlife/md`, a fork of `DoctorinaAI/md`. The package name
stays `flutter_md`, but the fork **no longer tracks upstream**: nothing is
merged from `DoctorinaAI/md` any more. The last upstream change taken is
`fix(theme): resolve a monospace family the platform actually knows (#29)`
(`12e068f`, cherry-picked; see *Monospace font resolution*). A later upstream
commit is cherry-picked by hand only when it is wanted, and it arrives as a new
commit here, never as a merge. The fork is not published to pub.dev: depend on
it by git ref, and pin the release tag (`v0.3.0`) so a lockfile is reproducible:

```yaml
dependencies:
  flutter_md:
    git:
      url: https://github.com/itsezlife/md.git
      ref: v0.3.0
```

`master` holds `feat/selection-chrome` (which already contains
`feat/horizontally-pannable-blocks`) in full. Two branches stay out on purpose.
`fix/drop-toolbar-on-chrome-ownership-loss` is not merged: both of its fixes
(drop the toolbar overlay when chrome ownership is lost; skip toolbar geometry
restore while a drag is active) already live in `selection_scope.dart` on this
line, and the branch also carries commits that split `clampMarkdownToLines`
and the monospace work out of an upstream PR, so merging it would delete that
API. `prototype/spoiler-particles` is a throwaway experiment and never merges.

### Horizontally pannable blocks
- **ADDED**: `BlockPainter$ScrollableTable` for wide tables that clip and pan
  instead of overflowing. Pick it in `MarkdownThemeData.builder`; the default
  `BlockPainter$Table` is unchanged. Pass `enabled: false` to keep the clip but
  refuse new pan; `restoreScrollOffset` still applies so a disabled rebuild does
  not wipe the controller pan store. Painters that implement
  `HorizontallyPannableBlock` get touch pan and fling from the render object
  (mouse/stylus keep selection; wheel/trackpad pan when `|dx| >= |dy|`). Offsets
  live on `MarkdownSelectionController` (`horizontalPanOffset` /
  `setHorizontalPanOffset` / `replaceHorizontalPanOffsets`), survive remount,
  and remap on `putDocument` / `setDocuments` (same-index text match, same-index
  table kind across streaming edits, else content-anchored). Dry layout does not
  commit pan. A temporary fit-width layout does not clear a stored offset. Leading
  edge follows `textDirection` (RTL from the right). Fling respects `TickerMode`.
  Pan paints outside the glyph `Picture` cache; selection highlights stay clipped
  to the table viewport. `MarkdownHorizontalPanStore` is the remount contract
  (`MarkdownSelectionController` implements it).

### Breaking vs 0.2.0

Source-breaking only for hosts that implement the render / selection
extension points or reach into a default block painter's fields. Ordinary
`MarkdownWidget` / `MarkdownSelectionScope` users are unaffected.

- **REMOVED**: `BlockPainter$Quote.painter` and `BlockPainter$Alert.bodyPainter`.
  Both painters now stack nested children, so a single body `TextPainter` no
  longer exists. Read `renderedText` / `fragments` (from
  `MultiPainterSelectable`) instead.
- **CHANGED**: `BlockPainter$Quote` and `BlockPainter$Alert` mix in
  `MultiPainterSelectable` instead of `SelectableTextBlock`. Subclasses that
  overrode `selectionPainter` / `selectionOrigin` must move to `fragments`.
- **CHANGED**: `SelectableBlockPainter` gained `positionAndAffinityForLocal`,
  `caretRectFor`, `hitsRenderedTextAt` and
  `selectionHighlightAboveCachedContent`. Custom painters built on the
  `SelectableTextBlock` / `MultiPainterSelectable` mixins inherit working
  implementations; painters that `implements SelectableBlockPainter` directly
  must add all four.
- **CHANGED**: `MarkdownSelectionSurface` gained `hitForGlobal`,
  `hitsSelectableGlyphs`, `isLinkAtGlobal`, `caretRectFor`,
  `localBoxesForRange`, `hasSelectionHandleLeaders` and
  `clearSelectionHandleLayersIfLinked`. Custom surfaces must implement them.
- **CHANGED**: `MarkdownThemeData.copyWith` returns `MarkdownThemeData` instead
  of `ThemeExtension<MarkdownThemeData>` (callers gain, overriders must narrow).
- **CHANGED**: `MarkdownRenderObject.updateSelection` takes an optional
  `markdown:`. `@meta.internal`, but `MarkdownWidget` subclasses that call it
  must now invoke it **before** `update` (see the registry fix below).

### Quote / alert nested fenced code
- **FIXED**: Fenced code (` ```lang ` / `~~~`) inside a blockquote or GitHub
  alert is re-parsed as nested `MD$Code` in `MD$Quote.blocks` /
  `MD$Alert.blocks`, instead of being consumed as inline monospace by backtick
  pairing (` `` ` + monospace + ` `` `). The fenced code keeps its
  indentation, fences inside nested quotes (`> > ```…`) are nested code too,
  and a fence may follow the `>` after up to three spaces or a tab (lines
  inside the code keep their indentation verbatim). Blank `>` lines around an
  alert body add no extra gap.
- **ADDED**: Optional `blocks` on `MD$Quote` / `MD$Alert` (empty for leaf
  inline bodies). Render and `markdownBlockRenderedText` walk nested children
  when present.
- **FIXED**: Prose nested inside a quote (paragraphs/lists/headings beside a
  fence) uses `quoteStyle` again; code/table chrome keeps the document theme.
- **FIXED**: Nested children route through `MarkdownThemeData.builder` like
  top-level blocks. A host that replaces the code painter (a fence with a copy
  button, say) was silently getting the default one inside `> …`.

### Glyph-tight hit testing
- **CHANGED**: Hover I-beam and link hit-testing use rendered **line/glyph
  boxes**, not the full max-width layout of a paragraph. Empty horizontal
  gutter beside a short line (quote and alert bodies included) is no longer
  I-beam / click-to-open. Glyph boxes are cached per `TextPainter` layout, so
  hovering stays cheap over long fenced code blocks.
- **CHANGED**: Gesture *starts* (`hitsSelectableContent`) stay **surface-
  bounds**. A press inside the document or bubble arms text selection.
  Drag-extend may still clamp outside glyphs.
- **CHANGED**: Mouse single-click that misses selectable content while a
  non-collapsed range is active clears the selection, instead of leaving
  the old range.
- **ADDED**: `SelectableBlockPainter.hitsRenderedTextAt`,
  `MarkdownSelectionSurface.hitsSelectableGlyphs`, and
  `MarkdownSelectionController.hitsSelectableGlyphs`.
- **CHANGED**: Glyph boxes are cached per `TextPainter` layout. They are read on
  every hover event (I-beam / link cursor); recomputing
  `getBoxesForSelection` over a whole block allocated one box per run per line
  on every mouse move (thousands of rects over a long fenced code block).

### Selection host gates
- **ADDED**: `MarkdownSelectionScope.canStartSelectionAt` — optional host gate
  so enclosing UIs can refuse selection starts on chrome (links, code headers)
  without the scope claiming the pointer. A refusal also un-arms the drag: the
  recognizers still join the arena while a range is live (so a chrome tap can
  dismiss it), and without this a long press / drag on refused chrome kept
  extending the active selection from that point.
- **ADDED**: `MarkdownSelectionScope.enableTouchGestures` — when false, touch /
  stylus / trackpad selection recognizers stay off; mouse multi-click, handles,
  toolbar, and keyboard remain. Focus loss also does not clear the range (host
  viewport may steal focus).
- **ADDED**: `MarkdownSelectionScope.enableTouchConsecutiveTaps` — when false
  (with `enableTouchGestures` true), touch long-press → word → drag-extend
  still arms, but touch multi-tap / horizontal-drag selection does not. Chat
  hosts use this so taps stay with the viewport while continuous text entry
  works. Focus loss also does not clear the range in that mode.
- **ADDED**: `MarkdownSelectionScope.ownsSelectionChrome` — optional host gate
  so only the scope that owns the selection’s document paints handles/toolbar
  when several scopes share one controller (chat per-body mounts).
- **FIXED**: Disabled / non-owning sibling scopes no longer clear handle
  leaders on every shared-controller surface. Clearing is scoped to leaders
  that reference that scope’s own `LayerLink`s, so chat dual mounts keep
  handles after non-collapsed range commits (including repeated handle-drag
  settles).
- **FIXED**: A scope that loses `ownsSelectionChrome` for the live selection
  document now removes its own context-menu overlay (and does the same when
  handles are disabled for that reason). Previously only handles were cleared,
  so a prior bubble’s adaptive toolbar could linger after selection moved to a
  sibling scope. `toolbarWanted` is left alone so the owning scope can still
  restore on settle.
- **ADDED**: `MarkdownSelectionSurface.hasSelectionHandleLeaders`,
  `clearSelectionHandleLayersIfLinked`, and
  `MarkdownSelectionScopeState.selectionHandleLeadersAttached` for observing
  coherent handle-leader attachment across multi-scope hosts.
- **CHANGED**: Flipping `enabled` from false → true with an existing
  non-collapsed range restores handles; when `toolbarWanted` is set, restores
  the toolbar. While disabled, the scope stays inert for chrome (no toolbar /
  handles) but keeps `toolbarWanted` for that restore path. Disabling the
  scope mid-drag aborts the drag.

### Dynamic cursor resolution & span bounding boxes
- **ADDED**: `MarkdownThemeData.cursorResolver` and
  `MarkdownWidget.cursorResolver` (`MarkdownCursorResolver`) — unopinionated
  hook to dynamically resolve hover mouse cursors per local offset, block
  index, and block model, falling back to default link/text/defer cursors when
  returning null. The hover cursor survives rebuilds that pass a new resolver
  closure and re-resolves when the theme or resolver changes.
- **ADDED**: `MarkdownSelectionSurface.localBoxesForRange` (backed by the
  internal `MarkdownPainter.localBoxesForRange`) — fast query returning
  content-local bounding boxes for an arbitrary character range within a block,
  directly from cached block painters without re-layout.

### Registry / multi-body selection
- **FIXED**: `removeDocument` defers while a surface for that id is mounted
  and flushes on `detachSurface`; a later `putDocument` cancels the pending
  remove. Parent `State.dispose` can run before child detach — eager remove
  left hittable surfaces with no registry entry (`rangeFor` / ordering broken).
- **FIXED**: `rangeFor` and endpoint ordering ignore unregistered document ids
  instead of treating them as index `-1` (which painted every body from the
  start of the registry through the other endpoint).
- **CHANGED**: `MarkdownRenderObject` heals with `putDocument` on attach /
  when the controller is wired while already attached, so a mounted selectable
  surface is never missing from the registry. Prefer explicit app registration
  for unmounted docs and unique reading-order `order` values.
- **FIXED**: Recycling a `MarkdownWidget` element onto a different `documentId`
  (a virtualized chat list reusing a slot) overwrote the **outgoing** document's
  registry model with the incoming body. `MarkdownWidget` now rewires the
  selection registry before pushing the new model, and
  `MarkdownRenderObject.updateSelection` takes the incoming `markdown:` so the
  heal lands on the right id.
- **FIXED**: `putDocument` without an explicit `order` appended at `_docs.length`
  which sorted **ahead** of sparse explicit orders (chat hosts key `order` on
  the message id), so a healed body jumped to the front of the conversation and
  reversed extracted text. It now sorts after every registered document.
- **FIXED**: Documents sharing an `order` could swap places on any re-sort
  (`List.sort` is not stable), silently reversing extracted text. Ties now break
  on registration sequence.
- **FIXED**: `MarkdownSelectionScope.onSelectionChanged` fired synchronously
  from inside build / layout — a streaming `putDocument` reconciling the range
  away (from `MarkdownWidget.updateRenderObject`) or a deferred
  `removeDocument` flushing from `RenderObject.detach` threw
  "setState() called during build" in any host that rebuilds from the callback.
  Delivery is now coalesced to the end of the frame in those phases.

### Selection chrome (SelectionArea parity)
- **ADDED**: Read-only selection chrome on the controller /
  `MarkdownSelectionScope` path brought up to Flutter `SelectableRegion` /
  `SelectionArea` quality without remounting SelectionArea:
  - Content-gated touch `TapAndHorizontalDragGestureRecognizer` + long-press
    (consecutive taps, no `DoubleTapGestureRecognizer` arena delay); mouse
    `TapAndPanGestureRecognizer`.
  - Gesture **starts** require a hit on mounted selectable markdown (chrome /
    empty space do not nearest-neighbor clamp); clamp remains for **extend**
    across gaps.
  - Soft-wrap affinity on handles; directed base/extent edges with reverse
    handle types; coincident-caret separation; handle proxies when an endpoint
    surface unmounts (virtualization), on the correct end for reversed
    selections too.
  - Native `SelectionOverlay` handles + magnifier on touch; LeaderLayer follow
    across scroll / multi-widget hosts.
  - Keyboard Copy / Select-all / Shift-extend / Esc; adaptive Copy / Select-all
    toolbar with live re-anchoring.
  - Word / block granular multi-tap and long-press; link hand cursor / I-beam on
    selectable content.
- **ADDED**: `MarkdownSelectionController.isSelectionReversed` (base after
  extent in reading order), `selectionEndpointGlobalRect({base})` (global
  caret rect of a mounted endpoint, null when unmounted, no proxying),
  `selectionEndpointOverlaps(rect, {base})` and
  `anySelectionEndpointOverlaps(rect)` (whether a mounted endpoint caret
  intersects a global rect), and `toolbarWanted` (the toolbar-restore intent;
  reset when the registry drops or collapses the range).
- **CHANGED**: Toolbar hides while expanding (body or handle drag) and may
  re-show on drag end; anchors recompute on selection change, host/ancestor
  scroll, and mounted-surface layout change. Scroll-driven restores are
  skipped while a drag is active.
- **CHANGED**: Toolbar placement — both endpoints in clip use stock
  above-preferring anchors; **bottom-only** endpoint prefers below that caret;
  neither endpoint in clip (tall mid-viewport) top-pins so the below-fallback
  cannot sink to the host bottom; empty intersection hides the overlay while
  `toolbarWanted` restores on scroll-back / remount.
- **CHANGED**: Desktop selection toolbar parity with stock Flutter:
  - On desktop (`macOS`, `Linux`, `Windows`), mouse drags, double/triple clicks,
    keyboard shortcuts (`Cmd/Ctrl+A`), and programmatic selection updates
    do not pop up the toolbar.
  - Right-click on desktop shows the context toolbar at the click coordinates
    without mutating the active selection (no select-word / caret collapse).
  - Desktop context menu preserves its right-click anchor when triggering
    actions such as "Select all", rather than jumping to selection endpoints.
  - Desktop context menu dismisses immediately upon scroll, but survives
    streamed updates, sibling updates and resizes, with or without a
    selection.
  - On mobile (`Android`, `iOS`), touch gestures and programmatic selection
    (`selectAll`, `selection = ...`) continue to present the adaptive toolbar
    and handles with action items.

### Autoscroll is scroll-protocol agnostic
- **ADDED**: `MarkdownAutoscrollTarget` — the scroll surface autoscroll drives,
  behind three members (`viewport`, `canScroll`, `applyScrollDelta`). Deltas are
  **screen-space content movement** (positive moves content up), never scroll
  offsets, so reverse axes and inverted anchors are the adapter's problem.
- **ADDED**: `MarkdownScrollableAutoscrollTarget` — the built-in sliver adapter
  (`ScrollableState` / `ScrollPosition`), used when no resolver is configured.
  Handles `AxisDirection.up` / `.left` sign flipping.
- **ADDED**: `MarkdownSelectionAutoscrollConfig.targetResolver`
  (`MarkdownAutoscrollTargetResolver` + `MarkdownAutoscrollRequest`) so a host
  with its own scroll implementation — an anchored chat viewport, a `RenderBox`
  that positions children itself, a transform canvas — can be driven without a
  `Scrollable` anywhere in the tree. Plus `MarkdownCallbackAutoscrollTarget` and
  `MarkdownAutoscrollViewport` (global bounds + band inset) for closure hosts.
- **CHANGED**: `applyMarkdownSelectionAutoscroll` takes an optional `target:`;
  `context:` is now optional and only used to resolve the built-in sliver
  target. Band, host-union gate and arming logic no longer reference
  `ScrollPosition` at all.
- **FIXED**: The scroll surface is resolved **once per drag** and cached. It
  used to walk the whole element subtree twice on every autoscroll frame (to
  find the surface's element, then the nearest `Scrollable`).
- **ADDED**: `MarkdownSelectionAutoscrollConfig.useHostUnionGate` (default
  `true`, the existing behaviour). Turn it off when the markdown bodies **are**
  the scrolling content and the host builds only what is visible: such a host's
  mounted union is barely larger than the viewport, so the gate would veto a
  drag that should keep paging through history. The target's `canScroll` and
  the delta it reports applying are then the only stops.
- **ADDED**: `MarkdownSelectionAutoscrollConfig.copyWith`, `==` / `hashCode`.

### Selection engine rework
- **ADDED**: Edge-zone autoscroll while dragging (body / handle / long-press)
  near the padded viewport — host-union hard-stop, direction arming gate,
  past-viewport max velocity while the union still allows that direction
  (`MarkdownSelectionScope.autoscroll`, default `edgeZone: 48`).
- **CHANGED**: Toolbar hides while expanding (body or handle drag) and may
  re-show on drag end; anchors recompute on selection change, host/ancestor
  scroll, and mounted-surface layout change.
- **FIXED**: Scroll / geometry toolbar restore is skipped while a selection
  drag is active (`_dragGlobal`). Autoscroll `ScrollNotification`s must not
  re-present the adaptive toolbar mid-gesture even when `toolbarWanted` was
  re-armed (e.g. a host restoring a clamped range via the public `selection`
  setter).
- **CHANGED**: Toolbar placement — both endpoints in clip use stock
  above-preferring anchors; **bottom-only** endpoint prefers below that caret;
  neither endpoint in clip (tall mid-viewport) top-pins so the below-fallback
  cannot sink to the host bottom; empty intersection hides the overlay while
  `toolbarWanted` restores on scroll-back / remount.
- **FIXED**: Selection highlight stays outside the glyph `Picture` cache —
  under glyphs by default (sharp text), with a second pass **above** opaque
  chrome (`selectionHighlightAboveCachedContent`) for code fences, table zebra
  rows, and inline monospace / highlight backgrounds.
- **FIXED**: Focus loss does not clear selection while a pointer drag is active
  (list rebuilds during autoscroll); geometry walks defer off `performLayout`.
- **FIXED**: `Esc` with no selection is no longer swallowed by the scope, so it
  reaches ancestors (closing a dialog, say).

### Edge autoscroll while selecting
- **ADDED**: Edge-zone autoscroll while dragging (body / handle / long-press)
  near the padded viewport — host-union hard-stop, direction arming gate,
  past-viewport max velocity while the union still allows that direction
  (`MarkdownSelectionScope.autoscroll`, `MarkdownSelectionAutoscrollConfig`
  with `copyWith` / `==`, default `edgeZone: 48`). Edge bands are capped at
  half the viewport; speed is time-based, not tied to the pointer event rate;
  a vertical edge drag only drives a vertical `Scrollable`; pointer cancel and
  long-press cancel stop it. The scroll surface is resolved once per drag.
- **ADDED**: `MarkdownAutoscrollTarget` — the scroll surface autoscroll drives,
  behind three members (`viewport`, `canScroll`, `applyScrollDelta`). Deltas are
  **screen-space content movement** (positive moves content up), never scroll
  offsets, so reverse axes and inverted anchors are the adapter's problem.
- **ADDED**: `MarkdownScrollableAutoscrollTarget` — the built-in sliver adapter
  (`ScrollableState` / `ScrollPosition`), used when no resolver is configured.
  Handles `AxisDirection.up` / `.left` sign flipping.
- **ADDED**: `MarkdownSelectionAutoscrollConfig.targetResolver`
  (`MarkdownAutoscrollTargetResolver` + `MarkdownAutoscrollRequest`) so a host
  with its own scroll implementation — an anchored chat viewport, a `RenderBox`
  that positions children itself, a transform canvas — can be driven without a
  `Scrollable` anywhere in the tree. Plus `MarkdownCallbackAutoscrollTarget` and
  `MarkdownAutoscrollViewport` (global bounds + band inset) for closure hosts.
- **ADDED**: `MarkdownSelectionAutoscrollConfig.useHostUnionGate` (default
  `true`). Turn it off when the markdown bodies **are** the scrolling content
  and the host builds only what is visible: such a host's mounted union is
  barely larger than the viewport, so the gate would veto a drag that should
  keep paging through history. The target's `canScroll` and the delta it
  reports applying are then the only stops.

### Layout
- **FIXED**: `MarkdownWidget` reports its intrinsic height and max intrinsic
  width, so `IntrinsicHeight` (and similar) no longer collapses it to 0.
- **FIXED**: A fenced code block too narrow for its padding is inert for
  selection, so `selectAll` at tiny widths no longer crashes, and no longer
  throws `TextPainter.paint called when text geometry was not yet calculated`
  while painting (at widget widths of a few dozen pixels, less inside a quote
  or alert).

### Right-to-left layout
- **FIXED**: With `MarkdownThemeData.textDirection` set to
  `TextDirection.rtl`, blocks were still laid out left-to-right: paragraphs
  and headings sat against the left edge, list bullets, quote bars and the
  alert accent bar were on the left, and table columns ran left to right.
  Blocks now mirror: text aligns to the right edge, bullets and bars sit on
  the right, and the first table column is on the right (unaligned data
  cells start on the right; explicit `:--` / `--:` alignment stays physical).
  Link taps, hit testing and text selection follow the mirrored positions,
  under tight and min-width constraints too. Left-to-right layout is
  unchanged.
- **FIXED**: Selection handles on right-to-left text sit at the logical start
  (right edge) and end (left edge) of the selection. Each handle follows the
  `textDirection` of the document it sits on, not the ambient
  `Directionality`: the two can differ, and one selection can span documents
  of both directions. Proxy handles for a scrolled-off edge land on the
  reading start / end of the visible selection in either direction.
- **FIXED**: A table too wide to fit overflows past its end edge in either
  direction, so the columns read first stay in view (to the left of the
  widget for right-to-left text).
- **FIXED**: Link taps inside quotes account for the quote's indent.
- **CHANGED**: Under tight constraints (for example a fixed-width chat
  bubble), right-to-left content aligns to the full width, like `Text`. Under
  loose constraints the widget still sizes to its content.
- **CHANGED**: Fenced code blocks always render left-to-right, even in
  right-to-left documents.
- **ADDED**: `ParagraphGestureHandler.hitTestInlineSpanWithPointerEvent` takes
  an optional `origin`, for painters whose text is not painted at the block
  origin.
- **FIXED**: A dry layout at other constraints, made after the real layout,
  left hit testing, highlights and link taps at the measured positions while
  the glyphs stayed put. The real layout is now restored after measuring.

### Monospace font resolution
- **FIXED**: Inline `` `code` `` and fenced blocks pick a monospace family the
  host platform can actually resolve. Flutter hands the family straight to the
  platform font manager, and CoreText (iOS / macOS) and DirectWrite (Windows)
  do not know the CSS generic `'monospace'` — code silently rendered in the
  proportional body face there. Those two now get `Menlo` / `Consolas`.
  **Android, Fuchsia, Linux and web keep `'monospace'`**, so the primary face
  there is unchanged. Note that on web it is unchanged but still wrong:
  CanvasKit / skwasm reach no system fonts, so no family name resolves there
  and code has always rendered in the proportional default. Bundling a
  monospace asset and pointing `monospaceFontFamily` at it is the only fix,
  and that is a host decision.
- **CHANGED**: code spans now carry a `fontFamilyFallback` on every platform:
  the monospace chain followed by whatever `textStyle` already carried. A
  monospace face covers Latin and little else, so the body face's chain is
  appended rather than replaced — a host's CJK / emoji coverage keeps working
  inside `` `code` `` and fenced blocks.
- **ADDED**: `MarkdownThemeData.monospaceFontFamily` /
  `monospaceFontFamilyFallback` to pin a bundled face. Both default to the
  platform-resolved chain above and are resolved once, in the constructor. One
  knob covers both inline `` `code` `` and fenced blocks — there was previously
  no supported way to change the fenced-block face at all: `BlockPainter$Code`
  built its style in a static method reading a global, so even overriding
  `textStyleFor` moved inline code only. An empty fallback list means "no
  monospace fallbacks", not "unset" — `textStyle`'s own chain still applies.
- **CHANGED**: `MarkdownThemeData.mergeTheme` resolves the default face from
  `ThemeData.platform` rather than the global `defaultTargetPlatform`, so an
  app that adapts its Material theme to another platform gets that platform's
  face. `ThemeData.platform` defaults to `defaultTargetPlatform`, so this only
  moves for an app that deliberately overrode it.

### Monospace font resolution
- **FIXED**: Inline `` `code` `` and fenced blocks pick a monospace family the
  host platform can actually resolve. Flutter hands the family straight to the
  platform font manager, and CoreText (iOS / macOS) and DirectWrite (Windows)
  do not know the CSS generic `'monospace'` — code silently rendered in the
  proportional body face there. Those two now get `Menlo` / `Consolas`.
  **Android, Fuchsia, Linux and web keep `'monospace'`**, so the primary face
  there is unchanged. Note that on web it is unchanged but still wrong:
  CanvasKit / skwasm reach no system fonts, so no family name resolves there
  and code has always rendered in the proportional default. Bundling a
  monospace asset and pointing `monospaceFontFamily` at it is the only fix,
  and that is a host decision.
- **CHANGED**: code spans now carry a `fontFamilyFallback` on every platform:
  the monospace chain followed by whatever `textStyle` already carried. A
  monospace face covers Latin and little else, so the body face's chain is
  appended rather than replaced — a host's CJK / emoji coverage keeps working
  inside `` `code` `` and fenced blocks.
- **ADDED**: `MarkdownThemeData.monospaceFontFamily` /
  `monospaceFontFamilyFallback` to pin a bundled face. Both default to the
  platform-resolved chain above and are resolved once, in the constructor. One
  knob covers both inline `` `code` `` and fenced blocks — there was previously
  no supported way to change the fenced-block face at all: `BlockPainter$Code`
  built its style in a static method reading a global, so even overriding
  `textStyleFor` moved inline code only. An empty fallback list means "no
  monospace fallbacks", not "unset" — `textStyle`'s own chain still applies.
- **CHANGED**: `MarkdownThemeData.mergeTheme` resolves the default face from
  `ThemeData.platform` rather than the global `defaultTargetPlatform`, so an
  app that adapts its Material theme to another platform gets that platform's
  face. `ThemeData.platform` defaults to `defaultTargetPlatform`, so this only
  moves for an app that deliberately overrode it.

## 0.2.0

> **Upgrading from 0.0.x?** See the
> [migration guide](docs/migration/0.0.x-to-0.2.x.md). 0.2.x is almost entirely
> backward compatible — the only required code change is a new `alert` branch
> for direct `MD$Block.map` / `switch` callers.

- **ADDED**: Opt-in, dependency-free syntax highlighting for fenced code blocks
  (65+ languages, GitHub light/dark themes). Assign a `SyntaxHighlighter` to the
  new `MarkdownThemeData.highlighter` field; the default (unset) renders code as
  plain monospace, so existing usage is unchanged. New public API on
  `package:flutter_md/highlight.dart`: `SyntaxHighlighter`, `MarkdownHighlighter`,
  `CodeHighlightTheme`, `Grammar`, `GrammarToken`, `compileHighlightPattern`
  (`SyntaxHighlighter` / `CodeHighlightTheme` are also re-exported from the main
  entrypoint). Each language is its own library
  (`package:flutter_md/highlight/<lang>.dart`, e.g. `HighlightDart.grammar`) with
  no central registry, so importing one never references the others and unused
  grammars tree-shake away — a Dart-only app adds ~0 beyond the engine; all 65
  add ~62 KB gzipped. `HighlightThemes.githubDark` / `githubLight`
  (`highlight/themes.dart`) provide ready themes; `allHighlightLanguages`
  (`highlight/all.dart`) is a convenience registry of every grammar for
  demos/tooling (it references all languages, so unused ones can no longer
  tree-shake away). The highlighter only partitions text — never edits it — so
  selection and copy stay aligned. Grammars are generated by
  `tool/highlight_codegen` (adapted from Prism, MIT).
- **ADDED**: Cross-block and cross-widget text selection. A
  `MarkdownSelectionController` anchors the selection on the immutable model, so
  it spans multiple blocks and multiple `MarkdownWidget`s and survives list
  disposal (e.g. chat scrolling). New public API: `MarkdownSelectionController`,
  `MarkdownSelectionScope`, `MarkdownSelectionGroup`, `MarkdownPosition`,
  `MarkdownSelection`, `MarkdownDocumentRef`, `MarkdownSelectedContent`
  (+ document/block), `MarkdownSelectionFormatter` /
  `MarkdownPlainTextFormatter` / `MarkdownMarkupFormatter`,
  `MarkdownReconciliationPolicy`, `MarkdownSelectionSurface`,
  `markdownBlockRenderedText`, and
  `SelectableBlockPainter` / `SelectableTextBlock`.
- **ADDED**: `StreamingMarkdownParser`, an incremental parser for streaming
  sources such as LLM token output. It freezes completed blocks (a block ends at
  a blank line, outside any open code fence) so only the still-growing tail is
  re-parsed as tokens arrive — turning the `O(N²)` cost of re-parsing the whole
  buffer on every token into roughly `O(tail)` (3–14× faster on a full message
  stream in `benchmark/streaming_benchmark.dart`). `parser.add(chunk)` returns
  the growing `Markdown`, always identical block-for-block to
  `Markdown.fromString(everythingSoFar)`, and a `Stream<String>.toMarkdown()`
  extension wires it into a stream transform. Pass a configured `MarkdownDecoder`
  (e.g. `inlineMath: true`) to match `Markdown.fromString`. The batch
  `MarkdownDecoder` hot path is byte-for-byte unchanged.
- **ADDED**: `MarkdownMarkupFormatter`, a built-in "Copy as Markdown" formatter.
  Pass it to `getText()` (or set `controller.formatter`) to reconstruct Markdown
  structure on copy — heading `#`s, nested list markers with task checkboxes,
  blockquote/alert `>` prefixes, fenced code and pipe tables — for blocks the
  selection covers in full; partially-selected boundary blocks fall back to the
  plain sliced text so nothing outside the selection is emitted. The default
  copy behaviour is unchanged (`MarkdownPlainTextFormatter`).
- **ADDED**: `MarkdownWidget` gains optional `documentId` and `controller`
  parameters (resolved from the ambient scope). Backward compatible: a widget
  with no `documentId` is inert.
- **ADDED**: Lists and tables are now interactively selectable. A new
  `MultiPainterSelectable` mixin (+ `SelectableFragment`) maps pointer positions
  and highlight boxes across the many `TextPainter`s of a list's items or a
  table's cells, so a drag can start or end inside a list item or table cell and
  the copied text keeps the `\n` / `\t` separators of `markdownBlockRenderedText`.
- **ADDED**: Keyboard shortcuts and a context toolbar on `MarkdownSelectionScope`,
  mirroring `SelectableRegion`/`SelectableText`. When focused: `Ctrl/Cmd+C`
  copies, `Ctrl/Cmd+A` selects all, `Shift`+arrows extend by character / word /
  line / document (and vertically by geometry), `Esc` clears. Right-click
  (desktop) / long-press (mobile) shows an adaptive Copy / Select-all toolbar.
  The scope is now a `StatefulWidget` with a public `MarkdownSelectionScopeState`
  (`copySelection` / `selectAll` / `clearSelection` / `showToolbar` /
  `hideToolbar` / `contextMenuButtonItems` / `contextMenuAnchors`). New
  customization params: `focusNode`, `enabled`, `selectionColor`,
  `contextMenuBuilder`, `magnifierConfiguration`, `selectionControls`,
  `onSelectionChanged`. New controller ops: `selectionColor`,
  `globalSelectionRects`, `moveSelectionEdgeToGlobal`, and the
  `extendSelectionBy*` family; `MarkdownPosition.copyWith`.
- **ADDED**: Native selection handles and a magnifier on touch platforms,
  driven by Flutter's `SelectionOverlay`. Selection endpoints push
  `LeaderLayer`s from the render objects so the handles follow the content as it
  scrolls (and across multiple `MarkdownWidget`s); dragging a handle adjusts the
  selection and shows the platform magnifier. Handles/magnifier respect the
  platform (`selectionControls`, `magnifierConfiguration`) and are absent on
  desktop, matching `SelectableText`. New surface geometry:
  `localSelectionRects`, `setSelectionHandleLayers`, `repaintSelection`, and
  `MarkdownSelectionController.selectionHandleEndpoints` /
  `MarkdownHandleEndpoints`.
- **ADDED**: Word- and block-granular selection gestures. Double-click/tap
  selects the word under the pointer, triple-click/tap selects the whole block,
  a single click collapses (clears) the selection, and `Shift`-click extends it.
  Dragging after a double/triple click keeps word/block granularity; a touch
  long-press grabs the whole word (then extends by word), and a touch
  double-tap selects the word and pops the toolbar. Word boundaries use the
  platform word segmentation (`TextPainter.getWordBoundary`), so double-click
  keeps intra-word punctuation like apostrophes (`can't`). New controller ops:
  `selectWordAtGlobal`, `selectBlockAtGlobal`, `wordSelectionAt`,
  `blockSelectionAt`, `extendSelectionGranular`, and `wordRangeIn`; new surface
  geometry `MarkdownSelectionSurface.wordBoundaryForGlobal`.
- **ADDED**: Mouse cursor feedback — a `MarkdownWidget` shows the click (hand)
  cursor over actionable links, the text (I-beam) cursor while it participates
  in a selection controller, and otherwise the default cursor.
- **CHANGED**: `MarkdownWidget`'s render object now draws the selection
  highlight outside the cached content `Picture` and becomes a repaint boundary
  when selectable, so selection/drag repaints do not rebuild the glyph cache.
  The highlight color is now customizable via the controller / scope. The
  highlight is painted on top of (rather than beneath) the glyphs, so a
  translucent selection stays visible over opaque backgrounds — code fences,
  `inline code`, and `==marked==` spans.
- **EXAMPLE**: Reworked the demo tabs — a longer, richer chat (tables, code,
  nested/task lists, alerts, math, token-by-token streaming with a typing
  indicator, Select-all/Clear) and a Selection tab that spans every block type.

## 0.1.0

- **ADDED**: GitHub-style alert blocks (`> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`,
  `> [!WARNING]`, `> [!CAUTION]`) via the new `MD$Alert` block and `MD$AlertType`.
- **ADDED**: GitHub task-list items (`- [ ]` / `- [x]`) via `MD$ListItem.checked`
  and `MD$ListItem.isTask`, rendered with a checkbox.
- **ADDED**: Table column alignment (`:---`, `:--:`, `---:`) captured on
  `MD$Table.alignments` and applied when rendering.
- **ADDED**: `linkStyle` on `MarkdownThemeData` to customize link text styling
  (thanks @inamhusain, #22).
- **ADDED**: Per-type alert accent colors via `MarkdownThemeData.alertColors`
  and `alertColorFor`.
- **ADDED**: Opt-in `$...$` inline LaTeX math conversion to Unicode, **disabled
  by default**. Enable with `MarkdownDecoder(inlineMath: true)` or
  `Markdown.fromString(text, inlineMath: true)`. Supports LaTeX commands
  (`\alpha`, `\rightarrow`, ...), superscripts/subscripts (`x^2`, `H_2O`,
  `x^{10}`), is code-span and code-block safe, and preserves currency (`$5`).
  The command table is configurable via `mathReplacements` (extend the
  exported `kMarkdownMathCommands`). Originally proposed in #21 by
  @ibragimov05.
- **FIXED**: `\$` is now a recognized backslash escape, producing a literal
  dollar sign (and opting a `$...$` run out of math conversion).
- **CHANGED**: Thematic breaks now support `***` and `___` (and spaced variants
  like `- - -`), and no longer greedily consume text after `---`.
- **CHANGED**: `~~~` fenced code blocks are now recognized in addition to ` ``` `.
- **FIXED**: Emphasis no longer leaks to the end of the line for stray or
  unterminated markers (e.g. `5 * 6 = 30`, `**bold never closed`).
- **FIXED**: Intraword underscores are no longer treated as emphasis
  (e.g. `snake_case`, `object_id` are preserved).
- **FIXED**: ATX headings require a space after `#`; `#hashtag` and 7+ `#`
  are no longer headings, and trailing `#` sequences are stripped.
- **FIXED**: Emphasis surrounding a link/image is now merged onto the link span.
- **FIXED**: Link/image targets support `<url>` and single-quoted titles.
- **FIXED**: `MarkdownThemeData.copyWith` no longer drops `builder` and `onLinkTap`.
- **BREAKING**: `MD$Block.map`/`maybeMap` gained an `alert` branch for the new
  `MD$Alert` block type.
- **PERFORMANCE**: Rewrote the parser hot path — a single-span fast path for
  plain text, first-code-unit guards that keep regexes off paragraph lines,
  hand-rolled list-line and link-target parsing (removing per-line / per-link
  `RegExp` allocation), lazy link-extraction gated on `[`, and a range-copy
  escape rebuild (no more per-character hash-set lookups). Together with math
  now being opt-in, the default parse path is roughly **45% faster** across
  representative workloads (links −68%, lists −61%, escapes −68%). Output is
  byte-identical, guarded by a golden snapshot test.
- **TESTS**: Added a golden characterization snapshot, a corner-case regression
  suite, span-offset invariants, and unit tests for the node model, theme, and
  widget; wired every test file into `test/unit_test.dart` so CI runs the full
  suite (**370+ tests**, previously only a fraction ran). `parser.dart`,
  `nodes.dart`, `markdown.dart`, `theme.dart`, and `widget.dart` are now at
  ~100% line coverage.
- **ADDED**: `benchmark/parser_benchmark.dart` (a multi-scenario
  `benchmark_harness` suite) and `benchmark/compare.dart` (a low-noise
  before/after comparison tool).
- **DOCS**: Documented alerts, task lists, table alignment, thematic-break
  variants, and opt-in inline math in the README.

## 0.0.8

- **CHANGED**: New table render
- **FIXED**: Invalidate and relayout render object after system fonts changed.

## 0.0.7

- **FIXED**: Preserved indentation on line breaks within list items [#4].
- **FIXED**: Inline code no longer processes inner Markdown syntax [#10].
- **CHANGED**: Improved theme support.
- **ADDED**: Dark mode support in the example app.

## 0.0.6

- **FIXED**: Fixed escaping of special characters. [#6]

## 0.0.5

- **FIXED**: Fixed parsing url such as `[text](https://domain.com/path(with)brackets)`.

## 0.0.4

- **CHANGED**: Improved link tap handling.

## 0.0.3

- **FIXED**: Links inside lists now work correctly.

## 0.0.2

- **ADDED**: All field in `MarkdownThemeData()` are now optional.
- **ADDED**: `MarkdownThemeData{}.headingStyleFor` method to customize heading styles.
- **FIXED**: Remove clipping for canvas. Fixes one line text trim at browsers.
- **FIXED**: Correctly apply styles to text in blocks.

## 0.0.1

- **ADDED**: Initial release with basic functionality.
