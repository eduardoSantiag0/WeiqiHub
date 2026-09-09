import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wqhub/joseki/joseki.dart';
import 'package:wqhub/joseki/joseki_sgf_import.dart';

/// Counts from importing a batch of SGF documents.
class SgfImportResult {
  int imported;
  int skipped;
  final List<String> skippedNames;

  SgfImportResult({
    this.imported = 0,
    this.skipped = 0,
    List<String>? skippedNames,
  }) : skippedNames = skippedNames ?? [];
}

/// User-created joseki categories, imported from SGF at runtime and persisted as
/// a JSON file (`joseki_library.json`, same shape as assets/joseki/joseki.json)
/// in the app documents directory.
///
/// [JosekiDb] holds the bundled read-only collection; this is its writable
/// companion. Its categories are shown in the Joseki tab right after the bundled
/// ones. Listeners (the tab list) are notified on every mutation.
class JosekiLibrary extends ChangeNotifier {
  static final Logger _log = Logger('JosekiLibrary');
  static JosekiLibrary? _instance;

  factory JosekiLibrary() => _instance!;
  JosekiLibrary._(this._file, this._categories);

  final File _file;
  final List<JosekiCategory> _categories;

  /// User categories, in creation order.
  List<JosekiCategory> get categories => List.unmodifiable(_categories);

  bool isUserCategory(String id) => _categories.any((c) => c.id == id);

  JosekiCategory? categoryById(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  static Future<void> init() async {
    assert(_instance == null);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'joseki_library.json'));
    final cats = <JosekiCategory>[];
    if (file.existsSync()) {
      try {
        final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        for (final c in (json['categories'] as List? ?? const [])) {
          cats.add(JosekiCategory.fromJson(c as Map<String, dynamic>));
        }
      } catch (e, st) {
        _log.severe('failed to read joseki library, starting empty', e, st);
      }
    }
    _instance = JosekiLibrary._(file, cats);
  }

  Future<void> _persist() async {
    try {
      await _file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'categories': [for (final c in _categories) c.toJson()],
        }),
      );
    } catch (e, st) {
      _log.severe('failed to persist joseki library', e, st);
      rethrow;
    }
  }

  static String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  String _uniqueId(String title) {
    final slug = _slug(title);
    final base = 'user-${slug.isEmpty ? 'category' : slug}';
    var id = base;
    var n = 2;
    while (_categories.any((c) => c.id == id)) {
      id = '$base-${n++}';
    }
    return id;
  }

  Future<JosekiCategory> createCategory(String title) async {
    final cat = JosekiCategory(
      id: _uniqueId(title),
      title: title.trim(),
      josekis: [],
    );
    _categories.add(cat);
    await _persist();
    notifyListeners();
    return cat;
  }

  Future<void> deleteCategory(String id) async {
    _categories.removeWhere((c) => c.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> renameCategory(String id, String title) async {
    final i = _categories.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _categories[i] = _categories[i].copyWith(title: title.trim());
    await _persist();
    notifyListeners();
  }

  /// Sets the icon of a user category ([iconName] is a key in
  /// joseki_category_icons.dart).
  Future<void> setCategoryIcon(String id, String iconName) async {
    final i = _categories.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _categories[i] = _categories[i].copyWith(iconName: iconName);
    await _persist();
    notifyListeners();
  }

  /// Parses [sgfs] (file name -> file text) and appends the resulting drills to
  /// the category [id], skipping unparseable files and exact-duplicate lines.
  /// Each SGF file may hold several game trees (shared decks pack one joseki
  /// per tree); a `.json` file is read as a joseki deck (joseki.json shape).
  Future<SgfImportResult> addSgfsToCategory(
    String id,
    Iterable<(String, String)> sgfs,
  ) async {
    final index = _categories.indexWhere((c) => c.id == id);
    if (index < 0) return SgfImportResult();
    final cat = _categories[index];

    final josekis = [...cat.josekis];
    final seenTrees = {for (final j in josekis) j.variationTreeSource};
    final result = SgfImportResult();

    for (final (name, text) in sgfs) {
      final parsed = name.toLowerCase().endsWith('.json')
          ? josekisFromDeckJson(text, categoryId: id)
          : josekisFromSgf(
              text,
              categoryId: id,
              fallbackTitle: titleFromFileName(name),
            );
      if (parsed.isEmpty) {
        result.skipped++;
        result.skippedNames.add(name);
        continue;
      }
      for (final joseki in parsed) {
        if (!seenTrees.add(joseki.variationTreeSource)) {
          result.skipped++;
          continue;
        }
        josekis.add(joseki);
        result.imported++;
      }
    }

    _categories[index] = cat.copyWith(josekis: josekis);
    await _persist();
    notifyListeners();
    return result;
  }
}

/// Every [Joseki] in a joseki deck JSON document. Accepts the bundled-asset
/// shape (`{"categories": [...]}`), a single category (`{"josekis": [...]}`) or
/// a bare list of josekis. Ids are re-scoped to [categoryId]. Returns an empty
/// list on any parse error.
List<Joseki> josekisFromDeckJson(String text, {required String categoryId}) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } catch (_) {
    return const [];
  }

  final rawJosekis = <Map<String, dynamic>>[];
  void collectCategory(Map<String, dynamic> c) {
    for (final j in (c['josekis'] as List? ?? const [])) {
      rawJosekis.add(j as Map<String, dynamic>);
    }
    for (final child in (c['children'] as List? ?? const [])) {
      collectCategory(child as Map<String, dynamic>);
    }
  }

  switch (json) {
    case {'categories': final List cats}:
      for (final c in cats) {
        collectCategory(c as Map<String, dynamic>);
      }
    case {'josekis': _}:
      collectCategory(json as Map<String, dynamic>);
    case final List list:
      for (final j in list) {
        rawJosekis.add(j as Map<String, dynamic>);
      }
    default:
      return const [];
  }

  final out = <Joseki>[];
  for (final raw in rawJosekis) {
    try {
      final rawId = raw['id'];
      final suffix = (rawId is String && rawId.contains('/'))
          ? rawId.split('/').last
          : (rawId is String && rawId.isNotEmpty
              ? rawId
              : '${raw['variationTree']}'.hashCode.toUnsigned(32).toRadixString(16));
      out.add(Joseki.fromJson({...raw, 'id': '$categoryId/$suffix'}));
    } catch (_) {
      // skip a malformed entry
    }
  }
  return out;
}
