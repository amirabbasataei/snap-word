import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/core/widgets/z_state_card.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_result_view.dart';

/// «جدول امروز» — today's Daily Challenge ranking, pushed from both daily
/// screens. It is the leaderboard tab's «امروز» board on its own route (back
/// button instead of the dock): the same data (`GET /daily/leaderboard` through
/// `LeaderboardRepository.fetchDaily`) and the same podium / rows / own-row
/// widgets, so there is one daily board, not two renderings of it.
///
/// Prizes are paid at Iran midnight as claimable rewards: everyone who played
/// gets [GameConstants.dailyCompletePrize] coins, the top three more
/// (`BoardNote` lists the latter, this screen adds the former).
class DailyBoardScreen extends StatelessWidget {
  /// Clock for the countdown in the note; tests pass a fixed one.
  final DateTime Function()? clock;

  const DailyBoardScreen({super.key, this.clock});

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthCubit>().state;
    final userId = auth is AuthAuthenticated ? auth.userId : '';
    final username = auth is AuthAuthenticated ? auth.username : '';
    return BlocProvider(
      create:
          (_) => LeaderboardCubit(
            repository: getIt<LeaderboardRepository>(),
            currentUserId: userId,
          )..select(BoardTab.daily),
      child: _DailyBoardView(username: username, clock: clock),
    );
  }
}

class _DailyBoardView extends StatelessWidget {
  final String username;
  final DateTime Function()? clock;

  const _DailyBoardView({required this.username, required this.clock});

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.zs.sky3,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HomeSceneBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      ZGameBackButton(onTap: () => _back(context)),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Center(
                          child: ZRibbonTitle(
                            'جدول امروز',
                            accent: ZDialogAccent.indigo,
                            expand: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10 + 44),
                    ],
                  ),
                ),
                Expanded(
                  child: BlocBuilder<LeaderboardCubit, LeaderboardState>(
                    builder: (context, state) {
                      final cubit = context.read<LeaderboardCubit>();
                      final result = state.boards[BoardTab.daily];
                      if (result == null) {
                        final error = state.errors[BoardTab.daily];
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                          child: ZStateCard(
                            child:
                                error != null
                                    ? ZLoadState.error(
                                      message: error,
                                      onRetry: cubit.load,
                                    )
                                    : const ZLoadState.loading(),
                          ),
                        );
                      }
                      if (result.entries.isEmpty) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                          child: ZStateCard(
                            child: ZEmptyState(
                              mood: ZMascotMood.thinking,
                              title: 'امروز هنوز کسی بازی نکرده',
                              body: 'اولین نفر چالش روزانه باش!',
                              actionLabel: 'بازگشت به چالش',
                              onAction: () => _back(context),
                            ),
                          ),
                        );
                      }
                      return BoardResultView(
                        tab: BoardTab.daily,
                        result: result,
                        currentUserId: state.currentUserId,
                        username: username,
                        selfAvatarId: state.selfAvatarId,
                        now: (clock ?? DateTime.now)(),
                        extraNoteLines: [
                          'همهٔ شرکت‌کننده‌ها ${toPersianDigits(GameConstants.dailyCompletePrize)} سکه می‌گیرند',
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
