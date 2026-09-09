import 'dart:convert';
import 'dart:io';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:wqhub/board/board.dart';
import 'package:wqhub/board/board_settings.dart';
import 'package:wqhub/joseki/joseki.dart';
import 'package:wqhub/joseki/joseki_db.dart';
import 'package:wqhub/joseki/joseki_library.dart';
import 'package:wqhub/joseki/joseki_practice_settings_button.dart';
import 'package:wqhub/joseki/joseki_trainer_page.dart';
import 'package:wqhub/l10n/app_localizations.dart';
import 'package:wqhub/settings/shared_preferences_inherited_widget.dart';
import 'package:wqhub/wq/wq.dart' as wq;

class JosekiListRouteArguments {
  /// `null` opens the favorites view instead of a category.
  final JosekiCategory? category;

  const JosekiListRouteArguments({this.category});
}

class JosekiListPage extends StatefulWidget {
  static const routeName = '/joseki/category';

  final JosekiCategory? category;

  const JosekiListPage({super.key, this.category});

  @override
  State<JosekiListPage> createState() => _JosekiListPageState();
}

class _JosekiListPageState extends State<JosekiListPage> {
  bool get _favoritesMode => widget.category == null;

  /// Category mode only: restrict the grid (and the shuffle button) to the
  /// drills of this category the learner has favorited.
  bool _favoritesOnly = false;

  /// The category, re-resolved from [JosekiLibrary] each build so imports made
  /// on this page (or elsewhere) show up. Bundled categories resolve to the
  /// object passed in.
  JosekiCategory? get _category {
    final c = widget.category;
    if (c == null) return null;
    return JosekiLibrary().categoryById(c.id) ?? c;
  }

  bool get _isUserCategory =>
      widget.category != null && JosekiLibrary().isUserCategory(widget.category!.id);

  List<Joseki> _josekis() {
    if (_favoritesMode) {
      return JosekiDb().josekisByIds(context.settings.favoriteJosekiIds);
    }
    final all = _category!.josekis;
    if (!_favoritesOnly) return all;
    final settings = context.settings;
    return [for (final j in all) if (settings.isJosekiFavorite(j.id)) j];
  }

  Future<void> _importMoreSgfs() async {
    final loc = AppLocalizations.of(context)!;
    final category = _category;
    if (category == null) return;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['sgf', 'json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final sgfs = <(String, String)>[];
    for (final f in picked.files) {
      final bytes =
          f.bytes ?? (f.path != null ? File(f.path!).readAsBytesSync() : null);
      if (bytes == null) continue;
      sgfs.add((f.name, utf8.decode(bytes, allowMalformed: true)));
    }
    if (sgfs.isEmpty) return;

    try {
      final res = await JosekiLibrary().addSgfsToCategory(category.id, sgfs);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(loc.josekiImportResult(res.imported, res.skipped))));
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(loc.josekiImportFailed)));
    }
  }

  void _toggleFavorite(Joseki joseki) {
    final settings = context.settings;
    setState(() {
      settings.setJosekiFavorite(joseki.id, !settings.isJosekiFavorite(joseki.id));
    });
  }

  void _open(List<Joseki> josekis, int index) {
    Navigator.pushNamed(
      context,
      JosekiTrainerPage.routeName,
      arguments: JosekiTrainerRouteArguments(josekis: josekis, index: index),
    );
  }

  void _playShuffled() {
    final shuffled = [..._josekis()]..shuffle();
    if (shuffled.isEmpty) return;
    _open(shuffled, 0);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final josekis = _josekis();
    final title = _favoritesMode ? loc.favorites : _category!.title;

    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 600
        ? 2
        : width < 840
            ? 3
            : 4;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!_favoritesMode)
            IconButton(
              icon: Icon(_favoritesOnly ? Icons.star : Icons.star_outline),
              color: _favoritesOnly ? Colors.amber : null,
              tooltip: loc.josekiShowFavoritesOnly,
              onPressed: () =>
                  setState(() => _favoritesOnly = !_favoritesOnly),
            ),
          if (_isUserCategory)
            IconButton(
              icon: const Icon(Icons.library_add_outlined),
              tooltip: loc.josekiImportFiles,
              onPressed: _importMoreSgfs,
            ),
          const JosekiPracticeSettingsButton(),
        ],
      ),
      body: josekis.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    _isUserCategory && !_favoritesOnly
                        ? loc.josekiImportFiles
                        : loc.josekiNoFavorites,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.82,
              ),
              itemCount: josekis.length,
              itemBuilder: (context, index) => _JosekiTile(
                joseki: josekis[index],
                favorite: context.settings.isJosekiFavorite(josekis[index].id),
                onToggleFavorite: () => _toggleFavorite(josekis[index]),
                onOpen: () => _open(josekis, index),
              ),
            ),
      bottomNavigationBar: josekis.isNotEmpty
          ? BottomAppBar(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.shuffle),
                    label: Text(_favoritesOnly
                        ? loc.josekiPlayFavoritesShuffled
                        : loc.josekiPlayShuffled),
                    onPressed: _playShuffled,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _JosekiTile extends StatelessWidget {
  final Joseki joseki;
  final bool favorite;
  final void Function() onToggleFavorite;
  final void Function() onOpen;

  const _JosekiTile({
    required this.joseki,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final boardSettings = BoardSettings(
      size: joseki.boardSize,
      subBoard: SubBoard(topLeft: joseki.topLeft, size: joseki.subBoardSize),
      theme: context.settings.boardTheme,
      edgeLine: context.settings.edgeLine,
      stoneShadows: context.settings.stoneShadows,
      interactive: false,
    );

    var stones = const IMap<wq.Point, wq.Color>.empty();
    for (final p in joseki.blackStones) {
      stones = stones.add(p, wq.Color.black);
    }
    for (final p in joseki.whiteStones) {
      stones = stones.add(p, wq.Color.white);
    }

    return Column(
      children: [
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: Board(
                    size: constraints.biggest.shortestSide,
                    settings: boardSettings,
                    cursor: SystemMouseCursors.click,
                    turn: null,
                    stones: stones,
                    annotations: const IMapConst({}),
                    confirmTap: false,
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(favorite ? Icons.star : Icons.star_border),
              color: favorite ? Colors.amber : null,
              visualDensity: VisualDensity.compact,
              tooltip: AppLocalizations.of(context)!.favorites,
              onPressed: onToggleFavorite,
            ),
            Expanded(
              child: Text(
                joseki.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
