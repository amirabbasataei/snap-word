import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';

class ContinuePrompt extends StatelessWidget {
  final GameOver state;
  final void Function(String method) onContinue;
  final VoidCallback onAcceptDefeat;

  const ContinuePrompt({
    super.key,
    required this.state,
    required this.onContinue,
    required this.onAcceptDefeat,
  });

  String get _titleText {
    return switch (state.reason) {
      'timeout' => 'Time\'s Up!',
      _ => 'Invalid Word!',
    };
  }

  String get _subtitleText {
    if (state.reason == 'timeout') {
      return 'Your turn timer ran out.\nYour chain of ${state.chainLength} words is at risk.';
    }
    final word = (state.rejectedWord ?? '').toUpperCase();
    return switch (state.rejectionReason) {
      'wrong_letter' =>
        '"$word" doesn\'t start with ${_requiredLetter()}.\nYour chain of ${state.chainLength} words is at risk.',
      'already_used' =>
        '"$word" was already used.\nYour chain of ${state.chainLength} words is at risk.',
      'too_short' => '"$word" is too short (min 3 letters).\nYour chain of ${state.chainLength} words is at risk.',
      _ =>
        '"$word" isn\'t in the dictionary.\nYour chain of ${state.chainLength} words is at risk.',
    };
  }

  String _requiredLetter() {
    if (state.wordChain.isEmpty) return '?';
    final last = state.wordChain.last;
    return last[last.length - 1].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background.withValues(alpha: 0.92),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('💥', style: TextStyle(fontSize: 60)),
              const SizedBox(height: 16),
              Text(
                _titleText,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _subtitleText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'SCORE',
                      value: state.score.toString(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatCard(
                      label: 'WORDS',
                      value: state.chainLength.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'CONTINUE PLAYING?',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => onContinue('ad'),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('WATCH AD — FREE CONTINUE'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.divider, width: 1.5),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => onContinue('coins'),
                icon: const Text('🪙', style: TextStyle(fontSize: 16)),
                label: const Text('SPEND 25 COINS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.background,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (state.continueTimeRemaining > 0)
                Text(
                  '⏱ ${state.continueTimeRemaining} seconds to decide…',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onAcceptDefeat,
                child: const Text(
                  'Accept defeat',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
