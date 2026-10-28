import 'dart:collection';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:meta/meta.dart' as meta show internal;

import '../flutter_md.dart';
import 'highlight/engine.dart';

/// Signature for dynamically resolving the [MouseCursor] at a content-local
/// [localOffset] within a Markdown render surface.
///
/// [blockIndex] is the source index of the hit block in `Markdown.blocks`, or
/// `null` if the offset does not fall within any block.
///
/// [block] is the hit [MD$Block] model, or `null` if no block was hit.
///
/// Returning `null` falls back to default cursor resolution (click for links,
/// text for selectable content, basic/defer otherwise).
typedef MarkdownCursorResolver = MouseCursor? Function(
  Offset localOffset,
  int? blockIndex,
  MD$Block? block,
);

/// Where the emoji sit in [text]: the ranges of UTF-16 code units, in reading
/// order and not overlapping, of each emoji sequence (a skin tone, a ZWJ
/// family, a flag and a keycap are one range each).
///
/// The package knows no emoji table: the host brings its own scanner, the one
/// that also decides what its messages count as emoji. See
/// [MarkdownThemeData.emojiRuns].
typedef MarkdownEmojiRuns = Iterable<TextRange> Function(String text);

/// Primary monospace face for [platform] — the default for
/// [MarkdownThemeData.monospaceFontFamily].
///
/// Flutter passes the family straight to the platform font manager, and only
/// some of them know the CSS generic `'monospace'`: Android's font config and
/// fontconfig on Linux resolve it, CoreText (iOS / macOS) and DirectWrite
/// (Windows) do not — there a `'monospace'` span silently falls back to the
/// proportional body face, so inline code stops looking like code.
///
/// So a real system family is substituted on exactly those two platforms, and
/// every other target keeps the generic it already resolved.
///
/// Web keeps the generic as well, but not because it works: CanvasKit and
/// skwasm reach no system fonts at all, so `'monospace'` resolves no better
/// than `'Courier New'` or a name nobody has — measured in a browser, all
/// three lay out identically to the default proportional face. Naming a
/// family cannot fix that; only bundling a monospace asset and setting
/// [MarkdownThemeData.monospaceFontFamily] to it can.
String _defaultMonospaceFontFamily(TargetPlatform platform) {
  if (kIsWeb) return 'monospace';
  return switch (platform) {
    // Ships with every iOS / macOS release; SF Mono is not user-installable.
    TargetPlatform.iOS || TargetPlatform.macOS => 'Menlo',
    // Ships with Windows since Vista.
    TargetPlatform.windows => 'Consolas',
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.linux =>
      'monospace',
  };
}

/// Families tried after the primary face, for a platform whose own is
/// missing (a trimmed Linux image, a custom Android ROM).
///
/// Ends in the CSS generic so anything that resolves it still gets a real
/// monospace face rather than the proportional default.
const List<String> _defaultMonospaceFontFamilyFallback = <String>[
  'Menlo', // Apple
  'Consolas', // Windows
  'DejaVu Sans Mono', // Linux
  'Roboto Mono', // Android
  'Courier New',
  'monospace',
];

/// {@template markdown_theme_data}
/// Theme data for Markdown widgets.
/// {@endtemplate}
class MarkdownThemeData implements ThemeExtension<MarkdownThemeData> {
  /// Creates a [MarkdownThemeData] instance.
  /// {@macro markdown_theme_data}
  MarkdownThemeData({
    required this.textStyle,
    this.textDirection = TextDirection.ltr,
    this.textScaler = TextScaler.noScaling,
    this.h1Style,
    this.h2Style,
    this.h3Style,
    this.h4Style,
    this.h5Style,
    this.h6Style,
    this.quoteStyle,
    this.linkColor = Colors.indigo,
    this.linkStyle,
    this.mentionColor,
    this.vacancyPillColor,
    this.vacancyPillBackground,
    this.vacancyPillMutedColor,
    this.vacancyPillMutedBackground,
    this.vacancyPillIcon,
    this.vacancyPillRadius,
    this.vacancyPillIconSize,
    this.vacancyPillGap,
    this.vacancyPillHorizontalPadding,
    this.vacancyPillMargin,
    this.surfaceColor = const Color.fromARGB(255, 235, 235, 235),
    this.highlightBackgroundColor = const Color(0x40FF5722),
    this.monospaceBackgroundColor = const Color(0x409E9E9E),
    String? monospaceFontFamily,
    List<String>? monospaceFontFamilyFallback,
    this.dividerColor,
    this.alertColors,
    this.blockFilter,
    this.spanFilter,
    this.builder,
    this.onLinkTap,
    this.onMentionTap,
    this.onVacancyTap,
    this.highlighter,
    this.cursorResolver,
    this.emojiRuns,
    this.emojiScale = 1,
  })  : assert(emojiScale > 0, 'emojiScale must be positive'),
        monospaceFontFamily = monospaceFontFamily ??
            _defaultMonospaceFontFamily(defaultTargetPlatform),
        monospaceFontFamilyFallback =
            monospaceFontFamilyFallback ?? _defaultMonospaceFontFamilyFallback,
        _headingStyles = List<TextStyle?>.filled(8, null),
        _textStyles = HashMap<int, TextStyle>();

  /// Creates a [MarkdownThemeData] from the given [ThemeData].
  factory MarkdownThemeData.mergeTheme(
    ThemeData theme, {
    TextStyle? textStyle,
    TextDirection? textDirection,
    TextScaler? textScaler,
    TextStyle? h1Style,
    TextStyle? h2Style,
    TextStyle? h3Style,
    TextStyle? h4Style,
    TextStyle? h5Style,
    TextStyle? h6Style,
    TextStyle? quoteStyle,
    Color? linkColor,
    TextStyle? linkStyle,
    Color? mentionColor,
    Color? vacancyPillColor,
    Color? vacancyPillBackground,
    Color? vacancyPillMutedColor,
    Color? vacancyPillMutedBackground,
    IconData? vacancyPillIcon,
    double? vacancyPillRadius,
    double? vacancyPillIconSize,
    double? vacancyPillGap,
    double? vacancyPillHorizontalPadding,
    double? vacancyPillMargin,
    Color? surfaceColor,
    Color? highlightBackgroundColor,
    Color? monospaceBackgroundColor,
    String? monospaceFontFamily,
    List<String>? monospaceFontFamilyFallback,
    Color? dividerColor,
    Map<MD$AlertType, Color>? alertColors,
    bool Function(MD$Block block)? blockFilter,
    bool Function(MD$Span span)? spanFilter,
    BlockPainter? Function(MD$Block block, MarkdownThemeData theme)? builder,
    void Function(String title, String url)? onLinkTap,
    void Function(String scheme, String? id, String name)? onMentionTap,
    void Function(String target, String title)? onVacancyTap,
    SyntaxHighlighter? highlighter,
    MarkdownCursorResolver? cursorResolver,
    MarkdownEmojiRuns? emojiRuns,
    double emojiScale = 1,
  }) {
    return MarkdownThemeData(
      textStyle: textStyle ??
          theme.textTheme.bodyMedium ??
          const TextStyle(color: Colors.black, fontSize: kDefaultFontSize),
      textDirection: textDirection ?? TextDirection.ltr,
      textScaler: textScaler ?? TextScaler.noScaling,
      h1Style: h1Style ?? theme.textTheme.headlineLarge,
      h2Style: h2Style ?? theme.textTheme.headlineMedium,
      h3Style: h3Style ?? theme.textTheme.headlineSmall,
      h4Style: h4Style ?? theme.textTheme.titleLarge,
      h5Style: h5Style ?? theme.textTheme.titleMedium,
      h6Style: h6Style ?? theme.textTheme.titleSmall,
      quoteStyle: quoteStyle ??
          theme.textTheme.bodyMedium?.copyWith(
              color:
                  theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75)),
      linkColor: linkColor ?? theme.colorScheme.primary,
      linkStyle: linkStyle,
      mentionColor: mentionColor,
      vacancyPillColor: vacancyPillColor,
      vacancyPillBackground: vacancyPillBackground,
      vacancyPillMutedColor: vacancyPillMutedColor,
      vacancyPillMutedBackground: vacancyPillMutedBackground,
      vacancyPillIcon: vacancyPillIcon,
      vacancyPillRadius: vacancyPillRadius,
      vacancyPillIconSize: vacancyPillIconSize,
      vacancyPillGap: vacancyPillGap,
      vacancyPillHorizontalPadding: vacancyPillHorizontalPadding,
      vacancyPillMargin: vacancyPillMargin,
      surfaceColor: surfaceColor ?? theme.colorScheme.surfaceContainerHigh,
      highlightBackgroundColor:
          highlightBackgroundColor ?? theme.colorScheme.errorContainer,
      monospaceBackgroundColor:
          monospaceBackgroundColor ?? theme.colorScheme.surfaceContainerHigh,
      // ThemeData.platform is the app's own answer to "which platform are
      // we adapting to". It defaults to defaultTargetPlatform, so this only
      // diverges for an app that deliberately overrode it.
      monospaceFontFamily:
          monospaceFontFamily ?? _defaultMonospaceFontFamily(theme.platform),
      monospaceFontFamilyFallback: monospaceFontFamilyFallback,
      dividerColor: dividerColor ?? theme.dividerColor.withValues(alpha: 0.12),
      alertColors: alertColors,
      blockFilter: blockFilter,
      spanFilter: spanFilter,
      builder: builder,
      onLinkTap: onLinkTap,
      onMentionTap: onMentionTap,
      onVacancyTap: onVacancyTap,
      highlighter: highlighter,
      cursorResolver: cursorResolver,
      emojiRuns: emojiRuns,
      emojiScale: emojiScale,
    );
  }

  @override
  Object get type => MarkdownThemeData;

  /// The text direction to use for rendering Markdown widgets.
  final TextDirection textDirection;

  /// The text scaler to use for scaling text in Markdown widgets.
  final TextScaler textScaler;

  /// The default text style to use for Markdown widgets.
  final TextStyle textStyle;

  /// Default text style for headings h1.
  final TextStyle? h1Style;

  /// Default text style for headings h2.
  final TextStyle? h2Style;

  /// Default text style for headings h3.
  final TextStyle? h3Style;

  /// Default text style for headings h4.
  final TextStyle? h4Style;

  /// Default text style for headings h5.
  final TextStyle? h5Style;

  /// Default text style for headings h6.
  final TextStyle? h6Style;

  /// Default text style for quote blocks.
  final TextStyle? quoteStyle;

  /// The color to use for link text.
  final Color? linkColor;

  /// An optional text style to merge into link spans, applied on top of the
  /// default link styling (bold + [linkColor]).
  final TextStyle? linkStyle;

  /// The color to use for mention-class text: mentions, usernames and
  /// hashtags ([MD$Style.mention]).
  ///
  /// When `null`, mention text follows [linkColor]. Mention text is plain
  /// coloured text: no underline and no bold, whatever [linkStyle] adds to
  /// links.
  final Color? mentionColor;

  /// The colour of a vacancy pill's icon and title ([MD$Style.vacancy]).
  /// When `null`, the pill follows [linkColor].
  final Color? vacancyPillColor;

  /// The rounded fill behind a vacancy pill. When `null`, the pill colour at
  /// 14% opacity.
  final Color? vacancyPillBackground;

  /// The icon and title colour of a muted pill (a vacancy reference that is
  /// not resolved yet). When `null`, the text colour at 55% opacity.
  final Color? vacancyPillMutedColor;

  /// The fill behind a muted pill. When `null`, the muted colour at 10%
  /// opacity.
  final Color? vacancyPillMutedBackground;

  /// The icon of a vacancy pill. When `null`, `Icons.work_outline_rounded`.
  /// Its own `fontFamily` and `fontPackage` are used, whatever package the
  /// host text style carries (for example `LucideIcons.briefcase_business`).
  final IconData? vacancyPillIcon;

  /// The corner radius of a vacancy pill's fill. When `null`, the ends are
  /// fully rounded (half the line height). A larger value is capped at that.
  final double? vacancyPillRadius;

  /// The size of a vacancy pill's icon. When `null`, the text font size. It
  /// widens the fill but never makes it taller than the title's line.
  final double? vacancyPillIconSize;

  /// The gap between a vacancy pill's icon and title. When `null`, 0.3 em.
  final double? vacancyPillGap;

  /// The room inside a vacancy pill's fill, before the icon and after the
  /// title. When `null`, 0.3 em. It is layout: the text is pushed by it, so the
  /// fill never overlaps a neighbouring glyph.
  final double? vacancyPillHorizontalPadding;

  /// The room outside a vacancy pill's fill on each side, which the text
  /// around it flows past (a comma after a pill starts this far from the
  /// fill). When `null`, 0.
  final double? vacancyPillMargin;

  /// The color to use for the background of the quote, block, table and etc.
  final Color? surfaceColor;

  /// The color to use for the background of highlighted text.
  final Color? highlightBackgroundColor;

  /// The color to use for the background of monospace text.
  final Color? monospaceBackgroundColor;

  /// Font family for inline `` `code` `` and fenced blocks. One knob covers
  /// both — [BlockPainter$Code] reads it too.
  ///
  /// Defaults to a family the host platform can actually resolve: the CSS
  /// generic `'monospace'` on Android, Fuchsia, Linux and web, `Menlo` on
  /// iOS / macOS and `Consolas` on Windows, because CoreText and DirectWrite
  /// do not know the generic and would fall back to the proportional body
  /// face. Pass a bundled face (`JetBrains Mono`, `Fira Code`, …) to pin it.
  ///
  /// Resolved once, when the theme is constructed.
  final String monospaceFontFamily;

  /// Families tried after [monospaceFontFamily].
  ///
  /// Defaults to a chain ending in the CSS generic, so a platform missing its
  /// primary face still lands on a real monospace one. Whatever [textStyle]
  /// carries is appended after it — see [monospaceFallbackChain] — so pass an
  /// empty list to fall straight through to the body face's own chain.
  final List<String> monospaceFontFamilyFallback;

  /// The fallback chain code spans actually use: [monospaceFontFamilyFallback]
  /// followed by [textStyle]'s own.
  ///
  /// A monospace face covers Latin and little else, so dropping the body
  /// face's chain would lose the host's coverage for everything it was there
  /// for — CJK, emoji, right-to-left scripts — and lose it inside `` `code` ``
  /// and fenced blocks only. Appending keeps the monospace faces winning
  /// wherever they have the glyph and hands the rest back to the host.
  @meta.internal
  late final List<String> monospaceFallbackChain = <String>[
    ...monospaceFontFamilyFallback,
    ...?textStyle.fontFamilyFallback,
  ];

  /// The color to use for the divider.
  final Color? dividerColor;

  /// Optional accent colors for GitHub-style alert blocks, keyed by type.
  /// Missing entries fall back to the GitHub default palette
  /// (see [alertColorFor]).
  final Map<MD$AlertType, Color>? alertColors;

  /// The default GitHub-style accent color for each alert type (light theme).
  static const Map<MD$AlertType, Color> _defaultAlertColors =
      <MD$AlertType, Color>{
    MD$AlertType.note: Color(0xFF0969DA), // blue
    MD$AlertType.tip: Color(0xFF1A7F37), // green
    MD$AlertType.important: Color(0xFF8250DF), // purple
    MD$AlertType.warning: Color(0xFF9A6700), // amber
    MD$AlertType.caution: Color(0xFFCF222E), // red
  };

  /// Returns the accent color for the given alert [type], using [alertColors]
  /// when provided and falling back to the GitHub default palette.
  Color alertColorFor(MD$AlertType type) =>
      alertColors?[type] ?? _defaultAlertColors[type]!;

  /// A filter function to determine whether a block should be rendered.
  /// If the function returns `true`, the block will be rendered.
  ///
  /// For example, you can use this to filter out blocks that are not
  /// relevant to the current context, such as code blocks or tables.
  final bool Function(MD$Block block)? blockFilter;

  /// A filter function to determine whether a span should be rendered.
  /// If the function returns `true`, the span will be rendered.
  ///
  /// For example, you can use this to filter out spans that are not
  /// relevant to the current context, such as links or images.
  /// This can be useful for customizing the rendering of Markdown spans.
  final bool Function(MD$Span span)? spanFilter;

  /// A custom block painter builder function.
  /// It receives a [MD$Block] and returns a [BlockPainter].
  /// If it returns `null`, the default painter will be used.
  /// This allows you to customize the rendering of specific blocks,
  /// such as code blocks, tables, or quote blocks.
  final BlockPainter? Function(
    MD$Block block,
    MarkdownThemeData theme,
  )? builder;

  /// A callback function that is called when a link is tapped.
  /// It receives the link title and URL as parameters.
  final void Function(String title, String url)? onLinkTap;

  /// A callback function that is called when a mention-class span (a mention,
  /// a username or a hashtag) is tapped. [onLinkTap] never fires for those.
  ///
  /// [scheme] is `mention`, `username` or `hashtag`. [id] is the identifier
  /// of a `mention:` span and `null` for the other two. [name] is the span's
  /// label for `mention:`, and the username or tag for the other two.
  final void Function(String scheme, String? id, String name)? onMentionTap;

  /// A callback that is called when a vacancy pill ([MD$Style.vacancy]) is
  /// tapped. [target] is the pill's host target (for example `vref:V1`) and
  /// [title] the text it shows. Neither [onLinkTap] nor [onMentionTap] fires.
  final void Function(String target, String title)? onVacancyTap;

  /// An optional syntax highlighter for fenced code blocks. When `null`, code
  /// is painted as plain monospace text.
  ///
  /// See `package:flutter_md/highlight.dart` and [MarkdownHighlighter]. Assign
  /// the exact set of languages you support so unused grammars tree-shake away.
  final SyntaxHighlighter? highlighter;

  /// An optional callback to dynamically resolve the mouse cursor based on
  /// hover offset, hit block index, and hit block model.
  ///
  /// When `null`, or when the callback returns `null`, the renderer falls back
  /// to its default cursors (hand cursor for actionable links, I-beam text
  /// cursor for selectable documents, or deferred cursor otherwise).
  final MarkdownCursorResolver? cursorResolver;

  /// Finds the emoji in a run of text, so they can be drawn larger than the
  /// text around them. When `null` (the default) an emoji is drawn like any
  /// other character, at the font size.
  ///
  /// A colour emoji font draws its glyph into a square of the font size, which
  /// is smaller than the line the text sits in: SF is about 1.18 times its size
  /// tall, so a 15 px emoji next to 15 px text looks undersized, and a custom
  /// emoji (an inline embed, 1.2 times the font's height) beside it looks
  /// large. With a scanner, each range it reports is set as a run of its own
  /// whose font size makes the glyph [emojiScale] times the font's height (its
  /// ascent plus descent, the rule the inline embeds use), with the line height
  /// of the surrounding text, so a line with an emoji is as tall as one
  /// without. The text, its offsets, the selection and the recognizers are
  /// those of the text without the scanner.
  ///
  /// The scanner runs once per text span at build time; it should be pure and
  /// cheap, and the same function for the life of the theme.
  final MarkdownEmojiRuns? emojiRuns;

  /// How many times the font's height ([emojiRuns]' glyphs are drawn at):
  /// 1 is the height of the line's font, as Android draws a unicode emoji; the
  /// inline embeds use 1.2. Only read when [emojiRuns] is set.
  final double emojiScale;

  final List<TextStyle?> _headingStyles;

  /// Returns a [TextStyle] for the given heading level.
  /// The level should be between 1 and 6, inclusive.
  TextStyle headingStyleFor(int level) =>
      _headingStyles[level] ??= switch (level.clamp(1, 7)) {
        1 => h1Style ??
            textStyle.copyWith(
              fontSize: (textStyle.fontSize ?? kDefaultFontSize) + 10.0,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.solid,
            ),
        2 => h2Style ??
            textStyle.copyWith(
              fontSize: (textStyle.fontSize ?? kDefaultFontSize) + 8.0,
              fontWeight: FontWeight.bold,
            ),
        3 => h3Style ??
            textStyle.copyWith(
              fontSize: (textStyle.fontSize ?? kDefaultFontSize) + 6.0,
              fontWeight: FontWeight.bold,
            ),
        4 => h4Style ??
            textStyle.copyWith(
              fontSize: (textStyle.fontSize ?? kDefaultFontSize) + 4.0,
              fontWeight: FontWeight.bold,
            ),
        5 => h5Style ??
            textStyle.copyWith(
              fontSize: (textStyle.fontSize ?? kDefaultFontSize) + 2.0,
              fontWeight: FontWeight.bold,
            ),
        6 => h6Style ??
            textStyle.copyWith(
              fontSize: (textStyle.fontSize ?? kDefaultFontSize) + 0.0,
              fontWeight: FontWeight.bold,
            ),
        _ => textStyle,
      };

  final HashMap<int, TextStyle> _textStyles;

  /// Returns a [TextStyle] for the given [MD$Style].
  TextStyle textStyleFor(MD$Style style) => _textStyles.putIfAbsent(
        style.hashCode,
        () {
          final resolved = textStyle.copyWith(
            fontWeight: switch (style) {
              var s when s.contains(MD$Style.bold) => FontWeight.bold,
              var s when s.contains(MD$Style.link) => FontWeight.bold,
              var s when s.contains(MD$Style.highlight) => FontWeight.bold,
              _ => null,
            },
            fontStyle:
                style.contains(MD$Style.italic) ? FontStyle.italic : null,
            decoration: switch (style) {
              var s when s.contains(MD$Style.underline) =>
                TextDecoration.underline,
              var s when s.contains(MD$Style.strikethrough) =>
                TextDecoration.lineThrough,
              _ => null,
            },
            fontFamily:
                style.contains(MD$Style.monospace) ? monospaceFontFamily : null,
            fontFamilyFallback: style.contains(MD$Style.monospace)
                ? monospaceFallbackChain
                : null,
            color: switch (style) {
              var s when s.contains(MD$Style.link) => linkColor,
              var s when s.contains(MD$Style.vacancy) =>
                vacancyPillColor ?? linkColor,
              var s when s.contains(MD$Style.mention) =>
                mentionColor ?? linkColor,
              _ => null,
            },
            backgroundColor: switch (style) {
              var s when s.contains(MD$Style.highlight) =>
                highlightBackgroundColor,
              var s when s.contains(MD$Style.monospace) =>
                monospaceBackgroundColor,
              _ => null,
            },
          );
          // Merge the optional link style on top of the default link styling.
          if (linkStyle != null && style.contains(MD$Style.link)) {
            return resolved.merge(linkStyle);
          }
          return resolved;
        },
      );

  /// Creates a copy of this theme with the given fields replaced.
  ///
  /// A `null` argument keeps the current value, as in Flutter's own themes,
  /// so `copyWith(onLinkTap: null)` does not remove a link handler. To remove
  /// a callback, pass its `clear*` flag: [clearOnLinkTap], [clearOnMentionTap],
  /// [clearOnVacancyTap],
  /// [clearBlockFilter], [clearSpanFilter], [clearBuilder],
  /// [clearCursorResolver] or [clearEmojiRuns]. A flag and a new value for the
  /// same callback are mutually exclusive.
  @override
  MarkdownThemeData copyWith({
    TextDirection? textDirection,
    TextScaler? textScaler,
    TextStyle? textStyle,
    TextStyle? h1Style,
    TextStyle? h2Style,
    TextStyle? h3Style,
    TextStyle? h4Style,
    TextStyle? h5Style,
    TextStyle? h6Style,
    TextStyle? quoteStyle,
    Color? linkColor,
    TextStyle? linkStyle,
    Color? mentionColor,
    Color? vacancyPillColor,
    Color? vacancyPillBackground,
    Color? vacancyPillMutedColor,
    Color? vacancyPillMutedBackground,
    IconData? vacancyPillIcon,
    double? vacancyPillRadius,
    double? vacancyPillIconSize,
    double? vacancyPillGap,
    double? vacancyPillHorizontalPadding,
    double? vacancyPillMargin,
    Color? surfaceColor,
    Color? highlightBackgroundColor,
    Color? monospaceBackgroundColor,
    String? monospaceFontFamily,
    List<String>? monospaceFontFamilyFallback,
    Color? dividerColor,
    Map<MD$AlertType, Color>? alertColors,
    bool Function(MD$Block block)? blockFilter,
    bool Function(MD$Span span)? spanFilter,
    BlockPainter? Function(MD$Block block, MarkdownThemeData theme)? builder,
    void Function(String title, String url)? onLinkTap,
    void Function(String scheme, String? id, String name)? onMentionTap,
    void Function(String target, String title)? onVacancyTap,
    SyntaxHighlighter? highlighter,
    MarkdownCursorResolver? cursorResolver,
    MarkdownEmojiRuns? emojiRuns,
    double? emojiScale,
    bool clearBlockFilter = false,
    bool clearSpanFilter = false,
    bool clearBuilder = false,
    bool clearOnLinkTap = false,
    bool clearOnMentionTap = false,
    bool clearOnVacancyTap = false,
    bool clearCursorResolver = false,
    bool clearEmojiRuns = false,
  }) {
    assert(
      !(clearBlockFilter && blockFilter != null) &&
          !(clearSpanFilter && spanFilter != null) &&
          !(clearBuilder && builder != null) &&
          !(clearOnLinkTap && onLinkTap != null) &&
          !(clearOnMentionTap && onMentionTap != null) &&
          !(clearOnVacancyTap && onVacancyTap != null) &&
          !(clearCursorResolver && cursorResolver != null) &&
          !(clearEmojiRuns && emojiRuns != null),
      'Pass either a callback or its clear flag, not both.',
    );
    return MarkdownThemeData(
      textDirection: textDirection ?? this.textDirection,
      textScaler: textScaler ?? this.textScaler,
      textStyle: textStyle ?? this.textStyle,
      h1Style: h1Style ?? this.h1Style,
      h2Style: h2Style ?? this.h2Style,
      h3Style: h3Style ?? this.h3Style,
      h4Style: h4Style ?? this.h4Style,
      h5Style: h5Style ?? this.h5Style,
      h6Style: h6Style ?? this.h6Style,
      quoteStyle: quoteStyle ?? this.quoteStyle,
      linkColor: linkColor ?? this.linkColor,
      linkStyle: linkStyle ?? this.linkStyle,
      mentionColor: mentionColor ?? this.mentionColor,
      vacancyPillColor: vacancyPillColor ?? this.vacancyPillColor,
      vacancyPillBackground:
          vacancyPillBackground ?? this.vacancyPillBackground,
      vacancyPillMutedColor:
          vacancyPillMutedColor ?? this.vacancyPillMutedColor,
      vacancyPillMutedBackground:
          vacancyPillMutedBackground ?? this.vacancyPillMutedBackground,
      vacancyPillIcon: vacancyPillIcon ?? this.vacancyPillIcon,
      vacancyPillRadius: vacancyPillRadius ?? this.vacancyPillRadius,
      vacancyPillIconSize: vacancyPillIconSize ?? this.vacancyPillIconSize,
      vacancyPillGap: vacancyPillGap ?? this.vacancyPillGap,
      vacancyPillHorizontalPadding:
          vacancyPillHorizontalPadding ?? this.vacancyPillHorizontalPadding,
      vacancyPillMargin: vacancyPillMargin ?? this.vacancyPillMargin,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      highlightBackgroundColor:
          highlightBackgroundColor ?? this.highlightBackgroundColor,
      monospaceBackgroundColor:
          monospaceBackgroundColor ?? this.monospaceBackgroundColor,
      monospaceFontFamily: monospaceFontFamily ?? this.monospaceFontFamily,
      monospaceFontFamilyFallback:
          monospaceFontFamilyFallback ?? this.monospaceFontFamilyFallback,
      dividerColor: dividerColor ?? this.dividerColor,
      alertColors: alertColors ?? this.alertColors,
      blockFilter: clearBlockFilter ? null : blockFilter ?? this.blockFilter,
      spanFilter: clearSpanFilter ? null : spanFilter ?? this.spanFilter,
      builder: clearBuilder ? null : builder ?? this.builder,
      onLinkTap: clearOnLinkTap ? null : onLinkTap ?? this.onLinkTap,
      onMentionTap:
          clearOnMentionTap ? null : onMentionTap ?? this.onMentionTap,
      onVacancyTap:
          clearOnVacancyTap ? null : onVacancyTap ?? this.onVacancyTap,
      highlighter: highlighter ?? this.highlighter,
      cursorResolver:
          clearCursorResolver ? null : cursorResolver ?? this.cursorResolver,
      emojiRuns: clearEmojiRuns ? null : emojiRuns ?? this.emojiRuns,
      emojiScale: emojiScale ?? this.emojiScale,
    );
  }

  @override
  ThemeExtension<MarkdownThemeData> lerp(
    covariant MarkdownThemeData? other,
    double t,
  ) {
    if (identical(this, other)) return this;

    return MarkdownThemeData(
      textDirection:
          t < 0.5 ? textDirection : other?.textDirection ?? TextDirection.ltr,
      textScaler:
          t < 0.5 ? textScaler : other?.textScaler ?? TextScaler.noScaling,
      textStyle: TextStyle.lerp(textStyle, other?.textStyle, t)!,
      h1Style: TextStyle.lerp(h1Style, other?.h1Style, t),
      h2Style: TextStyle.lerp(h2Style, other?.h2Style, t),
      h3Style: TextStyle.lerp(h3Style, other?.h3Style, t),
      h4Style: TextStyle.lerp(h4Style, other?.h4Style, t),
      h5Style: TextStyle.lerp(h5Style, other?.h5Style, t),
      h6Style: TextStyle.lerp(h6Style, other?.h6Style, t),
      quoteStyle: TextStyle.lerp(quoteStyle, other?.quoteStyle, t),
      linkColor: Color.lerp(linkColor, other?.linkColor, t),
      linkStyle: TextStyle.lerp(linkStyle, other?.linkStyle, t),
      mentionColor: Color.lerp(mentionColor, other?.mentionColor, t),
      vacancyPillColor:
          Color.lerp(vacancyPillColor, other?.vacancyPillColor, t),
      vacancyPillBackground:
          Color.lerp(vacancyPillBackground, other?.vacancyPillBackground, t),
      vacancyPillMutedColor:
          Color.lerp(vacancyPillMutedColor, other?.vacancyPillMutedColor, t),
      vacancyPillMutedBackground: Color.lerp(
          vacancyPillMutedBackground, other?.vacancyPillMutedBackground, t),
      vacancyPillIcon: t < 0.5 ? vacancyPillIcon : other?.vacancyPillIcon,
      vacancyPillRadius:
          lerpDouble(vacancyPillRadius, other?.vacancyPillRadius, t),
      vacancyPillIconSize:
          lerpDouble(vacancyPillIconSize, other?.vacancyPillIconSize, t),
      vacancyPillGap: lerpDouble(vacancyPillGap, other?.vacancyPillGap, t),
      vacancyPillHorizontalPadding: lerpDouble(
          vacancyPillHorizontalPadding, other?.vacancyPillHorizontalPadding, t),
      vacancyPillMargin:
          lerpDouble(vacancyPillMargin, other?.vacancyPillMargin, t),
      surfaceColor: Color.lerp(surfaceColor, other?.surfaceColor, t),
      highlightBackgroundColor: Color.lerp(
          highlightBackgroundColor, other?.highlightBackgroundColor, t),
      monospaceBackgroundColor: Color.lerp(
          monospaceBackgroundColor, other?.monospaceBackgroundColor, t),
      // A font family cannot be interpolated — snap at the midpoint.
      monospaceFontFamily: t < 0.5
          ? monospaceFontFamily
          : other?.monospaceFontFamily ?? monospaceFontFamily,
      monospaceFontFamilyFallback: t < 0.5
          ? monospaceFontFamilyFallback
          : other?.monospaceFontFamilyFallback ?? monospaceFontFamilyFallback,
      dividerColor: Color.lerp(dividerColor, other?.dividerColor, t),
      alertColors: t < 0.5 ? alertColors : other?.alertColors,
      blockFilter: t < 0.5 ? blockFilter : other?.blockFilter,
      spanFilter: t < 0.5 ? spanFilter : other?.spanFilter,
      builder: t < 0.5 ? builder : other?.builder,
      onLinkTap: t < 0.5 ? onLinkTap : other?.onLinkTap,
      onMentionTap: t < 0.5 ? onMentionTap : other?.onMentionTap,
      onVacancyTap: t < 0.5 ? onVacancyTap : other?.onVacancyTap,
      highlighter: t < 0.5 ? highlighter : other?.highlighter,
      cursorResolver: t < 0.5 ? cursorResolver : other?.cursorResolver,
      emojiRuns: t < 0.5 ? emojiRuns : other?.emojiRuns,
      emojiScale: t < 0.5 ? emojiScale : other?.emojiScale ?? emojiScale,
    );
  }

  @override
  String toString() => 'MarkdownThemeData{}';
}

/// {@template theme}
/// MarkdownTheme widget.
/// {@endtemplate}
class MarkdownTheme extends InheritedWidget {
  /// {@macro theme}
  const MarkdownTheme({
    required this.data,
    required super.child,
    super.key, // ignore: unused_element
  });

  /// The state from the closest instance of this class
  /// that encloses the given context, if any.
  /// e.g. `Theme.maybeOf(context)`.
  static MarkdownThemeData? maybeOf(BuildContext context,
          {bool listen = true}) =>
      listen
          ? context.dependOnInheritedWidgetOfExactType<MarkdownTheme>()?.data
          : context.getInheritedWidgetOfExactType<MarkdownTheme>()?.data;

  static Never _notFoundInheritedWidgetOfExactType() => throw ArgumentError(
        'Out of scope, not found inherited widget '
            'a MarkdownTheme of the exact type',
        'out_of_scope',
      );

  /// The state from the closest instance of this class
  /// that encloses the given context.
  /// e.g. `Theme.of(context)`
  static MarkdownThemeData of(BuildContext context, {bool listen = true}) =>
      maybeOf(context, listen: listen) ?? _notFoundInheritedWidgetOfExactType();

  /// The current theme data for Markdown widgets.
  final MarkdownThemeData data;

  @override
  bool updateShouldNotify(covariant MarkdownTheme oldWidget) =>
      !identical(data, oldWidget.data);
}
