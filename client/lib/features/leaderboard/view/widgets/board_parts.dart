import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';

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

/// The player's own subtitle under «تو — name». Everything here is derived
/// from the rank/score the server returned — no deltas, no league.
String selfSubtitle(BoardTab tab, int rank, int? score) {
  const play = 'یک بازی آنلاین بازی کن';
  switch (tab) {
    case BoardTab.daily:
      return rank <= 0
          ? 'امروز هنوز چالش روزانه را بازی نکرده‌ای'
          : rank <= 10
          ? 'جزو ده نفر برتر امروز!'
          : '${toPersianDigits(rank - 10)} پله تا ده‌تای اول';
    case BoardTab.friends:
      if (rank <= 0 || (score ?? 0) == 0) {
        return 'این هفته امتیازی نداری — $play';
      }
      return rank == 1
          ? 'بین دوستانت اولی!'
          : 'بین دوستانت نفر ${toPersianDigits(rank)}';
    case BoardTab.weekly:
    case BoardTab.allTime:
      if (rank <= 0) {
        return tab == BoardTab.weekly
            ? 'این هفته امتیازی نداری — $play'
            : 'هنوز امتیازی نداری — $play';
      }
      return rank <= 10
          ? 'جزو ده نفر برتری!'
          : '${toPersianDigits(rank - 10)} پله تا ده‌تای اول';
  }
}
