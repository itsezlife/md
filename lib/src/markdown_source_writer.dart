import 'nodes.dart';

/// Writes inline spans back as markdown source that this package's parser (and
/// the chat dialect's) reads as the same spans.
///
/// Internal to the package, not exported: [MarkdownSourceFormatter] is the
/// public way in. It lives apart from `selection.dart` because it is a
/// self-contained mechanism (span runs in, one string out) that needs none of
/// the selection state.
///
/// The marks are the parser's own, written as toggles the way it reads them:
/// a marker switches its style on or off, and the order and nesting of
/// different styles do not matter, so a style that ends inside another needs
/// no splitting. Three things are written around the toggles so the result
/// reads back:
///
/// - whitespace at the edge of a styled run is moved outside its marks (the
///   parser opens a marker only before a non-space and closes it only after
///   one), which un-styles that whitespace;
/// - a code span is closed and reopened around any other change of marks,
///   because nothing inside a code span is markup;
/// - literal text is escaped (see [_escape]).
///
/// What cannot be written is dropped to the nearest thing that can, never to
/// markup that would read back as something else: a code run holding a
/// backtick is written as plain text (the parser has no longer fence), and a
/// link label holding `]` keeps a backslash that the parser does not remove.
abstract final class MarkdownSourceWriter {
  /// The markdown source of [spans].
  static String inline(List<MD$Span> spans) {
    final pieces = _pieces(_runs(spans));
    while (true) {
      final written = _write(pieces.items, pieces.tail);
      final unreadable = written.unreadableUnderline;
      if (unreadable == null) return written.text;
      // The parser would read its `__` as literal underscores and the text
      // around them would be spoiled, so the underline goes and the text stays.
      for (var i = unreadable.$1; i <= unreadable.$2; i++) {
        pieces.items[i].marks &= ~_underline;
      }
    }
  }
}

/// [pieces] written with their marks, and the first underline (as the range of
/// its pieces) whose markers the parser would not read as markers.
///
/// The parser opens `__` only when no word character precedes it and closes it
/// only when none follows, so an underline that starts or ends inside a word
/// cannot be written. Which characters touch the markers is only known once
/// everything around them is written, so it is checked on the output.
({String text, (int, int)? unreadableUnderline}) _write(
  List<_Piece> pieces,
  String tail,
) {
  final sink = _Sink();
  final underlines = <(int, int, int, int)>[]; // first, last, open at, close at
  var open = 0;
  var openCode = false;
  var trail = '';
  var underlineFrom = 0;
  var underlineAt = 0;
  void writeMarkers(int bits, int piece, {required bool opening}) {
    for (final (style, marker) in _marks) {
      if (bits & style.value == 0) continue;
      final at = sink.structural(marker);
      if (style != MD$Style.underline) continue;
      if (opening) {
        underlineFrom = piece;
        underlineAt = at;
      } else {
        underlines.add((underlineFrom, piece - 1, underlineAt, at));
      }
    }
  }

  for (var i = 0; i < pieces.length; i++) {
    final piece = pieces[i];
    final closing = open & ~piece.marks;
    final opening = piece.marks & ~open;
    // Nothing inside a code span is markup, so it is closed around any other
    // change of marks and reopened after.
    final closeCode = openCode && (!piece.code || closing != 0 || opening != 0);
    final openCodeAgain = piece.code && (!openCode || closeCode);
    if (closeCode) sink.structural('`');
    writeMarkers(closing, i, opening: false);
    sink
      ..text(trail)
      ..text(piece.lead);
    writeMarkers(opening, i, opening: true);
    if (openCodeAgain) sink.structural('`');
    if (piece.atom) {
      sink.structural(piece.core, bracket: piece.core.startsWith('['));
    } else {
      sink.text(piece.core);
    }
    open = piece.marks;
    openCode = piece.code;
    trail = piece.trail;
  }
  if (openCode) sink.structural('`');
  writeMarkers(open, pieces.length, opening: false);
  sink
    ..text(trail)
    ..text(tail);
  final text = sink.finish();
  for (final (first, last, openAt, closeAt) in underlines) {
    final before = openAt > 0 && _isWord(text.codeUnitAt(openAt - 1));
    final after =
        closeAt + 2 < text.length && _isWord(text.codeUnitAt(closeAt + 2));
    if (before || after) {
      return (text: text, unreadableUnderline: (first, last));
    }
  }
  return (text: text, unreadableUnderline: null);
}

// --- Marks ---

/// The styles written as a toggle marker, in the order their markers are
/// written (closing and opening alike).
const List<(MD$Style, String)> _marks = <(MD$Style, String)>[
  (MD$Style.bold, '**'),
  (MD$Style.italic, '*'),
  (MD$Style.underline, '__'),
  (MD$Style.strikethrough, '~~'),
  (MD$Style.spoiler, '||'),
  (MD$Style.highlight, '=='),
];

final int _markMask = _marks.fold<int>(0, (mask, mark) => mask | mark.$1.value);

final int _underline = MD$Style.underline.value;

// --- Runs: spans merged, atoms written ---

/// One maximal stretch of text of one style, or one atom (a link, a mention,
/// an image) written whole.
final class _Run {
  _Run(this.text, this.marks, {this.code = false, this.atom = false});

  /// Raw text; for an [atom], its final markup.
  String text;

  /// The [_marks] bits.
  final int marks;

  /// Whether the text is a code span.
  final bool code;

  /// Whether [text] is finished markup that is not escaped or split.
  final bool atom;
}

List<_Run> _runs(List<MD$Span> spans) {
  final runs = <_Run>[];
  for (final span in spans) {
    final marks = span.style.value & _markMask;
    final markup = _atom(span);
    if (markup != null) {
      runs.add(_Run(markup, marks, atom: true));
      continue;
    }
    if (span.text.isEmpty) continue;
    // The parser has no code fence longer than one backtick.
    final code =
        span.style.contains(MD$Style.monospace) && !span.text.contains('`');
    final last = runs.isEmpty ? null : runs.last;
    if (last != null &&
        !last.atom &&
        last.marks == marks &&
        last.code == code) {
      last.text += span.text;
    } else {
      runs.add(_Run(span.text, marks, code: code));
    }
  }
  return runs;
}

/// The markup of a link, mention-class or image [span], or null when [span] is
/// none of them or lacks what its markup needs (it is then written as text).
String? _atom(MD$Span span) {
  final extra = span.extra;
  if (extra == null) return null;
  final style = span.style;
  final String? destination;
  if (style.contains(MD$Style.image)) {
    destination = extra['src'] as String?;
  } else if (style.contains(MD$Style.mention)) {
    final scheme = extra['scheme'];
    final payload = scheme == 'mention' ? extra['id'] : extra['name'];
    destination =
        scheme is String && payload != null ? '$scheme:$payload' : null;
  } else if (style.contains(MD$Style.link)) {
    destination = (extra['href'] ?? extra['url']) as String?;
  } else {
    return null;
  }
  if (destination == null) return null;
  final title = style.contains(MD$Style.mention) ? null : extra['alt'];
  final bang = style.contains(MD$Style.image) ? '!' : '';
  // The parser reads a label as it is, so only the `]` that would end it early
  // is escaped.
  final label = span.text.replaceAll(']', r'\]');
  return '$bang[$label](${_destination(destination, title as String?)})';
}

/// A link target, between angle brackets when it holds whitespace (the parser
/// ends a bare target at the first space), then the title when it can be
/// quoted. The parser keeps a target as written, so nothing in it is escaped.
String _destination(String target, String? title) {
  final bracket =
      target.contains(RegExp(r'[ \t\r\n]')) && !target.contains('>');
  final out = StringBuffer(bracket ? '<$target>' : target);
  if (title != null) {
    if (!title.contains('"')) {
      out.write(' "$title"');
    } else if (!title.contains("'")) {
      out.write(" '$title'");
    }
  }
  return out.toString();
}

// --- Pieces: escaped, whitespace set apart ---

final class _Piece {
  _Piece(
    this.lead,
    this.core,
    this.trail,
    this.marks, {
    required this.code,
    required this.atom,
  });

  /// Whitespace written before the opening marks.
  final String lead;

  /// The text between the marks.
  final String core;

  /// Whitespace written after the closing marks.
  final String trail;

  /// The [_marks] bits; underline bits are dropped when unreadable.
  int marks;
  final bool code;
  final bool atom;
}

({List<_Piece> items, String tail}) _pieces(List<_Run> runs) {
  final items = <_Piece>[];
  final escapes = _EscapeState();
  var carry = '';
  for (final run in runs) {
    if (run.atom || run.code) {
      escapes.passed();
      items.add(
        _Piece(carry, run.text, '', run.marks, code: run.code, atom: run.atom),
      );
      carry = '';
      continue;
    }
    final text = escapes.apply(run.text);
    var start = 0;
    var end = text.length;
    while (start < end && _isSpace(text.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
      end--;
    }
    // Whitespace alone carries no style: it joins the next piece's lead.
    if (start == end) {
      carry += text;
      continue;
    }
    items.add(
      _Piece(
        carry + text.substring(0, start),
        text.substring(start, end),
        text.substring(end),
        run.marks,
        code: false,
        atom: false,
      ),
    );
    carry = '';
  }
  return (items: items, tail: carry);
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

// --- Escaping ---

/// Backslash-escapes the text of runs so that it reads back as text.
///
/// Escaped: `\ * ` [ ]` always; `_` unless it sits between two word characters
/// of its own run; a run of `~`, `|` or `=` (the other markers) when it has
/// two or more characters and is not walled in by whitespace, or when it
/// touches the edge of its run (a marker may be written there); and the
/// characters that make a line a block: `# > - + |`, the `.` or `)` after
/// leading digits, and a run of three `~` or `=`. A block marker counts at the
/// first non-space character of a line, wherever the run that holds it began,
/// so the state of the line is carried from run to run.
final class _EscapeState {
  bool _atLineStart = true;

  /// A run written whole (code, atom) was passed; the line has begun.
  void passed() => _atLineStart = false;

  String apply(String text) {
    final length = text.length;
    final flags = List<bool>.filled(length, false);
    var lineStart = _atLineStart;
    for (var i = 0; i < length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x0A) {
        lineStart = true;
        continue;
      }
      if (unit == 0x20 || unit == 0x09 || unit == 0x0D) continue;
      if (lineStart) _flagBlockMarker(text, i, unit, flags);
      lineStart = false;
    }
    _atLineStart = lineStart;
    for (var i = 0; i < length; i++) {
      final unit = text.codeUnitAt(i);
      switch (unit) {
        case 0x5C || 0x2A || 0x60 || 0x5B || 0x5D: // \ * ` [ ]
          flags[i] = true;
        case 0x5F: // _
          if (!_isIntraword(text, i)) flags[i] = true;
        case 0x7E || 0x7C || 0x3D: // ~ | =
          var end = i;
          while (end < length && text.codeUnitAt(end) == unit) {
            end++;
          }
          if (_runNeedsEscape(text, i, end)) {
            for (var j = i; j < end; j++) {
              flags[j] = true;
            }
          }
          i = end - 1;
      }
    }
    if (!flags.contains(true)) return text;
    final out = StringBuffer();
    for (var i = 0; i < length; i++) {
      if (flags[i]) out.write(r'\');
      out.writeCharCode(text.codeUnitAt(i));
    }
    return out.toString();
  }

  void _flagBlockMarker(String text, int i, int unit, List<bool> flags) {
    switch (unit) {
      case 0x23 || 0x3E || 0x2D || 0x2B || 0x7C: // # > - + |
        flags[i] = true;
      case >= 0x30 && <= 0x39:
        var digits = i;
        while (digits < text.length &&
            text.codeUnitAt(digits) >= 0x30 &&
            text.codeUnitAt(digits) <= 0x39) {
          digits++;
        }
        if (digits < text.length &&
            (text.codeUnitAt(digits) == 0x2E ||
                text.codeUnitAt(digits) == 0x29)) {
          flags[digits] = true;
        }
      case 0x7E || 0x3D: // ~ =
        var run = i;
        while (run < text.length && text.codeUnitAt(run) == unit) {
          run++;
        }
        if (run - i >= 3) {
          for (var j = i; j < run; j++) {
            flags[j] = true;
          }
        }
    }
  }

  // An underscore between two word characters is never emphasis. At the edge
  // of a run a marker may be written next to it, so it is escaped there.
  bool _isIntraword(String text, int i) =>
      i > 0 &&
      i + 1 < text.length &&
      _isWord(text.codeUnitAt(i - 1)) &&
      _isWord(text.codeUnitAt(i + 1));

  // A pair marker needs two or more of a character and something to open or
  // close against; a run walled in by whitespace can do neither.
  bool _runNeedsEscape(String text, int start, int end) {
    if (start == 0 || end == text.length) return true;
    if (end - start < 2) return false;
    return !(_isSpace(text.codeUnitAt(start - 1)) &&
        _isSpace(text.codeUnitAt(end)));
  }
}

// The parser's own idea of a word character: an ASCII letter or digit, or any
// non-ASCII unit.
bool _isWord(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit >= 0x80;

// --- Output ---

/// The output buffer, holding back a trailing `!` until it is known whether a
/// link or mention follows: written right before its `[` the `!` would turn it
/// into an image, so it is escaped.
final class _Sink {
  final StringBuffer _buffer = StringBuffer();
  bool _bangPending = false;

  void text(String text) {
    if (text.isEmpty) return;
    _flush();
    if (text.endsWith('!')) {
      _buffer.write(text.substring(0, text.length - 1));
      _bangPending = true;
    } else {
      _buffer.write(text);
    }
  }

  /// Writes [markup]; returns the offset it begins at.
  int structural(String markup, {bool bracket = false}) {
    if (markup.isEmpty) return _buffer.length;
    if (_bangPending) {
      _buffer.write(bracket ? r'\!' : '!');
      _bangPending = false;
    }
    final at = _buffer.length;
    _buffer.write(markup);
    return at;
  }

  String finish() {
    _flush();
    return _buffer.toString();
  }

  void _flush() {
    if (_bangPending) _buffer.write('!');
    _bangPending = false;
  }
}
