import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';

/// Wraps a name in a bidi isolate so a Latin username can't reorder the
/// Persian around it (semantics labels).
String isolate(String name) => '\u2068$name\u2069';

/// A list-row avatar: a disc with the initial (or the premium avatar image),
/// its colour cycling through the four accents the way the canvas hues rows.
class BoardDisc extends StatelessWidget {
  final String name;
  final int index;
  final double size;
  final String? avatarId;

  const BoardDisc({
    super.key,
    required this.name,
    required this.index,
    required this.size,
    this.avatarId,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (fill, on) = switch (index % 4) {
      0 => (z.coral, context.zs.onCoralSm),
      1 => (z.teal, z.onTeal),
      2 => (z.amber, z.onAmber),
      _ => (z.indigo, z.onIndigo),
    };
    return ExcludeSemantics(
      child: ZDiscAvatar(
        fill: fill,
        onFill: on,
        letter: avatarInitial(name, fallback: '؟'),
        size: size,
        avatarId: avatarId,
      ),
    );
  }
}

/// A board's score as text. The weekly board counts the week's net «جام»
/// (signed, can be negative); the all-time and friends boards the rating; the
/// Daily board its word points.
String boardScoreText(BoardTab tab, int score) =>
    tab == BoardTab.weekly
        ? formatSignedPersianNumber(score)
        : formatPersianNumber(score);

/// What [boardScoreText] counts, for screen readers.
String boardScoreUnit(BoardTab tab) => tab == BoardTab.daily ? 'امتیاز' : 'جام';

/// «+۱۶ جام» — the whole spoken score of a row.
String boardScoreSpoken(BoardTab tab, int score) =>
    '${boardScoreText(tab, score)} ${boardScoreUnit(tab)}';

/// The score number of a row. The signed weekly value is laid out
/// left-to-right so the «+» / «−» stays on its left inside an RTL row.
class BoardScoreText extends StatelessWidget {
  final BoardTab tab;
  final int score;
  final TextStyle? style;

  const BoardScoreText({
    super.key,
    required this.tab,
    required this.score,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(boardScoreText(tab, score), style: style);
    return tab == BoardTab.weekly
        ? Directionality(textDirection: TextDirection.ltr, child: text)
        : text;
  }
}

/// The sub-line of a row under the name: the Daily chain, or the games (and,
/// this week, wins) behind the rating. Null when the server sent none.
String? boardRowSub(BoardTab tab, LeaderboardEntry e) {
  if (tab == BoardTab.daily) {
    final chain = e.chainLength;
    return chain == null ? null : 'زنجیر ${toPersianDigits(chain)} کلمه';
  }
  final games = e.games;
  if (games == null) return null;
  final played = '${toPersianDigits(games)} بازی';
  final wins = e.wins;
  return tab == BoardTab.weekly && wins != null
      ? '$played · ${toPersianDigits(wins)} برد'
      : played;
}

/// The player's own subtitle under «تو — name». Everything here is derived
/// from the rank, score and games the server returned — no deltas, no league.
///
/// [games] is the player's rated games on this board (`player_games`).
String selfSubtitle(BoardTab tab, int rank, int? score, {int? games}) {
  const play = 'یه بازی آنلاین بزن';
  switch (tab) {
    case BoardTab.daily:
      return rank <= 0
          ? 'امروز هنوز چالش روزانه رو بازی نکردی'
          : rank <= 10
          ? 'جزو ده نفر برتر امروز!'
          : '${toPersianDigits(rank - 10)} پله تا ده‌تای اول';
    case BoardTab.friends:
      if (rank <= 0) return 'هنوز بازی آنلاین نکردی. $play';
      return rank == 1
          ? 'بین دوستانت اولی!'
          : 'بین دوستانت نفر ${toPersianDigits(rank)}';
    case BoardTab.weekly:
      if (rank <= 0) return 'این هفته بازی آنلاین نکردی. $play';
      // The weekly prize needs a few games and a positive week.
      final left = GameConstants.weeklyMinRatedGames - (games ?? 0);
      if (left > 0) {
        return 'برای جایزه ${toPersianDigits(left)} بازی دیگه لازمه';
      }
      if ((score ?? 0) <= 0) return 'برای جایزه، جام این هفته‌ات باید مثبت بشه';
      return rank <= 10
          ? 'جزو ده نفر برتری!'
          : '${toPersianDigits(rank - 10)} پله تا ده‌تای اول';
    case BoardTab.allTime:
      if (rank <= 0) {
        // Below ten rated games the rating is shown but not ranked yet.
        final played = games ?? 0;
        return played < GameConstants.ratingMinGamesForBoard
            ? 'بعد از ${toPersianDigits(GameConstants.ratingMinGamesForBoard)} '
                'بازی رتبه می‌گیری. تا الان ${toPersianDigits(played)} بازی کردی.'
            : 'هنوز رتبه نداری. $play';
      }
      return rank <= 10
          ? 'جزو ده نفر برتری!'
          : '${toPersianDigits(rank - 10)} پله تا ده‌تای اول';
  }
}
