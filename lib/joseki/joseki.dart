import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wqhub/symmetry.dart';
import 'package:wqhub/train/task.dart';
import 'package:wqhub/train/task_ref.dart';
import 'package:wqhub/train/task_type.dart';
import 'package:wqhub/train/variation_tree.dart';
import 'package:wqhub/wq/rank.dart';
import 'package:wqhub/wq/wq.dart' as wq;

/// A single joseki the learner drills: a corner position plus the tree of
/// book continuations from it. Generated from SGF by tool/gen_joseki.dart.
class Joseki {
  final String id;
  final String title;
  final int boardSize;
  final int subBoardSize;
  final wq.Point topLeft;
  final wq.Color first;
  final ISet<wq.Point> blackStones;
  final ISet<wq.Point> whiteStones;

  /// Serialized [VariationTree] (see lib/train/variation_tree.dart).
  final String variationTreeSource;

  /// Path (concatenated SGF points from the first joseki move) -> commentary.
  final IMap<String, String> comments;

  const Joseki({
    required this.id,
    required this.title,
    required this.boardSize,
    required this.subBoardSize,
    required this.topLeft,
    required this.first,
    required this.blackStones,
    required this.whiteStones,
    required this.variationTreeSource,
    required this.comments,
  });

  IMapOfSets<wq.Color, wq.Point> get initialStones => IMapOfSets({
        wq.Color.black: blackStones,
        wq.Color.white: whiteStones,
      });

  /// [comments] re-keyed so their move paths line up with a board transformed
  /// by [symmetry] (comment keys are concatenated SGF points of the moves so
  /// far). Identity is returned unchanged.
  Map<String, String> commentsWithSymmetry(Symmetry symmetry, int boardSize) {
    final out = <String, String>{};
    for (final e in comments.entries) {
      if (symmetry == Symmetry.identity || e.key.isEmpty) {
        out[e.key] = e.value;
        continue;
      }
      final sb = StringBuffer();
      for (var i = 0; i + 1 < e.key.length; i += 2) {
        final p = wq.parseSgfPoint(e.key.substring(i, i + 2));
        sb.write(symmetry.transformPoint(p, boardSize).toSgf());
      }
      out[sb.toString()] = e.value;
    }
    return out;
  }

  /// Adapts the joseki to a [Task] so it can be driven by the existing
  /// task-solving machinery (TaskSolvingStateMixin). [numericId] only needs to
  /// be locally unique for the share/SGF helpers.
  Task toTask(int numericId) => Task(
        ref: TaskRef(rank: Rank.d1, type: TaskType.joseki, id: numericId),
        first: first,
        boardSize: boardSize,
        subBoardSize: subBoardSize,
        topLeft: topLeft,
        initialStones: initialStones,
        variationTree: VariationTree.parse(variationTreeSource),
        fingerprint: const [],
      );

  /// Inverse of [Joseki.fromJson]; produces the same shape tool/gen_joseki.dart
  /// writes into assets/joseki/joseki.json, so user-imported drills round-trip
  /// through [JosekiLibrary]'s on-disk file.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'boardSize': boardSize,
        'subBoardSize': subBoardSize,
        'topLeft': [topLeft.$1, topLeft.$2],
        'first': first == wq.Color.black ? 'black' : 'white',
        'initialStones': {
          'black': [for (final p in blackStones) p.toSgf()]..sort(),
          'white': [for (final p in whiteStones) p.toSgf()]..sort(),
        },
        'variationTree': variationTreeSource,
        'comments': {for (final e in comments.entries) e.key: e.value},
      };

  factory Joseki.fromJson(Map<String, dynamic> json) {
    final tl = (json['topLeft'] as List).cast<int>();
    return Joseki(
      id: json['id'] as String,
      title: json['title'] as String,
      boardSize: json['boardSize'] as int,
      subBoardSize: json['subBoardSize'] as int,
      topLeft: (tl[0], tl[1]),
      first: json['first'] == 'black' ? wq.Color.black : wq.Color.white,
      blackStones: _points(json['initialStones']['black']),
      whiteStones: _points(json['initialStones']['white']),
      variationTreeSource: json['variationTree'] as String,
      comments: IMap.fromEntries(
        (json['comments'] as Map<String, dynamic>).entries.map(
              (e) => MapEntry(e.key, e.value as String),
            ),
      ),
    );
  }

  static ISet<wq.Point> _points(dynamic list) => ISet(
        (list as List).map((s) => wq.parseSgfPoint(s as String)),
      );
}

class JosekiCategory {
  final String id;
  final String title;

  /// The drills directly in this category (empty for a group).
  final List<Joseki> josekis;

  /// Sub-categories (empty for a leaf category).
  final List<JosekiCategory> children;

  /// Icon key for a user category (see joseki_category_icons.dart). `null` for
  /// bundled categories, which pick their icon from [id].
  final String? iconName;

  const JosekiCategory({
    required this.id,
    required this.title,
    required this.josekis,
    this.children = const [],
    this.iconName,
  });

  JosekiCategory copyWith({
    String? title,
    List<Joseki>? josekis,
    List<JosekiCategory>? children,
    String? iconName,
  }) =>
      JosekiCategory(
        id: id,
        title: title ?? this.title,
        josekis: josekis ?? this.josekis,
        children: children ?? this.children,
        iconName: iconName ?? this.iconName,
      );

  bool get isGroup => children.isNotEmpty;

  /// Every drill in this category and its sub-categories.
  Iterable<Joseki> get allJosekis =>
      children.isEmpty ? josekis : children.expand((c) => c.allJosekis);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (iconName != null) 'icon': iconName,
        'josekis': [for (final j in josekis) j.toJson()],
        if (children.isNotEmpty)
          'children': [for (final c in children) c.toJson()],
      };

  factory JosekiCategory.fromJson(Map<String, dynamic> json) => JosekiCategory(
        id: json['id'] as String,
        title: json['title'] as String,
        iconName: json['icon'] as String?,
        josekis: [
          for (final j in json['josekis'] as List)
            Joseki.fromJson(j as Map<String, dynamic>)
        ],
        children: [
          for (final c in (json['children'] as List?) ?? const [])
            JosekiCategory.fromJson(c as Map<String, dynamic>)
        ],
      );
}
