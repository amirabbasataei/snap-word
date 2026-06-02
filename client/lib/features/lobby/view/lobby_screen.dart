import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/lobby/cubit/lobby_cubit.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LobbyCubit(
        repo: getIt(),
        syncService: getIt(),
        notificationService: getIt(),
      ),
      child: const _LobbyView(),
    );
  }
}

class _LobbyView extends StatefulWidget {
  const _LobbyView();

  @override
  State<_LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends State<_LobbyView> {
  String _selectedMode = 'classic';

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LobbyCubit, LobbyState>(
      listener: (context, state) {
        if (state is LobbyMatchFound) {
          _navigateToGame(context, state);
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              'Find Match',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            iconTheme: const IconThemeData(color: AppColors.textPrimary),
          ),
          body: SafeArea(
            child: switch (state) {
              LobbySearching() => _SearchingView(state: state),
              LobbyError() => _ErrorView(
                  message: state.message,
                  selectedMode: _selectedMode,
                ),
              _ => _IdleView(
                  selectedMode: _selectedMode,
                  onModeChanged: (mode) => setState(() => _selectedMode = mode),
                ),
            },
          ),
        );
      },
    );
  }

  void _navigateToGame(BuildContext context, LobbyMatchFound state) {
    final authState = getIt<AuthCubit>().state;
    final myPlayerId = authState is AuthAuthenticated ? authState.userId : '';

    context.pushReplacement(
      '/game',
      extra: GameRouteArgs(
        mode: state.mode,
        opponentType: 'multiplayer',
        roomId: state.roomId,
        myPlayerId: myPlayerId,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Idle — mode selector + Find Match button
// ---------------------------------------------------------------------------

class _IdleView extends StatelessWidget {
  final String selectedMode;
  final void Function(String) onModeChanged;

  const _IdleView({
    required this.selectedMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Game Mode',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          _ModeCard(
            mode: 'classic',
            title: 'Classic',
            subtitle: '15s turn timer · first mistake loses',
            icon: Icons.timer_outlined,
            selected: selectedMode == 'classic',
            onTap: () => onModeChanged('classic'),
          ),
          const SizedBox(height: 10),
          _ModeCard(
            mode: 'time_attack',
            title: 'Time Attack',
            subtitle: '8s turns · 90s match · highest score wins',
            icon: Icons.bolt_outlined,
            selected: selectedMode == 'time_attack',
            onTap: () => onModeChanged('time_attack'),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () =>
                  context.read<LobbyCubit>().startSearch(selectedMode),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Find Match'),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Matchmaking pairs you with a live opponent.\nAI fallback activates after 30 seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String mode;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? AppColors.primary : AppColors.textSecondary,
              size: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Searching — animated pulse + elapsed time + cancel
// ---------------------------------------------------------------------------

class _SearchingView extends StatefulWidget {
  final LobbySearching state;

  const _SearchingView({required this.state});

  @override
  State<_SearchingView> createState() => _SearchingViewState();
}

class _SearchingViewState extends State<_SearchingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.8, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _elapsed {
    final s = widget.state.elapsedSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final modeLabel = widget.state.mode == 'time_attack' ? 'TIME ATTACK' : 'CLASSIC';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _pulse,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: const Icon(
                  Icons.people_outline,
                  size: 52,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Searching for opponent…',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              modeLabel,
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            _DotProgressIndicator(elapsedSeconds: widget.state.elapsedSeconds),
            const SizedBox(height: 4),
            Text(
              _elapsed,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 40),
            OutlinedButton(
              onPressed: () => context.read<LobbyCubit>().cancelSearch(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotProgressIndicator extends StatefulWidget {
  final int elapsedSeconds;

  const _DotProgressIndicator({required this.elapsedSeconds});

  @override
  State<_DotProgressIndicator> createState() => _DotProgressIndicatorState();
}

class _DotProgressIndicatorState extends State<_DotProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = math.sin((t - i / 3) * math.pi * 2);
            final opacity = ((phase + 1) / 2).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: opacity),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String message;
  final String selectedMode;

  const _ErrorView({required this.message, required this.selectedMode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 56),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () =>
                  context.read<LobbyCubit>().startSearch(selectedMode),
              child: const Text('Try Again'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}
