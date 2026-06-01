import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_theme.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Daily Challenge',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: const Center(
        child: Text(
          'Daily Challenge — Phase 15',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
