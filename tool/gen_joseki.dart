// Generates assets/joseki/joseki.json from the SGF joseki collections in
// tool/joseki_src/. Run from the repo root:
//
//   dart run tool/gen_joseki.dart
//
// Source SGFs (build input only, not shipped in the app bundle):
//   * tool/joseki_src/1-dan-joseki-essentials.sgf - curated, commented (4-4, 3-4)
//   * tool/joseki_src/kogos-joseki-dictionary.sgf - Kogo's Joseki Dictionary
//     (both from github.com/benjaminmantle/baduk-study-material/05-joseki)
//   * imported-sgf/*.sgf - an OGS puzzle collection, becomes the "Invasions"
//     category (ogs-puzzle-exporter format: AB/AW setup, PL[] to move, the
//     solution line(s) end on a node commented "CORRECT").
//
// The output feeds lib/joseki/: each category is a corner point, each joseki
// is one line the learner drills with the existing task-solving machinery
// (VariationTree / TaskSolvingStateMixin).

import 'dart:convert';
import 'dart:io';

import 'package:wqhub/parse/sgf/sgf.dart';
import 'package:wqhub/wq/wq.dart' as wq;

/// Max plies kept in a joseki variation tree (keeps the asset small and the
/// lines memorable - Kogo goes 30+ moves deep in places).
const maxDepth = 14;

/// Max branches kept at any node. SGF writes the main lines first, so keeping
/// the first few drops only obscure side variations.
const maxBranches = 8;

/// Max book mistakes kept per position, each as a shallow refutation line (the
/// mistake move, the strongest reply, then a wrong verdict). The dictionary
/// flags these to warn against them; the trainer plays the punishment so the
/// learner sees why the move fails instead of a bare "wrong".
const maxRefutations = 3;

/// A move farther than this from the corner (in either direction) is treated
/// as tenuki and ends the local line.
const cornerReach = 11;

const maxCommentLen = 600;

/// A node whose comment matches this is a deviation / trick play / mistake the
/// dictionary keeps only to refute. We drop those subtrees so the trainer sticks
/// to real joseki (scoring genuine deviations is left to a later pass).
final _mistakeRe = RegExp(
    r'\b(mistake|overplay|trick play|not joseki|refuted|is an error|does ?n.?t work|does not work)\b',
    caseSensitive: false);

bool _mistakeFlagged(_MoveNode n) =>
    n.comment != null && _mistakeRe.hasMatch(n.comment!);

const _pointTypeTitles = {
  '3-3': '3-3 point (san-san)',
  '3-4': '3-4 point (komoku)',
  '4-4': '4-4 point (hoshi)',
  '5-3': '5-3 point (mokuhazushi)',
  '5-4': '5-4 point (takamoku)',
  '5-5': '5-5 point (go-no-go)',
  '6-3': '6-3 point (dai-mokuhazushi)',
  '6-4': '6-4 point (dai-takamoku)',
};

/// Corner-point sub-categories, in display order, grouped under "Corner
/// Patterns" in the output.
const _cornerOrder = ['4-4', '3-4', '3-3', '5-3', '5-4', '5-5', '6-3', '6-4'];

void main() {
  final categories = <String, _Category>{};

  for (final src in const [
    'tool/joseki_src/1-dan-joseki-essentials.sgf',
    'tool/joseki_src/kogos-joseki-dictionary.sgf',
  ]) {
    final sgf = Sgf.parse(File(src).readAsStringSync());
    final root = _buildTree(sgf.trees.first);
    for (final entry in root.children.entries) {
      final categoryNode = entry.value;
      final id = _classifyCorner(entry.key);
      if (id == null) continue;
      final category = categories.putIfAbsent(
          id, () => _Category(id, _pointTypeTitles[id] ?? '$id point'));
      _extractCategory(categoryNode, category);
    }
  }

  _processInvasions(categories);

  Map<String, dynamic> leaf(_Category c) => {
        'id': c.id,
        'title': c.title,
        'josekis': [
          for (final j in c.josekis) (j..['id'] = '${c.id}/${_stableId(j)}'),
        ],
      };

  final cornerCats = [
    for (final id in _cornerOrder)
      if (categories[id]?.josekis.isNotEmpty ?? false) categories[id]!,
  ];

  final out = {
    'categories': [
      if (categories['invasions']?.josekis.isNotEmpty ?? false)
        leaf(categories['invasions']!),
      {
        'id': 'corner-patterns',
        'title': 'Corner Patterns',
        'josekis': const <dynamic>[],
        'children': [for (final c in cornerCats) leaf(c)],
      },
    ],
  };

  final josekiCount = cornerCats.fold<int>(0, (n, c) => n + c.josekis.length) +
      (categories['invasions']?.josekis.length ?? 0);

  final file = File('assets/joseki/joseki.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));

  stdout.writeln('Wrote ${file.path}');
  stdout.writeln(
      '${cornerCats.length} corner sub-categories + Invasions, '
      '$josekiCount josekis, ${(file.lengthSync() / 1024).toStringAsFixed(1)} KB');
}

/// Content-derived id so favourites survive regeneration as long as the
/// position and its line tree are unchanged. FNV-1a over the defining stones
/// and the serialized variation tree.
String _stableId(Map<String, dynamic> joseki) {
  final stones = joseki['initialStones'] as Map<String, dynamic>;
  final src = [
    ...(stones['black'] as List),
    '|',
    ...(stones['white'] as List),
    '|',
    joseki['variationTree'],
    '|',
    '${joseki['first']}',
  ].join(',');
  var hash = 0x811c9dc5;
  for (final unit in src.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

// --------------------------------------------------------------------------
// Invasions category (OGS puzzle collection in imported-sgf/)
// --------------------------------------------------------------------------

const _invasionMaxDepth = 24;
const _invasionMaxBranches = 12;
final _correctRe = RegExp(r'\bcorrect\b', caseSensitive: false);

void _processInvasions(Map<String, _Category> categories) {
  final dir = Directory('imported-sgf');
  if (!dir.existsSync()) {
    stderr.writeln('  (no imported-sgf/ directory - skipping Invasions)');
    return;
  }
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.sgf'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final category = categories.putIfAbsent(
      'invasions', () => _Category('invasions', 'Invasions'));

  for (final file in files) {
    final joseki = _buildInvasion(file, category);
    if (joseki == null) continue;
    if (!category._seen.add(joseki['variationTree'] as String)) continue;
    category.josekis.add(joseki);
  }
}

Map<String, dynamic>? _buildInvasion(File file, _Category category) {
  final Sgf sgf;
  try {
    sgf = Sgf.parse(file.readAsStringSync());
  } catch (e) {
    stderr.writeln('  ! ${file.path}: parse failed ($e)');
    return null;
  }
  final gameTree = sgf.trees.first;
  final rootProps = gameTree.nodes.first;
  final root = _buildTree(gameTree);
  if (root.children.isEmpty) return null;

  final boardSize = int.tryParse(rootProps['SZ']?.first ?? '') ?? 19;
  final pl = rootProps['PL']?.first;
  final first = pl == 'W'
      ? 'white'
      : pl == 'B'
          ? 'black'
          : (root.children.values.first.color == 'W' ? 'white' : 'black');

  final title = (rootProps['GN']?.first.trim().isNotEmpty ?? false)
      ? rootProps['GN']!.first.trim()
      : _invasionTitleFromFilename(file);

  final black = [
    for (final s in root.setup)
      if (s.$1 == 'B') s.$2.toSgf(),
  ]..sort();
  final white = [
    for (final s in root.setup)
      if (s.$1 == 'W') s.$2.toSgf(),
  ]..sort();

  final comments = <String, String>{};
  final rootComment = _cleanCorrect(root.comment);
  if (rootComment != null) comments[''] = rootComment;

  var maxPlies = 0;

  String tailComments(_MoveNode node) {
    final parts = <String>[];
    var cur = node;
    while (true) {
      final c = _cleanCorrect(cur.comment);
      if (c != null) parts.add(c);
      if (cur.children.length != 1) break;
      cur = cur.children.values.first;
    }
    return parts.join('\n\n');
  }

  String serialize(_MoveNode node, String path, int depth) {
    if (node.comment != null && _correctRe.hasMatch(node.comment!)) {
      final c = tailComments(node);
      if (c.isNotEmpty) comments[path] = c;
      if (depth > maxPlies) maxPlies = depth;
      return '0'; // solution reached
    }
    final c = _cleanCorrect(node.comment);
    if (c != null) comments[path] = c;

    final kids = node.children.values.take(_invasionMaxBranches).toList();
    if (depth >= _invasionMaxDepth || kids.isEmpty) {
      if (depth > maxPlies) maxPlies = depth;
      return '1'; // dead end that never reached "CORRECT"
    }
    final buf = StringBuffer();
    for (final kid in kids) {
      buf.write(kid.point!.toSgf());
      buf.write(serialize(kid, '$path${kid.point!.toSgf()}', depth + 1));
    }
    buf.write('<');
    return buf.toString();
  }

  final buf = StringBuffer();
  for (final kid in root.children.values.take(_invasionMaxBranches)) {
    buf.write(kid.point!.toSgf());
    buf.write(serialize(kid, kid.point!.toSgf(), 1));
  }
  buf.write('<');
  final tree = buf.toString();

  if (maxPlies < 1 || !_validSerialized(tree)) {
    stderr.writeln('  ! ${file.path}: unusable tree');
    return null;
  }

  return {
    'id': '',
    'title': title,
    'boardSize': boardSize,
    'subBoardSize': boardSize,
    'topLeft': [0, 0],
    'first': first,
    'initialStones': {'black': black, 'white': white},
    'variationTree': tree,
    'comments': comments,
  };
}

String _invasionTitleFromFilename(File file) {
  var name = file.uri.pathSegments.last;
  name = name.replaceAll(RegExp(r'\.sgf$', caseSensitive: false), '');
  name = name.replaceAll(RegExp(r'^\d+\s*-\s*'), '');
  return name.trim();
}

/// [_clean] plus removal of the bare "CORRECT" solution marker.
String? _cleanCorrect(String? raw) {
  if (raw == null) return null;
  final stripped = raw.replaceAll(RegExp(r'\bCORRECT\b'), '').trim();
  return stripped.isEmpty ? null : _clean(stripped);
}

// --------------------------------------------------------------------------
// SGF -> move tree
// --------------------------------------------------------------------------

class _MoveNode {
  wq.Point? point;
  String? color; // 'B' | 'W'
  String? comment;
  final children = <wq.Point, _MoveNode>{};
  final setup = <(String, wq.Point)>[]; // root only (AB/AW)
}

_MoveNode _buildTree(SgfTree tree) {
  final root = _MoveNode();
  _consume(tree, root, root);
  return root;
}

void _consume(SgfTree tree, _MoveNode root, _MoveNode cursor) {
  for (final node in tree.nodes) {
    for (final (prop, color) in const [('AB', 'B'), ('AW', 'W')]) {
      for (final v in node[prop] ?? const <String>[]) {
        final p = wq.parseSgfPoint(v);
        if (p != const (-1, -1)) root.setup.add((color, p));
      }
    }
    final color = node.containsKey('B')
        ? 'B'
        : node.containsKey('W')
            ? 'W'
            : null;
    if (color != null) {
      final raw = node[color]!.first;
      final p = wq.parseSgfPoint(raw);
      if (p == const (-1, -1)) {
        // A pass ends the local line.
        return;
      }
      final existing = cursor.children[p];
      final child = existing ?? (_MoveNode()..point = p..color = color);
      if (existing == null) cursor.children[p] = child;
      cursor = child;
    }
    final c = node['C']?.first;
    if (c != null && c.trim().isNotEmpty) {
      cursor.comment =
          cursor.comment == null ? c : '${cursor.comment}\n\n$c';
    }
  }
  for (final child in tree.children) {
    _consume(child, root, cursor);
  }
}

// --------------------------------------------------------------------------
// Corner classification / geometry (everything normalised to the upper-right
// corner, which is what both source files use).
// --------------------------------------------------------------------------

const _boardSize = 19;

int _lineFromTop(wq.Point p) => p.$1;
int _lineFromRight(wq.Point p) => _boardSize - 1 - p.$2;

/// Distance from the nearest corner along each axis, as an unordered pair like
/// '4-4'. Returns null if the point is not a recognised corner opening.
String? _classifyCorner(wq.Point p) {
  final r = p.$1 <= _boardSize ~/ 2 ? p.$1 : _boardSize - 1 - p.$1;
  final c = p.$2 <= _boardSize ~/ 2 ? p.$2 : _boardSize - 1 - p.$2;
  final lo = (r < c ? r : c) + 1;
  final hi = (r < c ? c : r) + 1;
  if (lo < 3 || hi > 6) return null;
  // Conventional Go names put the larger number first once it reaches 5
  // (mokuhazushi 5-3, takamoku 5-4, dai-takamoku 6-4, …); 3-3, 3-4 and 4-4
  // keep the ascending form.
  return hi >= 5 ? '$hi-$lo' : '$lo-$hi';
}

bool _inCorner(wq.Point p) =>
    _lineFromTop(p) <= cornerReach && _lineFromRight(p) <= cornerReach;

// --------------------------------------------------------------------------
// Category -> josekis
// --------------------------------------------------------------------------

class _Category {
  _Category(this.id, this.title);
  final String id;
  final String title;
  final List<Map<String, dynamic>> josekis = [];
  final _seen = <String>{};
}

void _extractCategory(_MoveNode categoryNode, _Category category) {
  // Walk the forced run from the category-defining move to the first real
  // branch, accumulating setup stones.
  final setup = <(String, wq.Point)>[
    (categoryNode.color!, categoryNode.point!),
  ];
  final headerComments = <String>[];
  void addHeader(String? raw) {
    if (raw == null) return;
    final c = _clean(raw);
    if (c != null) headerComments.add(c);
  }

  addHeader(categoryNode.comment);
  var node = categoryNode;
  while (node.children.length == 1) {
    node = node.children.values.first;
    if (!_inCorner(node.point!)) return;
    setup.add((node.color!, node.point!));
    addHeader(node.comment);
  }
  if (node.children.isEmpty) return;

  final branches = node.children.values
      .where((c) => _inCorner(c.point!) && !_mistakeFlagged(c))
      .take(maxBranches)
      .toList();

  for (final defining in branches) {
    final joseki = _buildJoseki(
      category: category,
      setup: setup,
      header: headerComments.join('\n\n'),
      defining: defining,
    );
    if (joseki == null) continue;
    final fingerprint = joseki['variationTree'] as String;
    if (!category._seen.add('${_stonesKey(setup)}|$fingerprint')) continue;
    category.josekis.add(joseki);
  }
}

String _stonesKey(List<(String, wq.Point)> setup) =>
    (setup.map((s) => '${s.$1}${s.$2.toSgf()}').toList()..sort()).join();

Map<String, dynamic>? _buildJoseki({
  required _Category category,
  required List<(String, wq.Point)> setup,
  required String header,
  required _MoveNode defining,
}) {
  final comments = <String, String>{};
  if (header.isNotEmpty) comments[''] = header;

  final points = <wq.Point>{
    for (final s in setup) s.$2,
  };
  var maxPlies = 0;

  String serialize(_MoveNode node, String path, int depth) {
    final here = node.comment == null ? null : _clean(node.comment!);
    if (here != null) comments[path] = here;

    final inCorner =
        node.children.values.where((c) => _inCorner(c.point!)).toList();
    final kids =
        inCorner.where((c) => !_mistakeFlagged(c)).take(maxBranches).toList();
    if (depth >= maxDepth || kids.isEmpty) {
      if (depth > maxPlies) maxPlies = depth;
      return '0';
    }
    // Book mistakes by the side the learner plays: kept as refutation lines the
    // trainer punishes. Mistakes by the other side are dropped - the opponent's
    // replies are auto-generated and must stay in-book.
    final mistakes = inCorner
        .where((c) => _mistakeFlagged(c) && c.color == defining.color)
        .take(maxRefutations)
        .toList();

    final buf = StringBuffer();
    for (final kid in kids) {
      points.add(kid.point!);
      buf.write(kid.point!.toSgf());
      buf.write(serialize(kid, '$path${kid.point!.toSgf()}', depth + 1));
    }
    for (final mistake in mistakes) {
      final edge = _refutation(
          mistake, '$path${mistake.point!.toSgf()}', points, comments);
      if (edge == null) continue;
      points.add(mistake.point!);
      buf.write(mistake.point!.toSgf());
      buf.write(edge);
      if (depth + 1 > maxPlies) maxPlies = depth + 1;
    }
    buf.write('<');
    return buf.toString();
  }

  points.add(defining.point!);
  final tree =
      '${defining.point!.toSgf()}${serialize(defining, defining.point!.toSgf(), 1)}<';
  if (maxPlies < 2) return null;

  // Sanity-check the serialized form against the VariationTree grammar
  // (the real parser is exercised by test/joseki_test.dart under flutter test).
  if (!_validSerialized(tree)) {
    stderr.writeln('  ! ${category.id}: malformed tree: $tree');
    return null;
  }

  // Sub-board: smallest corner-anchored square covering every point, padded.
  var size = 0;
  for (final p in points) {
    final reach = _lineFromTop(p) > _lineFromRight(p)
        ? _lineFromTop(p)
        : _lineFromRight(p);
    if (reach + 1 > size) size = reach + 1;
  }
  size = (size + 1).clamp(9, 13);
  final topLeft = (0, _boardSize - size);

  final black = [
    for (final s in setup)
      if (s.$1 == 'B') s.$2.toSgf(),
  ]..sort();
  final white = [
    for (final s in setup)
      if (s.$1 == 'W') s.$2.toSgf(),
  ]..sort();

  return {
    'id': '', // filled in by caller
    'title': _title(setup, defining),
    'boardSize': _boardSize,
    'subBoardSize': size,
    'topLeft': [topLeft.$1, topLeft.$2],
    'first': defining.color == 'B' ? 'black' : 'white',
    'initialStones': {'black': black, 'white': white},
    'variationTree': tree,
    'comments': comments,
  };
}

/// Serializes a book mistake as a shallow refutation: the strongest in-corner
/// reply then a wrong-verdict leaf (`<reply>1<`), or a bare wrong leaf (`1`)
/// when the source has no reply but does explain the mistake. Returns `null`
/// when there is nothing to teach beyond "off book" (no reply, no comment), in
/// which case the caller drops the move. Comments met along the way are keyed
/// into [comments]; every point reached is added to [points].
String? _refutation(
  _MoveNode mistake,
  String path,
  Set<wq.Point> points,
  Map<String, String> comments,
) {
  final mistakeComment =
      mistake.comment == null ? null : _clean(mistake.comment!);
  if (mistakeComment != null) comments[path] = mistakeComment;

  _MoveNode? reply;
  for (final c in mistake.children.values) {
    if (_inCorner(c.point!)) {
      reply = c;
      break;
    }
  }
  if (reply == null) return mistakeComment != null ? '1' : null;

  final replyComment = reply.comment == null ? null : _clean(reply.comment!);
  if (replyComment != null) {
    comments['$path${reply.point!.toSgf()}'] = replyComment;
  }
  points.add(reply.point!);
  return '${reply.point!.toSgf()}1<';
}

// --------------------------------------------------------------------------
// Titles
// --------------------------------------------------------------------------

String _goCoord(wq.Point p) {
  const cols = 'ABCDEFGHJKLMNOPQRST';
  return '${cols[p.$2]}${_boardSize - p.$1}';
}

String _title(List<(String, wq.Point)> setup, _MoveNode defining) {
  final corner = setup.first.$2; // the point-defining stone
  final approach = setup.length > 1 ? setup[1].$2 : null;
  final d = defining.point!;

  final descr = <String>[];

  // Direction of the defining move relative to what's already down.
  final ref = approach ?? corner;
  final dr = _lineFromTop(d) - _lineFromTop(ref);
  final dc = _lineFromRight(d) - _lineFromRight(ref);
  final dist = dr.abs() + dc.abs();

  final line = _lineFromTop(d) < _lineFromRight(d)
      ? _lineFromTop(d) + 1
      : _lineFromRight(d) + 1;

  String label;
  if (approach == null) {
    // Defining move is White's approach to the corner stone.
    if (dist <= 1) {
      label = 'attachment';
    } else if (line <= 3) {
      label = 'low approach';
    } else if (line == 4) {
      label = 'high approach';
    } else {
      label = 'approach';
    }
  } else {
    if (dist <= 1) {
      label = 'attachment';
    } else if (dist == 2 && (dr == 0 || dc == 0)) {
      label = line <= 3 ? 'one-space low pincer' : 'one-space high pincer';
    } else if (dist == 3 && (dr == 0 || dc == 0)) {
      label = line <= 3 ? 'two-space low pincer' : 'two-space high pincer';
    } else if (dist == 3) {
      label = 'knight\'s-move pincer';
    } else if (_lineFromTop(d) >= 4 && _lineFromRight(d) >= 4) {
      label = 'jump';
    } else if (line <= 3 && _lineFromRight(d) <= 3) {
      label = '3-3 point';
    } else {
      label = 'response';
    }
  }
  descr.add(label);

  return '${_capitalize(descr.join(', '))} (${_goCoord(d)})';
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

// --------------------------------------------------------------------------
// Comment cleaning
// --------------------------------------------------------------------------

/// Mirrors the `_VariationTreeDefinition` grammar in
/// lib/train/variation_tree.dart: a node is either a status leaf (`0`/`1`) or a
/// run of `<2-letter-point><node>` edges terminated by `<`.
bool _validSerialized(String s) {
  var i = 0;
  bool isLower(String c) => c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7a;
  bool node() {
    if (i >= s.length) return false;
    final ch = s[i];
    if (ch == '0' || ch == '1') {
      i++;
      return true;
    }
    while (i < s.length && s[i] != '<') {
      if (i + 2 > s.length || !isLower(s[i]) || !isLower(s[i + 1])) return false;
      i += 2;
      if (!node()) return false;
    }
    if (i >= s.length || s[i] != '<') return false;
    i++;
    return true;
  }

  return node() && i == s.length;
}

String? _clean(String raw) {
  var s = raw.replaceAll('\r\n', '\n').trim();
  // Drop the leading "// " the essentials file uses for annotations.
  s = s.replaceAll(RegExp(r'^//\s*', multiLine: true), '');
  // Drop the ":::::" separator rules and the CJK header blocks.
  s = s
      .split('\n')
      .where((l) {
        final t = l.trim();
        if (RegExp(r'^[:\-=*]{4,}$').hasMatch(t)) return false; // rule lines
        // ALL-CAPS heading lines ("4-4 (STAR POINT) ESSENTIAL JOSEKI").
        final letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
        if (letters.length > 6 &&
            letters == letters.toUpperCase() &&
            t.length < 60) {
          return false;
        }
        return true;
      })
      .join('\n')
      .trim();
  // Collapse 3+ blank lines.
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  if (s.isEmpty) return null;
  if (s.length > maxCommentLen) {
    s = '${s.substring(0, maxCommentLen).trimRight()}…';
  }
  return s;
}
