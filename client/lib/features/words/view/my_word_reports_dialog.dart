import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/features/words/cubit/my_word_reports_cubit.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';

/// «پیشنهادهای من»: the player's reports and what became of each.
Future<void> showMyWordReportsDialog(BuildContext context) => showZDialog<void>(
  context,
  builder:
      (_) => BlocProvider(
        create:
            (_) =>
                MyWordReportsCubit(getIt<WordSuggestionsRepository>())..load(),
        child: const _MyWordReportsDialog(),
      ),
);

/// Persian status of a report: «بررسی نشده» / «اضافه شد» / «رد شد» …
String wordReportStatusLabel(MyWordReport r) {
  switch (r.status) {
    case 'approved':
      if (r.isAdd) return 'اضافه شد';
      return r.outcome == 'ai_block' ? 'برای هوش مصنوعی مسدود شد' : 'حذف شد';
    case 'rejected':
      return 'رد شد';
    default:
      return 'در انتظار بررسی';
  }
}

class _MyWordReportsDialog extends StatelessWidget {
  const _MyWordReportsDialog();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ZDialogCard(
      semanticLabel: 'پیشنهادهای من',
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'پیشنهادهای من',
              textAlign: TextAlign.center,
              style: ZTypography.screenTitle.copyWith(
                fontSize: 22,
                color: z.ink,
              ),
            ),
            const SizedBox(height: 12),
            BlocBuilder<MyWordReportsCubit, MyWordReportsState>(
              builder: (context, state) {
                switch (state.status) {
                  case MyWordReportsStatus.loading:
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: ZLoadState.loading(),
                    );
                  case MyWordReportsStatus.failed:
                    return ZLoadState.error(
                      message: state.message ?? genericErrorMessage,
                      onRetry: () => context.read<MyWordReportsCubit>().load(),
                    );
                  case MyWordReportsStatus.loaded:
                    if (state.items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'هنوز کلمه‌ای نفرستاده‌ای.',
                          textAlign: TextAlign.center,
                          style: ZTypography.body.copyWith(color: z.ink60),
                        ),
                      );
                    }
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: state.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder:
                            (context, i) => _ReportRow(report: state.items[i]),
                      ),
                    );
                }
              },
            ),
            const SizedBox(height: 14),
            ZDialogButton.secondary(
              label: 'بستن',
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final MyWordReport report;

  const _ReportRow({required this.report});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final approved = report.status == 'approved';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: z.wash,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              report.word,
              style: ZTypography.cardTitle.copyWith(fontSize: 16, color: z.ink),
            ),
          ),
          Text(
            [
              if (!report.isAdd) 'گزارش حذف · ',
              wordReportStatusLabel(report),
              if (report.rewarded) ' · سکه در جوایز',
            ].join(),
            style: ZTypography.metaLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: approved ? z.teal : z.ink60,
            ),
          ),
        ],
      ),
    );
  }
}
