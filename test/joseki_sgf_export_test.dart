import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wqhub/joseki/joseki.dart';
import 'package:wqhub/joseki/joseki_library.dart';
import 'package:wqhub/joseki/joseki_sgf_export.dart';
import 'package:wqhub/joseki/joseki_sgf_import.dart';
import 'package:wqhub/train/variation_tree.dart';

void main() {
  const multiGameSgf = '''
(;FF[4]GM[1]SZ[19]AW[dd]PL[B]GN[First]
;B[cc]C[CORRECT]
;W[dc](;B[cd]C[CORRECT])(;B[bb];W[cb]C[a punished line]))
(;FF[4]GM[1]SZ[13]AW[dd]PL[B]GN[Second]
;B[cc];W[dc];B[cd]C[CORRECT])
''';

  test('a multi-game SGF imports as one joseki per game tree', () {
    final josekis =
        josekisFromSgf(multiGameSgf, categoryId: 'user-test');
    expect(josekis, hasLength(2));
    expect(josekis.map((j) => j.title), ['First', 'Second']);
    expect(josekis[1].boardSize, 13);
    for (final j in josekis) {
      expect(VariationTree.parse(j.variationTreeSource).finalStatus(),
          VariationStatus.correct);
    }
  });

  test('josekiFromSgf still returns only the first game tree', () {
    final j = josekiFromSgf(multiGameSgf, categoryId: 'user-test');
    expect(j?.title, 'First');
  });

  test('a category round-trips through SGF export/import', () {
    final original = josekisFromSgf(multiGameSgf, categoryId: 'user-test');
    final category = JosekiCategory(
        id: 'user-test', title: 'Deck', josekis: original);

    final sgf = josekiCategoryToSgf(category);
    final reimported = josekisFromSgf(sgf, categoryId: 'user-test');

    expect(reimported.map((j) => j.id).toSet(),
        original.map((j) => j.id).toSet());
    for (final j in reimported) {
      expect(VariationTree.parse(j.variationTreeSource).finalStatus(),
          VariationStatus.correct);
    }
  });

  test('a comment containing a bracket survives the SGF round-trip', () {
    final original = josekisFromSgf(
        '(;FF[4]GM[1]SZ[19]AW[dd]PL[B]GN[Brackets]'
        ';B[cc]C[play at the marked point [a\\] then tenuki. CORRECT])',
        categoryId: 'user-test');
    expect(original, hasLength(1));

    final category = JosekiCategory(
        id: 'user-test', title: 'Deck', josekis: original);
    final reimported =
        josekisFromSgf(josekiCategoryToSgf(category), categoryId: 'user-test');
    expect(reimported.single.comments.values.join(), contains('[a]'));
  });

  test('a joseki.json-shaped deck imports through josekisFromDeckJson', () {
    final json = File('assets/joseki/joseki.json').readAsStringSync();
    final josekis = josekisFromDeckJson(json, categoryId: 'user-deck');
    expect(josekis.length, greaterThan(40));
    expect(josekis.every((j) => j.id.startsWith('user-deck/')), isTrue);
    for (final j in josekis) {
      expect(VariationTree.parse(j.variationTreeSource).finalStatus(),
          VariationStatus.correct);
    }
  });
}
