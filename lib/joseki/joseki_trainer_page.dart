import 'dart:math';

import 'package:flutter/material.dart';
import 'package:wqhub/board/board.dart';
import 'package:wqhub/board/board_settings.dart';
import 'package:wqhub/board/coordinate_style.dart';
import 'package:wqhub/joseki/joseki.dart';
import 'package:wqhub/l10n/app_localizations.dart';
import 'package:wqhub/settings/shared_preferences_inherited_widget.dart';
import 'package:wqhub/symmetry.dart';
import 'package:wqhub/train/task.dart';
import 'package:wqhub/train/task_action_bar.dart';
import 'package:wqhub/train/task_solving_state_mixin.dart';
import 'package:wqhub/train/upsolve_mode.dart';
import 'package:wqhub/train/variation_tree.dart';
import 'package:wqhub/turn_icon.dart';
import 'package:wqhub/wq/wq.dart' as wq;

class JosekiTrainerRouteArguments {
  final List<Joseki> josekis;
  final int index;

  const JosekiTrainerRouteArguments(
      {required this.josekis, required this.index});
}

class JosekiTrainerPage extends StatefulWidget {
  static const routeName = '/joseki/train';

  final List<Joseki> josekis;
  final int index;

  const JosekiTrainerPage(
      {super.key, required this.josekis, required this.index});

  @override
  State<JosekiTrainerPage> createState() => _JosekiTrainerPageState();
}

class _JosekiTrainerPageState extends State<JosekiTrainerPage>
    with TaskSolvingStateMixin {
  final _random = Random();
  late int _index = widget.index;
  Task? _task;
  Symmetry _symmetry = Symmetry.identity;
  Map<String, String> _comments = const {};

  Joseki get _joseki => widget.josekis[_index];

  @override
  Task get currentTask => _task ??= _buildTask();

  Task _buildTask() {
    var task = _joseki.toTask(_index);
    final settings = context.settings;

    // Which seat does the learner take?
    final playAs = settings.josekiRandomizeSide
        ? (_random.nextBool() ? wq.Color.black : wq.Color.white)
        : (settings.alwaysBlackToPlay ? wq.Color.black : task.first);
    if (task.first != playAs) task = task.withSwappedColors();

    // Orientation. The commentary is re-keyed through the same symmetry so it
    // still lines up with the moves played.
    _symmetry = settings.josekiRandomizeOrientation
        ? Symmetry.values[_random.nextInt(Symmetry.values.length)]
        : Symmetry.identity;
    task = task.withSymmetry(_symmetry);
    _comments = _joseki.commentsWithSymmetry(_symmetry, task.boardSize);

    return task;
  }

  void _goToJoseki(int index) {
    setState(() {
      _index = index;
      _task = _buildTask();
      solveStatus = null;
      setupCurrentTask();
    });
  }

  bool get _hasNext => _index < widget.josekis.length - 1;

  bool get _isFavorite => context.settings.isJosekiFavorite(_joseki.id);

  void _toggleFavorite() {
    setState(() {
      context.settings.setJosekiFavorite(_joseki.id, !_isFavorite);
    });
  }

  String? get _progressLabel => widget.josekis.length > 1
      ? '${_index + 1}/${widget.josekis.length}'
      : null;

  Widget _favoriteButton() => IconButton(
        icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
        color: _isFavorite ? Colors.amber : null,
        tooltip: AppLocalizations.of(context)!.favorites,
        onPressed: _toggleFavorite,
      );

  bool get _canUndo => gameTree.curNode.parent != null;

  /// Takes back the learner's last move (and the opponent's reply) so the
  /// position is live again. Works during normal practice, not just try mode.
  void _undoMove() {
    if (!_canUndo) return;
    final wasFinished = solveStatus != null;
    onPreviousMove();
    if (turn != currentTask.first && _canUndo) onPreviousMove();
    if (wasFinished) {
      setState(() {
        solveStatus = null;
        solveStatusNotified = false;
      });
    }
  }

  Widget _undoButton() => IconButton(
        icon: const Icon(Icons.undo),
        tooltip: AppLocalizations.of(context)!.taskUndoMove,
        onPressed: _canUndo ? _undoMove : null,
      );

  /// Concatenated SGF points from the first joseki move to the current node -
  /// the key into [Joseki.comments].
  String _commentKey() {
    final moves = <String>[];
    for (var n = gameTree.curNode; n.parent != null; n = n.parent!) {
      final mv = n.move;
      if (mv != null) moves.add(mv.p.toSgf());
    }
    return moves.reversed.join();
  }

  /// Commentary for the current position, or the closest commented ancestor.
  String? _currentComment() {
    var key = _commentKey();
    while (true) {
      final c = _comments[key];
      if (c != null) return c;
      if (key.isEmpty) return null;
      key = key.substring(0, key.length - 2);
    }
  }

  @override
  void onSolveStatus(VariationStatus status) {
    setState(() {});
  }

  @override
  void onResetTask() {
    setState(() {
      solveStatus = null;
      setupCurrentTask();
    });
  }

  @override
  void notifySolveStatus(VariationStatus status, bool wideLayout) {
    final loc = AppLocalizations.of(context)!;
    final correct = status == VariationStatus.correct;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 16,
        children: [
          Icon(correct ? Icons.check_circle : Icons.cancel),
          Text(correct ? loc.josekiComplete : loc.taskWrong,
              style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
      behavior: wideLayout ? SnackBarBehavior.floating : SnackBarBehavior.fixed,
      duration: const Duration(seconds: 1),
      backgroundColor: correct ? Colors.green : Colors.red,
      showCloseIcon: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final wideLayout = MediaQuery.sizeOf(context).aspectRatio > 1.5;
    final task = currentTask;

    final borderSize =
        1.5 * (Theme.of(context).textTheme.labelMedium?.fontSize ?? 0);
    final border = context.settings.showCoordinates
        ? BoardBorderSettings(
            size: borderSize,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            rowCoordinates: CoordinateStyle(
              labels: CoordinateLabels.numbers,
              reverse: true,
            ),
            columnCoordinates: CoordinateStyle(
              labels: CoordinateLabels.alphaNoI,
            ),
          )
        : null;

    final boardSettings = BoardSettings(
      size: task.boardSize,
      subBoard: task.subBoardSize >= task.boardSize
          ? null
          : SubBoard(topLeft: task.topLeft, size: task.subBoardSize),
      theme: context.settings.boardTheme,
      edgeLine: context.settings.edgeLine,
      border: border,
      stoneShadows: context.settings.stoneShadows,
    );

    // The board is a visual grid with no useful screen-reader representation;
    // excluding it from semantics also avoids a Windows a11y-bridge bug that
    // trips on the ~360 nodes a full-board render adds ("Nodes left pending").
    final board = ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide -
              2 * (boardSettings.border?.size ?? 0);
          return Board(
            size: size,
            settings: boardSettings,
            onPointClicked: (p) => onMove(p, wideLayout),
            turn: turn,
            stones: gameTree.stones,
            annotations: continuationAnnotations ?? gameTree.annotations,
            confirmTap: context.settings.confirmMoves,
          );
        },
      ),
    );

    final actionBar = TaskActionBar(
      upsolveMode: upsolveMode,
      onShowSolution: onShowContinuations,
      onCopySgf: onCopySgf,
      onResetTask: onResetTask,
      onNextTask: _hasNext ? () => _goToJoseki(_index + 1) : null,
      onPreviousMove: onPreviousMove,
      onNextMove: onNextMove,
      onUpdateUpsolveMode: onUpdateUpsolveMode,
    );

    if (wideLayout) {
      return Scaffold(
        body: Row(
          children: [
            Expanded(child: Center(child: board)),
            const VerticalDivider(thickness: 1, width: 8),
            _SideBar(
              title: _joseki.title,
              progress: _progressLabel,
              color: task.first,
              comment: _currentComment(),
              favorite: _isFavorite,
              onToggleFavorite: _toggleFavorite,
              solved: solveStatus == VariationStatus.correct,
              onNextJoseki: _hasNext ? () => _goToJoseki(_index + 1) : null,
              undoButton: _undoButton(),
              actionBar: actionBar,
            ),
          ],
        ),
      );
    }

    final comment = _currentComment();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          spacing: 8,
          children: [
            TurnIcon(color: task.first),
            Expanded(
              child: Text(_joseki.title, maxLines: 2, overflow: TextOverflow.fade),
            ),
            if (_progressLabel != null)
              Text(_progressLabel!,
                  style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        actions: [_undoButton(), _favoriteButton()],
      ),
      body: Column(
        children: [
          Expanded(child: Center(child: board)),
          if (solveStatus == VariationStatus.correct && _hasNext)
            Padding(
              padding: const EdgeInsets.all(8),
              child: FilledButton.icon(
                icon: const Icon(Icons.navigate_next),
                label: Text(loc.josekiNext),
                onPressed: () => _goToJoseki(_index + 1),
              ),
            ),
          if (comment != null)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 150),
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Text(comment,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        height: upsolveMode == UpsolveMode.auto ? 80.0 : 160.0,
        child: actionBar,
      ),
    );
  }
}

class _SideBar extends StatelessWidget {
  final String title;
  final String? progress;
  final wq.Color color;
  final String? comment;
  final bool favorite;
  final void Function() onToggleFavorite;
  final bool solved;
  final void Function()? onNextJoseki;
  final Widget undoButton;
  final Widget actionBar;

  const _SideBar({
    required this.title,
    required this.progress,
    required this.color,
    required this.comment,
    required this.favorite,
    required this.onToggleFavorite,
    required this.solved,
    required this.onNextJoseki,
    required this.undoButton,
    required this.actionBar,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final widgetSize = MediaQuery.sizeOf(context);
    final sidebarSize = min(
        widgetSize.longestSide - widgetSize.shortestSide, widgetSize.width / 3);
    return SizedBox(
      width: sidebarSize,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                TurnIcon(color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(title)),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(progress!,
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                IconButton(
                  icon: Icon(favorite ? Icons.star : Icons.star_border),
                  color: favorite ? Colors.amber : null,
                  tooltip: loc.favorites,
                  onPressed: onToggleFavorite,
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  comment ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            if (solved && onNextJoseki != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.navigate_next),
                  label: Text(loc.josekiNext),
                  onPressed: onNextJoseki,
                ),
              ),
            Align(alignment: Alignment.centerLeft, child: undoButton),
            actionBar,
          ],
        ),
      ),
    );
  }
}
