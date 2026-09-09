import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wqhub/joseki/joseki_sgf_import.dart';
import 'package:wqhub/joseki/ogs_puzzle_import.dart';
import 'package:wqhub/train/variation_tree.dart';
import 'package:wqhub/wq/wq.dart' as wq;

// Real responses from https://online-go.com/api/v1/puzzles/<id>, one puzzle
// per solution branch shape. 104479 has a single solution line; 99635 (from
// the same "Invasion Josekis to Learn" collection) has two.
const _singleAnswerPuzzle = r'''
{"id":104479,"name":"Invasion 3 Space Jump II","puzzle":{"name":"Invasion 3 Space Jump II","width":19,"height":19,"initial_state":{"white":"ddcf","black":"fcjcnd"},"puzzle_description":"Invade Black","initial_player":"white","move_tree":{"x":-1,"y":-1,"branches":[{"x":7,"y":2,"branches":[{"x":6,"y":3,"branches":[{"x":7,"y":3,"branches":[{"x":7,"y":4,"branches":[{"x":9,"y":3,"branches":[{"x":10,"y":2,"branches":[{"x":8,"y":4,"branches":[{"x":7,"y":5,"branches":[{"x":9,"y":6,"correct_answer":true}]}]}]}]}]}]}]}]}]}}}
''';

const _multiAnswerPuzzle = r'''
{"id":99635,"name":"Invasion 3 Space Jump I","puzzle":{"name":"Invasion 3 Space Jump I","width":13,"height":13,"initial_state":{"white":"icec","black":""},"puzzle_description":"","initial_player":"black","move_tree":{"x":-1,"y":-1,"text":"Invade white","branches":[{"x":6,"y":2,"branches":[{"x":6,"y":3,"branches":[{"x":5,"y":3,"branches":[{"x":5,"y":2,"branches":[{"x":7,"y":3,"branches":[{"x":6,"y":1,"branches":[{"x":6,"y":4,"branches":[{"x":7,"y":1,"branches":[{"x":7,"y":2,"correct_answer":true}]}]}]}]}]}]}]}]},{"x":7,"y":3,"branches":[{"x":7,"y":2,"branches":[{"x":5,"y":3,"branches":[{"x":6,"y":1,"branches":[{"x":6,"y":4,"branches":[{"x":5,"y":1,"branches":[{"x":5,"y":2,"correct_answer":true}]}]}]}]}]}]}]}}}
''';

void main() {
  group('parseOgsUrl', () {
    test('extracts the id from the site collection URL', () {
      final a = parseOgsUrl('https://online-go.com/puzzle-collection/10859')!;
      expect(a.kind, OgsUrlKind.collection);
      expect(a.id, '10859');

      final b = parseOgsUrl(
          'https://online-go.com/puzzle-collection/10859/invasion-josekis-to-learn')!;
      expect(b.kind, OgsUrlKind.collection);
      expect(b.id, '10859');
    });

    test('extracts the id from the API collection URL', () {
      final ref = parseOgsUrl(
          'https://online-go.com/api/v1/puzzles/collections/10859/puzzles')!;
      expect(ref.kind, OgsUrlKind.collection);
      expect(ref.id, '10859');
    });

    test('accepts a bare id as a collection id', () {
      final ref = parseOgsUrl('10859')!;
      expect(ref.kind, OgsUrlKind.collection);
      expect(ref.id, '10859');
    });

    test('recognises a single puzzle URL, id only', () {
      // What a user actually copies from a puzzle page, e.g. from the
      // "view collection" link.
      final ref = parseOgsUrl(
          'https://online-go.com/puzzle/104994?view-collection=1')!;
      expect(ref.kind, OgsUrlKind.puzzle);
      expect(ref.id, '104994');
    });

    test('recognises the puzzle API URL', () {
      final ref = parseOgsUrl('https://online-go.com/api/v1/puzzles/104994')!;
      expect(ref.kind, OgsUrlKind.puzzle);
      expect(ref.id, '104994');
    });

    test('rejects an unrelated URL', () {
      expect(parseOgsUrl('https://online-go.com/'), isNull);
      expect(parseOgsUrl('not a url'), isNull);
    });
  });

  group('sgfFromOgsPuzzleJson', () {
    test('converts a single-answer puzzle into a solvable drill', () {
      final entry =
          jsonDecode(_singleAnswerPuzzle) as Map<String, dynamic>;
      final sgf = sgfFromOgsPuzzleJson(entry);
      expect(sgf, isNotNull);

      final joseki = josekiFromSgf(sgf!, categoryId: 'user-test');
      expect(joseki, isNotNull);
      expect(joseki!.title, 'Invasion 3 Space Jump II');
      expect(joseki.first, wq.Color.white); // initial_player: white
      expect(joseki.boardSize, 19);
      expect(joseki.blackStones.map((p) => p.toSgf()).toSet(),
          {'fc', 'jc', 'nd'});
      expect(joseki.whiteStones.map((p) => p.toSgf()).toSet(), {'dd', 'cf'});
      expect(VariationTree.parse(joseki.variationTreeSource).finalStatus(),
          VariationStatus.correct);
    });

    test('keeps every solution branch of a multi-answer puzzle', () {
      final entry = jsonDecode(_multiAnswerPuzzle) as Map<String, dynamic>;
      final sgf = sgfFromOgsPuzzleJson(entry);
      expect(sgf, isNotNull);

      final joseki = josekiFromSgf(sgf!, categoryId: 'user-test');
      expect(joseki, isNotNull);
      expect(joseki!.boardSize, 13);
      expect(joseki.first, wq.Color.black); // initial_player: black
      expect(VariationTree.parse(joseki.variationTreeSource).finalStatus(),
          VariationStatus.correct);
    });

    test('returns null for a puzzle with no moves', () {
      final entry = {
        'name': 'Empty',
        'puzzle': {
          'width': 19,
          'initial_state': {'black': '', 'white': ''},
          'initial_player': 'black',
          'move_tree': {'x': -1, 'y': -1, 'branches': <dynamic>[]},
        },
      };
      expect(sgfFromOgsPuzzleJson(entry), isNull);
    });

    test('returns null when there is no puzzle payload', () {
      expect(sgfFromOgsPuzzleJson({'name': 'No puzzle field'}), isNull);
    });
  });

  group('fetchOgsPuzzleCollection', () {
    MockClient buildClient(String collectionId) => MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/v1/puzzles/104994') {
            return http.Response(
                jsonEncode({
                  'id': 104994,
                  'puzzle': {'puzzle_collection': int.parse(collectionId)},
                }),
                200);
          }
          if (path == '/api/v1/puzzles/collections/$collectionId') {
            return http.Response(
                jsonEncode({
                  'id': int.parse(collectionId),
                  'name': 'Invasion Josekis to Learn',
                }),
                200);
          }
          if (path == '/api/v1/puzzles/collections/$collectionId/puzzles') {
            return http.Response('[$_singleAnswerPuzzle]', 200);
          }
          return http.Response('not found', 404);
        });

    test('downloads a collection given its own URL', () async {
      final result = await fetchOgsPuzzleCollection(
        'https://online-go.com/puzzle-collection/10859',
        client: buildClient('10859'),
      );
      expect(result.title, 'Invasion Josekis to Learn');
      expect(result.sgfs, hasLength(1));
      expect(result.sgfs.single.$1, contains('Invasion 3 Space Jump II'));
    });

    test(
        'resolves a single puzzle URL (no collection id in it) to its '
        "puzzle's collection", () async {
      final result = await fetchOgsPuzzleCollection(
        'https://online-go.com/puzzle/104994?view-collection=1',
        client: buildClient('11485'),
      );
      expect(result.sgfs, hasLength(1));
    });

    test('throws for an unrelated URL', () {
      expect(
        () => fetchOgsPuzzleCollection('https://online-go.com/',
            client: MockClient((_) async => http.Response('', 404))),
        throwsA(isA<OgsPuzzleImportException>()),
      );
    });
  });
}
