import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';

/// How one invitation reads on its card: the title and line of text, the glyph
/// on the coloured disc (the sender's initial, as the canvas draws it) and the
/// words of the two buttons.
class MessageFace {
  final String title;
  final String body;
  final String glyph;
  final ZDialogAccent accent;
  final String acceptLabel;
  final String declineLabel;

  /// What a screen reader says for each button — the visible labels alone
  /// would not say whose invitation they answer.
  final String acceptSemantics;
  final String declineSemantics;

  const MessageFace({
    required this.title,
    required this.body,
    required this.glyph,
    required this.accent,
    required this.acceptLabel,
    required this.declineLabel,
    required this.acceptSemantics,
    required this.declineSemantics,
  });
}

// A username can be Latin; the isolate keeps the Persian around it in order.
String _isolate(String name) => '\u2068$name\u2069';

MessageFace requestFace(PendingRequest r) {
  final name = _isolate(r.username);
  return MessageFace(
    title: 'درخواست دوستی',
    body: '$name می‌خواهد دوست تو شود.',
    glyph: nameInitial(r.username),
    accent: ZDialogAccent.indigo,
    acceptLabel: 'بپذیر',
    declineLabel: 'رد',
    acceptSemantics: 'پذیرفتن درخواست دوستی $name',
    declineSemantics: 'رد درخواست دوستی $name',
  );
}

MessageFace challengeFace(PendingChallenge c) {
  final name = _isolate(c.challengerUsername);
  return MessageFace(
    title: 'دعوت به بازی',
    body: '$name تو را به یک بازی آنلاین دعوت کرده است.',
    glyph: nameInitial(c.challengerUsername),
    accent: ZDialogAccent.coral,
    acceptLabel: 'بازی کن',
    declineLabel: 'رد',
    acceptSemantics: 'پذیرفتن چالش $name',
    declineSemantics: 'رد چالش $name',
  );
}
