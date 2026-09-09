import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wqhub/joseki/joseki_sgf_import.dart';
import 'package:wqhub/train/variation_tree.dart';
import 'package:wqhub/wq/wq.dart' as wq;

void main() {
  test('imports an OGS puzzle SGF into a solvable drill', () {
    final text =
        File('imported-sgf/104488 - Corner Invasion I.sgf').readAsStringSync();
    final joseki =
        josekiFromSgf(text, categoryId: 'user-test', fallbackTitle: 'ignored');

    expect(joseki, isNotNull);
    expect(joseki!.id, matches(RegExp(r'^user-test/[0-9a-f]{8}$')));
    expect(joseki.title, 'Corner Invasion I'); // from GN[], not the fallback
    expect(joseki.first, wq.Color.black); // PL[B]
    expect(joseki.boardSize, 19);

    final tree = VariationTree.parse(joseki.variationTreeSource);
    expect(tree.finalStatus(), VariationStatus.correct);

    // The Task adapter must not throw.
    expect(joseki.toTask(0).variationTree, isNotNull);
  });

  test('keeps every solution branch of a multi-answer puzzle', () {
    final text = File('imported-sgf/99635 - Invasion 3 Space Jump I.sgf')
        .readAsStringSync();
    final joseki = josekiFromSgf(text, categoryId: 'user-test');

    expect(joseki, isNotNull);
    expect(joseki!.boardSize, 13); // SZ[13]
    expect(VariationTree.parse(joseki.variationTreeSource).finalStatus(),
        VariationStatus.correct);
  });

  test('title falls back to the file name when GN[] is missing', () {
    const text = '(;FF[4]GM[1]SZ[19]AW[dd]PL[B];B[cc]C[CORRECT])';
    final joseki = josekiFromSgf(text,
        categoryId: 'user-test',
        fallbackTitle: titleFromFileName('42 - Sneaky Invasion.sgf'));
    expect(joseki?.title, 'Sneaky Invasion');
  });

  test('rejects an SGF with no CORRECT marker', () {
    const text = '(;FF[4]GM[1]SZ[19]AW[dd]PL[B];B[cc];W[dc])';
    expect(josekiFromSgf(text, categoryId: 'user-test'), isNull);
  });

  test('rejects unparseable input', () {
    expect(josekiFromSgf('not an sgf at all', categoryId: 'user-test'), isNull);
  });

  test('same puzzle imported twice gets the same content-derived id', () {
    final text =
        File('imported-sgf/104488 - Corner Invasion I.sgf').readAsStringSync();
    final a = josekiFromSgf(text, categoryId: 'user-test');
    final b = josekiFromSgf(text, categoryId: 'user-test');
    expect(a!.id, b!.id);
  });
}
