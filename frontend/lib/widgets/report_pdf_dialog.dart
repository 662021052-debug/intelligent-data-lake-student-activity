import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/report_export.dart';

/// Dialog เลือกรูปแบบก่อนส่งออก PDF — คืน [ReportMode] ที่เลือก หรือ null ถ้ายกเลิก
///
/// แสดงจำนวนแถว/หน้าโดยประมาณของแต่ละรูปแบบตามตัวกรองที่ใช้อยู่ และเตือนก่อนถ้ารูปแบบที่เลือก
/// จะได้ไฟล์ใหญ่ ([counts] เป็น null = ดึงจำนวนไม่ได้ ก็ยังเลือกรูปแบบแล้วออกไฟล์ได้ตามปกติ)
Future<ReportMode?> showReportPdfDialog(
  BuildContext context, {
  required String filterSummary,
  ReportCounts? counts,
}) {
  return showDialog<ReportMode>(
    context: context,
    builder: (_) =>
        ReportPdfDialog(filterSummary: filterSummary, counts: counts),
  );
}

class ReportPdfDialog extends StatefulWidget {
  const ReportPdfDialog({super.key, required this.filterSummary, this.counts});

  final String filterSummary;
  final ReportCounts? counts;

  @override
  State<ReportPdfDialog> createState() => _ReportPdfDialogState();
}

class _ReportPdfDialogState extends State<ReportPdfDialog> {
  /// ค่าเริ่มต้นคือ "สรุปต่อคน" — สั้นกว่าแบบละเอียดราว 5 เท่า
  ReportMode _mode = ReportMode.summary;

  String? _sizeText(ReportMode mode) {
    final counts = widget.counts;
    if (counts == null) return null;
    return '${counts.rowsFor(mode)} แถว · ประมาณ ${counts.pagesFor(mode)} หน้า';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = widget.counts?.warningFor(_mode);

    return AlertDialog(
      icon: Icon(Icons.picture_as_pdf, color: theme.colorScheme.primary),
      title: const Text('ส่งออก PDF'),
      content: SizedBox(
        width: 460,
        // เลื่อนได้ — จอเตี้ย/คำเตือนขึ้นมาแล้วเนื้อหาสูงเกิน dialog จะล้นลงล่างและปุ่มโดนบัง
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ตัวกรอง: ${widget.filterSummary}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              RadioGroup<ReportMode>(
                groupValue: _mode,
                onChanged: (value) => setState(() => _mode = value ?? _mode),
                child: Column(
                  children: [
                    for (final mode in ReportMode.values)
                      RadioListTile<ReportMode>(
                        key: ValueKey('report-mode-${mode.apiValue}'),
                        value: mode,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          mode == ReportMode.summary
                              ? '${mode.label} (แนะนำ)'
                              : mode.label,
                        ),
                        subtitle: Text(
                          [mode.description, ?_sizeText(mode)].join('\n'),
                        ),
                        isThreeLine: true,
                      ),
                  ],
                ),
              ),
              if (warning != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  key: const ValueKey('report-large-warning'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          warning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          key: const ValueKey('report-confirm'),
          onPressed: () => Navigator.pop(context, _mode),
          child: Text(warning != null ? 'ดาวน์โหลดต่อ' : 'ดาวน์โหลด'),
        ),
      ],
    );
  }
}
