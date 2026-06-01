import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_theme.dart';

class GameScreen extends StatelessWidget {
  final String id;

  const GameScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Game',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: const Center(
        child: Text(
          'Game Screen — Phase 2',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
