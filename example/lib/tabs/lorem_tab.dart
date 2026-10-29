import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_md/flutter_md.dart';

const String _loremMdA = '''
# Cross-block selection

**Lorem ipsum** dolor sit amet, consectetur _adipiscing_ elit. Drag from this
heading straight down through every block below — headings, quotes, lists,
tables and code all join into one selection with sensible separators.

> Ut enim ad minim veniam, quis nostrud exercitation `ullamco` laboris nisi ut
> aliquip ex ea commodo consequat.

A nested list:

- alpha item
    - alpha one
    - alpha two
- beta item
- gamma item

And a table — its cells are selectable too:

| Lang   | Typing   | Year |
| ------ | -------- | ---: |
| Dart   | static   | 2011 |
| Python | dynamic  | 1991 |
| Rust   | static   | 2010 |

```dart
void main() => print('selectable code block');
```

## Pictures and spoilers

An inline picture ![Flutter](https://avatars.githubusercontent.com/u/14101776?s=48)
sits in the line and selects, highlights and copies as its alt text, whole. A
link gets the site's icon in front of its label:
[flutter.dev](https://flutter.dev).

![Flutter logo](https://avatars.githubusercontent.com/u/14101776?s=200)

The ending is ||hidden under a spoiler||: tap it to reveal, or drag a selection
across it — the selection reveals the document too.

- a list item with ||a secret|| inside
- a picture in a list ![Dart](https://avatars.githubusercontent.com/u/1609975?s=48)

> [!TIP]
> Selecting Markdown clears the plain `SelectableText` below, and vice-versa.''';

const String _loremMdB = '''
## A different document

Duis aute irure dolor in `reprehenderit` in voluptate velit esse cillum dolore
eu fugiat nulla pariatur — this block belongs to a **second** controller, so
selecting here clears the selection above.

| Column A | Column B |
| -------- | -------- |
| one      | two      |
| three    | four     |''';

const String _loremPlain =
    'This is a plain SelectableText (not Markdown). Selecting here clears the '
    'Markdown selections above — and selecting Markdown clears this one.';

/// Reconstructs Markdown block structure (heading levels, nested list markers,
/// task checkboxes, blockquotes, fenced code, pipe tables) on copy, with inline
/// styles as plain text. The default [MarkdownSourceFormatter] also writes the
/// inline marks.
const MarkdownMarkupFormatter _markupFormatter = MarkdownMarkupFormatter();

/// Demonstrates cross-block selection within a single [MarkdownWidget], several
/// independent controllers that reset one another via a shared
/// [MarkdownSelectionGroup], and coordination with a plain `SelectableText`.
///
/// Document A also holds pictures (the app theme's `imageResolver`) and
/// spoilers: a [MarkdownSpoilerController] whose dust a [Ticker] drives while
/// [MarkdownSpoilerController.wantsTicks] is true, revealed by a tap or by a
/// selection that reaches a spoiler.
class LoremTab extends StatefulWidget {
  /// Creates the lorem-ipsum selection demo tab.
  const LoremTab({super.key});

  @override
  State<LoremTab> createState() => _LoremTabState();
}

class _LoremTabState extends State<LoremTab>
    with SingleTickerProviderStateMixin {
  final MarkdownSelectionGroup _group = MarkdownSelectionGroup();
  late final MarkdownSelectionController _a = MarkdownSelectionController(
    group: _group,
  );
  late final MarkdownSelectionController _b = MarkdownSelectionController(
    group: _group,
  );
  final Markdown _docA = Markdown.fromString(_loremMdA);
  final Markdown _docB = Markdown.fromString(_loremMdB);

  /// Which documents have their spoilers revealed. The package owns no clock
  /// for the dust: [_dust] feeds it, and only runs while a hidden spoiler is
  /// mounted.
  final MarkdownSpoilerController _spoilers = MarkdownSpoilerController();
  late final Ticker _dust = createTicker(_spoilers.advance);

  // Bumping this key recreates the SelectionArea, clearing its selection when a
  // Markdown selection starts (the Markdown -> plain direction of the reset).
  int _plainEpoch = 0;
  bool _mdActive = false;

  @override
  void initState() {
    super.initState();
    _a.setDocuments(<MarkdownDocumentRef>[
      MarkdownDocumentRef(id: 'A', model: _docA),
    ]);
    _b.setDocuments(<MarkdownDocumentRef>[
      MarkdownDocumentRef(id: 'B', model: _docB),
    ]);
    _a.addListener(_onMarkdownSelection);
    _b.addListener(_onMarkdownSelection);
    _spoilers.wantsTicks.addListener(_syncDust);
  }

  void _syncDust() {
    final wants = _spoilers.wantsTicks.value;
    if (wants && !_dust.isActive) {
      _dust.start();
    } else if (!wants && _dust.isActive) {
      _dust.stop();
    }
  }

  /// Reveals a document once a selection reaches one of its spoilers: the
  /// package leaves that to the host ([MarkdownSpoilerController.reveal] with
  /// no origin ripples from the middle of the spoilers).
  void _revealSelectedSpoilers(MarkdownSelectionController controller) {
    for (final document in controller.selectedContent().documents) {
      if (_spoilers.isRevealed(document.documentId)) continue;
      if (document.blocks.any(_touchesSpoiler)) {
        _spoilers.reveal(document.documentId);
      }
    }
  }

  /// Whether [selected] covers a spoiler. Exact for a paragraph or a heading,
  /// whose span offsets index the rendered text; any spoiler in a list counts.
  static bool _touchesSpoiler(MarkdownSelectedBlock selected) {
    bool isSpoiler(MD$Span span) => span.style.contains(MD$Style.spoiler);
    bool inItems(List<MD$ListItem> items) => items.any(
      (item) => item.spans.any(isSpoiler) || inItems(item.children),
    );
    final range = selected.renderedRange;
    return switch (selected.block) {
      MD$Paragraph(:final spans) || MD$Heading(:final spans) => spans.any(
        (span) =>
            isSpoiler(span) && span.start < range.end && range.start < span.end,
      ),
      MD$List(:final items) => inItems(items),
      _ => false,
    };
  }

  bool _isActive(MarkdownSelectionController c) =>
      c.selection != null && !c.selection!.isCollapsed;

  void _onMarkdownSelection() {
    if (_isActive(_a)) _revealSelectedSpoilers(_a);
    final active = _isActive(_a) || _isActive(_b);
    setState(() {
      if (active && !_mdActive) _plainEpoch++; // clear the plain SelectableText
      _mdActive = active;
    });
  }

  @override
  void dispose() {
    _spoilers.wantsTicks.removeListener(_syncDust);
    _dust.dispose();
    _spoilers.dispose();
    _a
      ..removeListener(_onMarkdownSelection)
      ..dispose();
    _b
      ..removeListener(_onMarkdownSelection)
      ..dispose();
    super.dispose();
  }

  MarkdownSelectionController? get _activeController =>
      _isActive(_a) ? _a : (_isActive(_b) ? _b : null);

  Future<void> _copy({MarkdownSelectionFormatter? formatter}) async {
    final text = _activeController?.getText(formatter) ?? '';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    final how = formatter == null ? 'plain text' : 'Markdown';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: Text('Copied ${text.length} chars as $how'),
        ),
      );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );

  /// A custom [contextMenuBuilder] that appends "Copy as Markdown" and
  /// "Copy LOUD" actions to the default Copy / Select-all buttons.
  Widget _loudContextMenu(
    BuildContext context,
    MarkdownSelectionScopeState state,
  ) => AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: <ContextMenuButtonItem>[
      ...state.contextMenuButtonItems,
      ContextMenuButtonItem(
        label: 'Copy as Markdown',
        onPressed: () {
          // Reconstruct block structure (headings, nested lists, tables, …)
          // without the inline marks the default Copy also writes.
          Clipboard.setData(
            ClipboardData(text: state.controller.getText(_markupFormatter)),
          );
          state.hideToolbar();
        },
      ),
      ContextMenuButtonItem(
        label: 'Copy LOUD',
        onPressed: () {
          Clipboard.setData(
            ClipboardData(text: state.controller.getText().toUpperCase()),
          );
          state.hideToolbar();
        },
      ),
    ],
  );

  /// Keyboard/gesture hint shown while nothing is selected.
  Widget _hint() => Text(
    'Drag to select · Ctrl/Cmd+A all · Shift+arrows extend · '
    'right-click for the toolbar · Esc clears',
    style: Theme.of(context).textTheme.bodySmall,
  );

  /// A live, side-by-side preview of what the two Copy buttons produce for the
  /// current selection — the whole point of [MarkdownMarkupFormatter] is that
  /// the right column keeps the structure the left column flattens away.
  Widget _preview() {
    final c = _activeController;
    final plain = c?.getText() ?? '';
    final markdown = c?.getText(_markupFormatter) ?? '';
    return LayoutBuilder(
      builder: (context, constraints) {
        final plainPanel = _previewPanel(
          'Plain (default)',
          plain,
          accent: false,
        );
        final mdPanel = _previewPanel(
          'Copy as Markdown',
          markdown,
          accent: true,
        );
        if (constraints.maxWidth > 620) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: plainPanel),
              const SizedBox(width: 10),
              Expanded(child: mdPanel),
            ],
          );
        }
        return Column(
          children: <Widget>[plainPanel, const SizedBox(height: 8), mdPanel],
        );
      },
    );
  }

  Widget _previewPanel(String title, String body, {required bool accent}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: accent
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accent
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant,
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: accent ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 108),
            child: SingleChildScrollView(
              child: Text(
                body.isEmpty ? '—' : body,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: <String>['Courier'],
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _label(
                'Markdown A — custom toolbar (right-click / '
                'long-press for "Copy as Markdown" & "Copy LOUD")',
              ),
              MarkdownSelectionScope(
                controller: _a,
                contextMenuBuilder: _loudContextMenu,
                child: MarkdownWidget(
                  markdown: _docA,
                  documentId: 'A',
                  spoilerController: _spoilers,
                ),
              ),
              const Divider(height: 40),
              _label(
                'Markdown B — custom selection color '
                '(selecting one clears the other)',
              ),
              MarkdownSelectionScope(
                controller: _b,
                selectionColor: Colors.amber.withValues(alpha: 0.4),
                child: MarkdownWidget(markdown: _docB, documentId: 'B'),
              ),
              const Divider(height: 40),
              _label('Plain SelectableText — resets with the Markdown ones'),
              SelectionArea(
                key: ValueKey<int>(_plainEpoch),
                onSelectionChanged: (content) {
                  if ((content?.plainText ?? '').isNotEmpty) {
                    _group.clearExternal();
                  }
                },
                child: const Text(
                  _loremPlain,
                  style: TextStyle(fontSize: 16, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
      Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  _mdActive
                      ? 'Live preview — "Copy as Markdown" keeps the '
                            'structure that plain copy flattens:'
                      : 'Select any Markdown above to preview & copy it '
                            'two ways:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                _mdActive ? _preview() : _hint(),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _mdActive
                          ? () => _copy(formatter: _markupFormatter)
                          : null,
                      icon: const Icon(Icons.data_object),
                      label: const Text('Copy as Markdown'),
                    ),
                    FilledButton.icon(
                      onPressed: _mdActive ? _copy : null,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
