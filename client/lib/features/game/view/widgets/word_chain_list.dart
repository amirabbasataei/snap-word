import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_theme.dart';

class WordChainList extends StatefulWidget {
  final List<String> words;
  final List<int> scores;
  // Multiplayer: parallel list of player IDs; null entry = unknown/AI
  final List<String?>? wordOwners;
  final String? myPlayerId;
  final String? opponentUsername;

  const WordChainList({
    super.key,
    required this.words,
    required this.scores,
    this.wordOwners,
    this.myPlayerId,
    this.opponentUsername,
  });

  @override
  State<WordChainList> createState() => _WordChainListState();
}

class _WordChainListState extends State<WordChainList> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(WordChainList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.words.length != oldWidget.words.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isMyWord(int index) {
    if (widget.wordOwners == null || widget.myPlayerId == null) return true;
    if (index >= widget.wordOwners!.length) return true;
    return widget.wordOwners![index] == widget.myPlayerId;
  }

  String? _playerLabel(int index) {
    if (widget.wordOwners == null) return null;
    return _isMyWord(index) ? 'You' : (widget.opponentUsername ?? 'Opp');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.words.isEmpty) {
      return const Center(
        child: Text(
          'Type your first word to start!',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: widget.words.length,
      itemBuilder: (context, index) {
        final word = widget.words[index];
        final score = index < widget.scores.length ? widget.scores[index] : null;
        final isLast = index == widget.words.length - 1;
        final isMyWord = _isMyWord(index);
        final playerLabel = _playerLabel(index);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  child: Text(
                    '–',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isLast
                        ? (isMyWord ? AppColors.primary : AppColors.secondary)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: isLast
                        ? null
                        : Border.all(color: AppColors.divider, width: 1),
                  ),
                  child: Text(
                    word.toUpperCase(),
                    style: TextStyle(
                      color: isLast
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (playerLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    playerLabel,
                    style: TextStyle(
                      color: isMyWord
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const Spacer(),
                if (score != null)
                  Text(
                    isLast ? '+$score ✦' : '+$score',
                    style: TextStyle(
                      color: isLast ? AppColors.secondary : AppColors.success,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (!isLast)
              const Padding(
                padding: EdgeInsets.only(left: 20),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        );
      },
    );
  }
}
