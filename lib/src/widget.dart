import 'package:flutter/widgets.dart';

import 'markdown.dart' show Markdown;
import 'render.dart' show MarkdownRenderObject;
import 'selection.dart' show MarkdownSelectionController;
import 'selection_scope.dart' show MarkdownSelectionScope;
import 'theme.dart';

/// {@template markdown_widget}
/// MarkdownWidget widget.
/// {@endtemplate}
class MarkdownWidget extends LeafRenderObjectWidget {
  /// {@macro markdown_widget}
  const MarkdownWidget({
    required this.markdown,
    this.theme,
    this.controller,
    this.documentId,
    this.cursorResolver,
    super.key, // ignore: unused_element
  });

  /// Current markdown entity to render.
  final Markdown markdown;

  /// Current theme for the markdown widget.
  final MarkdownThemeData? theme;

  /// Selection controller. Falls back to the nearest [MarkdownSelectionScope]
  /// when null.
  ///
  /// Also the [MarkdownHorizontalPanStore] for pannable blocks. Pan remount
  /// needs a controller and [documentId] even if you never show selection
  /// chrome; you do not need a scope for that.
  final MarkdownSelectionController? controller;

  /// Stable id for selection anchors and horizontal pan.
  ///
  /// Both features need this plus a [controller]. For selection, register the
  /// document model on the controller yourself.
  final Object? documentId;

  /// An optional callback to dynamically resolve the mouse cursor based on
  /// hover offset, hit block index, and hit block model.
  ///
  /// When non-null, overrides [MarkdownThemeData.cursorResolver].
  final MarkdownCursorResolver? cursorResolver;

  MarkdownThemeData _resolveTheme(BuildContext context) =>
      theme ??
      MarkdownTheme.maybeOf(context) ??
      MarkdownThemeData(
        textStyle: DefaultTextStyle.of(context).style,
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        textScaler:
            MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
      );

  MarkdownSelectionController? _resolveController(BuildContext context) =>
      documentId == null
          ? null
          : (controller ?? MarkdownSelectionScope.maybeOf(context));

  @override
  RenderObject createRenderObject(BuildContext context) => MarkdownRenderObject(
        markdown: markdown,
        theme: _resolveTheme(context),
        cursorResolver: cursorResolver,
      )
        ..updateSelection(_resolveController(context), documentId)
        ..setTickerModeEnabled(TickerMode.valuesOf(context).enabled);

  @override
  void updateRenderObject(
    BuildContext context,
    MarkdownRenderObject renderObject,
  ) {
    // Bind selection / pan store before updating the model so a simultaneous
    // markdown + documentId change cannot harvest pans into the wrong doc.
    renderObject
      ..updateSelection(_resolveController(context), documentId)
      ..setTickerModeEnabled(TickerMode.valuesOf(context).enabled)
      ..update(
        markdown: markdown,
        theme: _resolveTheme(context),
        cursorResolver: cursorResolver,
      );
  }
}
