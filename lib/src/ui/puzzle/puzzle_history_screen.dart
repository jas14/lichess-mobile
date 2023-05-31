import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_providers.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_service.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:lichess_mobile/src/styles/lichess_colors.dart';
import 'package:lichess_mobile/src/ui/puzzle/puzzle_screen.dart';
import 'package:lichess_mobile/src/utils/chessground_compat.dart' as cg;
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/board_preview.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/shimmer.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';

final _puzzleLoadingProvider = StateProvider<bool>((ref) => false);

class PuzzleHistoryWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(puzzleHistoryProvider);
    return historyState.when(
      data: (data) {
        final crossAxisCount =
            MediaQuery.of(context).size.width > kTabletThreshold ? 4 : 2;
        final boardWidth = (defaultTargetPlatform == TargetPlatform.iOS)
            ? (MediaQuery.of(context).size.width) * 0.91 / crossAxisCount
            : MediaQuery.of(context).size.width / crossAxisCount;
        return ListSection(
          header: Text(context.l10n.puzzleHistory),
          headerTrailing: NoPaddingTextButton(
            onPressed: () => pushPlatformRoute(
              context,
              builder: (context) => PuzzleHistoryScreen(data.historyList),
            ),
            child: Text(
              context.l10n.more,
            ),
          ),
          children: [
            for (var i = 0; i < data.historyList.length; i += crossAxisCount)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: data.historyList
                    .getRange(
                      i,
                      i + crossAxisCount <= data.historyList.length
                          ? i + crossAxisCount
                          : data.historyList.length,
                    )
                    .map(
                      (e) => _HistoryBoard(e, boardWidth),
                    )
                    .toList(),
              ),
          ],
        );
      },
      error: (e, s) {
        debugPrint(
          'SEVERE: [PuzzleHistoryWidget] could not load dashboard',
        );
        return const Center(child: Text('Could not load Puzzle History'));
      },
      loading: () => Shimmer(
        child: ShimmerLoading(
          isLoading: true,
          child: ListSection.loading(
            itemsNumber: 5,
            header: true,
          ),
        ),
      ),
    );
  }
}

class PuzzleHistoryScreen extends StatelessWidget {
  const PuzzleHistoryScreen(this.historyList);

  final IList<PuzzleAndResult> historyList;

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(androidBuilder: _buildAndroid, iosBuilder: _buildIos);
  }

  Widget _buildIos(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(context.l10n.puzzleHistory),
      ),
      child: _Body(historyList),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.puzzleHistory)),
      body: _Body(historyList),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body(this.historyList);
  final IList<PuzzleAndResult> historyList;
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final ScrollController _scrollController = ScrollController();
  List<PuzzleAndResult> _historyList = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _historyList.addAll(widget.historyList);
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        _historyList.length < 500) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });
    final newList = await ref.read(puzzleHistoryProvider.notifier).getNext();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _historyList.addAll(newList);
        _historyList = _historyList.toSet().toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final crossAxisCount =
        MediaQuery.of(context).size.width > kTabletThreshold ? 4 : 2;
    final boardWidth = MediaQuery.of(context).size.width / crossAxisCount;
    return ListView.builder(
      controller: _scrollController,
      itemCount: _historyList.length ~/ crossAxisCount + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isLoading && index == _historyList.length ~/ crossAxisCount) {
          return const CenterLoadingIndicator();
        }
        final rowStartIndex = index * crossAxisCount;
        final rowEndIndex =
            min(rowStartIndex + crossAxisCount, _historyList.length);
        return Row(
          children: _historyList
              .getRange(index * crossAxisCount, rowEndIndex)
              .map(
                (e) => _HistoryBoard(e, boardWidth),
              )
              .toList(),
        );
      },
    );
  }
}

class _HistoryBoard extends ConsumerWidget {
  const _HistoryBoard(this.puzzle, this.boardWidth);

  final PuzzleAndResult puzzle;
  final double boardWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (fen, turn, lastMove) = puzzle.puzzle.preview();
    final isLoading = ref.watch(_puzzleLoadingProvider);
    return SizedBox(
      width: boardWidth,
      height: boardWidth + MediaQuery.of(context).textScaleFactor * 14 + 16.5,
      child: BoardPreview(
        onTap: isLoading
            ? null
            : () async {
                Puzzle? puzzleData;
                ref
                    .read(_puzzleLoadingProvider.notifier)
                    .update((state) => true);
                puzzleData =
                    await ref.read(puzzleProvider(puzzle.puzzle.id).future);
                ref
                    .read(_puzzleLoadingProvider.notifier)
                    .update((state) => false);
                final session = ref.read(authSessionProvider);
                if (context.mounted) {
                  pushPlatformRoute(
                    context,
                    rootNavigator: true,
                    builder: (ctx) => PuzzleScreen(
                      theme: PuzzleTheme.mix,
                      initialPuzzleContext: PuzzleContext(
                        puzzle: puzzleData!,
                        theme: PuzzleTheme.mix,
                        userId: session?.user.id,
                      ),
                    ),
                  );
                }
              },
        orientation: turn.cg,
        fen: fen,
        lastMove: lastMove.cg,
        footer: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              ColoredBox(
                color: puzzle.win ? LichessColors.good : LichessColors.red,
                child: Icon(
                  size: 20,
                  color: Colors.white,
                  (puzzle.win) ? Icons.done : Icons.close,
                ),
              ),
              const SizedBox(width: 8),
              Text(puzzle.puzzle.rating.toString()),
            ],
          ),
        ),
      ),
    );
  }
}
