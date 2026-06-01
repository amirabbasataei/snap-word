import 'package:share_plus/share_plus.dart';

class DailyChallengeResult {
  final int dayNumber;
  final int score;
  final int chainLength;
  final List<String> wordChain;

  const DailyChallengeResult({
    required this.dayNumber,
    required this.score,
    required this.chainLength,
    required this.wordChain,
  });
}

class ShareService {
  Future<void> shareDaily(DailyChallengeResult result) async {
    final chain = result.wordChain.join(' → ');
    final text = '''WordChain Daily #${result.dayNumber}
Score: ${result.score} | Chain: ${result.chainLength} words
$chain
Play at wordchain.app''';
    await Share.share(text);
  }
}
