import 'package:flutter/material.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_note.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_parts.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_podium.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_rows.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_self_row.dart';

/// A loaded, non-empty board: the note, the podium (three or more players),
/// the ranked list under it and the player's own row pinned below. Shared by
/// the leaderboard tab and the Daily Challenge's pushed «جدول امروز» screen.
class BoardResultView extends StatelessWidget {
  final BoardTab tab;
  final LeaderboardResult result;
  final String currentUserId;
  final String username;
  final String? selfAvatarId;
  final DateTime now;

  /// Lines appended to the [BoardNote] (the daily screen adds its
  /// participation prize).
  final List<String> extraNoteLines;

  const BoardResultView({
    super.key,
    required this.tab,
    required this.result,
    required this.currentUserId,
    required this.username,
    required this.selfAvatarId,
    required this.now,
    this.extraNoteLines = const [],
  });

  @override
  Widget build(BuildContext context) {
    final entries = result.entries;
    final hasPodium = entries.length >= 3;
    final rest = hasPodium ? entries.sublist(3) : entries;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              BoardNote(
                tab: tab,
                now: now,
                dayNumber: result.dayNumber,
                extraLines: extraNoteLines,
              ),
              if (hasPodium)
                BoardPodium(
                  top3: entries.take(3).toList(),
                  currentUserId: currentUserId,
                ),
              if (hasPodium && rest.isEmpty)
                // Nothing under the pedestals: close them with the card's rim.
                const SizedBox(height: 4)
              else if (rest.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: hasPodium ? 0 : 12),
                  child: BoardRowsCard(
                    entries: rest,
                    currentUserId: currentUserId,
                    underPodium: hasPodium,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: BoardSelfRow(
            username: username,
            avatarId: result.playerAvatarId ?? selfAvatarId,
            rank: result.playerRank,
            score: result.playerScore,
            subtitle: selfSubtitle(tab, result.playerRank, result.playerScore),
          ),
        ),
      ],
    );
  }
}
