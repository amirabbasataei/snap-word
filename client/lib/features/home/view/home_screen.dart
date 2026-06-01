import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/game/view/game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LocalMatche? _activeMatch;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkActiveMatch();
  }

  Future<void> _checkActiveMatch() async {
    final match = await getIt<MatchDao>().getActiveMatch();
    if (mounted) {
      setState(() {
        _activeMatch = match;
        _checked = true;
      });
    }
  }

  void _startSolo(BuildContext context) {
    _showModeSheet(
      context,
      title: 'Solo Game',
      opponentType: 'solo',
    );
  }

  void _startVsAi(BuildContext context) {
    _showDifficultySheet(context);
  }

  void _showModeSheet(
    BuildContext context, {
    required String title,
    required String opponentType,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/game',
                    extra: GameRouteArgs(
                      mode: 'classic',
                      opponentType: opponentType,
                    ),
                  );
                },
                child: const Text('Classic  (15s turn timer)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/game',
                    extra: GameRouteArgs(
                      mode: 'time_attack',
                      opponentType: opponentType,
                    ),
                  );
                },
                child: const Text('Time Attack  (8s • 90s match)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDifficultySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'VS AI — Select Difficulty',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              for (final entry in [
                ('Easy', 'ai_easy', 'Mistakes often, slow response'),
                ('Medium', 'ai_medium', 'Moderate challenge'),
                ('Hard', 'ai_hard', 'Fast & strategic trap words'),
              ]) ...[
                ListTile(
                  tileColor: AppColors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: Text(
                    entry.$1,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  subtitle: Text(
                    entry.$3,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showModeSheet(
                      context,
                      title: 'VS AI — ${entry.$1}',
                      opponentType: entry.$2,
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'WORDCHAIN',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Quick Play',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _QuickPlayCard(
                      icon: Icons.person,
                      label: 'SOLO',
                      subtitle: 'Classic / TA',
                      onTap: () => _startSolo(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickPlayCard(
                      icon: Icons.smart_toy_outlined,
                      label: 'VS AI',
                      subtitle: 'Pick Difficulty',
                      onTap: () => _startVsAi(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickPlayCard(
                      icon: Icons.people_outline,
                      label: '1V1',
                      subtitle: 'Find Match',
                      onTap: () => context.push('/lobby'),
                    ),
                  ),
                ],
              ),

              // Resume card shown when there's an active match
              if (_checked && _activeMatch != null) ...[
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    final match = _activeMatch!;
                    context.push(
                      '/game',
                      extra: GameRouteArgs(
                        mode: match.mode,
                        opponentType: match.opponentType,
                        resumeMatchId: match.id,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.play_circle_outline,
                            color: AppColors.primary, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Resume Game',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                '${_activeMatch!.mode.toUpperCase()} · ${_activeMatch!.opponentType.replaceAll('_', ' ').toUpperCase()}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPlayCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickPlayCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
