// Downloads an OGS puzzle collection (given its site URL, e.g.
// https://online-go.com/puzzle-collection/10859/some-name, or the URL of any
// one puzzle in it) and converts every puzzle it contains into the same
// ogs-puzzle-exporter SGF shape that joseki_sgf_import.dart already parses
// (AB/AW setup, PL[] to move, solution line(s) ending on a node commented
// "CORRECT"). This lets a user create a joseki category from just a URL
// instead of exporting SGFs by hand with that external tool first.
//
// OGS puzzles aren't stored as SGF server-side; the collection's "puzzles"
// endpoint already returns each puzzle's full JSON (initial_state, a
// move_tree of {x,y,branches,correct_answer} nodes), so this builds the SGF
// text itself rather than asking the server for one.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:wqhub/wq/wq.dart' as wq;

final _log = Logger('OgsPuzzleImport');

const _defaultOrigin = 'https://online-go.com';
const _userAgent = 'WeiqiHub/1.0';

class OgsPuzzleImportException implements Exception {
  final String message;
  const OgsPuzzleImportException(this.message);
  @override
  String toString() => message;
}

/// A downloaded collection, ready for [JosekiLibrary.addSgfsToCategory].
class OgsPuzzleCollection {
  final String title;
  final List<(String, String)> sgfs; // (file name, SGF text)

  const OgsPuzzleCollection({required this.title, required this.sgfs});
}

enum OgsUrlKind {
  /// A puzzle collection, e.g. `/puzzle-collection/<id>`.
  collection,

  /// A single puzzle, e.g. `/puzzle/<id>`. Its collection isn't in the URL
  /// and has to be looked up from the puzzle itself.
  puzzle,
}

class OgsUrlRef {
  final OgsUrlKind kind;
  final String id;
  const OgsUrlRef(this.kind, this.id);
}

/// Parses an OGS puzzle collection URL, a single OGS puzzle URL (e.g. one
/// copied from a puzzle page, `.../puzzle/104994?view-collection=1`), or a
/// bare id, or returns `null` if [input] doesn't look like any of those. A
/// puzzle reference still needs its collection id looked up server-side (see
/// [fetchOgsPuzzleCollection]) since the puzzle URL doesn't carry it.
OgsUrlRef? parseOgsUrl(String input) {
  final trimmed = input.trim();
  if (RegExp(r'^\d+$').hasMatch(trimmed)) {
    return OgsUrlRef(OgsUrlKind.collection, trimmed);
  }

  final Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } catch (_) {
    return null;
  }
  final segments = uri.pathSegments;

  String? idAfterAny(Set<String> names) {
    for (var i = 0; i < segments.length; i++) {
      if (names.contains(segments[i].toLowerCase()) &&
          i + 1 < segments.length &&
          RegExp(r'^\d+$').hasMatch(segments[i + 1])) {
        return segments[i + 1];
      }
    }
    return null;
  }

  final collectionId = idAfterAny(
      {'puzzle-collection', 'puzzle-collections', 'collection', 'collections'});
  if (collectionId != null) return OgsUrlRef(OgsUrlKind.collection, collectionId);

  final puzzleId = idAfterAny({'puzzle', 'puzzles'});
  if (puzzleId != null) return OgsUrlRef(OgsUrlKind.puzzle, puzzleId);

  for (final s in segments.reversed) {
    if (RegExp(r'^\d+$').hasMatch(s)) return OgsUrlRef(OgsUrlKind.collection, s);
  }
  return null;
}

String _originFromUrl(String input) {
  try {
    final uri = Uri.parse(input.trim());
    if (uri.hasScheme && uri.host.isNotEmpty) return uri.origin;
  } catch (_) {
    // fall through
  }
  return _defaultOrigin;
}

/// Downloads every puzzle in the collection referenced by [url] and converts
/// each one to SGF. [url] may be a collection URL or a single puzzle's URL
/// (its collection is then looked up from the puzzle itself, since the URL
/// doesn't carry it - e.g. `.../puzzle/104994?view-collection=1`). Throws
/// [OgsPuzzleImportException] if [url] isn't recognised, the request fails, or
/// the collection has no drillable puzzle.
Future<OgsPuzzleCollection> fetchOgsPuzzleCollection(
  String url, {
  http.Client? client,
}) async {
  final ref = parseOgsUrl(url);
  if (ref == null) {
    throw const OgsPuzzleImportException(
        'Not an OGS puzzle or puzzle collection URL');
  }
  final origin = _originFromUrl(url);
  final ownClient = client == null;
  final http.Client c = client ?? http.Client();
  try {
    final String id;
    if (ref.kind == OgsUrlKind.collection) {
      id = ref.id;
    } else {
      final puzzle =
          await _getJson(c, Uri.parse('$origin/api/v1/puzzles/${ref.id}'));
      final puzzleData = puzzle['puzzle'];
      final collectionId =
          puzzleData is Map ? puzzleData['puzzle_collection'] : null;
      if (collectionId == null) {
        throw const OgsPuzzleImportException(
            "That puzzle isn't part of a collection");
      }
      id = '$collectionId';
    }

    final collection =
        await _getJson(c, Uri.parse('$origin/api/v1/puzzles/collections/$id'));
    final puzzles = await _fetchAllPuzzles(c, origin, id);

    final sgfs = <(String, String)>[];
    for (final entry in puzzles) {
      final sgf = sgfFromOgsPuzzleJson(entry);
      if (sgf == null) continue;
      final puzzleId = entry['id'];
      final name = (entry['name'] as String?)?.trim();
      final label = (name == null || name.isEmpty) ? 'Puzzle' : name;
      sgfs.add(('${puzzleId ?? sgfs.length} - $label.sgf', sgf));
    }
    if (sgfs.isEmpty) {
      throw const OgsPuzzleImportException(
          'No drillable puzzles in that collection');
    }

    final title = (collection['name'] as String?)?.trim();
    return OgsPuzzleCollection(
      title: (title == null || title.isEmpty) ? 'OGS Puzzles' : title,
      sgfs: sgfs,
    );
  } on OgsPuzzleImportException {
    rethrow;
  } catch (e) {
    _log.warning('OGS puzzle collection import failed: $e');
    throw OgsPuzzleImportException('$e');
  } finally {
    if (ownClient) c.close();
  }
}

Future<Map<String, dynamic>> _getJson(http.Client client, Uri uri) async {
  final decoded = await _getDynamic(client, uri);
  return decoded as Map<String, dynamic>;
}

Future<dynamic> _getDynamic(http.Client client, Uri uri) async {
  final response = await client.get(uri, headers: {'User-Agent': _userAgent});
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw OgsPuzzleImportException('HTTP ${response.statusCode}');
  }
  return jsonDecode(response.body);
}

/// The collection's "puzzles" endpoint returns a plain JSON array with no
/// pagination for every collection this was tested against, but a
/// DRF-style `{results, next}` page is handled too, just in case.
Future<List<Map<String, dynamic>>> _fetchAllPuzzles(
  http.Client client,
  String origin,
  String collectionId,
) async {
  final out = <Map<String, dynamic>>[];
  Uri? next = Uri.parse('$origin/api/v1/puzzles/collections/$collectionId/puzzles')
      .replace(queryParameters: {'page_size': '1000'});
  while (next != null) {
    final decoded = await _getDynamic(client, next);
    if (decoded is List) {
      out.addAll(decoded.cast<Map<String, dynamic>>());
      next = null;
    } else if (decoded is Map<String, dynamic>) {
      final results = decoded['results'];
      if (results is List) out.addAll(results.cast<Map<String, dynamic>>());
      final nextUrl = decoded['next'] as String?;
      next = nextUrl == null ? null : Uri.parse(nextUrl);
    } else {
      next = null;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// OGS puzzle JSON -> SGF text
// ---------------------------------------------------------------------------

/// Converts one entry from the collection's "puzzles" list (or from
/// `/api/v1/puzzles/<id>`) into an SGF document shaped like
/// ogs-puzzle-exporter's output, or `null` if it has no moves at all.
String? sgfFromOgsPuzzleJson(Map<String, dynamic> entry) {
  final puzzle = entry['puzzle'];
  if (puzzle is! Map<String, dynamic>) return null;

  final rawWidth = puzzle['width'];
  final boardSize =
      rawWidth is int ? rawWidth : int.tryParse('$rawWidth') ?? 19;

  final initialState = puzzle['initial_state'];
  final blackPoints = _pointsFromOgsState(
      initialState is Map ? initialState['black'] as String? : null);
  final whitePoints = _pointsFromOgsState(
      initialState is Map ? initialState['white'] as String? : null);
  final firstColor = puzzle['initial_player'] == 'white' ? 'W' : 'B';

  final moveTree = puzzle['move_tree'];
  final rootBranches =
      (moveTree is Map ? moveTree['branches'] as List? : null) ?? const [];
  if (rootBranches.isEmpty) return null;

  final name = ((entry['name'] ?? puzzle['name']) as String?)?.trim();
  final rootText = moveTree is Map ? moveTree['text'] as String? : null;
  final description = (puzzle['puzzle_description'] as String?)?.trim();
  final rootComment = (rootText != null && rootText.trim().isNotEmpty)
      ? rootText.trim()
      : (description != null && description.isNotEmpty ? description : null);

  final buf = StringBuffer('(;FF[4]CA[UTF-8]GM[1]');
  if (name != null && name.isNotEmpty) buf.write('GN[${_escapeSgf(name)}]');
  buf.write('SZ[$boardSize]');
  if (blackPoints.isNotEmpty) {
    buf.write('AB');
    for (final p in blackPoints) {
      buf.write('[${p.toSgf()}]');
    }
  }
  if (whitePoints.isNotEmpty) {
    buf.write('AW');
    for (final p in whitePoints) {
      buf.write('[${p.toSgf()}]');
    }
  }
  buf.write('PL[$firstColor]');
  if (rootComment != null) buf.write('C[${_escapeSgf(rootComment)}]');
  _writeOgsMoves(buf, rootBranches, firstColor);
  buf.write(')');
  return buf.toString();
}

/// OGS's `initial_state.black`/`.white` are simply concatenated SGF-style
/// point letters (e.g. `"ddcf"` == the two points `dd`, `cf`), same as the
/// exporter's `AB`/`AW` values.
List<wq.Point> _pointsFromOgsState(String? state) {
  if (state == null) return const [];
  final out = <wq.Point>[];
  for (var i = 0; i + 1 < state.length; i += 2) {
    out.add(wq.parseSgfPoint(state.substring(i, i + 2)));
  }
  return out;
}

void _writeOgsMoves(StringBuffer buf, List<dynamic> branches, String color) {
  if (branches.isEmpty) return;
  if (branches.length == 1) {
    _writeOgsMove(buf, branches.first as Map<String, dynamic>, color);
    return;
  }
  for (final branch in branches) {
    buf.write('(');
    _writeOgsMove(buf, branch as Map<String, dynamic>, color);
    buf.write(')');
  }
}

/// A move_tree node's `x`/`y` are 0-indexed column/row, the same coordinate
/// system as SGF points.
void _writeOgsMove(StringBuffer buf, Map<String, dynamic> node, String color) {
  final x = node['x'];
  final y = node['y'];
  if (x is! int || y is! int) return;
  buf.write(';$color[${(y, x).toSgf()}]');

  var comment = (node['text'] as String?)?.trim();
  if (comment != null && comment.isEmpty) comment = null;
  if (node['correct_answer'] == true) {
    comment = comment == null ? 'CORRECT' : '$comment\nCORRECT';
  }
  if (comment != null) buf.write('C[${_escapeSgf(comment)}]');

  final children = node['branches'] as List? ?? const [];
  _writeOgsMoves(buf, children, color == 'B' ? 'W' : 'B');
}

String _escapeSgf(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll(']', '\\]');
