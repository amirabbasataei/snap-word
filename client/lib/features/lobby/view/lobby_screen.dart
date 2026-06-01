import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_theme.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Lobby',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: const Center(
        child: Text(
          'Lobby Screen — Phase 13',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
