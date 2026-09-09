// Runtime SGF -> Joseki conversion for user-imported puzzle collections.
//
// This is the in-app counterpart of the "Invasions" path in
// tool/gen_joseki.dart (which does the same thing offline for the bundled
// asset). It targets the ogs-puzzle-exporter format: AB/AW setup stones, PL[]
// to move, and solution line(s) ending on a node whose comment contains
// "CORRECT". Anything without a usable solution line is rejected (returns null).

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:logging/logging.dart';
import 'package:wqhub/joseki/joseki.dart';
import 'package:wqhub/parse/sgf/sgf.dart';
import 'package:wqhub/train/variation_tree.dart';
import 'package:wqhub/wq/wq.dart' as wq;

final _log = Logger('JosekiSgfImport');

/// Max plies kept per solution branch (keeps trees bounded on pathological SGF).
const _invasionMaxDepth = 24;

/// Max branches kept at any node.
const _invasionMaxBranches = 12;

const _maxCommentLen = 600;

final _correctRe = RegExp(r'\bcorrect\b', caseSensitive: false);

/// Parses the first game tree of an SGF document into a drillable [Joseki], or
/// returns `null` if it has no usable solution line (no CORRECT marker, illegal
/// moves, malformed tree). [categoryId] scopes the generated id; [fallbackTitle]
/// is used when the SGF has no `GN` game name.
Joseki? josekiFromSgf(
  String sgfText, {
  required String categoryId,
  String? fallbackTitle,
}) {
  final trees = _parseTrees(sgfText);
  if (trees == null || trees.isEmpty) return null;
  return _josekiFromTree(trees.first,
      categoryId: categoryId, fallbackTitle: fallbackTitle);
}

/// Every drillable [Joseki] in a (possibly multi-game) SGF document - one per
/// game tree. Unusable trees are dropped. Used for shared decks, which pack one
/// joseki per `(;...)` tree.
List<Joseki> josekisFromSgf(
  String sgfText, {
  required String categoryId,
  String? fallbackTitle,
}) {
  final trees = _parseTrees(sgfText);
  if (trees == null) return const [];
  return [
    for (final tree in trees)
      if (_josekiFromTree(tree,
              categoryId: categoryId, fallbackTitle: fallbackTitle)
          case final joseki?)
        joseki,
  ];
}

List<SgfTree>? _parseTrees(String sgfText) {
  try {
    return Sgf.parse(sgfText).trees;
  } catch (e) {
    _log.warning('SGF parse failed: $e');
    return null;
  }
}

Joseki? _josekiFromTree(
  SgfTree gameTree, {
  required String categoryId,
  String? fallbackTitle,
}) {
  if (gameTree.nodes.isEmpty) return null;
  final rootProps = gameTree.nodes.first;
  final root = _buildTree(gameTree);
  if (root.children.isEmpty) return null;

  final boardSize = int.tryParse(rootProps['SZ']?.first ?? '') ?? 19;
  final pl = rootProps['PL']?.first;
  final first = pl == 'W'
      ? wq.Color.white
      : pl == 'B'
          ? wq.Color.black
          : (root.children.values.first.color == 'W'
              ? wq.Color.white
              : wq.Color.black);

  final gn = rootProps['GN']?.first.trim();
  final fb = fallbackTitle?.trim();
  final title = (gn != null && gn.isNotEmpty)
      ? gn
      : (fb != null && fb.isNotEmpty ? fb : 'Untitled');

  final blackStones = <wq.Point>{
    for (final s in root.setup)
      if (s.$1 == 'B') s.$2,
  };
  final whiteStones = <wq.Point>{
    for (final s in root.setup)
      if (s.$1 == 'W') s.$2,
  };

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
    _log.warning('"$title": no usable solution line');
    return null;
  }

  final VariationTree parsed;
  try {
    parsed = VariationTree.parse(tree);
  } catch (e) {
    _log.warning('"$title": variation tree rejected: $e');
    return null;
  }
  if (parsed.finalStatus() != VariationStatus.correct) {
    _log.warning('"$title": no correct line');
    return null;
  }

  final joseki = Joseki(
    id: '$categoryId/${_stableId(blackStones, whiteStones, tree, first)}',
    title: title,
    boardSize: boardSize,
    subBoardSize: boardSize,
    topLeft: const (0, 0),
    first: first,
    blackStones: ISet(blackStones),
    whiteStones: ISet(whiteStones),
    variationTreeSource: tree,
    comments: IMap(comments),
  );

  try {
    joseki.toTask(0); // the Task adapter must not throw
  } catch (e) {
    _log.warning('"$title": Task adapter failed: $e');
    return null;
  }
  return joseki;
}

/// Human-readable title from an SGF file name: drops the extension and a leading
/// "12345 - " numeric prefix (the shape ogs-puzzle-exporter uses).
String titleFromFileName(String fileName) {
  var name = fileName;
  final slash = name.lastIndexOf(RegExp(r'[/\\]'));
  if (slash >= 0) name = name.substring(slash + 1);
  name = name.replaceAll(RegExp(r'\.sgf$', caseSensitive: false), '');
  name = name.replaceAll(RegExp(r'^\d+\s*-\s*'), '');
  return name.trim();
}

/// Content-derived id so favourites survive re-import as long as the position
/// and its line tree are unchanged. FNV-1a, matching tool/gen_joseki.dart.
String _stableId(
  Set<wq.Point> black,
  Set<wq.Point> white,
  String tree,
  wq.Color first,
) {
  final src = [
    ...([for (final p in black) p.toSgf()]..sort()),
    '|',
    ...([for (final p in white) p.toSgf()]..sort()),
    '|',
    tree,
    '|',
    first == wq.Color.black ? 'black' : 'white',
  ].join(',');
  var hash = 0x811c9dc5;
  for (final unit in src.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

// ---------------------------------------------------------------------------
// SGF -> move tree (ported from tool/gen_joseki.dart)
// ---------------------------------------------------------------------------

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
        return; // a pass ends the local line
      }
      final existing = cursor.children[p];
      final child = existing ?? (_MoveNode()..point = p..color = color);
      if (existing == null) cursor.children[p] = child;
      cursor = child;
    }
    final c = node['C']?.first;
    if (c != null && c.trim().isNotEmpty) {
      cursor.comment = cursor.comment == null ? c : '${cursor.comment}\n\n$c';
    }
  }
  for (final child in tree.children) {
    _consume(child, root, cursor);
  }
}

// ---------------------------------------------------------------------------
// Comment cleaning / tree validation (ported from tool/gen_joseki.dart)
// ---------------------------------------------------------------------------

/// [_clean] plus removal of the bare "CORRECT" solution marker.
String? _cleanCorrect(String? raw) {
  if (raw == null) return null;
  final stripped = raw.replaceAll(RegExp(r'\bCORRECT\b'), '').trim();
  return stripped.isEmpty ? null : _clean(stripped);
}

String? _clean(String raw) {
  var s = raw.replaceAll('\r\n', '\n').trim();
  s = s.replaceAll(RegExp(r'^//\s*', multiLine: true), '');
  s = s
      .split('\n')
      .where((l) {
        final t = l.trim();
        if (RegExp(r'^[:\-=*]{4,}$').hasMatch(t)) return false;
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
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  if (s.isEmpty) return null;
  if (s.length > _maxCommentLen) {
    s = '${s.substring(0, _maxCommentLen).trimRight()}…';
  }
  return s;
}

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
