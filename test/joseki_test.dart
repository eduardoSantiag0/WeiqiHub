import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wqhub/board/board_state.dart';
import 'package:wqhub/joseki/joseki.dart';
import 'package:wqhub/symmetry.dart';
import 'package:wqhub/train/variation_tree.dart';
import 'package:wqhub/wq/wq.dart' as wq;

void main() {
  final json = jsonDecode(File('assets/joseki/joseki.json').readAsStringSync())
      as Map<String, dynamic>;
  final categories = [
    for (final c in json['categories'] as List)
      JosekiCategory.fromJson(c as Map<String, dynamic>)
  ];

  /// Flattened leaf categories (a group contributes its children).
  List<JosekiCategory> leaves(Iterable<JosekiCategory> cats) => [
        for (final c in cats)
          if (c.isGroup) ...leaves(c.children) else c,
      ];
  final leafCategories = leaves(categories);
  final allJosekis = [for (final c in leafCategories) ...c.josekis];

  test('asset has the two top-level categories', () {
    expect(categories.map((c) => c.id),
        containsAll(['corner-patterns', 'invasions']));
    expect(allJosekis.length, greaterThan(40));
    for (final c in leafCategories) {
      expect(c.josekis, isNotEmpty, reason: 'empty category ${c.id}');
    }
  });

  test('has an Invasions category from the imported OGS puzzles', () {
    final invasions = categories.where((c) => c.id == 'invasions').toList();
    expect(invasions, hasLength(1));
    expect(invasions.single.josekis.length, greaterThan(10));
    for (final j in invasions.single.josekis) {
      final tree = VariationTree.parse(j.variationTreeSource);
      expect(tree.finalStatus(), VariationStatus.correct,
          reason: '${j.id} has no correct line');
    }
  });

  test('joseki ids are unique and stable-looking', () {
    final ids = [for (final j in allJosekis) j.id];
    expect(ids.toSet().length, ids.length, reason: 'duplicate joseki id');
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[0-9a-z-]+/[0-9a-f]{8}$')),
          reason: 'unexpected id shape: $id');
    }
  });

  for (final category in leafCategories) {
    for (final joseki in category.josekis) {
      test('${joseki.id} "${joseki.title}" is a valid drill', () {
        final tree = VariationTree.parse(joseki.variationTreeSource);

        // Sub-board rectangle covers every stone the drill can put down.
        final (tr, tc) = joseki.topLeft;
        final maxR = tr + joseki.subBoardSize - 1;
        final maxC = tc + joseki.subBoardSize - 1;
        void inBounds(wq.Point p, String what) {
          expect(p.$1 >= tr && p.$1 <= maxR && p.$2 >= tc && p.$2 <= maxC, isTrue,
              reason: '${joseki.id}: $what $p outside sub-board');
        }

        for (final p in joseki.blackStones) {
          inBounds(p, 'black stone');
        }
        for (final p in joseki.whiteStones) {
          inBounds(p, 'white stone');
        }

        // Every root-to-leaf line is legal alternating play and ends on a
        // verdict.
        final board = BoardState(
            size: joseki.boardSize, initialStones: joseki.initialStones);

        void walk(VariationTree node, wq.Color toMove, List<wq.Point> path) {
          if (node.children.isEmpty) {
            expect(node.status, isNotNull,
                reason: '${joseki.id}: leaf without verdict at $path');
            return;
          }
          for (final entry in node.children.entries) {
            final p = entry.key;
            inBounds(p, 'move');
            final captured = board.move((col: toMove, p: p));
            expect(captured, isNotNull,
                reason: '${joseki.id}: illegal move $p at $path');
            walk(entry.value, toMove.opposite, [...path, p]);
            board.undo((col: toMove, p: p), captured!);
          }
        }

        walk(tree, joseki.first, const []);

        // Comment keys must be reachable move paths.
        for (final key in joseki.comments.keys) {
          if (key.isEmpty) continue;
          var cur = tree;
          for (var i = 0; i + 1 < key.length; i += 2) {
            final child = cur.children[wq.parseSgfPoint(key.substring(i, i + 2))];
            expect(child, isNotNull,
                reason: '${joseki.id}: comment key "$key" is not a line');
            if (child == null) break;
            cur = child;
          }
        }

        // The Task adapter must not throw.
        expect(joseki.toTask(0).variationTree, isNotNull);

        // Under every orientation, the re-keyed commentary still lines up with
        // the moves and the swapped-colour drill is still solvable.
        for (final sym in Symmetry.values) {
          final t = joseki.toTask(0).withSymmetry(sym).withSwappedColors();
          final vt = t.variationTree;
          final rekeyed =
              joseki.commentsWithSymmetry(sym, joseki.boardSize);
          expect(rekeyed.length, joseki.comments.length);
          for (final key in rekeyed.keys) {
            if (key.isEmpty) continue;
            var cur = vt;
            var ok = true;
            for (var i = 0; i + 1 < key.length && ok; i += 2) {
              final child =
                  cur.children[wq.parseSgfPoint(key.substring(i, i + 2))];
              if (child == null) {
                ok = false;
              } else {
                cur = child;
              }
            }
            expect(ok, isTrue,
                reason: '${joseki.id} $sym: comment key "$key" off-tree');
          }
          expect(vt.finalStatus(), VariationStatus.correct,
              reason: '${joseki.id} $sym: unsolvable after transform');
        }
      });
    }
  }
}
