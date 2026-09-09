// Serializes a joseki category back to SGF so a learner can share a deck.
//
// The output is a multi-game SGF (one `(;...)` game tree per joseki) in the
// same shape [josekiFromSgf] reads: AB/AW setup, PL[] to move, and every
// solution leaf carrying "CORRECT" in its comment. Non-solution leaves (the
// refutation lines) are written without the marker, so they re-import as wrong
// branches.
//
// Intended for user categories (full-board drills); bundled corner patterns use
// a cropped sub-board that this format does not carry.

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wqhub/joseki/joseki.dart';
import 'package:wqhub/train/variation_tree.dart';
import 'package:wqhub/wq/wq.dart' as wq;

/// Multi-game SGF for every drill in [category] and its sub-categories.
String josekiCategoryToSgf(JosekiCategory category) {
  final buf = StringBuffer();
  for (final joseki in category.allJosekis) {
    buf.writeln(josekiToSgf(joseki));
  }
  return buf.toString();
}

/// A single `(;...)` SGF game tree for one drill.
String josekiToSgf(Joseki joseki) {
  final tree = VariationTree.parse(joseki.variationTreeSource);

  final buf = StringBuffer('(;FF[4]GM[1]CA[UTF-8]SZ[${joseki.boardSize}]');
  buf.write('PL[${joseki.first == wq.Color.black ? 'B' : 'W'}]');
  buf.write('GN[${_escape(joseki.title)}]');

  final ab = [for (final p in joseki.blackStones) p.toSgf()]..sort();
  final aw = [for (final p in joseki.whiteStones) p.toSgf()]..sort();
  if (ab.isNotEmpty) buf.write('AB${ab.map((p) => '[$p]').join()}');
  if (aw.isNotEmpty) buf.write('AW${aw.map((p) => '[$p]').join()}');

  final rootComment = joseki.comments[''];
  if (rootComment != null && rootComment.isNotEmpty) {
    buf.write('C[${_escape(rootComment)}]');
  }

  _writeContinuation(buf, tree, joseki.first, '', joseki.comments);
  buf.write(')');
  return buf.toString();
}

void _writeContinuation(
  StringBuffer buf,
  VariationTree node,
  wq.Color toMove,
  String path,
  IMap<String, String> comments,
) {
  final entries = node.children.entries.toList();
  if (entries.isEmpty) return;
  if (entries.length == 1) {
    final e = entries.first;
    _writeMoveNode(buf, e.key, e.value, toMove, path + e.key.toSgf(), comments);
  } else {
    for (final e in entries) {
      buf.write('(');
      _writeMoveNode(
          buf, e.key, e.value, toMove, path + e.key.toSgf(), comments);
      buf.write(')');
    }
  }
}

void _writeMoveNode(
  StringBuffer buf,
  wq.Point p,
  VariationTree child,
  wq.Color color,
  String path,
  IMap<String, String> comments,
) {
  buf.write(';${color == wq.Color.black ? 'B' : 'W'}[${p.toSgf()}]');

  final parts = <String>[];
  final c = comments[path];
  if (c != null && c.isNotEmpty) parts.add(c);
  if (child.status == VariationStatus.correct) parts.add('CORRECT');
  if (parts.isNotEmpty) buf.write('C[${_escape(parts.join('\n\n'))}]');

  _writeContinuation(buf, child, color.opposite, path, comments);
}

/// Escapes `]` inside a property value. The SGF parser ([Sgf.parse]) unescapes
/// `\]` back to `]` and leaves every other backslash untouched, so escaping just
/// this one character round-trips.
String _escape(String s) => s.replaceAll(']', '\\]');
