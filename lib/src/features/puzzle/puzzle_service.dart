import 'dart:math' show max;
import 'package:logging/logging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart'
    hide Tuple2;

import './data/puzzle_local_db.dart';
import './data/puzzle_repository.dart';
import './model/puzzle.dart';
import './model/puzzle_theme.dart';

final puzzleOfflineServiceProvider = Provider<PuzzleService>((ref) {
  final db = ref.watch(puzzleLocalDbProvider);
  final repository = ref.watch(puzzleRepositoryProvider);
  return PuzzleService(Logger('PuzzleService'), db: db, repository: repository);
});

class PuzzleService {
  const PuzzleService(
    this._log, {
    required this.db,
    required this.repository,
    this.localQueueLength = kPuzzleLocalQueueLength,
  });

  final int localQueueLength;
  final PuzzleLocalDB db;
  final PuzzleRepository repository;
  final Logger _log;

  /// Loads the next puzzle from database. Will sync with server if necessary.
  Future<Puzzle?> nextPuzzle(
      {String? userId, PuzzleTheme angle = PuzzleTheme.mix}) async {
    final data = await _syncAndLoadData(userId, angle);
    return data?.unsolved[0];
  }

  /// Update puzzle queue with the solved puzzle and sync with server
  Future<void> solve({
    String? userId,
    PuzzleTheme angle = PuzzleTheme.mix,
    required PuzzleSolution solution,
  }) async {
    final data = db.fetch(userId: userId, angle: angle);
    if (data != null) {
      await db.save(
        userId: userId,
        angle: angle,
        data: PuzzleLocalData(
          solved: IList([...data.solved, solution]),
          unsolved:
              data.unsolved.removeWhere((e) => e.puzzle.id == solution.id),
        ),
      );
      await _syncAndLoadData(userId, angle);
    }
  }

  /// Synchronize offline puzzle queue with server and gets latest data.
  ///
  /// This task will fetch missing puzzles so the queue length is always equal to
  /// `localQueueLength`.
  /// It will also call the `solveBatchTask` with solved puzzles.
  Future<PuzzleLocalData?> _syncAndLoadData(
      String? userId, PuzzleTheme angle) async {
    final data = db.fetch(userId: userId, angle: angle);

    final unsolved = data?.unsolved ?? IList(const []);
    final solved = data?.solved ?? IList(const []);

    final deficit = max(0, localQueueLength - unsolved.length);

    if (deficit > 0) {
      _log.fine('Have a puzzle deficit of $deficit, will sync with lichess');

      final result = await (solved.isNotEmpty
          ? repository.solveBatch(nb: deficit, solved: solved, angle: angle)
          : repository.selectBatch(nb: deficit, angle: angle));

      if (result.isFailure) {
        return data;
      } else {
        final list = result.getOrThrow();
        final newData = PuzzleLocalData(
          solved: IList(const []),
          unsolved: IList([...unsolved, ...list]),
        );
        await db.save(
          userId: userId,
          angle: angle,
          data: newData,
        );
      }
    }

    return data;
  }
}
