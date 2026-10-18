/// A writer's output for link labels, as a literal table.
///
/// Each row is a body a chat host's markdown writer produced for text with one
/// link-like thing in it, and the text it was written from: [markdown], the
/// text [before] the label, the [label] itself (the characters the writer was
/// given, not what it wrote), the text [after] it, and which [kind] of thing
/// the label belongs to (`link`, `mention`, `hashtag`, `username` or `image`).
///
/// The labels are drawn from every character a writer puts a backslash before
/// (`\ * ` [ ] _ ~ | =`), the block markers it leaves bare inside a label
/// (`# > - + .`), brackets and a bang, plus right-to-left letters, a right-to-
/// left mark, a ZWJ sequence and combining marks, alone and mixed. The rows
/// were captured once from the writer's own encoder (a fixed seed), so this
/// package depends on none of its code; a row whose markdown the writer
/// changes is a row of this table to update, and the parser must keep reading
/// the old one for stored bodies.
library;

/// One row: see the library comment.
typedef LabelRow = (
  String markdown,
  String before,
  String label,
  String after,
  String kind,
);

/// The rows.
const List<LabelRow> labelRows = [
  ('[\\\\](https://a.b)', '', '\\', '', 'link'),
  ('x [\\\\](https://a.b) y', 'x ', '\\', ' y', 'link'),
  ('wow\\![\\\\](https://a.b)!', 'wow!', '\\', '!', 'link'),
  ('[\\*](mention:7)', '', '*', '', 'mention'),
  ('[\\`](hashtag:t)', '', '`', '', 'hashtag'),
  ('[\\[](username:u)', '', '[', '', 'username'),
  ('x [\\[](username:u) y', 'x ', '[', ' y', 'username'),
  ('wow\\![\\[](username:u)!', 'wow!', '[', '!', 'username'),
  ('![\\]](document:5)', '', ']', '', 'image'),
  ('[\\_](https://a.b)', '', '_', '', 'link'),
  ('[\\~](mention:7)', '', '~', '', 'mention'),
  ('x [\\~](mention:7) y', 'x ', '~', ' y', 'mention'),
  ('wow\\![\\~](mention:7)!', 'wow!', '~', '!', 'mention'),
  ('[\\|](hashtag:t)', '', '|', '', 'hashtag'),
  ('[=](username:u)', '', '=', '', 'username'),
  ('![#](document:5)', '', '#', '', 'image'),
  ('x ![#](document:5) y', 'x ', '#', ' y', 'image'),
  ('wow!![#](document:5)!', 'wow!', '#', '!', 'image'),
  ('[>](https://a.b)', '', '>', '', 'link'),
  ('[-](mention:7)', '', '-', '', 'mention'),
  ('[+](hashtag:t)', '', '+', '', 'hashtag'),
  ('x [+](hashtag:t) y', 'x ', '+', ' y', 'hashtag'),
  ('wow\\![+](hashtag:t)!', 'wow!', '+', '!', 'hashtag'),
  ('[.](username:u)', '', '.', '', 'username'),
  ('![)](document:5)', '', ')', '', 'image'),
  ('[(](https://a.b)', '', '(', '', 'link'),
  ('x [(](https://a.b) y', 'x ', '(', ' y', 'link'),
  ('wow\\![(](https://a.b)!', 'wow!', '(', '!', 'link'),
  ('[!](mention:7)', '', '!', '', 'mention'),
  ('[a](hashtag:t)', '', 'a', '', 'hashtag'),
  ('[b](username:u)', '', 'b', '', 'username'),
  ('x [b](username:u) y', 'x ', 'b', ' y', 'username'),
  ('wow\\![b](username:u)!', 'wow!', 'b', '!', 'username'),
  ('![Z](document:5)', '', 'Z', '', 'image'),
  ('[7](https://a.b)', '', '7', '', 'link'),
  ('[\u{5D0}](mention:7)', '', '\u{5D0}', '', 'mention'),
  ('x [\u{5D0}](mention:7) y', 'x ', '\u{5D0}', ' y', 'mention'),
  ('wow\\![\u{5D0}](mention:7)!', 'wow!', '\u{5D0}', '!', 'mention'),
  ('[\u{639}](hashtag:t)', '', '\u{639}', '', 'hashtag'),
  ('[\u{200F}](username:u)', '', '\u{200F}', '', 'username'),
  ('![\u{200D}](document:5)', '', '\u{200D}', '', 'image'),
  ('x ![\u{200D}](document:5) y', 'x ', '\u{200D}', ' y', 'image'),
  ('wow!![\u{200D}](document:5)!', 'wow!', '\u{200D}', '!', 'image'),
  (
    '[\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}](https://a.b)',
    '',
    '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}',
    '',
    'link'
  ),
  ('[\u{301}](mention:7)', '', '\u{301}', '', 'mention'),
  ('[\u{E9}](hashtag:t)', '', '\u{E9}', '', 'hashtag'),
  ('x [\u{E9}](hashtag:t) y', 'x ', '\u{E9}', ' y', 'hashtag'),
  ('wow\\![\u{E9}](hashtag:t)!', 'wow!', '\u{E9}', '!', 'hashtag'),
  ('[x\\\\\\\\y](username:u)', '', 'x\\\\y', '', 'username'),
  ('![x\\*\\*y](document:5)', '', 'x**y', '', 'image'),
  ('[x\\`\\`y](https://a.b)', '', 'x``y', '', 'link'),
  ('x [x\\`\\`y](https://a.b) y', 'x ', 'x``y', ' y', 'link'),
  ('wow\\![x\\`\\`y](https://a.b)!', 'wow!', 'x``y', '!', 'link'),
  ('[x\\[\\[y](mention:7)', '', 'x[[y', '', 'mention'),
  ('[x\\]\\]y](hashtag:t)', '', 'x]]y', '', 'hashtag'),
  ('[x\\_\\_y](username:u)', '', 'x__y', '', 'username'),
  ('x [x\\_\\_y](username:u) y', 'x ', 'x__y', ' y', 'username'),
  ('wow\\![x\\_\\_y](username:u)!', 'wow!', 'x__y', '!', 'username'),
  ('![x\\~\\~y](document:5)', '', 'x~~y', '', 'image'),
  ('[x\\|\\|y](https://a.b)', '', 'x||y', '', 'link'),
  ('[x\\=\\=y](mention:7)', '', 'x==y', '', 'mention'),
  ('x [x\\=\\=y](mention:7) y', 'x ', 'x==y', ' y', 'mention'),
  ('wow\\![x\\=\\=y](mention:7)!', 'wow!', 'x==y', '!', 'mention'),
  ('[x##y](hashtag:t)', '', 'x##y', '', 'hashtag'),
  ('[x>>y](username:u)', '', 'x>>y', '', 'username'),
  ('![x--y](document:5)', '', 'x--y', '', 'image'),
  ('x ![x--y](document:5) y', 'x ', 'x--y', ' y', 'image'),
  ('wow!![x--y](document:5)!', 'wow!', 'x--y', '!', 'image'),
  ('[x++y](https://a.b)', '', 'x++y', '', 'link'),
  ('[x..y](mention:7)', '', 'x..y', '', 'mention'),
  ('[x))y](hashtag:t)', '', 'x))y', '', 'hashtag'),
  ('x [x))y](hashtag:t) y', 'x ', 'x))y', ' y', 'hashtag'),
  ('wow\\![x))y](hashtag:t)!', 'wow!', 'x))y', '!', 'hashtag'),
  ('[x((y](username:u)', '', 'x((y', '', 'username'),
  ('![x!!y](document:5)', '', 'x!!y', '', 'image'),
  ('[xaay](https://a.b)', '', 'xaay', '', 'link'),
  ('x [xaay](https://a.b) y', 'x ', 'xaay', ' y', 'link'),
  ('wow\\![xaay](https://a.b)!', 'wow!', 'xaay', '!', 'link'),
  ('[xbby](mention:7)', '', 'xbby', '', 'mention'),
  ('[xZZy](hashtag:t)', '', 'xZZy', '', 'hashtag'),
  ('[x77y](username:u)', '', 'x77y', '', 'username'),
  ('x [x77y](username:u) y', 'x ', 'x77y', ' y', 'username'),
  ('wow\\![x77y](username:u)!', 'wow!', 'x77y', '!', 'username'),
  ('![x  y](document:5)', '', 'x  y', '', 'image'),
  ('[x\u{5D0}\u{5D0}y](https://a.b)', '', 'x\u{5D0}\u{5D0}y', '', 'link'),
  ('[x\u{639}\u{639}y](mention:7)', '', 'x\u{639}\u{639}y', '', 'mention'),
  (
    'x [x\u{639}\u{639}y](mention:7) y',
    'x ',
    'x\u{639}\u{639}y',
    ' y',
    'mention'
  ),
  (
    'wow\\![x\u{639}\u{639}y](mention:7)!',
    'wow!',
    'x\u{639}\u{639}y',
    '!',
    'mention'
  ),
  ('[x\u{200F}\u{200F}y](hashtag:t)', '', 'x\u{200F}\u{200F}y', '', 'hashtag'),
  (
    '[x\u{200D}\u{200D}y](username:u)',
    '',
    'x\u{200D}\u{200D}y',
    '',
    'username'
  ),
  (
    '![x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{1F468}'
        '\u{200D}\u{1F469}\u{200D}\u{1F467}y](document:5)',
    '',
    'x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{1F468}'
        '\u{200D}\u{1F469}\u{200D}\u{1F467}y',
    '',
    'image'
  ),
  (
    'x ![x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{1F468}'
        '\u{200D}\u{1F469}\u{200D}\u{1F467}y](document:5) y',
    'x ',
    'x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{1F468}'
        '\u{200D}\u{1F469}\u{200D}\u{1F467}y',
    ' y',
    'image'
  ),
  (
    'wow!![x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{1F468}'
        '\u{200D}\u{1F469}\u{200D}\u{1F467}y](document:5)!',
    'wow!',
    'x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{1F468}'
        '\u{200D}\u{1F469}\u{200D}\u{1F467}y',
    '!',
    'image'
  ),
  ('[x\u{301}\u{301}y](https://a.b)', '', 'x\u{301}\u{301}y', '', 'link'),
  ('[x\u{E9}\u{E9}y](mention:7)', '', 'x\u{E9}\u{E9}y', '', 'mention'),
  ('[a\\\\\\]b](hashtag:t)', '', 'a\\]b', '', 'hashtag'),
  ('x [a\\\\\\]b](hashtag:t) y', 'x ', 'a\\]b', ' y', 'hashtag'),
  ('wow\\![a\\\\\\]b](hashtag:t)!', 'wow!', 'a\\]b', '!', 'hashtag'),
  ('[\\\\\\[x\\\\\\]](username:u)', '', '\\[x\\]', '', 'username'),
  ('![\\*\\*b\\*\\*](document:5)', '', '**b**', '', 'image'),
  ('[\\~\\~s\\~\\~](https://a.b)', '', '~~s~~', '', 'link'),
  ('x [\\~\\~s\\~\\~](https://a.b) y', 'x ', '~~s~~', ' y', 'link'),
  ('wow\\![\\~\\~s\\~\\~](https://a.b)!', 'wow!', '~~s~~', '!', 'link'),
  ('[\\|\\|p\\|\\|](mention:7)', '', '||p||', '', 'mention'),
  ('[\\=\\=h\\=\\=](hashtag:t)', '', '==h==', '', 'hashtag'),
  ('[\\_\\_u\\_\\_](username:u)', '', '__u__', '', 'username'),
  ('x [\\_\\_u\\_\\_](username:u) y', 'x ', '__u__', ' y', 'username'),
  ('wow\\![\\_\\_u\\_\\_](username:u)!', 'wow!', '__u__', '!', 'username'),
  ('![\\`c\\`](document:5)', '', '`c`', '', 'image'),
  ('[\\_x\\_](https://a.b)', '', '_x_', '', 'link'),
  ('[snake_case](mention:7)', '', 'snake_case', '', 'mention'),
  ('x [snake_case](mention:7) y', 'x ', 'snake_case', ' y', 'mention'),
  ('wow\\![snake_case](mention:7)!', 'wow!', 'snake_case', '!', 'mention'),
  ('[#tag](hashtag:t)', '', '#tag', '', 'hashtag'),
  ('[> q](username:u)', '', '> q', '', 'username'),
  ('![- i](document:5)', '', '- i', '', 'image'),
  ('x ![- i](document:5) y', 'x ', '- i', ' y', 'image'),
  ('wow!![- i](document:5)!', 'wow!', '- i', '!', 'image'),
  ('[1. n](https://a.b)', '', '1. n', '', 'link'),
  ('[+ p](mention:7)', '', '+ p', '', 'mention'),
  ('[b(\\~](hashtag:t)', '', 'b(~', '', 'hashtag'),
  ('x [b(\\~](hashtag:t) y', 'x ', 'b(~', ' y', 'hashtag'),
  ('wow\\![b(\\~](hashtag:t)!', 'wow!', 'b(~', '!', 'hashtag'),
  ('[#\u{639}|~  ](username:u)', '', '#\u{639}|~  ', '', 'username'),
  ('![\\~#bb\\].](document:5)', '', '~#bb].', '', 'image'),
  ('[b#a+](https://a.b)', '', 'b#a+', '', 'link'),
  ('x [b#a+](https://a.b) y', 'x ', 'b#a+', ' y', 'link'),
  ('wow\\![b#a+](https://a.b)!', 'wow!', 'b#a+', '!', 'link'),
  ('[b).](mention:7)', '', 'b).', '', 'mention'),
  ('[>=\\`\u{301}-](hashtag:t)', '', '>=`\u{301}-', '', 'hashtag'),
  ('[=ZZ](username:u)', '', '=ZZ', '', 'username'),
  ('x [=ZZ](username:u) y', 'x ', '=ZZ', ' y', 'username'),
  ('wow\\![=ZZ](username:u)!', 'wow!', '=ZZ', '!', 'username'),
  ('![a=\\_)+\u{200D}](document:5)', '', 'a=_)+\u{200D}', '', 'image'),
  ('[\\`\\_|\\_\\\\\u{E9}\\`](https://a.b)', '', '`_|_\\\u{E9}`', '', 'link'),
  (
    '[\u{E9}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}= |\u{E9}'
        '\u{200F}](mention:7)',
    '',
    '\u{E9}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}= |\u{E9}\u{200F}',
    '',
    'mention'
  ),
  (
    'x [\u{E9}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}= |'
        '\u{E9}\u{200F}](mention:7) y',
    'x ',
    '\u{E9}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}= |\u{E9}\u{200F}',
    ' y',
    'mention'
  ),
  (
    'wow\\![\u{E9}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}= |'
        '\u{E9}\u{200F}](mention:7)!',
    'wow!',
    '\u{E9}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}= |\u{E9}\u{200F}',
    '!',
    'mention'
  ),
  ('[\\]!](hashtag:t)', '', ']!', '', 'hashtag'),
  (
    '[\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467})!!a|!](username:u)',
    '',
    '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467})!!a|!',
    '',
    'username'
  ),
  ('![!\u{200D}\u{639}](document:5)', '', '!\u{200D}\u{639}', '', 'image'),
  (
    'x ![!\u{200D}\u{639}](document:5) y',
    'x ',
    '!\u{200D}\u{639}',
    ' y',
    'image'
  ),
  (
    'wow!![!\u{200D}\u{639}](document:5)!',
    'wow!',
    '!\u{200D}\u{639}',
    '!',
    'image'
  ),
  ('[.\\[\\|](https://a.b)', '', '.[|', '', 'link'),
  (
    '[-\u{200F}\\]\u{200D}aa\u{200D}](mention:7)',
    '',
    '-\u{200F}]\u{200D}aa\u{200D}',
    '',
    'mention'
  ),
  (
    '[\u{200F}\u{301}#\\*.](hashtag:t)',
    '',
    '\u{200F}\u{301}#*.',
    '',
    'hashtag'
  ),
  (
    'x [\u{200F}\u{301}#\\*.](hashtag:t) y',
    'x ',
    '\u{200F}\u{301}#*.',
    ' y',
    'hashtag'
  ),
  (
    'wow\\![\u{200F}\u{301}#\\*.](hashtag:t)!',
    'wow!',
    '\u{200F}\u{301}#*.',
    '!',
    'hashtag'
  ),
  ('[\u{200F}+](username:u)', '', '\u{200F}+', '', 'username'),
  (
    '![\u{639}>\u{639}\\`~\u{5D0}\u{200F}](document:5)',
    '',
    '\u{639}>\u{639}`~\u{5D0}\u{200F}',
    '',
    'image'
  ),
  ('[#-](https://a.b)', '', '#-', '', 'link'),
  ('x [#-](https://a.b) y', 'x ', '#-', ' y', 'link'),
  ('wow\\![#-](https://a.b)!', 'wow!', '#-', '!', 'link'),
  ('[\\|\\`.\\]](mention:7)', '', '|`.]', '', 'mention'),
  ('[\u{5D0}\u{301}\\|](hashtag:t)', '', '\u{5D0}\u{301}|', '', 'hashtag'),
  (
    '[\\\\-\u{E9}(\u{5D0}](username:u)',
    '',
    '\\-\u{E9}(\u{5D0}',
    '',
    'username'
  ),
  (
    'x [\\\\-\u{E9}(\u{5D0}](username:u) y',
    'x ',
    '\\-\u{E9}(\u{5D0}',
    ' y',
    'username'
  ),
  (
    'wow\\![\\\\-\u{E9}(\u{5D0}](username:u)!',
    'wow!',
    '\\-\u{E9}(\u{5D0}',
    '!',
    'username'
  ),
  ('![\\~\u{639}\\`#7](document:5)', '', '~\u{639}`#7', '', 'image'),
  ('[ -\\[\\\\b\\]](https://a.b)', '', ' -[\\b]', '', 'link'),
  ('[!a>!!](mention:7)', '', '!a>!!', '', 'mention'),
  ('x [!a>!!](mention:7) y', 'x ', '!a>!!', ' y', 'mention'),
  ('wow\\![!a>!!](mention:7)!', 'wow!', '!a>!!', '!', 'mention'),
  ('[=\\\\\\[](hashtag:t)', '', '=\\[', '', 'hashtag'),
  ('[\\~\\*](username:u)', '', '~*', '', 'username'),
  (
    '![\\`\\\\+\\`\\*\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}](document:5)',
    '',
    '`\\+`*\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}',
    '',
    'image'
  ),
  (
    'x ![\\`\\\\+\\`\\*\u{1F468}\u{200D}\u{1F469}\u{200D}'
        '\u{1F467}](document:5) y',
    'x ',
    '`\\+`*\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}',
    ' y',
    'image'
  ),
  (
    'wow!![\\`\\\\+\\`\\*\u{1F468}\u{200D}\u{1F469}\u{200D}'
        '\u{1F467}](document:5)!',
    'wow!',
    '`\\+`*\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}',
    '!',
    'image'
  ),
  ('[ \u{200D}>b](https://a.b)', '', ' \u{200D}>b', '', 'link'),
  ('[+#\\\\\\_\\_)](mention:7)', '', '+#\\__)', '', 'mention'),
  ('[\\*\u{E9}(](hashtag:t)', '', '*\u{E9}(', '', 'hashtag'),
  ('x [\\*\u{E9}(](hashtag:t) y', 'x ', '*\u{E9}(', ' y', 'hashtag'),
  ('wow\\![\\*\u{E9}(](hashtag:t)!', 'wow!', '*\u{E9}(', '!', 'hashtag'),
  ('[\u{301}\\*\\*](username:u)', '', '\u{301}**', '', 'username'),
  ('![)\\`](document:5)', '', ')`', '', 'image'),
  ('[\\|#\u{5D0})\u{5D0}](https://a.b)', '', '|#\u{5D0})\u{5D0}', '', 'link'),
  (
    'x [\\|#\u{5D0})\u{5D0}](https://a.b) y',
    'x ',
    '|#\u{5D0})\u{5D0}',
    ' y',
    'link'
  ),
  (
    'wow\\![\\|#\u{5D0})\u{5D0}](https://a.b)!',
    'wow!',
    '|#\u{5D0})\u{5D0}',
    '!',
    'link'
  ),
  (
    '[\\`\u{E9}-\u{E9}\\*#b](mention:7)',
    '',
    '`\u{E9}-\u{E9}*#b',
    '',
    'mention'
  ),
  ('[+\u{301}](hashtag:t)', '', '+\u{301}', '', 'hashtag'),
  ('[)|\u{301}](username:u)', '', ')|\u{301}', '', 'username'),
  ('x [)|\u{301}](username:u) y', 'x ', ')|\u{301}', ' y', 'username'),
  ('wow\\![)|\u{301}](username:u)!', 'wow!', ')|\u{301}', '!', 'username'),
  (
    '![\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}7\\[](document:5)',
    '',
    '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}7[',
    '',
    'image'
  ),
  ('[\\_7) ](https://a.b)', '', '_7) ', '', 'link'),
  (
    '[\\`\u{5D0}\\*\u{200D}\\[\u{200D}](mention:7)',
    '',
    '`\u{5D0}*\u{200D}[\u{200D}',
    '',
    'mention'
  ),
  (
    'x [\\`\u{5D0}\\*\u{200D}\\[\u{200D}](mention:7) y',
    'x ',
    '`\u{5D0}*\u{200D}[\u{200D}',
    ' y',
    'mention'
  ),
  (
    'wow\\![\\`\u{5D0}\\*\u{200D}\\[\u{200D}](mention:7)!',
    'wow!',
    '`\u{5D0}*\u{200D}[\u{200D}',
    '!',
    'mention'
  ),
  ('[\\[\\\\](hashtag:t)', '', '[\\', '', 'hashtag'),
  ('[\\[ (-\\=\\=](username:u)', '', '[ (-==', '', 'username'),
  (
    '![\u{200F}~|\u{5D0}\\\\](document:5)',
    '',
    '\u{200F}~|\u{5D0}\\',
    '',
    'image'
  ),
  (
    'x ![\u{200F}~|\u{5D0}\\\\](document:5) y',
    'x ',
    '\u{200F}~|\u{5D0}\\',
    ' y',
    'image'
  ),
  (
    'wow!![\u{200F}~|\u{5D0}\\\\](document:5)!',
    'wow!',
    '\u{200F}~|\u{5D0}\\',
    '!',
    'image'
  ),
  ('[\\*Z\u{200F}.!b ](https://a.b)', '', '*Z\u{200F}.!b ', '', 'link'),
  (
    '[#\u{301}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\\_](mention:7)',
    '',
    '#\u{301}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}_',
    '',
    'mention'
  ),
  ('[=\\[Z\u{639})+](hashtag:t)', '', '=[Z\u{639})+', '', 'hashtag'),
  ('x [=\\[Z\u{639})+](hashtag:t) y', 'x ', '=[Z\u{639})+', ' y', 'hashtag'),
  (
    'wow\\![=\\[Z\u{639})+](hashtag:t)!',
    'wow!',
    '=[Z\u{639})+',
    '!',
    'hashtag'
  ),
  ('[\u{E9}\\`\\*=>](username:u)', '', '\u{E9}`*=>', '', 'username'),
  ('![\\]\\_](document:5)', '', ']_', '', 'image'),
  ('[\\*\\|](https://a.b)', '', '*|', '', 'link'),
  ('x [\\*\\|](https://a.b) y', 'x ', '*|', ' y', 'link'),
  ('wow\\![\\*\\|](https://a.b)!', 'wow!', '*|', '!', 'link'),
  ('[-!7\u{5D0}\u{E9}](mention:7)', '', '-!7\u{5D0}\u{E9}', '', 'mention'),
  ('[-\u{200F} \\_b~+](hashtag:t)', '', '-\u{200F} _b~+', '', 'hashtag'),
];
