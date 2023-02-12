import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:async/async.dart';
import 'package:result_extensions/result_extensions.dart';
import 'package:tuple/tuple.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart'
    hide Tuple2;

import 'package:lichess_mobile/src/common/styles.dart';
import 'package:lichess_mobile/src/common/models.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/async_value.dart';
import 'package:lichess_mobile/src/widgets/adaptive_modal_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/auth/auth_actions_notifier.dart';
import 'package:lichess_mobile/src/model/auth/auth_repository.dart';
import 'package:lichess_mobile/src/model/user/user_repository_providers.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/board/play_preferences.dart';
import 'package:lichess_mobile/src/model/board/computer_opponent.dart';
import 'package:lichess_mobile/src/model/board/play_action_notifier.dart';

import 'time_control_modal.dart';
import 'playable_game_screen.dart';

final maiaBotsProvider =
    FutureProvider.autoDispose<List<Tuple2<User, UserStatus>>>((ref) async {
  final userRepo = ref.watch(userRepositoryProvider);
  final FutureResult<List<User>> maiaBots = Future.wait([
    userRepo.getUser(const UserId('maia1')),
    userRepo.getUser(const UserId('maia5')),
    userRepo.getUser(const UserId('maia9')),
  ]).then(Result.flattenAll);
  final maiaStatuses = userRepo.getUsersStatuses(
    ISet(
      {const UserId('maia1'), const UserId('maia5'), const UserId('maia9')},
    ),
  );
  final result = maiaBots.flatMap(
    (bots) => maiaStatuses.map(
      (statuses) => bots
          .map(
            (bot) => Tuple2<User, UserStatus>(
              bot,
              statuses.firstWhere((s) => s.id == bot.id),
            ),
          )
          .toList(),
    ),
  );
  return result.fold(
    (data) {
      // retry on error, cache indefinitely on success
      ref.keepAlive();
      return data;
    },
    (error, _) => throw error,
  );
});

class PlayScreen extends ConsumerWidget {
  const PlayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConsumerPlatformWidget(
      ref: ref,
      androidBuilder: _androidBuilder,
      iosBuilder: _iosBuilder,
    );
  }

  Widget _androidBuilder(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.play)),
      body: Center(
        child: authState.maybeWhen(
          data: (account) => PlayForm(account: account),
          orElse: () => const CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _iosBuilder(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(context.l10n.play)),
      child: Center(
        child: authState.maybeWhen(
          data: (account) => PlayForm(account: account),
          orElse: () => const CircularProgressIndicator.adaptive(),
        ),
      ),
    );
  }
}

class PlayForm extends ConsumerWidget {
  const PlayForm({this.account, super.key});

  final User? account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maiaBots = ref.watch(maiaBotsProvider);
    final opponentPref = ref.watch(computerOpponentPrefProvider);
    final maiaStrength = ref.watch(maiaStrengthProvider);
    final stockfishLevel = ref.watch(stockfishLevelProvider);
    final timeControlPref = ref.watch(timeControlPrefProvider);
    final authActionsAsync = ref.watch(authActionsProvider);
    final playActionAsync = ref.watch(playActionProvider);

    ref.listen<AsyncValue<PlayableGame?>>(playActionProvider, (_, state) {
      state.showSnackbarOnError(context);

      if (state.valueOrNull is PlayableGame && account != null) {
        ref.invalidate(playActionProvider);
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (context) =>
                PlayableGameScreen(game: state.value!, account: account!),
          ),
        );
      }
    });

    return SafeArea(
      child: ListView(
        padding: Styles.bodyPadding,
        children: [
          Text(
            context.l10n.playWithTheMachine,
            style: Styles.sectionTitle,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          CupertinoSlidingSegmentedControl<ComputerOpponent>(
            onValueChanged: (opponent) {
              if (opponent != null) {
                ref.read(computerOpponentPrefProvider.notifier).set(opponent);
              }
            },
            groupValue: opponentPref,
            children: const {
              ComputerOpponent.maia: Text('Maia'),
              ComputerOpponent.stockfish: Text('Stockfish 14'),
            },
          ),
          const SizedBox(height: 10),
          Builder(
            builder: (BuildContext context) {
              if (opponentPref == ComputerOpponent.maia) {
                return maiaBots.when(
                  data: (bots) {
                    return Column(
                      children: [
                        const Text(
                          'Maia is a human-like neural network chess engine. It was trained by learning from over 10 million Lichess games. It is an ongoing research project aiming to make a more human-friendly, useful, and fun chess AI. For more information go to maiachess.com. ',
                        ),
                        ChoicePicker(
                          notchedTile: true,
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          choices: MaiaStrength.values,
                          selectedItem: maiaStrength,
                          titleBuilder: (ms) => Text(ms.name),
                          subtitleBuilder: (ms) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [Perf.blitz, Perf.rapid, Perf.classical]
                                .map((p) {
                              final bot = bots
                                  .firstWhere(
                                    (b) => b.item1.id.value == ms.name,
                                  )
                                  .item1;
                              return Semantics(
                                label: p.title,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(p.icon, size: 18.0),
                                    const SizedBox(width: 3.0),
                                    Flexible(
                                      child: Text(
                                        bot.perfs[p]!.rating.toString(),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 12.0),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          onSelectedItemChanged: (value) {
                            ref.read(maiaStrengthProvider.notifier).set(value);
                          },
                        ),
                      ],
                    );
                  },
                  error: (err, st) {
                    debugPrint(
                      'SEVERE [PlayScreen] could not load bot info: $err\n$st',
                    );
                    return const Text('Could not load bot ratings.');
                  },
                  loading: () => const CenterLoadingIndicator(),
                );
              }

              int value = stockfishLevel;
              return StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  return Column(
                    children: [
                      const Text(
                        'Stockfish is a strong open source engine, 13-time winner of the Top Chess Engine Championship.',
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(context.l10n.strength),
                          Expanded(
                            child: Slider(
                              value: value.toDouble(),
                              min: 1,
                              max: 8,
                              divisions: 7,
                              label: '${context.l10n.level} $value',
                              semanticFormatterCallback: (double newValue) {
                                return '${context.l10n.level} ${newValue.round()}';
                              },
                              onChanged:
                                  opponentPref != ComputerOpponent.stockfish
                                      ? null
                                      : (double newVal) {
                                          setState(() {
                                            value = newVal.round();
                                          });
                                        },
                              onChangeEnd: (double value) {
                                ref
                                    .read(stockfishLevelProvider.notifier)
                                    .set(value.round());
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            semanticsLabel:
                '${context.l10n.timeControl} ${timeControlPref.perf.title} ${timeControlPref.value.display}',
            onPressed: () {
              showAdaptiveModalBottomSheet<void>(
                useRootNavigator: true,
                context: context,
                builder: (BuildContext context) {
                  return const DefaultGameClockModal();
                },
              );
            },
            textStyle: const TextStyle(fontSize: 18),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 28.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(timeControlPref.perf.icon, size: 20),
                        const SizedBox(width: 5),
                        Text(timeControlPref.value.display)
                      ],
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, size: 28.0),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FatButton(
            semanticsLabel: account == null
                ? 'Sign in to start playing'
                : context.l10n.play,
            onPressed: account == null
                ? authActionsAsync.isLoading
                    ? null
                    : () => ref.read(authActionsProvider.notifier).signIn()
                : playActionAsync.isLoading
                    ? null
                    : () => ref
                        .read(playActionProvider.notifier)
                        .createGame(account: account!),
            child: authActionsAsync.isLoading || playActionAsync.isLoading
                ? const ButtonLoadingIndicator()
                : Text(
                    account == null
                        // TODO translate
                        ? 'Sign in to start playing'
                        : context.l10n.play,
                  ),
          ),
        ],
      ),
    );
  }
}